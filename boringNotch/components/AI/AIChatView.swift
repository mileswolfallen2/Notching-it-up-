//
//  AIChatView.swift
//  boringNotch
//
//  Compact chat for the AI tab. Providers reuse the accounts signed in for usage.
//

import Defaults
import SwiftUI

// MARK: - Chat panel

struct AIChatPanel: View {
    @ObservedObject private var store = AIChatStore.shared
    @ObservedObject private var usageStore = AIUsageStore.shared

    @Default(.aiChatProvider) private var provider
    @Default(.aiChatUseAppleIntelligence) private var useAppleIntelligence
    @Default(.aiChatOllamaModel) private var ollamaModel
    @Default(.aiChatClaudeModel) private var claudeModel
    @Default(.aiChatCodexModel) private var codexModel
    @Default(.aiChatAntigravityModel) private var antigravityModel
    @Default(.aiChatCopilotModel) private var copilotModel

    @State private var draft = ""
    @FocusState private var composerFocused: Bool

    private var isConfigured: Bool {
        available(provider)
    }

    private var canSend: Bool {
        isConfigured
            && !store.isSending
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var modelLabel: String {
        switch provider {
        case .apple:       return "On-device"
        case .ollama:      return resolved(ollamaModel, fallback: provider.defaultModel)
        case .claude:      return resolved(claudeModel, fallback: provider.defaultModel)
        case .codex:       return resolved(codexModel, fallback: provider.defaultModel)
        case .antigravity: return resolved(antigravityModel, fallback: provider.defaultModel)
        case .copilot:     return resolved(copilotModel, fallback: provider.defaultModel)
        }
    }

    private var placeholder: String {
        isConfigured ? "Ask \(provider.label)…" : "Set up \(provider.label) first"
    }

    var body: some View {
        VStack(spacing: 6) {
            toolbar
            messages
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            chooseFallbackProviderIfNeeded()
            NotchTextInput.begin()
        }
        .onDisappear {
            NotchTextInput.end()
        }
        .onChange(of: useAppleIntelligence) { _, enabled in
            if !enabled && provider == .apple {
                chooseFallbackProviderIfNeeded()
            }
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(AIChatProvider.allCases) { item in
                    Button {
                        provider = item
                        store.errorText = nil
                        if available(item) {
                            composerFocused = true
                        }
                    } label: {
                        Label(providerMenuLabel(item), systemImage: item.iconName)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: provider.iconName)
                        .font(.system(size: 10, weight: .semibold))

                    Text(provider.label)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))

                    Circle()
                        .fill(isConfigured ? Color.green.opacity(0.8) : Color.orange.opacity(0.75))
                        .frame(width: 4, height: 4)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .foregroundStyle(.white.opacity(0.86))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Choose chat provider")
            .accessibilityLabel("Chat provider: \(provider.label)")
            .accessibilityHint("Choose which provider answers chat")

            Text(modelLabel)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.38))
                .lineLimit(1)

            Spacer(minLength: 4)

            if store.isSending {
                Button {
                    store.stop()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Stop replying")
                .accessibilityLabel("Stop reply")
            }

            if !store.messages.isEmpty {
                Button {
                    store.clear()
                    composerFocused = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New chat")
                .accessibilityLabel("New chat")
                .accessibilityHint("Clears the current conversation")
            }
        }
    }

    // MARK: Messages

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    if store.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.messages) { message in
                            AIChatBubble(message: message)
                        }
                    }

                    if store.isSending {
                        HStack(spacing: 5) {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.7)
                            Text("\(provider.label) is thinking…")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        .padding(.vertical, 2)
                    }

                    if let error = store.errorText, !error.isEmpty {
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 8))
                            Text(error)
                                .lineLimit(3)
                        }
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("chat-bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)
            .onChange(of: store.messages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: store.isSending) { _, _ in scrollToBottom(proxy) }
            .onChange(of: store.errorText) { _, _ in scrollToBottom(proxy) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: provider.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))

                Text(isConfigured ? "Ask \(provider.label) anything" : "Connect \(provider.label) to chat")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }

            Text(emptyHint)
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.44))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if !isConfigured {
                Button("Open AI settings") {
                    openAIUsageSettings()
                }
                .buttonStyle(.plain)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.68))
                .padding(.top, 1)
            }
        }
        .padding(.vertical, 4)
    }

    private var emptyHint: String {
        switch provider {
        case .apple:
            if !AIChatProvider.appleSupported {
                return "Apple Intelligence needs macOS 26 or later on a supported Mac."
            }
            return useAppleIntelligence
                ? "Answers run on this Mac using Apple Intelligence."
                : "Apple Intelligence is turned off in AI settings."
        case .ollama:
            return "Uses \(resolved(ollamaModel, fallback: provider.defaultModel)) from \(AIChatService.ollamaBaseURL()). Start Ollama before asking."
        case .claude, .codex, .antigravity, .copilot:
            return "Reuses the \(provider.label) account already signed in for usage. Sign in from AI settings to enable it."
        }
    }

    // MARK: Composer

    private var composer: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .focused($composerFocused)
                .disabled(!isConfigured || store.isSending)
                .onSubmit(submit)
                .accessibilityLabel("Message \(provider.label)")
                .accessibilityHint("Type a message, then press Return to send")

            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(canSend ? Color.white.opacity(0.9) : Color.white.opacity(0.22))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .help("Send")
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(composerFocused ? 0.20 : 0.10), lineWidth: 1)
        )
    }

    // MARK: Actions

    private func submit() {
        guard canSend else { return }
        let text = draft
        draft = ""
        composerFocused = true
        store.send(text, provider: provider)
    }

    private func chooseFallbackProviderIfNeeded() {
        guard !available(provider) else { return }
        if let first = AIChatProvider.allCases.first(where: { available($0) }) {
            provider = first
        }
    }

    private func providerMenuLabel(_ item: AIChatProvider) -> String {
        if available(item) { return item.label }
        if item == .apple {
            return AIChatProvider.appleSupported ? "\(item.label) · off" : "\(item.label) · unsupported"
        }
        return "\(item.label) · set up"
    }

    private func available(_ candidate: AIChatProvider) -> Bool {
        switch candidate {
        case .apple:
            return AIChatProvider.appleAvailable
        case .ollama:
            return true
        case .claude, .codex, .antigravity, .copilot:
            guard let accountProvider = candidate.accountProvider else { return false }
            return usageStore.isConnected(accountProvider)
        }
    }

    private func resolved(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(BoringMotion.animation(.easeOut(duration: 0.2))) {
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        }
    }
}

