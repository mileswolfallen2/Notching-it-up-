//
//  AIChat.swift
//  boringNotch
//
//  Chat backends for Apple Intelligence, already signed-in providers, and Ollama.
//

import Defaults
import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Chat provider

/// A provider that can answer a chat message from the AI tab.
enum AIChatProvider: String, CaseIterable, Codable, Identifiable, Defaults.Serializable, Hashable, Sendable {
    case apple
    case claude
    case codex
    case antigravity
    case copilot
    case ollama

    var id: String { rawValue }

    var label: String {
        switch self {
        case .apple:       return "Apple Intelligence"
        case .claude:      return "Claude"
        case .codex:       return "ChatGPT"
        case .antigravity: return "Antigravity"
        case .copilot:     return "Copilot"
        case .ollama:      return "Ollama"
        }
    }

    var iconName: String {
        switch self {
        case .apple:       return "apple.logo"
        case .claude:      return "sparkles"
        case .codex:       return "terminal"
        case .antigravity: return "atom"
        case .copilot:     return "chevron.left.forwardslash.chevron.right"
        case .ollama:      return "server.rack"
        }
    }

    /// The usage provider whose stored sign-in should be reused, when any.
    var accountProvider: AIProvider? {
        switch self {
        case .claude:      return .claude
        case .codex:       return .codex
        case .antigravity: return .antigravity
        case .copilot:     return .copilot
        case .apple, .ollama:
            return nil
        }
    }

    var defaultModel: String {
        switch self {
        case .apple:       return "Apple Intelligence"
        case .claude:      return "claude-sonnet-4-5"
        case .codex:       return "gpt-5"
        case .antigravity: return "gemini-2.5-pro"
        case .copilot:     return "gpt-4.1"
        case .ollama:      return "llama3.2"
        }
    }

    var detail: String {
        switch self {
        case .apple:       return "On-device"
        case .ollama:      return "Local server"
        case .claude, .codex, .antigravity, .copilot:
            return "Signed-in account"
        }
    }

    /// Whether this Mac can run Apple Intelligence, regardless of the chat toggle.
    static var appleSupported: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return AppleFoundationChat.isAvailable
        }
        #endif
        return false
    }

    /// Apple Intelligence is only used when it is supported and turned on in settings.
    static var appleAvailable: Bool {
        Defaults[.aiChatUseAppleIntelligence] && appleSupported
    }
}

// MARK: - Messages

enum AIChatRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

struct AIChatMessage: Identifiable, Equatable, Sendable {
    let id = UUID()
    let role: AIChatRole
    let content: String
    let date = Date()
}

// MARK: - Errors

enum AIChatError: LocalizedError {
    case unavailable(String)
    case invalidResponse
    case emptyResponse
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return message
        case .invalidResponse:
            return "The provider returned an unexpected response."
        case .emptyResponse:
            return "The provider returned an empty reply."
        case .http(let status, let body):
            let detail = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "Request failed with HTTP \(status)." : "HTTP \(status): \(detail)"
        }
    }
}

// MARK: - Store

@MainActor
final class AIChatStore: ObservableObject {
    static let shared = AIChatStore()

    @Published private(set) var messages: [AIChatMessage] = []
    @Published private(set) var isSending = false
    @Published var errorText: String?

    private var task: Task<Void, Never>?
    private let historyLimit = 24

    private init() {}

    func send(_ text: String, provider: AIChatProvider) {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isSending else { return }

        errorText = nil
        append(AIChatMessage(role: .user, content: prompt))
        isSending = true

        let history = messages
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let reply = try await AIChatService.reply(provider: provider, messages: history)
                guard !Task.isCancelled else { return }
                self.append(AIChatMessage(role: .assistant, content: reply))
            } catch is CancellationError {
                // The user stopped the reply.
            } catch {
                guard !Task.isCancelled else { return }
                self.errorText = error.localizedDescription
            }
            self.isSending = false
            self.task = nil
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isSending = false
    }

    func clear() {
        stop()
        messages.removeAll()
        errorText = nil
    }

    /// Keeps the notch chat small in memory while preserving recent context.
    private func append(_ message: AIChatMessage) {
        messages.append(message)
        if messages.count > historyLimit {
            messages.removeFirst(messages.count - historyLimit)
        }
    }
}

// MARK: - Service

