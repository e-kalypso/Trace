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

    private var yearLogs: [HikeLogRecord] {
        let y = Calendar.current.component(.year, from: Date())
        return logs.filter { Calendar.current.component(.year, from: $0.date) == y }
    }
    private var yearKm: Double { yearLogs.reduce(0) { $0 + $1.distance } / 1000 }
    private var yearUp: Double { yearLogs.reduce(0) { $0 + $1.ascent } }

    private struct Badge: Identifiable {
        let id: String
        let symbol: String
        let label: String
        let earned: Bool
    }

    private var badges: [Badge] {
        let km = totalKm / 1000
        return [
            Badge(id: "b1", symbol: "figure.walk", label: "Première sortie", earned: logs.count >= 1),
            Badge(id: "b2", symbol: "shoeprints.fill", label: "10 sorties", earned: logs.count >= 10),
            Badge(id: "b3", symbol: "flame.fill", label: "50 sorties", earned: logs.count >= 50),
            Badge(id: "b4", symbol: "star.fill", label: "100 km", earned: km >= 100),
            Badge(id: "b5", symbol: "map.fill", label: "500 km", earned: km >= 500),
            Badge(id: "b6", symbol: "mountain.2.fill", label: "5 000 m D+", earned: totalUp >= 5000),
            Badge(id: "b7", symbol: "crown.fill", label: "Everest (8 849 m D+)", earned: totalUp >= 8849),
            Badge(id: "b8", symbol: "moon.stars.fill", label: "Grande sortie (20 km+)",
                  earned: logs.contains { $0.distance >= 20000 }),
        ]
    }

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
                goal("Kilomètres", yearKm, model.goalKm, unit: "km")
                goal("Dénivelé positif", yearUp, model.goalUp, unit: "m")
            } header: {
                Text("Objectifs \(String(Calendar.current.component(.year, from: Date())))")
            } footer: {
                Text("Objectifs réglables dans Réglages.")
            }

            Section("Badges") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 12) {
                    ForEach(badges) { b in
                        VStack(spacing: 4) {
                            Image(systemName: b.symbol)
                                .font(.title2)
                                .foregroundStyle(b.earned ? Color.accentColor : .secondary)
                            Text(b.label)
                                .font(.caption2)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            b.earned ? Color.accentColor.opacity(0.12)
                                     : Color.secondary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 10))
                        .opacity(b.earned ? 1 : 0.5)
                    }
                }
                .padding(.vertical, 4)
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

    private func goal(_ label: String, _ value: Double, _ target: Double,
                      unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(value)) / \(Int(target)) \(unit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(1, value / max(1, target)))
                .tint(value >= target ? .green : Color.accentColor)
        }
        .padding(.vertical, 2)
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
