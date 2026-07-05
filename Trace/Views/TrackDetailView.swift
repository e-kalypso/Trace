//  TrackDetailView.swift
//  Détail d'une trace : stats, profil altimétrique interactif,
//  Suivre, et les éditions (inverser, simplifier, lisser, couleur…).

import SwiftData
import UIKit
import SwiftUI

struct TrackDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @Query(sort: \TrackRecord.sortOrder) private var records: [TrackRecord]

    let record: TrackRecord

    @State private var busyNetwork = false
    @State private var netToast: String?
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

                Section {
                    Button {
                        if let first = t.points.first {
                            model.startGuide(name: "Départ · \(record.name)",
                                             lat: first.lat, lon: first.lon)
                        }
                    } label: {
                        Label("Cap vers le départ (hors ligne)", systemImage: "safari")
                    }
                    NavigationLink {
                        PlanView(record: record)
                    } label: {
                        Label("Planifier (horaires, météo, nuit)", systemImage: "calendar.badge.clock")
                    }
                    NavigationLink {
                        OfflineView(record: record)
                    } label: {
                        Label("Télécharger la zone hors ligne", systemImage: "arrow.down.circle")
                    }
                    ShareLink(item: GPXStore.url(for: record.uuid)) {
                        Label("Partager le fichier GPX", systemImage: "square.and.arrow.up")
                    }
                    NavigationLink {
                        CompareView(record: record)
                    } label: {
                        Label("Comparer avec une autre trace", systemImage: "square.split.2x1")
                    }
                    if t.stats.maxEle == nil {
                        Button {
                            addElevation()
                        } label: {
                            if busyNetwork {
                                HStack { ProgressView(); Text("Altitude en cours…") }
                            } else {
                                Label("Ajouter l'altitude (en ligne)", systemImage: "arrow.up.forward.square")
                            }
                        }
                        .disabled(busyNetwork)
                    }
                    Button {
                        findPOIs()
                    } label: {
                        if busyNetwork {
                            HStack { ProgressView(); Text("Recherche en cours…") }
                        } else {
                            Label("Eau & refuges sur l'itinéraire", systemImage: "drop.fill")
                        }
                    }
                    .disabled(busyNetwork)
                    if let netToast {
                        Text(netToast).font(.footnote).foregroundStyle(.secondary)
                    }
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
                        apply { TrackGeometry.cleaned($0) }
                    } label: {
                        Label("Nettoyer les points aberrants", systemImage: "sparkles")
                    }
                    NavigationLink {
                        CutView(record: record)
                    } label: {
                        Label("Couper / rogner / scinder", systemImage: "scissors")
                    }
                    NavigationLink {
                        MergeView(record: record)
                    } label: {
                        Label("Fusionner avec une autre trace", systemImage: "link")
                    }
                    Button {
                        duplicate()
                    } label: {
                        Label("Dupliquer", systemImage: "plus.square.on.square")
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
                stat("Durée est.", Fmt.duration(s.estimatedDuration * model.paceFactor))
            }
            HStack {
                stat("Km-effort", String(format: "%.1f", s.distance / 1000 + s.ascent / 100))
                stat("Énergie", Fmt.kcal(weightKg: model.weightKg,
                                          distanceM: s.distance, ascent: s.ascent))
                stat("Points", "\(s.pointCount)")
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

    // MARK: réseau

    private func addElevation() {
        guard let t = parsed else { return }
        busyNetwork = true
        Task { @MainActor in
            if let filled = await ElevationService.fillElevation(t.points) {
                rewrite(points: filled, waypoints: t.waypoints)
                netToast = "Altitude ajoutée ✓ (D+ recalculé)"
            } else {
                netToast = "Altitude indisponible (hors ligne ?)"
            }
            busyNetwork = false
        }
    }

    private func findPOIs() {
        guard let t = parsed else { return }
        busyNetwork = true
        Task { @MainActor in
            do {
                let pois = try await POIFinder.findAlong(points: t.points)
                for poi in pois {
                    context.insert(WaypointRecord(
                        name: poi.name, category: poi.category,
                        lat: poi.lat, lon: poi.lon, ele: nil))
                }
                netToast = pois.isEmpty
                    ? "Aucun point d'eau ni refuge trouvé le long de la trace"
                    : "\(pois.count) repère(s) ajouté(s) : eau et refuges ✓"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                netToast = "Recherche indisponible (hors ligne ?)"
            }
            busyNetwork = false
        }
    }

    // MARK: éditions

    /// Copie indépendante de la trace (avant une édition destructive).
    private func duplicate() {
        guard let t = parsed else { return }
        let uuid = UUID()
        let name = "\(record.name) copie"
        let gpx = GPXWriter.gpx(name: name, points: t.points, waypoints: t.waypoints)
        guard (try? GPXStore.save(gpx, for: uuid)) != nil else { return }
        context.insert(TrackRecord(
            uuid: uuid, name: name,
            colorHex: TrackPalette.hex(at: records.count),
            sortOrder: records.count,
            distance: record.distance, ascent: record.ascent, descent: record.descent))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

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
