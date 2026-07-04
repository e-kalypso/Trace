//  ContentView.swift
//  Écran principal : la carte est le héros, l'UI flotte au-dessus.
//  Feuille à crans façon Plans d'Apple ; HUD de suivi en Liquid Glass.

import CoreLocation
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var model: AppModel
    @Query(sort: \TrackRecord.sortOrder) private var records: [TrackRecord]

    @Query(sort: \WaypointRecord.createdAt) private var waypoints: [WaypointRecord]

    @State private var selectedUUID: UUID?
    @State private var detent: PresentationDetent = .medium
    @State private var showImporter = false
    @State private var pendingImport: PendingImport?
    @State private var toast: String?
    @State private var locatePending = false
    @State private var newWaypointCoord: CLLocationCoordinate2D?
    @State private var showSaveRecording = false
    @State private var recordingName = ""
    @State private var recordedPoints: [TrackPoint] = []

    private var gpxType: UTType {
        UTType(filenameExtension: "gpx") ?? .xml
    }

    var body: some View {
        ZStack {
            MapContainerView(
                tracks: model.mapTracks(records: records, selected: selectedUUID),
                basemap: model.basemap,
                scrub: model.scrubCoordinate,
                fitTarget: model.fitTarget,
                fitRequest: model.fitRequest,
                following: model.follow != nil || model.recording != nil,
                revision: model.mapRevision,
                personalWaypoints: waypoints.map {
                    PersonalWaypointItem(id: $0.uuid, lat: $0.lat, lon: $0.lon,
                                         name: $0.name, symbol: $0.category.symbol)
                },
                onLongPress: { coord in
                    if model.follow == nil { newWaypointCoord = coord }
                }
            )
            .ignoresSafeArea()

            // HUD d'enregistrement (sous-vue observante : stats vivantes)
            if let rec = model.recording {
                RecordingHUDView(rec: rec, location: model.location) {
                    recordedPoints = model.stopRecording()
                    if recordedPoints.count >= 2 {
                        recordingName = "Sortie du \(Date().formatted(date: .abbreviated, time: .omitted))"
                        // petite pause : la feuille principale se re-présente
                        // d'abord, puis l'alerte s'affiche par-dessus
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                            showSaveRecording = true
                        }
                    }
                }
            }

            // HUD de suivi (sous-vue observante)
            if let follow = model.follow {
                FollowHUDView(follow: follow, location: model.location) {
                    model.stopFollow()
                }
            } else if model.recording == nil {
                // boutons flottants : ma position + enregistrer
                VStack(spacing: 10) {
                    HStack {
                        Spacer()
                        VStack(spacing: 10) {
                            Button {
                                locatePending = true
                                model.location.setBalancedAccuracy(model.balancedGPS)
                                model.location.start(background: false)
                                if let fix = model.location.fix {
                                    model.requestFit([fix.coordinate])
                                    locatePending = false
                                }
                            } label: {
                                Image(systemName: "location.fill")
                                    .font(.body.weight(.semibold))
                                    .frame(width: 44, height: 44)
                                    .background(.regularMaterial, in: Circle())
                            }
                            Button {
                                model.startRecording()
                            } label: {
                                Image(systemName: "record.circle")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.red)
                                    .frame(width: 44, height: 44)
                                    .background(.regularMaterial, in: Circle())
                            }
                        }
                        .padding(.trailing, 12)
                        .padding(.top, 56)
                    }
                    Spacer()
                }
            }

            if let toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 40)
                }
                .transition(.opacity)
            }
        }
        // Feuille principale, toujours présente hors suivi/enregistrement
        .sheet(isPresented: .init(
            get: { model.follow == nil && model.recording == nil },
            set: { _ in }
        )) {
            NavigationStack {
                TrackListView(selectedUUID: $selectedUUID) {
                    showImporter = true
                }
                .navigationDestination(for: UUID.self) { uuid in
                    if let rec = records.first(where: { $0.uuid == uuid }) {
                        TrackDetailView(record: rec)
                            .onAppear { selectedUUID = uuid }
                    }
                }
                .navigationDestination(for: String.self) { route in
                    if route == "settings" { SettingsView() }
                }
            }
            .presentationDetents([.height(130), .medium, .large], selection: $detent)
            .presentationBackgroundInteraction(.enabled(upThrough: .large))
            .presentationBackground(.regularMaterial)
            .interactiveDismissDisabled()
            // ⬇︎ présentées DEPUIS la feuille (iOS n'autorise qu'une
            // présentation par contexte : la base est déjà occupée)
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [gpxType, .xml],
                allowsMultipleSelection: true
            ) { result in
                handleImporter(result)
            }
            .sheet(item: $pendingImport) { pending in
                ImportPreviewView(pending: pending) {
                    importNow(pending)
                    pendingImport = nil
                } onCancel: {
                    pendingImport = nil
                }
            }
            .sheet(isPresented: .init(
                get: { newWaypointCoord != nil },
                set: { if !$0 { newWaypointCoord = nil } }
            )) {
                if let coord = newWaypointCoord {
                    NewWaypointSheet(coordinate: coord,
                                     altitude: model.location.fix?.altitude) {
                        newWaypointCoord = nil
                    }
                }
            }
            .alert("Enregistrer la sortie", isPresented: $showSaveRecording) {
                TextField("Nom", text: $recordingName)
                Button("Ignorer", role: .cancel) { recordedPoints = [] }
                Button("Enregistrer") { saveRecording() }
            } message: {
                Text("\(Fmt.distance(recordedPoints.last?.dist ?? 0)) parcourus")
            }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 12)
                }
            }
        }
        // GPX ouverts depuis Mail / Fichiers / AirDrop
        .onOpenURL { url in
            handleIncoming(url: url)
        }
        // le suivi et l'enregistrement consomment chaque fix GPS
        .onReceive(model.location.$fix) { fix in
            guard let fix else { return }
            model.follow?.update(with: fix)
            model.recording?.add(fix: fix)
            if locatePending {
                locatePending = false
                model.requestFit([fix.coordinate])
            }
        }

    }

    private func saveRecording() {
        let name = recordingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard recordedPoints.count >= 2, !name.isEmpty else { return }
        let uuid = UUID()
        let gpx = GPXWriter.gpx(name: name, points: recordedPoints, waypoints: [])
        do {
            try GPXStore.save(gpx, for: uuid)
            let stats = TrackGeometry.stats(for: recordedPoints)
            context.insert(TrackRecord(
                uuid: uuid, name: name,
                colorHex: TrackPalette.hex(at: records.count),
                sortOrder: records.count,
                distance: stats.distance, ascent: stats.ascent, descent: stats.descent))
            flash("Sortie enregistrée ✓")
        } catch {
            flash("Impossible d'enregistrer la sortie")
        }
        recordedPoints = []
    }


    // MARK: import

    private func handleImporter(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        var parsedOK = 0
        var failed = 0
        var single: PendingImport?

        for url in urls {
            guard let data = readSecurityScoped(url) else { failed += 1; continue }
            let name = url.deletingPathExtension().lastPathComponent
            guard let parsed = GPXParser.parse(data: data, fallbackName: name) else {
                failed += 1
                continue
            }
            if urls.count == 1 {
                single = PendingImport(parsed: parsed, rawData: data)
            } else {
                importParsed(parsed, data: data)
                parsedOK += 1
            }
        }

        if let single {
            pendingImport = single       // aperçu avant import (spec §3.2)
        } else if parsedOK > 0 {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            flash("\(parsedOK) trace\(parsedOK > 1 ? "s" : "") importée\(parsedOK > 1 ? "s" : "")")
        }
        if failed > 0 {
            flash("\(failed) fichier\(failed > 1 ? "s" : "") illisible\(failed > 1 ? "s" : "")")
        }
    }

    private func handleIncoming(url: URL) {
        guard let data = readSecurityScoped(url) else { return }
        let name = url.deletingPathExtension().lastPathComponent
        guard let parsed = GPXParser.parse(data: data, fallbackName: name) else {
            flash("Fichier GPX illisible")
            return
        }
        pendingImport = PendingImport(parsed: parsed, rawData: data)
    }

    private func importNow(_ pending: PendingImport) {
        importParsed(pending.parsed, data: pending.rawData)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        flash("« \(pending.parsed.name) » importée")
    }

    private func importParsed(_ parsed: ParsedTrack, data: Data) {
        let uuid = UUID()
        let text = String(data: data, encoding: .utf8)
            ?? GPXWriter.gpx(name: parsed.name, points: parsed.points, waypoints: parsed.waypoints)
        do {
            try GPXStore.save(text, for: uuid)
        } catch {
            flash("Impossible d'enregistrer la trace")
            return
        }
        let rec = TrackRecord(
            uuid: uuid,
            name: parsed.name,
            colorHex: TrackPalette.hex(at: records.count),
            sortOrder: records.count,
            distance: parsed.stats.distance,
            ascent: parsed.stats.ascent,
            descent: parsed.stats.descent
        )
        context.insert(rec)
        model.requestFit(parsed.points.map { .init(latitude: $0.lat, longitude: $0.lon) })
    }

    private func readSecurityScoped(_ url: URL) -> Data? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url)
    }

    private func flash(_ message: String) {
        withAnimation { toast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { if toast == message { toast = nil } }
        }
    }
}

