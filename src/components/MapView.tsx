/* ============================================================
   MapView v2 — carte plein écran.
   - Fond de carte commutable (les sources/couches custom sont
     ré-injectées après chaque changement de style)
   - Un trait par calque visible (le calque actif est renforcé)
   - Position de l'utilisateur (point bleu + cap + halo)
   - Ligne d'approche pointillée ("rejoindre…")
   - Suivi caméra doux pendant la navigation (nord en haut,
     recentrage throttlé : bon pour la batterie)
   ============================================================ */
import { useEffect, useRef } from "react";
import maplibregl, { Map as MlMap, Marker } from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import type { FeatureCollection, Feature } from "geojson";
import type { Layer } from "../layers/useLayers";
import type { GeoFix } from "../lib/geo";
import { getProvider } from "../lib/providers";

interface Props {
  providerId: string;
  layers: Layer[];
  activeLayerId: string | null;
  fix: GeoFix | null;
  navigating: boolean;
  /** [lng,lat][] pointillé vers le tracé / départ, ou null */
  approach: number[][] | null;
  onMapReady?: (map: MlMap) => void;
}

const LAYERS_SRC = "trace-layers";
const APPROACH_SRC = "trace-approach";

function layersToFC(layers: Layer[]): FeatureCollection {
  const features: Feature[] = [];
  // dessine du bas vers le haut : dernier calque d'abord, actif en dernier
  const visible = layers.filter((l) => l.visible);
  const active = visible[0] ?? null;
  for (const l of [...visible].reverse()) {
    features.push({
      type: "Feature",
      properties: {
        color: l.color,
        width: l.id === active?.id ? 5 : 3,
        opacity: l.id === active?.id ? 1 : 0.55,
      },
      geometry: {
        type: "LineString",
        coordinates: l.track.points.map((p) => [p.lng, p.lat]),
      },
    });
  }
  return { type: "FeatureCollection", features };
}

