//  AppModel.swift
//  État partagé : fond de carte, cache des traces parsées,
//  curseur de scrub, demandes de cadrage, session de suivi.

import CoreLocation
import Foundation
import SwiftUI
import UIKit

/// Fond raster tuilé (affiché via CachingTileOverlay, donc hors-ligne-able).
struct RasterProvider {
    let id: String
    let urlTemplate: String
    let maxZ: Int
}

enum Basemap: String, CaseIterable, Identifiable {
    case appleStandard
    case appleHybrid
    case appleSatellite
    case openTopo
    case ignPlan
    case swisstopo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .appleStandard: return "Plan (Apple)"
        case .appleHybrid: return "Hybride (Apple)"
        case .appleSatellite: return "Satellite (Apple)"
        case .openTopo: return "Topo (OpenTopoMap)"
        case .ignPlan: return "Plan IGN (France)"
        case .swisstopo: return "Swisstopo (Suisse)"
        }
    }

    var symbol: String {
        switch self {
        case .appleStandard: return "map"
        case .appleHybrid: return "map.fill"
        case .appleSatellite: return "globe.europe.africa.fill"
        case .openTopo: return "mountain.2.fill"
        case .ignPlan: return "signpost.right.fill"
        case .swisstopo: return "mountain.2.circle.fill"
        }
    }

    /// nil pour les fonds Apple (vectoriels natifs, non tuilables).
    var raster: RasterProvider? {
        switch self {
        case .openTopo:
            return RasterProvider(
                id: "opentopo",
                urlTemplate: "https://a.tile.opentopomap.org/{z}/{x}/{y}.png",
                maxZ: 16)
        case .ignPlan:
            return RasterProvider(
                id: "ignplan",
                urlTemplate:
                    "https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0"
                    + "&LAYER=GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2&STYLE=normal&TILEMATRIXSET=PM"
                    + "&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image%2Fpng",
                maxZ: 18)
        case .swisstopo:
            return RasterProvider(
                id: "swisstopo",
                urlTemplate:
                    "https://wmts.geo.admin.ch/1.0.0/ch.swisstopo.pixelkarte-farbe"
                    + "/default/current/3857/{z}/{x}/{y}.jpeg",
                maxZ: 18)
        default:
            return nil
        }
    }

    /// Fonds téléchargeables hors ligne (rasters uniquement).
    static var offlineCapable: [Basemap] { allCases.filter { $0.raster != nil } }
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
    /// Mode nuit : filtre rouge sombre pour préserver la vision nocturne (§10).
    @Published var nightMode: Bool {
        didSet { UserDefaults.standard.set(nightMode, forKey: "nightMode") }
    }
    /// Poids (kg) pour l'estimation des calories.
    @Published var weightKg: Double {
        didSet { UserDefaults.standard.set(weightKg, forKey: "weightKg") }
    }
    /// Pendant un suivi : caméra libérée pour voir toute la trace.
    @Published var followOverview = false
    /// Rythme de marche : multiplie la durée DIN 33466 (0.8 rapide … 1.3 tranquille).
    @Published var paceFactor: Double {
        didSet { UserDefaults.standard.set(paceFactor, forKey: "paceFactor") }
    }
    /// Objectifs annuels du carnet.
    @Published var goalKm: Double {
        didSet { UserDefaults.standard.set(goalKm, forKey: "goalKm") }
    }
    @Published var goalUp: Double {
        didSet { UserDefaults.standard.set(goalUp, forKey: "goalUp") }
    }

    init() {
        basemap = Basemap(rawValue: UserDefaults.standard.string(forKey: "basemap") ?? "")
            ?? .appleStandard
        balancedGPS = UserDefaults.standard.bool(forKey: "balancedGPS")
        nightMode = UserDefaults.standard.bool(forKey: "nightMode")
        let w = UserDefaults.standard.double(forKey: "weightKg")
        weightKg = w > 0 ? w : 70
        let pf = UserDefaults.standard.double(forKey: "paceFactor")
        paceFactor = pf > 0 ? pf : 1.0
        let gk = UserDefaults.standard.double(forKey: "goalKm")
        goalKm = gk > 0 ? gk : 200
        let gu = UserDefaults.standard.double(forKey: "goalUp")
        goalUp = gu > 0 ? gu : 10000
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
        startFollow(points: t.points, name: record.name, waypoints: t.waypoints)
    }

    /// Variante générique (enchaînement d'étapes, trace combinée…).
    func startFollow(points: [TrackPoint], name: String, waypoints: [Waypoint]) {
        followOverview = false
        follow = FollowSession(points: points, name: name, waypoints: waypoints)
        location.setBalancedAccuracy(balancedGPS)
        location.start(background: true)
        UIApplication.shared.isIdleTimerDisabled = true   // écran allumé en nav
    }

    func stopFollow() {
        follow = nil
        followOverview = false
        if recording == nil { location.stop() }
        UIApplication.shared.isIdleTimerDisabled = (recording != nil)
    }

    // MARK: guidage « cap vers un point » (hors ligne, vol d'oiseau)

    struct GuideTarget {
        var name: String
        var lat: Double
        var lon: Double
    }

    @Published var guide: GuideTarget?

    /// Créateur d'itinéraire (mode dessin sur carte).
    @Published var builder: BuilderSession?

    func startBuilder() {
        builder = BuilderSession()
    }

    func stopBuilder() {
        builder = nil
    }

    func startGuide(name: String, lat: Double, lon: Double) {
        guide = GuideTarget(name: name, lat: lat, lon: lon)
        location.setBalancedAccuracy(false)
        location.start(background: false)
    }

    func stopGuide() {
        guide = nil
        if follow == nil && recording == nil { location.stop() }
    }

    // MARK: enregistrement de sortie

    @Published var recording: RecordingSession?

    func startRecording() {
        recording = RecordingSession()
        location.setBalancedAccuracy(balancedGPS)
        location.start(background: true)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    /// Termine et renvoie les points capturés (à sauvegarder par l'appelant).
    func stopRecording() -> [TrackPoint] {
        let pts = recording?.finish() ?? []
        recording = nil
        if follow == nil { location.stop() }
        UIApplication.shared.isIdleTimerDisabled = (follow != nil)
        return pts
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
    /// Estimation calories marche montagne (plat + grimpe, rendement ~20 %).
    static func kcal(weightKg: Double, distanceM: Double, ascent: Double) -> String {
        let v = weightKg * (distanceM / 1000) * 0.78 + weightKg * ascent * 0.0117
        return "≈\(Int(v)) kcal"
    }
    static func clock(after seconds: Double) -> String {
        let d = Date().addingTimeInterval(seconds)
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}
