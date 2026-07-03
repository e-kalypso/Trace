/* ============================================================
   Routing — snap drawn segments to roads/trails.
   Uses BRouter's free public server (no API key, no signup),
   which is purpose-built for hiking/cycling and returns
   elevation in its geometry. Falls back to straight lines
   offline or on failure.
   ============================================================ */

export type RouteProfile = "hike" | "bike" | "straight";

export interface LngLat {
  lng: number;
  lat: number;
}

const BROUTER = "https://brouter.de/brouter";

// Map our friendly profiles onto BRouter profile names.
const BROUTER_PROFILE: Record<Exclude<RouteProfile, "straight">, string> = {
  hike: "hiking-mountain",
  bike: "trekking",
};

export interface SnapResult {
  /** [lng, lat, ele?] triples */
  coords: number[][];
  snapped: boolean;
}

/** Straight line between two points (used for the override and offline). */
export function straightSegment(a: LngLat, b: LngLat): SnapResult {
  return { coords: [[a.lng, a.lat], [b.lng, b.lat]], snapped: false };
}

/**
 * Route from a -> b along the given profile.
 * Throws on network failure so callers can decide to fall back.
 */
export async function routeSegment(
  a: LngLat,
  b: LngLat,
  profile: RouteProfile,
  signal?: AbortSignal,
): Promise<SnapResult> {
  if (profile === "straight") return straightSegment(a, b);

  const bp = BROUTER_PROFILE[profile];
  const url =
    `${BROUTER}?lonlats=${a.lng.toFixed(6)},${a.lat.toFixed(6)}|` +
    `${b.lng.toFixed(6)},${b.lat.toFixed(6)}` +
    `&profile=${bp}&alternativeidx=0&format=geojson`;

  const res = await fetch(url, { signal });
  if (!res.ok) throw new Error(`routing ${res.status}`);
  const gj = await res.json();
  const coords: number[][] | undefined =
    gj?.features?.[0]?.geometry?.coordinates;
  if (!coords || coords.length < 2) throw new Error("no route");
  return { coords, snapped: true };
}
