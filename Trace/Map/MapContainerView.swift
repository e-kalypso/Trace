//  MapContainerView.swift
//  Carte MKMapView (UIViewRepresentable) :
//  - fonds Apple (plan / hybride / satellite) via preferredConfiguration
//  - fond topo : MKTileOverlay OpenTopoMap (couvre France + Suisse + Italie,
//    continuité TMB — cahier des charges §4.1)
//  - une MKPolyline par trace visible (active plus épaisse)
//  - waypoints du GPX, curseur de scrub, position utilisateur

import MapKit
import SwiftUI

final class ColoredPolyline: MKPolyline {
    var color: UIColor = .systemBlue
    var isActive = false
}

final class WaypointAnnotation: MKPointAnnotation {}
final class ScrubAnnotation: MKPointAnnotation {}

/// Waypoint personnel (appui long) — porte son symbole SF.
final class PersonalAnnotation: MKPointAnnotation {
    var symbolName = "mappin"
}

struct PersonalWaypointItem {
    let id: UUID
    let lat: Double
    let lon: Double
    let name: String
    let symbol: String
}

struct MapContainerView: UIViewRepresentable {
    var tracks: [MapTrack]
    var basemap: Basemap
    var scrub: CLLocationCoordinate2D?
    var fitTarget: [CLLocationCoordinate2D]
    var fitRequest: Int
    var following: Bool
    var revision: Int
    var personalWaypoints: [PersonalWaypointItem] = []
    var onLongPress: ((CLLocationCoordinate2D) -> Void)? = nil

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        context.coordinator.onLongPress = onLongPress
        let press = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:)))
        press.minimumPressDuration = 0.5
        map.addGestureRecognizer(press)
        map.showsUserLocation = true
        map.showsCompass = true
        map.showsScale = true
        map.isPitchEnabled = false
        map.pointOfInterestFilter = .excludingAll
        // Chamonix par défaut
        map.setRegion(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 45.92, longitude: 6.87),
                span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
            ),
            animated: false
        )
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coord = context.coordinator

        // --- fond de carte ---
        if coord.appliedBasemap != basemap {
            coord.appliedBasemap = basemap
            applyBasemap(on: map)
        }

        // --- traces ---
        let key = "r\(revision);" + tracks
            .map { "\($0.id.uuidString)|\($0.colorHex)|\($0.isActive)|\($0.coordinates.count)" }
            .joined(separator: ";")
        if coord.appliedTracksKey != key {
            coord.appliedTracksKey = key
            rebuildTracks(on: map)
        }

        // --- cadrage demandé ---
        if coord.appliedFitRequest != fitRequest, !fitTarget.isEmpty {
            coord.appliedFitRequest = fitRequest
            if fitTarget.count == 1 {
                map.setRegion(
                    MKCoordinateRegion(
                        center: fitTarget[0],
                        span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                    ),
                    animated: true
                )
            } else {
                var rect = MKMapRect.null
                for c in fitTarget {
                    let p = MKMapPoint(c)
                    rect = rect.union(MKMapRect(x: p.x, y: p.y, width: 1, height: 1))
                }
                map.setVisibleMapRect(
                    rect,
                    edgePadding: UIEdgeInsets(top: 90, left: 40, bottom: 260, right: 40),
                    animated: true
                )
            }
        }

        // --- suivi caméra ---
        if following != coord.wasFollowing {
            coord.wasFollowing = following
            map.setUserTrackingMode(following ? .follow : .none, animated: true)
        }

        // --- waypoints personnels ---
        let wpKey = personalWaypoints.map { $0.id.uuidString }.joined(separator: ",")
        if coord.appliedWaypointsKey != wpKey {
            coord.appliedWaypointsKey = wpKey
            map.removeAnnotations(map.annotations.filter { $0 is PersonalAnnotation })
            for w in personalWaypoints {
                let a = PersonalAnnotation()
                a.coordinate = CLLocationCoordinate2D(latitude: w.lat, longitude: w.lon)
                a.title = w.name
                a.symbolName = w.symbol
                map.addAnnotation(a)
            }
        }

        // --- rappel du callback (closure capturée à jour) ---
        coord.onLongPress = onLongPress

        // --- curseur de scrub ---
        if let s = scrub {
            if let a = coord.scrubAnnotation {
                a.coordinate = s
            } else {
                let a = ScrubAnnotation()
                a.coordinate = s
                coord.scrubAnnotation = a
                map.addAnnotation(a)
            }
        } else if let a = coord.scrubAnnotation {
            map.removeAnnotation(a)
            coord.scrubAnnotation = nil
        }
    }

    private func applyBasemap(on map: MKMapView) {
        map.removeOverlays(map.overlays.filter { $0 is MKTileOverlay })
        if let raster = basemap.raster {
            let c = MKStandardMapConfiguration()
            c.pointOfInterestFilter = .excludingAll
            map.preferredConfiguration = c
            let tiles = CachingTileOverlay(providerID: raster.id,
                                           urlTemplate: raster.urlTemplate)
            tiles.canReplaceMapContent = true
            tiles.maximumZ = raster.maxZ
            // niveau .aboveRoads : sous les polylignes (qui sont en .aboveLabels)
            map.addOverlay(tiles, level: .aboveRoads)
            return
        }
        switch basemap {
        case .appleStandard:
            let c = MKStandardMapConfiguration(elevationStyle: .realistic)
            c.pointOfInterestFilter = .excludingAll
            map.preferredConfiguration = c
        case .appleHybrid:
            map.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .realistic)
        case .appleSatellite:
            map.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .realistic)
        default:
            break
        }
    }

    private func rebuildTracks(on map: MKMapView) {
        map.removeOverlays(map.overlays.filter { $0 is ColoredPolyline })
        map.removeAnnotations(map.annotations.filter { $0 is WaypointAnnotation })

        // inactives d'abord, active au-dessus
        for t in tracks.sorted(by: { !$0.isActive && $1.isActive }) {
            guard t.coordinates.count >= 2 else { continue }
            let line = ColoredPolyline(coordinates: t.coordinates, count: t.coordinates.count)
            line.color = UIColor(hex: t.colorHex)
            line.isActive = t.isActive
            map.addOverlay(line, level: .aboveLabels)

            if t.isActive {
                for w in t.waypoints {
                    let a = WaypointAnnotation()
                    a.coordinate = CLLocationCoordinate2D(latitude: w.lat, longitude: w.lon)
                    a.title = w.name
                    map.addAnnotation(a)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var appliedBasemap: Basemap?
        var appliedTracksKey = ""
        var appliedWaypointsKey = ""
        var appliedFitRequest = 0
        var wasFollowing = false
        var scrubAnnotation: ScrubAnnotation?
        var onLongPress: ((CLLocationCoordinate2D) -> Void)? = nil

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began,
                  let map = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: map)
            let coord = map.convert(point, toCoordinateFrom: map)
            onLongPress?(coord)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tiles)
            }
            if let line = overlay as? ColoredPolyline {
                let r = MKPolylineRenderer(polyline: line)
                r.strokeColor = line.isActive ? line.color : line.color.withAlphaComponent(0.55)
                r.lineWidth = line.isActive ? 5 : 3
                r.lineJoin = .round
                r.lineCap = .round
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            if annotation is ScrubAnnotation {
                let id = "scrub"
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
                v.annotation = annotation
                let size: CGFloat = 16
                v.frame = CGRect(x: 0, y: 0, width: size, height: size)
                v.layer.cornerRadius = size / 2
                v.backgroundColor = UIColor(hex: "FF9F0A")
                v.layer.borderColor = UIColor.white.cgColor
                v.layer.borderWidth = 3
                return v
            }
            if annotation is WaypointAnnotation {
                let id = "wpt"
                let v = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                v.annotation = annotation
                v.glyphImage = UIImage(systemName: "flag.fill")
                v.markerTintColor = UIColor(hex: "E8663C")
                v.canShowCallout = true
                return v
            }
            if let personal = annotation as? PersonalAnnotation {
                let id = "perso"
                let v = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                v.annotation = annotation
                v.glyphImage = UIImage(systemName: personal.symbolName)
                v.markerTintColor = UIColor(hex: "0A84FF")
                v.canShowCallout = true
                return v
            }
            return nil
        }
    }
}
