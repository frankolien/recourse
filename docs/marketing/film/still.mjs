// One frame of a beat at a given time, for checking a scene before rendering it.
import { chromium } from "playwright";
import { resolve } from "node:path";
const [, , pagePath, msArg, outPath] = process.argv;
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
await page.goto("file://" + resolve(pagePath), { waitUntil: "networkidle" });
await page.evaluate(() => document.fonts.ready);
await page.evaluate((ms) => { document.getAnimations().forEach((a) => { a.pause(); a.currentTime = ms; }); window.__tick?.(ms); }, Number(msArg));
await page.screenshot({ path: outPath });
await browser.close();
