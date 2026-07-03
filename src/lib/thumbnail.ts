/* Tiny SVG thumbnail of a track — cheap, crisp, offline, and
   scales in the library list without a canvas or map render. */
import type { Track } from "./gpx";

export interface Bbox {
  bbox: [number, number, number, number]; // w,s,e,n
}

export function trackBbox(track: Track): [number, number, number, number] {
  let w = Infinity;
  let s = Infinity;
  let e = -Infinity;
  let n = -Infinity;
  for (const p of track.points) {
    if (p.lng < w) w = p.lng;
    if (p.lng > e) e = p.lng;
    if (p.lat < s) s = p.lat;
    if (p.lat > n) n = p.lat;
  }
  return [w, s, e, n];
}

export function makeThumbnail(track: Track, size = 96): string {
  const [w, s, e, n] = trackBbox(track);
  const dx = Math.max(1e-6, e - w);
  const dy = Math.max(1e-6, n - s);
  // preserve aspect: use the larger span, center the other
  const pad = 6;
  const span = Math.max(dx, dy);
  const inner = size - pad * 2;
  const offX = pad + (inner * (span - dx)) / span / 2;
  const offY = pad + (inner * (span - dy)) / span / 2;

  const step = Math.max(1, Math.floor(track.points.length / 120));
  const pts: string[] = [];
  for (let i = 0; i < track.points.length; i += step) {
    const p = track.points[i];
    const x = offX + ((p.lng - w) / span) * inner;
    // invert y (north up)
    const y = offY + (1 - (p.lat - s) / span) * inner;
    pts.push(`${x.toFixed(1)},${y.toFixed(1)}`);
  }
  const d = "M" + pts.join(" L");
  return `<svg viewBox="0 0 ${size} ${size}" xmlns="http://www.w3.org/2000/svg">
<rect width="${size}" height="${size}" fill="var(--paper-sunk)"/>
<path d="${d}" fill="none" stroke="var(--track)" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>
</svg>`;
}
