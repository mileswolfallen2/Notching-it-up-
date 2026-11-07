//
//  WeatherManager.swift
//  boringNotch
//
//  Weather data from Open-Meteo. No API key or location permission is
//  required; the user chooses a city in Settings and the app resolves it
//  through Open-Meteo's geocoding service.
//

import Combine
import Defaults
import Foundation

// MARK: - Models

struct WeatherLocation: Equatable {
    let name: String
    let administrativeArea: String?
    let country: String?
    let latitude: Double
    let longitude: Double

    var displayName: String {
        if let administrativeArea, !administrativeArea.isEmpty {
            return "\(name), \(administrativeArea)"
        }
        if let country, !country.isEmpty {
            return "\(name), \(country)"
        }
        return name
    }

    var fullName: String {
        [name, administrativeArea, country]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: ", ")
    }
}

struct WeatherCurrent: Equatable {
    let temperatureC: Double
    let apparentTemperatureC: Double
    let relativeHumidity: Int?
    let weatherCode: Int
    let windSpeedKph: Double
    let isDay: Bool
    let precipitationMillimeters: Double?

    var condition: WeatherCondition {
        WeatherCondition.forCode(weatherCode, isDay: isDay)
    }
}

struct WeatherDaily: Equatable, Identifiable {
    let date: Date
    let weatherCode: Int
    let highC: Double
    let lowC: Double
    let precipitationProbability: Int?

    var id: Date { date }

    var condition: WeatherCondition {
        WeatherCondition.forCode(weatherCode, isDay: true)
    }
}

struct WeatherSnapshot: Equatable {
    let query: String
    let location: WeatherLocation
    let current: WeatherCurrent
    let daily: [WeatherDaily]
    let fetchedAt: Date
}

struct WeatherCondition {
    let symbolName: String
    let description: String

    static func forCode(_ code: Int, isDay: Bool) -> WeatherCondition {
        switch code {
        case 0:
            return WeatherCondition(
                symbolName: isDay ? "sun.max.fill" : "moon.stars.fill",
                description: "Clear"
            )
        case 1:
            return WeatherCondition(
                symbolName: isDay ? "sun.max.fill" : "moon.fill",
                description: "Mainly clear"
            )
        case 2:
            return WeatherCondition(
                symbolName: isDay ? "cloud.sun.fill" : "cloud.moon.fill",
                description: "Partly cloudy"
            )
        case 3:
            return WeatherCondition(symbolName: "cloud.fill", description: "Overcast")
        case 45, 48:
            return WeatherCondition(symbolName: "cloud.fog.fill", description: "Fog")
        case 51, 53, 55:
            return WeatherCondition(symbolName: "cloud.drizzle.fill", description: "Drizzle")
        case 56, 57:
            return WeatherCondition(symbolName: "cloud.sleet.fill", description: "Freezing drizzle")
        case 61, 63, 65:
            return WeatherCondition(symbolName: "cloud.rain.fill", description: "Rain")
        case 66, 67:
            return WeatherCondition(symbolName: "cloud.sleet.fill", description: "Freezing rain")
        case 71, 73, 75:
            return WeatherCondition(symbolName: "cloud.snow.fill", description: "Snow")
        case 77:
            return WeatherCondition(symbolName: "cloud.snow.fill", description: "Snow grains")
        case 80, 81, 82:
            return WeatherCondition(symbolName: "cloud.heavyrain.fill", description: "Rain showers")
        case 85, 86:
            return WeatherCondition(symbolName: "cloud.snow.fill", description: "Snow showers")
        case 95:
            return WeatherCondition(symbolName: "cloud.bolt.rain.fill", description: "Thunderstorm")
        case 96, 99:
            return WeatherCondition(symbolName: "cloud.bolt.fill", description: "Thunderstorm with hail")
        default:
            return WeatherCondition(symbolName: "cloud.fill", description: "Cloudy")
        }
    }
}

extension WeatherTemperatureUnit {
    func value(fromCelsius celsius: Double) -> Double {
        switch self {
        case .celsius:
            return celsius
        case .fahrenheit:
            return celsius * 9 / 5 + 32
        }
    }

