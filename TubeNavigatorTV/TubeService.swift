import Foundation
import SwiftUI

// TfL Unified API — https://api.tfl.gov.uk
// Free, no key required for personal use (about 50 requests/minute).
// The TV app reads line status, planned disruptions, live cameras
// and live arrivals — no journey planning, no places. Same endpoints
// as the iPhone app (TubeNavigator), trimmed to what a status board
// needs.
//
//   GET /Line/Mode/tube,dlr,elizabeth-line/Status
//   GET /Line/{explicit-line-ids}/Status/{start}/to/{end}   (planned)
//   GET /Line/{line-id}/Arrivals/{stopPointId}   (departure boards)
// The dated path only works with explicit line IDs — the
// /Line/Mode/... form of that path 404s.

struct TfLLine: Decodable, Identifiable {
    let id: String
    let name: String
    let modeName: String?
    let lineStatuses: [LineStatusItem]
}

struct ValidityPeriod: Decodable {
    let fromDate: String
    let toDate: String
    let isNow: Bool
}

struct LineStatusItem: Decodable {
    let statusSeverityDescription: String
    let reason: String?
    let validityPeriods: [ValidityPeriod]?
}

// MARK: - Line colours

enum TubeLines {
    // TfL line colours, by line id.
    static let colours: [String: String] = [
        "bakerloo": "894E24",
        "central": "DC241F",
        "circle": "FFCE00",
        "district": "007229",
        "hammersmith-city": "D799AF",
        "jubilee": "868F98",
        "metropolitan": "751056",
        "northern": "000000",
        "piccadilly": "0019A8",
        "victoria": "00A0E2",
        "waterloo-city": "76D0BD",
        "dlr": "00AFAD",
        "elizabeth": "9364CD",
    ]

    static func color(for id: String) -> Color {
        Color(hex: colours[id] ?? "868F98")
    }
}

extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var rgb: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Planned disruptions

enum PlannedRange: String, CaseIterable, Identifiable {
    case next7Days = "Next 7 days"
    case trip = "Trip · Dec 15–24"
    var id: String { rawValue }
}

struct PlannedDisruption: Identifiable {
    // Identical notices (e.g. a network-wide strike) appear on every line,
    // so items are grouped by reason + start date, with all affected lines.
    var id: String { reason + "|" + (fromDate ?? "") }
    let lineNames: [String]
    let severity: String
    let reason: String
    let fromDate: String?
    let toDate: String?

    var displayLines: String {
        if lineNames.count == 1 { return lineNames[0] }
        if lineNames.count >= 10 { return "All Tube lines" }
        return lineNames.joined(separator: ", ")
    }
}

// MARK: - Departure boards (v1.11)

// One prediction from the Arrivals feed. Decoded defensively —
// the feed always carries these fields, but a missing one must not
// kill the whole board.
struct Arrival: Decodable, Identifiable {
    let predictionId: String
    let lineId: String
    let lineName: String
    let platformName: String
    let direction: String
    let destinationName: String
    let towards: String
    let expectedArrival: String?
    let timeToStation: Int?
    let currentLocation: String
    let modeName: String
    // v1.14: the train's id, so the arrival sound can tell one train
    // from the next (a bong fires once per train, not once per
    // refresh), and timeToLive, so the ghost filter can tell a real
    // imminent train from a placeholder (see fetchArrivals).
    let vehicleId: String
    let timeToLive: String?
    // v1.17: the station this prediction is for — the whole-line
    // Arrivals feed (used by the live map) returns one row per
    // train per station, and the map needs the station to place
    // the train. Not present on every row type, so it defaults
    // to "" rather than failing the decode.
    let stationName: String

    // v1.16: the ForEach identity — NOT the raw prediction id.
    // The DLR feed gives EVERY row the same prediction id
    // ("-937089209"), so predictionId alone is not a unique
    // identity. SwiftUI's ForEach with duplicate ids renders
    // "undefined results": each platform section repeated its
    // first train (checked live 23 Nov 2026 — Platform 1 showed
    // three "Lewisham, 3 mins, 15:57" while the feed's three
    // Platform 1 trains were at 15:57, 16:01 and 16:06, and the
    // console warned the id occurs multiple times). The identity
    // is the prediction id plus platform, destination and arrival
    // time, which together name one train on every line. The
    // dedupe in fetchArrivals still keys on predictionId, not on
    // this composite, so its clock-based merging is unchanged.
    var id: String { "\(predictionId)|\(platformName)|\(destinationName)|\(expectedArrival ?? "")" }

    enum CodingKeys: String, CodingKey {
        case predictionId = "id"
        case lineId, lineName, platformName, direction, destinationName, towards, expectedArrival, timeToStation, currentLocation, modeName, vehicleId, timeToLive, stationName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        predictionId = (try? c.decode(String.self, forKey: .predictionId)) ?? UUID().uuidString
        lineId = (try? c.decode(String.self, forKey: .lineId)) ?? ""
        lineName = (try? c.decode(String.self, forKey: .lineName)) ?? ""
        platformName = (try? c.decode(String.self, forKey: .platformName)) ?? "Platform Unknown"
        direction = (try? c.decode(String.self, forKey: .direction)) ?? ""
        destinationName = (try? c.decode(String.self, forKey: .destinationName)) ?? ""
        towards = (try? c.decode(String.self, forKey: .towards)) ?? ""
        expectedArrival = try? c.decode(String.self, forKey: .expectedArrival)
        timeToStation = try? c.decode(Int.self, forKey: .timeToStation)
        currentLocation = (try? c.decode(String.self, forKey: .currentLocation)) ?? ""
        modeName = (try? c.decode(String.self, forKey: .modeName)) ?? ""
        vehicleId = (try? c.decode(String.self, forKey: .vehicleId)) ?? ""
        timeToLive = try? c.decode(String.self, forKey: .timeToLive)
        stationName = (try? c.decode(String.self, forKey: .stationName)) ?? ""
    }
}