export default function MapView(p: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<MlMap | null>(null);
  const styleReady = useRef(false);
  const userMarker = useRef<Marker | null>(null);
  const startMarker = useRef<Marker | null>(null);
  const finishMarker = useRef<Marker | null>(null);
  const lastCamMove = useRef(0);
  const pRef = useRef(p);
  pRef.current = p;

  /* création unique */
  useEffect(() => {
    if (!containerRef.current || mapRef.current) return;
    const map = new maplibregl.Map({
      container: containerRef.current,
      style: getProvider(p.providerId).style,
      center: [6.87, 45.92],
      zoom: 11,
      attributionControl: { compact: true },
      dragRotate: false,
      pitchWithRotate: false,
      fadeDuration: 0, // moins d'animations = moins de GPU
    });
    map.touchZoomRotate.disableRotation();

    // "styledata" couvre le chargement initial ET chaque setStyle ;
    // l'injection est idempotente donc sans risque d'appel multiple.
    map.on("styledata", () => {
      styleReady.current = true;
      injectSourcesAndLayers(map);
      renderLayers();
      renderApproach();
    });

    mapRef.current = map;
    if (import.meta.env.DEV) (window as unknown as { __map?: MlMap }).__map = map;
    p.onMapReady?.(map);
    return () => {
      map.remove();
      mapRef.current = null;
      styleReady.current = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function injectSourcesAndLayers(map: MlMap) {
    if (!map.getSource(LAYERS_SRC)) {
      map.addSource(LAYERS_SRC, {
        type: "geojson",
        data: { type: "FeatureCollection", features: [] },
      });
    }
    if (!map.getSource(APPROACH_SRC)) {
      map.addSource(APPROACH_SRC, {
        type: "geojson",
        data: { type: "FeatureCollection", features: [] },
      });
    }
    if (!map.getLayer("trk-casing")) {
      map.addLayer({
        id: "trk-casing",
        type: "line",
        source: LAYERS_SRC,
        layout: { "line-cap": "round", "line-join": "round" },
        paint: {
          "line-color": "#ffffff",
          "line-width": ["+", ["get", "width"], 3],
          "line-opacity": 0.6,
        },
      });
      map.addLayer({
        id: "trk-line",
        type: "line",
        source: LAYERS_SRC,
        layout: { "line-cap": "round", "line-join": "round" },
        paint: {
          "line-color": ["get", "color"],
          "line-width": ["get", "width"],
          "line-opacity": ["get", "opacity"],
        },
      });
      map.addLayer({
        id: "approach-line",
        type: "line",
        source: APPROACH_SRC,
        layout: { "line-cap": "round", "line-join": "round" },
        paint: {
          "line-color": "#0a84ff",
          "line-width": 4,
          "line-dasharray": [0.5, 2],
        },
      });
    }
  }

  function renderLayers() {
    const map = mapRef.current;
    if (!map || !styleReady.current) return;
    const src = map.getSource(LAYERS_SRC) as maplibregl.GeoJSONSource | undefined;
    src?.setData(layersToFC(pRef.current.layers));

    // départ / arrivée du calque actif
    startMarker.current?.remove();
    finishMarker.current?.remove();
    startMarker.current = null;
    finishMarker.current = null;
    const active = pRef.current.layers.find(
      (l) => l.id === pRef.current.activeLayerId && l.visible,
    );
    if (active && active.track.points.length > 1) {
      const pts = active.track.points;
      startMarker.current = new maplibregl.Marker({ element: endDot("#34c759") })
        .setLngLat([pts[0].lng, pts[0].lat])
        .addTo(map);
      finishMarker.current = new maplibregl.Marker({ element: endDot("#1c1c1e") })
        .setLngLat([pts[pts.length - 1].lng, pts[pts.length - 1].lat])
        .addTo(map);
    }
  }

  function renderApproach() {
    const map = mapRef.current;
    if (!map || !styleReady.current) return;
    const src = map.getSource(APPROACH_SRC) as maplibregl.GeoJSONSource | undefined;
    const coords = pRef.current.approach;
    src?.setData({
      type: "FeatureCollection",
      features:
        coords && coords.length >= 2
          ? [
              {
                type: "Feature",
                properties: {},
                geometry: { type: "LineString", coordinates: coords },
              },
            ]
          : [],
    });
  }

  /* changement de fond de carte (pas au montage : style déjà passé au constructeur) */
  const firstProvider = useRef(true);
  useEffect(() => {
    if (firstProvider.current) {
      firstProvider.current = false;
      return;
    }
    const map = mapRef.current;
    if (!map) return;
    styleReady.current = false;
    map.setStyle(getProvider(p.providerId).style, { diff: false });
    // "styledata" ré-injecte tout
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [p.providerId]);

  /* rendu des calques */
  useEffect(() => {
    renderLayers();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [p.layers, p.activeLayerId]);

  /* cadrage initial sur le calque actif (hors navigation) */
  useEffect(() => {
    const map = mapRef.current;
    if (!map || p.navigating) return;
    const active = p.layers.find((l) => l.id === p.activeLayerId && l.visible);
    if (!active || active.track.points.length < 2) return;
    const b = new maplibregl.LngLatBounds();
    for (const pt of active.track.points) b.extend([pt.lng, pt.lat]);
    map.fitBounds(b, { padding: { top: 90, bottom: 220, left: 40, right: 40 }, duration: 600, maxZoom: 15 });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [p.activeLayerId]);

  /* ligne d'approche */
  useEffect(() => {
    renderApproach();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [p.approach]);

  /* position utilisateur + suivi caméra */
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    if (!p.fix) {
      userMarker.current?.remove();
      userMarker.current = null;
      return;
    }
    if (!userMarker.current) {
      userMarker.current = new maplibregl.Marker({ element: userDot() });
    }
    const el = userMarker.current.getElement();
    const cone = el.querySelector(".user-dot__cone") as HTMLElement | null;
    if (cone) {
      if (p.fix.heading != null) {
        cone.style.display = "block";
        cone.style.transform = `rotate(${p.fix.heading}deg)`;
      } else cone.style.display = "none";
    }
    userMarker.current.setLngLat([p.fix.lng, p.fix.lat]).addTo(map);

    // suivi caméra pendant la nav : throttlé à 2,5 s, nord en haut
    if (p.navigating) {
      const now = Date.now();
      if (now - lastCamMove.current > 2500) {
        lastCamMove.current = now;
        map.easeTo({
          center: [p.fix.lng, p.fix.lat],
          zoom: Math.max(map.getZoom(), 14.5),
          duration: 800,
        });
      }
    }
  }, [p.fix, p.navigating]);

  return <div ref={containerRef} style={{ position: "absolute", inset: 0 }} />;
}

/* --- marqueurs DOM --- */

function userDot(): HTMLElement {
  const el = document.createElement("div");
  el.className = "user-dot";
  el.innerHTML =
    '<div class="user-dot__pulse"></div><div class="user-dot__cone"></div><div class="user-dot__core"></div>';
  return el;
}

function endDot(color: string): HTMLElement {
  const el = document.createElement("div");
  el.className = "end-dot";
  el.style.background = color;
  return el;
}
