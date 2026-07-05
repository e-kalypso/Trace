//  RecordingSession.swift
//  Enregistrement live d'une sortie (§9) : trace, distance, D+,
//  vitesse, durée. Pause auto quand on ne bouge pas, points espacés
//  d'au moins 3 m (batterie + fichiers propres).

import Foundation

final class RecordingSession: ObservableObject {

    @Published var distance: Double = 0
    @Published var ascent: Double = 0
    @Published var currentSpeed: Double = 0     // m/s
    @Published var elapsed: TimeInterval = 0
    @Published var isPaused = false
    /// Pause automatique : plus aucun déplacement accepté depuis 2 min.
    @Published var isAutoPaused = false

    private(set) var points: [TrackPoint] = []
    let startedAt = Date()
    private var lastEle: Double?
    private var timer: Timer?
    private var lastAccepted: Date?
    private var sinceAutosave = 0

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, !self.isPaused else { return }
            // pause auto : on fige le chrono quand on ne bouge plus
            if let la = self.lastAccepted, Date().timeIntervalSince(la) > 120 {
                self.isAutoPaused = true
                return
            }
            self.elapsed += 1
        }
    }

    func add(fix: GeoFix) {
        guard !isPaused else { return }
        currentSpeed = fix.speed

        if let last = points.last {
            let step = TrackGeometry.haversine(last.lat, last.lon,
                                               fix.coordinate.latitude,
                                               fix.coordinate.longitude)
            guard step >= 3 else { return }     // filtre le bruit à l'arrêt
            distance += step
        }

        let ele = fix.altitude
        if let prev = lastEle {
            let d = ele - prev
            if d > 2 { ascent += d; lastEle = ele }
            else if d < -2 { lastEle = ele }
        } else {
            lastEle = ele
        }

        points.append(TrackPoint(lat: fix.coordinate.latitude,
                                 lon: fix.coordinate.longitude,
                                 ele: ele,
                                 time: fix.timestamp,
                                 dist: distance))
        lastAccepted = Date()
        isAutoPaused = false

        // anti-crash : brouillon GPX toutes les 20 mesures
        sinceAutosave += 1
        if sinceAutosave >= 20 {
            sinceAutosave = 0
            let gpx = GPXWriter.gpx(name: "Sortie en cours", points: points, waypoints: [])
            try? gpx.write(to: GPXStore.autosaveURL, atomically: true, encoding: .utf8)
        }
    }

    func togglePause() { isPaused.toggle() }

    func finish() -> [TrackPoint] {
        timer?.invalidate()
        timer = nil
        try? FileManager.default.removeItem(at: GPXStore.autosaveURL)
        return points
    }

    deinit { timer?.invalidate() }
}
