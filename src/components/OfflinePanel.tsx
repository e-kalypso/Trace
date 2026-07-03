/* ============================================================
   OfflinePanel — download the current map area for offline use,
   and manage saved regions (size + delete + total storage).
   ============================================================ */
import { useCallback, useEffect, useMemo, useState } from "react";
import type { Map as MlMap } from "maplibre-gl";
import {
  buildTileUrl,
  downloadTiles,
  evictTiles,
  fmtBytes,
  getVectorSource,
  storageEstimate,
  tilesForBbox,
  type VectorSourceInfo,
} from "../lib/offline";
import {
  deleteRegion,
  getAllRegions,
  saveRegion,
  type SavedRegion,
} from "../lib/db";

interface Props {
  open: boolean;
  onClose: () => void;
  map: MlMap | null;
  online: boolean;
}

const TILE_WARN = 1500; // warn beyond this many tiles

export default function OfflinePanel(p: Props) {
  const [detail, setDetail] = useState(2); // extra zoom levels beyond base
  const [regions, setRegions] = useState<SavedRegion[]>([]);
  const [storage, setStorage] = useState<{ usage: number; quota: number } | null>(null);
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState({ done: 0, total: 0 });
  const [src, setSrc] = useState<VectorSourceInfo | null>(null);
  const [tick, setTick] = useState(0); // re-read bounds when the map moves

  const reload = useCallback(() => {
    getAllRegions().then(setRegions);
    storageEstimate().then(setStorage);
  }, []);

  useEffect(() => {
    if (p.open) reload();
  }, [p.open, reload]);

  // Grab the vector tile template + follow map movement while open.
  useEffect(() => {
    if (!p.open || !p.map) return;
    getVectorSource(p.map).then(setSrc);
    const bump = () => setTick((t) => t + 1);
    p.map.on("moveend", bump);
    return () => {
      p.map?.off("moveend", bump);
    };
  }, [p.open, p.map]);

  const plan = useMemo(() => {
    if (!p.map || !src) return null;
    const b = p.map.getBounds();
    const bbox: [number, number, number, number] = [
      b.getWest(),
      b.getSouth(),
      b.getEast(),
      b.getNorth(),
    ];
    const zMin = Math.max(src.minzoom, Math.floor(p.map.getZoom()));
    const zMax = Math.min(src.maxzoom, zMin + detail);
    const tiles = tilesForBbox(bbox, zMin, zMax);
    return { bbox, zMin, zMax, count: tiles.length, tiles };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [p.map, src, detail, tick]);

  async function onDownload() {
    if (!p.map || !src || !plan) return;
    if (plan.count > TILE_WARN) {
      if (
        !window.confirm(
          `This area needs ${plan.count} tiles and may use a lot of space/data. Download anyway?`,
        )
      )
        return;
    }
    const name = window.prompt("Name this offline area", "My area")?.trim();
    if (!name) return;

    setBusy(true);
    setProgress({ done: 0, total: plan.count });
    try {
      const urls = plan.tiles.map((t) => buildTileUrl(src.template, t));
      const result = await downloadTiles(urls, (done, total) =>
        setProgress({ done, total }),
      );
      await saveRegion({
        id: crypto.randomUUID(),
        name,
        bbox: plan.bbox,
        zMin: plan.zMin,
        zMax: plan.zMax,
        tileUrls: result.tileUrls,
        bytes: result.bytes,
        createdAt: Date.now(),
      });
      reload();
    } finally {
      setBusy(false);
    }
  }

  async function onDelete(r: SavedRegion) {
    if (!window.confirm(`Delete offline area "${r.name}"?`)) return;
    await evictTiles(r.tileUrls);
    await deleteRegion(r.id);
    reload();
  }

  const totalRegionBytes = regions.reduce((a, r) => a + r.bytes, 0);

  return (
    <>
      <div className={`drawer-scrim${p.open ? " drawer-scrim--on" : ""}`} onClick={p.onClose} />
      <aside className={`drawer${p.open ? " drawer--on" : ""}`} aria-hidden={!p.open}>
        <div className="drawer__head">
          <div className="drawer__title">Offline maps</div>
          <button className="iconx" onClick={p.onClose} aria-label="Close">
            ✕
          </button>
        </div>

        <div className="offline-new">
          <div className="offline-hint">
            Move and zoom the map to the area you want, then download it to view
            offline.
          </div>

          <label className="offline-field">
            <span>Detail</span>
            <input
              type="range"
              min={0}
              max={3}
              value={detail}
              onChange={(e) => setDetail(Number(e.target.value))}
            />
            <span className="num">+{detail}</span>
          </label>

          <div className="offline-plan num">
            {plan ? (
              <>
                zoom {plan.zMin}–{plan.zMax} · {plan.count} tiles
                {plan.count > TILE_WARN && <span className="warn-inline"> · large</span>}
              </>
            ) : (
              "Preparing…"
            )}
          </div>

          {busy ? (
            <div className="offline-progress">
              <div
                className="offline-progress__bar"
                style={{
                  width: `${progress.total ? (progress.done / progress.total) * 100 : 0}%`,
                }}
              />
              <span className="offline-progress__label num">
                {progress.done}/{progress.total}
              </span>
            </div>
          ) : (
            <button
              className="btn btn--primary offline-dl"
              onClick={onDownload}
              disabled={!p.online || !plan || plan.count === 0}
            >
              {p.online ? "Download this area" : "Go online to download"}
            </button>
          )}
        </div>

        <div className="offline-storage num">
          {regions.length} area{regions.length === 1 ? "" : "s"} · {fmtBytes(totalRegionBytes)}
          {storage && (
            <span className="offline-storage__quota">
              {" "}
              · {fmtBytes(storage.usage)} of {fmtBytes(storage.quota)} used
            </span>
          )}
        </div>

        <div className="drawer__list">
          {regions.length === 0 && (
            <div className="drawer__empty">No offline areas yet.</div>
          )}
          {regions.map((r) => (
            <div className="region-item" key={r.id}>
              <div className="region-item__body">
                <div className="region-item__name">{r.name}</div>
                <div className="region-item__meta num">
                  zoom {r.zMin}–{r.zMax} · {r.tileUrls.length} tiles · {fmtBytes(r.bytes)}
                </div>
              </div>
              <button className="chip chip--danger" onClick={() => onDelete(r)}>
                Delete
              </button>
            </div>
          ))}
        </div>
      </aside>
    </>
  );
}
