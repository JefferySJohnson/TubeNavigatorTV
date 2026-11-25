import Foundation
import CoreLocation
import WeatherKit
import SwiftUI

// WeatherKit weather for TubeNavigatorTV.
// The Apple TV has no user location to use, so the weather is always
// for Paddington — the hotel, 4 North Wharf Road — at 51.5166, -0.1765.
// Requires the WeatherKit capability on the App ID
// (com.rolltide.TubeNavigatorTV, explicit App ID — a wildcard App ID
// cannot carry WeatherKit) and the com.apple.developer.weatherkit
// entitlement. No API key; 500,000 calls/month are included in the
// Developer Program. Apple requires the "Data from Apple Weather"
// attribution in the UI.

@MainActor
final class WeatherViewModel: ObservableObject {
    @Published var current: CurrentWeather?
    @Published var todayHigh: Measurement<UnitTemperature>?
    @Published var todayLow: Measurement<UnitTemperature>?
    // v1.8: the seven-day forecast for the strip under the weather
    // strip — it comes back in the same WeatherKit call, so no new
    // setup was needed.
    @Published var forecast: [DayWeather] = []
    // v1.16: next 12 hours, for the Hours forecast view.
    @Published var hourly: [HourWeather] = []
    @Published var errorMessage: String?
    @Published var isLoading = false

    // The hotel. (The iPhone app uses the same fallback when the phone's
    // location is unavailable.)
    private let paddington = CLLocation(latitude: 51.5166, longitude: -0.1765)
    private var didStart = false

    func load() {
        guard !didStart else { return }
        didStart = true
        Task { await fetch() }
    }

    func refresh() async {
        await fetch()
    }

    private func fetch() async {
        isLoading = true
        do {
            let weather = try await WeatherService.shared.weather(for: paddington)
            current = weather.currentWeather
            let today = weather.dailyForecast.first
            todayHigh = today?.highTemperature
            todayLow = today?.lowTemperature
            forecast = Array(weather.dailyForecast.prefix(7))
            // v1.16: the hourly forecast for the tappable weather
            // strip — the same WeatherKit call, just kept now.
            // Sorted and filtered to the current hour onward: the
            // forecast's order isn't guaranteed, and stale hours
            // must not show.
            let nowHour = Calendar.current.date(bySetting: .minute, value: 0, of: Date()) ?? Date()
            hourly = Array(weather.hourlyForecast
                .filter { $0.date >= nowHour }
                .sorted { $0.date < $1.date }
                .prefix(12))
            errorMessage = nil
        } catch {
            errorMessage = "Weather isn't available right now."
        }
        isLoading = false
    }

    func tempF(_ measurement: Measurement<UnitTemperature>?) -> String {
        guard let measurement else { return "—" }
        return "\(Int(measurement.converted(to: .fahrenheit).value.rounded()))°"
    }

    // Short weekday for a forecast day ("Mon", "Tue" …) in London time.
    func weekdayShort(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE"
        fmt.locale = Locale(identifier: "en_GB")
        fmt.timeZone = TimeZone(identifier: "Europe/London")
        return fmt.string(from: date)
    }

    // Short hour for an hourly-forecast column ("9", "14") and a
    // short clock time for sunrise/sunset ("07:48", "15:51") —
    // 24-hour, like the boards' arrival times. London time.
    func hourShort(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "H"
        fmt.locale = Locale(identifier: "en_GB")
        fmt.timeZone = TimeZone(identifier: "Europe/London")
        return fmt.string(from: date)
    }

    func timeShort(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.locale = Locale(identifier: "en_GB")
        fmt.timeZone = TimeZone(identifier: "Europe/London")
        return fmt.string(from: date)
    }

    // A clock time, or "—" when the date is missing — sunrise and
    // sunset are Date? on DayWeather's sun.
    func timeShortOrDash(_ date: Date?) -> String {
        guard let date else { return "—" }
        return timeShort(date)
    }

    func conditionText(_ condition: WeatherCondition) -> String {
        switch condition {
        case .clear: return "Clear"
        case .cloudy: return "Cloudy"
        case .mostlyClear: return "Mostly clear"
        case .mostlyCloudy: return "Mostly cloudy"
        case .partlyCloudy: return "Partly cloudy"
        case .rain: return "Rain"
        case .heavyRain: return "Heavy rain"
        case .drizzle: return "Drizzle"
        case .snow: return "Snow"
        case .heavySnow: return "Heavy snow"
        case .sleet: return "Sleet"
        case .hail: return "Hail"
        case .thunderstorms: return "Thunderstorms"
        case .isolatedThunderstorms: return "Isolated thunderstorms"
        case .scatteredThunderstorms: return "Scattered thunderstorms"
        case .strongStorms: return "Strong storms"
        case .foggy: return "Foggy"
        case .haze: return "Haze"
        case .windy: return "Windy"
        case .blizzard: return "Blizzard"
        case .blowingDust: return "Blowing dust"
        case .freezingDrizzle: return "Freezing drizzle"
        case .freezingRain: return "Freezing rain"
        case .hurricane: return "Hurricane"
        case .tropicalStorm: return "Tropical storm"
        case .sunFlurries: return "Sun flurries"
        case .sunShowers: return "Sun showers"
        case .wintryMix: return "Wintry mix"
        default: return "—"
        }
    }
}
