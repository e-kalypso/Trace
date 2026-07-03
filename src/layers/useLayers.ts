/* ============================================================
   Calques de tracés — comme les calques d'un éditeur photo.
   Le PREMIER calque visible est le tracé actif (navigation).
   Persistés en IndexedDB : tout marche hors ligne.
   ============================================================ */
import { useCallback, useEffect, useMemo, useState } from "react";
import { parseGpx, trackFromCoords, type Track } from "../lib/gpx";
import { toGpx } from "../lib/export";
import { trackBbox } from "../lib/thumbnail";
import {
  deleteTrack,
  getAllTracks,
  saveTrack,
  type SavedTrack,
} from "../lib/db";

/* Palette iOS — attribuée à la création, stable ensuite. */
export const LAYER_COLORS = [
  "#0a84ff",
  "#ff9f0a",
  "#30d158",
  "#bf5af2",
  "#ff375f",
  "#40c8e0",
];

export interface Layer {
  id: string;
  name: string;
  color: string;
  visible: boolean;
  order: number;
  track: Track;
}

interface StoredExtras {
  color?: string;
  visible?: boolean;
  order?: number;
}

function toRecord(l: Layer): SavedTrack & StoredExtras {
  const s = l.track.stats;
  return {
    id: l.id,
    name: l.name,
    createdAt: Date.now(),
    updatedAt: Date.now(),
    distance: s.distance,
    ascent: s.ascent,
    hasEle: s.maxEle != null,
    hasTime: s.hasTime,
    pointCount: s.pointCount,
    bbox: trackBbox(l.track),
    gpx: toGpx(l.track),
    thumbnail: "",
    color: l.color,
    visible: l.visible,
    order: l.order,
  };
}

export function useLayers() {
  const [layers, setLayers] = useState<Layer[]>([]);
  const [loaded, setLoaded] = useState(false);

  // Chargement initial depuis IndexedDB.
  useEffect(() => {
    getAllTracks()
      .then((recs) => {
        const ls: Layer[] = [];
        for (const rec of recs as (SavedTrack & StoredExtras)[]) {
          try {
            const parsed = parseGpx(rec.gpx, `${rec.name}.gpx`);
            const track = parsed.tracks[0];
            if (!track) continue;
            ls.push({
              id: rec.id,
              name: rec.name,
              color: rec.color ?? LAYER_COLORS[ls.length % LAYER_COLORS.length],
              visible: rec.visible ?? true,
              order: rec.order ?? ls.length,
              track: { ...track, name: rec.name },
            });
          } catch {
            /* fichier corrompu : ignoré */
          }
        }
        ls.sort((a, b) => a.order - b.order);
        setLayers(ls);
      })
      .finally(() => setLoaded(true));
  }, []);

  const persist = useCallback((ls: Layer[]) => {
    ls.forEach((l, i) => {
      void saveTrack(toRecord({ ...l, order: i }));
    });
  }, []);

  const commit = useCallback(
    (ls: Layer[]) => {
      const ordered = ls.map((l, i) => ({ ...l, order: i }));
      setLayers(ordered);
      persist(ordered);
    },
    [persist],
  );

  const addFromGpxText = useCallback(
    (text: string, fileName: string): Layer | null => {
      try {
        const parsed = parseGpx(text, fileName);
        const track = parsed.tracks[0];
        if (!track) return null;
        const layer: Layer = {
          id: crypto.randomUUID(),
          name: track.name || parsed.name,
          color: LAYER_COLORS[layers.length % LAYER_COLORS.length],
          visible: true,
          order: layers.length,
          track,
        };
        commit([...layers, layer]);
        return layer;
      } catch {
        return null;
      }
    },
    [layers, commit],
  );

  const remove = useCallback(
    (id: string) => {
      void deleteTrack(id);
      commit(layers.filter((l) => l.id !== id));
    },
    [layers, commit],
  );

  const toggleVisible = useCallback(
    (id: string) => {
      commit(layers.map((l) => (l.id === id ? { ...l, visible: !l.visible } : l)));
    },
    [layers, commit],
  );

  const reverse = useCallback(
    (id: string) => {
      commit(
        layers.map((l) => {
          if (l.id !== id) return l;
          const coords = [...l.track.points]
            .reverse()
            .map((p) => (p.ele != null ? [p.lng, p.lat, p.ele] : [p.lng, p.lat]));
          const track = { ...trackFromCoords(l.name, coords), name: l.name };
          return { ...l, track };
        }),
      );
    },
    [layers, commit],
  );

  const move = useCallback(
    (id: string, dir: -1 | 1) => {
      const idx = layers.findIndex((l) => l.id === id);
      const to = idx + dir;
      if (idx < 0 || to < 0 || to >= layers.length) return;
      const ls = [...layers];
      [ls[idx], ls[to]] = [ls[to], ls[idx]];
      commit(ls);
    },
    [layers, commit],
  );

  const rename = useCallback(
    (id: string, name: string) => {
      commit(layers.map((l) => (l.id === id ? { ...l, name } : l)));
    },
    [layers, commit],
  );

  /** Le tracé actif = premier calque visible. */
  const activeLayer = useMemo(() => layers.find((l) => l.visible) ?? null, [layers]);

  return {
    layers,
    loaded,
    activeLayer,
    addFromGpxText,
    remove,
    toggleVisible,
    reverse,
    move,
    rename,
  };
}
