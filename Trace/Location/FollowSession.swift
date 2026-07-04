//  FollowSession.swift
//  Suivi d'une trace : accrochage de la position, distance restante,
//  alerte hors-trace (vibration + notification), sans voix.

import CoreLocation
import Foundation
import UIKit
import UserNotifications

final class FollowSession: ObservableObject {

    struct State {
        var done: Double = 0
        var remaining: Double = 0
        var offset: Double = 0
        var offRoute = false
        var arrived = false
        var etaSeconds: Double?
        var progress: Double = 0            // 0…1
        var nextWaypointName: String?
        var nextWaypointIn: Double?         // m le long de la trace
    }

    @Published var state = State()

    let points: [TrackPoint]
    let trackName: String
    private let total: Double
    private var hint: Int?
    private var offRouteSince: Date?
    private var offRouteNotified = false
    private var arrivedNotified = false
    private var emaSpeed: Double = 1.1   // ~4 km/h

    /// Waypoints du GPX projetés sur la trace (nom, distance cumulée).
    private let routeWaypoints: [(name: String, dist: Double)]
    private var notifiedWaypoints: Set<Int> = []

    static let offRouteThreshold: Double = 45      // m
    private static let offRouteDelay: TimeInterval = 12
    private static let arriveThreshold: Double = 25
    private static let waypointAlert: Double = 120

    init(points: [TrackPoint], name: String, waypoints: [Waypoint] = []) {
        self.points = points
        self.trackName = name
        self.total = points.last?.dist ?? 0
        self.routeWaypoints = waypoints
            .compactMap { w in
                guard let s = TrackGeometry.snap(to: points, lat: w.lat, lon: w.lon,
                                                 hint: nil),
                      s.offset < 200 else { return nil }   // trop loin = pas sur l'itinéraire
                return (w.name, s.dist)
            }
            .sorted { $0.dist < $1.dist }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func update(with fix: GeoFix) {
        guard let snap = TrackGeometry.snap(to: points,
                                            lat: fix.coordinate.latitude,
                                            lon: fix.coordinate.longitude,
                                            hint: hint) else { return }
        hint = snap.segIdx

        var s = State()
        s.done = min(snap.dist, total)
        s.remaining = max(0, total - s.done)
        s.offset = snap.offset

        if fix.speed > 0.1 && fix.speed < 12 {
            emaSpeed = emaSpeed * 0.8 + fix.speed * 0.2
        }
        s.etaSeconds = s.remaining / max(0.6, emaSpeed)

        // hors-trace temporisé (ignore les pertes GPS ponctuelles)
        if snap.offset > Self.offRouteThreshold {
            if offRouteSince == nil { offRouteSince = Date() }
            if let since = offRouteSince, Date().timeIntervalSince(since) > Self.offRouteDelay {
                s.offRoute = true
                if !offRouteNotified {
                    offRouteNotified = true
                    Self.haptic(.warning)
                    Self.notify(title: "Hors trace",
                                body: "Vous vous éloignez de « \(trackName) » (\(Int(snap.offset)) m).")
                }
            }
        } else {
            offRouteSince = nil
            offRouteNotified = false
        }

        s.progress = total > 0 ? s.done / total : 0

        // prochain waypoint devant nous + alerte d'approche
        for (i, wp) in routeWaypoints.enumerated() where wp.dist > s.done {
            s.nextWaypointName = wp.name
            s.nextWaypointIn = wp.dist - s.done
            if wp.dist - s.done < Self.waypointAlert && !notifiedWaypoints.contains(i) {
                notifiedWaypoints.insert(i)
                Self.haptic(.success)
                Self.notify(title: wp.name,
                            body: "À \(Int(wp.dist - s.done)) m devant vous.")
            }
            break
        }

        if s.remaining <= Self.arriveThreshold {
            s.arrived = true
            if !arrivedNotified {
                arrivedNotified = true
                Self.haptic(.success)
                Self.notify(title: "Arrivée", body: "Vous êtes au bout de « \(trackName) ». Bravo !")
            }
        }

        state = s
    }

    private static func haptic(_ kind: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(kind)
    }

    private static func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString,
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