@MainActor
enum AIChatService {
    static func reply(provider: AIChatProvider, messages: [AIChatMessage]) async throws -> String {
        switch provider {
        case .apple:
            return try await appleReply(messages)
        case .ollama:
            return try await ollamaReply(messages)
        case .claude, .codex, .antigravity, .copilot:
            guard let usageProvider = provider.accountProvider else {
                throw AIChatError.unavailable("\(provider.label) is not available for chat.")
            }
            let account = try await AIAuthService.shared.validAccount(for: usageProvider)
            switch provider {
            case .claude:
                return try await claudeReply(messages, account: account)
            case .codex:
                return try await codexReply(messages, account: account)
            case .antigravity:
                return try await antigravityReply(messages, account: account)
            case .copilot:
                return try await copilotReply(messages, account: account)
            case .apple, .ollama:
                throw AIChatError.unavailable("\(provider.label) is not available for chat.")
            }
        }
    }

    // MARK: Shared

    private static var systemPrompt: String {
        let value = Defaults[.aiChatSystemPrompt].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty
            ? "You are a concise, helpful assistant in the macOS notch. Keep replies short and practical."
            : value
    }

    private static func model(for provider: AIChatProvider) -> String {
        let value: String
        switch provider {
        case .claude:      value = Defaults[.aiChatClaudeModel]
        case .codex:       value = Defaults[.aiChatCodexModel]
        case .antigravity: value = Defaults[.aiChatAntigravityModel]
        case .copilot:     value = Defaults[.aiChatCopilotModel]
        case .ollama:      value = Defaults[.aiChatOllamaModel]
        case .apple:       value = ""
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? provider.defaultModel : trimmed
    }

    static func ollamaBaseURL() -> String {
        let raw = Defaults[.aiChatOllamaBaseURL].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = raw.isEmpty ? "http://localhost:11434" : raw
        return value.hasSuffix("/") ? String(value.dropLast()) : value
    }

    static func checkOllama() async -> String {
        let base = ollamaBaseURL()
        guard let url = URL(string: base + "/api/tags") else {
            return "That server address isn’t valid."
        }

        do {
            let response = try await AIChatHTTP.get(url)
            guard response.isSuccess else {
                return "Ollama answered with HTTP \(response.statusCode)."
            }
            let models = (response.jsonObject()?["models"] as? [[String: Any]])?
                .compactMap { $0["name"] as? String } ?? []
            if models.isEmpty {
                return "Connected. No models are installed yet."
            }
            return "Connected. \(models.count) model\(models.count == 1 ? "" : "s") available."
        } catch {
            return "Not reachable. Make sure Ollama is running."
        }
    }

    private static func chatMessages(_ messages: [AIChatMessage]) -> [[String: String]] {
        messages
            .filter { $0.role != .system }
            .map { ["role": $0.role.rawValue, "content": $0.content] }
    }

    private static func ensureSuccess(_ response: AIHTTPResponse, provider: AIChatProvider) throws {
        guard response.isSuccess else {
            throw responseError(response, provider: provider)
        }
    }

    private static func responseError(_ response: AIHTTPResponse, provider: AIChatProvider) -> AIChatError {
        let body = String(decoding: response.data.prefix(400), as: UTF8.self)
        switch response.statusCode {
        case 401, 403:
            return .unavailable("\(provider.label) couldn’t use this sign-in for chat. Sign in again in AI settings.")
        case 429:
            return .unavailable("\(provider.label) is rate limited right now. Try again in a moment.")
        default:
            return .http(response.statusCode, body)
        }
    }

    private static func json(_ response: AIHTTPResponse, provider: AIChatProvider) throws -> [String: Any] {
        try ensureSuccess(response, provider: provider)
        guard let object = response.jsonObject() else {
            throw AIChatError.invalidResponse
        }
        return object
    }

    // MARK: Apple Intelligence

    private static func appleReply(_ messages: [AIChatMessage]) async throws -> String {
        guard Defaults[.aiChatUseAppleIntelligence] else {
            throw AIChatError.unavailable("Apple Intelligence is turned off in AI settings.")
        }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return try await AppleFoundationChat.reply(
                messages: messages,
                instructions: systemPrompt
            )
        }
        #endif
        throw AIChatError.unavailable("Apple Intelligence requires macOS 26 or later on a supported Mac.")
    }

