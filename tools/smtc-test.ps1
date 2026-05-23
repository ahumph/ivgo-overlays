# tools/smtc-test.ps1 — print whatever the Windows System Media Transport
# Controls API currently reports as playing. Confirms that Tidal / YouTube /
# etc. are visible to SMTC before wiring a bridge to the IVGO overlay.
#
# MUST be run with Windows PowerShell 5.1 (powershell.exe), NOT PowerShell 7+
# (pwsh.exe) — PS7 dropped the WinRT projection used here. Example:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\smtc-test.ps1
#
# For the eventual production bridge we'll use Node.js with the
# `node-windows-media` (or similar) package which works regardless of PS version.

[Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType=WindowsRuntime] | Out-Null
Add-Type -AssemblyName System.Runtime.WindowsRuntime

# WinRT IAsyncOperation -> .NET Task helper (PowerShell can't await directly).
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() |
  Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
                 $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]

function Await($op, $resultType) {
    $task = $asTaskGeneric.MakeGenericMethod($resultType).Invoke($null, @($op))
    $task.Wait() | Out-Null
    $task.Result
}

$mgr = Await `
  ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) `
  ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])

$sessions = @($mgr.GetSessions())   # force PowerShell-array; .Count on the raw
                                    # WinRT IReadOnlyList is unreliable here.
if ($sessions.Count -eq 0) {
    Write-Host "No active media sessions. Start playback in Tidal / YouTube / etc. and rerun."
    return
}

$current = $mgr.GetCurrentSession()
$currentId = if ($current) { $current.SourceAppUserModelId } else { $null }

Write-Host ("Sessions: {0}" -f $sessions.Count)
Write-Host ""

foreach ($s in $sessions) {
    $props = Await `
      ($s.TryGetMediaPropertiesAsync()) `
      ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])
    $info = $s.GetPlaybackInfo()
    $marker = if ($s.SourceAppUserModelId -eq $currentId) { "[CURRENT] " } else { "          " }

    [pscustomobject]@{
        Tag            = ($marker + $s.SourceAppUserModelId)
        Title          = $props.Title
        Artist         = $props.Artist
        Album          = $props.AlbumTitle
        TrackNumber    = $props.TrackNumber
        PlaybackStatus = $info.PlaybackStatus
    } | Format-List
}
