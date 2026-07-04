//  LocationManager.swift
//  Géolocalisation « GPS de rando » :
//  - CoreLocation multi-constellation, précision BestForNavigation
//  - altitude BAROMÉTRIQUE (CMAltimeter) recalée doucement sur le GPS :
//    bien plus stable en montagne que l'altitude GPS brute
//  - filtrage des fixes trop imprécis + indicateur de qualité
//  - arrière-plan uniquement pendant un suivi (batterie)

import CoreLocation
import CoreMotion
import Foundation

struct GeoFix {
    var coordinate: CLLocationCoordinate2D
    var horizontalAccuracy: Double
    var altitude: Double          // m, fusion baro/GPS
    var speed: Double             // m/s (>= 0)
    var course: Double            // degrés, -1 si inconnu
    var timestamp: Date
}

enum GPSQuality: String {
    case excellent = "Excellent"
    case good = "Bon"
    case poor = "Faible"
    case none = "Recherche…"
}

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    @Published var fix: GeoFix?
    @Published var quality: GPSQuality = .none
    @Published var authorized = false

    private let manager = CLLocationManager()
    private let altimeter = CMAltimeter()

    // Fusion baro : altitude de référence GPS + delta baro depuis la référence.
    private var baroReferenceAltitude: Double?
    private var baroRelative: Double = 0
    private var lastGPSAltitude: Double?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .fitness
        manager.distanceFilter = 3
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func start(background: Bool) {
        requestPermission()
        manager.pausesLocationUpdatesAutomatically = !background
        if background,
           manager.authorizationStatus == .authorizedWhenInUse
            || manager.authorizationStatus == .authorizedAlways {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
        }
        manager.startUpdatingLocation()
        startBarometer()
    }

    func stop() {
        manager.allowsBackgroundLocationUpdates = false
        manager.stopUpdatingLocation()
        altimeter.stopRelativeAltitudeUpdates()
        baroReferenceAltitude = nil
        baroRelative = 0
        quality = .none
    }

    /// Économie de batterie pendant les longs suivis.
    func setBalancedAccuracy(_ balanced: Bool) {
        manager.desiredAccuracy = balanced
            ? kCLLocationAccuracyNearestTenMeters
            : kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = balanced ? 15 : 3
    }

    private func startBarometer() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return }
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            self.baroRelative = data.relativeAltitude.doubleValue
            if self.baroReferenceAltitude == nil, let gps = self.lastGPSAltitude {
                self.baroReferenceAltitude = gps - self.baroRelative
            }
        }
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let st = manager.authorizationStatus
        authorized = (st == .authorizedWhenInUse || st == .authorizedAlways)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let acc = loc.horizontalAccuracy
        // rejet des fixes inutilisables (spec §3.7)
        guard acc > 0, acc < 100 else { return }

        switch acc {
        case ..<8: quality = .excellent
        case ..<20: quality = .good
        default: quality = .poor
        }

        if loc.verticalAccuracy > 0 {
            lastGPSAltitude = loc.altitude
            // recalage lent de la référence baro sur le GPS (dérive météo)
            if let ref = baroReferenceAltitude {
                let fused = ref + baroRelative
                let error = loc.altitude - fused
                baroReferenceAltitude = ref + error * 0.02
            }
        }

        let altitude: Double
        if let ref = baroReferenceAltitude {
            altitude = ref + baroRelative
        } else {
            altitude = loc.altitude
        }

        fix = GeoFix(
            coordinate: loc.coordinate,
            horizontalAccuracy: acc,
            altitude: altitude,
            speed: max(0, loc.speed),
            course: loc.course,
            timestamp: loc.timestamp
        )
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // silencieux : le prochain fix reprendra
    }
}