    // MARK: Claude

    private static func claudeReply(_ messages: [AIChatMessage], account: AIAccount) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let body: [String: Any] = [
            "model": model(for: .claude),
            "max_tokens": 1_024,
            "system": systemPrompt,
            "messages": chatMessages(messages)
        ]
        let headers = [
            "Authorization": "Bearer \(account.accessToken)",
            "anthropic-version": "2023-06-01",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": "claude-cli/2.1.294 (external, cli)"
        ]

        let response = try await AIChatHTTP.postJSON(url, fields: body, headers: headers)
        let object = try json(response, provider: .claude)

        let text = (object["content"] as? [[String: Any]])?
            .compactMap { $0["text"] as? String }
            .joined(separator: "")
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIChatError.emptyResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Codex / ChatGPT

    private static func codexReply(_ messages: [AIChatMessage], account: AIAccount) async throws -> String {
        let url = URL(string: "https://chatgpt.com/backend-api/codex/responses")!
        var headers = [
            "Authorization": "Bearer \(account.accessToken)",
            "Accept": "application/json",
            "Content-Type": "application/json",
            "OpenAI-Beta": "responses=experimental",
            "originator": "codex_cli_rs",
            "session_id": UUID().uuidString,
            "User-Agent": "codex_cli_rs/0.54.0"
        ]
        if let accountID = account.accountID, !accountID.isEmpty {
            headers["ChatGPT-Account-Id"] = accountID
        }

        let baseBody: [String: Any] = [
            "model": model(for: .codex),
            "instructions": systemPrompt,
            "input": chatMessages(messages),
            "store": false
        ]

        // Ask for a single JSON reply first. Some Codex backends only stream,
        // so retry with SSE and assemble the deltas when that is rejected.
        var body = baseBody
        body["stream"] = false
        let response = try await AIChatHTTP.postJSON(url, fields: body, headers: headers)

        if response.isSuccess {
            if let object = response.jsonObject(), let text = codexText(from: object) {
                return text
            }
            if let text = codexTextFromSSE(response.data) {
                return text
            }
        } else if [401, 403, 429].contains(response.statusCode) {
            throw responseError(response, provider: .codex)
        }

        var streamBody = baseBody
        streamBody["stream"] = true
        var streamHeaders = headers
        streamHeaders["Accept"] = "text/event-stream"
        let streamResponse = try await AIChatHTTP.postJSON(url, fields: streamBody, headers: streamHeaders)
        try ensureSuccess(streamResponse, provider: .codex)

        if let text = codexTextFromSSE(streamResponse.data) {
            return text
        }
        if let object = streamResponse.jsonObject(), let text = codexText(from: object) {
            return text
        }
        throw AIChatError.emptyResponse
    }

