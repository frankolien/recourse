// Renders an HTML film to MP4 by stepping every animation on the page to an exact
// time and screenshotting each frame, so the output never drops a frame no matter
// how heavy the page is. Usage: node render.mjs <page.html> <seconds> <out.mp4> [fps]
import { chromium } from "playwright";
import { spawn } from "node:child_process";
import { resolve } from "node:path";

const [, , pagePath, secondsArg, outPath, fpsArg] = process.argv;
const seconds = Number(secondsArg);
const fps = Number(fpsArg ?? 60);
const frames = Math.round(seconds * fps);

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1 });
await page.goto("file://" + resolve(pagePath), { waitUntil: "networkidle" });
await page.evaluate(() => document.fonts.ready);
// Freeze everything; the loop below owns time.
await page.evaluate(() => document.getAnimations().forEach((a) => a.pause()));

const ffmpeg = spawn("ffmpeg", ["-y", "-loglevel", "error", "-f", "image2pipe", "-framerate", String(fps), "-i", "-", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "16", "-preset", "slow", "-movflags", "+faststart", outPath], { stdio: ["pipe", "inherit", "inherit"] });

const t0 = Date.now();
for (let i = 0; i < frames; i += 1) {
  const t = (i / fps) * 1000;
  await page.evaluate((ms) => {
    document.getAnimations().forEach((a) => {
      a.pause();
      a.currentTime = ms;
    });
    window.__tick?.(ms);
  }, t);
  const png = await page.screenshot({ type: "png" });
  if (!ffmpeg.stdin.write(png)) await new Promise((r) => ffmpeg.stdin.once("drain", r));
  if (i % (fps * 5) === 0) process.stderr.write(`frame ${i}/${frames} ${((Date.now() - t0) / 1000).toFixed(0)}s\n`);
}
ffmpeg.stdin.end();
await new Promise((r) => ffmpeg.on("close", r));
await browser.close();
console.log(outPath);
