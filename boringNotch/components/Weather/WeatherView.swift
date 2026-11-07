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

    private var cityName: String {
        if let snapshot = manager.snapshot {
            return snapshot.location.displayName
        }
        let trimmed = configuredLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No city" : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header

            if let snapshot = manager.snapshot {
                snapshotCard(snapshot)
            } else {
                statusCard
            }

            Spacer(minLength: 0)

            Text("Open-Meteo")
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(NotchPanelStyle.secondaryText)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 3)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            manager.refreshIfNeeded()
        }
    }

    private var header: some View {
        NotchPanelHeader(icon: "cloud.sun.fill", title: "Weather", detail: cityName) {
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
            }
        }
    }

    // MARK: Snapshot

    private func snapshotCard(_ snapshot: WeatherSnapshot) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(temperatureUnit.string(fromCelsius: snapshot.current.temperatureC, includeUnit: false))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(temperatureUnit.shortLabel)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Text(snapshot.current.condition.description)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(width: 92, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(currentAccessibilityLabel(snapshot))

            forecast(snapshot)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: NotchPanelStyle.cornerRadius, style: .continuous)
                .fill(NotchPanelStyle.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NotchPanelStyle.cornerRadius, style: .continuous)
                .strokeBorder(NotchPanelStyle.border, lineWidth: 1)
        )
    }

    private func forecast(_ snapshot: WeatherSnapshot) -> some View {
        HStack(spacing: 0) {
            ForEach(snapshot.daily) { day in
                dayColumn(day, isToday: day.id == snapshot.daily.first?.id)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayColumn(_ day: WeatherDaily, isToday: Bool) -> some View {
        VStack(spacing: 4) {
            Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                .font(.system(size: 9, weight: isToday ? .bold : .medium, design: .rounded))
                .foregroundStyle(isToday ? .white : NotchPanelStyle.secondaryText)
                .lineLimit(1)

            Image(systemName: day.condition.symbolName)
                .font(.system(size: 14, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.9))
                .frame(height: 17)

            HStack(spacing: 3) {
                Text(temperatureUnit.string(fromCelsius: day.highC, includeUnit: false))
                    .foregroundStyle(.white)
                Text(temperatureUnit.string(fromCelsius: day.lowC, includeUnit: false))
                    .foregroundStyle(NotchPanelStyle.secondaryText)
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dayAccessibilityLabel(day, isToday: isToday))
    }

    // MARK: Empty and loading

    private var statusCard: some View {
        HStack(spacing: 8) {
            if manager.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: hasLocation ? "exclamationmark.triangle" : "mappin.and.ellipse")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Text(statusText)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(2)

            Spacer(minLength: 8)

            if !manager.isLoading {
                if hasLocation {
                    Button("Retry") {
                        manager.refresh()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                } else {
                    Button("Settings") {
                        openWeatherSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: NotchPanelStyle.cornerRadius, style: .continuous)
                .fill(NotchPanelStyle.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NotchPanelStyle.cornerRadius, style: .continuous)
                .strokeBorder(NotchPanelStyle.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statusText)
    }

    private var statusText: String {
        if manager.isLoading {
            return "Loading weather"
        }
        if !hasLocation {
            return "Choose a city in Weather settings"
        }
        return manager.errorMessage ?? "Weather unavailable"
    }

    // MARK: Accessibility

    private func currentAccessibilityLabel(_ snapshot: WeatherSnapshot) -> String {
        var parts = [
            snapshot.location.displayName,
            snapshot.current.condition.description,
            temperatureUnit.spokenTemperature(fromCelsius: snapshot.current.temperatureC),
        ]
        if let today = snapshot.daily.first {
            parts.append("high \(temperatureUnit.spokenTemperature(fromCelsius: today.highC))")
            parts.append("low \(temperatureUnit.spokenTemperature(fromCelsius: today.lowC))")
        }
        return parts.joined(separator: ", ")
    }

    private func dayAccessibilityLabel(_ day: WeatherDaily, isToday: Bool) -> String {
        let weekday = isToday ? "Today" : day.date.formatted(.dateTime.weekday(.wide))
        return [
            weekday,
            day.condition.description,
            "high \(temperatureUnit.spokenTemperature(fromCelsius: day.highC))",
            "low \(temperatureUnit.spokenTemperature(fromCelsius: day.lowC))",
        ]
        .joined(separator: ", ")
    }
}

// MARK: - Settings

struct WeatherSettings: View {
    @ObservedObject private var manager = WeatherManager.shared
    @Default(.weatherLocation) private var location
    @Default(.weatherTemperatureUnit) private var temperatureUnit

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showWeatherTab) {
                    Label("Show Weather tab in the notch", systemImage: "cloud.sun.fill")
                }

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

                HStack(spacing: 8) {
                    statusLabel

                    Spacer()

                    Button("Refresh") {
                        manager.refresh()
                    }
                    .controlSize(.small)
                    .disabled(manager.isLoading)
                }
            } header: {
                Text("Weather")
            } footer: {
                if let url = URL(string: "https://open-meteo.com/") {
                    Link("Weather data by Open-Meteo", destination: url)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Weather")
        .task {
            manager.refreshIfNeeded()
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if manager.isLoading {
            ProgressView()
                .controlSize(.small)
        } else if let error = manager.errorMessage {
            Text(error)
                .foregroundStyle(.orange)
                .lineLimit(1)
        } else if let lastUpdated = manager.lastUpdated {
            Text("Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))")
                .foregroundStyle(.secondary)
        } else {
            Text("Not loaded yet")
                .foregroundStyle(.secondary)
        }
    }
}
