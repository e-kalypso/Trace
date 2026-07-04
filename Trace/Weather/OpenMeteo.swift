//  OpenMeteo.swift
//  Client Open-Meteo (§5.1 — gratuit, sans clé, modèles haute résolution).
//  Fournit les variables montagne : rafales, CAPE (orage), isotherme 0 °C,
//  UV, ressenti, visibilité par la couverture nuageuse.

import Foundation

struct HourlyWeather {
    var time: Date
    var temperature: Double?
    var feelsLike: Double?
    var precipProbability: Double?
    var precipitation: Double?
    var windSpeed: Double?       // km/h
    var windGusts: Double?       // km/h
    var windDirection: Double?
    var cloudCover: Double?
    var cape: Double?            // J/kg — instabilité orageuse
    var freezingLevel: Double?   // m — isotherme 0 °C
    var uvIndex: Double?
}

enum WeatherRisk {
    case go, caution, noGo

    var label: String {
        switch self {
        case .go: return "Conditions favorables"
        case .caution: return "Prudence"
        case .noGo: return "Défavorable"
        }
    }
    var symbol: String {
        switch self {
        case .go: return "checkmark.circle.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .noGo: return "xmark.octagon.fill"
        }
    }
}

enum OpenMeteo {

    struct Response: Decodable {
        struct Hourly: Decodable {
            let time: [String]
            let temperature_2m: [Double?]?
            let apparent_temperature: [Double?]?
            let precipitation_probability: [Double?]?
            let precipitation: [Double?]?
            let windspeed_10m: [Double?]?
            let windgusts_10m: [Double?]?
            let winddirection_10m: [Double?]?
            let cloudcover: [Double?]?
            let cape: [Double?]?
            let freezing_level_height: [Double?]?
            let uv_index: [Double?]?
        }
        let hourly: Hourly
        let utc_offset_seconds: Int
    }

    /// Prévisions horaires (7 jours) pour un point.
    static func forecast(lat: Double, lon: Double) async throws -> [HourlyWeather] {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", lon)),
            URLQueryItem(name: "hourly", value:
                "temperature_2m,apparent_temperature,precipitation_probability,precipitation,"
                + "windspeed_10m,windgusts_10m,winddirection_10m,cloudcover,cape,"
                + "freezing_level_height,uv_index"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        let resp = try JSONDecoder().decode(Response.self, from: data)

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm"
        fmt.timeZone = TimeZone(secondsFromGMT: resp.utc_offset_seconds)

        var out: [HourlyWeather] = []
        let h = resp.hourly
        for (i, ts) in h.time.enumerated() {
            guard let date = fmt.date(from: ts) else { continue }
            func v(_ arr: [Double?]?) -> Double? {
                guard let arr, i < arr.count else { return nil }
                return arr[i]
            }
            out.append(HourlyWeather(
                time: date,
                temperature: v(h.temperature_2m),
                feelsLike: v(h.apparent_temperature),
                precipProbability: v(h.precipitation_probability),
                precipitation: v(h.precipitation),
                windSpeed: v(h.windspeed_10m),
                windGusts: v(h.windgusts_10m),
                windDirection: v(h.winddirection_10m),
                cloudCover: v(h.cloudcover),
                cape: v(h.cape),
                freezingLevel: v(h.freezing_level_height),
                uvIndex: v(h.uv_index)
            ))
        }
        return out
    }

    /// L'heure de prévision la plus proche d'une date cible.
    static func nearest(_ hours: [HourlyWeather], to target: Date) -> HourlyWeather? {
        hours.min { abs($0.time.timeIntervalSince(target)) < abs($1.time.timeIntervalSince(target)) }
    }

    /// Code couleur go / prudence / no-go (§5.4), adapté montagne.
    static func risk(_ w: HourlyWeather, summitEle: Double?) -> WeatherRisk {
        let cape = w.cape ?? 0
        let gusts = w.windGusts ?? 0
        let prob = w.precipProbability ?? 0
        if cape > 1500 || gusts > 70 || prob > 70 { return .noGo }
        var caution = cape > 800 || gusts > 45 || prob > 40
        if let fl = w.freezingLevel, let summit = summitEle, fl < summit + 200 {
            caution = true   // limite pluie/neige proche du point culminant
        }
        return caution ? .caution : .go
    }
}
