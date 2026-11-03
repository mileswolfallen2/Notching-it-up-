//
//  AIAuth.swift
//  boringNotch
//
//  OAuth / device-code sign-in for AI usage providers, plus local token storage.
//

import AppKit
import CryptoKit
import Foundation
import Network

// MARK: - Account

/// Credentials and identity for one signed-in provider. Tokens never touch Defaults;
/// they are stored in the app's sandboxed Application Support folder.
struct AIAccount: Codable, Equatable, Sendable {
    var provider: AIProvider
    var accountLabel: String
    var planName: String?
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    /// Provider-specific identity (ChatGPT account id, Claude organization id, …).
    var accountID: String?
    var updatedAt: Date = Date()
}

enum AISignInPrompt: Identifiable, Equatable {
    case browser(provider: AIProvider, url: URL)
    case deviceCode(provider: AIProvider, userCode: String, url: URL)

    var id: String {
        switch self {
        case .browser(let provider, _): return "browser-\(provider.rawValue)"
        case .deviceCode(let provider, _, _): return "device-\(provider.rawValue)"
        }
    }

    var provider: AIProvider {
        switch self {
        case .browser(let provider, _), .deviceCode(let provider, _, _): return provider
        }
    }
}

enum AIAuthError: LocalizedError {
    case cancelled
    case notSignedIn(AIProvider)
    case signInExpired(AIProvider)
    case unsupported(AIProvider)
    case invalidResponse
    case http(Int, String)
    case storage(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Sign-in was cancelled."
        case .notSignedIn(let provider):
            return "Sign in to \(provider.label) to load your usage."
        case .signInExpired(let provider):
            return "Your \(provider.label) session expired. Sign in again."
        case .unsupported(let provider):
            return "\(provider.label) doesn’t offer a usage sign-in. Track it manually."
        case .invalidResponse:
            return "The provider returned an unexpected response."
        case .http(let status, let body):
            let detail = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "Request failed with HTTP \(status)." : "HTTP \(status): \(detail)"
        case .storage(let message):
            return "Could not save the sign-in securely. \(message)"
        case .unavailable(let message):
            return message
        }
    }
}

// MARK: - Local account storage

/// Stores provider tokens outside the Keychain so rebuilding or updating the
/// ad-hoc signed app never triggers a Keychain access prompt.
enum AIAccountStore {
    private static let lock = NSLock()

    private static var directoryURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AI Usage", isDirectory: true)
    }

    private static var fileURL: URL? {
        directoryURL?.appendingPathComponent("accounts.json", isDirectory: false)
    }

    static func save(_ account: AIAccount) throws {
        lock.lock()
        defer { lock.unlock() }

        var accounts = readAllLocked()
        accounts[account.provider.rawValue] = account
        try writeLocked(accounts)
    }

    static func load(_ provider: AIProvider) -> AIAccount? {
        lock.lock()
        defer { lock.unlock() }
        return readAllLocked()[provider.rawValue]
    }

    static func delete(_ provider: AIProvider) {
        lock.lock()
        defer { lock.unlock() }

        var accounts = readAllLocked()
        guard accounts.removeValue(forKey: provider.rawValue) != nil else { return }
        try? writeLocked(accounts)
    }

    private static func readAllLocked() -> [String: AIAccount] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: AIAccount].self, from: data)) ?? [:]
    }

    private static func writeLocked(_ accounts: [String: AIAccount]) throws {
        guard let directory = directoryURL, let file = fileURL else {
            throw AIAuthError.storage("Application Support is unavailable.")
        }

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = try JSONEncoder().encode(accounts)
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: file.path
            )

            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableFile = file
            try? mutableFile.setResourceValues(resourceValues)
        } catch {
            throw AIAuthError.storage(error.localizedDescription)
        }
    }
}

// MARK: - HTTP

struct AIHTTPResponse {
    let data: Data
    let statusCode: Int
    let headers: [String: String]

    var isSuccess: Bool { (200..<300).contains(statusCode) }

    func jsonObject() -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        guard isSuccess else {
            throw AIAuthError.http(statusCode, String(decoding: data.prefix(400), as: UTF8.self))
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw AIAuthError.invalidResponse
        }
    }
}

