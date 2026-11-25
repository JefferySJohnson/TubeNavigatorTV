import SwiftUI
import WeatherKit
import AVKit
import AVFoundation
import UIKit

// TubeNavigatorTV — a status board for the Apple TV.
// Seven tabs: Status (London weather on top, then one button per
// line — name, status colour and status name — tap a button for the
// full detail), Planned (dated disruptions for the next 7 days or
// the Dec 15–24 trip), Live (TfL traffic cameras — a short clip
// per camera, refreshed every few minutes), Map (the Tube
// diagram — focus a line button to light that line up on the map,
// with its status below), Boards (departure boards — pick a
// station, pick a line, and the next trains both ways, like the
// boards in the station), Live Map (the Elizabeth line redrawn
// as a schematic with a live dot per train — focus a dot for its
// details, Select to pin it), and Settings (themes and the forecast
// toggle, with the version). No journey planning — the telly is
// for glancing at, not planning on.
//
// v1.4: smaller again — one more step down in type, tighter row
// padding, a narrower centred grid, and a smaller weather strip.
// The focus pill hugs the button, so a narrower button means a
// smaller pill: the grid is capped at 900pt and centred, instead of
// spanning the full screen width.
// v1.5: v1.4 went too far — the type got too small, the centred grid
// pushed Bakerloo right and Central left, and the narrow columns
// truncated "Hammersmith & City", "Reduced Service" and other long
// names. So the type is back to v1.3 sizes and the grid is full-width
// again, but each BUTTON is capped and left-aligned in its
// column: the pill hugs the button, not the column, so it is much
// smaller while Bakerloo stays at the left edge and Central stays
// in the middle.
// v1.6: the 520pt cap was too narrow — the long names still shrank
// and truncated. 720pt gives them room at full size.
// v1.7: the Planned tab gets the same treatment — one step down in
// type everywhere (day headers, card titles, reason text, range
// buttons), tighter padding and spacing, and the grey fill behind
// the range buttons is gone (same no-fill direction as v1.3).
// v1.8: Settings — a gear button on the Status tab opens a full
// screen (icon + version on the left, settings on the right) with a
// theme picker and a 7-day forecast toggle; the forecast strip and
// weather condition icons come from the same WeatherKit call; and
// the footer row is one step smaller on both tabs. Themes are dark
// schemes only — the white focus pill is drawn by tvOS and can't be
// recoloured, so a light theme would hide it.
// v1.9: a Live tab — six central TfL traffic cameras (JamCams), each
// a short clip refreshed every few minutes, played with the native
// VideoPlayer. The clips are 352x288, so they are soft on a big TV,
// and they are not a continuous stream — the detail says so plainly.
// v1.10: a Map tab — the Tube diagram (September 2026 TfL map,
// cropped to the diagram, bundled as a picture), with the thirteen
// line buttons beside it. Focusing a button lights that line up on
// the map — the line's path, extracted once from the map PDF by its
// colour, drawn thick over a dimmed map — and the status panel under
// the buttons shows the line's live status. The diagram is static;
// the status is live.
// v1.11: Settings becomes a tab (gear icon, last in the tab bar),
// so the "⚙ Settings" row leaves the Status tab and the Back
// button leaves Settings. The version text comes off the tab
// footers — it already lives in Settings — and Refresh moves to a
// centred header row at the top of each tab with the Updated time,
// so the footer rows go away entirely. And a Boards tab:
// departure boards from TfL's live arrivals feed — pick a station
// (Paddington first, then the other stations Jeffery uses), pick a
// line there, and the next trains by platform, both directions,
// refreshed every 30 seconds.
// v1.17: a Live Map tab — the Elizabeth line redrawn as a native
// SwiftUI schematic (Jeffery said the TfL picture does not have
// to be kept exactly, as long as it stays recognisably the
// Elizabeth line map), with a live dot per train in service.
// The dots are focusable buttons: focus one and the strip below
// shows where it is going and when it gets there; Select pins
// it. Positions are estimated from the minutes to each train's
// next stop — the Elizabeth line feed never says where a train
// is — and the tab says so plainly.
//
// tvOS notes: the remote moves focus, it does not tap. Every button
// and card has .focusable() so the list scrolls when you move down
// it, and the type is big enough to read from the couch. The classic
// .tabItem API is used (not the tvOS 18 Tab syntax) so the app runs
// on tvOS 17+.

// MARK: - Theme (v1.8)

// Dark schemes only. The white focus pill is drawn by tvOS and
// cannot be recoloured, so a light theme would make the pill nearly
// invisible on a white background. Midnight is the current black
// look, so nothing changes until a theme is picked. Stored in
// UserDefaults under "TubeNavigatorTV.theme"; every view reads the
// same key with @AppStorage.
enum AppTheme: String, CaseIterable, Identifiable {
    case midnight, navy, oxblood, forest

    var id: String { rawValue }

    var name: String {
        switch self {
        case .midnight: return "Midnight"
        case .navy: return "Tube Navy"
        case .oxblood: return "Oxblood"
        case .forest: return "Forest"
        }
    }

    var background: Color {
        switch self {
        case .midnight: return .black
        case .navy: return Color(red: 0.02, green: 0.07, blue: 0.16)
        case .oxblood: return Color(red: 0.16, green: 0.03, blue: 0.05)
        case .forest: return Color(red: 0.03, green: 0.12, blue: 0.07)
        }
    }

    var swatch: Color {
        switch self {
        case .midnight: return Color(white: 0.30)
        case .navy: return Color(red: 0.10, green: 0.25, blue: 0.55)
        case .oxblood: return Color(red: 0.55, green: 0.10, blue: 0.12)
        case .forest: return Color(red: 0.10, green: 0.45, blue: 0.25)
        }
    }

    static func from(_ raw: String) -> AppTheme { AppTheme(rawValue: raw) ?? .midnight }
}

// MARK: - Arrival sound (v1.14)

// The chime played once when a train on the open board first drops
// to a minute or less. Three short sounds bundled as data assets in
// Assets.xcassets (ArrivalBong / ArrivalChime / ArrivalBell); the
// choice and the on/off toggle live in Settings.
enum ArrivalSound: String, CaseIterable, Identifiable {
    case bong, chime, bell

    var id: String { rawValue }

    var name: String {
        switch self {
        case .bong: return "Bong"
        case .chime: return "Chime"
        case .bell: return "Bell"
        }
    }

    var assetName: String { "Arrival" + name }

    static func from(_ raw: String) -> ArrivalSound { ArrivalSound(rawValue: raw) ?? .bong }
}

/// "TubeNavigatorTV vX.Y (B)" from the bundle — shown on the
/// Settings screen.
func appVersionText() -> String {
    let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    return "TubeNavigatorTV v\(short) (\(build))"
}

// v1.11: the header row every tab shares — Refresh + Updated,
// centred, at the top. The footer rows are gone (the version lives
// in Settings now), so this is where Refresh lives. Centred, like
// the Planned range buttons, so Down from the tab bar lands on it.
// v1.13: the title (when a tab has one) sits on the left, and
// Updated + Refresh sit at the upper right — the centred row wasted
// a line of height and the middle of the screen. Tabs without a
// title pass none and just get the right-aligned controls. One
// caution from v1.8: the remote has skipped small corner buttons
// before (the gear in the weather strip), so whether Down from the
// tab bar still lands on Refresh needs checking on the simulator.
struct RefreshHeaderRow: View {
    let updated: Date?
    let title: String?
    let action: () -> Void

