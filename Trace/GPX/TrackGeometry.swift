//  TrackGeometry.swift
//  Géométrie de trace : stats, D+ fiabilisé, estimation DIN 33466,
//  simplification Douglas-Peucker, lissage d'altitude, accrochage.

import CoreLocation
import Foundation

struct TrackPoint {
    var lat: Double
    var lon: Double
    var ele: Double?          // m
    var time: Date?
    var dist: Double = 0      // distance cumulée (m)
}

struct Waypoint: Identifiable {
    let id = UUID()
    var lat: Double
    var lon: Double
    var name: String
    var ele: Double?
}

struct TrackStats {
    var distance: Double = 0        // m
    var ascent: Double = 0          // m (D+)
    var descent: Double = 0         // m (D-)
    var minEle: Double?
    var maxEle: Double?
    var duration: TimeInterval?     // horodatages GPX s'ils existent
    var estimatedDuration: TimeInterval = 0  // DIN 33466 adapté
    var pointCount: Int = 0
}

struct ParsedTrack {
    var name: String
    var points: [TrackPoint]
    var waypoints: [Waypoint]
    var stats: TrackStats
}

enum TrackGeometry {

    // MARK: distances

    static func haversine(_ aLat: Double, _ aLon: Double, _ bLat: Double, _ bLon: Double) -> Double {
        let r = 6_371_008.8
        let dLat = (bLat - aLat) * .pi / 180
        let dLon = (bLon - aLon) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(aLat * .pi / 180) * cos(bLat * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }

    /// Remplit `dist` cumulée sur chaque point.
    static func accumulateDistances(_ pts: inout [TrackPoint]) {
        var total = 0.0
        for i in pts.indices {
            if i > 0 {
                total += haversine(pts[i - 1].lat, pts[i - 1].lon, pts[i].lat, pts[i].lon)
            }
            pts[i].dist = total
        }
    }

    // MARK: stats

    /// Seuil anti-bruit pour le cumul de dénivelé (le D+ brut d'un GPX est gonflé).
    private static let eleNoiseGate = 2.0

    static func stats(for pts: [TrackPoint]) -> TrackStats {
        var s = TrackStats()
        s.pointCount = pts.count
        guard let last = pts.last else { return s }
        s.distance = last.dist

        var lastEle: Double?
        for p in pts {
            guard let e = p.ele else { continue }
            s.minEle = min(s.minEle ?? e, e)
            s.maxEle = max(s.maxEle ?? e, e)
            if let prev = lastEle {
                let d = e - prev
                if d > eleNoiseGate { s.ascent += d; lastEle = e }
                else if d < -eleNoiseGate { s.descent += -d; lastEle = e }
            } else {
                lastEle = e
            }
        }

        if let t0 = pts.first?.time, let t1 = last.time, t1 > t0 {
            s.duration = t1.timeIntervalSince(t0)
        }

        // DIN 33466 adapté (cahier des charges §8) : 4 km/h, 400 m D+/h, 600 m D-/h.
        let th = s.distance / 4000.0          // heures « horizontales »
        let tv = s.ascent / 400.0 + s.descent / 600.0
        s.estimatedDuration = (max(th, tv) + min(th, tv) / 2) * 3600
        return s
    }

    // MARK: éditions

    static func reversed(_ pts: [TrackPoint]) -> [TrackPoint] {
        var out = Array(pts.reversed())
        for i in out.indices { out[i].time = nil }   // les horaires n'ont plus de sens
        accumulateDistances(&out)
        return out
    }

    /// Lissage d'altitude par moyenne glissante (fenêtre impaire).
    static func smoothedElevation(_ pts: [TrackPoint], window: Int = 5) -> [TrackPoint] {
        guard pts.count > window else { return pts }
        var out = pts
        let half = window / 2
        for i in pts.indices {
            var sum = 0.0
            var n = 0.0
            for j in max(0, i - half)...min(pts.count - 1, i + half) {
                if let e = pts[j].ele { sum += e; n += 1 }
            }
            if n > 0 { out[i].ele = sum / n }
        }
        return out
    }

    /// Douglas-Peucker, tolérance en mètres (itératif, pas de récursion profonde).
    static func simplified(_ pts: [TrackPoint], toleranceMeters: Double) -> [TrackPoint] {
        guard pts.count > 2 else { return pts }
        let cosLat = cos(pts[pts.count / 2].lat * .pi / 180)
        let mLat = 111_320.0
        let mLon = 111_320.0 * cosLat
        func px(_ p: TrackPoint) -> (x: Double, y: Double) { (p.lon * mLon, p.lat * mLat) }

        var keep = [Bool](repeating: false, count: pts.count)
        keep[0] = true
        keep[pts.count - 1] = true
        var stack: [(Int, Int)] = [(0, pts.count - 1)]

        while let (a, b) = stack.popLast() {
            guard b > a + 1 else { continue }
            let pa = px(pts[a])
            let pb = px(pts[b])
            let dx = pb.x - pa.x
            let dy = pb.y - pa.y
            let len2 = max(dx * dx + dy * dy, 1e-9)
            var worst = -1.0
            var worstIdx = a
            for i in (a + 1)..<b {
                let p = px(pts[i])
                let t = max(0, min(1, ((p.x - pa.x) * dx + (p.y - pa.y) * dy) / len2))
                let ex = pa.x + t * dx - p.x
                let ey = pa.y + t * dy - p.y
                let d = (ex * ex + ey * ey).squareRoot()
                if d > worst { worst = d; worstIdx = i }
            }
            if worst > toleranceMeters {
                keep[worstIdx] = true
                stack.append((a, worstIdx))
                stack.append((worstIdx, b))
            }
        }
        var out: [TrackPoint] = []
        for i in pts.indices where keep[i] { out.append(pts[i]) }
        accumulateDistances(&out)
        return out
    }

    // MARK: accrochage (suivi)

    struct Snap {
        var dist: Double        // distance cumulée projetée (m)
        var offset: Double      // écart perpendiculaire (m)
        var lat: Double
        var lon: Double
        var segIdx: Int
    }

    /// Projette une position sur la trace ; `hint` = dernier segment connu.
    static func snap(to pts: [TrackPoint], lat: Double, lon: Double, hint: Int?) -> Snap? {
        guard pts.count >= 2 else { return nil }
        let cosLat = cos(lat * .pi / 180)
        let mLat = 111_320.0
        let mLon = 111_320.0 * cosLat

        var from = 0
        var to = pts.count - 2
        if let h = hint {
            from = max(0, h - 40)
            to = min(pts.count - 2, h + 80)
        }

        var best = Snap(dist: 0, offset: .infinity, lat: pts[0].lat, lon: pts[0].lon, segIdx: 0)
        for i in from...to {
            let ax = (pts[i].lon - lon) * mLon
            let ay = (pts[i].lat - lat) * mLat
            let bx = (pts[i + 1].lon - lon) * mLon
            let by = (pts[i + 1].lat - lat) * mLat
            let dx = bx - ax
            let dy = by - ay
            let len2 = max(dx * dx + dy * dy, 1e-9)
            var t = -(ax * dx + ay * dy) / len2
            t = max(0, min(1, t))
            let ox = ax + t * dx
            let oy = ay + t * dy
            let off = (ox * ox + oy * oy).squareRoot()
            if off < best.offset {
                let segLen = pts[i + 1].dist - pts[i].dist
                best = Snap(
                    dist: pts[i].dist + t * segLen,
                    offset: off,
                    lat: pts[i].lat + t * (pts[i + 1].lat - pts[i].lat),
                    lon: pts[i].lon + t * (pts[i + 1].lon - pts[i].lon),
                    segIdx: i
                )
            }
        }
        if hint != nil && best.offset > 80 {
            return snap(to: pts, lat: lat, lon: lon, hint: nil)
        }
        return best
    }
}
