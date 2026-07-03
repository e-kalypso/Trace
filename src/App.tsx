/* ============================================================
   Trace v2 — GPS de randonnée.
   Carte plein écran + bottom sheet (calques, détail, réglages)
   + HUD de navigation (virages, distance restante, ETA).
   ============================================================ */
import { useCallback, useMemo, useRef, useState } from "react";
import type { Map as MlMap } from "maplibre-gl";
import MapView from "./components/MapView";
import BottomSheet, { type SheetPos } from "./components/BottomSheet";
import ElevationProfile from "./components/ElevationProfile";
import { useLayers, type Layer } from "./layers/useLayers";
import { useNavigation } from "./nav/useNavigation";
import { turnGlyph, turnLabel, snapToTrack, OFF_ROUTE_M } from "./nav/engine";
import { useOnline } from "./lib/useOnline";
import { routeSegment, straightSegment } from "./lib/routing";
import { PROVIDERS } from "./lib/providers";
import { fmtDistance, fmtElevation } from "./lib/format";
import type { GeoAccuracy } from "./lib/geo";
import "./App.css";

type Page =
  | { kind: "layers" }
  | { kind: "detail"; layerId: string }
  | { kind: "settings" };

export default function App() {
  const online = useOnline();
  const L = useLayers();

  const [providerId, setProviderId] = useState("plan");
  const [accuracy, setAccuracy] = useState<GeoAccuracy>("max");
  const nav = useNavigation(accuracy);

  const [sheetPos, setSheetPos] = useState<SheetPos>("half");
  const [page, setPage] = useState<Page>({ kind: "layers" });
  const [approach, setApproach] = useState<number[][] | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  const [hoverIdx, setHoverIdx] = useState<number | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const mapRef = useRef<MlMap | null>(null);

  const flash = useCallback((m: string) => {
    setToast(m);
    window.setTimeout(() => setToast((t) => (t === m ? null : t)), 2600);
  }, []);

  /* ---------- import GPX ---------- */
  const onPick = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = e.target.files;
    if (!files) return;
    for (const f of Array.from(files)) {
      const layer = L.addFromGpxText(await f.text(), f.name);
      if (!layer) flash(`Impossible de lire ${f.name}`);
    }
    e.target.value = "";
  };

  /* ---------- actions tracé ---------- */

  const detailLayer: Layer | null =
    page.kind === "detail" ? (L.layers.find((l) => l.id === page.layerId) ?? null) : null;

  const startNav = useCallback(
    async (layer: Layer) => {
      const ok = await nav.startNavigation(layer.track);
      if (!ok) {
        flash("Autorisez la localisation pour naviguer");
        return;
      }
      setApproach(null);
      setSheetPos("peek");
    },
    [nav, flash],
  );

  /** Itinéraire d'approche par chemins de randonnée. */
  const joinTrack = useCallback(
    async (layer: Layer, target: "nearest" | "start") => {
      if (!nav.fix) {
        const ok = await nav.locate();
        if (!ok) {
          flash("Position introuvable");
          return;
        }
        flash("Recherche de votre position… réessayez dans un instant");
        return;
      }
      const from = { lng: nav.fix.lng, lat: nav.fix.lat };
      const pts = layer.track.points;
      const to =
        target === "start"
          ? { lng: pts[0].lng, lat: pts[0].lat }
          : (() => {
              const s = snapToTrack(layer.track, from.lng, from.lat, null);
              return { lng: s.lng, lat: s.lat };
            })();
      try {
        const res = online
          ? await routeSegment(from, to, "hike")
          : straightSegment(from, to);
        setApproach(res.coords);
        if (!res.snapped) {
          flash(
            online
              ? "Itinéraire indisponible — ligne droite affichée"
              : "Hors ligne — ligne droite affichée",
          );
        }
        setSheetPos("peek");
      } catch {
        setApproach(straightSegment(from, to).coords);
        flash("Itinéraire indisponible — ligne droite affichée");
      }
    },
    [nav, online, flash],
  );

  /* ---------- HUD ---------- */

  const u = nav.update;
  const etaClock = useMemo(() => {
    if (!u || u.etaMs == null) return "—";
    const d = new Date(Date.now() + u.etaMs);
    return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
  }, [u]);

  return (
    <div className="app">
      <MapView
        providerId={providerId}
        layers={L.layers}
        activeLayerId={L.activeLayer?.id ?? null}
        fix={nav.fix}
        navigating={nav.navigating}
        approach={approach}
        onMapReady={(m) => (mapRef.current = m)}
      />

      {/* pastille hors-ligne */}
      {!online && <div className="offline-pill glass">Hors ligne</div>}

      {/* bannière navigation */}
      {nav.navigating && (
        <div className={`navbanner glass${u?.offRoute ? " navbanner--off" : ""}`}>
          {u?.offRoute ? (
            <>
              <span className="navbanner__glyph">⚠︎</span>
              <div className="navbanner__text">
                <div className="navbanner__title">Hors tracé</div>
                <div className="navbanner__sub">
                  à {fmtDistance(u.snap.offset)} du tracé (seuil {OFF_ROUTE_M} m)
                </div>
              </div>
            </>
          ) : u?.nextTurn && u.nextTurn.in < 400 ? (
            <>
              <span className="navbanner__glyph">{turnGlyph(u.nextTurn.dir)}</span>
              <div className="navbanner__text">
                <div className="navbanner__title">{turnLabel(u.nextTurn.dir)}</div>
                <div className="navbanner__sub num">dans {fmtDistance(u.nextTurn.in)}</div>
              </div>
            </>
          ) : (
            <>
              <span className="navbanner__glyph">↑</span>
              <div className="navbanner__text">
                <div className="navbanner__title">Suivez le tracé</div>
                {u && (
                  <div className="navbanner__sub num">
                    encore {fmtDistance(u.remaining)}
                  </div>
                )}
              </div>
            </>
          )}
        </div>
      )}

      {/* barre de stats de nav */}
      {nav.navigating && u && (
        <div className="navstats glass">
          <div className="navstats__item">
            <div className="navstats__val num">{fmtDistance(u.remaining)}</div>
            <div className="navstats__lbl">restant</div>
          </div>
          <div className="navstats__item">
            <div className="navstats__val num">{etaClock}</div>
            <div className="navstats__lbl">arrivée</div>
          </div>
          <div className="navstats__item">
            <div className="navstats__val num">{(u.speed * 3.6).toFixed(1)}</div>
            <div className="navstats__lbl">km/h</div>
          </div>
          <button className="navstats__stop" onClick={() => void nav.stopNavigation()}>
            Arrêter
          </button>
        </div>
      )}

      {/* bouton position */}
      <button
        className="fab glass"
        aria-label="Ma position"
        onClick={() => void nav.locate()}
        style={{ bottom: undefined }}
      >
        {nav.locating ? "…" : "◉"}
      </button>

      {/* feuille inférieure */}
      {!nav.navigating && (
        <BottomSheet pos={sheetPos} onPos={setSheetPos}>
          {page.kind === "layers" && (
            <>
              <div className="sheet__titlebar">
                <h1 className="sheet__title">Tracés</h1>
                <div className="sheet__titleactions">
                  <button className="pillbtn" onClick={() => setPage({ kind: "settings" })}>
                    Réglages
                  </button>
                  <button
                    className="pillbtn pillbtn--primary"
                    onClick={() => inputRef.current?.click()}
                  >
                    + GPX
                  </button>
                </div>
              </div>

              {L.loaded && L.layers.length === 0 && (
                <div className="empty">
                  <div className="empty__icon">🥾</div>
                  <div className="empty__title">Aucun tracé</div>
                  <div className="empty__sub">
                    Importez un fichier GPX pour commencer. Le premier calque
                    visible devient le tracé suivi.
                  </div>
                </div>
              )}

              <div className="rows">
                {L.layers.map((l, i) => (
                  <div className={`row${l.visible ? "" : " row--hidden"}`} key={l.id}>
                    <button
                      className="row__eye"
                      aria-label="Afficher/masquer"
                      onClick={() => L.toggleVisible(l.id)}
                    >
                      {l.visible ? "●" : "○"}
                    </button>
                    <span className="row__dot" style={{ background: l.color }} />
                    <button className="row__main" onClick={() => setPage({ kind: "detail", layerId: l.id })}>
                      <span className="row__name">
                        {l.name}
                        {L.activeLayer?.id === l.id && <span className="row__badge">actif</span>}
                      </span>
                      <span className="row__meta num">
                        {fmtDistance(l.track.stats.distance)} · +
                        {Math.round(l.track.stats.ascent)} m
                      </span>
                    </button>
                    <div className="row__order">
                      <button disabled={i === 0} onClick={() => L.move(l.id, -1)}>▲</button>
                      <button disabled={i === L.layers.length - 1} onClick={() => L.move(l.id, 1)}>▼</button>
                    </div>
                  </div>
                ))}
              </div>
            </>
          )}

          {page.kind === "detail" && detailLayer && (
            <>
              <div className="sheet__titlebar">
                <button className="backbtn" onClick={() => setPage({ kind: "layers" })}>
                  ‹ Tracés
                </button>
              </div>
              <h1 className="sheet__title sheet__title--detail">{detailLayer.name}</h1>
              <div className="statgrid num">
                <div><b>{fmtDistance(detailLayer.track.stats.distance)}</b><span>distance</span></div>
                <div><b>+{Math.round(detailLayer.track.stats.ascent)} m</b><span>D+</span></div>
                <div><b>{fmtElevation(detailLayer.track.stats.maxEle)}</b><span>alt. max</span></div>
              </div>

              <ElevationProfile
                track={detailLayer.track}
                hoverIdx={hoverIdx}
                onHover={setHoverIdx}
              />

              <button className="bigbtn" onClick={() => void startNav(detailLayer)}>
                Naviguer
              </button>
              <div className="btnrow">
                <button className="pillbtn" onClick={() => void joinTrack(detailLayer, "nearest")}>
                  Rejoindre le tracé
                </button>
                <button className="pillbtn" onClick={() => void joinTrack(detailLayer, "start")}>
                  Rejoindre le départ
                </button>
              </div>
              <div className="btnrow">
                <button className="pillbtn" onClick={() => L.reverse(detailLayer.id)}>
                  Inverser
                </button>
                <button
                  className="pillbtn pillbtn--danger"
                  onClick={() => {
                    L.remove(detailLayer.id);
                    setPage({ kind: "layers" });
                  }}
                >
                  Supprimer
                </button>
              </div>
            </>
          )}

          {page.kind === "settings" && (
            <>
              <div className="sheet__titlebar">
                <button className="backbtn" onClick={() => setPage({ kind: "layers" })}>
                  ‹ Tracés
                </button>
              </div>
              <h1 className="sheet__title sheet__title--detail">Réglages</h1>

              <div className="setting">
                <div className="setting__label">Fond de carte</div>
                <div className="seg">
                  {PROVIDERS.map((pr) => (
                    <button
                      key={pr.id}
                      disabled={pr.disabled}
                      title={pr.note}
                      className={`seg__opt${providerId === pr.id ? " seg__opt--on" : ""}`}
                      onClick={() => setProviderId(pr.id)}
                    >
                      {pr.name}
                    </button>
                  ))}
                </div>
                <div className="setting__hint">
                  Apple Plans arrive — il nécessite une clé MapKit de votre compte
                  Apple Developer.
                </div>
              </div>

              <div className="setting">
                <div className="setting__label">Précision GPS</div>
                <div className="seg">
                  <button
                    className={`seg__opt${accuracy === "max" ? " seg__opt--on" : ""}`}
                    onClick={() => setAccuracy("max")}
                  >
                    Maximale
                  </button>
                  <button
                    className={`seg__opt${accuracy === "balanced" ? " seg__opt--on" : ""}`}
                    onClick={() => setAccuracy("balanced")}
                  >
                    Équilibrée
                  </button>
                </div>
                <div className="setting__hint">
                  Équilibrée espace les mesures GPS (≈25 m) pour économiser la
                  batterie sur les longues sorties.
                </div>
              </div>
            </>
          )}
        </BottomSheet>
      )}

      <input
        ref={inputRef}
        type="file"
        accept=".gpx,application/gpx+xml,application/xml,text/xml"
        multiple
        hidden
        onChange={(e) => void onPick(e)}
      />

      {toast && <div className="toast glass">{toast}</div>}
    </div>
  );
}