// A station on the Boards tab: the TfL stop point id and the lines
// that serve it, in picker order. Ids and lines are from the iPhone
// app's StationData (same TfL ids the journey planner uses), and
// were cross-checked against the StopPoint API on 23 Nov 2026 for
// Paddington, Oxford Circus, Green Park, Bank, Liverpool Street
// and Waterloo. Most stations answer to one stop point; Paddington
// and Liverpool Street need two (their Tube lines answer to the
// 940GZZLU… id, their Elizabeth line platforms to the 910G… rail
// id — 910GPADTON, 910GLIVST), and Canary Wharf needs three
// (Elizabeth 910GCANWHRF, Jubilee 940GZZLUCYF, DLR 940GZZDLCAN —
// from the HUBCAW line groups, checked live 23 Nov 2026). So each
// station carries its default id plus a per-line override map.
struct BoardStation: Identifiable, Hashable {
    var id: String { arrivalsId }
    let name: String
    let lines: [String]
    let arrivalsId: String
    let extraArrivalsIds: [String: String]

    func arrivalsId(for lineId: String) -> String {
        extraArrivalsIds[lineId] ?? arrivalsId
    }
}

extension TubeService {
    // The stations Jeffery uses — the main termini, Paddington
    // first, then alphabetical. King's Cross and St Pancras share
    // one Tube station (King's Cross St. Pancras), so they are one
    // entry. Set by Jeffery 23 Nov 2026.
    static let boardStations: [BoardStation] = [
        BoardStation(name: "Paddington", lines: ["elizabeth", "bakerloo", "circle", "district", "hammersmith-city"], arrivalsId: "940GZZLUPAC", extraArrivalsIds: ["elizabeth": "910GPADTON"]),
        BoardStation(name: "Canary Wharf", lines: ["elizabeth", "jubilee", "dlr"], arrivalsId: "940GZZLUCYF", extraArrivalsIds: ["elizabeth": "910GCANWHRF", "dlr": "940GZZDLCAN"]),
        BoardStation(name: "King's Cross St. Pancras", lines: ["circle", "hammersmith-city", "metropolitan", "northern", "piccadilly", "victoria"], arrivalsId: "940GZZLUKSX", extraArrivalsIds: [:]),
        BoardStation(name: "Liverpool Street", lines: ["elizabeth", "central", "circle", "hammersmith-city", "metropolitan"], arrivalsId: "940GZZLULVT", extraArrivalsIds: ["elizabeth": "910GLIVST"]),
        BoardStation(name: "London Bridge", lines: ["jubilee", "northern"], arrivalsId: "940GZZLULNB", extraArrivalsIds: [:]),
        BoardStation(name: "Victoria", lines: ["circle", "district", "victoria"], arrivalsId: "940GZZLUVIC", extraArrivalsIds: [:]),
        BoardStation(name: "Waterloo", lines: ["bakerloo", "jubilee", "northern", "waterloo-city"], arrivalsId: "940GZZLUWLO", extraArrivalsIds: [:]),
    ]
}

// MARK: - Live cameras (JamCams, v1.9)

// TfL traffic cameras. GET /Place/Type/JamCam returns all 889 as
// Places; each one's additionalProperties carry the clip URL
// (videoUrl, an ~11-second MP4 refreshed every few minutes), a still
// (imageUrl) and whether it is up (available, the string "true" /
// "false"). The app only shows a shortlist of six central ones —
// the full list is mostly motorways and suburbs. No key, same TfL
// open data as the rest of the app.
struct JamCamPlace: Decodable {
    let commonName: String
    let additionalProperties: [JamCamProperty]

    struct JamCamProperty: Decodable {
        let key: String
        let value: String
    }
}

struct JamCam: Identifiable {
    var id: String { name }
    let name: String       // display name, e.g. "Westminster Bridge"
    let view: String       // the camera's TfL name, e.g. "Westminster Bridge/York Rd"
    let videoUrl: String
    let imageUrl: String
    let available: Bool
}

@MainActor
final class TubeService: ObservableObject {
    @Published var lineStatuses: [TfLLine] = []
    @Published var isLoadingStatus = false
    @Published var statusError: String?
    @Published var lastStatusUpdate: Date?

    @Published var plannedItems: [PlannedDisruption] = []
    @Published var isLoadingPlanned = false
    @Published var plannedError: String?
    @Published var plannedRange: PlannedRange = .next7Days
    @Published var lastPlannedUpdate: Date?

    @Published var cameras: [JamCam] = []
    @Published var isLoadingCameras = false
    @Published var camerasError: String?
    @Published var lastCamerasUpdate: Date?

    // The six cameras on the Live tab, in display order. Matched by
    // the API's commonName. "Oxford Circus" is the Oxford St/Vere St
    // camera, which sits at the junction.
    static let liveCameraShortlist: [(display: String, commonName: String)] = [
        ("Westminster Bridge", "Westminster Bridge/York Rd"),
        ("Parliament Square", "Parliament Square"),
        ("Piccadilly Circus", "Piccadilly Circus"),
        ("Trafalgar Square", "Trafalgar Square"),
        ("Oxford Circus", "Oxford St/Vere St"),
        ("Tower Bridge", "Tower Bridge App./East Smithfield"),
    ]

