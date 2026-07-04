//  TraceApp.swift
//  Point d'entrée — SwiftData + état partagé.

import SwiftData
import SwiftUI

@main
struct TraceApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .modelContainer(for: [TrackRecord.self, OfflinePackRecord.self, WaypointRecord.self, HikeLogRecord.self])
    }
}
