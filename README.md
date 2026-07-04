# Trace

**La meilleure app iOS de randonnée en montagne** — natif SwiftUI, design
système, offline-first. Voir `Trace_Cahier_des_charges.md` (Downloads) pour la
spécification complète.

## Architecture (v3 — Phase 1 MVP)

- **SwiftUI + SwiftData** (iOS 17+), aucune dépendance externe.
- **MapKit natif** (plan / hybride / satellite relief) + **OpenTopoMap** en
  `MKTileOverlay` (continuité France·Suisse·Italie pour le TMB).
- **CoreLocation** BestForNavigation + **altitude barométrique** `CMAltimeter`
  recalée sur le GPS.
- Moteur GPX maison : parseur XML robuste (trk/rte/wpt, multi-segments),
  stats avec D+ fiabilisé, durée **DIN 33466**, Douglas-Peucker, lissage
  d'altitude, accrochage à la trace.
- Fichiers `.gpx` bruts = source de vérité (Application Support), SwiftData
  pour les métadonnées.
- Trace est **handler des fichiers .gpx** (ouverture depuis Mail / Fichiers).

## Build

Le projet Xcode n'est pas commité : il est généré par **XcodeGen** depuis
`project.yml`. Build cloud sur Codemagic (`codemagic.yaml`) :
XcodeGen → agvtool (n° de build) → signature → IPA → **TestFlight**.

Sur un Mac local : `xcodegen generate && open Trace.xcodeproj`.

## Roadmap

- **Phase 1 (ce dépôt)** : GPX (import/preview/stats/profil), carte multi-fonds,
  géoloc précise + baro, éditions de base, suivi avec alerte hors-trace.
- **Phase 2** : offline (packs de tuiles), IGN + Swisstopo, météo montagne
  (WeatherKit + Open-Meteo le long de la trace), planification, Live Activity.
- **Phase 3** : bivouac, parcs nationaux, Apple Watch, sécurité complète.