enum AIHTTP {
    static func send(_ request: URLRequest, allowFailure: Bool = false) async throws -> AIHTTPResponse {
        var request = request
        if request.timeoutInterval <= 0 || request.timeoutInterval > 25 {
            request.timeoutInterval = 25
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIAuthError.invalidResponse }

        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            headers[String(describing: key)] = String(describing: value)
        }

        let result = AIHTTPResponse(data: data, statusCode: http.statusCode, headers: headers)
        if !allowFailure, !result.isSuccess {
            let text = String(decoding: data.prefix(400), as: UTF8.self)
            throw AIAuthError.http(http.statusCode, text)
        }
        return result
    }

    static func get(
        _ url: URL,
        headers: [String: String] = [:],
        allowFailure: Bool = false
    ) async throws -> AIHTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        return try await send(request, allowFailure: allowFailure)
    }

    static func postForm(
        _ url: URL,
        fields: [String: String],
        headers: [String: String] = [:],
        allowFailure: Bool = false
    ) async throws -> AIHTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        var allHeaders = [
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "application/json"
        ]
        allHeaders.merge(headers) { _, new in new }
        for (key, value) in allHeaders { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = formEncode(fields).data(using: .utf8)
        return try await send(request, allowFailure: allowFailure)
    }

    static func postJSON(
        _ url: URL,
        fields: [String: Any],
        headers: [String: String] = [:],
        allowFailure: Bool = false
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
        return try await send(request, allowFailure: allowFailure)
    }

    private static func formEncode(_ fields: [String: String]) -> String {
        fields
            .map { "\(encode($0.key))=\(encode($0.value))" }
            .sorted()
            .joined(separator: "&")
    }

    private static func encode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

// MARK: - OAuth helpers

struct PKCEPair {
    let verifier: String
    let challenge: String
}

enum PKCE {
    static func generate() -> PKCEPair {
        let verifier = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return PKCEPair(verifier: verifier, challenge: challenge)
    }
}

struct AIOAuthToken: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Double?
    let idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case idToken = "id_token"
    }

    var expiry: Date? {
        expiresIn.map { Date().addingTimeInterval($0) }
    }
}

enum AIJWT {
    static func payload<T: Decodable>(_ token: String, as type: T.Type) -> T? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    struct Expiry: Decodable {
        let exp: Double?
    }

    static func expiry(_ token: String) -> Date? {
        payload(token, as: Expiry.self)?.exp.map { Date(timeIntervalSince1970: $0) }
    }
}

// MARK: - Loopback callback server

