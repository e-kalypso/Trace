/* ============================================================
   MapView — MapLibre GL map with free OpenFreeMap tiles.
   Responsibilities:
   - View: draw the loaded track (ink) + start/finish + hover dot,
     two-way linked with the elevation profile.
   - Edit: draw the active route (coral), draggable anchors,
     waypoints, and click-to-add.
   ============================================================ */
import { useEffect, useRef } from "react";
import maplibregl, { Map as MlMap, LngLatBounds, Marker } from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import type { FeatureCollection } from "geojson";
import type { Track } from "../lib/gpx";
import type { LngLat } from "../lib/routing";
import { routeToGeoJSON, type EditRoute } from "../edit/route";
import type { EditMode } from "../edit/useEditor";

const STYLE_URL = "https://tiles.openfreemap.org/styles/positron";
const SRC = "trace-track";
const EDIT_SRC = "trace-edit";
const CMP_SRC = "trace-compare";

interface Props {
  geojson: FeatureCollection | null;
  compareGeojson: FeatureCollection | null; // overlay a second track
  track: Track | null; // GPX track: start/finish markers + fit-to-bounds
  focusTrack: Track | null; // track the scrub index indexes into (edit or GPX)
  hoverIdx: number | null;
  onHover: (idx: number | null) => void;
  // edit
  editRoute: EditRoute | null;
  editMode: EditMode;
  onMapClick: (p: LngLat) => void;
  onAnchorDragEnd: (idx: number, p: LngLat) => void;
  onAnchorClick: (idx: number) => void;
  onWaypointClick: (id: string) => void;
  onReady?: (map: MlMap) => void;
}

