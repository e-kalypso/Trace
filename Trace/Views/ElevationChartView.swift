//  ElevationChartView.swift
//  Profil altitude/distance (Swift Charts) avec scrub :
//  le doigt déplace un curseur synchronisé sur la carte,
//  et affiche altitude / distance / % de pente au point survolé.

import Charts
import CoreLocation
import SwiftUI

private struct ProfilePoint: Identifiable {
    let id: Int
    let km: Double
    let ele: Double
    let lat: Double
    let lon: Double
    let grade: Double   // % de pente locale
}

struct ElevationChartView: View {
    let points: [TrackPoint]
    var onScrub: (CLLocationCoordinate2D?) -> Void

    @State private var selected: ProfilePoint?

    private var profile: [ProfilePoint] {
        let withEle = points.filter { $0.ele != nil }
        guard withEle.count >= 2 else { return [] }
        let step = max(1, points.count / 400)
        var out: [ProfilePoint] = []
        var lastEle = withEle[0].ele ?? 0
        var i = 0
        while i < points.count {
            let p = points[i]
            let e = p.ele ?? lastEle
            lastEle = e
            // pente locale sur ~60 m devant
            var grade = 0.0
            var j = i
            while j < points.count - 1 && points[j].dist - p.dist < 60 { j += 1 }
            let dd = points[j].dist - p.dist
            if dd > 5, let e2 = points[j].ele {
                grade = (e2 - e) / dd * 100
            }
            out.append(ProfilePoint(id: i, km: p.dist / 1000, ele: e,
                                    lat: p.lat, lon: p.lon, grade: grade))
            i += step
        }
        if let last = points.last, let le = last.ele ?? out.last.map({ $0.ele }) {
            out.append(ProfilePoint(id: points.count - 1, km: last.dist / 1000,
                                    ele: le, lat: last.lat, lon: last.lon, grade: 0))
        }
        return out
    }

    var body: some View {
        let data = profile
        if data.isEmpty {
            Text("Pas de données d'altitude dans ce fichier.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                if let s = selected {
                    HStack(spacing: 12) {
                        Label("\(Int(s.ele)) m", systemImage: "arrow.up.forward")
                        Text(String(format: "%.2f km", s.km))
                        Text(String(format: "%+.0f %%", s.grade))
                            .foregroundStyle(gradeColor(s.grade))
                    }
                    .font(.footnote.monospacedDigit().weight(.semibold))
                } else {
                    Text("Glissez sur le profil pour explorer")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Chart(data) { p in
                    AreaMark(x: .value("km", p.km), y: .value("alt", p.ele))
                        .foregroundStyle(
                            .linearGradient(
                                colors: [.accentColor.opacity(0.35), .accentColor.opacity(0.03)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    LineMark(x: .value("km", p.km), y: .value("alt", p.ele))
                        .foregroundStyle(Color.accentColor)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))

                    if let s = selected, s.id == p.id {
                        RuleMark(x: .value("km", s.km))
                            .foregroundStyle(.orange)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        PointMark(x: .value("km", s.km), y: .value("alt", s.ele))
                            .foregroundStyle(.orange)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 130)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let origin = geo[proxy.plotAreaFrame].origin
                                        let x = value.location.x - origin.x
                                        guard let km: Double = proxy.value(atX: x) else { return }
                                        if let nearest = data.min(by: {
                                            abs($0.km - km) < abs($1.km - km)
                                        }) {
                                            selected = nearest
                                            onScrub(CLLocationCoordinate2D(
                                                latitude: nearest.lat, longitude: nearest.lon))
                                        }
                                    }
                                    .onEnded { _ in
                                        selected = nil
                                        onScrub(nil)
                                    }
                            )
                    }
                }
            }
        }
    }

    private func gradeColor(_ g: Double) -> Color {
        let a = abs(g)
        if a < 10 { return .green }
        if a < 20 { return .orange }
        return .red
    }
}
