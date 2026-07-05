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
    @State private var builderTick = 0
    @State private var showSaveBuilder = false
    @State private var builderName = "Mon itinéraire"

    private static let draftID = UUID()

    private var gpxType: UTType {
        UTType(filenameExtension: "gpx") ?? .xml
    }

    /// Traces visibles + brouillon du créateur par-dessus.
    private var displayTracks: [MapTrack] {
        var tracks = model.mapTracks(records: records, selected: selectedUUID)
        if let b = model.builder {
            tracks.append(MapTrack(id: Self.draftID,
                                   coordinates: b.draftCoordinates,
                                   waypoints: [],
                                   colorHex: "FF9F0A",
                                   isActive: true))
        }
        return tracks
    }

    var body: some View {
        ZStack {
            MapContainerView(
                tracks: displayTracks,
                basemap: model.basemap,
                scrub: model.scrubCoordinate,
                fitTarget: model.fitTarget,
                fitRequest: model.fitRequest,
                following: (model.follow != nil || model.recording != nil)
                    && !model.followOverview,
                revision: model.mapRevision &+ builderTick,
                personalWaypoints: waypoints.map {
                    PersonalWaypointItem(id: $0.uuid, lat: $0.lat, lon: $0.lon,
                                         name: $0.name, symbol: $0.category.symbol)
                },
                onLongPress: { coord in
                    if model.follow == nil && model.builder == nil {
                        newWaypointCoord = coord
                    }
                },
                tapEnabled: model.builder != nil,
                onTap: { coord in
                    guard let b = model.builder else { return }
                    Task {
                        await b.addAnchor(coord)
                        builderTick &+= 1
                    }
                }
            )
            .ignoresSafeArea()

            // HUD d'enregistrement (sous-vue observante : stats vivantes)
            if let rec = model.recording {
                RecordingHUDView(rec: rec, location: model.location,
                                 weightKg: model.weightKg) {
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

            // HUD du créateur d'itinéraire
            if let b = model.builder {
                BuilderHUDView(
                    builder: b,
                    onUndo: {
                        b.undo()
                        builderTick &+= 1
                    },
                    onSave: { showSaveBuilder = true },
                    onCancel: {
                        model.stopBuilder()
                        builderTick &+= 1
                    }
                )
            }

            // HUD de suivi (sous-vue observante)
            if let follow = model.follow {
                FollowHUDView(
                    follow: follow,
                    location: model.location,
                    overviewOn: model.followOverview,
                    onOverview: {
                        model.followOverview.toggle()
                        if model.followOverview {
                            model.requestFit(follow.points.map {
                                .init(latitude: $0.lat, longitude: $0.lon)
                            })
                        }
                    },
                    onUTurn: {
                        let reversedPts = TrackGeometry.reversed(follow.points)
                        model.startFollow(points: reversedPts,
                                          name: "\(follow.trackName) (retour)",
                                          waypoints: [])
                    },
                    onStop: {
                        // consigne la sortie au carnet si on a vraiment marché
                        if follow.state.progress > 0.3 {
                            context.insert(HikeLogRecord(
                                name: follow.trackName,
                                distance: follow.state.done,
                                ascent: 0,
                                duration: Date().timeIntervalSince(follow.startedAt),
                                kind: "Suivie"))
                        }
                        model.stopFollow()
                    }
                )
            } else if model.recording == nil && model.builder == nil {
                // boutons flottants — sous la boussole MapKit (fix offset)
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
                            Button {
                                model.startBuilder()
                            } label: {
                                Image(systemName: "pencil.and.outline")
                                    .font(.body.weight(.semibold))
                                    .frame(width: 44, height: 44)
                                    .background(.regularMaterial, in: Circle())
                            }
                            AltChip(location: model.location)
                        }
                        .padding(.trailing, 12)
                        .padding(.top, 118)
                    }
                    Spacer()
                }
            }

            // HUD « cap vers un point » (hors ligne, vol d'oiseau)
            if let guide = model.guide {
                GuideHUDView(target: guide, location: model.location) {
                    model.stopGuide()
                }
            }

            // mode nuit : filtre rouge sombre, ne bloque pas les taps
            if model.nightMode {
                Color(red: 0.4, green: 0, blue: 0)
                    .opacity(0.35)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                Color.black
                    .opacity(0.25)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
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
        // sauvegarde de l'itinéraire créé (feuille masquée → pas de conflit)
        .alert("Enregistrer l'itinéraire", isPresented: $showSaveBuilder) {
            TextField("Nom", text: $builderName)
            Button("Annuler", role: .cancel) {}
            Button("Enregistrer") { saveBuilder() }
        } message: {
            Text(model.builder.map { Fmt.distance($0.distance) } ?? "")
        }
        // Feuille principale, hors suivi/enregistrement/création
        .sheet(isPresented: .init(
            get: { model.follow == nil && model.recording == nil && model.builder == nil },
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
                    switch route {
                    case "settings": SettingsView()
                    case "discover": DiscoverView()
                    case "sequence": SequenceView()
                    case "history": HistoryView()
                    case "weather": WeatherNowView()
                    case "place": PlaceSearchView()
                    default: EmptyView()
                    }
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
        // récupération anti-crash : une sortie interrompue traîne ?
        .onAppear { recoverAutosaveIfNeeded() }
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
            // carnet : la sortie rejoint l'historique
            var duration: TimeInterval = 0
            if let t0 = recordedPoints.first?.time, let t1 = recordedPoints.last?.time {
                duration = t1.timeIntervalSince(t0)
            }
            context.insert(HikeLogRecord(
                name: name, distance: stats.distance, ascent: stats.ascent,
                duration: duration, kind: "Enregistrée"))
            flash("Sortie enregistrée ✓")
        } catch {
            flash("Impossible d'enregistrer la sortie")
        }
        recordedPoints = []
    }

    /// Si l'app s'est arrêtée en plein enregistrement, le brouillon
    /// autosauvegardé est restauré comme trace « Sortie récupérée ».
    private func recoverAutosaveIfNeeded() {
        guard model.recording == nil,
              let data = try? Data(contentsOf: GPXStore.autosaveURL),
              let parsed = GPXParser.parse(data: data, fallbackName: "Sortie récupérée"),
              parsed.points.count >= 2 else { return }
        importParsed(parsed, data: data)
        try? FileManager.default.removeItem(at: GPXStore.autosaveURL)
        flash("Sortie interrompue récupérée ✓")
    }

    private func saveBuilder() {
        guard let b = model.builder else { return }
        let pts = b.toTrackPoints()
        guard pts.count >= 2 else { return }
        let name = builderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = name.isEmpty ? "Mon itinéraire" : name
        let uuid = UUID()
        let gpx = GPXWriter.gpx(name: finalName, points: pts, waypoints: [])
        do {
            try GPXStore.save(gpx, for: uuid)
            let stats = TrackGeometry.stats(for: pts)
            context.insert(TrackRecord(
                uuid: uuid, name: finalName,
                colorHex: TrackPalette.hex(at: records.count),
                sortOrder: records.count,
                distance: stats.distance, ascent: stats.ascent, descent: stats.descent))
            flash("« \(finalName) » créé ✓")
        } catch {
            flash("Impossible d'enregistrer l'itinéraire")
        }
        model.stopBuilder()
        builderTick &+= 1
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
                // offset = parsedOK : chaque trace du lot a SA couleur
                importParsed(parsed, data: data, colorOffset: parsedOK)
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

    private func importParsed(_ parsed: ParsedTrack, data: Data, colorOffset: Int = 0) {
        let uuid = UUID()
        let text = String(data: data, encoding: .utf8)
            ?? GPXWriter.gpx(name: parsed.name, points: parsed.points, waypoints: parsed.waypoints)
        do {
            try GPXStore.save(text, for: uuid)
        } catch {
            flash("Impossible d'enregistrer la trace")
            return
        }
        // records n'est pas rafraîchi au milieu d'un import par lot :
        // colorOffset garantit une couleur différente à chaque fichier.
        let rec = TrackRecord(
            uuid: uuid,
            name: parsed.name,
            colorHex: TrackPalette.hex(at: records.count + colorOffset),
            sortOrder: records.count + colorOffset,
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
    var overviewOn: Bool
    var onOverview: () -> Void
    var onUTurn: () -> Void
    var onStop: () -> Void

    /// « Nuit dans X » — coucher du soleil à la position courante.
    private var nightIn: String? {
        guard let fix = location.fix,
              let sunset = Sun.times(date: Date(),
                                     lat: fix.coordinate.latitude,
                                     lon: fix.coordinate.longitude).sunset,
              sunset > Date() else { return nil }
        let h = sunset.timeIntervalSinceNow / 3600
        if h > 12 { return nil }
        let hh = Int(h)
        let mm = Int((h - Double(hh)) * 60)
        return hh > 0 ? "nuit dans \(hh) h \(String(format: "%02d", mm))" : "nuit dans \(mm) min"
    }

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
                    HStack(spacing: 8) {
                        Text(st.offRoute
                             ? "à \(Int(st.offset)) m du tracé"
                             : "encore \(Fmt.distance(st.remaining))")
                        if let g = st.upcomingGrade, abs(g) >= 3 {
                            Text(String(format: "%+.0f %%", g))
                                .foregroundStyle(abs(g) > 15 ? .red : abs(g) > 8 ? .orange : .green)
                        }
                    }
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    if let wp = st.nextWaypointName, let d = st.nextWaypointIn {
                        Label("\(wp) dans \(Fmt.distance(d))", systemImage: "flag.fill")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                    }
                    if let night = nightIn {
                        Label(night, systemImage: "moon.fill")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(spacing: 8) {
                    GPSBadge(location: location)
                    HStack(spacing: 6) {
                        Button(action: onOverview) {
                            Image(systemName: overviewOn
                                  ? "location.viewfinder" : "map")
                                .font(.footnote.weight(.semibold))
                                .frame(width: 30, height: 30)
                                .background(.thinMaterial, in: Circle())
                        }
                        Button(action: onUTurn) {
                            Image(systemName: "arrow.uturn.down")
                                .font(.footnote.weight(.semibold))
                                .frame(width: 30, height: 30)
                                .background(.thinMaterial, in: Circle())
                        }
                    }
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 12)

            // progression le long de la trace
            ProgressView(value: st.progress)
                .tint(Color.accentColor)
                .padding(.horizontal, 24)
                .padding(.top, 2)

            Spacer()

            HStack(spacing: 0) {
                HUDStat(value: Fmt.distance(st.remaining), label: "restant")
                HUDStat(value: "+\(Int(st.remainingAscent)) m", label: "D+ restant")
                HUDStat(value: st.etaSeconds.map { Fmt.clock(after: $0) } ?? "—",
                        label: "arrivée")
                HUDStat(value: location.fix.map { "\(Int($0.altitude)) m" } ?? "—",
                        label: "altitude")
                Button(action: onStop) {
                    Text("Arrêter")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
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
    var weightKg: Double
    var onFinish: () -> Void

    var body: some View {
        VStack {
            HStack(spacing: 12) {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                    .opacity(rec.isPaused ? 0.3 : 1)
                Text(rec.isPaused ? "En pause"
                     : rec.isAutoPaused ? "Pause auto (immobile)"
                     : "Enregistrement")
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
                HUDStat(value: Fmt.kcal(weightKg: weightKg,
                                        distanceM: rec.distance,
                                        ascent: rec.ascent),
                        label: "énergie")
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

// MARK: - Altimètre live (petit cadran sous les boutons)

private struct AltChip: View {
    @ObservedObject var location: LocationManager
    var body: some View {
        if let fix = location.fix {
            Text("\(Int(fix.altitude)) m")
                .font(.caption.monospacedDigit().weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
        }
    }
}

// MARK: - HUD « cap vers un point » (boussole hors ligne)

struct GuideHUDView: View {
    let target: AppModel.GuideTarget
    @ObservedObject var location: LocationManager
    var onStop: () -> Void

    private var distance: Double? {
        guard let fix = location.fix else { return nil }
        return TrackGeometry.haversine(
            fix.coordinate.latitude, fix.coordinate.longitude,
            target.lat, target.lon)
    }

    /// Rotation de la flèche : cap vers la cible moins cap de marche.
    private var arrowAngle: Double {
        guard let fix = location.fix else { return 0 }
        let b = TrackGeometry.bearing(
            fromLat: fix.coordinate.latitude, fromLon: fix.coordinate.longitude,
            toLat: target.lat, toLon: target.lon)
        let course = fix.course >= 0 ? fix.course : 0
        return b - course
    }

    var body: some View {
        VStack {
            HStack(spacing: 14) {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .rotationEffect(.degrees(arrowAngle))
                    .animation(.easeInOut(duration: 0.4), value: arrowAngle)
                VStack(alignment: .leading, spacing: 1) {
                    Text(target.name)
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(distance.map { Fmt.distance($0) } ?? "recherche GPS…")
                            .font(.footnote.monospacedDigit().weight(.semibold))
                        if let fix = location.fix, fix.course < 0 {
                            Text("· flèche = nord si vous êtes à l'arrêt")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Button(action: onStop) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(.thinMaterial, in: Circle())
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 12)
            Spacer()
        }
        .padding(.top, 4)
    }
}
