//  DiscoverView.swift
//  Bibliothèque d'itinéraires SANS alourdir l'app : les sentiers
//  balisés (GR, PR, tours…) proches de l'utilisateur sont récupérés
//  à la demande depuis OpenStreetMap (Overpass, gratuit, sans clé),
//  puis importables en un tap.

import CoreLocation
import Foundation
import SwiftData
import SwiftUI
import UIKit

struct DiscoveredRoute: Identifiable {
    let id: Int
    let name: String
    let network: String?
    let coords: [(lat: Double, lon: Double)]
    let lengthM: Double
    let distanceFromUser: Double
}

enum Overpass {
    private struct Response: Decodable {
        struct Element: Decodable {
            struct Member: Decodable {
                struct Geo: Decodable { let lat: Double; let lon: Double }
                let type: String
                let geometry: [Geo]?
            }
            let id: Int
            let tags: [String: String]?
            let members: [Member]?
        }
        let elements: [Element]
    }

    static func hikingRoutes(lat: Double, lon: Double,
                             radiusKm: Double) async throws -> [DiscoveredRoute] {
        let query = """
        [out:json][timeout:\(radiusKm > 30 ? 50 : 25)];
        relation["route"="hiking"](around:\(Int(radiusKm * 1000)),\(lat),\(lon));
        out tags geom \(radiusKm > 30 ? 80 : 40);
        """
        var req = URLRequest(url: URL(string: "https://overpass-api.de/api/interpreter")!)
        req.httpMethod = "POST"
        req.httpBody = "data=\(query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query)"
            .data(using: .utf8)
        req.timeoutInterval = radiusKm > 30 ? 55 : 30
        let (data, _) = try await URLSession.shared.data(for: req)
        let resp = try JSONDecoder().decode(Response.self, from: data)

        var out: [DiscoveredRoute] = []
        for el in resp.elements {
            guard let members = el.members else { continue }
            var coords: [(Double, Double)] = []
            for m in members where m.type == "way" {
                for g in m.geometry ?? [] { coords.append((g.lat, g.lon)) }
            }
            guard coords.count >= 20 else { continue }
            var len = 0.0
            for i in 1..<coords.count {
                len += TrackGeometry.haversine(coords[i-1].0, coords[i-1].1,
                                               coords[i].0, coords[i].1)
            }
            guard len > 2000, len < 200_000 else { continue }
            let name = el.tags?["name"] ?? el.tags?["ref"] ?? "Itinéraire sans nom"
            let dist = TrackGeometry.haversine(lat, lon, coords[0].0, coords[0].1)
            out.append(DiscoveredRoute(
                id: el.id, name: name, network: el.tags?["network"],
                coords: coords, lengthM: len, distanceFromUser: dist))
        }
        return out.sorted { $0.distanceFromUser < $1.distanceFromUser }
    }
}

struct DiscoverView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var model: AppModel
    @Query(sort: \TrackRecord.sortOrder) private var records: [TrackRecord]

    @State private var routes: [DiscoveredRoute] = []
    @State private var loading = false
    @State private var error: String?
    @State private var importedIDs: Set<Int> = []
    @State private var radiusKm = 15.0

    var body: some View {
        List {
            Section {
                Picker("Rayon de recherche", selection: $radiusKm) {
                    Text("5 km").tag(5.0)
                    Text("15 km").tag(15.0)
                    Text("50 km").tag(50.0)
                    Text("100 km").tag(100.0)
                }
                .pickerStyle(.segmented)
                Button {
                    Task { await load() }
                } label: {
                    Label("Chercher dans ce rayon", systemImage: "location.magnifyingglass")
                }
                .disabled(loading)
            }

            Section {
                if loading {
                    HStack {
                        ProgressView()
                        Text("Recherche des sentiers balisés autour de vous…")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else if let error {
                    Label(error, systemImage: "wifi.slash")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(routes) { r in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name).font(.body.weight(.semibold)).lineLimit(2)
                            Text("\(Fmt.distance(r.lengthM)) · à \(Fmt.distance(r.distanceFromUser)) de vous"
                                 + (r.network.map { " · \($0.uppercased())" } ?? ""))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if importedIDs.contains(r.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button("Importer") { importRoute(r) }
                                .buttonStyle(.bordered)
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
            } header: {
                Text("Sentiers balisés à proximité")
            } footer: {
                Text("Données OpenStreetMap (GR, PR, tours). Récupérées à la demande : l'app reste légère. La géométrie brute peut nécessiter un petit nettoyage (Couper).")
            }
        }
        .navigationTitle("Découvrir")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if routes.isEmpty { await load() }
        }
    }

    private func load() async {
        // position : dernier fix, sinon on demande
        if model.location.fix == nil {
            _ = await requestFix()
        }
        guard let fix = model.location.fix else {
            error = "Activez la localisation pour découvrir les sentiers proches."
            return
        }
        loading = true
        error = nil
        do {
            routes = try await Overpass.hikingRoutes(
                lat: fix.coordinate.latitude,
                lon: fix.coordinate.longitude,
                radiusKm: radiusKm)
            if routes.isEmpty { error = "Aucun itinéraire balisé trouvé dans ce rayon." }
        } catch {
            self.error = "Réseau indisponible — réessayez plus tard."
        }
        loading = false
    }

    private func requestFix() async -> Bool {
        model.location.start(background: false)
        for _ in 0..<10 {
            if model.location.fix != nil { return true }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return model.location.fix != nil
    }

    private func importRoute(_ r: DiscoveredRoute) {
        var pts = r.coords.map { TrackPoint(lat: $0.lat, lon: $0.lon, ele: nil, time: nil) }
        TrackGeometry.accumulateDistances(&pts)
        let uuid = UUID()
        let gpx = GPXWriter.gpx(name: r.name, points: pts, waypoints: [])
        guard (try? GPXStore.save(gpx, for: uuid)) != nil else { return }
        let s = TrackGeometry.stats(for: pts)
        context.insert(TrackRecord(
            uuid: uuid, name: r.name,
            colorHex: TrackPalette.hex(at: records.count),
            sortOrder: records.count,
            distance: s.distance, ascent: s.ascent, descent: s.descent))
        importedIDs.insert(r.id)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