    func fetchLineStatus() async {
        isLoadingStatus = true
        statusError = nil
        let urlString = "https://api.tfl.gov.uk/Line/Mode/tube,dlr,elizabeth-line/Status"
        do {
            guard let url = URL(string: urlString) else { throw URLError(.badURL) }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            var lines = try JSONDecoder().decode([TfLLine].self, from: data)
            lines.sort { $0.name < $1.name }
            lineStatuses = lines
            lastStatusUpdate = Date()
        } catch {
            statusError = "Could not fetch line status. Showing the last status if there is one. (\(error.localizedDescription))"
        }
        isLoadingStatus = false
    }

    func fetchPlanned() async {
        isLoadingPlanned = true
        plannedError = nil
        let ids = "bakerloo,central,circle,district,hammersmith-city,jubilee,metropolitan,northern,piccadilly,victoria,waterloo-city,dlr,elizabeth"
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_GB")
        let start: Date
        let end: Date
        switch plannedRange {
        case .next7Days:
            start = Date()
            end = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        case .trip:
            start = fmt.date(from: "2026-12-15") ?? Date()
            end = fmt.date(from: "2026-12-24") ?? Date()
        }
        let urlString = "https://api.tfl.gov.uk/Line/\(ids)/Status/\(fmt.string(from: start))/to/\(fmt.string(from: end))"
        do {
            guard let url = URL(string: urlString) else { throw URLError(.badURL) }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let lines = try JSONDecoder().decode([TfLLine].self, from: data)
            // Group identical notices across lines (network-wide strikes).
            var grouped: [String: PlannedDisruption] = [:]
            for line in lines {
                for status in line.lineStatuses {
                    guard status.statusSeverityDescription != "Good Service" else { continue }
                    guard let reason = status.reason, !reason.isEmpty else { continue }
                    let vp = status.validityPeriods?.first
                    let key = reason + "|" + (vp?.fromDate ?? "")
                    if var existing = grouped[key] {
                        if !existing.lineNames.contains(line.name) {
                            existing = PlannedDisruption(
                                lineNames: existing.lineNames + [line.name],
                                severity: existing.severity,
                                reason: existing.reason,
                                fromDate: existing.fromDate,
                                toDate: existing.toDate
                            )
                            grouped[key] = existing
                        }
                    } else {
                        grouped[key] = PlannedDisruption(
                            lineNames: [line.name],
                            severity: status.statusSeverityDescription,
                            reason: reason,
                            fromDate: vp?.fromDate,
                            toDate: vp?.toDate
                        )
                    }
                }
            }
            plannedItems = grouped.values.sorted { ($0.fromDate ?? "") < ($1.fromDate ?? "") }
            lastPlannedUpdate = Date()
        } catch {
            plannedError = "Could not fetch planned disruptions. (\(error.localizedDescription))"
        }
        isLoadingPlanned = false
    }

    func fetchCameras() async {
        isLoadingCameras = true
        camerasError = nil
        let urlString = "https://api.tfl.gov.uk/Place/Type/JamCam"
        do {
            guard let url = URL(string: urlString) else { throw URLError(.badURL) }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let places = try JSONDecoder().decode([JamCamPlace].self, from: data)
            var found: [JamCam] = []
            for entry in Self.liveCameraShortlist {
                guard let place = places.first(where: { $0.commonName == entry.commonName }) else { continue }
                var props: [String: String] = [:]
                for p in place.additionalProperties { props[p.key] = p.value }
                guard let videoUrl = props["videoUrl"], let imageUrl = props["imageUrl"] else { continue }
                found.append(JamCam(
                    name: entry.display,
                    view: place.commonName,
                    videoUrl: videoUrl,
                    imageUrl: imageUrl,
                    available: props["available"] == "true"
                ))
            }
            cameras = found
            lastCamerasUpdate = Date()
        } catch {
            camerasError = "Could not fetch the cameras. (\(error.localizedDescription))"
        }
        isLoadingCameras = false
    }

    // MARK: - Departure boards (v1.11)

    // Live arrivals — the same countdown feed as the station boards.
    // GET /Line/{lineId}/Arrivals/{stopPointId} returns one line's
    // trains at one station, each with its destination, platform,
    // direction, seconds to arrival and where it is right now.
    // The board fetches per line: Paddington's Elizabeth line
    // platforms answer to a different stop point (910GPADTON, the
    // rail station) than its Tube platforms (940GZZLUPAC), so each
    // station carries the stop point to query per line (see
    // BoardStation.arrivalsId(for:)). Verified live 23 Nov 2026:
    // 910GPADTON returns the Elizabeth line trains, 940GZZLUPAC
    // returns the Tube lines (Bakerloo first trains of the day,
    // still in Queen's Park sidings) — neither covers the other.
    @Published var arrivals: [Arrival] = []
    @Published var isLoadingArrivals = false
    @Published var arrivalsError: String?
    @Published var lastArrivalsUpdate: Date?