    init(updated: Date?, title: String? = nil, action: @escaping () -> Void) {
        self.updated = updated
        self.title = title
        self.action = action
    }

    var body: some View {
        HStack(spacing: 32) {
            if let title {
                Text(title)
                    .font(.title)
                    .fontWeight(.bold)
            }
            Spacer()
            if let updated {
                Text("Updated \(shortTime(updated))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button(action: action) {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.subheadline)
            }
        }
    }

    private func shortTime(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.locale = Locale(identifier: "en_GB")
        return fmt.string(from: date)
    }
}

struct ContentView: View {
    @EnvironmentObject var service: TubeService
    @EnvironmentObject var weather: WeatherViewModel
    @AppStorage("TubeNavigatorTV.theme") private var themeRaw = AppTheme.midnight.rawValue

    var body: some View {
        ZStack {
            AppTheme.from(themeRaw).background.ignoresSafeArea()
            TabView {
                StatusView()
                    .tabItem { Label("Status", systemImage: "info.circle") }
                PlannedView()
                    .tabItem { Label("Planned", systemImage: "calendar") }
                LiveView()
                    .tabItem { Label("Live", systemImage: "video.fill") }
                MapView()
                    .tabItem { Label("Map", systemImage: "map.fill") }
                BoardsView()
                    .tabItem { Label("Boards", systemImage: "list.bullet") }
                LiveMapView()
                    .tabItem { Label("Live Map", systemImage: "train.side.front.car") }
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            }
        }
        // v1.14: the app is dark-only — the theme backgrounds are
        // fixed dark, but the lettering follows the system, and
        // when the TV's appearance switched the text came out black
        // on a black background (Midnight, 23 Nov 2026). Forcing
        // dark keeps the text white whatever the system is set to,
        // so the system setting stops mattering for this app. The
        // white focus pill is untouched (focused text already goes
        // black on it, v1.3).
        .preferredColorScheme(.dark)
    }
}

// MARK: - Status tab

struct StatusView: View {
    @EnvironmentObject var service: TubeService
    @EnvironmentObject var weather: WeatherViewModel
    // Which line button has focus — used to darken its status word,
    // which otherwise washes out on the white focus pill (v1.3).
    @FocusState private var focusedLine: String?
    @AppStorage("TubeNavigatorTV.theme") private var themeRaw = AppTheme.midnight.rawValue
    // v1.8: whether the forecast strip shows under the weather
    // strip. On by default; the toggle lives in Settings. (v1.16:
    // the toggle reads "Show forecast" — it hides the whole cycler,
    // not just the 7-day view.)
    @AppStorage("TubeNavigatorTV.showForecast") private var showForecast = true
    // v1.16: which forecast the strip shows — tapping the strip
    // cycles sevenDay → hours → today. Persisted, so the preferred
    // view sticks across launches.
    @AppStorage("TubeNavigatorTV.forecastMode") private var forecastModeRaw = ForecastMode.sevenDay.rawValue
    private var forecastMode: ForecastMode {
        get { ForecastMode(rawValue: forecastModeRaw) ?? .sevenDay }
        nonmutating set { forecastModeRaw = newValue.rawValue }
    }

