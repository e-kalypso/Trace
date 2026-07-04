//  OfflineView.swift
//  Télécharger la zone d'une trace pour le hors-ligne + gérer les packs.

import SwiftData
import SwiftUI

struct OfflineView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var model: AppModel
    @Query(sort: \OfflinePackRecord.createdAt, order: .reverse)
    private var packs: [OfflinePackRecord]

    /// Trace autour de laquelle télécharger (nil = gestion des packs seulement).
    var record: TrackRecord?

    @StateObject private var downloader = OfflineDownloader()
    @State private var basemap: Basemap = .openTopo
    @State private var maxZ = 15
    @State private var toast: String?

    private var bbox: (w: Double, s: Double, e: Double, n: Double)? {
        guard let record, let t = model.track(for: record), !t.points.isEmpty else { return nil }
        var w = 180.0, s = 90.0, e = -180.0, n = -90.0
        for p in t.points {
            w = min(w, p.lon); e = max(e, p.lon)
            s = min(s, p.lat); n = max(n, p.lat)
        }
        // marge ~2 km (§4.3 : buffer autour de la trace)
        let pad = 0.02
        return (w - pad, s - pad, e + pad, n + pad)
    }

    private var estimate: (count: Int, bytes: Int) {
        guard let b = bbox else { return (0, 0) }
        let count = TileCache.tiles(west: b.w, south: b.s, east: b.e, north: b.n,
                                    zMin: 10, zMax: maxZ).count
        return (count, count * 30_000)   // ~30 Ko / tuile en moyenne
    }

    var body: some View {
        List {
            if let record, bbox != nil {
                Section("Télécharger autour de « \(record.name) »") {
                    Picker("Fond de carte", selection: $basemap) {
                        ForEach(Basemap.offlineCapable) { b in
                            Text(b.label).tag(b)
                        }
                    }
                    Stepper("Détail max : zoom \(maxZ)", value: $maxZ, in: 12...16)
                    LabeledContent("Estimation") {
                        Text("\(estimate.count) tuiles · ~\(OfflineDownloader.fmtBytes(estimate.bytes))")
                            .font(.footnote.monospacedDigit())
                    }

                    if downloader.isRunning {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: Double(downloader.done),
                                         total: Double(max(1, downloader.total)))
                            HStack {
                                Text("\(downloader.done)/\(downloader.total)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Annuler", role: .destructive) {
                                    downloader.cancel()
                                }
                                .font(.caption.weight(.semibold))
                            }
                        }
                    } else {
                        Button {
                            startDownload()
                        } label: {
                            Label("Télécharger cette zone", systemImage: "arrow.down.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }

            Section("Zones hors ligne") {
                if packs.isEmpty {
                    Text("Aucune zone téléchargée.")
                        .foregroundStyle(.secondary)
                }
                ForEach(packs) { pack in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pack.name).font(.body.weight(.semibold))
                        Text("\(pack.providerLabel) · zoom ≤\(pack.zMax) · \(pack.tileCount) tuiles · \(OfflineDownloader.fmtBytes(pack.bytes))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    for i in offsets {
                        OfflineDownloader.evict(record: packs[i])
                        context.delete(packs[i])
                    }
                }
            } footer: {
                Text("Les traces, stats et le GPS fonctionnent toujours sans réseau. Les zones téléchargées rendent aussi la carte disponible (fonds topo/IGN/Swisstopo).")
            }
        }
        .navigationTitle("Hors ligne")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 16)
            }
        }
    }

    private func startDownload() {
        guard let record, let b = bbox, let raster = basemap.raster else { return }
        let name = record.name
        let label = basemap.label
        Task {
            if let result = await downloader.download(
                provider: raster,
                west: b.w, south: b.s, east: b.e, north: b.n,
                zMin: 10, zMax: maxZ
            ) {
                context.insert(OfflinePackRecord(
                    name: name, providerID: raster.id, providerLabel: label,
                    west: b.w, south: b.s, east: b.e, north: b.n,
                    zMin: 10, zMax: maxZ,
                    tileCount: result.count, bytes: result.bytes))
                toast = "Zone téléchargée ✓"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { toast = nil }
            }
        }
    }
}