    func fetchArrivals(station: BoardStation, lineId: String) async {
        // Only show the spinner on the first load — the 30-second
        // refresh must not flash the board.
        if arrivals.isEmpty { isLoadingArrivals = true }
        arrivalsError = nil
        let urlString = "https://api.tfl.gov.uk/Line/\(lineId)/Arrivals/\(station.arrivalsId(for: lineId))"
        do {
            guard let url = URL(string: urlString) else { throw URLError(.badURL) }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            var rows = try JSONDecoder().decode([Arrival].self, from: data)
            // Paddington's Elizabeth line feed covers the whole
            // station complex (910GPADTON's children include both
            // the underground station and the mainline station), so
            // it also returns the mainline platforms 11 and 12 —
            // late-night trains terminating at Paddington mainline.
            // Jeffery wants only the underground platforms A and B
            // on the board, so drop the mainline-platform rows here,
            // before dedupe and the ghost filter. Scoped to
            // Paddington's Elizabeth line only: outer Elizabeth
            // line stations use numbered platforms, and a future
            // board out there must not go blank. (v1.18, 23 Nov 2026.)
            if lineId == "elizabeth" && station.arrivalsId(for: lineId) == "910GPADTON" {
                rows.removeAll { row in
                    row.platformName == "Platform 11" || row.platformName == "Platform 12"
                        || row.platformName == "11" || row.platformName == "12"
                }
            }
            // The feed returns some predictions more than once, and
            // the copies differ in the raw seconds (timeToStation)
            // by a few seconds — same platform, same destination,
            // same displayed minutes, same clock time. So the key
            // is what the board shows (platform + destination +
            // clock time, HH:mm), not the raw seconds: the old key
            // used timeToStation, and the copies slipped through
            // it. The prediction id stays in the key: on lines
            // where ids are real (Elizabeth, Tube) it keeps two
            // different trains apart, and on the DLR every row
            // shares one id ("-937089209") so it adds nothing
            // there. Two real trains to the same place due in the
            // same minute would also merge — that needs a sub-minute
            // headway, which these lines don't run. (v1.16 note:
            // the DLR board's triplication turned out NOT to be a
            // dedupe miss at all — the feed returns 16 distinct
            // trains and the dedupe kept all 16. The triplication
            // was SwiftUI repeating the first row because every DLR
            // row shared one prediction id; see Arrival.id. The
            // dedupe below is still needed for the Elizabeth line,
            // whose feed really does return each prediction three
            // times.)
            var seenKeys = Set<String>()
            rows.removeAll { row in
                // The clock time is what the board shows; the copies
                // share it to the minute. Fall back to the raw
                // seconds when there's no arrival time to format.
                // Keys on predictionId, not row.id — row.id is the
                // composite ForEach identity (see Arrival.id).
                let clock = TubeService.arrivalTimeText(row.expectedArrival)
                let when = clock.isEmpty ? "\(row.timeToStation ?? -1)s" : clock
                let key = "\(row.predictionId)|\(row.platformName)|\(row.destinationName)|\(when)"
                return !seenKeys.insert(key).inserted
            }
            // Drop the early-morning placeholder rows. Before the
            // first trains run, the feed lists trains "due in 41
            // seconds" that do not exist — the real first trains
            // (05:48, 05:54) carry a real wait. The platform is NOT
            // the signal — the placeholders can carry any platform
            // ("Platform Unknown", "A", "B", even "Platform 10" /
            // "Platform 11", all seen 23 Nov 2026). v1.11–v1.13 also
            // used an empty currentLocation as the signal, but that
            // was wrong: Elizabeth line rows NEVER carry a location
            // (checked live 23 Nov 2026 — every row at Paddington
            // blank), so the old rule silently dropped every
            // Elizabeth line train within five minutes, and the
            // "arriving" label could never have shown on it. The
            // signal that does hold: a placeholder's prediction
            // outlives its own arrival by minutes (timeToLive far
            // past expectedArrival — 9 to 45 minutes in the live
            // rows), while a real train's prediction expires around
            // its arrival (timeToLive from ~45 seconds before to a few
            // seconds after expectedArrival — both seen live 23 Nov 2026).
            // So: drop a row under five minutes with no location only
            // when its prediction also
            // outlives its arrival by more than two minutes (or
            // when the dates are missing, the old cautious rule).
            rows.removeAll { row in
                guard let tts = row.timeToStation, tts < 300 else { return false }
                guard row.currentLocation.isEmpty else { return false }
                guard let ttl = TubeService.parseISODate(row.timeToLive),
                      let exp = TubeService.parseISODate(row.expectedArrival) else { return true }
                return ttl > exp.addingTimeInterval(120)
            }
            rows.removeAll { $0.timeToStation == nil }
            rows.sort { ($0.timeToStation ?? 0) < ($1.timeToStation ?? 0) }
            arrivals = rows
            lastArrivalsUpdate = Date()
        } catch {
            // A cancelled fetch (the line changed under it) is not
            // an error — the new line's fetch replaces it. Without
            // this, flicking across lines flashes an error.
            if !(error is CancellationError) {
                arrivalsError = "Could not fetch arrivals. (\(error.localizedDescription))"
            }
        }
        isLoadingArrivals = false
    }

    // "Heathrow Terminal 4 Rail Station" -> "Heathrow Terminal 4";
    // "Elephant & Castle Underground Station" -> "Elephant & Castle".
    static func cleanDestination(_ name: String) -> String {
        name.replacingOccurrences(of: " Rail Station", with: "")
            .replacingOccurrences(of: " Underground Station", with: "")
    }

    // The station boards show "Shenfield via Stratford" — the feed
    // only gives the destination, so the "via" comes from the route.
    // Fixed per Elizabeth line destination; Tube destinations stand
    // alone (the destination says enough).
    static func viaText(for destination: String, lineId: String, stationName: String = "") -> String {
        guard lineId == "elizabeth" else { return "" }
        let via: String
        switch cleanDestination(destination) {
        case "Shenfield": via = "Stratford"
        case "Abbey Wood": via = "Canary Wharf"
        case "Reading", "Heathrow Terminal 4", "Heathrow Terminal 5", "Maidenhead": via = "Ealing Broadway"
        default: return ""
        }
        // "Abbey Wood via Canary Wharf" reads wrong on the Canary
        // Wharf board itself — drop the via when it names the
        // station you are already at.
        guard via != stationName else { return "" }
        return "via \(via)"
    }

