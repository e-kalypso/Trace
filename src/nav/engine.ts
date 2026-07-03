/* ============================================================
   Moteur de navigation.
   - Projection de la position GPS sur le tracé (accrochage)
   - Progression : distance faite / restante, ETA
   - Détection de virages à l'avance (bannière + notification)
   - Détection hors-tracé
   Tout est pur et sans dépendance UI.
   ============================================================ */
import type { Track, TrackPoint } from "../lib/gpx";

const toRad = Math.PI / 180;

function bearing(aLng: number, aLat: number, bLng: number, bLat: number) {
  const y = Math.sin((bLng - aLng) * toRad) * Math.cos(bLat * toRad);
  const x =
    Math.cos(aLat * toRad) * Math.sin(bLat * toRad) -
    Math.sin(aLat * toRad) * Math.cos(bLat * toRad) * Math.cos((bLng - aLng) * toRad);
  return ((Math.atan2(y, x) / toRad) + 360) % 360;
}

/** différence d'angle signée dans [-180, 180] */
function angleDiff(a: number, b: number) {
  return ((b - a + 540) % 360) - 180;
}

/* ---------- virages précalculés ---------- */

export type TurnDir =
  | "left"
  | "right"
  | "slight-left"
  | "slight-right"
  | "sharp-left"
  | "sharp-right"
  | "finish";

export interface TurnEvent {
  dist: number; // distance cumulée sur le tracé (m)
  dir: TurnDir;
  angle: number; // amplitude du changement de cap
  lng: number;
  lat: number;
}

const LOOK_M = 25; // fenêtre de lissage du cap (m)
const TURN_MIN = 35; // ° minimum pour compter comme virage
const TURN_SHARP = 100;
const TURN_SLIGHT = 55;

/** Précalcule les virages notables d'un tracé. */
export function computeTurns(track: Track): TurnEvent[] {
  const pts = track.points;
  if (pts.length < 3) return [];
  const events: TurnEvent[] = [];

  // cap "entrant" et "sortant" lissés sur ~LOOK_M autour de chaque point
  let lastEventDist = -Infinity;
  for (let i = 1; i < pts.length - 1; i++) {
    const p = pts[i];
    const before = pointAtDist(pts, p.dist - LOOK_M, i, -1);
    const after = pointAtDist(pts, p.dist + LOOK_M, i, +1);
    if (!before || !after) continue;
    const bIn = bearing(before.lng, before.lat, p.lng, p.lat);
    const bOut = bearing(p.lng, p.lat, after.lng, after.lat);
    const d = angleDiff(bIn, bOut);
    const mag = Math.abs(d);
    if (mag < TURN_MIN) continue;
    // regroupe les virages trop proches (< 30 m) : garde le premier
    if (p.dist - lastEventDist < 30) continue;
    lastEventDist = p.dist;
    const side = d > 0 ? "right" : "left";
    const dir: TurnDir =
      mag >= TURN_SHARP
        ? (`sharp-${side}` as TurnDir)
        : mag <= TURN_SLIGHT
          ? (`slight-${side}` as TurnDir)
          : (side as TurnDir);
    events.push({ dist: p.dist, dir, angle: mag, lng: p.lng, lat: p.lat });
  }

  const last = pts[pts.length - 1];
  events.push({ dist: last.dist, dir: "finish", angle: 0, lng: last.lng, lat: last.lat });
  return events;
}

function pointAtDist(
  pts: TrackPoint[],
  target: number,
  fromIdx: number,
  step: 1 | -1,
): TrackPoint | null {
  let i = fromIdx;
  while (i > 0 && i < pts.length - 1 && (step === 1 ? pts[i].dist < target : pts[i].dist > target)) {
    i += step;
  }
  return pts[i] ?? null;
}

/* ---------- accrochage / progression ---------- */

export interface Snap {
  /** distance cumulée projetée sur le tracé (m) */
  dist: number;
  /** distance perpendiculaire au tracé (m) */
  offset: number;
  lng: number;
  lat: number;
  segIdx: number;
}

/**
 * Projette une position sur le tracé. `hintIdx` : dernier segment connu,
 * pour ne chercher qu'autour (perf + cohérence en lacets serrés).
 */
export function snapToTrack(
  track: Track,
  lng: number,
  lat: number,
  hintIdx: number | null,
): Snap {
  const pts = track.points;
  const cosLat = Math.cos(lat * toRad);
  const mPerDegLat = 111320;
  const mPerDegLng = 111320 * cosLat;

  let from = 0;
  let to = pts.length - 2;
  if (hintIdx != null) {
    from = Math.max(0, hintIdx - 40);
    to = Math.min(pts.length - 2, hintIdx + 80);
  }

  let best: Snap = { dist: 0, offset: Infinity, lng: pts[0].lng, lat: pts[0].lat, segIdx: 0 };
  for (let i = from; i <= to; i++) {
    const a = pts[i];
    const b = pts[i + 1];
    const ax = (a.lng - lng) * mPerDegLng;
    const ay = (a.lat - lat) * mPerDegLat;
    const bx = (b.lng - lng) * mPerDegLng;
    const by = (b.lat - lat) * mPerDegLat;
    const dx = bx - ax;
    const dy = by - ay;
    const len2 = dx * dx + dy * dy || 1e-9;
    let t = -(ax * dx + ay * dy) / len2;
    t = Math.max(0, Math.min(1, t));
    const px = ax + t * dx;
    const py = ay + t * dy;
    const off = Math.hypot(px, py);
    if (off < best.offset) {
      const segLen = b.dist - a.dist;
      best = {
        dist: a.dist + t * segLen,
        offset: off,
        lng: a.lng + t * (b.lng - a.lng),
        lat: a.lat + t * (b.lat - a.lat),
        segIdx: i,
      };
    }
  }
  // si l'indice-guide donne un mauvais résultat, re-chercher globalement
  if (hintIdx != null && best.offset > 80) {
    return snapToTrack(track, lng, lat, null);
  }
  return best;
}

