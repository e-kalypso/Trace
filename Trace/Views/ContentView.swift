//  ContentView.swift
//  Écran principal : la carte est le héros, l'UI flotte au-dessus.
//  Feuille à crans façon Plans d'Apple ; HUD de suivi en Liquid Glass.

import CoreLocation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var model: AppModel
    @Query(sort: \TrackRecord.sortOrder) private var records: [TrackRecord]

    @State private var selectedUUID: UUID?
    @State private var detent: PresentationDetent = .medium
    @State private var showImporter = false
    @State private var pendingImport: PendingImport?
    @State private var toast: String?
    @State private var locatePending = false

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
                following: model.follow != nil,
                revision: model.mapRevision
            )
            .ignoresSafeArea()

            // HUD de suivi
            if let follow = model.follow {
                followHUD(follow)
            } else {
                // bouton « ma position » flottant
                VStack {
                    HStack {
                        Spacer()
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
        // Feuille principale, toujours présente hors suivi (pattern Plans)
        .sheet(isPresented: .init(
            get: { model.follow == nil },
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
        }
        // Aperçu avant import
        .sheet(item: $pendingImport) { pending in
            ImportPreviewView(pending: pending) {
                importNow(pending)
                pendingImport = nil
            } onCancel: {
                pendingImport = nil
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [gpxType, .xml],
            allowsMultipleSelection: true
        ) { result in
            handleImporter(result)
        }
        // GPX ouverts depuis Mail / Fichiers / AirDrop
        .onOpenURL { url in
            handleIncoming(url: url)
        }
        // le suivi consomme chaque fix GPS
        .onReceive(model.location.$fix) { fix in
            guard let fix else { return }
            model.follow?.update(with: fix)
            if locatePending {
                locatePending = false
                model.requestFit([fix.coordinate])
            }
        }
    }

    // MARK: HUD de suivi

    @ViewBuilder
    private func followHUD(_ follow: FollowSession) -> some View {
        let st = follow.state
        VStack {
            // bannière haute
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
                gpsBadge
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 12)

            Spacer()

            // barre basse : stats + stop
            HStack(spacing: 0) {
                hudStat(Fmt.distance(st.remaining), "restant")
                hudStat(st.etaSeconds.map { Fmt.clock(after: $0) } ?? "—", "arrivée")
                hudStat(model.location.fix.map { "\(Int($0.altitude)) m" } ?? "—", "altitude")
                Button {
                    model.stopFollow()
                } label: {
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

    private var gpsBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "antenna.radiowaves.left.and.right")
            Text(model.location.quality.rawValue)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(model.location.quality == .poor ? .orange : .secondary)
    }

    private func hudStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.subheadline.monospacedDigit().weight(.bold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
