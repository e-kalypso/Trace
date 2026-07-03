/* Human-friendly formatters for the stats panel. Metric for v1. */

export function fmtDistance(metres: number): string {
  if (metres >= 1000) return `${(metres / 1000).toFixed(2)} km`;
  return `${Math.round(metres)} m`;
}

export function fmtElevation(metres: number | null): string {
  if (metres == null) return "—";
  return `${Math.round(metres)} m`;
}

export function fmtDuration(ms: number | null): string {
  if (ms == null) return "—";
  const totalSec = Math.round(ms / 1000);
  const h = Math.floor(totalSec / 3600);
  const m = Math.floor((totalSec % 3600) / 60);
  const s = totalSec % 60;
  if (h > 0) return `${h}h ${String(m).padStart(2, "0")}m`;
  if (m > 0) return `${m}m ${String(s).padStart(2, "0")}s`;
  return `${s}s`;
}

export function fmtCoord(lng: number, lat: number): string {
  return `${lat.toFixed(5)}, ${lng.toFixed(5)}`;
}

/** average pace/speed if we have moving time + distance */
export function fmtSpeed(metres: number, ms: number | null): string {
  if (!ms || ms <= 0) return "—";
  const kmh = metres / 1000 / (ms / 3600000);
  return `${kmh.toFixed(1)} km/h`;
}
