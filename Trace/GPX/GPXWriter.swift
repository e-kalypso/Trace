//  GPXWriter.swift
//  Sérialisation GPX 1.1 (après édition : inverser, simplifier…).

import Foundation

enum GPXWriter {

    static func gpx(name: String, points: [TrackPoint], waypoints: [Waypoint]) -> String {
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Trace" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata><name>\(escape(name))</name></metadata>

        """
        for w in waypoints {
            out += "  <wpt lat=\"\(fmt(w.lat))\" lon=\"\(fmt(w.lon))\">"
            if let e = w.ele { out += "<ele>\(String(format: "%.1f", e))</ele>" }
            out += "<name>\(escape(w.name))</name></wpt>\n"
        }
        out += "  <trk>\n    <name>\(escape(name))</name>\n    <trkseg>\n"
        let iso = ISO8601DateFormatter()
        for p in points {
            out += "      <trkpt lat=\"\(fmt(p.lat))\" lon=\"\(fmt(p.lon))\">"
            if let e = p.ele { out += "<ele>\(String(format: "%.1f", e))</ele>" }
            if let t = p.time { out += "<time>\(iso.string(from: t))</time>" }
            out += "</trkpt>\n"
        }
        out += "    </trkseg>\n  </trk>\n</gpx>\n"
        return out
    }

    private static func fmt(_ v: Double) -> String { String(format: "%.6f", v) }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
