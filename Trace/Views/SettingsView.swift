//  SettingsView.swift
//  Réglages : fond de carte, précision GPS (batterie), à propos.

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
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
