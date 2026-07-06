//  CompareView.swift
//  Comparer deux traces côte à côte : distance, D+, D-, altitudes,
//  durée estimée, km-effort. Pour choisir sa sortie du jour.

import SwiftData
import SwiftUI

struct CompareView: View {
    @EnvironmentObject private var model: AppModel
    @Query(sort: \TrackRecord.sortOrder) private var records: [TrackRecord]

    let record: TrackRecord
    @State private var otherUUID: UUID?

    private var other: TrackRecord? {
        records.first { $0.uuid == otherUUID }
    }

    var body: some View {
        List {
            Section("Comparer avec") {
                ForEach(records.filter { $0.uuid != record.uuid }) { rec in
                    Button {
                        otherUUID = rec.uuid
                    } label: {
                        HStack {
                            Circle().fill(Color(hex: rec.colorHex))
                                .frame(width: 10, height: 10)
                            Text(rec.name).foregroundStyle(.primary).lineLimit(1)
                            Spacer()
                            if otherUUID == rec.uuid {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }

            if let other,
               let a = model.track(for: record),
               let b = model.track(for: other) {
                Section {
                    row("Distance", Fmt.distance(a.stats.distance), Fmt.distance(b.stats.distance))
                    row("D+", "+\(Int(a.stats.ascent)) m", "+\(Int(b.stats.ascent)) m")
                    row("D-", "−\(Int(a.stats.descent)) m", "−\(Int(b.stats.descent)) m")
                    row("Alt. max", Fmt.elevation(a.stats.maxEle), Fmt.elevation(b.stats.maxEle))
                    row("Durée est.",
                        Fmt.duration(a.stats.estimatedDuration * model.paceFactor),
                        Fmt.duration(b.stats.estimatedDuration * model.paceFactor))
                    row("Km-effort",
                        String(format: "%.1f", a.stats.distance / 1000 + a.stats.ascent / 100),
                        String(format: "%.1f", b.stats.distance / 1000 + b.stats.ascent / 100))
                } header: {
                    HStack {
                        Text(record.name).lineLimit(1)
                        Spacer()
                        Text(other.name).lineLimit(1)
                    }
                }
            }
        }
        .navigationTitle("Comparer")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ label: String, _ a: String, _ b: String) -> some View {
        HStack {
            Text(a).font(.callout.monospacedDigit().weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(label).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            Text(b).font(.callout.monospacedDigit().weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
