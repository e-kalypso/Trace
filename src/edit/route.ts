/* ============================================================
   Edit route model + pure helpers.
   An EditRoute is an ordered list of anchors (the points you
   click) plus the resolved geometry between each pair (snapped
   to trails, or straight). Waypoints are named POIs.
   Everything here is pure so undo/redo is just snapshotting.
   ============================================================ */
import type { FeatureCollection } from "geojson";
import { trackFromCoords, type Track } from "../lib/gpx";
import type { LngLat, RouteProfile, SnapResult } from "../lib/routing";

export interface Anchor extends LngLat {}

export interface Segment {
  /** [lng,lat,ele?] from anchor i to anchor i+1 (inclusive of both ends) */
  coords: number[][];
  snapped: boolean;
}

export interface Waypoint {
  id: string;
  lng: number;
  lat: number;
  name: string;
}

export interface EditRoute {
  anchors: Anchor[];
  segments: Segment[]; // length === max(0, anchors.length - 1)
  waypoints: Waypoint[];
  profile: RouteProfile;
}

export function emptyRoute(profile: RouteProfile = "hike"): EditRoute {
  return { anchors: [], segments: [], waypoints: [], profile };
}

let wpSeq = 0;
export function newWaypointId(): string {
  return `w${wpSeq++}`;
}

/** Flatten all segment coords into one continuous polyline. */
export function routeCoords(route: EditRoute): number[][] {
  if (route.anchors.length === 0) return [];
  if (route.segments.length === 0) {
    // single anchor, no line yet
    const a = route.anchors[0];
    return [[a.lng, a.lat]];
  }
  const out: number[][] = [];
  route.segments.forEach((seg, i) => {
    const start = i === 0 ? 0 : 1; // avoid duplicating the shared anchor
    for (let j = start; j < seg.coords.length; j++) out.push(seg.coords[j]);
  });
  return out;
}

/** Whether any segment is a straight (unsnapped) fallback. */
export function hasUnsnapped(route: EditRoute): boolean {
  return route.segments.some((s) => !s.snapped);
}

/** GeoJSON for the coral edit line. */
export function routeToGeoJSON(route: EditRoute): FeatureCollection {
  const coords = routeCoords(route);
  const features =
    coords.length >= 2
      ? [
          {
            type: "Feature" as const,
            properties: {},
            geometry: { type: "LineString" as const, coordinates: coords },
          },
        ]
      : [];
  return { type: "FeatureCollection", features };
}

/** Build a Track for stats + elevation profile of the edited route. */
export function routeToTrack(route: EditRoute, name = "New route"): Track | null {
  const coords = routeCoords(route);
  if (coords.length < 2) return null;
  return trackFromCoords(name, coords);
}

/* --- immutable edit operations (return new EditRoute) --- */

export function withAnchorAppended(
  route: EditRoute,
  anchor: Anchor,
  seg: Segment | null,
): EditRoute {
  const anchors = [...route.anchors, anchor];
  const segments = seg ? [...route.segments, seg] : [...route.segments];
  return { ...route, anchors, segments };
}

export function withAnchorMoved(
  route: EditRoute,
  idx: number,
  anchor: Anchor,
  before: Segment | null,
  after: Segment | null,
): EditRoute {
  const anchors = route.anchors.map((a, i) => (i === idx ? anchor : a));
  const segments = [...route.segments];
  if (idx > 0 && before) segments[idx - 1] = before;
  if (idx < anchors.length - 1 && after) segments[idx] = after;
  return { ...route, anchors, segments };
}

export function withAnchorDeleted(
  route: EditRoute,
  idx: number,
  bridge: Segment | null,
): EditRoute {
  const anchors = route.anchors.filter((_, i) => i !== idx);
  let segments = [...route.segments];
  if (idx === 0) {
    segments = segments.slice(1);
  } else if (idx === route.anchors.length - 1) {
    segments = segments.slice(0, -1);
  } else {
    // remove the two segments touching idx, insert the bridge between idx-1 and idx+1
    const before = segments.slice(0, idx - 1);
    const after = segments.slice(idx + 1);
    segments = bridge ? [...before, bridge, ...after] : [...before, ...after];
  }
  return { ...route, anchors, segments };
}

export function withReversed(route: EditRoute): EditRoute {
  const anchors = [...route.anchors].reverse();
  const segments = [...route.segments]
    .reverse()
    .map((s) => ({ ...s, coords: [...s.coords].reverse() }));
  return { ...route, anchors, segments };
}

export function withProfile(route: EditRoute, profile: RouteProfile): EditRoute {
  return { ...route, profile };
}

export function withWaypoint(route: EditRoute, wp: Waypoint): EditRoute {
  return { ...route, waypoints: [...route.waypoints, wp] };
}

export function withoutWaypoint(route: EditRoute, id: string): EditRoute {
  return { ...route, waypoints: route.waypoints.filter((w) => w.id !== id) };
}

export function segFromSnap(snap: SnapResult): Segment {
  return { coords: snap.coords, snapped: snap.snapped };
}