// MARK: - HUDs observants (stats vivantes pendant suivi / enregistrement)

private struct HUDStat: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 1) {
            Text(value).font(.subheadline.monospacedDigit().weight(.bold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct GPSBadge: View {
    @ObservedObject var location: LocationManager
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "antenna.radiowaves.left.and.right")
            Text(location.quality.rawValue)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(location.quality == .poor ? .orange : .secondary)
    }
}

struct FollowHUDView: View {
    @ObservedObject var follow: FollowSession
    @ObservedObject var location: LocationManager
    var onStop: () -> Void

    var body: some View {
        let st = follow.state
        VStack {
            HStack(spacing: 12) {
                Image(systemName: st.offRoute
                      ? "exclamationmark.triangle.fill"
                      : "location.north.line.fill")
                    .font(.title2)
                    .foregroundStyle(st.offRoute ? .orange : Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(st.offRoute ? "Hors trace" : follow.trackName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(st.offRoute
                         ? "à \(Int(st.offset)) m du tracé"
                         : "encore \(Fmt.distance(st.remaining))")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                GPSBadge(location: location)
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 12)

            Spacer()

            HStack(spacing: 0) {
                HUDStat(value: Fmt.distance(st.remaining), label: "restant")
                HUDStat(value: st.etaSeconds.map { Fmt.clock(after: $0) } ?? "—",
                        label: "arrivée")
                HUDStat(value: location.fix.map { "\(Int($0.altitude)) m" } ?? "—",
                        label: "altitude")
                Button(action: onStop) {
                    Text("Arrêter")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.red, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }
}

struct RecordingHUDView: View {
    @ObservedObject var rec: RecordingSession
    @ObservedObject var location: LocationManager
    var onFinish: () -> Void

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                    .opacity(rec.isPaused ? 0.3 : 1)
                Text(rec.isPaused ? "En pause" : "Enregistrement")
                    .font(.headline)
                Spacer()
                GPSBadge(location: location)
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 12)

            Spacer()

            HStack(spacing: 0) {
                HUDStat(value: Fmt.distance(rec.distance), label: "distance")
                HUDStat(value: "+\(Int(rec.ascent)) m", label: "D+")
                HUDStat(value: Fmt.duration(rec.elapsed), label: "durée")
                Button {
                    rec.togglePause()
                } label: {
                    Image(systemName: rec.isPaused ? "play.fill" : "pause.fill")
                        .frame(width: 40, height: 40)
                        .background(.thinMaterial, in: Circle())
                }
                Button(action: onFinish) {
                    Text("Terminer")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.red, in: Capsule())
                        .foregroundStyle(.white)
                }
                .padding(.leading, 6)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }
}