/// A tiny one-shot HTTP server used as the OAuth redirect target.
final class LoopbackCallbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let expectedState: String
    private let callbackPath: String
    private let queue = DispatchQueue(label: "com.notchingitup.ai-oauth")
    private let lock = NSLock()
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var codeContinuation: CheckedContinuation<String, Error>?
    private var storedResult: Result<String, Error>?
    private(set) var port: UInt16 = 0

    private init(state: String, port: UInt16?, path: String) throws {
        expectedState = state
        callbackPath = path
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: .ipv4(.loopback),
            port: port.flatMap { NWEndpoint.Port(rawValue: $0) } ?? .any
        )
        listener = try NWListener(using: parameters)
    }

    static func start(
        state: String,
        port: UInt16? = nil,
        path: String = "/callback"
    ) async throws -> LoopbackCallbackServer {
        let server = try LoopbackCallbackServer(state: state, port: port, path: path)
        try await server.startListening()
        return server
    }

    var redirectURI: String { "http://localhost:\(port)\(callbackPath)" }

    func waitForCode() async throws -> String {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if let storedResult {
                    lock.unlock()
                    continuation.resume(with: storedResult)
                    return
                }
                codeContinuation = continuation
                lock.unlock()
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() {
        resolve(.failure(AIAuthError.cancelled))
        listener.cancel()
    }

    private func startListening() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            readyContinuation = continuation
            lock.unlock()

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let value = self.listener.port?.rawValue else {
                        self.finishReady(.failure(AIAuthError.unavailable("Could not open a sign-in callback port.")))
                        return
                    }
                    self.port = value
                    self.finishReady(.success(()))
                case .failed(let error):
                    self.finishReady(.failure(AIAuthError.unavailable(error.localizedDescription)))
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)
        }
    }

    private func finishReady(_ result: Result<Void, Error>) {
        lock.lock()
        guard let continuation = readyContinuation else {
            lock.unlock()
            return
        }
        readyContinuation = nil
        lock.unlock()
        continuation.resume(with: result)
    }

    private func resolve(_ result: Result<String, Error>) {
        lock.lock()
        if let continuation = codeContinuation {
            codeContinuation = nil
            lock.unlock()
            continuation.resume(with: result)
            return
        }
        if storedResult == nil {
            storedResult = result
        }
        lock.unlock()
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private static let headerLimit = 16_384

    private func receive(on connection: NWConnection, buffer: Data) {
        let remaining = max(Self.headerLimit - buffer.count, 1)
        connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var combined = buffer
            if let data { combined.append(data) }

            if combined.range(of: Data("\r\n\r\n".utf8)) != nil {
                guard let text = String(data: combined, encoding: .utf8),
                      let requestLine = text.components(separatedBy: "\r\n").first
                else {
                    self.respond(connection, status: "400 Bad Request", body: "Invalid callback.")
                    self.resolve(.failure(AIAuthError.invalidResponse))
                    return
                }
                self.handle(requestLine: requestLine, connection: connection)
            } else if isComplete || error != nil || combined.count >= Self.headerLimit {
                connection.cancel()
                self.resolve(.failure(AIAuthError.invalidResponse))
            } else {
                self.receive(on: connection, buffer: combined)
            }
        }
    }

    private func handle(requestLine: String, connection: NWConnection) {
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            respond(connection, status: "400 Bad Request", body: "Invalid callback.")
            resolve(.failure(AIAuthError.invalidResponse))
            return
        }

        let target = String(parts[1])
        guard let components = URLComponents(string: "http://localhost\(target)"),
              components.path == callbackPath
        else {
            respond(connection, status: "404 Not Found", body: "Not found.")
            resolve(.failure(AIAuthError.invalidResponse))
            return
        }

        let items = components.queryItems ?? []
        let code = items.first { $0.name == "code" }?.value
        let state = items.first { $0.name == "state" }?.value
        let error = items.first { $0.name == "error" }?.value

        if let error {
            respond(connection, status: "200 OK", body: "Sign-in was not completed. You can close this window.")
            resolve(.failure(AIAuthError.unavailable("Sign-in was not completed (\(error)).")))
            return
        }

        guard let code, !code.isEmpty, state == expectedState else {
            respond(connection, status: "400 Bad Request", body: "The sign-in response did not match this request.")
            resolve(.failure(AIAuthError.invalidResponse))
            return
        }

        respond(connection, status: "200 OK", body: "You’re signed in. You can close this window and return to Notching it up.")
        resolve(.success(code))
    }

    private func respond(_ connection: NWConnection, status: String, body: String) {
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:#101014;color:#f5f5f7;text-align:center}div{max-width:360px;padding:24px}p{color:#a1a1aa;line-height:1.5}</style>
        </head><body><div><h2>Notching it up</h2><p>\(body)</p></div></body></html>
        """
        let length = Data(html.utf8).count
        let response = [
            "HTTP/1.1 \(status)",
            "Content-Type: text/html; charset=utf-8",
            "Content-Length: \(length)",
            "Connection: close",
            "",
            html
        ].joined(separator: "\r\n")
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    deinit {
        listener.cancel()
    }
}

// MARK: - Sign-in service

@MainActor
final class AIAuthService {
    static let shared = AIAuthService()

    /// Called when a flow needs to show a browser or device-code prompt.
    var onPrompt: ((AISignInPrompt) -> Void)?

    private init() {}

    // MARK: Public

    func signIn(provider: AIProvider) async throws -> AIAccount {
        switch provider {
        case .claude:
            return try await signInClaude()
        case .codex:
            return try await signInCodex()
        case .antigravity:
            return try await signInAntigravity()
        case .copilot:
            return try await signInCopilot()
        case .cursor, .gemini, .opencode:
            throw AIAuthError.unsupported(provider)
        }
    }

    /// Returns a usable account, refreshing the access token first when it is close to expiry.
    func validAccount(for provider: AIProvider) async throws -> AIAccount {
        guard var account = AIAccountStore.load(provider) else {
            throw AIAuthError.notSignedIn(provider)
        }

        let needsRefresh = account.expiresAt.map { $0.timeIntervalSinceNow < 120 } ?? false
        if needsRefresh {
            account = try await refresh(account)
            try AIAccountStore.save(account)
        }
        return account
    }

    // MARK: Claude

    private static let claudeClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let claudeAuthorizeURL = URL(string: "https://claude.ai/oauth/authorize")!
    private static let claudeTokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let claudeUsageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let claudeProfileURL = URL(string: "https://api.anthropic.com/api/oauth/profile")!
    private static let claudeScopes = "user:profile"

    private func signInClaude() async throws -> AIAccount {
        let pkce = PKCE.generate()
        let state = UUID().uuidString
        let server = try await LoopbackCallbackServer.start(state: state)
        defer { server.cancel() }

        var components = URLComponents(url: Self.claudeAuthorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.claudeClientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: server.redirectURI),
            URLQueryItem(name: "scope", value: Self.claudeScopes),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code", value: "true")
        ]
        guard let url = components.url else { throw AIAuthError.invalidResponse }
        present(.browser(provider: .claude, url: url))

        let code = try await server.waitForCode()

        let tokenResponse = try await AIHTTP.postJSON(Self.claudeTokenURL, fields: [
            "grant_type": "authorization_code",
            "client_id": Self.claudeClientID,
            "code": code,
            "state": state,
            "redirect_uri": server.redirectURI,
            "code_verifier": pkce.verifier
        ])
        let token = try tokenResponse.decode(AIOAuthToken.self)

        let profileResponse = try await AIHTTP.get(
            Self.claudeProfileURL,
            headers: claudeHeaders(token.accessToken, includeBeta: true)
        )
        let profile = try? profileResponse.decode(ClaudeProfile.self)

        return AIAccount(
            provider: .claude,
            accountLabel: profile?.account.email ?? profile?.email ?? "Claude account",
            planName: claudePlanName(from: profile),
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: token.expiry ?? AIJWT.expiry(token.accessToken),
            accountID: profile?.organization?.uuid
        )
    }

    private func claudePlanName(from profile: ClaudeProfile?) -> String? {
        guard let organization = profile?.organization else { return "Claude" }
        let type = organization.organizationType?.lowercased() ?? ""

        let base: String
        if type.contains("ultra") {
            base = "Claude Ultra"
        } else if type.contains("max") {
            base = "Claude Max"
        } else if type.contains("pro") {
            base = "Claude Pro"
        } else if type.contains("team") {
            base = "Claude Team"
        } else if type.contains("enterprise") {
            base = "Claude Enterprise"
        } else {
            return "Claude"
        }

        // The rate-limit tier carries the multiplier ("…max_20x").
        if let tier = organization.rateLimitTier,
           let multiplier = tier.range(of: #"\d+x"#, options: .regularExpression) {
            return "\(base) \(tier[multiplier])"
        }
        return base
    }

    private func claudeHeaders(_ token: String, includeBeta: Bool) -> [String: String] {
        var headers = [
            "Authorization": "Bearer \(token)",
            "Accept": "application/json"
        ]
        if includeBeta {
            headers["anthropic-beta"] = "oauth-2025-04-20"
        }
        return headers
    }

    // MARK: Codex / ChatGPT

    private static let codexClientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private static let codexAuthorizeURL = URL(string: "https://auth.openai.com/oauth/authorize")!
    private static let codexTokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    private static let codexScopes = "openid profile email offline_access"

    private func signInCodex() async throws -> AIAccount {
        let pkce = PKCE.generate()
        let state = UUID().uuidString

        if let server = try? await LoopbackCallbackServer.start(state: state, port: 1455, path: "/auth/callback") {
            defer { server.cancel() }
            var components = URLComponents(url: Self.codexAuthorizeURL, resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: Self.codexClientID),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "redirect_uri", value: server.redirectURI),
                URLQueryItem(name: "scope", value: Self.codexScopes),
                URLQueryItem(name: "code_challenge", value: pkce.challenge),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "id_token_add_organizations", value: "true"),
                URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
                URLQueryItem(name: "originator", value: "pi")
            ]
            guard let url = components.url else { throw AIAuthError.invalidResponse }
            present(.browser(provider: .codex, url: url))

            let code = try await server.waitForCode()
            return try await exchangeCodex(code: code, verifier: pkce.verifier, redirectURI: server.redirectURI)
        }

        return try await signInCodexDevice()
    }

    private func signInCodexDevice() async throws -> AIAccount {
        let startResponse = try await AIHTTP.postJSON(
            URL(string: "https://auth.openai.com/api/accounts/deviceauth/usercode")!,
            fields: ["client_id": Self.codexClientID]
        )
        guard let json = startResponse.jsonObject(),
              let deviceAuthID = json["device_auth_id"] as? String,
              let userCode = json["user_code"] as? String
        else { throw AIAuthError.invalidResponse }

        let interval = (json["interval"] as? Double) ?? Double(json["interval"] as? String ?? "") ?? 5
        let verificationURL = URL(string: "https://auth.openai.com/codex/device")!
        present(.deviceCode(provider: .codex, userCode: userCode, url: verificationURL))

        let deadline = Date().addingTimeInterval(900)
        var delay = max(2, interval)

        while Date() < deadline {
            try Task.checkCancellation()
            let response = try await AIHTTP.postJSON(
                URL(string: "https://auth.openai.com/api/accounts/deviceauth/token")!,
                fields: [
                    "device_auth_id": deviceAuthID,
                    "user_code": userCode
                ],
                allowFailure: true
            )

            if let body = response.jsonObject(),
               let authorizationCode = body["authorization_code"] as? String,
               let codeVerifier = body["code_verifier"] as? String {
                return try await exchangeCodex(
                    code: authorizationCode,
                    verifier: codeVerifier,
                    redirectURI: "https://auth.openai.com/deviceauth/callback"
                )
            }

            let errorCode = response.jsonObject()?["error"] as? String
            if errorCode == "slow_down" {
                delay += 5
            } else if response.statusCode == 403 || response.statusCode == 404
                        || errorCode == "deviceauth_authorization_pending" {
                // Keep waiting for the user to approve the code.
            } else if errorCode == "expired_token" {
                throw AIAuthError.unavailable("The device code expired. Try signing in again.")
            } else if !response.isSuccess && errorCode == nil {
                throw AIAuthError.http(response.statusCode, String(decoding: response.data.prefix(200), as: UTF8.self))
            }

            try await Task.sleep(nanoseconds: UInt64(min(delay, 20) * 1_000_000_000))
        }
        throw AIAuthError.unavailable("The device code expired. Try signing in again.")
    }

    private func exchangeCodex(code: String, verifier: String, redirectURI: String) async throws -> AIAccount {
        let response = try await AIHTTP.postForm(Self.codexTokenURL, fields: [
            "grant_type": "authorization_code",
            "client_id": Self.codexClientID,
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": redirectURI
        ])
        let token = try response.decode(AIOAuthToken.self)

        let auth = AIJWT.payload(token.accessToken, as: CodexAccessClaims.self)?.auth
        let email = token.idToken.flatMap { AIJWT.payload($0, as: CodexIDClaims.self)?.email }
        let accountID = auth?.chatgptAccountID

        return AIAccount(
            provider: .codex,
            accountLabel: email ?? "ChatGPT account",
            planName: "ChatGPT",
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: token.expiry ?? AIJWT.expiry(token.accessToken),
            accountID: accountID
        )
    }

    // MARK: Antigravity / Google

    private static let antigravityClientID = "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"
    private static let antigravityClientSecret = "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"
    private static let antigravityTokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    private static let antigravityScopes = "https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/userinfo.email"

    private func signInAntigravity() async throws -> AIAccount {
        let pkce = PKCE.generate()
        let state = UUID().uuidString
        let server = try await LoopbackCallbackServer.start(state: state, port: 51121, path: "/oauth-callback")
        defer { server.cancel() }

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.antigravityClientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: server.redirectURI),
            URLQueryItem(name: "scope", value: Self.antigravityScopes),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        guard let url = components.url else { throw AIAuthError.invalidResponse }
        present(.browser(provider: .antigravity, url: url))

        let code = try await server.waitForCode()

        let response = try await AIHTTP.postForm(Self.antigravityTokenURL, fields: [
            "client_id": Self.antigravityClientID,
            "client_secret": Self.antigravityClientSecret,
            "code": code,
            "grant_type": "authorization_code",
            "redirect_uri": server.redirectURI,
            "code_verifier": pkce.verifier
        ])
        let token = try response.decode(AIOAuthToken.self)

        let userInfoResponse = try? await AIHTTP.get(
            URL(string: "https://www.googleapis.com/oauth2/v1/userinfo?alt=json")!,
            headers: ["Authorization": "Bearer \(token.accessToken)"]
        )
        let userInfo = userInfoResponse.flatMap { try? $0.decode(GoogleUserInfo.self) }

        return AIAccount(
            provider: .antigravity,
            accountLabel: userInfo?.email ?? "Google account",
            planName: "Google AI",
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: token.expiry ?? AIJWT.expiry(token.accessToken),
            accountID: userInfo?.id ?? userInfo?.email
        )
    }

    // MARK: GitHub Copilot

    private static let copilotClientID = "Iv1.b507a08c87ecfe98"

    private func signInCopilot() async throws -> AIAccount {
        let startResponse = try await AIHTTP.postForm(
            URL(string: "https://github.com/login/device/code")!,
            fields: [
                "client_id": Self.copilotClientID,
                "scope": "read:user"
            ],
            headers: ["User-Agent": "Notching it up"]
        )
        guard let json = startResponse.jsonObject(),
              let deviceCode = json["device_code"] as? String,
              let userCode = json["user_code"] as? String
        else { throw AIAuthError.invalidResponse }

        let verificationURL = URL(string: (json["verification_uri"] as? String) ?? "https://github.com/login/device")!
        let interval = (json["interval"] as? Double) ?? Double(json["interval"] as? String ?? "") ?? 5
        let expiresIn = (json["expires_in"] as? Double) ?? Double(json["expires_in"] as? String ?? "") ?? 900

        present(.deviceCode(provider: .copilot, userCode: userCode, url: verificationURL))

        let deadline = Date().addingTimeInterval(expiresIn)
        var delay = max(2, interval)
        var accessToken: String?

        while Date() < deadline, accessToken == nil {
            try Task.checkCancellation()
            let response = try await AIHTTP.postForm(
                URL(string: "https://github.com/login/oauth/access_token")!,
                fields: [
                    "client_id": Self.copilotClientID,
                    "device_code": deviceCode,
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
                ],
                headers: ["User-Agent": "Notching it up"],
                allowFailure: true
            )

            let body = response.jsonObject() ?? [:]
            if let token = body["access_token"] as? String {
                accessToken = token
                break
            }

            switch body["error"] as? String {
            case "authorization_pending":
                break
            case "slow_down":
                delay += 5
            case "expired_token":
                throw AIAuthError.unavailable("The GitHub device code expired. Try again.")
            case "access_denied":
                throw AIAuthError.cancelled
            case let error?:
                throw AIAuthError.unavailable("GitHub sign-in failed (\(error)).")
            case nil:
                if !response.isSuccess {
                    throw AIAuthError.http(response.statusCode, String(decoding: response.data.prefix(200), as: UTF8.self))
                }
            }

            try await Task.sleep(nanoseconds: UInt64(min(delay, 20) * 1_000_000_000))
        }

        guard let token = accessToken else {
            throw AIAuthError.unavailable("The GitHub device code expired. Try again.")
        }

        let profileResponse = try? await AIHTTP.get(
            URL(string: "https://api.github.com/user")!,
            headers: [
                "Authorization": "token \(token)",
                "Accept": "application/vnd.github+json",
                "User-Agent": "Notching it up"
            ]
        )
        let login = profileResponse.flatMap { try? $0.decode(GitHubUser.self).login } ?? "GitHub account"

        return AIAccount(
            provider: .copilot,
            accountLabel: login,
            planName: "GitHub Copilot",
            accessToken: token,
            refreshToken: nil,
            expiresAt: nil
        )
    }

    // MARK: Refresh

    private func refresh(_ account: AIAccount) async throws -> AIAccount {
        switch account.provider {
        case .claude:
            guard let refreshToken = account.refreshToken else { throw AIAuthError.signInExpired(.claude) }
            let response: AIHTTPResponse
            do {
                response = try await AIHTTP.postJSON(Self.claudeTokenURL, fields: [
                    "grant_type": "refresh_token",
                    "refresh_token": refreshToken,
                    "client_id": Self.claudeClientID,
                    "scope": Self.claudeScopes
                ])
            } catch let error as AIAuthError {
                throw mapRefreshError(error, provider: .claude)
            }
            let token = try response.decode(AIOAuthToken.self)
            var updated = account
            updated.accessToken = token.accessToken
            updated.refreshToken = token.refreshToken ?? refreshToken
            updated.expiresAt = token.expiry ?? AIJWT.expiry(token.accessToken)
            updated.updatedAt = Date()
            return updated

        case .codex:
            guard let refreshToken = account.refreshToken else { throw AIAuthError.signInExpired(.codex) }
            let response: AIHTTPResponse
            do {
                response = try await AIHTTP.postForm(Self.codexTokenURL, fields: [
                    "grant_type": "refresh_token",
                    "client_id": Self.codexClientID,
                    "refresh_token": refreshToken
                ])
            } catch let error as AIAuthError {
                throw mapRefreshError(error, provider: .codex)
            }
            let token = try response.decode(AIOAuthToken.self)
            var updated = account
            updated.accessToken = token.accessToken
            updated.refreshToken = token.refreshToken ?? refreshToken
            updated.expiresAt = token.expiry ?? AIJWT.expiry(token.accessToken)
            updated.updatedAt = Date()
            return updated

        case .antigravity:
            guard let refreshToken = account.refreshToken else { throw AIAuthError.signInExpired(.antigravity) }
            let response: AIHTTPResponse
            do {
                response = try await AIHTTP.postForm(Self.antigravityTokenURL, fields: [
                    "client_id": Self.antigravityClientID,
                    "client_secret": Self.antigravityClientSecret,
                    "refresh_token": refreshToken,
                    "grant_type": "refresh_token"
                ])
            } catch let error as AIAuthError {
                throw mapRefreshError(error, provider: .antigravity)
            }
            let token = try response.decode(AIOAuthToken.self)
            var updated = account
            updated.accessToken = token.accessToken
            updated.refreshToken = token.refreshToken ?? refreshToken
            updated.expiresAt = token.expiry ?? AIJWT.expiry(token.accessToken)
            updated.updatedAt = Date()
            return updated

        case .copilot, .cursor, .gemini, .opencode:
            return account
        }
    }

    private func mapRefreshError(_ error: AIAuthError, provider: AIProvider) -> AIAuthError {
        if case .http(let status, _) = error, [400, 401, 403].contains(status) {
            return .signInExpired(provider)
        }
        return error
    }

    // MARK: Prompt

    private func present(_ prompt: AISignInPrompt) {
        onPrompt?(prompt)
        if case .browser(_, let url) = prompt {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Provider payloads

private struct ClaudeProfile: Decodable {
    struct Account: Decodable {
        let uuid: String
        let email: String?
    }

    struct Organization: Decodable {
        let uuid: String?
        let organizationType: String?
        let rateLimitTier: String?

        enum CodingKeys: String, CodingKey {
            case uuid
            case organizationType = "organization_type"
            case rateLimitTier = "rate_limit_tier"
        }
    }

    let account: Account
    let organization: Organization?
    let email: String?
}

private struct CodexAccessClaims: Decodable {
    struct Auth: Decodable {
        let chatgptAccountID: String?

        enum CodingKeys: String, CodingKey {
            case chatgptAccountID = "chatgpt_account_id"
        }
    }

    let auth: Auth?

    enum CodingKeys: String, CodingKey {
        case auth = "https://api.openai.com/auth"
    }
}

private struct CodexIDClaims: Decodable {
    let email: String?
}

private struct GoogleUserInfo: Decodable {
    let id: String?
    let email: String?
}

private struct GitHubUser: Decodable {
    let login: String
}
