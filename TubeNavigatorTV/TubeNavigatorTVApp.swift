import SwiftUI

// TubeNavigatorTV — a Tube status board for the Apple TV.
// Status tab: London weather on top, then Tube/DLR/Elizabeth line
// status with the disruption messages in full. Planned tab: dated
// disruptions for the next 7 days or the Dec 15–24, 2026 trip.

@main
struct TubeNavigatorTVApp: App {
    @StateObject private var service = TubeService()
    @StateObject private var weather = WeatherViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(service)
                .environmentObject(weather)
        }
    }
}
