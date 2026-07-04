//  NewWaypointSheet.swift
//  Création d'un waypoint perso après appui long sur la carte (§3.5).

import CoreLocation
import SwiftData
import SwiftUI

struct NewWaypointSheet: View {
    @Environment(\.modelContext) private var context
    let coordinate: CLLocationCoordinate2D
    let altitude: Double?
    var onDone: () -> Void

    @State private var name = ""
    @State private var category: WaypointCategory = .vue

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom du repère", text: $name)
                }
                Section("Catégorie") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76))], spacing: 10) {
                        ForEach(WaypointCategory.allCases) { cat in
                            Button {
                                category = cat
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: cat.symbol)
                                        .font(.title3)
                                    Text(cat.label)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    category == cat
                                        ? Color.accentColor.opacity(0.2)
                                        : Color.secondary.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section {
                    LabeledContent("Position", value: String(
                        format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                    if let altitude {
                        LabeledContent("Altitude", value: "\(Int(altitude)) m")
                    }
                }
            }
            .navigationTitle("Nouveau repère")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", action: onDone)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        context.insert(WaypointRecord(
                            name: n.isEmpty ? category.label : n,
                            category: category,
                            lat: coordinate.latitude,
                            lon: coordinate.longitude,
                            ele: altitude))
                        onDone()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
