/* ============================================================
   Fournisseurs de fonds de carte.
   Tous sans clé ni compte, sauf Apple Plans (MapKit JS) qui
   nécessitera une clé du compte Apple Developer — l'entrée
   existe déjà pour que l'architecture soit prête.
   ============================================================ */
import type { StyleSpecification } from "maplibre-gl";

export interface MapProvider {
  id: string;
  name: string;
  /** URL de style vectoriel OU style raster construit */
  style: string | StyleSpecification;
  /** true si les tuiles peuvent être mises en cache hors ligne */
  offlineCapable: boolean;
  /** non sélectionnable tant que la clé n'est pas configurée */
  disabled?: boolean;
  note?: string;
}

function rasterStyle(
  tiles: string[],
  attribution: string,
  maxzoom = 17,
): StyleSpecification {
  return {
    version: 8,
    sources: {
      raster: { type: "raster", tiles, tileSize: 256, attribution, maxzoom },
    },
    layers: [{ id: "raster", type: "raster", source: "raster" }],
  };
}

export const PROVIDERS: MapProvider[] = [
  {
    id: "plan",
    name: "Plan",
    style: "https://tiles.openfreemap.org/styles/liberty",
    offlineCapable: true,
  },
  {
    id: "clair",
    name: "Clair",
    style: "https://tiles.openfreemap.org/styles/positron",
    offlineCapable: true,
  },
  {
    id: "topo",
    name: "Topo",
    style: rasterStyle(
      [
        "https://a.tile.opentopomap.org/{z}/{x}/{y}.png",
        "https://b.tile.opentopomap.org/{z}/{x}/{y}.png",
        "https://c.tile.opentopomap.org/{z}/{x}/{y}.png",
      ],
      "© OpenStreetMap, SRTM | © OpenTopoMap (CC-BY-SA)",
      16,
    ),
    offlineCapable: false,
  },
  {
    id: "satellite",
    name: "Satellite",
    style: rasterStyle(
      [
        "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
      ],
      "© Esri, Maxar, Earthstar Geographics",
      18,
    ),
    offlineCapable: false,
  },
  {
    id: "apple",
    name: "Apple Plans",
    style: "https://tiles.openfreemap.org/styles/liberty", // placeholder
    offlineCapable: false,
    disabled: true,
    note: "Nécessite une clé MapKit JS (compte Apple Developer)",
  },
];

export function getProvider(id: string): MapProvider {
  return PROVIDERS.find((p) => p.id === id && !p.disabled) ?? PROVIDERS[0];
}
