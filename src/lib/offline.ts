/* ============================================================
   Offline map regions.
   Downloads the vector tiles covering a bounding box into the
   SAME Cache Storage bucket the service worker serves from, so
   a pre-downloaded area renders with no connection.
   ============================================================ */
import type { Map as MlMap } from "maplibre-gl";

// Must match the runtimeCaching cacheName in vite.config.ts.
export const TILE_CACHE = "openfreemap-tiles";

export interface TileCoord {
  z: number;
  x: number;
  y: number;
}

export interface VectorSourceInfo {
  template: string; // e.g. https://.../{z}/{x}/{y}.pbf
  minzoom: number;
  maxzoom: number;
}

export function lon2tile(lon: number, z: number): number {
  return Math.floor(((lon + 180) / 360) * 2 ** z);
}
export function lat2tile(lat: number, z: number): number {
  const r = (lat * Math.PI) / 180;
  return Math.floor(
    ((1 - Math.log(Math.tan(r) + 1 / Math.cos(r)) / Math.PI) / 2) * 2 ** z,
  );
}

/** All tiles covering bbox [w,s,e,n] across the zoom range (inclusive). */
export function tilesForBbox(
  bbox: [number, number, number, number],
  zMin: number,
  zMax: number,
): TileCoord[] {
  const [w, s, e, n] = bbox;
  const out: TileCoord[] = [];
  for (let z = zMin; z <= zMax; z++) {
    const xMin = clamp(lon2tile(w, z), z);
    const xMax = clamp(lon2tile(e, z), z);
    const yMin = clamp(lat2tile(n, z), z); // north = smaller y
    const yMax = clamp(lat2tile(s, z), z);
    for (let x = Math.min(xMin, xMax); x <= Math.max(xMin, xMax); x++) {
      for (let y = Math.min(yMin, yMax); y <= Math.max(yMin, yMax); y++) {
        out.push({ z, x, y });
      }
    }
  }
  return out;
}

function clamp(v: number, z: number): number {
  return Math.max(0, Math.min(2 ** z - 1, v));
}

/** Read the vector tile URL template from the live map style. */
export async function getVectorSource(map: MlMap): Promise<VectorSourceInfo | null> {
  const style = map.getStyle();
  const sources = style.sources || {};
  for (const src of Object.values(sources)) {
    const s = src as Record<string, unknown>;
    if (s.type !== "vector") continue;
    if (Array.isArray(s.tiles) && s.tiles.length) {
      return {
        template: s.tiles[0] as string,
        minzoom: (s.minzoom as number) ?? 0,
        maxzoom: (s.maxzoom as number) ?? 14,
      };
    }
    if (typeof s.url === "string") {
      try {
        const tj = await (await fetch(s.url)).json();
        if (Array.isArray(tj.tiles) && tj.tiles.length) {
          return {
            template: tj.tiles[0],
            minzoom: tj.minzoom ?? 0,
            maxzoom: tj.maxzoom ?? 14,
          };
        }
      } catch {
        /* fall through */
      }
    }
  }
  return null;
}

export function buildTileUrl(template: string, t: TileCoord): string {
  return template
    .replace("{z}", String(t.z))
    .replace("{x}", String(t.x))
    .replace("{y}", String(t.y));
}

export interface DownloadResult {
  tileUrls: string[];
  bytes: number;
  failed: number;
}

/** Download tiles into the tile cache with limited concurrency + progress. */
export async function downloadTiles(
  urls: string[],
  onProgress: (done: number, total: number) => void,
  concurrency = 6,
): Promise<DownloadResult> {
  const cache = await caches.open(TILE_CACHE);
  const done = { n: 0, bytes: 0, failed: 0, stored: [] as string[] };
  let cursor = 0;

  async function worker() {
    while (cursor < urls.length) {
      const url = urls[cursor++];
      try {
        const res = await fetch(url, { mode: "cors" });
        if (res.ok) {
          const buf = await res.clone().arrayBuffer();
          done.bytes += buf.byteLength;
          await cache.put(url, res);
          done.stored.push(url);
        } else {
          done.failed++;
        }
      } catch {
        done.failed++;
      }
      done.n++;
      onProgress(done.n, urls.length);
    }
  }

  await Promise.all(
    Array.from({ length: Math.min(concurrency, urls.length) }, worker),
  );
  return { tileUrls: done.stored, bytes: done.bytes, failed: done.failed };
}

/** Remove a region's tiles from the cache to free space. */
export async function evictTiles(urls: string[]): Promise<void> {
  const cache = await caches.open(TILE_CACHE);
  await Promise.all(urls.map((u) => cache.delete(u)));
}

export function fmtBytes(bytes: number): string {
  if (bytes >= 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  if (bytes >= 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${bytes} B`;
}

export async function storageEstimate(): Promise<{ usage: number; quota: number } | null> {
  if (navigator.storage?.estimate) {
    const e = await navigator.storage.estimate();
    return { usage: e.usage ?? 0, quota: e.quota ?? 0 };
  }
  return null;
}
