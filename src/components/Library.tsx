/* ============================================================
   Library — on-device saved tracks (IndexedDB).
   Search, sort, open, compare, export, delete. Works offline.
   ============================================================ */
import { useEffect, useMemo, useState } from "react";
import { getAllTracks, deleteTrack, type SavedTrack } from "../lib/db";
import { fmtDistance } from "../lib/format";
import type { ExportFormat } from "../lib/export";

type SortKey = "recent" | "name" | "distance";

interface Props {
  open: boolean;
  version: number; // bump to reload
  compareId: string | null;
  onClose: () => void;
  onOpen: (rec: SavedTrack) => void;
  onCompare: (rec: SavedTrack | null) => void;
  onExport: (rec: SavedTrack, format: ExportFormat) => void;
}

export default function Library(p: Props) {
  const [items, setItems] = useState<SavedTrack[]>([]);
  const [query, setQuery] = useState("");
  const [sort, setSort] = useState<SortKey>("recent");

  useEffect(() => {
    if (!p.open) return;
    let live = true;
    getAllTracks().then((all) => live && setItems(all));
    return () => {
      live = false;
    };
  }, [p.open, p.version]);

  const shown = useMemo(() => {
    const q = query.trim().toLowerCase();
    const filtered = q ? items.filter((i) => i.name.toLowerCase().includes(q)) : items;
    const sorted = [...filtered];
    sorted.sort((a, b) => {
      if (sort === "name") return a.name.localeCompare(b.name);
      if (sort === "distance") return b.distance - a.distance;
      return b.updatedAt - a.updatedAt;
    });
    return sorted;
  }, [items, query, sort]);

  async function onDelete(rec: SavedTrack) {
    if (!window.confirm(`Delete "${rec.name}"? This can't be undone.`)) return;
    await deleteTrack(rec.id);
    if (p.compareId === rec.id) p.onCompare(null);
    setItems((prev) => prev.filter((i) => i.id !== rec.id));
  }

  return (
    <>
      <div className={`drawer-scrim${p.open ? " drawer-scrim--on" : ""}`} onClick={p.onClose} />
      <aside className={`drawer${p.open ? " drawer--on" : ""}`} aria-hidden={!p.open}>
        <div className="drawer__head">
          <div className="drawer__title">Library</div>
          <button className="iconx" onClick={p.onClose} aria-label="Close">
            ✕
          </button>
        </div>

        <div className="drawer__controls">
          <input
            className="search"
            placeholder="Search saved tracks…"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
          <select
            className="sortsel"
            value={sort}
            onChange={(e) => setSort(e.target.value as SortKey)}
          >
            <option value="recent">Recent</option>
            <option value="name">Name</option>
            <option value="distance">Distance</option>
          </select>
        </div>

        <div className="drawer__list">
          {shown.length === 0 && (
            <div className="drawer__empty">
              {items.length === 0
                ? "Nothing saved yet. Open or draw a track, then tap Save."
                : "No matches."}
            </div>
          )}
          {shown.map((rec) => (
            <div className="lib-item" key={rec.id}>
              <div
                className="lib-item__thumb"
                dangerouslySetInnerHTML={{ __html: rec.thumbnail }}
              />
              <div className="lib-item__body">
                <button className="lib-item__name" onClick={() => p.onOpen(rec)} title="Open">
                  {rec.name}
                </button>
                <div className="lib-item__meta num">
                  {fmtDistance(rec.distance)} · +{Math.round(rec.ascent)} m ·{" "}
                  {new Date(rec.updatedAt).toLocaleDateString()}
                </div>
                <div className="lib-item__actions">
                  <button className="chip" onClick={() => p.onOpen(rec)}>
                    Open
                  </button>
                  <button
                    className={`chip${p.compareId === rec.id ? " chip--on" : ""}`}
                    onClick={() => p.onCompare(p.compareId === rec.id ? null : rec)}
                  >
                    {p.compareId === rec.id ? "Comparing" : "Compare"}
                  </button>
                  <details className="menu">
                    <summary className="chip">Export ▾</summary>
                    <div className="menu__pop">
                      <button onClick={() => p.onExport(rec, "gpx")}>GPX</button>
                      <button onClick={() => p.onExport(rec, "kml")}>KML</button>
                      <button onClick={() => p.onExport(rec, "geojson")}>GeoJSON</button>
                    </div>
                  </details>
                  <button className="chip chip--danger" onClick={() => onDelete(rec)}>
                    Delete
                  </button>
                </div>
              </div>
            </div>
          ))}
        </div>
      </aside>
    </>
  );
}
