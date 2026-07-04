//  WaypointRecord.swift
//  Waypoints personnels (§3.5) : posés par appui long sur la carte,
//  catégorisés avec SF Symbols, persistés en SwiftData.

import Foundation
import SwiftData

enum WaypointCategory: String, CaseIterable, Identifiable {
    case eau, refuge, bivouac, danger, vue, parking, sommet, col

    var id: String { rawValue }

    var label: String {
        switch self {
        case .eau: return "Eau / source"
        case .refuge: return "Refuge"
        case .bivouac: return "Bivouac"
        case .danger: return "Danger"
        case .vue: return "Point de vue"
        case .parking: return "Parking"
        case .sommet: return "Sommet"
        case .col: return "Col"
        }
    }

    var symbol: String {
        switch self {
        case .eau: return "drop.fill"
        case .refuge: return "house.fill"
        case .bivouac: return "tent.fill"
        case .danger: return "exclamationmark.triangle.fill"
        case .vue: return "binoculars.fill"
        case .parking: return "parkingsign"
        case .sommet: return "mountain.2.fill"
        case .col: return "point.topleft.down.curvedto.point.bottomright.up"
        }
    }
}

@Model
final class WaypointRecord {
    @Attribute(.unique) var uuid: UUID
    var name: String
    var categoryRaw: String
    var lat: Double
    var lon: Double
    var ele: Double?
    var createdAt: Date

    var category: WaypointCategory {
        WaypointCategory(rawValue: categoryRaw) ?? .vue
    }

    init(name: String, category: WaypointCategory, lat: Double, lon: Double, ele: Double?) {
        self.uuid = UUID()
        self.name = name
        self.categoryRaw = category.rawValue
        self.lat = lat
        self.lon = lon
        self.ele = ele
        self.createdAt = Date()
    }
}
