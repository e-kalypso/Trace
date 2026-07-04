//  GPXParser.swift
//  Parseur GPX robuste : <trk> multi-segments, <rte>, <wpt>,
//  élévation + horodatages. Un fichier malformé rend nil, jamais un crash.

import Foundation

final class GPXParser: NSObject, XMLParserDelegate {

    static func parse(data: Data, fallbackName: String) -> ParsedTrack? {
        let p = GPXParser()
        let xml = XMLParser(data: data)
        xml.delegate = p
        guard xml.parse() || !p.points.isEmpty else { return nil }
        guard p.points.count >= 2 || !p.waypoints.isEmpty else { return nil }

        var pts = p.points
        TrackGeometry.accumulateDistances(&pts)
        let name = p.trackName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedTrack(
            name: (name?.isEmpty == false ? name! : fallbackName),
            points: pts,
            waypoints: p.waypoints,
            stats: TrackGeometry.stats(for: pts)
        )
    }

    // MARK: état du parseur

    private var points: [TrackPoint] = []
    private var waypoints: [Waypoint] = []
    private var trackName: String?

    private var inTrk = false
    private var inRte = false
    private var inWpt = false
    private var pendingLat: Double?
    private var pendingLon: Double?
    private var pendingEle: Double?
    private var pendingTime: Date?
    private var pendingWptName: String?
    private var text = ""
    private var elementStack: [String] = []

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let isoFracFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func date(from s: String) -> Date? {
        isoFormatter.date(from: s) ?? isoFracFormatter.date(from: s)
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes attrs: [String: String] = [:]) {
        elementStack.append(name)
        text = ""
        switch name {
        case "trk": inTrk = true
        case "rte": inRte = true
        case "wpt":
            inWpt = true
            pendingLat = Double(attrs["lat"] ?? "")
            pendingLon = Double(attrs["lon"] ?? "")
            pendingEle = nil
            pendingWptName = nil
        case "trkpt", "rtept":
            pendingLat = Double(attrs["lat"] ?? "")
            pendingLon = Double(attrs["lon"] ?? "")
            pendingEle = nil
            pendingTime = nil
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "name":
            // premier nom de trk/rte rencontré = nom de la trace
            if inWpt {
                pendingWptName = value
            } else if (inTrk || inRte) && trackName == nil {
                trackName = value
            }
        case "ele":
            pendingEle = Double(value)
        case "time":
            if elementStack.contains("trkpt") || elementStack.contains("rtept") {
                pendingTime = Self.date(from: value)
            }
        case "trkpt", "rtept":
            if let la = pendingLat, let lo = pendingLon,
               la.isFinite, lo.isFinite, abs(la) <= 90, abs(lo) <= 180 {
                points.append(TrackPoint(lat: la, lon: lo, ele: pendingEle, time: pendingTime))
            }
        case "wpt":
            if let la = pendingLat, let lo = pendingLon, la.isFinite, lo.isFinite {
                waypoints.append(Waypoint(lat: la, lon: lo,
                                          name: pendingWptName ?? "Repère",
                                          ele: pendingEle))
            }
            inWpt = false
        case "trk": inTrk = false
        case "rte": inRte = false
        default: break
        }
        if elementStack.last == name { elementStack.removeLast() }
    }
}
