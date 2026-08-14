# Idea: chat Tetris

Parked design note, not a commitment. Written up alongside the `!weeman` avatars,
which ship first and establish the per-user colour identity this reuses.

## The problem to design around

Chat runs 2–5 seconds behind the stream. So anything needing timing precision is
luck, and anything needing several messages is too slow to be fun. The whole
design follows from one rule:

**One chat message must be one complete decision.**

## Ruleset

Play field is a narrow vertical strip down one edge, roughly 8 columns wide,
semi-transparent. It sits there all stream and accumulates. A full-width field
eats the gameplay; a strip can be ignored for twenty minutes and still be there.

- A piece waits at the top of the strip, **auto-rotating on a slow cycle**.
- `!t 5` drops it in column 5, at whatever rotation it happens to be showing.
- First valid command claims the piece. One piece, one person.
- If nobody commands within ~20s it drops where it is, so the game never stalls.

**Players never rotate pieces.** That removes an entire input dimension, most of
the syntax, and most of the implementation complexity, while keeping the two
decisions that matter: where, and when. The rotation cycle is what makes the
same column land differently, and that is where the comedy is.

## Why anyone plays

A landed block keeps the placer's colour and initials **permanently**. The wall
becomes a visible record of who built it. That, not the game, is the engagement
engine: people point at their block an hour later.

Line clears pay Ostis or XP back to everyone with a block in the cleared line,
so clearing is a shared goal rather than the loss of your monument.

## Topping out

Don't just reset. When the stack reaches the top the field floods across the
whole screen for a beat, then collapses into a leaderboard of the top builders,
and the board clears. A punchline and a scoreboard in one.

## Ostis sinks, once the base game is proven fun

Keep `!t` free. Participation is the point. Charge for power:

- `!bomb <col>` clears a 3x3
- `!gravity` compacts the stack
- `!piece <shape>` buys the shape of the next piece

## Cross-pollination with the weeman avatars

- A line clear makes every weeman jump and cheer.
- A landing block gives the ticker a small shake.
- Same colour identity in both, so a viewer's weeman and their tetris blocks
  match.

## Implementation notes

- Collision, line clears and the spawn queue are all simple. Rotation is the
  fiddly part, and players not rotating removes most of it.
- Entirely client-side and deterministic. No backend until the paid power-ups.
- Board state persists to `localStorage`, so a source refresh does not destroy
  an hour of stacking. Key it per day.
- Needs a mod `!tetrisclear` and a pause, same as every other chat-driven
  overlay here.

## Alternatives considered

- **Sweeping cursor**, piece slides across the top and `!tetris` drops it where
  it is. One word, no arguments, maximum accessibility. Rejected as the default
  because chat latency makes it pure luck, though that is arguably the joke. Worth
  revisiting if `!t <col>` proves too fiddly to type.
- **Vote per piece**, a 10s window where chat votes on the column. Better with a
  big chat, dead air with a small one.