    func string(fromCelsius celsius: Double, includeUnit: Bool = true) -> String {
        let number = String(format: "%.0f", value(fromCelsius: celsius))
        return includeUnit ? "\(number)\(shortLabel)" : number
    }

    func spokenTemperature(fromCelsius celsius: Double) -> String {
        let number = String(format: "%.0f", value(fromCelsius: celsius))
        return "\(number) degrees \(rawValue.lowercased())"
    }

    func windString(fromKilometersPerHour kilometersPerHour: Double) -> String {
        switch self {
        case .celsius:
            return String(format: "%.0f km/h", kilometersPerHour)
        case .fahrenheit:
            return String(format: "%.0f mph", kilometersPerHour * 0.621371)
        }
    }
}

// MARK: - Errors

enum WeatherError: LocalizedError {
    case emptyLocation
    case locationNotFound
    case requestFailed(Int)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .emptyLocation:
            return "Add a city in Weather settings."
        case .locationNotFound:
            return "No matching city found. Try a more specific name."
        case .requestFailed:
            return "The weather service is unavailable right now. Try again in a moment."
        case .invalidData:
            return "The weather service returned data the app could not read."
        }
    }
}

// MARK: - Manager

@MainActor
final class WeatherManager: ObservableObject {
    static let shared = WeatherManager()

    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?

