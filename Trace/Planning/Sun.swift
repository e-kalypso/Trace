//  Sun.swift
//  Lever / coucher du soleil, calcul NOAA simplifié — 100 % local,
//  aucun réseau requis (offline-first, §8 « retour avant la nuit »).

import Foundation

enum Sun {

    /// Lever et coucher (heure locale) pour une date et une position.
    static func times(date: Date, lat: Double, lon: Double)
        -> (sunrise: Date?, sunset: Date?) {
        (event(rise: true, date: date, lat: lat, lon: lon),
         event(rise: false, date: date, lat: lat, lon: lon))
    }

    private static func event(rise: Bool, date: Date, lat: Double, lon: Double) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let day = cal.ordinality(of: .day, in: .year, for: date) ?? 1

        let zenith = 90.833 * Double.pi / 180
        let latRad = lat * .pi / 180

        let lngHour = lon / 15
        let t = Double(day) + ((rise ? 6.0 : 18.0) - lngHour) / 24

        // anomalie moyenne
        let m = (0.9856 * t) - 3.289
        // vraie longitude du soleil
        var l = m + (1.916 * sin(m * .pi / 180)) + (0.020 * sin(2 * m * .pi / 180)) + 282.634
        l = fmod(l + 360, 360)

        // ascension droite
        var ra = atan(0.91764 * tan(l * .pi / 180)) * 180 / .pi
        ra = fmod(ra + 360, 360)
        let lQuadrant = floor(l / 90) * 90
        let raQuadrant = floor(ra / 90) * 90
        ra = (ra + (lQuadrant - raQuadrant)) / 15

        // déclinaison
        let sinDec = 0.39782 * sin(l * .pi / 180)
        let cosDec = cos(asin(sinDec))

        // angle horaire
        let cosH = (cos(zenith) - (sinDec * sin(latRad))) / (cosDec * cos(latRad))
        if cosH > 1 || cosH < -1 { return nil }   // soleil de minuit / nuit polaire

        var h = rise
            ? 360 - acos(cosH) * 180 / .pi
            : acos(cosH) * 180 / .pi
        h /= 15

        let tUTC = fmod(h + ra - (0.06571 * t) - 6.622 - lngHour + 24, 24)

        var comps = cal.dateComponents([.year, .month, .day], from: date)
        comps.hour = 0
        comps.minute = 0
        guard let midnightUTC = cal.date(from: comps) else { return nil }
        return midnightUTC.addingTimeInterval(tUTC * 3600)
    }
}
