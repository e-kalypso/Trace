//  ImportPreviewView.swift
//  Prévisualisation avant import (cahier des charges §3.2) :
//  carte cadrée + profil + stats, puis Importer / Annuler.

import CoreLocation
import SwiftUI

struct PendingImport: Identifiable {
    let id = UUID()
    let parsed: ParsedTrack
    let rawData: Data
}

struct ImportPreviewView: View {
    let pending: PendingImport
    var onImport: () -> Void
    var onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MapContainerView(
                    tracks: [MapTrack(
                        id: pending.id,
                        coordinates: pending.parsed.points.map {
                            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
                        },
                        waypoints: pending.parsed.waypoints,
                        colorHex: TrackPalette.hexes[0],
                        isActive: true
                    )],
                    basemap: .appleStandard,
                    scrub: nil,
                    fitTarget: pending.parsed.points.map {
                        CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
                    },
                    fitRequest: 1,
                    following: false,
                    revision: 0
                )
                .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 12) {
                    let s = pending.parsed.stats
                    HStack {
                        statChip("point.topleft.down.curvedto.point.bottomright.up",
                                 Fmt.distance(s.distance))
                        statChip("arrow.up.right", "+\(Int(s.ascent)) m")
                        statChip("arrow.down.right", "−\(Int(s.descent)) m")
                        statChip("clock", Fmt.duration(s.estimatedDuration))
                    }

                    ElevationChartView(points: pending.parsed.points) { _ in }

                    Button {
                        onImport()
                    } label: {
                        Text("Importer")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding()
                .background(.regularMaterial)
            }
            .navigationTitle(pending.parsed.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", action: onCancel)
                }
            }
        }
    }

    private func statChip(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.monospacedDigit().weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
    }
}
