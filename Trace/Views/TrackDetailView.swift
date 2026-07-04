//  TrackDetailView.swift
//  Détail d'une trace : stats, profil altimétrique interactif,
//  Suivre, et les éditions (inverser, simplifier, lisser, couleur…).

import SwiftData
import SwiftUI

struct TrackDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel

    let record: TrackRecord

    @State private var showRename = false
    @State private var newName = ""
    @State private var confirmDelete = false

    private var parsed: ParsedTrack? { model.track(for: record) }

    var body: some View {
        List {
            if let t = parsed {
                Section {
                    statGrid(t)
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                }

                Section("Profil altimétrique") {
                    ElevationChartView(points: t.points) { coord in
                        model.scrubCoordinate = coord
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }

                Section {
                    Button {
                        model.startFollow(record: record)
                    } label: {
                        Label("Suivre cette trace", systemImage: "location.north.line.fill")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    .listRowBackground(Color.clear)
                }

                Section("Couleur") {
                    HStack(spacing: 14) {
                        ForEach(TrackPalette.hexes, id: \.self) { hex in
                            Button {
                                record.colorHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        if record.colorHex == hex {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Édition") {
                    Button {
                        apply { TrackGeometry.reversed($0) }
                    } label: {
                        Label("Inverser le sens", systemImage: "arrow.left.arrow.right")
                    }
                    Button {
                        apply { TrackGeometry.simplified($0, toleranceMeters: 5) }
                    } label: {
                        Label("Simplifier (Douglas-Peucker 5 m)", systemImage: "scissors")
                    }
                    Button {
                        apply { pts in
                            var out = TrackGeometry.smoothedElevation(pts)
                            TrackGeometry.accumulateDistances(&out)
                            return out
                        }
                    } label: {
                        Label("Lisser l'altitude (fiabilise le D+)", systemImage: "waveform.path")
                    }
                    Button {
                        newName = record.name
                        showRename = true
                    } label: {
                        Label("Renommer", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                }
            } else {
                ContentUnavailableView("Fichier illisible", systemImage: "exclamationmark.triangle")
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(record.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let t = parsed {
                model.requestFit(t.points.map {
                    .init(latitude: $0.lat, longitude: $0.lon)
                })
            }
        }
        .onDisappear { model.scrubCoordinate = nil }
        .alert("Renommer", isPresented: $showRename) {
            TextField("Nom", text: $newName)
            Button("Annuler", role: .cancel) {}
            Button("OK") {
                let n = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !n.isEmpty {
                    record.name = n
                    rewrite(points: nil)
                }
            }
        }
        .confirmationDialog("Supprimer « \(record.name) » ?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                GPXStore.delete(for: record.uuid)
                model.invalidate(record.uuid)
                context.delete(record)
                dismiss()
            }
        }
    }

    // MARK: stats

    @ViewBuilder
    private func statGrid(_ t: ParsedTrack) -> some View {
        let s = t.stats
        VStack(spacing: 10) {
            HStack {
                stat("Distance", Fmt.distance(s.distance))
                stat("D+", "+\(Int(s.ascent)) m")
                stat("D-", "−\(Int(s.descent)) m")
            }
            HStack {
                stat("Alt. min", Fmt.elevation(s.minEle))
                stat("Alt. max", Fmt.elevation(s.maxEle))
                stat("Durée est.", Fmt.duration(s.estimatedDuration))
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.bold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: éditions

    /// Applique une transformation géométrique puis réécrit le fichier GPX.
    private func apply(_ transform: ([TrackPoint]) -> [TrackPoint]) {
        guard let t = parsed else { return }
        rewrite(points: transform(t.points), waypoints: t.waypoints)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func rewrite(points: [TrackPoint]?, waypoints: [Waypoint] = []) {
        guard let t = parsed else { return }
        let pts = points ?? t.points
        let wpts = points == nil ? t.waypoints : waypoints
        let gpx = GPXWriter.gpx(name: record.name, points: pts, waypoints: wpts)
        do {
            try GPXStore.save(gpx, for: record.uuid)
            let stats = TrackGeometry.stats(for: pts)
            record.distance = stats.distance
            record.ascent = stats.ascent
            record.descent = stats.descent
            model.invalidate(record.uuid)
            model.mapRevision += 1
        } catch {
            // le fichier d'origine reste intact en cas d'échec d'écriture
        }
    }
}
