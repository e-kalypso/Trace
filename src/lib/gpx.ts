/* ============================================================
   GPX parsing + track normalization + stats.
   Uses @tmcw/togeojson to read the XML, then we normalize into
   a flat, indexable point list with cumulative distance so the
   map, elevation profile, and stats panel all share one model.
   ============================================================ */
import { gpx as gpxToGeoJSON } from "@tmcw/togeojson";
import type { Feature, FeatureCollection, LineString, MultiLineString } from "geojson";

export interface TrackPoint {
  lng: number;
  lat: number;
  ele: number | null; // metres, null if absent
  time: number | null; // epoch ms, null if absent
  /** cumulative distance from the first point, in metres */
  dist: number;
}

export interface TrackStats {
  distance: number; // metres
  ascent: number; // metres gained
  descent: number; // metres lost
  minEle: number | null;
  maxEle: number | null;
  avgEle: number | null;
  hasTime: boolean;
  duration: number | null; // ms, wall-clock start->end
  movingTime: number | null; // ms, excluding pauses
  pointCount: number;
}

export interface Track {
  id: string;
  name: string;
  points: TrackPoint[];
  stats: TrackStats;
}

export interface ParsedGpx {
  name: string;
  tracks: Track[];
  /** GeoJSON of all track lines, ready to hand to MapLibre */
  geojson: FeatureCollection;
}

const EARTH_R = 6371008.8; // mean Earth radius, metres

/** Haversine great-circle distance between two lng/lat points, in metres. */
function haversine(aLng: number, aLat: number, bLng: number, bLat: number): number {
  const toRad = Math.PI / 180;
  const dLat = (bLat - aLat) * toRad;
  const dLng = (bLng - aLng) * toRad;
  const lat1 = aLat * toRad;
  const lat2 = bLat * toRad;
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_R * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** A point is "moving" if it covered >0.5 m and <=2 min since the last one. */
const MOVING_MIN_DIST = 0.5;
const MOVING_MAX_GAP = 2 * 60 * 1000;
/** Ignore sub-metre elevation jitter when summing ascent/descent. */
const ELE_NOISE = 1.0;

function buildPoints(
  coords: number[][],
  times: (string | null)[] | undefined,
): TrackPoint[] {
  const pts: TrackPoint[] = [];
  let cumDist = 0;
  for (let i = 0; i < coords.length; i++) {
    const c = coords[i];
    const lng = c[0];
    const lat = c[1];
    const ele = c.length > 2 && Number.isFinite(c[2]) ? c[2] : null;
    const t = times && times[i] ? Date.parse(times[i] as string) : NaN;
    if (i > 0) {
      const prev = coords[i - 1];
      cumDist += haversine(prev[0], prev[1], lng, lat);
    }
    pts.push({ lng, lat, ele, time: Number.isNaN(t) ? null : t, dist: cumDist });
  }
  return pts;
}

function computeStats(points: TrackPoint[]): TrackStats {
  let ascent = 0;
  let descent = 0;
  let minEle: number | null = null;
  let maxEle: number | null = null;
  let eleSum = 0;
  let eleCount = 0;
  let movingTime = 0;
  let lastEle: number | null = null;

  for (let i = 0; i < points.length; i++) {
    const p = points[i];
    if (p.ele != null) {
      minEle = minEle == null ? p.ele : Math.min(minEle, p.ele);
      maxEle = maxEle == null ? p.ele : Math.max(maxEle, p.ele);
      eleSum += p.ele;
      eleCount++;
      if (lastEle != null) {
        const d = p.ele - lastEle;
        if (d > ELE_NOISE) ascent += d;
        else if (d < -ELE_NOISE) descent += -d;
      }
      lastEle = p.ele;
    }
    if (i > 0) {
      const prev = points[i - 1];
      if (p.time != null && prev.time != null) {
        const gap = p.time - prev.time;
        const step = p.dist - prev.dist;
        if (gap > 0 && gap <= MOVING_MAX_GAP && step >= MOVING_MIN_DIST) {
          movingTime += gap;
        }
      }
    }
  }

  const first = points[0];
  const last = points[points.length - 1];
  const hasTime = !!(first?.time != null && last?.time != null);
  const duration = hasTime ? (last.time as number) - (first.time as number) : null;

  return {
    distance: last ? last.dist : 0,
    ascent,
    descent,
    minEle,
    maxEle,
    avgEle: eleCount ? eleSum / eleCount : null,
    hasTime,
    duration,
    movingTime: hasTime ? movingTime : null,
    pointCount: points.length,
  };
}

let idSeq = 0;

/** Build a Track (points + stats) from raw [lng,lat,ele?] coordinates.
    Used by the route editor so edits share the same stats/elevation model. */
export function trackFromCoords(name: string, coords: number[][]): Track {
  const points = buildPoints(coords, undefined);
  return { id: `t${idSeq++}`, name, points, stats: computeStats(points) };
}

/** Parse raw GPX text into normalized tracks + GeoJSON. */
export function parseGpx(text: string, fileName = "track.gpx"): ParsedGpx {
  const dom = new DOMParser().parseFromString(text, "application/xml");
  const parseError = dom.querySelector("parsererror");
  if (parseError) {
    throw new Error("This file isn't valid GPX/XML.");
  }
  const fc = gpxToGeoJSON(dom) as FeatureCollection;

  const tracks: Track[] = [];
  const lineFeatures: Feature[] = [];

  for (const feature of fc.features) {
    const geom = feature.geometry;
    if (!geom) continue;
    const name =
      (feature.properties && (feature.properties.name as string)) ||
      stripExt(fileName);
    // togeojson stores per-point times under coordinateProperties.times
    const coordTimes =
      (feature.properties &&
        (feature.properties as Record<string, unknown>).coordinateProperties) ||
      null;

    if (geom.type === "LineString") {
      const times = getTimes(coordTimes, 0);
      addTrack(tracks, name, (geom as LineString).coordinates, times);
      lineFeatures.push(feature);
    } else if (geom.type === "MultiLineString") {
      const parts = (geom as MultiLineString).coordinates;
      // Concatenate segments into one logical track for stats.
      const merged: number[][] = [];
      const mergedTimes: (string | null)[] = [];
      parts.forEach((seg, si) => {
        const times = getTimes(coordTimes, si) ?? [];
        seg.forEach((c, ci) => {
          merged.push(c);
          mergedTimes.push(times[ci] ?? null);
        });
      });
      addTrack(tracks, name, merged, mergedTimes);
      lineFeatures.push(feature);
    }
  }

  return {
    name: stripExt(fileName),
    tracks,
    geojson: { type: "FeatureCollection", features: lineFeatures },
  };
}

function addTrack(
  tracks: Track[],
  name: string,
  coords: number[][],
  times: (string | null)[] | undefined,
) {
  if (!coords || coords.length < 2) return;
  const points = buildPoints(coords, times);
  tracks.push({
    id: `t${idSeq++}`,
    name,
    points,
    stats: computeStats(points),
  });
}

/** coordinateProperties.times can be a flat array (LineString) or nested (Multi). */
function getTimes(
  coordProps: unknown,
  segIndex: number,
): (string | null)[] | undefined {
  if (!coordProps || typeof coordProps !== "object") return undefined;
  const times = (coordProps as Record<string, unknown>).times;
  if (!Array.isArray(times)) return undefined;
  if (times.length && Array.isArray(times[0])) {
    return times[segIndex] as (string | null)[];
  }
  return times as (string | null)[];
}

function stripExt(name: string): string {
  return name.replace(/\.[^.]+$/, "");
}
