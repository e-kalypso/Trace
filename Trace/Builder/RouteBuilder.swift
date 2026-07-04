//  RouteBuilder.swift
//  Créer son itinéraire sans GPX : on tape sur la carte, chaque
//  segment est aimanté aux sentiers de randonnée (BRouter, gratuit,
//  sans clé) — ou tracé en ligne droite hors ligne. Distance et D+
//  en direct, annuler, sauvegarder en trace.

import CoreLocation
import Foundation
import SwiftUI
import UIKit

final class BuilderSession: ObservableObject {
    /// Un segment = la géométrie entre deux points tapés (lat, lon, ele?).
    struct Segment {
        var coords: [(lat: Double, lon: Double, ele: Double?)]
        var snapped: Bool
    }

    @Published var anchors: [CLLocationCoordinate2D] = []
    @Published var segments: [Segment] = []
    @Published var snapToTrails = true
    @Published var isRouting = false
    @Published var lastFellBack = false

    var distance: Double {
        var d = 0.0
        for s in segments {
            for i in 1..<max(1, s.coords.count) {
                d += TrackGeometry.haversine(s.coords[i-1].lat, s.coords[i-1].lon,
                                             s.coords[i].lat, s.coords[i].lon)
            }
        }
        return d
    }

    var ascent: Double {
        var a = 0.0
        var last: Double?
        for s in segments {
            for c in s.coords {
                guard let e = c.ele else { continue }
                if let l = last, e - l > 2 { a += e - l }
                if last == nil || abs(e - (last ?? e)) > 2 { last = e }
            }
        }
        return a
    }

    /// Polyline à dessiner sur la carte.
    var draftCoordinates: [CLLocationCoordinate2D] {
        var out: [CLLocationCoordinate2D] = []
        for (i, s) in segments.enumerated() {
            for (j, c) in s.coords.enumerated() {
                if i > 0 && j == 0 { continue }
                out.append(.init(latitude: c.lat, longitude: c.lon))
            }
        }
        if out.isEmpty, let a = anchors.first { out = [a] }
        return out
    }

    @MainActor
    func addAnchor(_ coord: CLLocationCoordinate2D) async {
        let prev = anchors.last
        anchors.append(coord)
        guard let prev else { return }

        if snapToTrails {
            isRouting = true
            if let routed = await BRouter.route(from: prev, to: coord) {
                segments.append(Segment(coords: routed, snapped: true))
                lastFellBack = false
                isRouting = false
                return
            }
            lastFellBack = true
            isRouting = false
        }
        segments.append(Segment(
            coords: [(prev.latitude, prev.longitude, nil),
                     (coord.latitude, coord.longitude, nil)],
            snapped: false))
    }

    func undo() {
        guard !anchors.isEmpty else { return }
        anchors.removeLast()
        if !segments.isEmpty { segments.removeLast() }
    }

    /// Convertit le brouillon en points de trace prêts à sauvegarder.
    func toTrackPoints() -> [TrackPoint] {
        var pts: [TrackPoint] = draftCoordinates.map {
            TrackPoint(lat: $0.latitude, lon: $0.longitude, ele: nil, time: nil)
        }
        // récupère l'altitude BRouter quand elle existe
        var flat: [(Double, Double, Double?)] = []
        for (i, s) in segments.enumerated() {
            for (j, c) in s.coords.enumerated() {
                if i > 0 && j == 0 { continue }
                flat.append(c)
            }
        }
        for i in pts.indices where i < flat.count {
            pts[i].ele = flat[i].2
        }
        TrackGeometry.accumulateDistances(&pts)
        return pts
    }
}

/// Client BRouter minimal (serveur public, profil rando montagne).
enum BRouter {
    private struct GeoJSON: Decodable {
        struct Feature: Decodable {
            struct Geometry: Decodable { let coordinates: [[Double]] }
            let geometry: Geometry
        }
        let features: [Feature]
    }

    static func route(from a: CLLocationCoordinate2D,
                      to b: CLLocationCoordinate2D)
        async -> [(lat: Double, lon: Double, ele: Double?)]? {
        let urlString = "https://brouter.de/brouter?lonlats="
            + String(format: "%.6f,%.6f|%.6f,%.6f",
                     a.longitude, a.latitude, b.longitude, b.latitude)
            + "&profile=hiking-mountain&alternativeidx=0&format=geojson"
        guard let url = URL(string: urlString) else { return nil }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 12
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let gj = try JSONDecoder().decode(GeoJSON.self, from: data)
            guard let coords = gj.features.first?.geometry.coordinates,
                  coords.count >= 2 else { return nil }
            return coords.map { c in
                (lat: c[1], lon: c[0], ele: c.count > 2 ? c[2] : nil)
            }
        } catch {
            return nil
        }
    }
}

// MARK: - HUD du créateur

struct BuilderHUDView: View {
    @ObservedObject var builder: BuilderSession
    var onUndo: () -> Void
    var onSave: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "pencil.and.outline")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Créer un itinéraire").font(.headline)
                        Text(builder.anchors.isEmpty
                             ? "Touchez la carte pour poser le départ"
                             : "\(Fmt.distance(builder.distance))"
                               + (builder.ascent > 0 ? " · +\(Int(builder.ascent)) m" : ""))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if builder.isRouting { ProgressView() }
                }
                HStack(spacing: 8) {
                    Toggle(isOn: $builder.snapToTrails) {
                        Text("Sentiers").font(.caption.weight(.semibold))
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    Button(action: onUndo) {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                    .disabled(builder.anchors.isEmpty)
                    Spacer()
                    Button("Annuler", role: .cancel, action: onCancel)
                        .buttonStyle(.bordered)
                    Button(action: onSave) {
                        Text("Enregistrer").fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(builder.anchors.count < 2)
                }
                if builder.lastFellBack {
                    Label("Sentiers injoignables (hors ligne ?) — ligne droite utilisée",
                          systemImage: "wifi.slash")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 12)
            Spacer()
        }
        .padding(.top, 4)
    }
}
