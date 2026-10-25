import SwiftUI

/// Live local date and weather, with sample task and lifestyle cards.
struct BriefingView: View {
    @State private var weatherModel = BriefingWeatherViewModel()
    private let accent = Color(red: 1, green: 0.18, blue: 0.45)
    private let ink = Color(red: 0.16, green: 0.13, blue: 0.15)
    private let green = Color(red: 0.10, green: 0.69, blue: 0.43)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                weatherCard
                weatherAttribution

                card {
                    BriefingRow(symbol: "calendar", color: .blue,
                                title: "Design review", detail: "10:30 AM · Studio B", trailing: "45 min")
                    BriefingRow(symbol: "envelope", color: accent,
                                title: "2 priority emails", detail: "Ana needs contract approval", trailing: "Review")
                    BriefingRow(symbol: "checkmark.circle", color: green,
                                title: "4 tasks today", detail: "Prep deck is due at 10:00", trailing: "1 due")
                }

                card {
                    BriefingRow(symbol: "headphones", color: accent,
                                title: "Continue Sunday Slowdown", detail: "Living room · 18 min left", trailing: "Play")
                    BriefingRow(symbol: "shippingbox", color: .orange,
                                title: "Coffee delivery", detail: "Arriving 11:15–11:45 AM", trailing: "Track")
                    BriefingRow(symbol: "heart.text.square", color: green,
                                title: "Wellness check", detail: "7h 42m sleep · Recovery looks good", trailing: "82%")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .task { await weatherModel.refresh() }
        .refreshable { await weatherModel.refresh() }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.97, green: 0.96, blue: 0.97))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 4) {
                    Text(dateSubtitle(for: context.date))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accent)
                    Text(briefingTitle(for: context.date))
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(ink)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        }
        .padding(.bottom, 2)
    }

    private func dateSubtitle(for date: Date) -> String {
        let style = Date.FormatStyle(
            locale: .autoupdatingCurrent,
            calendar: .autoupdatingCurrent,
            timeZone: .autoupdatingCurrent
        )
        let weekday = date.formatted(style.weekday(.wide))
        let monthAndDay = date.formatted(style.month(.abbreviated).day())
        return "\(weekday) · \(monthAndDay)".uppercased(with: .autoupdatingCurrent)
    }

    private func briefingTitle(for date: Date) -> String {
        switch Calendar.autoupdatingCurrent.component(.hour, from: date) {
        case 0..<12: "Your morning"
        case 12..<18: "Your afternoon"
        default: "Your evening"
        }
    }

    private var weatherCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(weatherModel.weather?.locationName ?? "Local weather")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(weatherModel.temperatureText(weatherModel.weather?.temperature))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .fontWidth(.expanded)
                    Text(weatherModel.weather?.condition ?? (weatherModel.isLoading ? "Loading weather…" : "Weather unavailable"))
                        .font(.headline.weight(.regular))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Group {
                    if weatherModel.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: weatherModel.weather?.symbolName ?? "cloud")
                            .font(.system(size: 34, weight: .ultraLight))
                    }
                }
                .frame(width: 76, height: 76)
                .background(.white.opacity(0.13), in: Circle())
                .accessibilityHidden(true)
            }

            if let message = weatherModel.errorMessage {
                Text(message).font(.subheadline)
                Button("Try again") { Task { await weatherModel.refresh() } }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .disabled(weatherModel.isLoading)
            } else {
                Text("Rest of today (est.) · High \(weatherModel.temperatureText(weatherModel.weather?.high)) · Low \(weatherModel.temperatureText(weatherModel.weather?.low))")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.top, 4)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.92, green: 0.24, blue: 0.49), in: RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder
    private var weatherAttribution: some View {
        if let weather = weatherModel.weather {
            Link("Weather data by OpenWeather", destination: weather.attributionURL)
                .font(.caption)
                .foregroundStyle(ink)
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 14, content: content)
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(Color(red: 0.92, green: 0.88, blue: 0.90), lineWidth: 0.75)
            }
            .shadow(color: ink.opacity(0.05), radius: 14, y: 7)
    }
}

private struct BriefingRow: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String
    let trailing: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color(red: 0.16, green: 0.13, blue: 0.15))
                Text(detail)
                    .font(.subheadline)
                if dynamicTypeSize.isAccessibilitySize {
                    Text(trailing).font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

            if !dynamicTypeSize.isAccessibilitySize {
                Text(trailing)
                    .font(.subheadline)
                    .fixedSize()
                    .padding(.top, 12)
            }
        }
        .foregroundStyle(Color(red: 0.48, green: 0.43, blue: 0.46))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    BriefingView()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                HomeSectionNavigationView(selection: .constant(.agenda), height: 56 * 2 / 3)
                BottomNavigationView(selection: .constant(.home))
            }
        }
}
