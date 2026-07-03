# Trace

A GPX viewer & route editor for iPhone — built as an offline-first web app
(PWA) so it runs 100% on Windows today and installs to the iPhone home screen.

In the spirit of gpx.studio, with a calmer, more opinionated "ink on paper"
design.

## Stack (pinned)

- Vite 5 + React 18 + TypeScript 5.6
- MapLibre GL JS 4.7 with free **OpenFreeMap** tiles (no API key, no signup)
- `@tmcw/togeojson` for GPX parsing

## Run it

```powershell
cd trace
npm install      # first time only
npm run dev
```

Then open the URL it prints (http://localhost:5173).

- Click **Open GPX** or drag a `.gpx` onto the window.
- A sample track is bundled: `public/samples/lac-blanc.gpx`.

## Build for production

```powershell
npm run build      # type-checks, then bundles to dist/
npm run preview    # serves the built app (use --host to test from your iPhone)
```

## Features

- **View** — open a GPX (button or drag-drop), track on the map, start/finish
  markers, full stats (distance, ascent/descent, min/max/avg elevation,
  duration, moving time, avg speed). Time stats hide when a file has no
  timestamps.
- **Elevation profile** — fills left-to-right, scrub with mouse/finger; the map
  and profile are linked both ways.
- **Draw & edit** — click to draw; snap to trails/roads via BRouter (Hike / Bike
  / straight-line), drag anchors to reshape, delete points, add named
  waypoints, reverse, undo/redo. Offline it falls back to straight lines and
  says so.
- **Library** — save tracks on-device (IndexedDB) with SVG thumbnails, search &
  sort, open, compare two tracks (teal overlay), export to GPX / KML / GeoJSON.
- **Offline** — installs to the home screen; the app shell is precached so it
  launches with no connection. Download map regions for offline viewing and
  manage their storage.

Keyboard: `V` select · `D` draw · `W` waypoint · `Esc` select · `Ctrl+Z` /
`Ctrl+Shift+Z` undo/redo.

## Test it offline (the trail scenario)

1. `npm run build` then `npm run preview -- --host` (the service worker only runs
   in a production build, not `npm run dev`).
2. Open the printed URL, pan to an area, open **Offline → Download this area**.
3. In Chrome DevTools → Network, switch to **Offline**, then reload. The app
   still launches, your library opens, and the downloaded area renders.
4. On your iPhone: open the `--host` URL in Safari → Share → **Add to Home
   Screen**. Launch it, then turn on **Airplane mode** to confirm offline.

## Milestones

- **M1 ✅** Open a GPX → map + markers + stats.
- **M2 ✅** Elevation profile + two-way scrub + full stats.
- **M3 ✅** Draw/edit with trail snapping (split/merge/trim still to come — M3b).
- **M4 ✅** Library, compare, export, installable PWA.
- **M4.5 ✅** Offline map region downloads.
- **M5** iOS App Store packaging — needs a cloud Mac build + Apple Developer
  account. Not started (requires your Apple ID + the yearly fee).

## Ship to iOS (App Store / TestFlight)

iOS can't be compiled on Windows, so Trace is wrapped with **Capacitor** and
built on a **cloud Mac** (Codemagic). The native project already exists in
`ios/`, and [`codemagic.yaml`](codemagic.yaml) defines the build.

Windows-side workflow (already wired):

```powershell
npm run ios:sync    # build the web app + copy it into ios/
```

What still needs *you* (one-time): an Apple ID with 2FA, the **$99/yr** Apple
Developer Program, an App Store Connect app record + bundle ID, and connecting
your Apple credentials to Codemagic. Then every push produces a TestFlight
build. See the checklist handed over in chat.

## Notes

- The main JS bundle is ~1 MB (mostly MapLibre); we can code-split it later.
- `npm audit` reports advisories in transitive build-time deps; they don't ship
  to the browser bundle. We'll address before release.