    // Seconds to station -> "arriving" (a minute or less, v1.14),
    // "1 min", "12 mins" (station-board style — the board never
    // shows seconds).
    static func minutesText(_ seconds: Int) -> String {
        if seconds <= 60 { return "arriving" }
        if seconds < 105 { return "1 min" }
        return "\(seconds / 60) mins"
    }

    // "2026-11-23T05:48:00Z" -> "05:48" (London time, 24-hour).
    // The Boards tab shows this next to the minutes, so the clock
    // time is right there on the board — no working it out.
    static func arrivalTimeText(_ iso: String?) -> String {
        guard let date = parseISODate(iso) else { return "" }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.locale = Locale(identifier: "en_GB")
        fmt.timeZone = londonTimeZone
        return fmt.string(from: date)
    }

    // TfL times are London wall-clock time. These formatters must use the
    // Europe/London timezone, not the device timezone: on a US device the
    // device zone (EST, UTC-5) shifts early-morning London times back to
    // the previous evening. (Same fix as the iPhone app, 17 Nov 2026.)
    static var londonTimeZone: TimeZone { TimeZone(identifier: "Europe/London") ?? .gmt }

    // "2026-12-19T12:00:00Z" -> Date (or nil)
    static func parseISODate(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        return ISO8601DateFormatter().date(from: iso)
    }

    // "2026-12-19T12:00:00Z" -> "Sat 19 Dec" (London time)
    static func dayTitle(_ iso: String?) -> String {
        guard let date = parseISODate(iso) else { return "Planned" }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE d MMM"
        fmt.locale = Locale(identifier: "en_GB")
        fmt.timeZone = londonTimeZone
        return fmt.string(from: date)
    }

    // "12:00 Sat 19 Dec – 11:59 Sun 20 Dec" (London time)
    static func timeRange(from: String?, to: String?) -> String {
        guard let fromDate = parseISODate(from) else { return "" }
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm"
        tf.locale = Locale(identifier: "en_GB")
        tf.timeZone = londonTimeZone
        let df = DateFormatter()
        df.dateFormat = "EEE d MMM"
        df.locale = Locale(identifier: "en_GB")
        df.timeZone = londonTimeZone
        var text = tf.string(from: fromDate) + " " + df.string(from: fromDate)
        if let toDate = parseISODate(to) {
            text += " – " + tf.string(from: toDate) + " " + df.string(from: toDate)
        }
        return text
    }

    // MARK: - Elizabeth line live map (v1.17)

    // One whole-line fetch, ~2,000 rows / ~140 trains. The old
    // trains stay on screen until a fresh fetch lands — a failed
    // refresh keeps the last positions and their Updated time
    // (same as the web map page). A cancelled fetch (the tab
    // closed under it) is not an error.
    @Published var positionedTrains: [PositionedTrain] = []
    @Published var isLoadingPositions = false
    @Published var positionsError: String?
    @Published var lastPositionsUpdate: Date?
    // The last fetch's trains, by vehicle, for the two history
    // cases in the positioning (see ElizabethLineMap).
    private var previousPositions: [String: PositionedTrain] = [:]

    func fetchElizabethLinePositions() async {
        if positionedTrains.isEmpty { isLoadingPositions = true }
        positionsError = nil
        let urlString = "https://api.tfl.gov.uk/Line/elizabeth/Arrivals"
        do {
            guard let url = URL(string: urlString) else { throw URLError(.badURL) }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let rows = try JSONDecoder().decode([Arrival].self, from: data)
            let trains = ElizabethLineMap.positionTrains(rows, previous: previousPositions)
            positionedTrains = trains
            previousPositions = Dictionary(uniqueKeysWithValues: trains.map { ($0.vehicleId, $0) })
            lastPositionsUpdate = Date()
        } catch {
            if !(error is CancellationError) {
                positionsError = "Could not fetch trains. (\(error.localizedDescription))"
            }
        }
        isLoadingPositions = false
    }
}

// MARK: - Elizabeth line live map (v1.17)

// The geometry and the positioning algorithm for the Live Map
// tab. Ports the research's positions.py (workspace/
// research_notes/elizabeth-live-map/, validated against live
// data 23 Nov 2026) — same ghost filter, same in-service rule,
// same segment-running-time medians, same edge cases. The
// station coordinates are the centres of the 25.2pt purple
// discs in the Nov 2024 TfL route map PDF, verified against
// the rendered map. Do not re-derive them by guessing.

/// One train positioned on the Elizabeth line diagram.
/// Coordinates are in TfL diagram points (the 3251.34 x
/// 793.701 page) — the view scales them to the screen.
/// Positions are ESTIMATED: the Elizabeth line feed never
/// reports where a train is, so the dot sits between its last
/// station and its next one, placed from the minutes to the
/// next stop.
struct PositionedTrain: Identifiable, Equatable {
    var id: String { vehicleId }
    let vehicleId: String
    let destination: String      // cleaned, e.g. "Shenfield"
    let direction: TrainDirection
    let nextStation: String
    let prevStation: String?     // nil when the dot sits at the next station
    let timeToStation: Int       // seconds to the next station
    let x: Double                // diagram points
    let y: Double

    var isEastbound: Bool { direction == .east }

    /// "Between Farringdon and Liverpool Street" / "At Liverpool Street".
    var segmentText: String {
        if let prev = prevStation {
            return "Between \(prev) and \(nextStation)"
        }
        return "At \(nextStation)"
    }

    /// "next stop Liverpool Street in ~2 min" / "arriving at Liverpool Street".
    var nextStopText: String {
        if timeToStation <= 60 { return "arriving at \(nextStation)" }
        return "next stop \(nextStation) in ~\(timeToStation / 60) min"
    }
}

