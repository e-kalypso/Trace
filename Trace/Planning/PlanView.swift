//  PlanView.swift
//  Planifier une sortie (§8) : heure de départ → horaires de passage
//  (DIN 33466), météo Open-Meteo au bon endroit ET au bon moment (§5.2),
//  coucher du soleil + alerte « retour avant la nuit », feuille de route.

import SwiftUI

struct PlanView: View {
    @EnvironmentObject private var model: AppModel
    let record: TrackRecord

    @State private var departure = defaultDeparture()
    @State private var weatherByPoint: [Int: HourlyWeather] = [:]
    @State private var loading = false
    @State private var weatherError = false

    private static func defaultDeparture() -> Date {
        // demain 8 h
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return cal.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow) ?? Date()
    }

    private struct KeyPoint: Identifiable {
        let id: Int
        let label: String
        let point: TrackPoint
        let eta: Date
    }

    private var parsed: ParsedTrack? { model.track(for: record) }

    private var keyPoints: [KeyPoint] {
        guard let t = parsed, t.points.count >= 2 else { return [] }
        let pts = t.points
        let total = max(1, t.stats.distance)
        let dur = t.stats.estimatedDuration

        func at(fraction: Double) -> TrackPoint {
            let target = total * fraction
            return pts.min { abs($0.dist - target) < abs($1.dist - target) } ?? pts[0]
        }
        // point culminant
        let summit = pts.max { ($0.ele ?? -9999) < ($1.ele ?? -9999) } ?? pts[0]

        var raw: [(String, TrackPoint)] = [
            ("Départ", pts[0]),
            ("Mi-parcours", at(fraction: 0.5)),
            ("Point culminant", summit),
            ("Arrivée", pts[pts.count - 1]),
        ]
        // tri par distance le long de la trace, dédoublonnage grossier
        raw.sort { $0.1.dist < $1.1.dist }
        var seen: Set<Int> = []
        var out: [KeyPoint] = []
        for (label, p) in raw {
            let bucket = Int(p.dist / 200)
            if seen.contains(bucket) { continue }
            seen.insert(bucket)
            let eta = departure.addingTimeInterval(dur * (p.dist / total))
            out.append(KeyPoint(id: out.count, label: label, point: p, eta: eta))
        }
        return out
    }

    private var sunset: Date? {
        guard let t = parsed, let first = t.points.first else { return nil }
        return Sun.times(date: departure, lat: first.lat, lon: first.lon).sunset
    }

    private var nightWarning: Bool {
        guard let sunset, let last = keyPoints.last else { return false }
        return last.eta > sunset.addingTimeInterval(-30 * 60)
    }

    var body: some View {
        List {
            Section("Départ") {
                DatePicker("Date et heure", selection: $departure)
                if let t = parsed {
                    LabeledContent("Durée estimée (DIN 33466)",
                                   value: Fmt.duration(t.stats.estimatedDuration))
                }
                if let sunset {
                    LabeledContent("Coucher du soleil") {
                        Text(sunset, style: .time)
                    }
                }
                if nightWarning {
                    Label("Arrivée estimée proche ou après la nuit — partez plus tôt.",
                          systemImage: "moon.stars.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }

            Section("Horaires et météo au passage") {
                ForEach(keyPoints) { kp in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(kp.label).font(.body.weight(.semibold))
                            Spacer()
                            Text(kp.eta, style: .time)
                                .font(.body.monospacedDigit().weight(.semibold))
                        }
                        Text("km \(String(format: "%.1f", kp.point.dist / 1000)) · \(Fmt.elevation(kp.point.ele))")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let w = weatherByPoint[kp.id] {
                            weatherRow(w)
                        }
                    }
                    .padding(.vertical, 2)
                }

                if loading {
                    HStack {
                        ProgressView()
                        Text("Météo en cours de chargement…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else if weatherError {
                    Label("Météo indisponible (hors ligne ?)", systemImage: "wifi.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ShareLink(item: roadbook()) {
                    Label("Envoyer la feuille de route", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("Itinéraire + horaires prévus, à partager à un proche : « si je ne suis pas rentré, appelle les secours » (§8).")
            }
        }
        .navigationTitle("Planifier")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: departure) { await loadWeather() }
    }

    @ViewBuilder
    private func weatherRow(_ w: HourlyWeather) -> some View {
        let risk = OpenMeteo.risk(w, summitEle: parsed?.stats.maxEle)
        HStack(spacing: 10) {
            Image(systemName: risk.symbol)
                .foregroundStyle(risk == .go ? .green : risk == .caution ? .orange : .red)
            if let temp = w.temperature {
                Text("\(Int(temp.rounded()))°")
            }
            if let gusts = w.windGusts {
                Label("\(Int(gusts)) km/h", systemImage: "wind")
            }
            if let prob = w.precipProbability {
                Label("\(Int(prob)) %", systemImage: "cloud.rain")
            }
            if let fl = w.freezingLevel {
                Label("0° à \(Int(fl)) m", systemImage: "thermometer.snowflake")
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private func loadWeather() async {
        guard !keyPoints.isEmpty else { return }
        loading = true
        weatherError = false
        var result: [Int: HourlyWeather] = [:]
        for kp in keyPoints {
            do {
                let hours = try await OpenMeteo.forecast(lat: kp.point.lat, lon: kp.point.lon)
                if let w = OpenMeteo.nearest(hours, to: kp.eta) {
                    result[kp.id] = w
                }
            } catch {
                weatherError = true
            }
        }
        weatherByPoint = result
        loading = false
    }

    private func roadbook() -> String {
        let df = DateFormatter()
        df.dateStyle = .full
        df.timeStyle = .short
        var text = """
        🥾 Feuille de route — \(record.name)
        Départ : \(df.string(from: departure))
        Distance : \(Fmt.distance(record.distance)) · D+ \(Int(record.ascent)) m

        Horaires prévus :
        """
        let tf = DateFormatter()
        tf.timeStyle = .short
        for kp in keyPoints {
            text += "\n  • \(kp.label) (km \(String(format: "%.1f", kp.point.dist / 1000))) : \(tf.string(from: kp.eta))"
        }
        if let sunset {
            text += "\nCoucher du soleil : \(tf.string(from: sunset))"
        }
        text += "\n\nSi je ne donne pas de nouvelles 2 h après l'arrivée prévue, appelle le 112."
        return text
    }
}
