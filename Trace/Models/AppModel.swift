//  AppModel.swift
//  État partagé : fond de carte, cache des traces parsées,
//  curseur de scrub, demandes de cadrage, session de suivi.

import CoreLocation
import Foundation
import SwiftUI

enum Basemap: String, CaseIterable, Identifiable {
    case appleStandard
    case appleHybrid
    case appleSatellite
    case openTopo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .appleStandard: return "Plan (Apple)"
        case .appleHybrid: return "Hybride (Apple)"
        case .appleSatellite: return "Satellite (Apple)"
        case .openTopo: return "Topo (OpenTopoMap)"
        }
    }

    var symbol: String {
        switch self {
        case .appleStandard: return "map"
        case .appleHybrid: return "map.fill"
        case .appleSatellite: return "globe.europe.africa.fill"
        case .openTopo: return "mountain.2.fill"
        }
    }
}

/// Une trace prête à dessiner sur la carte.
struct MapTrack: Identifiable {
    let id: UUID
    let coordinates: [CLLocationCoordinate2D]
    let waypoints: [Waypoint]
    let colorHex: String
    let isActive: Bool
}

@MainActor
final class AppModel: ObservableObject {

    @Published var basemap: Basemap {
        didSet { UserDefaults.standard.set(basemap.rawValue, forKey: "basemap") }
    }
    @Published var balancedGPS: Bool {
        didSet { UserDefaults.standard.set(balancedGPS, forKey: "balancedGPS") }
    }

    init() {
        basemap = Basemap(rawValue: UserDefaults.standard.string(forKey: "basemap") ?? "")
            ?? .appleStandard
        balancedGPS = UserDefaults.standard.bool(forKey: "balancedGPS")
    }

    /// Cache uuid → trace parsée (le fichier .gpx reste la source de vérité).
    @Published private(set) var parsed: [UUID: ParsedTrack] = [:]

    /// Curseur du profil altimétrique sur la carte.
    @Published var scrubCoordinate: CLLocationCoordinate2D?

    /// Demande de cadrage : incrémenter `fitRequest` après avoir posé `fitTarget`.
    @Published var fitTarget: [CLLocationCoordinate2D] = []
    @Published var fitRequest = 0

    /// Suivi en cours.
    @Published var follow: FollowSession?

    /// Incrémenté après une édition pour forcer le redessin des polylignes.
    @Published var mapRevision = 0

    let location = LocationManager()

    // MARK: cache

    func track(for record: TrackRecord) -> ParsedTrack? {
        if let t = parsed[record.uuid] { return t }
        guard let data = GPXStore.data(for: record.uuid),
              let t = GPXParser.parse(data: data, fallbackName: record.name) else { return nil }
        parsed[record.uuid] = t
        return t
    }

    func invalidate(_ uuid: UUID) {
        parsed[uuid] = nil
    }

    /// Traces visibles prêtes pour la carte (la sélection est le tracé actif).
    func mapTracks(records: [TrackRecord], selected: UUID?) -> [MapTrack] {
        records
            .filter { $0.isVisible }
            .compactMap { rec in
                guard let t = track(for: rec) else { return nil }
                return MapTrack(
                    id: rec.uuid,
                    coordinates: t.points.map {
                        CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
                    },
                    waypoints: t.waypoints,
                    colorHex: rec.colorHex,
                    isActive: rec.uuid == selected
                )
            }
    }

    func requestFit(_ coords: [CLLocationCoordinate2D]) {
        guard !coords.isEmpty else { return }
        fitTarget = coords
        fitRequest += 1
    }

    // MARK: suivi

    func startFollow(record: TrackRecord) {
        guard let t = track(for: record) else { return }
        follow = FollowSession(points: t.points, name: record.name)
        location.setBalancedAccuracy(balancedGPS)
        location.start(background: true)
    }

    func stopFollow() {
        follow = nil
        location.stop()
        // on garde l'affichage de position si l'utilisateur relance « ma position »
    }
}

// MARK: - couleur hex

extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
        self.init(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}

extension UIColor {
    convenience init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v)
        self.init(
            red: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - formats

enum Fmt {
    static func distance(_ m: Double) -> String {
        m >= 1000 ? String(format: "%.2f km", m / 1000) : "\(Int(m)) m"
    }
    static func elevation(_ m: Double?) -> String {
        guard let m else { return "—" }
        return "\(Int(m.rounded())) m"
    }
    static func duration(_ s: TimeInterval?) -> String {
        guard let s, s.isFinite else { return "—" }
        let h = Int(s) / 3600
        let m = (Int(s) % 3600) / 60
        return h > 0 ? "\(h) h \(String(format: "%02d", m))" : "\(m) min"
    }
    static func clock(after seconds: Double) -> String {
        let d = Date().addingTimeInterval(seconds)
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}
