//  TrackListView.swift
//  Liste des traces : visibilité, couleur, stats, recherche, tri,
//  réorganisation manuelle, import GPX multi-sélection.

import SwiftData
import SwiftUI

enum TrackSort: String, CaseIterable, Identifiable {
    case manual, name, recent, distance, ascent
    var id: String { rawValue }
    var label: String {
        switch self {
        case .manual: return "Ordre manuel"
        case .name: return "Nom"
        case .recent: return "Plus récentes"
        case .distance: return "Distance"
        case .ascent: return "Dénivelé"
        }
    }
}

struct TrackListView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var model: AppModel
    @Query(sort: \TrackRecord.sortOrder) private var records: [TrackRecord]

    @Binding var selectedUUID: UUID?
    var onImportTap: () -> Void

    @State private var search = ""
    @State private var sort: TrackSort = .manual

    private var shown: [TrackRecord] {
        var list = records
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter { $0.name.lowercased().contains(q) }
        }
        switch sort {
        case .manual: break
        case .name: list.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .recent: list.sort { $0.createdAt > $1.createdAt }
        case .distance: list.sort { $0.distance > $1.distance }
        case .ascent: list.sort { $0.ascent > $1.ascent }
        }
        return list
    }

    var body: some View {
        List {
            if records.isEmpty {
                ContentUnavailableView(
                    "Aucune trace",
                    systemImage: "figure.hiking",
                    description: Text("Importez un fichier GPX pour commencer. Trace ouvre aussi les GPX reçus par Mail ou AirDrop.")
                )
                .listRowBackground(Color.clear)
            }

            ForEach(shown) { rec in
                NavigationLink(value: rec.uuid) {
                    HStack(spacing: 12) {
                        Button {
                            rec.isVisible.toggle()
                        } label: {
                            Image(systemName: rec.isVisible ? "eye.fill" : "eye.slash")
                                .foregroundStyle(rec.isVisible ? Color.accentColor : .secondary)
                        }
                        .buttonStyle(.plain)

                        Circle()
                            .fill(Color(hex: rec.colorHex))
                            .frame(width: 12, height: 12)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(rec.name)
                                .font(.body.weight(.semibold))
                                .lineLimit(1)
                            Text("\(Fmt.distance(rec.distance)) · +\(Int(rec.ascent)) m")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .opacity(rec.isVisible ? 1 : 0.5)
                }
            }
            .onMove { from, to in
                guard sort == .manual, search.isEmpty else { return }
                var list = records
                list.move(fromOffsets: from, toOffset: to)
                for (i, r) in list.enumerated() { r.sortOrder = i }
            }
            .onDelete { offsets in
                for i in offsets {
                    let r = shown[i]
                    GPXStore.delete(for: r.uuid)
                    model.invalidate(r.uuid)
                    context.delete(r)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: "Rechercher une trace")
        .navigationTitle("Tracés")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(value: "settings") {
                    Image(systemName: "gearshape")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Tri", selection: $sort) {
                        ForEach(TrackSort.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onImportTap) {
                    Image(systemName: "plus")
                }
            }
        }
    }
}
