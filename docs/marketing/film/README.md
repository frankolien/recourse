# App film

The launch film is rendered from code, not from a video editor, so a beat can be
recut in minutes and costs nothing.

Inputs: screen recordings of the app, 60 fps portrait, put under `rec/` as
`send.mp4`, `cheque.mp4`, `convert.mp4`, `earn.mp4`, `teams.mp4`.

1. `node build.mjs` cuts each recording into the segments listed at the top of
   the file (start, end, speed) and writes one page per beat.
2. `node render.mjs scene-send.html 6.52 out/s-send.mp4` renders a beat. The
   frame count printed by build.mjs divided by 60 is the length.
3. Concat the beats with ffmpeg in order: scene1, send, cheque, convert, earn,
   teams, close.

`still.mjs page.html 1500 out.png` shows one frame for checking a beat first.
Playwright and ffmpeg are the only dependencies.

## Clips for the daily posts

One beat each, cut from the finished film so the phone is parked and the headline
is up for the whole clip (seconds in, seconds out): home 0 to 4.5, send 4.85 to
10.15, cheque 10.85 to 15.45, keys 16.15 to 20.25, convert 20.95 to 24.45, earn
24.95 to 28.95, teams 29.55 to 32.55.

```
ffmpeg -ss 4.85 -to 10.15 -i app-film-v3.mp4 -c:v libx264 -crf 18 -pix_fmt yuv420p cuts/send.mp4
```
