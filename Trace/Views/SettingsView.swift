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
            Section {
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
            } header: {
                Text("Fond de carte")
            } footer: {
                Text("OpenTopoMap couvre la France, la Suisse et l'Italie de façon homogène — idéal pour le Tour du Mont-Blanc. Plan IGN et Swisstopo sont les fonds officiels de chaque pays.")
            }

            Section {
                Toggle(isOn: $model.balancedGPS) {
                    Label("Économie de batterie", systemImage: "battery.75percent")
                }
                Toggle(isOn: $model.nightMode) {
                    Label("Mode nuit (vision nocturne)", systemImage: "moon.stars.fill")
                }
                Stepper(value: $model.weightKg, in: 35...150, step: 1) {
                    Label("Poids : \(Int(model.weightKg)) kg (calories)",
                          systemImage: "figure.walk")
                }
            } header: {
                Text("GPS et affichage")
            } footer: {
                Text("Économie : mesures GPS espacées (~15 m), pour les longues sorties. Mode nuit : filtre rouge sombre qui préserve la vision nocturne en bivouac ou marche de nuit.")
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
                            Spacer()
                            Button {
                                model.startGuide(name: w.name, lat: w.lat, lon: w.lon)
                            } label: {
                                Image(systemName: "safari")
                                    .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets { context.delete(waypoints[i]) }
                    }
                }
            }

            Section {
                LabeledContent("Version", value: "3.0")
                LabeledContent("Cartes", value: "Apple · OpenTopoMap · IGN · Swisstopo")
            } header: {
                Text("À propos")
            } footer: {
                Text("Vos traces restent sur votre appareil. Seuls les fonds de carte et la météo transitent par le réseau.")
            }
        }
        .navigationTitle("Réglages")
        .navigationBarTitleDisplayMode(.inline)
    }
}
