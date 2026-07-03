/* Generates a realistic synthetic hike GPX with elevation + timestamps.
   Run: node scripts/make-sample.mjs  ->  public/samples/lac-blanc.gpx */
import { writeFileSync, mkdirSync } from "node:fs";

// A rough out-and-back climb near Chamonix (Lac Blanc-ish), synthetic.
const start = { lng: 6.8794, lat: 45.9846, ele: 1420 };
const N = 220;
const points = [];
let t = Date.parse("2026-06-14T07:30:00Z");

for (let i = 0; i <= N; i++) {
  const p = i / N;
  // out then back
  const leg = p < 0.5 ? p * 2 : (1 - p) * 2;
  // wander north-east on the way up
  const lng = start.lng + leg * 0.028 + Math.sin(i / 9) * 0.0011;
  const lat = start.lat + leg * 0.019 + Math.cos(i / 11) * 0.0009;
  // climb ~780 m with some rolling
  const ele =
    start.ele + leg * 780 + Math.sin(i / 6) * 9 + (Math.random() - 0.5) * 3;
  points.push({ lng, lat, ele, time: new Date(t).toISOString() });
  // ~14 s/point uphill, faster downhill, with a lunch pause midway
  t += (p < 0.5 ? 15000 : 9000);
  if (i === Math.floor(N / 2)) t += 22 * 60 * 1000; // 22 min pause at the lake
}

const trkpts = points
  .map(
    (p) =>
      `      <trkpt lat="${p.lat.toFixed(6)}" lon="${p.lng.toFixed(6)}"><ele>${p.ele.toFixed(
        1,
      )}</ele><time>${p.time}</time></trkpt>`,
  )
  .join("\n");

const gpx = `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Trace sample generator" xmlns="http://www.topografix.com/GPX/1/1">
  <metadata><name>Lac Blanc loop (sample)</name></metadata>
  <trk>
    <name>Lac Blanc loop (sample)</name>
    <trkseg>
${trkpts}
    </trkseg>
  </trk>
</gpx>
`;

mkdirSync("public/samples", { recursive: true });
writeFileSync("public/samples/lac-blanc.gpx", gpx);
console.log(`Wrote public/samples/lac-blanc.gpx (${points.length} points)`);
