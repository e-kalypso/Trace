import type { CapacitorConfig } from "@capacitor/cli";

const config: CapacitorConfig = {
  // NOTE: this is the iOS "bundle ID" — it must be globally unique on the App
  // Store. Change it to something you own, e.g. com.<yourname>.trace, before
  // creating the App Store Connect record.
  appId: "app.trace.gpx",
  appName: "Trace",
  webDir: "dist",
  backgroundColor: "#141b23",
};

export default config;