enum TrainDirection: Equatable {
    case east, west
}

enum ElizabethLineMap {
    static let pageWidth: Double = 3251.34
    static let pageHeight: Double = 793.701

    /// Station -> (x, y) in diagram points. From stations.json
    /// in the research notes — the Nov 2024 TfL route map PDF.
    static let stations: [String: CGPoint] = [
        "Reading": CGPoint(x: 97.1, y: 278.9),
        "Twyford": CGPoint(x: 129.1, y: 311.1),
        "Maidenhead": CGPoint(x: 161.6, y: 344.4),
        "Taplow": CGPoint(x: 195.0, y: 378.0),
        "Burnham": CGPoint(x: 229.5, y: 412.5),
        "Slough": CGPoint(x: 263.3, y: 446.3),
        "Langley": CGPoint(x: 371.1, y: 478.2),
        "Iver": CGPoint(x: 441.2, y: 478.2),
        "West Drayton": CGPoint(x: 592.8, y: 478.2),
        "Hayes & Harlington": CGPoint(x: 776.2, y: 478.2),
        "Southall": CGPoint(x: 869.4, y: 478.2),
        "Hanwell": CGPoint(x: 943.2, y: 478.2),
        "West Ealing": CGPoint(x: 1023.3, y: 478.2),
        "Ealing Broadway": CGPoint(x: 1114.3, y: 478.2),
        "Acton Main Line": CGPoint(x: 1216.6, y: 478.2),
        "Paddington": CGPoint(x: 1325.3, y: 478.0),
        "Bond Street": CGPoint(x: 1449.2, y: 478.7),
        "Tottenham Court Road": CGPoint(x: 1571.8, y: 478.0),
        "Farringdon": CGPoint(x: 1693.1, y: 478.0),
        "Liverpool Street": CGPoint(x: 1816.2, y: 478.1),
        "Whitechapel": CGPoint(x: 1940.0, y: 478.1),
        "Stratford": CGPoint(x: 2086.2, y: 396.3),
        "Maryland": CGPoint(x: 2120.1, y: 362.3),
        "Forest Gate": CGPoint(x: 2216.7, y: 313.8),
        "Manor Park": CGPoint(x: 2312.9, y: 313.8),
        "Ilford": CGPoint(x: 2385.1, y: 313.8),
        "Seven Kings": CGPoint(x: 2453.3, y: 313.8),
        "Goodmayes": CGPoint(x: 2529.1, y: 313.8),
        "Chadwell Heath": CGPoint(x: 2637.9, y: 313.8),
        "Romford": CGPoint(x: 2741.7, y: 313.8),
        "Gidea Park": CGPoint(x: 2837.4, y: 313.8),
        "Harold Wood": CGPoint(x: 2918.6, y: 313.8),
        "Brentwood": CGPoint(x: 3019.5, y: 313.8),
        "Shenfield": CGPoint(x: 3134.0, y: 313.8),
        "Canary Wharf": CGPoint(x: 2286.6, y: 642.4),
        "Custom House": CGPoint(x: 2618.1, y: 642.4),
        "Woolwich": CGPoint(x: 2867.6, y: 642.4),
        "Abbey Wood": CGPoint(x: 3112.5, y: 642.2),
        "Terminal 5": CGPoint(x: 422.4, y: 623.6),
        "Terminal 4": CGPoint(x: 453.8, y: 693.7),
        "Terminals 2 & 3": CGPoint(x: 565.3, y: 582.3),
    ]

    /// The five chains, west to east / branch order. Stratford
    /// and West Drayton are the junctions; a train's full route
    /// is the main chain plus one branch.
    static let chains: [[String]] = [
        ["Reading", "Twyford", "Maidenhead", "Taplow", "Burnham", "Slough", "Langley", "Iver", "West Drayton", "Hayes & Harlington", "Southall", "Hanwell", "West Ealing", "Ealing Broadway", "Acton Main Line", "Paddington", "Bond Street", "Tottenham Court Road", "Farringdon", "Liverpool Street", "Whitechapel", "Stratford"],
        ["Stratford", "Maryland", "Forest Gate", "Manor Park", "Ilford", "Seven Kings", "Goodmayes", "Chadwell Heath", "Romford", "Gidea Park", "Harold Wood", "Brentwood", "Shenfield"],
        ["Stratford", "Canary Wharf", "Custom House", "Woolwich", "Abbey Wood"],
        ["Terminal 5", "Terminals 2 & 3", "West Drayton"],
        ["Terminal 4", "Terminals 2 & 3", "West Drayton"],
    ]

    /// Every station, in chain order (for stable ForEach).
    static let stationNames: [String] = {
        var seen: [String] = []
        for chain in chains {
            for name in chain where !seen.contains(name) {
                seen.append(name)
            }
        }
        return seen
    }()

    /// Neighbours on the full graph, both directions.
    static let neighbours: [String: Set<String>] = {
        var out: [String: Set<String>] = [:]
        for chain in chains {
            for (a, b) in zip(chain, chain.dropFirst()) {
                out[a, default: []].insert(b)
                out[b, default: []].insert(a)
            }
        }
        return out
    }()

    /// The feed's station and destination names, normalised
    /// the same way positions.py does: strip " Rail Station" /
    /// " Underground Station", a leading "London " or
    /// "Heathrow ", and " (Berks)" / " (London)". Returns nil
    /// for a station the diagram does not know, so an unknown
    /// row is skipped rather than placed wrong.
    static func normaliseName(_ raw: String) -> String? {
        var name = raw
        name = name.replacingOccurrences(of: " Rail Station", with: "")
        name = name.replacingOccurrences(of: " Underground Station", with: "")
        if name.hasPrefix("London ") { name = String(name.dropFirst("London ".count)) }
        if name.hasPrefix("Heathrow ") { name = String(name.dropFirst("Heathrow ".count)) }
        name = name.replacingOccurrences(of: " (Berks)", with: "")
        name = name.replacingOccurrences(of: " (London)", with: "")
        return stations[name] != nil ? name : nil
    }

