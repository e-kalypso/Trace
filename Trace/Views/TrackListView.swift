//  TrackListView.swift
//  Liste des traces : visibilité, couleur, stats, réorganisation,
//  import GPX (Fichiers / multi-sélection).

import SwiftData
import SwiftUI

struct TrackListView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var model: AppModel
    @Query(sort: \TrackRecord.sortOrder) private var records: [TrackRecord]

    @Binding var selectedUUID: UUID?
    var onImportTap: () -> Void

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

            ForEach(records) { rec in
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
                var list = records
                list.move(fromOffsets: from, toOffset: to)
                for (i, r) in list.enumerated() { r.sortOrder = i }
            }
            .onDelete { offsets in
                for i in offsets {
                    let r = records[i]
                    GPXStore.delete(for: r.uuid)
                    model.invalidate(r.uuid)
                    context.delete(r)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Tracés")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(value: "settings") {
                    Image(systemName: "gearshape")
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
