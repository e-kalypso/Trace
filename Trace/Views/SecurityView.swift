//  SecurityView.swift
//  Module Sécurité (§11) : coordonnées aux formats attendus par les
//  secours (copiables en 1 tap), altitude, numéros d'urgence montagne,
//  partage de position. Fonctionne hors ligne (le GPS n'a pas besoin
//  de réseau).

import SwiftUI
import UIKit

struct SecurityView: View {
    /// Observé directement : position et qualité GPS vivantes.
    @ObservedObject var location: LocationManager
    @State private var copied: String?

    private var fix: GeoFix? { location.fix }

    var body: some View {
        List {
            Section("Ma position (pour les secours)") {
                if let fix {
                    row("Décimal", decimal(fix))
                    row("DMS", dms(fix))
                    row("Altitude", "\(Int(fix.altitude)) m")
                    LabeledContent("Précision GPS") {
                        Text("±\(Int(fix.horizontalAccuracy)) m · \(location.quality.rawValue)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        location.start(background: false)
                    } label: {
                        Label("Activer le GPS", systemImage: "location.fill")
                    }
                }
            }

            if let fix {
                Section {
                    ShareLink(item: "Ma position : \(decimal(fix)) (±\(Int(fix.horizontalAccuracy)) m, alt. \(Int(fix.altitude)) m) — https://maps.apple.com/?ll=\(String(format: "%.5f", fix.coordinate.latitude)),\(String(format: "%.5f", fix.coordinate.longitude))") {
                        Label("Partager ma position", systemImage: "square.and.arrow.up")
                    }
                }
            }

            Section {
                Link(destination: URL(string: "tel:112")!) {
                    Label("112 — Urgences européennes", systemImage: "phone.fill")
                }
                Link(destination: URL(string: "tel:+33450531689")!) {
                    Label("PGHM Chamonix", systemImage: "cross.case.fill")
                }
            } header: {
                Text("Urgences montagne")
            } footer: {
                Text("Hors réseau : l'iPhone 14+ permet SOS d'urgence par satellite (maintenez le bouton latéral + volume).")
            }
        }
        .navigationTitle("Sécurité")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if let copied {
                Text("\(copied) copié ✓")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 16)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        Button {
            UIPasteboard.general.string = value
            copied = label
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { copied = nil }
        } label: {
            HStack {
                Text(label).foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func decimal(_ f: GeoFix) -> String {
        String(format: "%.5f, %.5f", f.coordinate.latitude, f.coordinate.longitude)
    }

    private func dms(_ f: GeoFix) -> String {
        func conv(_ v: Double, pos: String, neg: String) -> String {
            let a = abs(v)
            let d = Int(a)
            let m = Int((a - Double(d)) * 60)
            let s = ((a - Double(d)) * 60 - Double(m)) * 60
            return String(format: "%d°%02d'%04.1f\"%@", d, m, s, v >= 0 ? pos : neg)
        }
        return conv(f.coordinate.latitude, pos: "N", neg: "S") + " "
            + conv(f.coordinate.longitude, pos: "E", neg: "O")
    }
}
