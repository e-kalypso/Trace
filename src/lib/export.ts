/* ============================================================
   Export a Track to GPX / KML / GeoJSON, plus a download helper.
   Optional waypoints are included where the format supports them.
   ============================================================ */
import type { Track } from "./gpx";

export interface ExportWaypoint {
  lng: number;
  lat: number;
  name: string;
}

const XHEAD = '<?xml version="1.0" encoding="UTF-8"?>';

function esc(s: string): string {
  return s.replace(/[&<>"']/g, (c) =>
    c === "&" ? "&amp;" : c === "<" ? "&lt;" : c === ">" ? "&gt;" : c === '"' ? "&quot;" : "&#39;",
  );
}

export function toGpx(track: Track, waypoints: ExportWaypoint[] = []): string {
  const wpts = waypoints
    .map(
      (w) =>
        `  <wpt lat="${w.lat.toFixed(6)}" lon="${w.lng.toFixed(6)}"><name>${esc(
          w.name,
        )}</name></wpt>`,
    )
    .join("\n");
  const trkpts = track.points
    .map((p) => {
      const ele = p.ele != null ? `<ele>${p.ele.toFixed(1)}</ele>` : "";
      const time = p.time != null ? `<time>${new Date(p.time).toISOString()}</time>` : "";
      return `      <trkpt lat="${p.lat.toFixed(6)}" lon="${p.lng.toFixed(6)}">${ele}${time}</trkpt>`;
    })
    .join("\n");
  return `${XHEAD}
<gpx version="1.1" creator="Trace" xmlns="http://www.topografix.com/GPX/1/1">
  <metadata><name>${esc(track.name)}</name></metadata>
${wpts ? wpts + "\n" : ""}  <trk>
    <name>${esc(track.name)}</name>
    <trkseg>
${trkpts}
    </trkseg>
  </trk>
</gpx>
`;
}

export function toGeoJSON(track: Track, waypoints: ExportWaypoint[] = []): string {
  const line = {
    type: "Feature",
    properties: { name: track.name },
    geometry: {
      type: "LineString",
      coordinates: track.points.map((p) =>
        p.ele != null ? [p.lng, p.lat, p.ele] : [p.lng, p.lat],
      ),
    },
  };
  const wpts = waypoints.map((w) => ({
    type: "Feature",
    properties: { name: w.name },
    geometry: { type: "Point", coordinates: [w.lng, w.lat] },
  }));
  return JSON.stringify(
    { type: "FeatureCollection", features: [line, ...wpts] },
    null,
    2,
  );
}

export function toKml(track: Track, waypoints: ExportWaypoint[] = []): string {
  const coords = track.points
    .map((p) => `${p.lng.toFixed(6)},${p.lat.toFixed(6)}${p.ele != null ? "," + p.ele.toFixed(1) : ""}`)
    .join(" ");
  const placemarks = waypoints
    .map(
      (w) =>
        `    <Placemark><name>${esc(w.name)}</name><Point><coordinates>${w.lng.toFixed(
          6,
        )},${w.lat.toFixed(6)}</coordinates></Point></Placemark>`,
    )
    .join("\n");
  return `${XHEAD}
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>${esc(track.name)}</name>
    <Placemark>
      <name>${esc(track.name)}</name>
      <LineString><tessellate>1</tessellate><coordinates>${coords}</coordinates></LineString>
    </Placemark>
${placemarks}
  </Document>
</kml>
`;
}

export type ExportFormat = "gpx" | "geojson" | "kml";

const MIME: Record<ExportFormat, string> = {
  gpx: "application/gpx+xml",
  geojson: "application/geo+json",
  kml: "application/vnd.google-earth.kml+xml",
};

export function exportTrack(
  track: Track,
  format: ExportFormat,
  waypoints: ExportWaypoint[] = [],
): void {
  const text =
    format === "gpx"
      ? toGpx(track, waypoints)
      : format === "geojson"
        ? toGeoJSON(track, waypoints)
        : toKml(track, waypoints);
  const safe = track.name.replace(/[^\w.-]+/g, "_") || "track";
  download(`${safe}.${format}`, text, MIME[format]);
}

export function download(filename: string, text: string, mime: string): void {
  const blob = new Blob([text], { type: mime });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
