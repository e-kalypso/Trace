//  EditTools.swift
//  Édition légère (§3.3) : couper/rogner une trace à un point choisi
//  (curseur visible sur la carte), scinder en deux, fusionner deux traces.

import SwiftData
import SwiftUI
import UIKit

// MARK: - Couper / rogner / scinder

struct CutView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @Query(sort: \TrackRecord.sortOrder) private var records: [TrackRecord]

    let record: TrackRecord
    @State private var cutDist: Double = 0
    @State private var didInit = false

    private var parsed: ParsedTrack? { model.track(for: record) }

    private var cutPoint: TrackPoint? {
        guard let t = parsed, !t.points.isEmpty else { return nil }
        return t.points.min { abs($0.dist - cutDist) < abs($1.dist - cutDist) }
    }

    var body: some View {
        List {
            Section {
                if let t = parsed, let p = cutPoint {
                    VStack(alignment: .leading, spacing: 10) {
                        Slider(value: $cutDist, in: 0...max(1, t.stats.distance))
                        HStack {
                            Text("Point de coupe")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("km \(String(format: "%.2f", p.dist / 1000)) · \(Fmt.elevation(p.ele))")
                                .font(.callout.monospacedDigit().weight(.semibold))
                        }
                        .font(.footnote)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Choisissez le point")
            } footer: {
                Text("Le curseur orange sur la carte suit le point de coupe. Baissez la feuille pour mieux voir.")
            }

            Section("Actions") {
                Button {
                    performCut(keepFirst: true, keepSecond: false)
                } label: {
                    Label("Garder le début (rogner la fin)", systemImage: "arrow.left.to.line")
                }
                Button {
                    performCut(keepFirst: false, keepSecond: true)
                } label: {
                    Label("Garder la fin (rogner le début)", systemImage: "arrow.right.to.line")
                }
                Button {
                    performCut(keepFirst: true, keepSecond: true)
                } label: {
                    Label("Scinder en deux traces", systemImage: "scissors")
                }
            }
        }
        .navigationTitle("Couper")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !didInit, let t = parsed else { return }
            didInit = true
            cutDist = t.stats.distance / 2
        }
        .onChange(of: cutDist) { _, _ in
            if let p = cutPoint {
                model.scrubCoordinate = .init(latitude: p.lat, longitude: p.lon)
            }
        }
        .onDisappear { model.scrubCoordinate = nil }
    }

    private func performCut(keepFirst: Bool, keepSecond: Bool) {
        guard let t = parsed, t.points.count >= 4 else { return }
        let idx = t.points.firstIndex { $0.dist >= cutDist } ?? t.points.count / 2
        guard idx > 1, idx < t.points.count - 2 else { return }

        var first = Array(t.points[0...idx])
        var second = Array(t.points[idx...])
        TrackGeometry.accumulateDistances(&first)
        TrackGeometry.accumulateDistances(&second)

        if keepFirst && keepSecond {
            saveAsNew(points: first, name: "\(record.name) (1/2)", waypoints: t.waypoints)
            saveAsNew(points: second, name: "\(record.name) (2/2)", waypoints: [])
        } else {
            let kept = keepFirst ? first : second
            overwrite(points: kept, waypoints: t.waypoints)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private func overwrite(points: [TrackPoint], waypoints: [Waypoint]) {
        let gpx = GPXWriter.gpx(name: record.name, points: points, waypoints: waypoints)
        try? GPXStore.save(gpx, for: record.uuid)
        let s = TrackGeometry.stats(for: points)
        record.distance = s.distance
        record.ascent = s.ascent
        record.descent = s.descent
        model.invalidate(record.uuid)
        model.mapRevision += 1
    }

    private func saveAsNew(points: [TrackPoint], name: String, waypoints: [Waypoint]) {
        let uuid = UUID()
        let gpx = GPXWriter.gpx(name: name, points: points, waypoints: waypoints)
        guard (try? GPXStore.save(gpx, for: uuid)) != nil else { return }
        let s = TrackGeometry.stats(for: points)
        context.insert(TrackRecord(
            uuid: uuid, name: name,
            colorHex: TrackPalette.hex(at: records.count + Int.random(in: 0...3)),
            sortOrder: records.count,
            distance: s.distance, ascent: s.ascent, descent: s.descent))
    }
}

// MARK: - Fusionner

struct MergeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @Query(sort: \TrackRecord.sortOrder) private var records: [TrackRecord]

    let record: TrackRecord

    var body: some View {
        List {
            Section {
                ForEach(records.filter { $0.uuid != record.uuid }) { other in
                    Button {
                        merge(with: other)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(other.name).foregroundStyle(.primary)
                            Text("\(Fmt.distance(other.distance)) · +\(Int(other.ascent)) m")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Ajouter à la suite de « \(record.name) »")
            } footer: {
                Text("La trace choisie est ajoutée bout à bout. Une nouvelle trace fusionnée est créée, les originales sont conservées.")
            }
        }
        .navigationTitle("Fusionner")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func merge(with other: TrackRecord) {
        guard let a = model.track(for: record),
              let b = model.track(for: other) else { return }
        let pts = TrackGeometry.merged(a.points, b.points)
        let name = "\(record.name) + \(other.name)"
        let uuid = UUID()
        let gpx = GPXWriter.gpx(name: name, points: pts,
                                waypoints: a.waypoints + b.waypoints)
        guard (try? GPXStore.save(gpx, for: uuid)) != nil else { return }
        let s = TrackGeometry.stats(for: pts)
        context.insert(TrackRecord(
            uuid: uuid, name: name,
            colorHex: TrackPalette.hex(at: records.count),
            sortOrder: records.count,
            distance: s.distance, ascent: s.ascent, descent: s.descent))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