    private static func codexText(from object: [String: Any]) -> String? {
        if let text = object["output_text"] as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let output = object["output"] as? [[String: Any]] {
            let parts = output.flatMap { item -> [String] in
                guard let content = item["content"] as? [[String: Any]] else { return [] }
                return content.compactMap { $0["text"] as? String }
            }
            let text = parts.joined()
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Some compatible endpoints answer with a chat-completions shape.
        if let choices = object["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let text = message["content"] as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func codexTextFromSSE(_ data: Data) -> String? {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        var parts: [String] = []
        var completed: String?

        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data:") else { continue }
            let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            guard payload != "[DONE]", let payloadData = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
            else { continue }

            guard let type = event["type"] as? String else { continue }
            if type == "response.output_text.delta", let delta = event["delta"] as? String {
                parts.append(delta)
            } else if type == "response.output_text.done", let text = event["text"] as? String {
                completed = text
            }
        }

        let text = parts.isEmpty ? (completed ?? "") : parts.joined()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: Antigravity / Google

    private static let antigravityBaseURLs = [
        "https://cloudcode-pa.googleapis.com",
        "https://daily-cloudcode-pa.googleapis.com"
    ]

    private static func antigravityReply(_ messages: [AIChatMessage], account: AIAccount) async throws -> String {
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "amd64"
        #endif
        let headers = [
            "Accept": "application/json",
            "Content-Type": "application/json",
            "Authorization": "Bearer \(account.accessToken)",
            "User-Agent": "antigravity/2.24.0 (aidev_client; os_type=darwin; arch=\(arch))"
        ]

        let contents = messages
            .filter { $0.role != .system }
            .map { message -> [String: Any] in
                [
                    "role": message.role == .assistant ? "model" : "user",
                    "parts": [["text": message.content]]
                ]
            }

        let modelName = model(for: .antigravity)
        let request: [String: Any] = [
            "contents": contents,
            "systemInstruction": ["parts": [["text": systemPrompt]]]
        ]
        let project = await antigravityProject(headers: headers)

        var lastError: Error = AIChatError.emptyResponse
        for base in antigravityBaseURLs {
            guard let url = URL(string: base + "/v1internal:generateContent") else { continue }
            var body: [String: Any] = ["model": modelName, "request": request]
            if let project, !project.isEmpty {
                body["project"] = project
            }

            do {
                let response = try await AIChatHTTP.postJSON(url, fields: body, headers: headers)
                if let object = try? json(response, provider: .antigravity),
                   let text = antigravityText(from: object) {
                    return text
                }
                lastError = responseError(response, provider: .antigravity)
            } catch {
                lastError = error
            }
        }

        // Google’s public endpoint is a useful fallback when the project-scoped
        // Antigravity endpoint isn’t available for this account.
        let publicModel = modelName.hasPrefix("models/") ? String(modelName.dropFirst(7)) : modelName
        if let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(publicModel):generateContent") {
            do {
                let response = try await AIChatHTTP.postJSON(
                    url,
                    fields: [
                        "contents": contents,
                        "systemInstruction": ["parts": [["text": systemPrompt]]]
                    ],
                    headers: ["Authorization": "Bearer \(account.accessToken)"]
                )
                let object = try json(response, provider: .antigravity)
                if let text = antigravityText(from: object) {
                    return text
                }
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    private static func antigravityProject(headers: [String: String]) async -> String? {
        let payload: [String: Any] = [
            "metadata": [
                "ideType": "ANTIGRAVITY",
                "platform": "PLATFORM_UNSPECIFIED",
                "pluginType": "GEMINI"
            ]
        ]

        for base in antigravityBaseURLs {
            guard let url = URL(string: base + "/v1internal:loadCodeAssist") else { continue }
            guard let response = try? await AIChatHTTP.postJSON(url, fields: payload, headers: headers),
                  response.isSuccess,
                  let root = response.jsonObject()
            else { continue }

            let body = (root["response"] as? [String: Any]) ?? root
            if let project = (body["cloudaicompanionProject"] as? String)
                ?? (body["cloudAiCompanionProject"] as? String)
                ?? (body["project"] as? String),
               !project.isEmpty {
                return project
            }
        }
        return nil
    }

    private static func antigravityText(from object: [String: Any]) -> String? {
        let root = (object["response"] as? [String: Any]) ?? object
        guard let candidates = root["candidates"] as? [[String: Any]] else { return nil }

        let parts = candidates.flatMap { candidate -> [String] in
            guard let content = candidate["content"] as? [String: Any],
                  let pieces = content["parts"] as? [[String: Any]]
            else { return [] }
            return pieces.compactMap { $0["text"] as? String }
        }
        let text = parts.joined()
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    // MARK: GitHub Copilot

    private static func copilotReply(_ messages: [AIChatMessage], account: AIAccount) async throws -> String {
        let tokenURL = URL(string: "https://api.github.com/copilot_internal/v2/token")!
        let tokenResponse = try await AIChatHTTP.get(
            tokenURL,
            headers: [
                "Authorization": "token \(account.accessToken)",
                "Accept": "application/json",
                "User-Agent": "Notching it up",
                "Editor-Version": "vscode/1.95.0",
                "Editor-Plugin-Version": "copilot-chat/0.23.0"
            ]
        )
        let tokenObject = try json(tokenResponse, provider: .copilot)
        guard let copilotToken = tokenObject["token"] as? String else {
            throw AIChatError.unavailable("GitHub didn’t return a Copilot token. Sign in again in AI settings.")
        }

        let api = (tokenObject["endpoints"] as? [String: Any])?["api"] as? String
            ?? "https://api.githubcopilot.com"
        let base = api.hasSuffix("/") ? String(api.dropLast()) : api
        guard let url = URL(string: base + "/chat/completions") else {
            throw AIChatError.invalidResponse
        }

        var chatMessages = chatMessages(messages)
        chatMessages.insert(["role": "system", "content": systemPrompt], at: 0)

        let response = try await AIChatHTTP.postJSON(
            url,
            fields: [
                "model": model(for: .copilot),
                "messages": chatMessages,
                "stream": false
            ],
            headers: [
                "Authorization": "Bearer \(copilotToken)",
                "Copilot-Integration-Id": "vscode-chat",
                "Editor-Version": "vscode/1.95.0",
                "X-Initiator": "user"
            ]
        )
        let object = try json(response, provider: .copilot)

        guard let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw AIChatError.emptyResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Ollama

    private static func ollamaReply(_ messages: [AIChatMessage]) async throws -> String {
        let base = ollamaBaseURL()
        guard let url = URL(string: base + "/api/chat") else {
            throw AIChatError.unavailable("That Ollama server address isn’t valid.")
        }

        var chatMessages = chatMessages(messages)
        chatMessages.insert(["role": "system", "content": systemPrompt], at: 0)

        do {
            let response = try await AIChatHTTP.postJSON(
                url,
                fields: [
                    "model": model(for: .ollama),
                    "messages": chatMessages,
                    "stream": false
                ]
            )
            let object = try json(response, provider: .ollama)
            guard let message = object["message"] as? [String: Any],
                  let text = message["content"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw AIChatError.emptyResponse
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as AIChatError {
            throw error
        } catch {
            throw AIChatError.unavailable("Could not reach Ollama at \(base). Make sure Ollama is running.")
        }
    }
}

// MARK: - Apple Intelligence

#if canImport(FoundationModels)
@available(macOS 26.0, *)
enum AppleFoundationChat {
    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    static func reply(messages: [AIChatMessage], instructions: String) async throws -> String {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            throw AIChatError.unavailable(availabilityMessage(for: model.availability))
        }

        let session = LanguageModelSession(model: model, instructions: instructions)
        let transcript = messages
            .filter { $0.role != .system }
            .map { "\($0.role == .user ? "User" : "Assistant"): \($0.content)" }
            .joined(separator: "\n\n")
        let prompt = transcript + "\n\nAssistant:"

        do {
            let response = try await session.respond(to: prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw AIChatError.emptyResponse }
            return text
        } catch let error as AIChatError {
            throw error
        } catch {
            throw AIChatError.unavailable("Apple Intelligence couldn’t answer. \(error.localizedDescription)")
        }
    }

    private static func availabilityMessage(for availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            return "Apple Intelligence is ready."
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "This Mac doesn’t support Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                return "Turn on Apple Intelligence in System Settings to use it here."
            case .modelNotReady:
                return "Apple Intelligence is still getting ready. Try again in a moment."
            @unknown default:
                return "Apple Intelligence isn’t available right now."
            }
        }
    }
}
#endif

// MARK: - HTTP

/// A chat-specific HTTP helper with a longer timeout than usage requests.
private enum AIChatHTTP {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    static func get(_ url: URL, headers: [String: String] = [:]) async throws -> AIHTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        return try await send(request)
    }

    static func postJSON(
        _ url: URL,
        fields: [String: Any],
        headers: [String: String] = [:]
    ) async throws -> AIHTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        var allHeaders = [
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]
        allHeaders.merge(headers) { _, new in new }
        for (key, value) in allHeaders { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = try JSONSerialization.data(withJSONObject: fields)
        return try await send(request)
    }

    private static func send(_ request: URLRequest) async throws -> AIHTTPResponse {
        var request = request
        if request.timeoutInterval <= 0 || request.timeoutInterval > 120 {
            request.timeoutInterval = 60
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            switch error.code {
            case .cancelled:
                throw CancellationError()
            case .timedOut:
                throw AIChatError.unavailable("The provider took too long to respond. Try again.")
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost:
                throw AIChatError.unavailable("Could not reach the provider. Check your connection or make sure the local server is running.")
            default:
                throw AIChatError.unavailable("Could not reach the provider. \(error.localizedDescription)")
            }
        }

        guard let http = response as? HTTPURLResponse else {
            throw AIChatError.invalidResponse
        }

        var responseHeaders: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            responseHeaders[String(describing: key)] = String(describing: value)
        }
        return AIHTTPResponse(data: data, statusCode: http.statusCode, headers: responseHeaders)
    }
}
