import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { VitePWA } from "vite-plugin-pwa";

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      registerType: "autoUpdate",
      includeAssets: ["favicon.svg", "icons/apple-touch-icon.png"],
      manifest: {
        name: "Trace — GPX viewer & editor",
        short_name: "Trace",
        description: "View and edit GPX routes. Works offline.",
        theme_color: "#141b23",
        background_color: "#141b23",
        display: "standalone",
        orientation: "any",
        start_url: "/",
        icons: [
          { src: "icons/icon-192.png", sizes: "192x192", type: "image/png" },
          { src: "icons/icon-512.png", sizes: "512x512", type: "image/png" },
          {
            src: "icons/maskable-512.png",
            sizes: "512x512",
            type: "image/png",
            purpose: "maskable",
          },
        ],
      },
      workbox: {
        globPatterns: ["**/*.{js,css,html,svg,png,woff2,gpx}"],
        maximumFileSizeToCacheInBytes: 4 * 1024 * 1024, // maplibre-gl is large
        // Cache visited basemap tiles so recently-seen areas load offline.
        runtimeCaching: [
          {
            urlPattern: ({ url }) =>
              url.href.startsWith("https://tiles.openfreemap.org"),
            handler: "CacheFirst",
            options: {
              cacheName: "openfreemap-tiles",
              expiration: { maxEntries: 3000, maxAgeSeconds: 60 * 60 * 24 * 30 },
              cacheableResponse: { statuses: [0, 200] },
            },
          },
        ],
      },
    }),
  ],
});
