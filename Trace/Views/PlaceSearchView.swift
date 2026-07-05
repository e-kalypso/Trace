//  PlaceSearchView.swift
//  Aller à un lieu : recherche native (MKLocalSearch), tap → la carte
//  se centre dessus. Idéal pour préparer une rando ailleurs.

import MapKit
import SwiftUI

struct PlaceSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false

    var body: some View {
        List {
            Section {
                TextField("Village, sommet, refuge…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await search() } }
                Button {
                    Task { await search() }
                } label: {
                    Label("Rechercher", systemImage: "magnifyingglass")
                }
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || searching)
            }

            Section {
                if searching { ProgressView() }
                ForEach(results, id: \.self) { item in
                    Button {
                        let c = item.placemark.coordinate
                        model.requestFit([c])
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? "Lieu")
                                .foregroundStyle(.primary)
                            if let t = item.placemark.title {
                                Text(t).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Aller à un lieu")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func search() async {
        searching = true
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = query
        if let fix = model.location.fix {
            req.region = MKCoordinateRegion(
                center: fix.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 2, longitudeDelta: 2))
        }
        let search = MKLocalSearch(request: req)
        results = (try? await search.start())?.mapItems ?? []
        searching = false
    }
}
