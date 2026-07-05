//  History.swift
//  Carnet de randonnées : chaque sortie (enregistrée ou suivie) est
//  consignée automatiquement. Totaux à vie + liste chronologique.

import Foundation
import SwiftData
import SwiftUI

@Model
final class HikeLogRecord {
    @Attribute(.unique) var uuid: UUID
    var date: Date
    var name: String
    var distance: Double
    var ascent: Double
    var duration: TimeInterval
    var kind: String        // "Enregistrée" | "Suivie"

    init(name: String, distance: Double, ascent: Double,
         duration: TimeInterval, kind: String) {
        self.uuid = UUID()
        self.date = Date()
        self.name = name
        self.distance = distance
        self.ascent = ascent
        self.duration = duration
        self.kind = kind
    }
}

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var model: AppModel
    @Query(sort: \HikeLogRecord.date, order: .reverse)
    private var logs: [HikeLogRecord]

    private var totalKm: Double { logs.reduce(0) { $0 + $1.distance } }
    private var totalUp: Double { logs.reduce(0) { $0 + $1.ascent } }
    private var totalTime: TimeInterval { logs.reduce(0) { $0 + $1.duration } }

    var body: some View {
        List {
            Section {
                HStack {
                    total("\(logs.count)", "sorties")
                    total(Fmt.distance(totalKm), "au total")
                    total("+\(Int(totalUp)) m", "D+ cumulé")
                    total(Fmt.duration(totalTime), "en marche")
                }
                .padding(.vertical, 4)
            } header: {
                Text("Depuis le début")
            }

            Section {
                if logs.isEmpty {
                    Text("Vos sorties enregistrées ou suivies apparaîtront ici.")
                        .foregroundStyle(.secondary)
                }
                ForEach(logs) { log in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(log.name).font(.body.weight(.semibold)).lineLimit(1)
                            Spacer()
                            Text(log.kind)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15),
                                            in: Capsule())
                        }
                        Text("\(log.date.formatted(date: .abbreviated, time: .shortened)) · \(Fmt.distance(log.distance)) · +\(Int(log.ascent)) m · \(Fmt.duration(log.duration)) · \(Fmt.kcal(weightKg: model.weightKg, distanceM: log.distance, ascent: log.ascent))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    for i in offsets { context.delete(logs[i]) }
                }
            } header: {
                Text("Sorties")
            }
        }
        .navigationTitle("Carnet")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func total(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.monospacedDigit().weight(.bold))
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
