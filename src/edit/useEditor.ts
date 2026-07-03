/* ============================================================
   useEditor — the route-editing controller.
   Holds the EditRoute with undo/redo, and runs snapping
   (async) as you draw / drag, with straight-line fallback
   when offline or when routing fails.
   ============================================================ */
import { useCallback, useRef, useState } from "react";
import {
  routeSegment,
  straightSegment,
  type LngLat,
  type RouteProfile,
} from "../lib/routing";
import {
  emptyRoute,
  segFromSnap,
  withAnchorAppended,
  withAnchorDeleted,
  withAnchorMoved,
  withProfile,
  withReversed,
  withWaypoint,
  withoutWaypoint,
  newWaypointId,
  type Anchor,
  type EditRoute,
  type Segment,
} from "./route";

export type EditMode = "view" | "draw" | "waypoint";

interface Hist {
  past: EditRoute[];
  present: EditRoute;
  future: EditRoute[];
}

export function useEditor() {
  const [hist, setHist] = useState<Hist>({
    past: [],
    present: emptyRoute("hike"),
    future: [],
  });
  const [mode, setMode] = useState<EditMode>("view");
  const [routing, setRouting] = useState(0); // in-flight snap count
  const [lastFellBack, setLastFellBack] = useState(false);

  const presentRef = useRef(hist.present);
  presentRef.current = hist.present;

  const commit = useCallback((next: EditRoute) => {
    setHist((h) => ({ past: [...h.past, h.present], present: next, future: [] }));
  }, []);

  /** Resolve geometry a->b, snapping unless straight/offline; fall back gracefully. */
  const resolveSeg = useCallback(
    async (a: LngLat, b: LngLat, profile: RouteProfile): Promise<Segment> => {
      if (profile === "straight" || !navigator.onLine) {
        if (profile !== "straight") setLastFellBack(true);
        return segFromSnap(straightSegment(a, b));
      }
      setRouting((n) => n + 1);
      try {
        const snap = await routeSegment(a, b, profile);
        setLastFellBack(false);
        return segFromSnap(snap);
      } catch {
        setLastFellBack(true);
        return segFromSnap(straightSegment(a, b));
      } finally {
        setRouting((n) => n - 1);
      }
    },
    [],
  );

  const addAnchor = useCallback(
    async (p: LngLat) => {
      const route = presentRef.current;
      const anchor: Anchor = { lng: p.lng, lat: p.lat };
      if (route.anchors.length === 0) {
        commit(withAnchorAppended(route, anchor, null));
        return;
      }
      const prev = route.anchors[route.anchors.length - 1];
      const seg = await resolveSeg(prev, anchor, route.profile);
      // present may have advanced if the user clicked again; recompute against latest
      commit(withAnchorAppended(presentRef.current, anchor, seg));
    },
    [commit, resolveSeg],
  );

  const moveAnchor = useCallback(
    async (idx: number, p: LngLat) => {
      const route = presentRef.current;
      const anchor: Anchor = { lng: p.lng, lat: p.lat };
      const prev = idx > 0 ? route.anchors[idx - 1] : null;
      const next = idx < route.anchors.length - 1 ? route.anchors[idx + 1] : null;
      const before = prev ? await resolveSeg(prev, anchor, route.profile) : null;
      const after = next ? await resolveSeg(anchor, next, route.profile) : null;
      commit(withAnchorMoved(presentRef.current, idx, anchor, before, after));
    },
    [commit, resolveSeg],
  );

  const deleteAnchor = useCallback(
    async (idx: number) => {
      const route = presentRef.current;
      const isMiddle = idx > 0 && idx < route.anchors.length - 1;
      const bridge = isMiddle
        ? await resolveSeg(route.anchors[idx - 1], route.anchors[idx + 1], route.profile)
        : null;
      commit(withAnchorDeleted(presentRef.current, idx, bridge));
    },
    [commit, resolveSeg],
  );

  const setProfile = useCallback(
    async (profile: RouteProfile) => {
      const route = presentRef.current;
      // change profile, then re-resolve every segment
      if (route.anchors.length < 2) {
        commit(withProfile(route, profile));
        return;
      }
      const segs: Segment[] = [];
      for (let i = 0; i < route.anchors.length - 1; i++) {
        segs.push(await resolveSeg(route.anchors[i], route.anchors[i + 1], profile));
      }
      commit({ ...presentRef.current, profile, segments: segs });
    },
    [commit, resolveSeg],
  );

  const reverse = useCallback(() => commit(withReversed(presentRef.current)), [commit]);

  const clear = useCallback(() => {
    commit(emptyRoute(presentRef.current.profile));
  }, [commit]);

  const addWaypoint = useCallback(
    (p: LngLat, name: string) => {
      commit(
        withWaypoint(presentRef.current, {
          id: newWaypointId(),
          lng: p.lng,
          lat: p.lat,
          name,
        }),
      );
    },
    [commit],
  );

  const removeWaypoint = useCallback(
    (id: string) => commit(withoutWaypoint(presentRef.current, id)),
    [commit],
  );

  const undo = useCallback(() => {
    setHist((h) => {
      if (h.past.length === 0) return h;
      const prev = h.past[h.past.length - 1];
      return {
        past: h.past.slice(0, -1),
        present: prev,
        future: [h.present, ...h.future],
      };
    });
  }, []);

  const redo = useCallback(() => {
    setHist((h) => {
      if (h.future.length === 0) return h;
      const next = h.future[0];
      return {
        past: [...h.past, h.present],
        present: next,
        future: h.future.slice(1),
      };
    });
  }, []);

  return {
    route: hist.present,
    mode,
    setMode,
    isRouting: routing > 0,
    lastFellBack,
    canUndo: hist.past.length > 0,
    canRedo: hist.future.length > 0,
    addAnchor,
    moveAnchor,
    deleteAnchor,
    setProfile,
    reverse,
    clear,
    addWaypoint,
    removeWaypoint,
    undo,
    redo,
  };
}
