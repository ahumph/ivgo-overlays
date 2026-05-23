# tools/now-playing-watch.ps1
#
# Polls the Windows System Media Transport Controls (SMTC) every 2 seconds,
# picks the highest-priority *playing* session (Tidal > any Chromium/Firefox
# tab > nothing), and exposes both the live state and the static overlay
# files over HTTP on http://localhost:7779 so an OBS browser source can
# fetch JSON without hitting CEF's file:// CORS restrictions.
#
# Endpoints:
#   GET /state                       → JSON of the current playing track (or `null`)
#   GET /scenes/09-now-playing.html  → the overlay HTML
#   GET /ivgo-shared.js              → the shared overlay JS
#   GET /<anything-in-repo>          → static-file serves any file under the repo
#
# MUST be run with Windows PowerShell 5.1 (powershell.exe), NOT PowerShell 7+
# (pwsh.exe) — PS7 dropped the WinRT projection used here.
#
# Run with:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\now-playing-watch.ps1
# Then point the OBS browser source at:
#   http://localhost:7779/scenes/09-now-playing.html

[Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType=WindowsRuntime] | Out-Null
Add-Type -AssemblyName System.Runtime.WindowsRuntime

$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() |
  Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
                 $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]

function Await($op, $resultType) {
    $task = $asTaskGeneric.MakeGenericMethod($resultType).Invoke($null, @($op))
    $task.Wait() | Out-Null
    $task.Result
}

$priorities = @{
    'TIDAL.exe'         = 1
    'chrome.exe'        = 2
    'msedge.exe'        = 2
    'firefox.exe'       = 2
    'firefox.exe!App.0' = 2
    'chrome.exe!App.0'  = 2
    'msedge.exe!App.0'  = 2
}

function Get-AumidPriority($aumid) {
    if ($null -eq $aumid) { return $null }
    if ($priorities.ContainsKey($aumid)) { return $priorities[$aumid] }
    $exe = $aumid.Split('!')[0]
    if ($priorities.ContainsKey($exe)) { return $priorities[$exe] }
    return $null
}

function Get-PlayingState {
    $mgr = Await `
        ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) `
        ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])

    $sessions = @($mgr.GetSessions())
    if ($sessions.Count -eq 0) { return $null }

    $playingStatus = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionPlaybackStatus]::Playing
    $candidates = @()
    foreach ($s in $sessions) {
        $info = $s.GetPlaybackInfo()
        if ($info.PlaybackStatus -ne $playingStatus) { continue }
        $prio = Get-AumidPriority $s.SourceAppUserModelId
        if ($null -eq $prio) { continue }
        $candidates += [pscustomobject]@{ Session = $s; Priority = $prio }
    }
    if ($candidates.Count -eq 0) { return $null }

    $chosen = ($candidates | Sort-Object Priority)[0].Session
    $props = Await `
        ($chosen.TryGetMediaPropertiesAsync()) `
        ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])

    return [pscustomobject]@{
        title      = $props.Title
        artist     = $props.Artist
        album      = $props.AlbumTitle
        source     = $chosen.SourceAppUserModelId
        updated_at = (Get-Date).ToUniversalTime().ToString('o')
    }
}

# ── HTTP server ──────────────────────────────────────────────────────────────

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$port = 7779

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Prefixes.Add("http://127.0.0.1:$port/")
$listener.Start()

$contentTypes = @{
    '.html' = 'text/html; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.png'  = 'image/png'
    '.gif'  = 'image/gif'
    '.jpg'  = 'image/jpeg'
    '.jpeg' = 'image/jpeg'
    '.svg'  = 'image/svg+xml'
    '.mp4'  = 'video/mp4'
    '.webm' = 'video/webm'
    '.ico'  = 'image/x-icon'
}

function Serve-Context($ctx) {
    $req  = $ctx.Request
    $resp = $ctx.Response
    $resp.Headers.Add('Access-Control-Allow-Origin', '*')
    $resp.Headers.Add('Cache-Control', 'no-cache, no-store, must-revalidate')

    try {
        $path = $req.Url.AbsolutePath
        if ($path -eq '/state') {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($script:CurrentJson)
            $resp.ContentType = 'application/json; charset=utf-8'
            $resp.OutputStream.Write($bytes, 0, $bytes.Length)
            return
        }

        if ($path -eq '/') { $path = '/scenes/09-now-playing.html' }
        $relative = $path.TrimStart('/').Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $filePath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $relative))

        # Path traversal guard.
        if (-not $filePath.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            $resp.StatusCode = 403; return
        }
        if (-not (Test-Path $filePath -PathType Leaf)) {
            $resp.StatusCode = 404; return
        }

        $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
        $resp.ContentType = if ($contentTypes.ContainsKey($ext)) { $contentTypes[$ext] } else { 'application/octet-stream' }
        $bytes = [System.IO.File]::ReadAllBytes($filePath)
        $resp.OutputStream.Write($bytes, 0, $bytes.Length)
    } catch {
        $resp.StatusCode = 500
        $msg = [System.Text.Encoding]::UTF8.GetBytes("$_")
        try { $resp.OutputStream.Write($msg, 0, $msg.Length) } catch {}
    } finally {
        try { $resp.Close() } catch {}
    }
}

# ── Main loop: SMTC poll on a 2s cadence, HTTP serve in between ─────────────

$script:CurrentJson = 'null'
$pollIntervalMs = 2000
$lastPollTicks = -1
$pendingAccept = $null
$lastLoggedJson = $null

Write-Host "[smtc-watch] listening at http://localhost:$port/  (Ctrl+C to stop)"

while ($true) {
    $nowTicks = [Environment]::TickCount
    if ($lastPollTicks -lt 0 -or (($nowTicks - $lastPollTicks) -ge $pollIntervalMs)) {
        try {
            $state = Get-PlayingState
            $json = if ($null -eq $state) { 'null' } else { $state | ConvertTo-Json -Compress }
            $script:CurrentJson = $json
            if ($json -ne $lastLoggedJson) {
                Write-Host ("[smtc-watch] {0}" -f $json)
                $lastLoggedJson = $json
            }
        } catch {
            Write-Host "[smtc-watch] poll error: $_"
        }
        $lastPollTicks = $nowTicks
    }

    if ($null -eq $pendingAccept) {
        $pendingAccept = $listener.GetContextAsync()
    }
    if ($pendingAccept.Wait(100)) {
        Serve-Context $pendingAccept.Result
        $pendingAccept = $null
    }
}