    // v1.16: the forecast views the weather strip cycles through.
    enum ForecastMode: String, CaseIterable {
        case sevenDay, hours, today
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                // v1.11: Refresh lives up here now, in a centred row
                // with the Updated time — the footer row is gone, and
                // the version lives in Settings. Down from the tab
                // bar lands on this row (centred, like the Planned
                // range buttons).
                RefreshHeaderRow(updated: service.lastStatusUpdate) {
                    Task {
                        await service.fetchLineStatus()
                        await weather.refresh()
                    }
                }
                // Weather strip — London, big, at the top.
                weatherStrip
                // Line status.
                if service.isLoadingStatus && service.lineStatuses.isEmpty {
                    ProgressView("Checking the Tube…")
                        .font(.title2)
                } else if let error = service.statusError, service.lineStatuses.isEmpty {
                    Text(error)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .focusable()
                } else {
                    // One button per line, two columns — all thirteen
                    // fit on one screen. Tap a button for the full
                    // detail (v1.2: this replaces the long scrolling
                    // list of full-message cards).
                    // v1.5: the grid is full-width again (v1.4's
                    // centred 900pt grid pushed Bakerloo right and
                    // Central left, and truncated long names), but
                    // each button is capped and left-aligned
                    // in its column — the pill hugs the button, not
                    // the column, so it is much smaller.
                    // v1.6: the cap is 720pt, not 520pt — 520 still
                    // shrank and truncated the long names.
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], alignment: .leading, spacing: 10) {
                        ForEach(service.lineStatuses) { line in
                            NavigationLink(value: line.id) {
                                lineButton(line, isFocused: focusedLine == line.id)
                            }
                            .buttonStyle(.plain)
                            .focused($focusedLine, equals: line.id)
                            .frame(maxWidth: 720, alignment: .leading)
                        }
                    }
                }
            }
            .padding(36)
        }
        .background(AppTheme.from(themeRaw).background)
        .navigationDestination(for: String.self) { lineId in
            if let line = service.lineStatuses.first(where: { $0.id == lineId }) {
                LineDetailView(line: line)
            }
        }
        .task {
            weather.load()
            await service.fetchLineStatus()
        }
        }
    }

    private var weatherStrip: some View {
        // v1.3: smaller — the 96pt temperature hogged the top third.
        // 64pt is still big from the couch and frees nearly a row.
        // v1.4 shrank it to 48pt; v1.5 puts it back to 64pt — v1.4
        // was too small overall.
        // v1.8: the condition gets its WeatherKit icon, and the
        // 7-day forecast strip sits underneath when the Settings
        // toggle is on. (v1.8 also put a gear button at the top
        // right for Settings; the remote's focus skipped it
        // entirely — Down from the tab bar went straight to
        // Central — and the centred row below the strip that
        // replaced it went away in v1.11, when Settings became a
        // tab of its own.) The strip itself is not .focusable() —
        // it holds no interactive element, and the grid buttons
        // handle scrolling.
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 40) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("London")
                        .font(.title)
                        .fontWeight(.bold)
                    if let current = weather.current {
                        HStack(spacing: 10) {
                            Image(systemName: current.symbolName)
                                .font(.title2)
                            Text(weather.conditionText(current.condition))
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                    } else if let error = weather.errorMessage {
                        Text(error)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Checking the weather…")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    Text("Data from Apple Weather")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    if let current = weather.current {
                        Text(weather.tempF(current.temperature))
                            .font(.system(size: 64, weight: .bold))
                    } else {
                        Text("—°")
                            .font(.system(size: 64, weight: .bold))
                    }
                    Text("H \(weather.tempF(weather.todayHigh))  ·  L \(weather.tempF(weather.todayLow))")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            if showForecast, !weather.forecast.isEmpty {
                forecastButton
            }
        }
    }

    // v1.16: the forecast row is a button — tapping it cycles the
    // view (7 days → hours → today). Only the forecast row is
    // tappable, not the whole weather strip: a focus pill around
    // the entire strip would be one giant white block.
    private var forecastButton: some View {
        Button {
            cycleForecastMode()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                forecastContent
                Text(forecastHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var forecastContent: some View {
        switch forecastMode {
        case .sevenDay:
            forecastStrip
        case .hours:
            hoursStrip
        case .today:
            todayStrip
        }
    }

    private func cycleForecastMode() {
        let all = ForecastMode.allCases
        let index = (all.firstIndex(of: forecastMode) ?? 0) + 1
        forecastMode = all[index % all.count]
    }

    private var forecastHint: String {
        switch forecastMode {
        case .sevenDay: return "Tap for hours"
        case .hours: return "Tap for today"
        case .today: return "Tap for 7 days"
        }
    }

    private var forecastStrip: some View {
        // v1.8: seven days from WeatherKit's dailyForecast — the same
        // call that already feeds the strip, so no new setup. One
        // compact row: day, icon, high/low.
        HStack(spacing: 36) {
            ForEach(weather.forecast, id: \.date) { day in
                VStack(spacing: 6) {
                    Text(weather.weekdayShort(day.date))
                        .font(.headline)
                    Image(systemName: day.symbolName)
                        .font(.title2)
                    Text("\(weather.tempF(day.highTemperature)) / \(weather.tempF(day.lowTemperature))")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 8)
    }

    private var hoursStrip: some View {
        // v1.16: the next 12 hours — hour (London time), icon, temp.
        HStack(spacing: 24) {
            ForEach(weather.hourly, id: \.date) { hour in
                VStack(spacing: 6) {
                    Text(weather.hourShort(hour.date))
                        .font(.headline)
                    Image(systemName: hour.symbolName)
                        .font(.title2)
                    Text(weather.tempF(hour.temperature))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var todayStrip: some View {
        // v1.16: today on its own — condition, high/low, rain
        // chance, sunrise/sunset (London time, 24-hour). The
        // strings are computed first — the nested interpolation
        // in one expression was too much for the type-checker.
        if let today = weather.forecast.first {
            let condition = weather.conditionText(today.condition)
            let highLow = "H \(weather.tempF(today.highTemperature)) / L \(weather.tempF(today.lowTemperature))"
            let rain = "Rain \(Int(today.precipitationChance * 100))%"
            let sunrise = "Sunrise \(weather.timeShortOrDash(today.sun.sunrise))"
            let sunset = "Sunset \(weather.timeShortOrDash(today.sun.sunset))"
            HStack(spacing: 36) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Image(systemName: today.symbolName)
                            .font(.title2)
                        Text(condition)
                            .font(.headline)
                    }
                    Text("Today")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(highLow)
                        .font(.headline)
                    Text(rain)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(sunrise)
                        .font(.headline)
                    Text(sunset)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
        }
    }

    private func lineButton(_ line: TfLLine, isFocused: Bool) -> some View {
        let status = line.lineStatuses.first
        let severity = status?.statusSeverityDescription ?? "—"
        let isGood = severity == "Good Service"
        // Single line — name left, status right — so all thirteen
        // buttons fit on one screen. The two-line version only fit
        // three and a half rows.
        // v1.3: one step down in type (name .title2 → .title3, status
        // .title3 → .headline), a smaller dot, and no fill — the rows
        // are just text on the dark background now, so the grid reads
        // as a list instead of a wall of grey boxes. The focused
        // button's status word goes black: green/orange on the white
        // focus pill washed out.
        // v1.4 went one step further (.headline / .subheadline) and
        // v1.5 reverts that — the type is back to v1.3 sizes. The
        // tighter vertical padding (4pt, from v1.4) stays: it makes
        // the focus pill shorter.
        return HStack(spacing: 16) {
            Circle()
                .fill(TubeLines.color(for: line.id))
                .frame(width: 24, height: 24)
                // The Northern line's dot is black — the ring keeps it
                // visible against the dark background.
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1.5))
            Text(line.name)
                .font(.title3)
                .fontWeight(.bold)
                // Long names (Hammersmith & City, Elizabeth line) must
                // stay on one line — a wrapped name makes its row
                // taller and the grid no longer fits on one screen.
                // 0.6, not 0.8: 0.8 still truncated Hammersmith & City.
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer()
            Text(severity)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(isFocused ? .black : (isGood ? .green : .orange))
                // The longest status ("Reduced Service") wrapped onto
                // two lines next to the longest name — keep it on one.
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
}

// MARK: - Line detail (from a Status button)

struct LineDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("TubeNavigatorTV.theme") private var themeRaw = AppTheme.midnight.rawValue
    let line: TfLLine

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    Circle()
                        .fill(TubeLines.color(for: line.id))
                        .frame(width: 32, height: 32)
                        .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1.5))
                    Text(line.name)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Spacer()
                    Text(severity)
                        .font(.title)
                        .fontWeight(.semibold)
                        .foregroundStyle(isGood ? .green : .orange)
                }
                if let reason = line.lineStatuses.first?.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("No further detail from TfL right now.")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                // A way back that can take focus: without a focusable
                // element the detail holds no focus, and the remote's
                // Menu button exits the app instead of going back.
                Button {
                    dismiss()
                } label: {
                    Label("Back to all lines", systemImage: "chevron.left")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(48)
        }
        .background(AppTheme.from(themeRaw).background)
    }

    private var severity: String {
        line.lineStatuses.first?.statusSeverityDescription ?? "—"
    }

    private var isGood: Bool {
        severity == "Good Service"
    }
}

// MARK: - Planned tab

struct PlannedView: View {
    @EnvironmentObject var service: TubeService
    @AppStorage("TubeNavigatorTV.theme") private var themeRaw = AppTheme.midnight.rawValue

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                // v1.11: Refresh + Updated live up here now (see
                // RefreshHeaderRow) — the footer row is gone.
                RefreshHeaderRow(updated: service.lastPlannedUpdate) {
                    Task { await service.fetchPlanned() }
                }
                // Range switch — two buttons in a centred row, not a Picker.
                // v1.0 used a segmented Picker here, but inside this
                // ScrollView + LazyVStack the tvOS focus engine skipped it
                // entirely: Down from the tab bar went straight to the
                // first card, Up from the card never came back, and taps
                // did not select it, so the range could not be changed at
                // all. Buttons always take focus, and the row is centred
                // so Down from the tab bar lands on it.
                // v1.7: smaller buttons (.headline, tighter padding) and
                // the grey container fill is gone (same no-fill direction
                // as v1.3's Status buttons) — the selected button still
                // gets its own highlight, so the active range is clear.
                HStack {
                    Spacer()
                    HStack(spacing: 8) {
                        ForEach(PlannedRange.allCases) { range in
                            Button {
                                service.plannedRange = range
                                Task { await service.fetchPlanned() }
                            } label: {
                                Text(range.rawValue)
                                    .font(.headline)
                                    .fontWeight(service.plannedRange == range ? .semibold : .regular)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 24)
                                    .background(service.plannedRange == range ? Color.white.opacity(0.22) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Spacer()
                }

                if service.isLoadingPlanned && service.plannedItems.isEmpty {
                    ProgressView("Checking planned works…")
                        .font(.title3)
                } else if let error = service.plannedError, service.plannedItems.isEmpty {
                    Text(error)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .focusable()
                } else if service.plannedItems.isEmpty {
                    Text("No planned disruptions in this range — good news.")
                        .font(.title3)
                        .focusable()
                } else {
                    ForEach(groupedDays, id: \.self) { day in
                        daySection(day)
                    }
                }
            }
            .padding(48)
        }
        .background(AppTheme.from(themeRaw).background)
        .task {
            await service.fetchPlanned()
        }
    }

    private var groupedDays: [String] {
        var seen: [String] = []
        for item in service.plannedItems {
            let day = TubeService.dayTitle(item.fromDate)
            if !seen.contains(day) { seen.append(day) }
        }
        return seen
    }

    private func daySection(_ day: String) -> some View {
        // v1.7: one step down in type everywhere (day .title → .title2,
        // card titles .title2 → .title3, time + reason .title3 →
        // .headline) and tighter padding/spacing, so the cards read
        // cleaner and more fits on screen.
        VStack(alignment: .leading, spacing: 12) {
            Text(day)
                .font(.title2)
                .fontWeight(.bold)
            ForEach(service.plannedItems.filter { TubeService.dayTitle($0.fromDate) == day }) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Text(item.displayLines)
                            .font(.title3)
                            .fontWeight(.bold)
                        Spacer()
                        Text(item.severity)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(.orange)
                    }
                    Text(TubeService.timeRange(from: item.fromDate, to: item.toDate))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(item.reason)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .focusable()
            }
        }
    }
}