    private let session: URLSession
    private let geocodingURL = URL(string: "https://geocoding-api.open-meteo.com/v1/search")!
    private let forecastURL = URL(string: "https://api.open-meteo.com/v1/forecast")!
    private var refreshTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)

        // Editing the city in Settings updates Defaults on every keystroke.
        // Debounce those edits so typing does not send a request per character.
        Defaults.publisher(.weatherLocation)
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refresh(debounce: true)
                }
            }
            .store(in: &cancellables)
    }

    private var query: String {
        Defaults[.weatherLocation].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var temperatureUnit: WeatherTemperatureUnit {
        Defaults[.weatherTemperatureUnit]
    }

    /// Loads weather only when the tab has no data, the city changed, or the
    /// cached snapshot is older than ten minutes.
    func refreshIfNeeded() {
        let isStale = snapshot.map { Date().timeIntervalSince($0.fetchedAt) > 600 } ?? true
        let queryChanged = snapshot?.query.caseInsensitiveCompare(query) != .orderedSame
        guard isStale || queryChanged else { return }
        refresh()
    }

    func refresh(debounce: Bool = false) {
        refreshTask?.cancel()

        let requestedQuery = query
        guard !requestedQuery.isEmpty else {
            isLoading = false
            errorMessage = WeatherError.emptyLocation.errorDescription
            return
        }

        refreshTask = Task { [weak self] in
            if debounce {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
            }
            guard let self else { return }
            await self.load(query: requestedQuery)
        }
    }

    private func load(query: String) async {
        isLoading = true
        errorMessage = nil

        defer {
            // A cancelled request must not hide the spinner for the request
            // that replaced it.
            if !Task.isCancelled {
                isLoading = false
            }
        }

        do {
            let location = try await geocode(query)
            try Task.checkCancellation()
            let response = try await fetchForecast(for: location)
            try Task.checkCancellation()

            snapshot = WeatherSnapshot(
                query: query,
                location: location,
                current: response.current,
                daily: response.daily,
                fetchedAt: Date()
            )
            lastUpdated = Date()
        } catch is CancellationError {
            return
        } catch let error as WeatherError {
            errorMessage = error.errorDescription
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch is URLError {
            errorMessage = "Couldn't load weather. Check your internet connection and try again."
        } catch {
            errorMessage = WeatherError.invalidData.errorDescription
        }
    }

    // MARK: Networking

    private func geocode(_ query: String) async throws -> WeatherLocation {
        var components = URLComponents(url: geocodingURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
        ]

        guard let url = components?.url else {
            throw WeatherError.invalidData
        }

        let data = try await request(url)
        let response: GeocodingResponse
        do {
            response = try JSONDecoder().decode(GeocodingResponse.self, from: data)
        } catch {
            throw WeatherError.invalidData
        }

        guard let result = response.results?.first else {
            throw WeatherError.locationNotFound
        }

        return WeatherLocation(
            name: result.name,
            administrativeArea: result.admin1,
            country: result.country,
            latitude: result.latitude,
            longitude: result.longitude
        )
    }

    private func fetchForecast(for location: WeatherLocation) async throws -> ForecastResponse {
        var components = URLComponents(url: forecastURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", location.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", location.longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weather_code,wind_speed_10m"
            ),
            URLQueryItem(
                name: "daily",
                value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"
            ),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
            URLQueryItem(name: "wind_speed_unit", value: "kmh"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "6"),
        ]

        guard let url = components?.url else {
            throw WeatherError.invalidData
        }

        let data = try await request(url)
        let response: OpenMeteoForecastResponse
        do {
            response = try JSONDecoder().decode(OpenMeteoForecastResponse.self, from: data)
        } catch {
            throw WeatherError.invalidData
        }

        return ForecastResponse(
            current: WeatherCurrent(
                temperatureC: response.current.temperature,
                apparentTemperatureC: response.current.apparentTemperature,
                relativeHumidity: response.current.relativeHumidity.map { Int($0.rounded()) },
                weatherCode: response.current.weatherCode,
                windSpeedKph: response.current.windSpeed,
                isDay: response.current.isDay != 0,
                precipitationMillimeters: response.current.precipitation
            ),
            daily: Self.dailyForecasts(from: response)
        )
    }

    private func request(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WeatherError.invalidData
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw WeatherError.requestFailed(httpResponse.statusCode)
        }
        return data
    }

    private static func dailyForecasts(from response: OpenMeteoForecastResponse) -> [WeatherDaily] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        if let timeZoneIdentifier = response.timezone,
           let timeZone = TimeZone(identifier: timeZoneIdentifier) {
            formatter.timeZone = timeZone
        }

        let daily = response.daily
        let count = min(
            daily.time.count,
            daily.weatherCode.count,
            daily.temperatureMax.count,
            daily.temperatureMin.count
        )

        return (0..<count).prefix(5).compactMap { index in
            guard let date = formatter.date(from: daily.time[index]) else { return nil }

            let precipitation: Int?
            if let values = daily.precipitationProbability,
               values.indices.contains(index) {
                precipitation = values[index]
            } else {
                precipitation = nil
            }

            return WeatherDaily(
                date: date,
                weatherCode: daily.weatherCode[index],
                highC: daily.temperatureMax[index],
                lowC: daily.temperatureMin[index],
                precipitationProbability: precipitation
            )
        }
    }
}

// MARK: - API payloads

private struct GeocodingResponse: Decodable {
    let results: [GeocodingResult]?
}

private struct GeocodingResult: Decodable {
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
    let admin1: String?
}

private struct ForecastResponse {
    let current: WeatherCurrent
    let daily: [WeatherDaily]
}

private struct OpenMeteoForecastResponse: Decodable {
    let timezone: String?
    let current: Current
    let daily: Daily

    struct Current: Decodable {
        let temperature: Double
        let apparentTemperature: Double
        let relativeHumidity: Double?
        let weatherCode: Int
        let windSpeed: Double
        let isDay: Int
        let precipitation: Double?

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case relativeHumidity = "relative_humidity_2m"
            case weatherCode = "weather_code"
            case windSpeed = "wind_speed_10m"
            case isDay = "is_day"
            case precipitation
        }
    }

    struct Daily: Decodable {
        let time: [String]
        let weatherCode: [Int]
        let temperatureMax: [Double]
        let temperatureMin: [Double]
        let precipitationProbability: [Int?]?

        enum CodingKeys: String, CodingKey {
            case time
            case weatherCode = "weather_code"
            case temperatureMax = "temperature_2m_max"
            case temperatureMin = "temperature_2m_min"
            case precipitationProbability = "precipitation_probability_max"
        }
    }
}
