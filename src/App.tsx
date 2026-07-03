/* ============================================================
   Trace — app shell.
   View a GPX (ink) and/or draw & edit a route (coral) with
   trail snapping, an elevation profile, and live stats.
   ============================================================ */
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { FeatureCollection } from "geojson";
import type { Map as MlMap } from "maplibre-gl";
import MapView from "./components/MapView";
import ElevationProfile from "./components/ElevationProfile";
import ToolRail from "./components/ToolRail";
import Library from "./components/Library";
import OfflinePanel from "./components/OfflinePanel";
import { parseGpx, type ParsedGpx, type Track } from "./lib/gpx";
import { routeToTrack } from "./edit/route";
import { useEditor } from "./edit/useEditor";
import { useOnline } from "./lib/useOnline";
import type { LngLat } from "./lib/routing";
import { saveTrack, type SavedTrack } from "./lib/db";
import { exportTrack, toGpx, type ExportFormat } from "./lib/export";
import { makeThumbnail, trackBbox } from "./lib/thumbnail";
import { fmtDistance, fmtDuration, fmtElevation, fmtSpeed } from "./lib/format";
import "./App.css";

/** A track as a GeoJSON line (for the compare overlay). */
function trackToLineFC(track: Track): FeatureCollection {
  return {
    type: "FeatureCollection",
    features: [
      {
        type: "Feature",
        properties: {},
        geometry: {
          type: "LineString",
          coordinates: track.points.map((p) => [p.lng, p.lat]),
        },
      },
    ],
  };
}

