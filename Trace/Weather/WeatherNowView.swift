//  WeatherNowView.swift
//  Météo montagne sur MA position, maintenant et les 12 prochaines
//  heures (Open-Meteo) : le réflexe avant de partir ou au refuge.

import SwiftUI

struct WeatherNowView: View {
    @EnvironmentObject private var model: AppModel

    @State private var hours: [HourlyWeather] = []
    @State private var loading = false
    @State private var error: String?

    private var upcoming: [HourlyWeather] {
        let now = Date().addingTimeInterval(-1800)
        return Array(hours.filter { $0.time > now }.prefix(12))
    }

    var body: some View {
        List {
            if let current = upcoming.first {
                Section {
                    let risk = OpenMeteo.risk(current, summitEle: nil)
                    HStack(spacing: 14) {
                        Image(systemName: risk.symbol)
                            .font(.system(size: 34))
                            .foregroundStyle(risk == .go ? .green
                                             : risk == .caution ? .orange : .red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(risk.label).font(.headline)
                            if let t = current.temperature, let f = current.feelsLike {
                                Text("\(Int(t.rounded()))° (ressenti \(Int(f.rounded()))°)")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let fl = current.freezingLevel {
                            VStack(spacing: 1) {
                                Text("0 °C").font(.caption2).foregroundStyle(.secondary)
                                Text("\(Int(fl)) m")
                                    .font(.subheadline.monospacedDigit().weight(.bold))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Maintenant, ici")
                }
            }

            Section {
                if loading {
                    HStack {
                        ProgressView()
                        Text("Chargement de la météo…")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else if let error {
                    Label(error, systemImage: "wifi.slash")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(upcoming.indices, id: \.self) { i in
                    let h = upcoming[i]
                    HStack(spacing: 10) {
                        Text(h.time, style: .time)
                            .font(.callout.monospacedDigit().weight(.semibold))
                            .frame(width: 52, alignment: .leading)
                        if let t = h.temperature {
                            Text("\(Int(t.rounded()))°")
                                .font(.callout.monospacedDigit())
                                .frame(width: 36, alignment: .leading)
                        }
                        if let g = h.windGusts {
                            Label("\(Int(g))", systemImage: "wind")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(g > 45 ? .orange : .secondary)
                        }
                        if let p = h.precipProbability {
                            Label("\(Int(p)) %", systemImage: "cloud.rain")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(p > 50 ? .blue : .secondary)
                        }
                        Spacer()
                        let risk = OpenMeteo.risk(h, summitEle: nil)
                        Image(systemName: risk.symbol)
                            .foregroundStyle(risk == .go ? .green
                                             : risk == .caution ? .orange : .red)
                    }
                }
            } header: {
                Text("12 prochaines heures")
            } footer: {
                Text("Open-Meteo (modèles haute résolution). Rafales en km/h. Pour la météo le long d'une trace à l'heure de passage, utilisez Planifier depuis la trace.")
            }
        }
        .navigationTitle("Météo ici")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        if model.location.fix == nil {
            model.location.start(background: false)
            for _ in 0..<10 {
                if model.location.fix != nil { break }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        guard let fix = model.location.fix else {
            error = "Activez la localisation pour la météo locale."
            return
        }
        loading = true
        error = nil
        do {
            hours = try await OpenMeteo.forecast(lat: fix.coordinate.latitude,
                                                 lon: fix.coordinate.longitude)
        } catch {
            self.error = "Météo indisponible (hors ligne ?)."
        }
        loading = false
    }
}
