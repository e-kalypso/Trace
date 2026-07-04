//  SettingsView.swift
//  Réglages : fond de carte, précision GPS (batterie), à propos.

import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var model: AppModel
    @Query(sort: \WaypointRecord.createdAt, order: .reverse)
    private var waypoints: [WaypointRecord]

    var body: some View {
        List {
            Section {
                NavigationLink {
                    SecurityView(location: model.location)
                } label: {
                    Label("Sécurité (coordonnées secours)", systemImage: "cross.case.fill")
                }
                NavigationLink {
                    OfflineView(record: nil)
                } label: {
                    Label("Zones hors ligne", systemImage: "arrow.down.circle")
                }
            }
            Section("Fond de carte") {
                ForEach(Basemap.allCases) { b in
                    Button {
                        model.basemap = b
                    } label: {
                        HStack {
                            Label(b.label, systemImage: b.symbol)
                                .foregroundStyle(.primary)
                            Spacer()
                            if model.basemap == b {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
            } footer: {
                Text("OpenTopoMap couvre la France, la Suisse et l'Italie de façon homogène — idéal pour le Tour du Mont-Blanc. Fonds IGN et Swisstopo : prochaine version.")
            }

            Section("GPS") {
                Toggle(isOn: $model.balancedGPS) {
                    Label("Économie de batterie", systemImage: "battery.75percent")
                }
            } footer: {
                Text("Espace les mesures GPS (~15 m) pendant le suivi. Recommandé pour les sorties de plusieurs heures.")
            }

            if !waypoints.isEmpty {
                Section("Mes repères") {
                    ForEach(waypoints) { w in
                        HStack {
                            Image(systemName: w.category.symbol)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(w.name)
                                Text(String(format: "%.4f, %.4f", w.lat, w.lon))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets { context.delete(waypoints[i]) }
                    }
                }
            }

            Section("À propos") {
                LabeledContent("Version", value: "3.0")
                LabeledContent("Cartes", value: "Apple Maps · OpenTopoMap")
            } footer: {
                Text("Vos traces restent sur votre appareil. Seuls les fonds de carte et la météo transitent par le réseau.")
            }
        }
        .navigationTitle("Réglages")
        .navigationBarTitleDisplayMode(.inline)
    }
}
