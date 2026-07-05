//  ElevationService.swift
//  Ajoute l'altitude aux traces qui n'en ont pas (imports Découvrir,
//  itinéraires créés en ligne droite…) via l'API Elevation
//  d'Open-Meteo (gratuite, sans clé), par lots de 100 points.

import Foundation

enum ElevationService {
    private struct Response: Decodable { let elevation: [Double] }

    /// Renvoie les points enrichis d'altitude, ou nil si le réseau échoue.
    static func fillElevation(_ pts: [TrackPoint]) async -> [TrackPoint]? {
        guard !pts.isEmpty else { return pts }
        var out = pts
        var i = 0
        while i < pts.count {
            let chunk = Array(pts[i..<min(i + 100, pts.count)])
            let lats = chunk.map { String(format: "%.5f", $0.lat) }.joined(separator: ",")
            let lons = chunk.map { String(format: "%.5f", $0.lon) }.joined(separator: ",")
            guard let url = URL(string:
                "https://api.open-meteo.com/v1/elevation?latitude=\(lats)&longitude=\(lons)")
            else { return nil }
            do {
                let (data, resp) = try await URLSession.shared.data(from: url)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                let eles = try JSONDecoder().decode(Response.self, from: data).elevation
                for (j, e) in eles.enumerated() where i + j < out.count {
                    out[i + j].ele = e
                }
            } catch {
                return nil
            }
            i += 100
        }
        return out
    }
}
