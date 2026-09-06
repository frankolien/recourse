// Turns the phone recordings into film beats: each beat is a list of source
// segments (start, end, speed) cut into a 60fps frame sequence, then a page that
// shows those frames inside the phone rig with one headline. Zero credits.
import { execFileSync } from "node:child_process";
import { readdirSync, writeFileSync, mkdirSync } from "node:fs";

const FPS = 60;
const SCENES = [
  { id: "send", src: "rec/send.mp4", h1: ["Sent by", "name."], p: "Type a handle, hold Face ID, done.",
    seg: [[9.6, 11.25, 1], [11.25, 13.25, 3], [13.25, 14.5, 1], [14.5, 15.25, 3], [15.25, 16.25, 1], [16.25, 17.9, 1]] },
  { id: "cheque", src: "rec/cheque.mp4", h1: ["Write a", "cheque."], p: "They cash it when they like. Void it before they do.",
    seg: [[19.25, 20.75, 1], [20.75, 21.25, 3], [21.25, 22.25, 1], [22.25, 22.75, 2], [22.75, 25.4, 1]] },
  { id: "convert", src: "rec/convert.mp4", h1: ["Dollars to", "euros."], p: "The rate is checked before you sign.",
    seg: [[3.25, 5.5, 1], [6.5, 7.25, 1], [10.0, 11.1, 1]] },
  { id: "earn", src: "rec/earn.mp4", h1: ["Idle dollars", "earn."], p: "Deposit and withdraw any time.",
    seg: [[4.5, 5.75, 1], [7.25, 7.75, 1], [9.25, 10.0, 1], [16.5, 17.5, 1], [18.5, 19.6, 1]] },
  { id: "teams", src: "rec/teams.mp4", h1: ["Approve", "together."], p: "A team account with rules the chain enforces.",
    seg: [[5.4, 6.25, 1], [6.25, 7.5, 2], [7.5, 9.8, 1]] },
];

for (const s of SCENES) {
  const dir = `work/${s.id}`;
  mkdirSync(dir, { recursive: true });
  for (const f of readdirSync(dir)) execFileSync("rm", [`${dir}/${f}`]);
  const parts = s.seg.map(([a, b, v], i) => `[0:v]trim=start=${a}:end=${b},setpts=(PTS-STARTPTS)/${v}[v${i}]`);
  const chain = s.seg.map((_, i) => `[v${i}]`).join("");
  const filter = `${parts.join(";")};${chain}concat=n=${s.seg.length}:v=1:a=0,fps=${FPS},scale=520:-1[out]`;
  execFileSync("ffmpeg", ["-y", "-loglevel", "error", "-i", s.src, "-filter_complex", filter, "-map", "[out]", "-q:v", "3", `${dir}/%04d.jpg`]);
  const frames = readdirSync(dir).length;
  const seconds = frames / FPS;
  const leave = Math.round(seconds * 1000 - 400);
  const html = `<!doctype html><meta charset="utf-8"><link rel="stylesheet" href="base.css"><link rel="stylesheet" href="beat.css">
<style>:root { --leave: ${leave}ms; --len: ${Math.round(seconds * 1000)}ms; }</style>
<div class="stage">
  <div class="copy"><h1><span>${s.h1[0]}</span><span>${s.h1[1]}</span></h1><p>${s.p}</p></div>
  <div class="rig"><div class="phone rec"><div class="screen"><img id="shot" src="${dir}/0001.jpg"></div><div class="island"></div><div class="glare"></div></div></div>
</div>
<script>
  const frames = ${frames}, dir = "${dir}";
  const pad = (n) => String(n).padStart(4, "0");
  // Every frame is decoded before the render starts so a swap never shows a blank.
  const cache = Array.from({ length: frames }, (_, i) => { const im = new Image(); im.src = dir + "/" + pad(i + 1) + ".jpg"; return im; });
  window.__tick = (ms) => {
    const i = Math.min(frames - 1, Math.floor(ms / 1000 * ${FPS}));
    document.getElementById("shot").src = cache[i].src;
  };
</script>`;
  writeFileSync(`scene-${s.id}.html`, html);
  console.log(`${s.id}: ${frames} frames, ${seconds.toFixed(2)}s`);
}
