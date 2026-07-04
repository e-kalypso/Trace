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

struct MapContainerView: UIViewRepresentable {
    var tracks: [MapTrack]
    var basemap: Basemap
    var scrub: CLLocationCoordinate2D?
    var fitTarget: [CLLocationCoordinate2D]
    var fitRequest: Int
    var following: Bool
    var revision: Int

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
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
        switch basemap {
        case .appleStandard:
            let c = MKStandardMapConfiguration(elevationStyle: .realistic)
            c.pointOfInterestFilter = .excludingAll
            map.preferredConfiguration = c
        case .appleHybrid:
            map.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .realistic)
        case .appleSatellite:
            map.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .realistic)
        case .openTopo:
            let c = MKStandardMapConfiguration()
            c.pointOfInterestFilter = .excludingAll
            map.preferredConfiguration = c
            let tiles = MKTileOverlay(
                urlTemplate: "https://a.tile.opentopomap.org/{z}/{x}/{y}.png"
            )
            tiles.canReplaceMapContent = true
            tiles.maximumZ = 16
            map.insertOverlay(tiles, at: 0, level: .aboveLabels)
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
        var appliedFitRequest = 0
        var wasFollowing = false
        var scrubAnnotation: ScrubAnnotation?

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
            return nil
        }
    }
}
