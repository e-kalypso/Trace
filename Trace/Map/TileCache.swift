//  TileCache.swift
//  Cache disque persistant des tuiles raster (Application Support/Tiles).
//  Sert à la fois au confort en ligne et aux packs hors ligne (§4.3) :
//  toute tuile affichée ou téléchargée est réutilisable sans réseau.

import Foundation
import MapKit

enum TileCache {

    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Tiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(provider: String, z: Int, x: Int, y: Int) -> URL {
        root.appendingPathComponent("\(provider)/\(z)/\(x)/\(y).tile")
    }

    static func store(_ data: Data, provider: String, z: Int, x: Int, y: Int) {
        let file = url(provider: provider, z: z, x: x, y: y)
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file)
    }

    static func data(provider: String, z: Int, x: Int, y: Int) -> Data? {
        try? Data(contentsOf: url(provider: provider, z: z, x: x, y: y))
    }

    static func delete(provider: String, z: Int, x: Int, y: Int) {
        try? FileManager.default.removeItem(at: url(provider: provider, z: z, x: x, y: y))
    }

    /// Session dédiée avec User-Agent identifié (politique d'usage OSM).
    static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpAdditionalHeaders = ["User-Agent": "Trace-iOS/3.0 (app.trace.gpx)"]
        cfg.timeoutIntervalForRequest = 20
        return URLSession(configuration: cfg)
    }()

    // MARK: maths Web Mercator

    static func tileX(lon: Double, z: Int) -> Int {
        let n = pow(2.0, Double(z))
        return max(0, min(Int(n) - 1, Int((lon + 180) / 360 * n)))
    }

    static func tileY(lat: Double, z: Int) -> Int {
        let n = pow(2.0, Double(z))
        let rad = lat * .pi / 180
        let y = (1 - log(tan(rad) + 1 / cos(rad)) / .pi) / 2 * n
        return max(0, min(Int(n) - 1, Int(y)))
    }

    /// Toutes les tuiles couvrant une bbox sur une plage de zooms.
    static func tiles(west: Double, south: Double, east: Double, north: Double,
                      zMin: Int, zMax: Int) -> [(z: Int, x: Int, y: Int)] {
        var out: [(Int, Int, Int)] = []
        guard zMin <= zMax else { return out }
        for z in zMin...zMax {
            let x0 = tileX(lon: west, z: z)
            let x1 = tileX(lon: east, z: z)
            let y0 = tileY(lat: north, z: z)   // nord = y plus petit
            let y1 = tileY(lat: south, z: z)
            for x in min(x0, x1)...max(x0, x1) {
                for y in min(y0, y1)...max(y0, y1) {
                    out.append((z, x, y))
                }
            }
        }
        return out
    }
}

/// MKTileOverlay qui lit d'abord le cache disque, puis le réseau.
final class CachingTileOverlay: MKTileOverlay {
    let providerID: String

    init(providerID: String, urlTemplate: String) {
        self.providerID = providerID
        super.init(urlTemplate: urlTemplate)
    }

    override func loadTile(at path: MKTileOverlayPath,
                           result: @escaping (Data?, Error?) -> Void) {
        if let cached = TileCache.data(provider: providerID, z: path.z, x: path.x, y: path.y) {
            result(cached, nil)
            return
        }
        let url = url(forTilePath: path)
        TileCache.session.dataTask(with: url) { data, _, error in
            if let data, !data.isEmpty {
                TileCache.store(data, provider: self.providerID,
                                z: path.z, x: path.x, y: path.y)
            }
            result(data, error)
        }.resume()
    }
}
