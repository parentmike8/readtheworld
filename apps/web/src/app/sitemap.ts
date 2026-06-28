import type { MetadataRoute } from "next";

export default function sitemap(): MetadataRoute.Sitemap {
  return [
    {
      url: "https://readtheworld.today",
      changeFrequency: "daily",
      priority: 1,
    },
  ];
}