export default function App() {
  const [parsed, setParsed] = useState<ParsedGpx | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [dragging, setDragging] = useState(false);
  const [hoverIdx, setHoverIdx] = useState<number | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  const [libraryOpen, setLibraryOpen] = useState(false);
  const [offlineOpen, setOfflineOpen] = useState(false);
  const [mapObj, setMapObj] = useState<MlMap | null>(null);
  const [libVersion, setLibVersion] = useState(0);
  const [compare, setCompare] = useState<{ track: Track; name: string; id: string } | null>(
    null,
  );
  const inputRef = useRef<HTMLInputElement>(null);

  const editor = useEditor();
  const online = useOnline();

  const flash = useCallback((msg: string) => {
    setToast(msg);
    window.setTimeout(() => setToast((t) => (t === msg ? null : t)), 2200);
  }, []);

  const gpxTrack: Track | null = parsed?.tracks[0] ?? null;

  // The edited route as a Track (for stats + elevation), if it has a line.
  const editTrack = useMemo(
    () => routeToTrack(editor.route, "New route"),
    [editor.route],
  );

  // What the dock (stats + elevation + scrub) reflects.
  const focusTrack = editTrack ?? gpxTrack;
  const stats = focusTrack?.stats;

  const loadFile = useCallback(async (file: File) => {
    setError(null);
    setHoverIdx(null);
    try {
      const text = await file.text();
      const result = parseGpx(text, file.name);
      if (result.tracks.length === 0) {
        setError("No track points found in this GPX.");
        return;
      }
      setParsed(result);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not read that file.");
    }
  }, []);

  const onPick = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) void loadFile(file);
    e.target.value = "";
  };

  const onDrop = (e: React.DragEvent) => {
    e.preventDefault();
    setDragging(false);
    const file = e.dataTransfer.files?.[0];
    if (file) void loadFile(file);
  };

  // Map interactions in edit modes.
  const onMapClick = useCallback(
    (p: LngLat) => {
      if (editor.mode === "draw") {
        void editor.addAnchor(p);
      } else if (editor.mode === "waypoint") {
        const name = window.prompt("Waypoint name", "Waypoint");
        if (name != null && name.trim()) editor.addWaypoint(p, name.trim());
      }
    },
    [editor],
  );

  const onWaypointClick = useCallback(
    (id: string) => {
      if (window.confirm("Delete this waypoint?")) editor.removeWaypoint(id);
    },
    [editor],
  );

  // Waypoints only belong to the drawn route (not a loaded GPX).
  const editWaypoints = editTrack
    ? editor.route.waypoints.map((w) => ({ lng: w.lng, lat: w.lat, name: w.name }))
    : [];

  const saveCurrent = useCallback(() => {
    if (!focusTrack) return;
    const name = window.prompt("Save as", focusTrack.name)?.trim();
    if (!name) return;
    const t: Track = { ...focusTrack, name };
    const s = t.stats;
    const now = Date.now();
    const rec: SavedTrack = {
      id: crypto.randomUUID(),
      name,
      createdAt: now,
      updatedAt: now,
      distance: s.distance,
      ascent: s.ascent,
      hasEle: s.maxEle != null,
      hasTime: s.hasTime,
      pointCount: s.pointCount,
      bbox: trackBbox(t),
      gpx: toGpx(t, editWaypoints),
      thumbnail: makeThumbnail(t),
    };
    saveTrack(rec)
      .then(() => {
        setLibVersion((v) => v + 1);
        flash(`Saved “${name}” to your library`);
      })
      .catch(() => flash("Couldn't save — storage error"));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [focusTrack, editWaypoints, flash]);

  const openSaved = useCallback(
    (rec: SavedTrack) => {
      try {
        const result = parseGpx(rec.gpx, `${rec.name}.gpx`);
        editor.clear();
        editor.setMode("view");
        setParsed(result);
        setHoverIdx(null);
        setLibraryOpen(false);
        if (compare?.id === rec.id) setCompare(null);
      } catch {
        flash("Couldn't open that saved track");
      }
    },
    [editor, compare, flash],
  );

  const compareSaved = useCallback(
    (rec: SavedTrack | null) => {
      if (!rec) {
        setCompare(null);
        return;
      }
      try {
        const result = parseGpx(rec.gpx, `${rec.name}.gpx`);
        const t = result.tracks[0];
        if (t) setCompare({ track: t, name: rec.name, id: rec.id });
      } catch {
        flash("Couldn't load that track to compare");
      }
    },
    [flash],
  );

  const exportSaved = useCallback((rec: SavedTrack, format: ExportFormat) => {
    const result = parseGpx(rec.gpx, `${rec.name}.gpx`);
    const t = result.tracks[0];
    if (t) exportTrack(t, format);
  }, []);

  const exportCurrent = useCallback(
    (format: ExportFormat) => {
      if (focusTrack) exportTrack(focusTrack, format, editWaypoints);
    },
    [focusTrack, editWaypoints],
  );

  // Keyboard shortcuts.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const tag = (e.target as HTMLElement)?.tagName;
      if (tag === "INPUT" || tag === "TEXTAREA") return;
      const mod = e.ctrlKey || e.metaKey;
      if (mod && e.key.toLowerCase() === "z") {
        e.preventDefault();
        if (e.shiftKey) editor.redo();
        else editor.undo();
      } else if (mod && e.key.toLowerCase() === "y") {
        e.preventDefault();
        editor.redo();
      } else if (!mod && e.key === "v") editor.setMode("view");
      else if (!mod && e.key === "d") editor.setMode("draw");
      else if (!mod && e.key === "w") editor.setMode("waypoint");
      else if (e.key === "Escape") editor.setMode("view");
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [editor]);

  const showEmpty = !parsed && editor.route.anchors.length === 0;
  const title = editTrack
    ? "New route"
    : parsed
      ? gpxTrack?.name || parsed.name
      : null;

  return (
    <div
      className="app"
      onDragOver={(e) => {
        e.preventDefault();
        setDragging(true);
      }}
      onDragLeave={() => setDragging(false)}
      onDrop={onDrop}
    >
      <header className="topbar">
        <div className="brand">
          <span className="brand__mark" aria-hidden />
          <span className="brand__name">Trace</span>
        </div>
        <div className="topbar__title">
          {title ? (
            <span className="file-name">{title}</span>
          ) : (
            <span className="topbar__hint">GPX viewer &amp; route editor</span>
          )}
        </div>
        <div className="topbar__actions">
          <span
            className={`conn ${online ? "conn--on" : "conn--off"}`}
            title={online ? "Online" : "Offline"}
          >
            <span className="conn__dot" />
            {online ? "Online" : "Offline"}
          </span>
          {focusTrack && (
            <>
              <button className="btn" onClick={saveCurrent}>
                Save
              </button>
              <details className="menu menu--bar">
                <summary className="btn">Export ▾</summary>
                <div className="menu__pop menu__pop--right">
                  <button onClick={() => exportCurrent("gpx")}>GPX</button>
                  <button onClick={() => exportCurrent("kml")}>KML</button>
                  <button onClick={() => exportCurrent("geojson")}>GeoJSON</button>
                </div>
              </details>
            </>
          )}
          <button className="btn" onClick={() => setOfflineOpen(true)}>
            Offline
          </button>
          <button className="btn" onClick={() => setLibraryOpen(true)}>
            Library
          </button>
          <button className="btn btn--primary" onClick={() => inputRef.current?.click()}>
            Open GPX
          </button>
          <input
            ref={inputRef}
            type="file"
            accept=".gpx,application/gpx+xml,application/xml,text/xml"
            hidden
            onChange={onPick}
          />
        </div>
      </header>

      <main className="stage">
        <MapView
          geojson={parsed?.geojson ?? null}
          compareGeojson={compare ? trackToLineFC(compare.track) : null}
          track={gpxTrack}
          focusTrack={focusTrack}
          hoverIdx={hoverIdx}
          onHover={setHoverIdx}
          editRoute={editor.route}
          editMode={editor.mode}
          onMapClick={onMapClick}
          onAnchorDragEnd={(idx, p) => void editor.moveAnchor(idx, p)}
          onAnchorClick={(idx) => void editor.deleteAnchor(idx)}
          onWaypointClick={onWaypointClick}
          onReady={setMapObj}
        />

        <ToolRail
          mode={editor.mode}
          setMode={editor.setMode}
          profile={editor.route.profile}
          setProfile={(pr) => void editor.setProfile(pr)}
          online={online}
          isRouting={editor.isRouting}
          lastFellBack={editor.lastFellBack}
          route={editor.route}
          canUndo={editor.canUndo}
          canRedo={editor.canRedo}
          onUndo={editor.undo}
          onRedo={editor.redo}
          onReverse={editor.reverse}
          onClear={editor.clear}
        />

        {editor.mode === "draw" && editor.route.anchors.length === 0 && (
          <div className="hint-pill">Click on the map to start drawing</div>
        )}
        {editor.mode === "waypoint" && (
          <div className="hint-pill">Click on the map to drop a waypoint</div>
        )}

        {showEmpty && (
          <div className="empty">
            <div className="empty__card">
              <div className="empty__title">Drop a GPX here</div>
              <div className="empty__sub">
                or{" "}
                <button className="linklike" onClick={() => inputRef.current?.click()}>
                  browse your files
                </button>{" "}
                — or pick <b>Draw</b> to trace a new route
              </div>
              <div className="empty__note num">.gpx · tracks &amp; routes</div>
            </div>
          </div>
        )}

        {compare && focusTrack && (
          <div className="compare-card">
            <div className="compare-card__head">
              <span>Comparing</span>
              <button
                className="iconx"
                onClick={() => setCompare(null)}
                aria-label="Stop comparing"
              >
                ✕
              </button>
            </div>
            <div className="compare-row">
              <span className="compare-dot compare-dot--main" />
              <span className="compare-name">{focusTrack.name}</span>
              <span className="num compare-val">{fmtDistance(focusTrack.stats.distance)}</span>
              <span className="num compare-val">+{Math.round(focusTrack.stats.ascent)} m</span>
            </div>
            <div className="compare-row">
              <span className="compare-dot compare-dot--cmp" />
              <span className="compare-name">{compare.name}</span>
              <span className="num compare-val">{fmtDistance(compare.track.stats.distance)}</span>
              <span className="num compare-val">+{Math.round(compare.track.stats.ascent)} m</span>
            </div>
          </div>
        )}

        {dragging && <div className="dropzone">Release to open</div>}
        {error && <div className="toast toast--error">{error}</div>}
        {toast && <div className="toast">{toast}</div>}
      </main>

      {stats && focusTrack && (
        <footer className="dock">
          <div className="statbar">
            <Stat label="Distance" value={fmtDistance(stats.distance)} />
            <Stat label="Ascent" value={`+${fmtElevation(stats.ascent)}`} accent="up" />
            <Stat label="Descent" value={`−${fmtElevation(stats.descent)}`} accent="down" />
            <Stat label="Max ele" value={fmtElevation(stats.maxEle)} />
            <Stat label="Min ele" value={fmtElevation(stats.minEle)} />
            <Stat label="Avg ele" value={fmtElevation(stats.avgEle)} />
            {stats.hasTime ? (
              <>
                <Stat label="Duration" value={fmtDuration(stats.duration)} />
                <Stat label="Moving" value={fmtDuration(stats.movingTime)} />
                <Stat label="Avg speed" value={fmtSpeed(stats.distance, stats.movingTime)} />
              </>
            ) : editTrack ? null : (
              <Stat label="Time" value="no timestamps" muted />
            )}
            <Stat label="Points" value={String(stats.pointCount)} muted />
          </div>
          <ElevationProfile track={focusTrack} hoverIdx={hoverIdx} onHover={setHoverIdx} />
        </footer>
      )}

      <Library
        open={libraryOpen}
        version={libVersion}
        compareId={compare?.id ?? null}
        onClose={() => setLibraryOpen(false)}
        onOpen={openSaved}
        onCompare={compareSaved}
        onExport={exportSaved}
      />

      <OfflinePanel
        open={offlineOpen}
        onClose={() => setOfflineOpen(false)}
        map={mapObj}
        online={online}
      />
    </div>
  );
}

function Stat({
  label,
  value,
  accent,
  muted,
}: {
  label: string;
  value: string;
  accent?: "up" | "down";
  muted?: boolean;
}) {
  return (
    <div className={`stat${muted ? " stat--muted" : ""}`}>
      <div className="stat__label">{label}</div>
      <div className={`stat__value num${accent ? ` stat__value--${accent}` : ""}`}>
        {value}
      </div>
    </div>
  );
}