/* ---------- état de navigation ---------- */

export interface NavUpdate {
  snap: Snap;
  remaining: number; // m
  done: number; // m
  pct: number;
  offRoute: boolean;
  speed: number; // m/s lissée
  etaMs: number | null;
  nextTurn: (TurnEvent & { in: number }) | null; // in = m avant le virage
  arrived: boolean;
}

export interface NavSession {
  track: Track;
  turns: TurnEvent[];
  lastSegIdx: number | null;
  emaSpeed: number;
  offRouteSince: number | null;
  notifiedTurnDist: number; // dernier virage notifié (via sa dist)
  offRouteNotified: boolean;
}

export const OFF_ROUTE_M = 45;
const OFF_ROUTE_DELAY = 12_000;
const TURN_NOTIFY_M = 90; // notifie quand on passe sous ~90 m du virage
const ARRIVE_M = 25;

export function createSession(track: Track): NavSession {
  return {
    track,
    turns: computeTurns(track),
    lastSegIdx: null,
    emaSpeed: 1.1, // marche ~4 km/h par défaut
    offRouteSince: null,
    notifiedTurnDist: -1,
    offRouteNotified: false,
  };
}

export interface NavEvents {
  notifyTurn?: (turn: TurnEvent & { in: number }) => void;
  notifyOffRoute?: () => void;
  notifyArrived?: () => void;
}

export function updateSession(
  s: NavSession,
  lng: number,
  lat: number,
  rawSpeed: number | null,
  ev: NavEvents,
): NavUpdate {
  const snap = snapToTrack(s.track, lng, lat, s.lastSegIdx);
  s.lastSegIdx = snap.segIdx;

  const total = s.track.stats.distance;
  const done = Math.min(snap.dist, total);
  const remaining = Math.max(0, total - done);

  // vitesse lissée (EMA) — plancher pour éviter ETA infinie à l'arrêt
  if (rawSpeed != null && rawSpeed >= 0 && rawSpeed < 12) {
    s.emaSpeed = s.emaSpeed * 0.8 + rawSpeed * 0.2;
  }
  const speedForEta = Math.max(0.6, s.emaSpeed);
  const etaMs = remaining > 0 ? (remaining / speedForEta) * 1000 : 0;

  // hors-tracé (temporisé pour ignorer les pertes GPS ponctuelles)
  const now = Date.now();
  let offRoute = false;
  if (snap.offset > OFF_ROUTE_M) {
    if (s.offRouteSince == null) s.offRouteSince = now;
    else if (now - s.offRouteSince > OFF_ROUTE_DELAY) offRoute = true;
  } else {
    s.offRouteSince = null;
    s.offRouteNotified = false;
  }
  if (offRoute && !s.offRouteNotified) {
    s.offRouteNotified = true;
    ev.notifyOffRoute?.();
  }

  // prochain virage devant nous
  let nextTurn: (TurnEvent & { in: number }) | null = null;
  for (const t of s.turns) {
    if (t.dist > done + 8) {
      nextTurn = { ...t, in: t.dist - done };
      break;
    }
  }
  if (
    nextTurn &&
    !offRoute &&
    nextTurn.in <= TURN_NOTIFY_M &&
    s.notifiedTurnDist !== nextTurn.dist &&
    nextTurn.dir !== "finish"
  ) {
    s.notifiedTurnDist = nextTurn.dist;
    ev.notifyTurn?.(nextTurn);
  }

  const arrived = remaining <= ARRIVE_M;
  if (arrived && s.notifiedTurnDist !== Infinity) {
    s.notifiedTurnDist = Infinity;
    ev.notifyArrived?.();
  }

  return {
    snap,
    remaining,
    done,
    pct: total ? done / total : 0,
    offRoute,
    speed: s.emaSpeed,
    etaMs,
    nextTurn,
    arrived,
  };
}

/* ---------- libellés ---------- */

export function turnLabel(dir: TurnDir): string {
  switch (dir) {
    case "left": return "Tournez à gauche";
    case "right": return "Tournez à droite";
    case "slight-left": return "Légèrement à gauche";
    case "slight-right": return "Légèrement à droite";
    case "sharp-left": return "Virage serré à gauche";
    case "sharp-right": return "Virage serré à droite";
    case "finish": return "Arrivée";
  }
}

export function turnGlyph(dir: TurnDir): string {
  switch (dir) {
    case "left": return "↰";
    case "right": return "↱";
    case "slight-left": return "↖";
    case "slight-right": return "↗";
    case "sharp-left": return "⤺";
    case "sharp-right": return "⤻";
    case "finish": return "⚑";
  }
}