// MARK: - Bubble

private struct AIChatBubble: View {
    let message: AIChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 46) }

            Text(message.content)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(isUser ? 0.92 : 0.86))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(isUser ? 0.12 : 0.045))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(isUser ? 0 : 0.08), lineWidth: 1)
                )
                .accessibilityLabel("\(isUser ? "You" : "Assistant"): \(message.content)")

            if !isUser { Spacer(minLength: 46) }
        }
    }
}

// MARK: - Settings

struct AIChatSettingsSection: View {
    @ObservedObject private var usageStore = AIUsageStore.shared

    @Default(.aiChatProvider) private var provider
    @Default(.aiChatUseAppleIntelligence) private var useAppleIntelligence
    @Default(.aiChatOllamaBaseURL) private var ollamaBaseURL
    @Default(.aiChatOllamaModel) private var ollamaModel
    @Default(.aiChatClaudeModel) private var claudeModel
    @Default(.aiChatCodexModel) private var codexModel
    @Default(.aiChatAntigravityModel) private var antigravityModel
    @Default(.aiChatCopilotModel) private var copilotModel
    @Default(.aiChatSystemPrompt) private var systemPrompt

    @State private var ollamaStatus: String?
    @State private var checkingOllama = false

    private var fallbackProvider: AIChatProvider {
        AIChatProvider.allCases.first { item in
            if item == .ollama { return true }
            guard let accountProvider = item.accountProvider else { return false }
            return usageStore.isConnected(accountProvider)
        } ?? .ollama
    }

    private var providerStatus: String {
        switch provider {
        case .apple:
            guard AIChatProvider.appleSupported else {
                return "Unavailable — needs macOS 26 or later"
            }
            return useAppleIntelligence ? "Available on this Mac" : "Turned off"
        case .ollama:
            return ollamaStatus ?? "Local server"
        case .claude, .codex, .antigravity, .copilot:
            guard let accountProvider = provider.accountProvider else { return "Unavailable" }
            if let account = usageStore.account(for: accountProvider) {
                return "Signed in as \(account.accountLabel)"
            }
            return "Sign in under Accounts above"
        }
    }

    var body: some View {
        Section {
            Defaults.Toggle("Use Apple Intelligence when available", key: .aiChatUseAppleIntelligence)

            Picker("Default provider", selection: $provider) {
                ForEach(AIChatProvider.allCases) { item in
                    Text(item.label).tag(item)
                }
            }

            LabeledContent("Status", value: providerStatus)
                .font(.caption)

            if provider == .apple && !AIChatProvider.appleSupported {
                Label(
                    "Apple Intelligence requires macOS 26 or later on a supported Mac. Choose another provider for now.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if provider == .apple && AIChatProvider.appleSupported && !useAppleIntelligence {
                Label(
                    "Apple Intelligence is off. Turn the switch above back on to use it for chat.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if provider == .ollama {
                TextField(
                    "Server",
                    text: $ollamaBaseURL,
                    prompt: Text("http://localhost:11434")
                )
                .textFieldStyle(.roundedBorder)

                TextField(
                    "Model",
                    text: $ollamaModel,
                    prompt: Text(AIChatProvider.ollama.defaultModel)
                )
                .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Button(checkingOllama ? "Checking…" : "Check connection") {
                        checkingOllama = true
                        Task {
                            ollamaStatus = await AIChatService.checkOllama()
                            checkingOllama = false
                        }
                    }
                    .controlSize(.small)
                    .disabled(checkingOllama)

                    if let ollamaStatus {
                        Text(ollamaStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            DisclosureGroup("Model overrides") {
                TextField(
                    "Claude",
                    text: $claudeModel,
                    prompt: Text(AIChatProvider.claude.defaultModel)
                )
                .textFieldStyle(.roundedBorder)

                TextField(
                    "ChatGPT",
                    text: $codexModel,
                    prompt: Text(AIChatProvider.codex.defaultModel)
                )
                .textFieldStyle(.roundedBorder)

                TextField(
                    "Antigravity",
                    text: $antigravityModel,
                    prompt: Text(AIChatProvider.antigravity.defaultModel)
                )
                .textFieldStyle(.roundedBorder)

                TextField(
                    "Copilot",
                    text: $copilotModel,
                    prompt: Text(AIChatProvider.copilot.defaultModel)
                )
                .textFieldStyle(.roundedBorder)

                TextField(
                    "System prompt",
                    text: $systemPrompt,
                    axis: .vertical
                )
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
            }
        } header: {
            Text("Chat")
        } footer: {
            Text("Chat appears in the AI tab next to usage. It reuses the Claude, ChatGPT, Antigravity, and Copilot sign-ins above. Apple Intelligence and Ollama answer on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: provider) { _, _ in
            ollamaStatus = nil
        }
        .onChange(of: useAppleIntelligence) { _, enabled in
            if !enabled && provider == .apple {
                provider = fallbackProvider
            }
        }
    }
}