    /// "Shenfield Rail Station" -> "Shenfield"; "Heathrow
    /// Terminal 4 Rail Station" -> "Terminal 4". Destinations
    /// are not all stations on the diagram (e.g. a train can
    /// terminate somewhere the map does not name), so there is
    /// no stations check here — direction() decides whether
    /// the destination is one the map can place.
    static func normaliseDestination(_ raw: String) -> String {
        var name = raw
        name = name.replacingOccurrences(of: " Rail Station", with: "")
        name = name.replacingOccurrences(of: " Underground Station", with: "")
        if name.hasPrefix("London ") { name = String(name.dropFirst("London ".count)) }
        if name.hasPrefix("Heathrow ") { name = String(name.dropFirst("Heathrow ".count)) }
        name = name.replacingOccurrences(of: " (Berks)", with: "")
        name = name.replacingOccurrences(of: " (London)", with: "")
        return name
    }

    static func direction(for destination: String) -> TrainDirection? {
        switch destination {
        case "Shenfield", "Abbey Wood", "Gidea Park": return .east
        case "Reading", "Maidenhead", "Terminal 4", "Terminal 5", "Paddington": return .west
        default: return nil
        }
    }

    // MARK: - Positioning

    /// One leg of the graph, keyed unordered — the running time
    /// is the same either way along it.
    private struct Leg: Hashable {
        let a: String
        let b: String
        init(_ x: String, _ y: String) {
            if x < y { a = x; b = y } else { a = y; b = x }
        }
    }

