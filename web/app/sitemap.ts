import type { MetadataRoute } from "next";

const base = "https://recourse-arc.vercel.app";

export default function sitemap(): MetadataRoute.Sitemap {
  return ["/", "/support", "/privacy", "/terms", "/olien"].map((path) => ({
    url: `${base}${path}`,
    lastModified: new Date(),
  }));
}