// MARK: - Live tab (v1.9)

// TfL traffic cameras (JamCams): six central ones, each a short
// clip refreshed every few minutes. The list comes from the same
// TfL API as the rest of the app (fetchCameras, in TubeService);
// the rows show the camera's still image as a thumbnail, and
// tapping one plays the clip in CameraDetailView.
struct LiveView: View {
    @EnvironmentObject var service: TubeService
    @AppStorage("TubeNavigatorTV.theme") private var themeRaw = AppTheme.midnight.rawValue

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // v1.11: Refresh + Updated live up here now.
                    RefreshHeaderRow(updated: service.lastCamerasUpdate) {
                        Task { await service.fetchCameras() }
                    }
                    Text("Live views")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("TfL traffic cameras — a short clip, refreshed every few minutes. Tap a camera to watch it.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    if service.isLoadingCameras && service.cameras.isEmpty {
                        Text("Finding the cameras…")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    } else if let error = service.camerasError, service.cameras.isEmpty {
                        Text(error)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(service.cameras) { camera in
                            NavigationLink(destination: CameraDetailView(camera: camera)) {
                                cameraRow(camera)
                            }
                            .buttonStyle(.plain)
                            .disabled(!camera.available)
                        }
                    }
                }
                .padding(48)
            }
            .background(AppTheme.from(themeRaw).background)
            .task {
                if service.cameras.isEmpty {
                    await service.fetchCameras()
                }
            }
        }
    }

    private func cameraRow(_ camera: JamCam) -> some View {
        HStack(spacing: 24) {
            // The still is 352x288, the clip's native size — shown
            // as-is rather than upscaled into a blur.
            AsyncImage(url: URL(string: camera.imageUrl)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color.white.opacity(0.08)
                }
            }
            .frame(width: 352, height: 288)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 8) {
                Text(camera.name)
                    .font(.title2)
                    .fontWeight(.bold)
                Text(camera.view)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                if camera.available {
                    Text("Tap to watch")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Unavailable right now")
                        .font(.headline)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
        }
        .opacity(camera.available ? 1 : 0.5)
    }
}

struct CameraDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("TubeNavigatorTV.theme") private var themeRaw = AppTheme.midnight.rawValue
    let camera: JamCam
    @State private var player: AVPlayer?
    @State private var loopObserver: NSObjectProtocol?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(camera.name)
                .font(.largeTitle)
                .fontWeight(.bold)
            Text(camera.view)
                .font(.title3)
                .foregroundStyle(.secondary)
            if let player {
                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text("A short clip, refreshed every few minutes — not a continuous stream.")
                .font(.headline)
                .foregroundStyle(.secondary)
            // A way back that can take focus: without a focusable
            // element the detail holds no focus, and the remote's
            // Menu button exits the app instead of going back.
            Button {
                dismiss()
            } label: {
                Label("Back to live views", systemImage: "chevron.left")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(48)
        .background(AppTheme.from(themeRaw).background)
        .onAppear {
            guard player == nil, let url = URL(string: camera.videoUrl) else { return }
            let newPlayer = AVPlayer(url: url)
            // The clip is about 11 seconds — loop it so the view
            // keeps moving instead of freezing on the last frame.
            loopObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: newPlayer.currentItem,
                queue: .main
            ) { _ in
                print("[CameraDetail] clip ended — looping")
                newPlayer.seek(to: .zero)
                newPlayer.play()
            }
            player = newPlayer
            newPlayer.play()
            // Debug (v1.9): log the playback state a few seconds in,
            // so a frozen clip can be diagnosed from the console
            // instead of guessed at from screenshots.
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                let status = newPlayer.timeControlStatus.rawValue
                let time = newPlayer.currentTime().seconds
                let itemStatus = newPlayer.currentItem?.status.rawValue ?? -1
                let itemError = String(describing: newPlayer.currentItem?.error)
                print("[CameraDetail] timeControlStatus=\(status) (0 paused, 1 waiting, 2 playing) time=\(time) itemStatus=\(itemStatus) (0 unknown, 1 ready, 2 failed) error=\(itemError)")
            }
        }
        .onDisappear {
            player?.pause()
            if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
            self.loopObserver = nil
        }
    }
}

// MARK: - Map tab (v1.10)

// The Tube diagram with one line lit up at a time.
//
// The geometry comes from TfL's standard map PDF (September 2026
// edition), extracted once with extract_map_lines.py: each of the 13
// lines is 1-9 continuous paths in its own exact colour. The points
// are stored in the MapLines data asset as JSON, in crop-relative
// coordinates — the bundled map picture is the same PDF page cropped
// to x[25-1015], y[95-775] (990 x 680), so a point (x, y) in the JSON
// is (x, y) on the picture. The picture itself (TubeMap imageset,
// 1x + 2x) is just the diagram — no header, legend or ads.
//
// Interaction, as Jeffery asked: the map sits on the left, the
// thirteen line buttons on the right. Focusing a button lights that
// line up on the map (the rest of the map dims, the line is drawn
// thick in its own colour over a white under-stroke) and the status
// panel under the buttons shows the line's live status — the same
// TfL call the Status tab makes. Nothing on the map itself takes
// focus, so Down from the tab bar lands straight on the buttons.
struct MapLinePaths {
    static let mapWidth: CGFloat = 990
    static let mapHeight: CGFloat = 680

    /// Line display name → paths → points, from the MapLines data
    /// asset. Empty when the asset is missing, so the tab still
    /// shows the map and the buttons.
    static let shared: [String: [[CGPoint]]] = {
        guard let asset = NSDataAsset(name: "MapLines"),
              let raw = try? JSONDecoder().decode([String: [[[Double]]]].self, from: asset.data) else {
            return [:]
        }
        var out: [String: [[CGPoint]]] = [:]
        for (name, paths) in raw {
            out[name] = paths.map { path in
                path.compactMap { pair in
                    guard pair.count == 2 else { return nil }
                    return CGPoint(x: pair[0], y: pair[1])
                }
            }
        }
        return out
    }()
}

