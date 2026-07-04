//  TrackRecord.swift
//  Persistance : SwiftData pour les métadonnées, fichier .gpx brut sur
//  disque (source de vérité, portable). Offline-first par construction.

import Foundation
import SwiftData

@Model
final class TrackRecord {
    @Attribute(.unique) var uuid: UUID
    var name: String
    var colorHex: String
    var isVisible: Bool
    var sortOrder: Int
    var createdAt: Date
    // stats dénormalisées pour lister sans re-parser
    var distance: Double
    var ascent: Double
    var descent: Double

    init(uuid: UUID = UUID(), name: String, colorHex: String, sortOrder: Int,
         distance: Double, ascent: Double, descent: Double) {
        self.uuid = uuid
        self.name = name
        self.colorHex = colorHex
        self.isVisible = true
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.distance = distance
        self.ascent = ascent
        self.descent = descent
    }
}

/// Palette iOS attribuée aux traces à l'import.
enum TrackPalette {
    static let hexes = ["0A84FF", "FF9F0A", "30D158", "BF5AF2", "FF375F", "40C8E0"]
    static func hex(at index: Int) -> String { hexes[index % hexes.count] }
}

/// Fichiers GPX bruts dans Application Support/GPX/<uuid>.gpx.
enum GPXStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("GPX", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for uuid: UUID) -> URL {
        directory.appendingPathComponent("\(uuid.uuidString).gpx")
    }

    static func save(_ text: String, for uuid: UUID) throws {
        try text.write(to: url(for: uuid), atomically: true, encoding: .utf8)
    }

    static func data(for uuid: UUID) -> Data? {
        try? Data(contentsOf: url(for: uuid))
    }

    static func delete(for uuid: UUID) {
        try? FileManager.default.removeItem(at: url(for: uuid))
    }
}
