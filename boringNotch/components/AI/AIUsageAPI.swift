//
//  AIUsageAPI.swift
//  boringNotch
//
//  Reads usage from the provider's own account endpoint after sign-in.
//

import Foundation

struct AIUsageWindow: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let percentRemaining: Double
    let resetDate: Date?
}

struct AILiveUsage: Sendable {
    let percentRemaining: Double
    let resetDate: Date?
    let planName: String?
    let windows: [AIUsageWindow]
}

enum AIUsageAPI {
    static func fetch(provider: AIProvider, account: AIAccount) async throws -> AILiveUsage {
        switch provider {
        case .claude:
            return try await fetchClaude(account)
        case .codex:
            return try await fetchCodex(account)
        case .antigravity:
            return try await fetchAntigravity(account)
        case .copilot:
            return try await fetchCopilot(account)
        case .cursor, .gemini, .opencode:
            throw AIAuthError.unsupported(provider)
        }
    }

    // MARK: Claude

    private static func fetchClaude(_ account: AIAccount) async throws -> AILiveUsage {
        let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
        let response: AIHTTPResponse
        do {
            response = try await AIHTTP.get(url, headers: [
                "Authorization": "Bearer \(account.accessToken)",
                "Accept": "application/json",
                "anthropic-beta": "oauth-2025-04-20",
                "User-Agent": "claude-cli/2.1.294 (external, cli)"
            ])
        } catch let error as AIAuthError {
            throw mapAuthFailure(error, provider: .claude)
        }

        guard let body = response.jsonObject() else { throw AIAuthError.invalidResponse }

        let specs: [(key: String, label: String)] = [
            ("five_hour", "Session"),
            ("seven_day", "Weekly"),
            ("seven_day_sonnet", "Sonnet")
        ]

        var windows: [AIUsageWindow] = []
        for spec in specs {
            guard let object = body[spec.key] as? [String: Any],
                  let used = number(object["utilization"])
            else { continue }
            windows.append(
                AIUsageWindow(
                    label: spec.label,
                    percentRemaining: clamp(100 - used),
                    resetDate: parseDate(object["resets_at"])
                )
            )
        }

        // Newer responses move per-model weekly limits into `limits`.
        if let limits = body["limits"] as? [[String: Any]] {
            for limit in limits {
                guard let kind = limit["kind"] as? String, kind == "weekly_scoped",
                      let scope = limit["scope"] as? [String: Any],
                      let model = scope["model"] as? [String: Any],
                      let name = model["display_name"] as? String,
                      let used = number(limit["percent"])
                else { continue }
                windows.append(
                    AIUsageWindow(
                        label: name,
                        percentRemaining: clamp(100 - used),
                        resetDate: parseDate(limit["resets_at"])
                    )
                )
            }
        }

        guard let primary = windows.min(by: { $0.percentRemaining < $1.percentRemaining }) else {
            throw AIAuthError.unavailable("Claude didn’t return any usage windows for this account.")
        }

        return AILiveUsage(
            percentRemaining: primary.percentRemaining,
            resetDate: primary.resetDate,
            planName: account.planName ?? "Claude",
            windows: windows
        )
    }

    // MARK: Codex / ChatGPT

    private static func fetchCodex(_ account: AIAccount) async throws -> AILiveUsage {
        var headers = [
            "Authorization": "Bearer \(account.accessToken)",
            "Accept": "application/json",
            "User-Agent": "NotchingItUp/1.0"
        ]
        if let accountID = account.accountID, !accountID.isEmpty {
            headers["ChatGPT-Account-Id"] = accountID
        }

        let response: AIHTTPResponse
        do {
            response = try await AIHTTP.get(
                URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
                headers: headers
            )
        } catch let error as AIAuthError {
            throw mapAuthFailure(error, provider: .codex)
        }

        guard let body = response.jsonObject() else { throw AIAuthError.invalidResponse }

        var windows: [AIUsageWindow] = []
        if let rateLimit = body["rate_limit"] as? [String: Any] {
            let slots: [(key: String, fallback: String)] = [
                ("primary_window", "Session"),
                ("secondary_window", "Weekly")
            ]
            for slot in slots {
                guard let window = rateLimit[slot.key] as? [String: Any],
                      let used = number(window["used_percent"])
                else { continue }

                // Some plans swap which slot holds which period; the window length is authoritative.
                let seconds = number(window["limit_window_seconds"])
                let label: String
                if let seconds, seconds >= 6 * 86_400 {
                    label = "Weekly"
                } else if let seconds, seconds > 0 {
                    label = "Session"
                } else {
                    label = slot.fallback
                }

                windows.append(
                    AIUsageWindow(
                        label: label,
                        percentRemaining: clamp(100 - used),
                        resetDate: codexReset(window)
                    )
                )
            }
        }

        guard let primary = windows.min(by: { $0.percentRemaining < $1.percentRemaining }) else {
            throw AIAuthError.unavailable("ChatGPT didn’t return any rate-limit windows for this account.")
        }

        return AILiveUsage(
            percentRemaining: primary.percentRemaining,
            resetDate: primary.resetDate,
            planName: codexPlan(body["plan_type"] as? String) ?? account.planName ?? "ChatGPT",
            windows: windows
        )
    }

