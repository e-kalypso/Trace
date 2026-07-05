//  POIFinder.swift
//  Trouve les points d'EAU (sources, fontaines) et les REFUGES/cabanes
//  le long d'une trace (OSM Overpass), et les ajoute comme repères —
//  à moins de 400 m de l'itinéraire uniquement.

import Foundation

enum POIFinder {
    struct POI {
        let name: String
        let lat: Double
        let lon: Double
        let category: WaypointCategory
    }

    private struct Response: Decodable {
        struct Element: Decodable {
            let lat: Double?
            let lon: Double?
            let tags: [String: String]?
        }
        let elements: [Element]
    }

    /// POI eau + refuges à moins de `maxOffset` m de la trace.
    static func findAlong(points: [TrackPoint],
                          maxOffset: Double = 400) async throws -> [POI] {
        guard points.count >= 2 else { return [] }
        var w = 180.0, s = 90.0, e = -180.0, n = -90.0
        for p in points {
            w = min(w, p.lon); e = max(e, p.lon)
            s = min(s, p.lat); n = max(n, p.lat)
        }
        let pad = 0.006
        let bbox = "\(s - pad),\(w - pad),\(n + pad),\(e + pad)"
        let query = """
        [out:json][timeout:25];
        (
          node["natural"="spring"](\(bbox));
          node["amenity"="drinking_water"](\(bbox));
          node["tourism"~"alpine_hut|wilderness_hut"](\(bbox));
        );
        out 120;
        """
        var req = URLRequest(url: URL(string: "https://overpass-api.de/api/interpreter")!)
        req.httpMethod = "POST"
        req.httpBody = "data=\(query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query)"
            .data(using: .utf8)
        req.timeoutInterval = 30
        let (data, _) = try await URLSession.shared.data(for: req)
        let resp = try JSONDecoder().decode(Response.self, from: data)

        var out: [POI] = []
        for el in resp.elements {
            guard let lat = el.lat, let lon = el.lon else { continue }
            guard let snap = TrackGeometry.snap(to: points, lat: lat, lon: lon, hint: nil),
                  snap.offset <= maxOffset else { continue }
            let tags = el.tags ?? [:]
            let isHut = (tags["tourism"] ?? "").contains("hut")
            let name = tags["name"]
                ?? (isHut ? "Refuge" : tags["amenity"] == "drinking_water" ? "Eau potable" : "Source")
            out.append(POI(name: name, lat: lat, lon: lon,
                           category: isHut ? .refuge : .eau))
        }
        return out
    }
}