    /// The shortest station list from one station to another
    /// through the chain graph (BFS — 41 stations, trivial).
    /// Used both for the forward neighbour and for the
    /// interpolation polyline (a Heathrow train's leg from
    /// Terminals 2 & 3 to Hayes & Harlington runs through West
    /// Drayton, which the feed never lists).
    static func path(from: String, to: String) -> [String] {
        if from == to { return [from] }
        var visited: Set<String> = [from]
        var queue: [[String]] = [[from]]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            let last = current.last!
            for next in neighbours[last] ?? [] {
                if visited.contains(next) { continue }
                let extended = current + [next]
                if next == to { return extended }
                visited.insert(next)
                queue.append(extended)
            }
        }
        return [from, to]
    }

    /// "2026-11-23T05:48:00Z" -> Date (or nil). A local copy of
    /// TubeService.parseISODate: that one is main-actor-isolated
    /// (TubeService is @MainActor) and this runs in a synchronous
    /// nonisolated context, so it cannot call it.
    private static func parseISODate(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        return ISO8601DateFormatter().date(from: iso)
    }

    private static func median(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 240 }
        let sorted = values.sorted()
        if sorted.count % 2 == 1 { return sorted[sorted.count / 2] }
        return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
    }

    /// Position every in-service train from one whole-line
    /// Arrivals fetch. `previous` is the last fetch's trains by
    /// vehicle, for the two history cases below.
    static func positionTrains(_ rows: [Arrival], previous: [String: PositionedTrain]) -> [PositionedTrain] {
        // Group by vehicle; dedupe by station (min time to
        // station); ghost filter (same as the Boards tab).
        // The feed lists each train at every station it will
        // call at, each station twice (Tube + rail stop points)
        // — the normalisation collapses the pair.
        var perVehicle: [String: [String: (tts: Int, destination: String)]] = [:]
        for row in rows {
            guard !row.vehicleId.isEmpty, let tts = row.timeToStation else { continue }
            guard let station = normaliseName(row.stationName) else { continue }
            // Ghost filter: a placeholder row under five minutes
            // with no location whose prediction outlives its own
            // arrival by more than two minutes. Never drop on an
            // empty currentLocation alone — Elizabeth line rows
            // NEVER carry one.
            if tts < 300 && row.currentLocation.isEmpty {
                if let ttl = parseISODate(row.timeToLive),
                   let exp = parseISODate(row.expectedArrival) {
                    if ttl > exp.addingTimeInterval(120) { continue }
                } else {
                    continue
                }
            }
            let destination = normaliseDestination(row.destinationName)
            if let existing = perVehicle[row.vehicleId]?[station] {
                if tts < existing.tts {
                    perVehicle[row.vehicleId]?[station] = (tts, destination)
                }
            } else {
                perVehicle[row.vehicleId, default: [:]][station] = (tts, destination)
            }
        }

        // Segment running times, from the fetched data itself:
        // for each train, the time-to-station differences
        // between consecutive stops that are chain neighbours.
        // Median per leg, needing at least two samples (same
        // as positions.py); a leg with no data falls back to
        // 240 s at lookup time.
        var legSamples: [Leg: [Int]] = [:]
        for stops in perVehicle.values {
            let ordered = stops.sorted { $0.value.tts < $1.value.tts }
            for (first, second) in zip(ordered, ordered.dropFirst()) {
                if neighbours[first.key]?.contains(second.key) == true {
                    legSamples[Leg(first.key, second.key), default: []].append(second.value.tts - first.value.tts)
                }
            }
        }
        var legTimes: [Leg: Int] = [:]
        for (leg, samples) in legSamples where samples.count >= 2 {
            legTimes[leg] = median(samples)
        }
        func runningTime(_ a: String, _ b: String) -> Int {
            legTimes[Leg(a, b)] ?? 240
        }

        let mainChain = chains[0]
        let shenfieldBranch = Set(chains[1].dropFirst())
        let abbeyWoodBranch = Set(chains[2].dropFirst())
        let heathrowStations = Set(["Terminal 4", "Terminal 5", "Terminals 2 & 3"])

        var out: [PositionedTrain] = []
        for (vehicleId, stops) in perVehicle {
            let ordered = stops.sorted { $0.value.tts < $1.value.tts }
            guard let (next, first) = ordered.first else { continue }
            // In service only: a train whose next arrival is
            // more than 30 minutes away is a future service
            // sitting at a terminus.
            guard first.tts <= 1800 else { continue }
            guard let direction = direction(for: first.destination) else { continue }

            // The neighbour on the far side of the next station
            // — the side the train is heading toward. Found from
            // the chain graph, not the feed's sparse list: the
            // feed skips stops (an Abbey Wood train's list jumps
            // Canary Wharf -> Whitechapel with no Stratford row).
            let forwardPath = path(from: next, to: first.destination)
            let forwardNeighbour = forwardPath.count >= 2 ? forwardPath[1] : nil
            var prevCandidates = neighbours[next] ?? []
            if let forwardNeighbour { prevCandidates.remove(forwardNeighbour) }

            var prev: String?
            if prevCandidates.count == 1 {
                prev = prevCandidates.first
            } else if prevCandidates.count > 1 {
                // The train came from one side only. Eastbound it
                // came from the west (the main-chain neighbour
                // with the lowest index); westbound from the east
                // (the highest index). A candidate off the main
                // chain (Maryland, Canary Wharf) only counts when
                // it is the only one.
                let onMain = prevCandidates.compactMap { c -> (String, Int)? in
                    guard let i = mainChain.firstIndex(of: c) else { return nil }
                    return (c, i)
                }
                if direction == .east {
                    prev = onMain.min(by: { $0.1 < $1.1 })?.0
                } else {
                    prev = onMain.max(by: { $0.1 < $1.1 })?.0
                }
            }
            // History, for the two genuinely ambiguous cases.
            // Stratford heading west: Maryland or Canary Wharf —
            // the branch the train was last seen on decides.
            // Hayes & Harlington heading east: West Drayton by
            // default, Terminals 2 & 3 when the train came down
            // the Heathrow branch. Terminals 2 & 3 heading east:
            // Terminal 4 or Terminal 5, whichever it came from.
            if prev == nil, let prior = previous[vehicleId] {
                if next == "Stratford" && direction == .west {
                    if let p = prior.prevStation, shenfieldBranch.contains(p) { prev = "Maryland" }
                    else if let p = prior.prevStation, abbeyWoodBranch.contains(p) { prev = "Canary Wharf" }
                    else if shenfieldBranch.contains(prior.nextStation) { prev = "Maryland" }
                    else if abbeyWoodBranch.contains(prior.nextStation) { prev = "Canary Wharf" }
                } else if next == "Hayes & Harlington" && direction == .east {
                    if let p = prior.prevStation, heathrowStations.contains(p) { prev = "Terminals 2 & 3" }
                    else if heathrowStations.contains(prior.nextStation) { prev = "Terminals 2 & 3" }
                } else if next == "Terminals 2 & 3" && direction == .east {
                    if prior.prevStation == "Terminal 5" || prior.nextStation == "Terminal 5" { prev = "Terminal 5" }
                    else if prior.prevStation == "Terminal 4" || prior.nextStation == "Terminal 4" { prev = "Terminal 4" }
                }
            }

            // Where the dot goes: interpolate along the polyline
            // from the previous station to the next one, through
            // any intermediate chain stations. Fraction =
            // clamp(1 - timeToStation / R, 0, 1), where R is the
            // running time for the leg (summed over the polyline
            // legs when the leg is not direct). No previous
            // station: the dot sits at the next station.
            let point: CGPoint
            if let prev, let prevPoint = stations[prev], let nextPoint = stations[next] {
                let polyline = path(from: prev, to: next)
                var total: Double = 0
                var legs: [(CGPoint, CGPoint, Double)] = []
                for (a, b) in zip(polyline, polyline.dropFirst()) {
                    guard let pa = stations[a], let pb = stations[b] else { continue }
                    let dx = Double(pb.x - pa.x)
                    let dy = Double(pb.y - pa.y)
                    let len = (dx * dx + dy * dy).squareRoot()
                    legs.append((pa, pb, len))
                    total += len
                }
                let r = zip(polyline, polyline.dropFirst()).reduce(0) { $0 + runningTime($1.0, $1.1) }
                let frac = total > 0 ? max(0, min(1, 1 - Double(first.tts) / Double(r))) : 1
                var distance = frac * total
                var placed = nextPoint
                for (pa, pb, len) in legs {
                    if distance <= len {
                        let t = len > 0 ? distance / len : 0
                        placed = CGPoint(x: pa.x + (pb.x - pa.x) * CGFloat(t), y: pa.y + (pb.y - pa.y) * CGFloat(t))
                        break
                    }
                    distance -= len
                    placed = pb
                }
                _ = prevPoint
                point = placed
            } else if let nextPoint = stations[next] {
                point = nextPoint
            } else {
                continue
            }

            out.append(PositionedTrain(
                vehicleId: vehicleId,
                destination: first.destination,
                direction: direction,
                nextStation: next,
                prevStation: prev,
                timeToStation: first.tts,
                x: Double(point.x),
                y: Double(point.y)
            ))
        }
        return out.sorted { $0.vehicleId < $1.vehicleId }
    }
}
