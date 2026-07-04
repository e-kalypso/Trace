//  SequenceView.swift
//  Enchaîner plusieurs traces (raid multi-jours, TMB…) : on choisit
//  l'ordre, puis on suit l'enchaînement d'une traite (avec annonce de
//  chaque étape) ou on crée une trace fusionnée.

import SwiftData
import SwiftUI
import UIKit

struct SequenceView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @Query(sort: \TrackRecord.sortOrder) private var records: [TrackRecord]

    @State private var chain: [UUID] = []

    private var chainRecords: [TrackRecord] {
        chain.compactMap { id in records.first { $0.uuid == id } }
    }
    private var available: [TrackRecord] {
        records.filter { !chain.contains($0.uuid) }
    }
    private var totalKm: Double { chainRecords.reduce(0) { $0 + $1.distance } }
    private var totalUp: Double { chainRecords.reduce(0) { $0 + $1.ascent } }

    var body: some View {
        List {
            Section {
                if chain.isEmpty {
                    Text("Ajoutez des traces ci-dessous, dans l'ordre de marche.")
                        .foregroundStyle(.secondary)
                }
                ForEach(chainRecords) { rec in
                    HStack {
                        Circle().fill(Color(hex: rec.colorHex))
                            .frame(width: 10, height: 10)
                        Text(rec.name).lineLimit(1)
                        Spacer()
                        Text(Fmt.distance(rec.distance))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .onMove { from, to in chain.move(fromOffsets: from, toOffset: to) }
                .onDelete { offsets in chain.remove(atOffsets: offsets) }

                if chain.count >= 2 {
                    LabeledContent("Total") {
                        Text("\(Fmt.distance(totalKm)) · +\(Int(totalUp)) m")
                            .font(.callout.monospacedDigit().weight(.semibold))
                    }
                }
            } header: {
                Text("Enchaînement (\(chain.count) étapes)")
            } footer: {
                Text("Réordonnez par glisser. Pendant le suivi, chaque changement d'étape est annoncé comme un repère.")
            }

            if !available.isEmpty {
                Section("Ajouter une étape") {
                    ForEach(available) { rec in
                        Button {
                            chain.append(rec.uuid)
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                                Text(rec.name).foregroundStyle(.primary).lineLimit(1)
                                Spacer()
                                Text(Fmt.distance(rec.distance))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if chain.count >= 2 {
                Section {
                    Button {
                        followChain()
                    } label: {
                        Label("Suivre l'enchaînement", systemImage: "arrow.triangle.merge")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        mergeChain()
                    } label: {
                        Label("Créer la trace fusionnée", systemImage: "link")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Enchaîner")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
    }

    /// Points combinés + un repère « Étape k » à chaque jonction.
    private func combined() -> (points: [TrackPoint], waypoints: [Waypoint])? {
        var pts: [TrackPoint] = []
        var wpts: [Waypoint] = []
        for (i, rec) in chainRecords.enumerated() {
            guard let t = model.track(for: rec), !t.points.isEmpty else { continue }
            if let first = t.points.first, i > 0 {
                wpts.append(Waypoint(lat: first.lat, lon: first.lon,
                                     name: "Étape \(i + 1) · \(rec.name)",
                                     ele: first.ele))
            }
            pts = pts.isEmpty ? t.points : TrackGeometry.merged(pts, t.points)
            wpts.append(contentsOf: t.waypoints)
        }
        guard pts.count >= 2 else { return nil }
        return (pts, wpts)
    }

    private func followChain() {
        guard let c = combined() else { return }
        model.startFollow(points: c.points,
                          name: "Enchaînement (\(chain.count) étapes)",
                          waypoints: c.waypoints)
        dismiss()
    }

    private func mergeChain() {
        guard let c = combined() else { return }
        let name = "Enchaînement \(chainRecords.first?.name ?? "")…"
        let uuid = UUID()
        let gpx = GPXWriter.gpx(name: name, points: c.points, waypoints: c.waypoints)
        guard (try? GPXStore.save(gpx, for: uuid)) != nil else { return }
        let s = TrackGeometry.stats(for: c.points)
        context.insert(TrackRecord(
            uuid: uuid, name: name,
            colorHex: TrackPalette.hex(at: records.count),
            sortOrder: records.count,
            distance: s.distance, ascent: s.ascent, descent: s.descent))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
