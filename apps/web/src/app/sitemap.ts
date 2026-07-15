import type { MetadataRoute } from "next";

export default function sitemap(): MetadataRoute.Sitemap {
  return [
    {
      url: "https://readtheworld.today",
      changeFrequency: "daily",
      priority: 1,
    },
    {
      url: "https://readtheworld.today/support",
      changeFrequency: "monthly",
      priority: 0.6,
    },
    {
      url: "https://readtheworld.today/privacy",
      changeFrequency: "yearly",
      priority: 0.3,
    },
    {
      url: "https://readtheworld.today/terms",
      changeFrequency: "yearly",
      priority: 0.3,
    },
  ];
}
