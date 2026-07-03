/* ============================================================
   useNavigation — orchestre GPS, moteur et notifications.
   - Avant-plan : watch haute fréquence
   - App en arrière-plan pendant une nav : bascule sur le
     watcher natif arrière-plan (notifications écran éteint)
   - Batterie : précision réglable, watcher bg coupé hors nav
   ============================================================ */
import { useCallback, useEffect, useRef, useState } from "react";
import { App as CapApp } from "@capacitor/app";
import type { Track } from "../lib/gpx";
import {
  createSession,
  updateSession,
  turnLabel,
  type NavSession,
  type NavUpdate,
} from "./engine";
import {
  isNative,
  requestGeoPermission,
  startBackgroundWatch,
  startForegroundWatch,
  stopBackgroundWatch,
  stopForegroundWatch,
  type GeoAccuracy,
  type GeoFix,
} from "../lib/geo";
import { notify, requestNotifyPermission } from "../lib/notify";
import { fmtDistance } from "../lib/format";

export interface NavState {
  navigating: boolean;
  fix: GeoFix | null;
  update: NavUpdate | null;
}

export function useNavigation(accuracy: GeoAccuracy) {
  const [fix, setFix] = useState<GeoFix | null>(null);
  const [update, setUpdate] = useState<NavUpdate | null>(null);
  const [navigating, setNavigating] = useState(false);
  const [locating, setLocating] = useState(false);

  const sessionRef = useRef<NavSession | null>(null);
  const accuracyRef = useRef(accuracy);
  accuracyRef.current = accuracy;

  const onFix = useCallback((f: GeoFix) => {
    setFix(f);
    const s = sessionRef.current;
    if (!s) return;
    const u = updateSession(s, f.lng, f.lat, f.speed, {
      notifyTurn: (t) =>
        void notify(turnLabel(t.dir), `Dans ${fmtDistance(t.in)}`),
      notifyOffRoute: () =>
        void notify("Hors tracé", "Vous vous éloignez du tracé."),
      notifyArrived: () => void notify("Arrivée", "Vous êtes au bout du tracé 🎉"),
    });
    setUpdate(u);
  }, []);

  /** Localisation simple (bouton "ma position"), sans navigation. */
  const locate = useCallback(async () => {
    setLocating(true);
    const ok = await requestGeoPermission();
    if (ok) await startForegroundWatch(onFix, accuracyRef.current);
    setLocating(false);
    return ok;
  }, [onFix]);

  const startNavigation = useCallback(
    async (track: Track) => {
      const ok = await requestGeoPermission();
      if (!ok) return false;
      await requestNotifyPermission();
      sessionRef.current = createSession(track);
      setUpdate(null);
      setNavigating(true);
      await startForegroundWatch(onFix, accuracyRef.current);
      return true;
    },
    [onFix],
  );

  const stopNavigation = useCallback(async () => {
    sessionRef.current = null;
    setNavigating(false);
    setUpdate(null);
    await stopBackgroundWatch();
    // on garde le watch avant-plan pour continuer d'afficher la position
  }, []);

  // Bascule avant/arrière-plan pendant une navigation (natif seulement).
  useEffect(() => {
    if (!isNative) return;
    const sub = CapApp.addListener("appStateChange", ({ isActive }) => {
      if (!sessionRef.current) return;
      if (isActive) {
        void stopBackgroundWatch();
        void startForegroundWatch(onFix, accuracyRef.current);
      } else {
        void stopForegroundWatch();
        void startBackgroundWatch(onFix, accuracyRef.current);
      }
    });
    return () => {
      void sub.then((h) => h.remove());
    };
  }, [onFix]);

  // Ménage à la fermeture.
  useEffect(
    () => () => {
      void stopForegroundWatch();
      void stopBackgroundWatch();
    },
    [],
  );

  return { fix, update, navigating, locating, locate, startNavigation, stopNavigation };
}
