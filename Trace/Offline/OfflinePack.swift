//  OfflinePack.swift
//  Packs de cartes hors ligne (§4.3) : téléchargement des tuiles
//  d'une zone (bbox autour d'une trace) sur une plage de zooms,
//  avec estimation de taille, progression et reprise (les tuiles
//  déjà en cache ne sont pas retéléchargées).

import Foundation
import SwiftData

@Model
final class OfflinePackRecord {
    @Attribute(.unique) var uuid: UUID
    var name: String
    var providerID: String
    var providerLabel: String
    var west: Double
    var south: Double
    var east: Double
    var north: Double
    var zMin: Int
    var zMax: Int
    var tileCount: Int
    var bytes: Int
    var createdAt: Date

    init(uuid: UUID = UUID(), name: String, providerID: String, providerLabel: String,
         west: Double, south: Double, east: Double, north: Double,
         zMin: Int, zMax: Int, tileCount: Int, bytes: Int) {
        self.uuid = uuid
        self.name = name
        self.providerID = providerID
        self.providerLabel = providerLabel
        self.west = west
        self.south = south
        self.east = east
        self.north = north
        self.zMin = zMin
        self.zMax = zMax
        self.tileCount = tileCount
        self.bytes = bytes
        self.createdAt = Date()
    }
}

@MainActor
final class OfflineDownloader: ObservableObject {
    @Published var isRunning = false
    @Published var done = 0
    @Published var total = 0
    @Published var bytes = 0
    private var cancelled = false

    func cancel() { cancelled = true }

    /// Télécharge la zone ; renvoie (tuiles réussies, octets) ou nil si annulé.
    func download(provider: RasterProvider,
                  west: Double, south: Double, east: Double, north: Double,
                  zMin: Int, zMax: Int) async -> (count: Int, bytes: Int)? {
        let tiles = TileCache.tiles(west: west, south: south, east: east, north: north,
                                    zMin: zMin, zMax: zMax)
        isRunning = true
        cancelled = false
        done = 0
        bytes = 0
        total = tiles.count

        var okCount = 0
        var okBytes = 0

        // 4 téléchargements en parallèle, séquencé par lots pour rester simple
        var index = 0
        while index < tiles.count && !cancelled {
            let batch = Array(tiles[index..<min(index + 4, tiles.count)])
            index += batch.count
            await withTaskGroup(of: Int.self) { group in
                for t in batch {
                    group.addTask {
                        // déjà en cache → gratuit
                        if TileCache.data(provider: provider.id, z: t.z, x: t.x, y: t.y) != nil {
                            return 0
                        }
                        let urlString = provider.urlTemplate
                            .replacingOccurrences(of: "{z}", with: String(t.z))
                            .replacingOccurrences(of: "{x}", with: String(t.x))
                            .replacingOccurrences(of: "{y}", with: String(t.y))
                        guard let url = URL(string: urlString) else { return -1 }
                        do {
                            let (data, resp) = try await TileCache.session.data(from: url)
                            guard let http = resp as? HTTPURLResponse,
                                  http.statusCode == 200, !data.isEmpty else { return -1 }
                            TileCache.store(data, provider: provider.id,
                                            z: t.z, x: t.x, y: t.y)
                            return data.count
                        } catch {
                            return -1
                        }
                    }
                }
                for await size in group {
                    done += 1
                    if size >= 0 {
                        okCount += 1
                        okBytes += size
                    }
                }
            }
        }

        isRunning = false
        return cancelled ? nil : (okCount, okBytes)
    }

    /// Supprime du disque les tuiles d'un pack (best effort : le cache est partagé).
    static func evict(record: OfflinePackRecord) {
        for t in TileCache.tiles(west: record.west, south: record.south,
                                 east: record.east, north: record.north,
                                 zMin: record.zMin, zMax: record.zMax) {
            TileCache.delete(provider: record.providerID, z: t.z, x: t.x, y: t.y)
        }
    }

    static func fmtBytes(_ b: Int) -> String {
        if b >= 1_048_576 { return String(format: "%.1f Mo", Double(b) / 1_048_576) }
        if b >= 1024 { return "\(b / 1024) Ko" }
        return "\(b) o"
    }
}