struct MapView: View {
    @EnvironmentObject var service: TubeService
    @AppStorage("TubeNavigatorTV.theme") private var themeRaw = AppTheme.midnight.rawValue
    // The focused line button — drives the highlight and the panel.
    @FocusState private var focusedLine: String?
    // The line the panel shows. Set from focus; nil until a button
    // is focused, so the map starts plain with a hint.
    @State private var selectedLineId: String?

    // The map picture is 990 x 680 (aspect 1.456). At 1150 wide it
    // is 790 tall, which leaves room for the title and the header
    // row with the right column beside it.
    private let mapDisplayWidth: CGFloat = 1150

    private var mapScale: CGFloat { mapDisplayWidth / MapLinePaths.mapWidth }
    private var mapDisplayHeight: CGFloat { MapLinePaths.mapHeight * mapScale }

    // The thirteen lines, in the Status tab's order. From the live
    // statuses when loaded; the static list keeps the tab working
    // before the first fetch (or if it fails).
    private var rows: [(id: String, name: String)] {
        if !service.lineStatuses.isEmpty {
            return service.lineStatuses.map { ($0.id, $0.name) }
        }
        return Self.fallbackRows
    }

    private static let fallbackRows: [(id: String, name: String)] = [
        ("bakerloo", "Bakerloo"), ("central", "Central"), ("circle", "Circle"),
        ("dlr", "DLR"), ("district", "District"), ("elizabeth", "Elizabeth line"),
        ("hammersmith-city", "Hammersmith & City"), ("jubilee", "Jubilee"),
        ("metropolitan", "Metropolitan"), ("northern", "Northern"),
        ("piccadilly", "Piccadilly"), ("victoria", "Victoria"),
        ("waterloo-city", "Waterloo & City"),
    ]

    private var selectedRow: (id: String, name: String)? {
        guard let id = selectedLineId else { return nil }
        return rows.first { $0.id == id }
    }

    private var selectedStatus: TfLLine? {
        guard let id = selectedLineId else { return nil }
        return service.lineStatuses.first { $0.id == id }
    }

    private var statusSeverity: String {
        selectedStatus?.lineStatuses.first?.statusSeverityDescription ?? "—"
    }