    private static func codexReset(_ window: [String: Any]) -> Date? {
        if let seconds = number(window["reset_at"]) {
            return Date(timeIntervalSince1970: seconds)
        }
        if let after = number(window["reset_after_seconds"]) {
            return Date().addingTimeInterval(after)
        }
        return nil
    }

    private static func codexPlan(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "plus":       return "ChatGPT Plus"
        case "pro":        return "ChatGPT Pro"
        case "prolite":    return "ChatGPT Pro 100"
        case "promax":     return "ChatGPT Pro 500"
        case "team":       return "ChatGPT Team"
        case "enterprise": return "ChatGPT Enterprise"
        default:           return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // MARK: Antigravity / Google

    private static let antigravityBaseURLs = [
        "https://cloudcode-pa.googleapis.com",
        "https://daily-cloudcode-pa.googleapis.com"
    ]

    private static let antigravityLabels: [String: String] = [
        "gemini-5h": "Session",
        "gemini-weekly": "Weekly",
        "3p-5h": "Claude Session",
        "3p-weekly": "Claude Weekly"
    ]

    private struct AntigravityBucket {
        let id: String
        let percentRemaining: Double
        let resetDate: Date?
    }

    private static func fetchAntigravity(_ account: AIAccount) async throws -> AILiveUsage {
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "amd64"
        #endif
        let userAgent = "antigravity/2.24.0 (aidev_client; os_type=darwin; arch=\(arch))"
        let headers = [
            "Accept": "application/json",
            "Content-Type": "application/json",
            "Authorization": "Bearer \(account.accessToken)",
            "User-Agent": userAgent
        ]

        let loadPayload: [String: Any] = [
            "metadata": [
                "ideType": "ANTIGRAVITY",
                "platform": "PLATFORM_UNSPECIFIED",
                "pluginType": "GEMINI"
            ]
        ]

        // `loadCodeAssist` needs Antigravity's client metadata for the plan to be readable.
        var loadBody: [String: Any]?
        for base in Self.antigravityBaseURLs {
            guard let url = URL(string: base + "/v1internal:loadCodeAssist") else { continue }
            guard let response = try? await AIHTTP.postJSON(
                url,
                fields: loadPayload,
                headers: headers,
                allowFailure: true
            ) else { continue }

            if [401, 403].contains(response.statusCode) {
                throw AIAuthError.signInExpired(.antigravity)
            }
            if response.isSuccess {
                let root = response.jsonObject()
                loadBody = (root?["response"] as? [String: Any]) ?? root
                break
            }
        }

        let project = (loadBody?["cloudaicompanionProject"] as? String)
            ?? (loadBody?["cloudAiCompanionProject"] as? String)
        let plan = antigravityPlan(loadBody)

        var quotaPayload: [String: Any] = [:]
        if let project, !project.isEmpty { quotaPayload["project"] = project }

        // Production sometimes omits Gemini buckets from an otherwise successful response,
        // so fall back to the daily endpoint when no known bucket came back.
        var buckets: [AntigravityBucket] = []
        var lastError: Error?
        for base in Self.antigravityBaseURLs {
            guard let url = URL(string: base + "/v1internal:retrieveUserQuotaSummary") else { continue }
            do {
                let response = try await AIHTTP.postJSON(
                    url,
                    fields: quotaPayload,
                    headers: headers,
                    allowFailure: true
                )

                if [401, 403].contains(response.statusCode) {
                    if response.statusCode == 403,
                       let error = response.jsonObject()?["error"] as? [String: Any],
                       let details = error["details"] as? [[String: Any]],
                       details.contains(where: { $0["reason"] as? String == "SUBSCRIPTION_REQUIRED" }) {
                        throw AIAuthError.unavailable("Google reports no Antigravity quota for this account.")
                    }
                    throw AIAuthError.signInExpired(.antigravity)
                }
                guard response.isSuccess, let root = response.jsonObject() else { continue }

                let parsed = antigravityBuckets(root)
                buckets.append(contentsOf: parsed)
                // Production can return a partial summary; only stop once every known pool is present.
                if Self.antigravityLabels.keys.allSatisfy({ id in parsed.contains { $0.id == id } }) {
                    break
                }
            } catch let error as AIAuthError {
                if case .signInExpired = error { throw error }
                lastError = error
            } catch {
                lastError = error
            }
        }

        if buckets.isEmpty, let lastError {
            throw lastError
        }

        // Both endpoints may report the same bucket; keep the most constrained reading.
        let unique = Dictionary(grouping: buckets, by: \.id).compactMap { _, group in
            group.min { $0.percentRemaining < $1.percentRemaining }
        }

        let windows = unique.map { bucket in
            AIUsageWindow(
                label: Self.antigravityLabels[bucket.id] ?? bucket.id,
                percentRemaining: bucket.percentRemaining,
                resetDate: bucket.resetDate
            )
        }

        guard let primary = windows.min(by: { $0.percentRemaining < $1.percentRemaining }) else {
            throw AIAuthError.unavailable("Antigravity didn’t return any quota windows for this account.")
        }

        return AILiveUsage(
            percentRemaining: primary.percentRemaining,
            resetDate: primary.resetDate,
            planName: plan ?? account.planName ?? "Google AI",
            windows: windows
        )
    }

    private static func antigravityBuckets(_ root: [String: Any]) -> [AntigravityBucket] {
        let groups = ((root["response"] as? [String: Any])?["groups"] as? [[String: Any]])
            ?? (root["groups"] as? [[String: Any]])
            ?? []

        return groups.flatMap { group -> [AntigravityBucket] in
            // Argon weekly is a separate pool with its own labelling rules; skip it here.
            guard (group["displayName"] as? String) != "Gemini 4 Argon",
                  let buckets = group["buckets"] as? [[String: Any]]
            else { return [] }

            return buckets.compactMap { bucket in
                guard let id = bucket["bucketId"] as? String,
                      Self.antigravityLabels[id] != nil,
                      bucket["disabled"] as? Bool != true,
                      let fraction = number(bucket["remainingFraction"]),
                      fraction.isFinite
                else { return nil }

                return AntigravityBucket(
                    id: id,
                    percentRemaining: clamp(fraction * 100),
                    resetDate: parseDate(bucket["resetTime"])
                )
            }
        }
    }

    private static func antigravityPlan(_ body: [String: Any]?) -> String? {
        let tier = (body?["paidTier"] as? [String: Any]) ?? (body?["currentTier"] as? [String: Any])
        guard let tier else { return nil }
        switch tier["id"] as? String {
        case "g1-pro-tier":       return "Google AI Pro"
        case "g1-ultra-tier":     return "Google AI Ultra"
        case "g1-ultra-lite-tier": return "Google AI Ultra Lite"
        default:
            guard let name = tier["name"] as? String, !name.isEmpty else { return nil }
            return name
        }
    }

    // MARK: GitHub Copilot

    private static func fetchCopilot(_ account: AIAccount) async throws -> AILiveUsage {
        let response: AIHTTPResponse
        do {
            response = try await AIHTTP.get(
                URL(string: "https://api.github.com/copilot_internal/user")!,
                headers: [
                    "Authorization": "token \(account.accessToken)",
                    "Accept": "application/json",
                    "Editor-Version": "vscode/1.96.2",
                    "Editor-Plugin-Version": "copilot-chat/0.26.7",
                    "User-Agent": "GitHubCopilotChat/0.26.7",
                    "X-Github-Api-Version": "2025-04-01"
                ]
            )
        } catch let error as AIAuthError {
            throw mapAuthFailure(error, provider: .copilot)
        }

        guard let body = response.jsonObject() else { throw AIAuthError.invalidResponse }
        let resetDate = parseDate(body["quota_reset_date"]) ?? parseDate(body["limited_user_reset_date"])

        var windows: [AIUsageWindow] = []
        if let snapshots = body["quota_snapshots"] as? [String: Any] {
            let specs: [(key: String, label: String)] = [
                ("premium_interactions", "Credits"),
                ("chat", "Chat"),
                ("completions", "Completions")
            ]
            for spec in specs {
                guard let snapshot = snapshots[spec.key] as? [String: Any] else { continue }
                if snapshot["unlimited"] as? Bool == true { continue }
                if let entitlement = number(snapshot["entitlement"]), entitlement <= 0 { continue }

                let remaining: Double?
                if let percent = number(snapshot["percent_remaining"]) {
                    remaining = clamp(percent)
                } else if let entitlement = number(snapshot["entitlement"]),
                          entitlement > 0,
                          let left = number(snapshot["remaining"]) {
                    remaining = clamp(left / entitlement * 100)
                } else {
                    remaining = nil
                }

                guard let remaining else { continue }
                windows.append(
                    AIUsageWindow(
                        label: spec.label,
                        percentRemaining: remaining,
                        resetDate: resetDate
                    )
                )
            }
        }

        // Older Copilot responses report quotas as remaining/total pairs instead of snapshots.
        if windows.isEmpty {
            let remainingQuotas = body["limited_user_quotas"] as? [String: Any]
            let totalQuotas = body["monthly_quotas"] as? [String: Any]
            let specs: [(key: String, label: String)] = [
                ("chat", "Chat"),
                ("completions", "Completions")
            ]
            for spec in specs {
                guard let remaining = number(remainingQuotas?[spec.key]),
                      let total = number(totalQuotas?[spec.key]),
                      total > 0
                else { continue }
                windows.append(
                    AIUsageWindow(
                        label: spec.label,
                        percentRemaining: clamp(remaining / total * 100),
                        resetDate: resetDate
                    )
                )
            }
        }

        guard let primary = windows.min(by: { $0.percentRemaining < $1.percentRemaining }) else {
            throw AIAuthError.unavailable("Copilot didn’t return a usage quota for this account.")
        }

        return AILiveUsage(
            percentRemaining: primary.percentRemaining,
            resetDate: primary.resetDate,
            planName: copilotPlan(body["copilot_plan"] as? String) ?? account.planName ?? "GitHub Copilot",
            windows: windows
        )
    }

    private static func copilotPlan(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "individual": return "Copilot Individual"
        case "business":   return "Copilot Business"
        case "enterprise": return "Copilot Enterprise"
        default:           return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // MARK: Helpers

    private static func mapAuthFailure(_ error: AIAuthError, provider: AIProvider) -> AIAuthError {
        if case .http(let status, _) = error, [401, 403].contains(status) {
            return .signInExpired(provider)
        }
        return error
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let value as Double:
            return value
        case let value as Int:
            return Double(value)
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return Double(value)
        default:
            return nil
        }
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 100)
    }

    private static func parseDate(_ value: Any?) -> Date? {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                // Formatter instances are not thread-safe and providers sync concurrently.
                let fractional = ISO8601DateFormatter()
                fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let plain = ISO8601DateFormatter()
                plain.formatOptions = [.withInternetDateTime]
                if let date = fractional.date(from: trimmed) ?? plain.date(from: trimmed) {
                    return date
                }
                if trimmed.count == 10 {
                    let dayOnly = DateFormatter()
                    dayOnly.calendar = Calendar(identifier: .gregorian)
                    dayOnly.locale = Locale(identifier: "en_US_POSIX")
                    dayOnly.timeZone = TimeZone(secondsFromGMT: 0)
                    dayOnly.dateFormat = "yyyy-MM-dd"
                    if let date = dayOnly.date(from: trimmed) {
                        return date
                    }
                }
            }
        }
        if let seconds = number(value) {
            let normalized = seconds > 10_000_000_000 ? seconds / 1000 : seconds
            return Date(timeIntervalSince1970: normalized)
        }
        return nil
    }
}
