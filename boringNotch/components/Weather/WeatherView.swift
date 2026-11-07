//
//  WeatherView.swift
//  boringNotch
//
//  Current conditions and a five-day forecast from Open-Meteo.
//

import Defaults
import SwiftUI

/// Opens the settings window directly on the Weather pane.
private func openWeatherSettings() {
    DispatchQueue.main.async {
        SettingsWindowController.shared.showWindow()
        // On a cold open the pane starts observing only after the window mounts.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .openWeatherSettings, object: nil)
        }
    }
}

// MARK: - Notch panel

struct WeatherView: View {
    @ObservedObject private var manager = WeatherManager.shared
    @Default(.weatherLocation) private var configuredLocation
    @Default(.weatherTemperatureUnit) private var temperatureUnit

    private var hasLocation: Bool {
        !configuredLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NotchPanelStyle.spacing) {
            header

            Group {
                if let snapshot = manager.snapshot {
                    weatherCard(for: snapshot)
                } else if manager.isLoading {
                    loadingCard
                } else {
                    emptyCard
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            footer
        }
        .padding(.horizontal, 3)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            manager.refreshIfNeeded()
        }
    }

    private var header: some View {
        NotchPanelHeader(
            icon: "cloud.sun.fill",
            title: "Weather",
            detail: manager.snapshot?.location.displayName ?? (hasLocation ? configuredLocation : "No city selected")
        ) {
            HStack(spacing: 2) {
                Button {
                    manager.refresh()
                } label: {
                    Group {
                        if manager.isLoading {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(manager.isLoading)
                .help("Refresh weather")
                .accessibilityLabel("Refresh weather")
                .accessibilityHint("Fetches the latest conditions for the selected city")

                Button {
                    openWeatherSettings()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Configure weather")
                .accessibilityLabel("Configure weather")
                .accessibilityHint("Opens Weather settings")
            }
        }
    }

    // MARK: Current conditions

    private func weatherCard(for snapshot: WeatherSnapshot) -> some View {
        HStack(alignment: .top, spacing: 10) {
            currentConditions(for: snapshot)
            Rectangle()
                .fill(NotchPanelStyle.border)
                .frame(width: 1)
                .padding(.vertical, 4)
            forecast(for: snapshot)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: NotchPanelStyle.cornerRadius, style: .continuous)
                .fill(NotchPanelStyle.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NotchPanelStyle.cornerRadius, style: .continuous)
                .strokeBorder(NotchPanelStyle.border, lineWidth: 1)
        )
    }

    private func currentConditions(for snapshot: WeatherSnapshot) -> some View {
        let current = snapshot.current
        let today = snapshot.daily.first

        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(temperatureUnit.string(fromCelsius: current.temperatureC, includeUnit: false))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(temperatureUnit.shortLabel)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Text(current.condition.description)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(1)

            Text("Feels like \(temperatureUnit.string(fromCelsius: current.apparentTemperatureC))")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(NotchPanelStyle.secondaryText)
                .lineLimit(1)

            if let today {
                Text("H \(temperatureUnit.string(fromCelsius: today.highC))  L \(temperatureUnit.string(fromCelsius: today.lowC))")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }

            HStack(spacing: 7) {
                Label(
                    temperatureUnit.windString(fromKilometersPerHour: current.windSpeedKph),
                    systemImage: "wind"
                )
                if let humidity = current.relativeHumidity {
                    Label("\(humidity)%", systemImage: "humidity.fill")
                }
            }
            .font(.system(size: 8, weight: .medium, design: .rounded))
            .foregroundStyle(NotchPanelStyle.secondaryText)
            .lineLimit(1)
        }
        .frame(width: 150, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary(for: snapshot))
    }

    private func forecast(for snapshot: WeatherSnapshot) -> some View {
        HStack(spacing: 0) {
            ForEach(snapshot.daily) { day in
                forecastColumn(for: day, isToday: day.id == snapshot.daily.first?.id)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func forecastColumn(for day: WeatherDaily, isToday: Bool) -> some View {
        VStack(spacing: 3) {
            Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                .font(.system(size: 9, weight: isToday ? .bold : .semibold, design: .rounded))
                .foregroundStyle(isToday ? .white : NotchPanelStyle.secondaryText)
                .lineLimit(1)

            Image(systemName: day.condition.symbolName)
                .font(.system(size: 14, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.9))
                .frame(height: 17)

            Text("\(temperatureUnit.string(fromCelsius: day.highC, includeUnit: false))°")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text("\(temperatureUnit.string(fromCelsius: day.lowC, includeUnit: false))°")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(NotchPanelStyle.secondaryText)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: day, isToday: isToday))
    }

    // MARK: Loading and empty states

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("Loading weather")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Fetching conditions for \(configuredLocation)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(NotchPanelStyle.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: NotchPanelStyle.cornerRadius, style: .continuous)
                .fill(NotchPanelStyle.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NotchPanelStyle.cornerRadius, style: .continuous)
                .strokeBorder(NotchPanelStyle.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading weather for \(configuredLocation)")
    }

    private var emptyCard: some View {
        HStack(spacing: 10) {
            Image(systemName: hasLocation ? "cloud.slash.fill" : "mappin.and.ellipse")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(hasLocation ? "Weather unavailable" : "Choose a city")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(manager.errorMessage ?? "Set a location in Weather settings to see conditions and a five-day forecast.")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(NotchPanelStyle.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if hasLocation {
                Button("Retry") {
                    manager.refresh()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .accessibilityLabel("Retry loading weather")
            } else {
                Button("Open Settings") {
                    openWeatherSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .accessibilityLabel("Open Weather settings")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: NotchPanelStyle.cornerRadius, style: .continuous)
                .fill(NotchPanelStyle.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NotchPanelStyle.cornerRadius, style: .continuous)
                .strokeBorder(NotchPanelStyle.border, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(hasLocation ? "Weather unavailable" : "No city selected")
    }

    private var footer: some View {
        HStack(spacing: 4) {
            if let error = manager.errorMessage, manager.snapshot != nil {
                Text(error)
                    .foregroundStyle(.orange.opacity(0.9))
                    .lineLimit(1)
            } else if let lastUpdated = manager.lastUpdated {
                Text("Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))")
            }
            Spacer(minLength: 4)
            Text("Open-Meteo")
        }
        .font(.system(size: 8, weight: .medium, design: .rounded))
        .foregroundStyle(NotchPanelStyle.secondaryText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(weatherFooterAccessibilityLabel)
    }

    // MARK: Accessibility

    private func accessibilitySummary(for snapshot: WeatherSnapshot) -> String {
        let current = snapshot.current
        var parts = [
            snapshot.location.displayName,
            current.condition.description,
            temperatureUnit.spokenTemperature(fromCelsius: current.temperatureC),
            "feels like \(temperatureUnit.spokenTemperature(fromCelsius: current.apparentTemperatureC))",
        ]
        if let today = snapshot.daily.first {
            parts.append("high \(temperatureUnit.spokenTemperature(fromCelsius: today.highC))")
            parts.append("low \(temperatureUnit.spokenTemperature(fromCelsius: today.lowC))")
        }
        parts.append("wind \(temperatureUnit.windString(fromKilometersPerHour: current.windSpeedKph))")
        if let humidity = current.relativeHumidity {
            parts.append("humidity \(humidity) percent")
        }
        return parts.joined(separator: ", ")
    }

    private func accessibilityLabel(for day: WeatherDaily, isToday: Bool) -> String {
        var parts = [isToday ? "Today" : day.date.formatted(.dateTime.weekday(.wide))]
        parts.append(day.condition.description)
        parts.append("high \(temperatureUnit.spokenTemperature(fromCelsius: day.highC))")
        parts.append("low \(temperatureUnit.spokenTemperature(fromCelsius: day.lowC))")
        if let precipitation = day.precipitationProbability, precipitation > 0 {
            parts.append("\(precipitation) percent chance of precipitation")
        }
        return parts.joined(separator: ", ")
    }

    private var weatherFooterAccessibilityLabel: String {
        if let error = manager.errorMessage, manager.snapshot != nil {
            return "\(error). Weather data from Open-Meteo."
        }
        if let lastUpdated = manager.lastUpdated {
            return "Updated \(lastUpdated.formatted(date: .omitted, time: .shortened)). Weather data from Open-Meteo."
        }
        return "Weather data from Open-Meteo."
    }
}

// MARK: - Settings

struct WeatherSettings: View {
    @ObservedObject private var manager = WeatherManager.shared
    @Default(.weatherLocation) private var location
    @Default(.weatherTemperatureUnit) private var temperatureUnit
    @Default(.showWeatherTab) private var showWeatherTab

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showWeatherTab) {
                    Label("Show Weather tab in the notch", systemImage: "cloud.sun.fill")
                }
            } header: {
                Text("Notch")
            }

            Section {
                TextField("City", text: $location)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        manager.refresh()
                    }

                Picker("Temperature unit", selection: $temperatureUnit) {
                    ForEach(WeatherTemperatureUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Location")
            } footer: {
                Text("Enter a city name and press Return. Notching it up looks up the city with Open-Meteo; it does not use Location Services or ask for a location permission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 8) {
                    if manager.isLoading {
                        ProgressView()
                            .controlSize(.small)
                        Text("Updating weather…")
                            .foregroundStyle(.secondary)
                    } else if let error = manager.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else if let lastUpdated = manager.lastUpdated {
                        Text("Last updated \(lastUpdated.formatted(date: .abbreviated, time: .shortened))")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Weather has not been loaded yet.")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Refresh now") {
                        manager.refresh()
                    }
                    .controlSize(.small)
                    .disabled(manager.isLoading)
                }
            } header: {
                Text("Status")
            }

            Section {
                if let url = URL(string: "https://open-meteo.com/") {
                    Link("Weather data by Open-Meteo", destination: url)
                        .font(.caption)
                }
                Text("Open-Meteo provides free weather forecasts for non-commercial use. Notching it up sends only the city name and coordinates needed for the forecast.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Data")
            }
        }
        .navigationTitle("Weather")
        .task {
            manager.refreshIfNeeded()
        }
    }
}