    private var statusIsGood: Bool {
        statusSeverity == "Good Service"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // v1.11: Refresh + Updated live up here now — the
                // footer row is gone (which also retires the
                // below-the-fold footer this tab had in v1.10).
                RefreshHeaderRow(updated: service.lastStatusUpdate) {
                    Task { await service.fetchLineStatus() }
                }
                Text("Tube map")
                    .font(.title)
                    .fontWeight(.bold)
                HStack(alignment: .top, spacing: 32) {
                    mapPicture
                    rightColumn
                }
            }
            .padding(36)
        }
        .background(AppTheme.from(themeRaw).background)
        .task {
            await service.fetchLineStatus()
        }
        .onChange(of: focusedLine) { _, newValue in
            selectedLineId = newValue
        }
    }

    private var mapPicture: some View {
        ZStack {
            Image("TubeMap")
                .resizable()
                .aspectRatio(contentMode: .fit)
            if let row = selectedRow {
                Color.black.opacity(0.45)
                let path = highlightPath(for: row.name)
                path.stroke(Color.white, style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
                path.stroke(TubeLines.color(for: row.id), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: mapDisplayWidth, height: mapDisplayHeight)
    }

    private func highlightPath(for lineName: String) -> Path {
        var path = Path()
        for subpath in MapLinePaths.shared[lineName] ?? [] {
            guard let first = subpath.first else { continue }
            path.move(to: CGPoint(x: first.x * mapScale, y: first.y * mapScale))
            for point in subpath.dropFirst() {
                path.addLine(to: CGPoint(x: point.x * mapScale, y: point.y * mapScale))
            }
        }
        return path
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Two columns of line buttons, then the status panel
            // underneath — so the panel is on screen while you
            // browse the lines. The grid needs the column's explicit
            // 666pt width: without it the flexible columns collapsed
            // to ~240pt inside the ScrollView and truncated
            // "Hammersmith & City" and "Waterloo & City".
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], alignment: .leading, spacing: 8) {
                ForEach(rows, id: \.id) { row in
                    Button {
                        selectedLineId = row.id
                    } label: {
                        mapLineButton(row)
                    }
                    .buttonStyle(.plain)
                    .focused($focusedLine, equals: row.id)
                }
            }
            statusPanel
        }
        // Explicit width: without it the column sizes to its
        // content and the grid collapsed (see above). 1848 (content
        // width) - 1150 (map) - 32 (spacing) = 666.
        .frame(width: 666, alignment: .leading)
    }

    private func mapLineButton(_ row: (id: String, name: String)) -> some View {
        // Dot + name only — the status word lives in the panel
        // below, and the two-column grid has no room for it next
        // to the longest names.
        HStack(spacing: 12) {
            Circle()
                .fill(TubeLines.color(for: row.id))
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1.5))
            Text(row.name)
                .font(.title3)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let row = selectedRow {
                HStack(spacing: 12) {
                    Circle()
                        .fill(TubeLines.color(for: row.id))
                        .frame(width: 28, height: 28)
                        .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1.5))
                    Text(row.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    Spacer()
                    if selectedStatus != nil {
                        Text(statusSeverity)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(statusIsGood ? .green : .orange)
                    }
                }
                if let status = selectedStatus {
                    if let reason = status.lineStatuses.first?.reason, !reason.isEmpty {
                        Text(reason)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("No further detail from TfL right now.")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Status not loaded yet — try Refresh above.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Move to a line to light it up on the map.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Boards tab (v1.11)

// Departure boards from TfL's live arrivals feed — the same
// countdown data as the boards in the station. Pick a station,
// pick a line there, and the next trains by platform, both
// directions, refreshed every 30 seconds while the tab is open.
//
// The feed: GET /Line/{lineId}/Arrivals/{stopPointId} — one call
// per line (see TubeService.fetchArrivals). Paddington's Elizabeth
// line platforms answer to a different stop point (910GPADTON, the
// rail station) than its Tube platforms (940GZZLUPAC). The stations
// are the ones Jeffery uses, with their TfL ids and lines from the
// iPhone app's StationData. Mainline trains (GWR, Heathrow
// Express) are not in this feed — Tube, Elizabeth line and DLR
// only.
// MARK: - Boards tab (v1.14: two screens)

// Screen one: the station picker, full screen — room for many more
// stations than the old 2×3 grid, so adding stations no longer means
// shrinking the text. Each row shows the station name (one step down
// in type from the old grid) and the coloured dots for the lines that
// serve it. Tapping a station pushes its board.
struct BoardsView: View {
    @AppStorage("TubeNavigatorTV.theme") private var themeRaw = AppTheme.midnight.rawValue

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Departure boards")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(TubeService.boardStations) { station in
                            NavigationLink(value: station) {
                                HStack(spacing: 16) {
                                    Text(station.name)
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                        .lineLimit(1)
                                    Spacer()
                                    HStack(spacing: 8) {
                                        ForEach(station.lines, id: \.self) { id in
                                            Circle()
                                                .fill(TubeLines.color(for: id))
                                                .frame(width: 16, height: 16)
                                                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
                                        }
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.headline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 24)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(48)
            }
            .background(AppTheme.from(themeRaw).background)
            .navigationDestination(for: BoardStation.self) { station in
                StationBoardView(station: station)
            }
        }
    }
}

// Screen two: one station's board, full screen. The lines across the
// top, then the trains underneath — destination (+ "via" on the
// Elizabeth line) left, minutes and London clock time right, the
// train's current location in secondary text (Tube lines only — the
// Elizabeth line feed carries none). Five trains per platform now
// that the pickers live on their own screen. The board re-fetches
// every 30 seconds while it is open, and a soft chime sounds once
// when a train first drops to a minute or less (Settings can turn
// it off or change it).
struct StationBoardView: View {
    @EnvironmentObject var service: TubeService
    @AppStorage("TubeNavigatorTV.theme") private var themeRaw = AppTheme.midnight.rawValue
    @AppStorage("TubeNavigatorTV.arrivalSoundEnabled") private var soundEnabled = true
    @AppStorage("TubeNavigatorTV.arrivalSound") private var soundName = ArrivalSound.bong.rawValue

    let station: BoardStation
    @State private var lineId: String
    // The trains that have already bonged (by vehicleId), so the
    // chime fires once per train, not once per refresh. Seeded from
    // the first fetch — a train already under a minute when the board
    // opens does NOT bong; only trains that cross into "arriving"
    // while the board is open do.
    @State private var bonged: Set<String> = []
    @State private var seeded = false
    @State private var player: AVAudioPlayer?
    // v1.16: which station the board last loaded for — see the task.
    @State private var loadedStationId: String?
    // v1.16: which line button holds focus — focus IS the selection.
    @FocusState private var focusedLine: String?

    init(station: BoardStation) {
        self.station = station
        _lineId = State(initialValue: station.lines[0])
    }

    var body: some View {
        // v1.16: the header (station + Refresh) and the line row are
        // pinned at the top — only the trains scroll. Before this,
        // the whole screen scrolled, so Down from the line row walked
        // a blank path through the non-focusable rows and the lines
        // scrolled away with it. No Back button (v1.15): the remote's
        // Menu button already returns to the picker, and the line
        // buttons hold focus on their own.
        VStack(alignment: .leading, spacing: 12) {
            RefreshHeaderRow(updated: service.lastArrivalsUpdate, title: station.name) {
                Task { await service.fetchArrivals(station: station, lineId: lineId) }
            }
            lineRow
            ScrollView {
                board
            }
        }
        // v1.14: the board is indented in from both sides, so the
        // destination and the minutes/time sit closer together
        // instead of stretched across the whole screen.
        .padding(.horizontal, 120)
        .padding(.vertical, 20)
        .background(AppTheme.from(themeRaw).background)
        // The task restarts whenever the line changes — the old fetch
        // loop is cancelled and the new line's trains load — and it
        // re-fetches every 30 seconds while the board is open, like
        // the station board.
        .task(id: "\(station.id)|\(lineId)") {
            // v1.16: clear the board only when the station changes.
            // A line change keeps the old trains until the new fetch
            // lands — otherwise every Left/Right press (focus-driven
            // switching) flashes "Checking trains…".
            if loadedStationId != station.id {
                service.arrivals = []
                loadedStationId = station.id
            }
            bonged = []
            seeded = false
            await service.fetchArrivals(station: station, lineId: lineId)
            seedBonged()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                await service.fetchArrivals(station: station, lineId: lineId)
                if !seeded {
                    seedBonged()
                } else {
                    checkArrivals()
                }
            }
        }
    }

    private func seedBonged() {
        // Mark the trains already at a minute or less as seen, without
        // sounding — the chime is only for trains that arrive while
        // the board is open. Only seed once the fetch has actually
        // returned trains, so a failed first load doesn't arm the
        // chime for trains that were already there.
        guard !service.arrivals.isEmpty else { return }
        bonged = Set(service.arrivals.compactMap { train in
            guard let tts = train.timeToStation, tts <= 60, !train.vehicleId.isEmpty else { return nil }
            return train.vehicleId
        })
        seeded = true
    }

    private func checkArrivals() {
        guard soundEnabled, seeded else { return }
        let newly = service.arrivals.filter { train in
            guard let tts = train.timeToStation, tts <= 60, !train.vehicleId.isEmpty else { return false }
            return !bonged.contains(train.vehicleId)
        }
        guard !newly.isEmpty else { return }
        for train in newly { bonged.insert(train.vehicleId) }
        playArrivalSound()
    }

    private func playArrivalSound() {
        guard let data = NSDataAsset(name: ArrivalSound.from(soundName).assetName)?.data else { return }
        do {
            player = try AVAudioPlayer(data: data)
            player?.volume = 0.5
            player?.play()
        } catch {
            // A missing or broken sound must not break the board.
        }
    }

    private var lineRow: some View {
        HStack(spacing: 8) {
            ForEach(station.lines, id: \.self) { id in
                lineButton(id)
            }
        }
        // v1.16: focus IS the selection — moving the pill onto a
        // line switches the board, no Select needed. The task
        // restarts on lineId and fetches the new line; the old
        // trains stay until it lands.
        .onChange(of: focusedLine) { _, new in
            if let new, new != lineId { lineId = new }
        }
    }

    // v1.16: one line button, extracted so the compiler can
    // type-check it on its own — the ForEach + Button + label in
    // a single expression was too much for it.
    private func lineButton(_ id: String) -> some View {
        Button {
            lineId = id
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(TubeLines.color(for: id))
                    .frame(width: 20, height: 20)
                    .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1.5))
                Text(lineName(id))
                    .font(.title3)
                    .fontWeight(lineId == id ? .semibold : .regular)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 24)
            .background(lineId == id ? Color.white.opacity(0.22) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        // v1.16: the button reports its focus into focusedLine;
        // the row's onChange switches the board. (There is no
        // .onFocusChange modifier in SwiftUI — the compiler says
        // so — so this is @FocusState + .focused + .onChange.)
        .focused($focusedLine, equals: id)
    }

    // The line's display name. From the live statuses when loaded;
    // the static names keep the picker working before the first
    // fetch (or if it fails).
    private func lineName(_ id: String) -> String {
        if let line = service.lineStatuses.first(where: { $0.id == id }) {
            return line.name
        }
        return [
            "bakerloo": "Bakerloo", "central": "Central", "circle": "Circle",
            "district": "District", "dlr": "DLR", "elizabeth": "Elizabeth line",
            "hammersmith-city": "Hammersmith & City", "jubilee": "Jubilee",
            "metropolitan": "Metropolitan", "northern": "Northern",
            "piccadilly": "Piccadilly", "victoria": "Victoria",
            "waterloo-city": "Waterloo & City",
        ][id] ?? id
    }

    // One section per platform, in alphabetical platform order
    // (v1.16) — A always on top at Paddington. The platform with
    // the soonest train used to lead, which made A and B swap on
    // every refresh. Five trains per platform: the board has the
    // full screen to itself now (v1.13's four was the fit for the
    // shared screen).
    private var sections: [(platform: String, trains: [Arrival])] {
        var order: [String] = []
        var byPlatform: [String: [Arrival]] = [:]
        for train in service.arrivals {
            if byPlatform[train.platformName] == nil {
                order.append(train.platformName)
                byPlatform[train.platformName] = []
            }
            byPlatform[train.platformName]?.append(train)
        }
        // v1.16: alphabetical platform order — A always on top.
        return order.map { (platform: $0, trains: Array((byPlatform[$0] ?? []).prefix(5))) }
            .sorted { $0.platform < $1.platform }
    }

    private var board: some View {
        VStack(alignment: .leading, spacing: 12) {
            if service.isLoadingArrivals && service.arrivals.isEmpty {
                Text("Checking trains…")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            } else if let error = service.arrivalsError, service.arrivals.isEmpty {
                Text(error)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .focusable()
            } else if service.arrivals.isEmpty {
                Text("No trains due right now.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .focusable()
            } else {
                ForEach(sections, id: \.platform) { section in
                    platformSection(section)
                }
            }
        }
    }

    private func platformSection(_ section: (platform: String, trains: [Arrival])) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(section.platform)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
            ForEach(section.trains) { train in
                trainRow(train)
            }
        }
    }

    private func trainRow(_ train: Arrival) -> some View {
        let via = TubeService.viaText(for: train.destinationName, lineId: train.lineId, stationName: station.name)
        let arrival = TubeService.arrivalTimeText(train.expectedArrival)
        return HStack(spacing: 16) {
            Text(TubeService.cleanDestination(train.destinationName))
                .font(.headline)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if !via.isEmpty {
                Text(via)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !train.currentLocation.isEmpty {
                Text(train.currentLocation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(TubeService.minutesText(train.timeToStation ?? 0))
                .font(.headline)
                .fontWeight(.semibold)
            if !arrival.isEmpty {
                Text(arrival)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .focusable()
    }
}

// MARK: - Live Map tab (v1.17)

// The Elizabeth line, redrawn as a native SwiftUI schematic
// with a live dot per train — the web live-map page, on the
// TV. The geometry is the TfL diagram's own station
// coordinates (ElizabethLineMap.stations, from the Nov 2024
// route map PDF); the line is drawn as a path through the
// five chains in Elizabeth purple, station dots for all 41
// stations, labels for the major ones. Train dots are red
// eastbound, blue westbound (same as the web page), placed
// from the minutes to each train's next stop — estimated,
// because the Elizabeth line feed never says where a train
// is, and the tab says so. Each dot is a focusable button:
// focusing a train shows its details in the strip below
// (destination, the stretch it is on, next stop and
// minutes); Select pins it. Refresh every 30 seconds while
// the tab is open, keeping the old trains until a fresh
// fetch lands.
struct LiveMapView: View {
    @EnvironmentObject var service: TubeService
    @AppStorage("TubeNavigatorTV.theme") private var themeRaw = AppTheme.midnight.rawValue
    // Which train dot holds focus — drives the detail strip
    // when nothing is pinned. Which train Select pinned.
    @FocusState private var focusedTrain: String?
    @State private var pinnedTrain: String?

    // The diagram is 3251.34 x 793.701 points (~4:1). At full
    // content width it is ~450 tall, leaving room for the
    // header and the detail strip.
    private let mapDisplayWidth: CGFloat = 1848
    private var scale: CGFloat { mapDisplayWidth / ElizabethLineMap.pageWidth }
    private var mapDisplayHeight: CGFloat { ElizabethLineMap.pageHeight * scale }

    private static let eastboundColor = Color(red: 0.95, green: 0.30, blue: 0.25)
    private static let westboundColor = Color(red: 0.25, green: 0.55, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            RefreshHeaderRow(updated: service.lastPositionsUpdate, title: "Elizabeth line live map") {
                Task { await service.fetchElizabethLinePositions() }
            }
            mapView
            detailStrip
            Text("Train positions are estimated from TfL arrival times — the Elizabeth line doesn't report where its trains are, so each dot is placed between stations from the minutes to its next stop.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(36)
        .background(AppTheme.from(themeRaw).background)
        .task {
            await service.fetchElizabethLinePositions()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                await service.fetchElizabethLinePositions()
            }
        }
        // A pinned train that has left the line (arrived,
        // terminated) drops its pin rather than pointing at a
        // train that is no longer there.
        .onChange(of: service.positionedTrains) { _, trains in
            if let pinned = pinnedTrain, !trains.contains(where: { $0.vehicleId == pinned }) {
                pinnedTrain = nil
            }
        }
    }

    // The train the strip shows: the pinned one when there is
    // one, otherwise the focused one.
    private var displayedTrain: PositionedTrain? {
        if let pinned = pinnedTrain,
           let train = service.positionedTrains.first(where: { $0.vehicleId == pinned }) {
            return train
        }
        if let focused = focusedTrain {
            return service.positionedTrains.first(where: { $0.vehicleId == focused })
        }
        return nil
    }

    private func togglePin(_ train: PositionedTrain) {
        // Select pins the focused train; Select again on the
        // same train releases it. Select on another train
        // re-pins to that one.
        pinnedTrain = (pinnedTrain == train.vehicleId) ? nil : train.vehicleId
    }

    private var mapView: some View {
        ZStack {
            // The line, white under-stroke then Elizabeth
            // purple — the same treatment as the Map tab's
            // highlight, so it reads on every theme.
            linePath.stroke(Color.white, style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
            linePath.stroke(TubeLines.color(for: "elizabeth"), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
            // Station dots for all 41 stations.
            ForEach(ElizabethLineMap.stationNames, id: \.self) { name in
                if let point = ElizabethLineMap.stations[name] {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(TubeLines.color(for: "elizabeth"), lineWidth: 2))
                        .position(x: point.x * scale, y: point.y * scale)
                }
            }
            // Labels for the major stations only — the diagram
            // is too dense to name all 41 at TV size.
            ForEach(Self.labels, id: \.name) { label in
                if let point = ElizabethLineMap.stations[label.name] {
                    Text(label.display)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(AppTheme.from(themeRaw).background.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .position(x: point.x * scale, y: labelY(point, label))
                }
            }
            // One focusable dot per train in service.
            ForEach(service.positionedTrains) { train in
                Button {
                    togglePin(train)
                } label: {
                    Circle()
                        .fill(train.isEastbound ? Self.eastboundColor : Self.westboundColor)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                        .overlay(
                            // A pinned train gets a second ring.
                            Circle().stroke(Color.white, lineWidth: 2)
                                .frame(width: 34, height: 34)
                                .opacity(pinnedTrain == train.vehicleId ? 1 : 0)
                        )
                }
                .buttonStyle(.plain)
                .frame(width: 34, height: 34)
                .focused($focusedTrain, equals: train.vehicleId)
                .position(x: train.x * scale, y: train.y * scale)
            }
        }
        .frame(width: mapDisplayWidth, height: mapDisplayHeight)
    }

    private var linePath: Path {
        var path = Path()
        for chain in ElizabethLineMap.chains {
            var points: [CGPoint] = []
            for name in chain {
                if let point = ElizabethLineMap.stations[name] {
                    points.append(CGPoint(x: point.x * scale, y: point.y * scale))
                }
            }
            guard let first = points.first else { continue }
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
        return path
    }

    // A label's vertical position: above or below its station
    // dot, row 0 close in, row 1 further out. Row 1 is what
    // keeps "Tottenham Court Road" clear of "Paddington" and
    // "Liverpool Street" in the dense central stretch.
    private func labelY(_ point: CGPoint, _ label: LiveMapLabel) -> CGFloat {
        let offset: CGFloat = label.row == 0 ? 36 : 68
        return point.y * scale + (label.side == .above ? -offset : offset)
    }

    private struct LiveMapLabel {
        enum Side { case above, below }
        let name: String
        let display: String
        let side: Side
        let row: Int
    }

    // "Terminals 2 & 3" is deliberately unlabelled — its dot
    // sits between the Terminal 4 and Terminal 5 labels, and
    // there is no room for a third Heathrow label without one
    // of them colliding.
    private static let labels: [LiveMapLabel] = [
        LiveMapLabel(name: "Reading", display: "Reading", side: .above, row: 0),
        LiveMapLabel(name: "Maidenhead", display: "Maidenhead", side: .below, row: 0),
        LiveMapLabel(name: "Slough", display: "Slough", side: .above, row: 0),
        LiveMapLabel(name: "Hayes & Harlington", display: "Hayes & Harlington", side: .above, row: 0),
        LiveMapLabel(name: "Ealing Broadway", display: "Ealing Broadway", side: .below, row: 0),
        LiveMapLabel(name: "Paddington", display: "Paddington", side: .above, row: 0),
        LiveMapLabel(name: "Bond Street", display: "Bond Street", side: .below, row: 0),
        LiveMapLabel(name: "Tottenham Court Road", display: "Tottenham Court Road", side: .above, row: 1),
        LiveMapLabel(name: "Farringdon", display: "Farringdon", side: .below, row: 1),
        LiveMapLabel(name: "Liverpool Street", display: "Liverpool Street", side: .above, row: 0),
        LiveMapLabel(name: "Whitechapel", display: "Whitechapel", side: .below, row: 0),
        LiveMapLabel(name: "Stratford", display: "Stratford", side: .above, row: 0),
        LiveMapLabel(name: "Shenfield", display: "Shenfield", side: .above, row: 0),
        LiveMapLabel(name: "Canary Wharf", display: "Canary Wharf", side: .above, row: 0),
        LiveMapLabel(name: "Woolwich", display: "Woolwich", side: .below, row: 0),
        LiveMapLabel(name: "Abbey Wood", display: "Abbey Wood", side: .above, row: 0),
        LiveMapLabel(name: "Terminal 5", display: "Terminal 5", side: .above, row: 0),
        LiveMapLabel(name: "Terminal 4", display: "Terminal 4", side: .below, row: 0),
    ]

    // Two lines when a train is shown: destination + next stop
    // on the first, the stretch it is on underneath. One line
    // held all three and the segment and next-stop texts ran
    // off the right edge (seen on the simulator 23 Nov 2026).
    private var detailStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let train = displayedTrain {
                HStack(spacing: 16) {
                    Circle()
                        .fill(train.isEastbound ? Self.eastboundColor : Self.westboundColor)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    Text("To \(train.destination)")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text(train.nextStopText)
                        .font(.title3)
                        .fontWeight(.semibold)
                    if pinnedTrain == train.vehicleId {
                        Text("Pinned")
                            .font(.headline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.22))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Spacer()
                }
                Text(train.segmentText)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            } else if service.isLoadingPositions && service.positionedTrains.isEmpty {
                Text("Checking trains…")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            } else if let error = service.positionsError, service.positionedTrains.isEmpty {
                Text(error)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .focusable()
            } else {
                Text("\(service.positionedTrains.count) trains on the line — move to a train to see its details.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 100, alignment: .leading)
    }
}

// MARK: - Settings (v1.8)

// A full screen, and since v1.11 a tab of its own (gear icon, last
// in the tab bar) — no longer pushed from the Status tab, so no
// Back button: there is nothing to go back from. Two columns, as
// Jeffery laid it out — the left has the app icon with the build
// version under it, the right has the settings.
struct SettingsView: View {
    @AppStorage("TubeNavigatorTV.theme") private var themeRaw = AppTheme.midnight.rawValue
    @AppStorage("TubeNavigatorTV.showForecast") private var showForecast = true
    @AppStorage("TubeNavigatorTV.arrivalSoundEnabled") private var soundEnabled = true
    @AppStorage("TubeNavigatorTV.arrivalSound") private var soundName = ArrivalSound.bong.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("Settings")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                HStack(alignment: .top, spacing: 96) {
                    // Left: the icon and the facts about the app.
                    VStack(alignment: .leading, spacing: 16) {
                        RoundelIcon()
                            .frame(width: 160, height: 160)
                        Text(appVersionText())
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("Line status: Transport for London")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Weather: Apple WeatherKit")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Data from Apple Weather")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    // Right: the settings.
                    VStack(alignment: .leading, spacing: 28) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Theme")
                                .font(.title2)
                                .fontWeight(.bold)
                            ForEach(AppTheme.allCases) { theme in
                                Button {
                                    themeRaw = theme.rawValue
                                } label: {
                                    HStack(spacing: 16) {
                                        Circle()
                                            .fill(theme.swatch)
                                            .frame(width: 28, height: 28)
                                        Text(theme.name)
                                            .font(.title3)
                                        if AppTheme.from(themeRaw) == theme {
                                            Image(systemName: "checkmark")
                                                .font(.title3)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            Text("Dark schemes only — the white focus pill is drawn by tvOS and can't be recoloured, so a light theme would hide it.")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Weather")
                                .font(.title2)
                                .fontWeight(.bold)
                            Toggle("Show forecast", isOn: $showForecast)
                                .font(.title3)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Sound")
                                .font(.title2)
                                .fontWeight(.bold)
                            Toggle("Arrival sound", isOn: $soundEnabled)
                                .font(.title3)
                            ForEach(ArrivalSound.allCases) { sound in
                                Button {
                                    soundName = sound.rawValue
                                } label: {
                                    HStack(spacing: 16) {
                                        Text(sound.name)
                                            .font(.title3)
                                        if ArrivalSound.from(soundName) == sound {
                                            Image(systemName: "checkmark")
                                                .font(.title3)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(!soundEnabled)
                                .opacity(soundEnabled ? 1.0 : 0.5)
                            }
                            Text("A soft chime when a train on the open board first drops to a minute or less. It never sounds when you first open a board.")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(48)
        }
        .background(AppTheme.from(themeRaw).background)
    }
}

// The Jeff roundel, drawn in SwiftUI — red ring, blue bar, JEFF —
// the same mark as the app icon. The ring is drawn last so it covers
// the bar's ends, the way the real roundel's bar stops at the ring.
struct RoundelIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(red: 0.0, green: 0.10, blue: 0.66))
                .frame(width: 150, height: 48)
            Text("JEFF")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
            Circle()
                .stroke(Color(red: 0.86, green: 0.14, blue: 0.12), lineWidth: 16)
        }
    }
}