export default function MapView(props: Props) {
  const { geojson, compareGeojson, track, focusTrack, hoverIdx, editRoute, editMode } =
    props;
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<MlMap | null>(null);
  const readyRef = useRef(false);
  const startMarker = useRef<Marker | null>(null);
  const finishMarker = useRef<Marker | null>(null);
  const hoverMarker = useRef<Marker | null>(null);
  const anchorMarkers = useRef<Marker[]>([]);
  const waypointMarkers = useRef<Marker[]>([]);

  // Latest values for the long-lived map event handlers.
  const focusRef = useRef<Track | null>(focusTrack);
  const modeRef = useRef<EditMode>(editMode);
  const pRef = useRef(props);
  focusRef.current = focusTrack;
  modeRef.current = editMode;
  pRef.current = props;

  // Create the map once.
  useEffect(() => {
    if (!containerRef.current || mapRef.current) return;
    const map = new maplibregl.Map({
      container: containerRef.current,
      style: STYLE_URL,
      center: [6.86, 45.83],
      zoom: 10,
      attributionControl: { compact: true },
      dragRotate: false,
    });
    map.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-right");

    map.on("load", () => {
      readyRef.current = true;
      map.addSource(SRC, { type: "geojson", data: emptyFC() });
      map.addSource(CMP_SRC, { type: "geojson", data: emptyFC() });
      map.addSource(EDIT_SRC, { type: "geojson", data: emptyFC() });

      map.addLayer({
        id: "track-halo",
        type: "line",
        source: SRC,
        layout: { "line-cap": "round", "line-join": "round" },
        paint: {
          "line-color": readColor("--track-halo", "rgba(47,74,92,0.18)"),
          "line-width": 9,
          "line-blur": 1,
        },
      });
      map.addLayer({
        id: "track-line",
        type: "line",
        source: SRC,
        layout: { "line-cap": "round", "line-join": "round" },
        paint: { "line-color": readColor("--track", "#2f4a5c"), "line-width": 3.5 },
      });
      // comparison track (teal, dashed) sits above the base track
      map.addLayer({
        id: "compare-line",
        type: "line",
        source: CMP_SRC,
        layout: { "line-cap": "round", "line-join": "round" },
        paint: {
          "line-color": readColor("--compare", "#2f8fa8"),
          "line-width": 3,
          "line-dasharray": [2, 1.5],
        },
      });
      // edit line (coral) sits on top
      map.addLayer({
        id: "edit-halo",
        type: "line",
        source: EDIT_SRC,
        layout: { "line-cap": "round", "line-join": "round" },
        paint: {
          "line-color": readColor("--accent", "#e8663c"),
          "line-width": 10,
          "line-opacity": 0.18,
          "line-blur": 1,
        },
      });
      map.addLayer({
        id: "edit-line",
        type: "line",
        source: EDIT_SRC,
        layout: { "line-cap": "round", "line-join": "round" },
        paint: { "line-color": readColor("--accent", "#e8663c"), "line-width": 3.5 },
      });

      renderView();
      renderCompare();
      renderEdit();
      pRef.current.onReady?.(map);
    });

    map.on("mousemove", (e) => {
      if (modeRef.current !== "view") return;
      const t = focusRef.current;
      if (!t || t.points.length < 2) return;
      pRef.current.onHover(nearestPointIdx(t, e.lngLat.lng, e.lngLat.lat));
    });
    map.on("mouseout", () => {
      if (modeRef.current === "view") pRef.current.onHover(null);
    });

    map.on("click", (e) => {
      if (modeRef.current === "draw" || modeRef.current === "waypoint") {
        pRef.current.onMapClick({ lng: e.lngLat.lng, lat: e.lngLat.lat });
      }
    });

    mapRef.current = map;
    if (import.meta.env.DEV) (window as unknown as { __map?: MlMap }).__map = map;
    return () => {
      map.remove();
      mapRef.current = null;
      readyRef.current = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Cursor hint for edit modes.
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    map.getCanvas().style.cursor =
      editMode === "draw" || editMode === "waypoint" ? "crosshair" : "";
  }, [editMode]);

  function renderView() {
    const map = mapRef.current;
    if (!map || !readyRef.current) return;
    (map.getSource(SRC) as maplibregl.GeoJSONSource | undefined)?.setData(
      geojson ?? emptyFC(),
    );

    startMarker.current?.remove();
    finishMarker.current?.remove();
    startMarker.current = null;
    finishMarker.current = null;

    if (track && track.points.length > 1) {
      const first = track.points[0];
      const last = track.points[track.points.length - 1];
      startMarker.current = new maplibregl.Marker({ element: dot("start") })
        .setLngLat([first.lng, first.lat])
        .addTo(map);
      finishMarker.current = new maplibregl.Marker({ element: dot("finish") })
        .setLngLat([last.lng, last.lat])
        .addTo(map);

      const b = new LngLatBounds();
      for (const p of track.points) b.extend([p.lng, p.lat]);
      map.fitBounds(b, { padding: 64, duration: 700, maxZoom: 15 });
    }
  }

  function renderCompare() {
    const map = mapRef.current;
    if (!map || !readyRef.current) return;
    (map.getSource(CMP_SRC) as maplibregl.GeoJSONSource | undefined)?.setData(
      compareGeojson ?? emptyFC(),
    );
  }

  function renderEdit() {
    const map = mapRef.current;
    if (!map || !readyRef.current) return;
    (map.getSource(EDIT_SRC) as maplibregl.GeoJSONSource | undefined)?.setData(
      editRoute ? routeToGeoJSON(editRoute) : emptyFC(),
    );

    // rebuild anchor markers
    anchorMarkers.current.forEach((m) => m.remove());
    anchorMarkers.current = [];
    waypointMarkers.current.forEach((m) => m.remove());
    waypointMarkers.current = [];
    if (!editRoute) return;

    editRoute.anchors.forEach((a, i) => {
      const el = anchorEl();
      let dragged = false;
      const m = new maplibregl.Marker({ element: el, draggable: true })
        .setLngLat([a.lng, a.lat])
        .addTo(map);
      m.on("dragstart", () => {
        dragged = true;
      });
      m.on("dragend", () => {
        const ll = m.getLngLat();
        pRef.current.onAnchorDragEnd(i, { lng: ll.lng, lat: ll.lat });
        setTimeout(() => (dragged = false), 0);
      });
      el.addEventListener("click", (ev) => {
        ev.stopPropagation();
        if (!dragged) pRef.current.onAnchorClick(i);
      });
      anchorMarkers.current.push(m);
    });

    editRoute.waypoints.forEach((w) => {
      const el = waypointEl(w.name);
      const m = new maplibregl.Marker({ element: el, anchor: "bottom" })
        .setLngLat([w.lng, w.lat])
        .addTo(map);
      el.addEventListener("click", (ev) => {
        ev.stopPropagation();
        pRef.current.onWaypointClick(w.id);
      });
      waypointMarkers.current.push(m);
    });
  }

  useEffect(() => {
    renderView();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [geojson, track]);

  useEffect(() => {
    renderCompare();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [compareGeojson]);

  useEffect(() => {
    renderEdit();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [editRoute]);

  // coral hover marker (scrub link, indexes into the focus track)
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !readyRef.current) return;
    if (hoverIdx == null || !focusTrack || !focusTrack.points[hoverIdx]) {
      hoverMarker.current?.remove();
      hoverMarker.current = null;
      return;
    }
    const p = focusTrack.points[hoverIdx];
    if (!hoverMarker.current) {
      hoverMarker.current = new maplibregl.Marker({ element: hoverDot() });
    }
    hoverMarker.current.setLngLat([p.lng, p.lat]).addTo(map);
  }, [hoverIdx, focusTrack]);

  return <div ref={containerRef} style={{ position: "absolute", inset: 0 }} />;
}

/* --- helpers --- */

function emptyFC(): FeatureCollection {
  return { type: "FeatureCollection", features: [] };
}

function nearestPointIdx(track: Track, lng: number, lat: number): number {
  const pts = track.points;
  const cosLat = Math.cos((lat * Math.PI) / 180);
  let best = 0;
  let bestD = Infinity;
  for (let i = 0; i < pts.length; i++) {
    const dx = (pts[i].lng - lng) * cosLat;
    const dy = pts[i].lat - lat;
    const d = dx * dx + dy * dy;
    if (d < bestD) {
      bestD = d;
      best = i;
    }
  }
  return best;
}

function readColor(varName: string, fallback: string): string {
  const v = getComputedStyle(document.documentElement).getPropertyValue(varName).trim();
  return v || fallback;
}

function dot(kind: "start" | "finish"): HTMLElement {
  const el = document.createElement("div");
  el.className = `trace-marker trace-marker--${kind}`;
  el.textContent = kind === "start" ? "S" : "F";
  return el;
}

function hoverDot(): HTMLElement {
  const el = document.createElement("div");
  el.className = "trace-hover";
  return el;
}

function anchorEl(): HTMLElement {
  const el = document.createElement("div");
  el.className = "edit-anchor";
  return el;
}

function waypointEl(name: string): HTMLElement {
  const el = document.createElement("div");
  el.className = "edit-waypoint";
  el.innerHTML = `<span class="edit-waypoint__pin"></span><span class="edit-waypoint__label">${escapeHtml(
    name,
  )}</span>`;
  return el;
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) =>
    c === "&"
      ? "&amp;"
      : c === "<"
        ? "&lt;"
        : c === ">"
          ? "&gt;"
          : c === '"'
            ? "&quot;"
            : "&#39;",
  );
}
