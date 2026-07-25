import type { MetadataRoute } from "next";

export default function sitemap(): MetadataRoute.Sitemap {
  const base = "https://recourse-arc.vercel.app";
  return [
    { url: base, priority: 1 },
    { url: `${base}/verify/13`, priority: 0.9 },
    { url: `${base}/verify/15`, priority: 0.9 },
    { url: `${base}/vault`, priority: 0.8 },
    { url: `${base}/signin`, priority: 0.5 },
  ];
}
