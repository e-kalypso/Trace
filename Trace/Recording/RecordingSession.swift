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

    private(set) var points: [TrackPoint] = []
    let startedAt = Date()
    private var lastEle: Double?
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, !self.isPaused else { return }
            self.elapsed = Date().timeIntervalSince(self.startedAt)
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
    }

    func togglePause() { isPaused.toggle() }

    func finish() -> [TrackPoint] {
        timer?.invalidate()
        timer = nil
        return points
    }

    deinit { timer?.invalidate() }
}
