/* ============================================================
   Géolocalisation — abstraction web / natif iOS.
   - Avant-plan : @capacitor/geolocation (natif) ou
     navigator.geolocation (navigateur).
   - Arrière-plan (guidage écran éteint) :
     @capacitor-community/background-geolocation, activé
     uniquement pendant une navigation pour préserver la batterie.
   ============================================================ */
import { Capacitor, registerPlugin } from "@capacitor/core";
import { Geolocation } from "@capacitor/geolocation";

export interface GeoFix {
  lng: number;
  lat: number;
  accuracy: number; // m
  heading: number | null; // degrés, null si inconnu
  speed: number | null; // m/s
  time: number;
}

export type GeoAccuracy = "max" | "balanced";

type Cb = (fix: GeoFix) => void;

const isNative = Capacitor.isNativePlatform();

/* Plugin arrière-plan (interface minimale) */
interface BgWatcherOptions {
  backgroundMessage?: string;
  backgroundTitle?: string;
  requestPermissions?: boolean;
  stale?: boolean;
  distanceFilter?: number;
}
interface BgLocation {
  latitude: number;
  longitude: number;
  accuracy: number;
  bearing: number | null;
  speed: number | null;
  time: number | null;
}
interface BackgroundGeolocationPlugin {
  addWatcher(
    options: BgWatcherOptions,
    callback: (position?: BgLocation, error?: { code?: string }) => void,
  ): Promise<string>;
  removeWatcher(options: { id: string }): Promise<void>;
}
const BackgroundGeolocation = registerPlugin<BackgroundGeolocationPlugin>(
  "BackgroundGeolocation",
);

export async function requestGeoPermission(): Promise<boolean> {
  if (isNative) {
    try {
      const st = await Geolocation.requestPermissions();
      return st.location === "granted" || st.coarseLocation === "granted";
    } catch {
      return false;
    }
  }
  return "geolocation" in navigator;
}

/* ---------- avant-plan ---------- */

let fgWatchId: string | number | null = null;

export async function startForegroundWatch(
  cb: Cb,
  accuracy: GeoAccuracy,
): Promise<void> {
  await stopForegroundWatch();
  const enableHighAccuracy = accuracy === "max";
  if (isNative) {
    fgWatchId = await Geolocation.watchPosition(
      { enableHighAccuracy, timeout: 15000, maximumAge: 3000 },
      (pos) => {
        if (!pos) return;
        cb({
          lng: pos.coords.longitude,
          lat: pos.coords.latitude,
          accuracy: pos.coords.accuracy,
          heading: pos.coords.heading ?? null,
          speed: pos.coords.speed ?? null,
          time: pos.timestamp,
        });
      },
    );
  } else if ("geolocation" in navigator) {
    fgWatchId = navigator.geolocation.watchPosition(
      (pos) =>
        cb({
          lng: pos.coords.longitude,
          lat: pos.coords.latitude,
          accuracy: pos.coords.accuracy,
          heading: pos.coords.heading,
          speed: pos.coords.speed,
          time: pos.timestamp,
        }),
      () => undefined,
      { enableHighAccuracy, maximumAge: 3000, timeout: 15000 },
    );
  }
}

export async function stopForegroundWatch(): Promise<void> {
  if (fgWatchId == null) return;
  if (isNative) await Geolocation.clearWatch({ id: fgWatchId as string });
  else navigator.geolocation.clearWatch(fgWatchId as number);
  fgWatchId = null;
}

/* ---------- arrière-plan (navigation seulement) ---------- */

let bgWatchId: string | null = null;

export async function startBackgroundWatch(
  cb: Cb,
  accuracy: GeoAccuracy,
): Promise<boolean> {
  if (!isNative) return false;
  await stopBackgroundWatch();
  try {
    bgWatchId = await BackgroundGeolocation.addWatcher(
      {
        backgroundTitle: "Trace vous guide",
        backgroundMessage: "Guidage GPS actif sur votre tracé",
        requestPermissions: true,
        stale: false,
        // filtre distance = grosses économies de batterie en équilibré
        distanceFilter: accuracy === "max" ? 5 : 25,
      },
      (position) => {
        if (!position) return;
        cb({
          lng: position.longitude,
          lat: position.latitude,
          accuracy: position.accuracy,
          heading: position.bearing,
          speed: position.speed,
          time: position.time ?? Date.now(),
        });
      },
    );
    return true;
  } catch {
    return false;
  }
}

export async function stopBackgroundWatch(): Promise<void> {
  if (!bgWatchId) return;
  try {
    await BackgroundGeolocation.removeWatcher({ id: bgWatchId });
  } catch {
    /* déjà retiré */
  }
  bgWatchId = null;
}

export { isNative };
