//
//  AIUsageView.swift
//  boringNotch
//
//  Droppy-style AI plan usage panel for the notch.
//

import Defaults
import SwiftUI

/// Opens the settings window directly on the AI Usage pane.
private func openAIUsageSettings() {
    DispatchQueue.main.async {
        SettingsWindowController.shared.showWindow()
        NotificationCenter.default.post(name: .openAISettings, object: nil)
    }
}

// MARK: - Notch panel

struct AIUsageView: View {
    @ObservedObject private var store = AIUsageStore.shared
    @Default(.aiSortByLowest) private var sortByLowest
    @Default(.aiCompactCards) private var compactCards

    private var visibleEntries: [AIUsageEntry] {
        let base = store.entries.filter(\.enabled)
        return sortByLowest
            ? base.sorted { $0.clampedPercent < $1.clampedPercent }
            : base
    }

    private var summaryText: String {
        guard let lowest = store.lowestRemaining else { return "No plans" }
        let lowestText = "\(Int(lowest.rounded()))% lowest"
        if store.lowPlanCount > 0 {
            let lowNoun = store.lowPlanCount == 1 ? "plan low" : "plans low"
            return "\(store.lowPlanCount) \(lowNoun) · \(lowestText)"
        }
        let count = store.enabledEntries.count
        return "\(count) \(count == 1 ? "plan" : "plans") · \(lowestText)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header

            if visibleEntries.isEmpty {
                emptyState
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    ScrollView(.horizontal) {
                        HStack(spacing: compactCards ? 7 : 9) {
                            ForEach(visibleEntries) { entry in
                                card(for: entry)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    .scrollIndicators(.never)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.effectiveAccent)

            Text("AI Usage")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Text(summaryText)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(store.lowPlanCount > 0 ? .orange : .white.opacity(0.42))
                .lineLimit(1)

            if !store.syncing.isEmpty {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
            }

            Spacer()

            Button {
                openAIUsageSettings()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Configure AI usage")
        }
    }

    @ViewBuilder
    private func card(for entry: AIUsageEntry) -> some View {
        if compactCards {
            AICompactUsageCard(entry: entry)
        } else {
            AIUsageCard(entry: entry)
        }
    }

    private var emptyState: some View {
        Button {
            openAIUsageSettings()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.06))
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.effectiveAccent)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Track your AI limits")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Sign in to Claude, ChatGPT, Copilot or Antigravity, or add any plan manually.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(0.12),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Usage ring card

private struct AIUsageCard: View {
    let entry: AIUsageEntry

    @ObservedObject private var store = AIUsageStore.shared
    @Default(.aiShowPlanName) private var showPlanName
    @Default(.aiShowResetTime) private var showResetTime
    @State private var appeared = false
    @State private var hovering = false

    private var progress: CGFloat {
        CGFloat(entry.clampedPercent / 100)
    }

    private var percentageText: String {
        "\(Int(entry.clampedPercent.rounded()))%"
    }

    private var showsReset: Bool {
        showResetTime && entry.resetDate != nil
    }

    var body: some View {
        VStack(spacing: 4) {
            ring

            HStack(spacing: 3) {
                Image(systemName: entry.provider.iconName)
                    .font(.system(size: 8, weight: .semibold))
                Text(entry.provider.label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if store.isConnected(entry.provider) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 4, height: 4)
                        .help("Live from your account")
                }
            }
            .foregroundStyle(.white)

            if showPlanName {
                Text(entry.displayPlanName)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            if showsReset {
                HStack(spacing: 2) {
                    Image(systemName: "clock")
                        .font(.system(size: 7, weight: .semibold))
                    Text(entry.resetText)
                        .font(.system(size: 8, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.06)))
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .frame(width: 112, height: 106, alignment: .top)
        .background(cardBackground)
        .overlay(cardBorder)
        .scaleEffect(hovering ? 1.025 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: hovering)
        .onHover { hovering = $0 }
        .contextMenu { AIUsageCardMenu(entry: entry) }
        .help("\(entry.provider.label) — \(percentageText) left. \(entry.resetText).")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.provider.label), \(percentageText) remaining, \(entry.resetText)")
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 4)

            Circle()
                .trim(from: 0, to: appeared ? progress : 0)
                .stroke(
                    AngularGradient(
                        colors: [
                            entry.statusColor.opacity(0.55),
                            entry.statusColor,
                            entry.statusColor.opacity(0.8)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: entry.statusColor.opacity(0.35), radius: 3)
                .animation(.easeOut(duration: 0.65), value: appeared)
                .animation(.easeOut(duration: 0.35), value: entry.clampedPercent)

            Text(percentageText)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .frame(width: 42, height: 42)
        .onAppear { appeared = true }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        entry.provider.tint.opacity(0.14),
                        Color.white.opacity(0.035)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        entry.provider.tint.opacity(hovering ? 0.5 : 0.22),
                        Color.white.opacity(0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
}

private struct AICompactUsageCard: View {
    let entry: AIUsageEntry

    @ObservedObject private var store = AIUsageStore.shared
    @Default(.aiShowResetTime) private var showResetTime
    @State private var appeared = false
    @State private var hovering = false

    private var progress: CGFloat {
        CGFloat(entry.clampedPercent / 100)
    }

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 3)

                Circle()
                    .trim(from: 0, to: appeared ? progress : 0)
                    .stroke(
                        entry.statusColor,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.55), value: appeared)

                Text("\(Int(entry.clampedPercent.rounded()))%")
                    .font(.system(size: 7.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .frame(width: 30, height: 30)
            .onAppear { appeared = true }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(entry.provider.label)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if store.isConnected(entry.provider) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 4, height: 4)
                    }
                }

                Text(showsReset ? entry.resetText : entry.displayPlanName)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(width: 136, height: 46)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            entry.provider.tint.opacity(0.12),
                            Color.white.opacity(0.035)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    entry.provider.tint.opacity(hovering ? 0.45 : 0.2),
                    lineWidth: 1
                )
        )
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: hovering)
        .onHover { hovering = $0 }
        .contextMenu { AIUsageCardMenu(entry: entry) }
        .help("\(entry.provider.label) — \(Int(entry.clampedPercent.rounded()))% left. \(entry.resetText).")
    }

    private var showsReset: Bool {
        showResetTime && entry.resetDate != nil
    }
}

private struct AIUsageCardMenu: View {
    let entry: AIUsageEntry
    @ObservedObject private var store = AIUsageStore.shared

    var body: some View {
        if store.isConnected(entry.provider) {
            Button(store.isSyncing(entry.provider) ? "Refreshing…" : "Refresh usage") {
                Task { await store.fetchLive(provider: entry.provider, force: true) }
            }
            .disabled(store.isSyncing(entry.provider))

            if let account = store.account(for: entry.provider) {
                Text("Signed in as \(account.accountLabel)")
            }
            if let error = store.error(for: entry.provider) {
                Text(error)
            }
            Divider()
        }

        Button("Mark as full") {
            store.setPercent(id: entry.id, to: 100)
        }
        Button("Used 5%") {
            store.decrement(id: entry.id, by: 5)
        }
        Button("Used 10%") {
            store.decrement(id: entry.id, by: 10)
        }
        Button("Reset in 5 hours") {
            store.update(id: entry.id) {
                $0.resetDate = Date().addingTimeInterval(5 * 60 * 60)
            }
        }
        Divider()
        Button("Open AI settings") {
            openAIUsageSettings()
        }
    }
}

// MARK: - Settings

struct AIUsageSettings: View {
    @ObservedObject private var store = AIUsageStore.shared

    @Default(.showAITab) private var showAITab
    @Default(.aiLiveSync) private var liveSync
    @Default(.aiSortByLowest) private var sortByLowest
    @Default(.aiShowPlanName) private var showPlanName
    @Default(.aiShowResetTime) private var showResetTime
    @Default(.aiCompactCards) private var compactCards
    @Default(.aiAutoReset) private var autoReset
    @Default(.aiLowUsageAlerts) private var lowUsageAlerts
    @Default(.aiLowUsageThreshold) private var lowThreshold

    private var availableProviders: [AIProvider] {
        AIProvider.allCases.filter { provider in
            !store.entries.contains { $0.provider == provider }
        }
    }

    private var promptBinding: Binding<AISignInPrompt?> {
        Binding(
            get: { store.authPrompt },
            set: { value in
                if value == nil {
                    store.cancelSignIn()
                } else {
                    store.authPrompt = value
                }
            }
        )
    }

    var body: some View {
        Form {
            connectionSection
            overviewSection
            displaySection
            automationSection
            trackedSection
            maintenanceSection
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("AI Usage")
        .sheet(item: promptBinding) { prompt in
            AISignInSheet(prompt: prompt) {
                store.cancelSignIn()
            }
        }
    }

    // MARK: Accounts

    private var connectionSection: some View {
        Section {
            Defaults.Toggle(key: .aiLiveSync) {
                Label("Sync usage from signed-in accounts", systemImage: "arrow.triangle.2.circlepath")
            }

            ForEach(AIProvider.liveProviders) { provider in
                accountRow(for: provider)
            }

            if !store.accounts.isEmpty {
                HStack(spacing: 8) {
                    if let last = store.lastLiveFetch {
                        Text("Last synced \(last.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Waiting for the first sync")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Refresh now") {
                        store.refreshLiveIfNeeded(force: true)
                    }
                    .controlSize(.small)
                }
            }
        } header: {
            Text("Accounts")
        } footer: {
            Text("Sign in once and Notching it up reads the same usage numbers your provider shows. Tokens are kept in your Mac’s Keychain and never leave this device. Cursor, Gemini and OpenCode are tracked manually.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func accountRow(for provider: AIProvider) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(provider.tint.opacity(0.16))
                Image(systemName: provider.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(provider.tint)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(provider.label)
                        .fontWeight(.medium)

                    if store.isConnected(provider) {
                        Text("Live")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.green.opacity(0.14)))
                    }
                }

                if let account = store.account(for: provider) {
                    Text(account.accountLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let error = store.error(for: provider) {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                    }
                } else {
                    Text(provider.signInHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if store.isSyncing(provider) {
                ProgressView()
                    .controlSize(.small)
            } else if store.isConnected(provider) {
                Button("Refresh") {
                    Task { await store.fetchLive(provider: provider, force: true) }
                }
                .controlSize(.small)

                Button("Sign out", role: .destructive) {
                    store.disconnect(provider)
                }
                .controlSize(.small)
            } else {
                Button("Sign in") {
                    store.connect(provider)
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(!liveSync)
            }
        }
    }

    // MARK: Overview

    private var overviewSection: some View {
        Section {
            Defaults.Toggle(key: .showAITab) {
                Label("Show AI Usage tab in the notch", systemImage: "sparkles")
            }

            if showAITab {
                preview
            }
        } header: {
            Text("AI Usage")
        } footer: {
            Text("Rings show how much is left and when each plan refreshes. Signed-in providers update automatically; manual plans follow their own countdown.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Notch preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if store.lowPlanCount > 0 {
                    Label("\(store.lowPlanCount) low", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    if store.enabledEntries.isEmpty {
                        Text("No plans visible")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.45))
                            .padding(.vertical, 30)
                            .padding(.horizontal, 12)
                    } else {
                        ForEach(store.enabledEntries) { entry in
                            if compactCards {
                                AICompactUsageCard(entry: entry)
                            } else {
                                AIUsageCard(entry: entry)
                            }
                        }
                    }
                }
                .padding(10)
            }
            .scrollIndicators(.never)
            .frame(height: compactCards ? 66 : 126)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: Display

    private var displaySection: some View {
        Section {
            Toggle("Sort by lowest remaining", isOn: $sortByLowest)
            Toggle("Show plan names", isOn: $showPlanName)
            Toggle("Show reset times", isOn: $showResetTime)
            Toggle("Compact cards", isOn: $compactCards)
        } header: {
            Text("Display")
        } footer: {
            Text("Sorting and card style apply to both the notch panel and the preview above.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Automation

    private var automationSection: some View {
        Section {
            Toggle("Reset plans automatically", isOn: $autoReset)

            Toggle("Notify when a plan runs low", isOn: $lowUsageAlerts)
                .onChange(of: lowUsageAlerts) { _, enabled in
                    if enabled {
                        store.requestAlertAuthorization()
                    }
                }

            if lowUsageAlerts {
                HStack(spacing: 10) {
                    Text("Alert at")
                    Slider(value: $lowThreshold, in: 5...50, step: 5)
                    Text("\(Int(lowThreshold))%")
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }

                Button("Send test notification") {
                    store.sendTestAlert()
                }
            }
        } header: {
            Text("Automation")
        } footer: {
            Text("When a window ends, the plan returns to 100% and its countdown advances automatically. Low-usage alerts are sent once per window.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Tracked providers

    private var trackedSection: some View {
        Section {
            if store.entries.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.secondary)
                    Text("No AI providers added yet")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            ForEach(store.entries) { entry in
                AIUsageEntryEditor(
                    entry: binding(for: entry.id),
                    isLive: store.isConnected(entry.provider),
                    isSyncing: store.isSyncing(entry.provider),
                    error: store.error(for: entry.provider),
                    onRefresh: {
                        Task { await store.fetchLive(provider: entry.provider, force: true) }
                    },
                    onRemove: { store.remove(id: entry.id) }
                )
            }

            Menu {
                ForEach(availableProviders) { provider in
                    Button {
                        store.add(provider)
                    } label: {
                        Label(provider.label, systemImage: provider.iconName)
                    }
                }
            } label: {
                Label("Add AI provider", systemImage: "plus.circle.fill")
            }
            .disabled(availableProviders.isEmpty)
        } header: {
            HStack {
                Text("Tracked AIs")
                Spacer()
                Text("\(store.entries.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("Click a provider to edit its plan name, usage, and reset time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Maintenance

    private var maintenanceSection: some View {
        Section {
            Button("Mark all plans as full") {
                store.markAllFull()
            }

            Button("Restart all countdowns") {
                store.restartCountdowns()
            }

            Button("Restore default providers") {
                store.restoreDefaults()
            }
        } header: {
            Text("Maintenance")
        }
    }

    private func binding(for id: UUID) -> Binding<AIUsageEntry> {
        Binding(
            get: {
                store.entry(with: id) ?? AIUsageEntry(provider: .claude)
            },
            set: { newValue in
                store.update(id: id) { $0 = newValue }
            }
        )
    }
}

private struct AIUsageEntryEditor: View {
    @Binding var entry: AIUsageEntry
    let isLive: Bool
    let isSyncing: Bool
    let error: String?
    let onRefresh: () -> Void
    let onRemove: () -> Void

    @Default(.aiLowUsageThreshold) private var lowThreshold
    @State private var isExpanded = false

    private var resetEnabled: Binding<Bool> {
        Binding(
            get: { entry.resetDate != nil },
            set: { enabled in
                entry.resetDate = enabled
                    ? (entry.resetDate ?? entry.defaultResetDate)
                    : nil
            }
        )
    }

    private var resetDate: Binding<Date> {
        Binding(
            get: { entry.resetDate ?? entry.defaultResetDate },
            set: { entry.resetDate = $0 }
        )
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                if isLive {
                    liveDetails
                } else {
                    manualDetails
                }

                HStack {
                    Button(role: .destructive, action: onRemove) {
                        Label("Remove", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    Text(isLive ? "Live from your account" : "Window: \(entry.provider.resetIntervalLabel)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            .padding(.vertical, 6)
        } label: {
            rowLabel
        }
    }

    @ViewBuilder
    private var liveDetails: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Synced automatically")
                    .font(.caption.weight(.medium))

                if let last = entry.lastSyncDate {
                    Text("· \(last.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(isSyncing ? "Refreshing…" : "Refresh now", action: onRefresh)
                    .controlSize(.small)
                    .disabled(isSyncing)
            }

            if let account = entry.accountLabel {
                LabeledContent("Account", value: account)
                    .font(.caption)
            }

            LabeledContent("Plan", value: entry.displayPlanName)
                .font(.caption)

            LabeledContent("Remaining", value: "\(Int(entry.clampedPercent.rounded()))%")
                .font(.caption)

            if let reset = entry.resetDate {
                LabeledContent(
                    "Resets",
                    value: reset.formatted(.dateTime.weekday(.abbreviated).hour().minute())
                )
                .font(.caption)
            }

            if let error, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var manualDetails: some View {
        if entry.provider.supportsLiveUsage {
            Text("Sign in from Accounts above to keep this plan in sync automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        TextField(
            "Plan name",
            text: $entry.planName,
            prompt: Text(entry.provider.defaultPlanName)
        )
        .textFieldStyle(.roundedBorder)

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Remaining")
                Spacer()
                Text("\(Int(entry.clampedPercent.rounded()))%")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(entry.statusColor)
            }

            Slider(value: $entry.percentRemaining, in: 0...100, step: 1)
                .tint(entry.statusColor)

            HStack(spacing: 6) {
                ForEach([100, 75, 50, 25, 0], id: \.self) { value in
                    Button("\(value)%") {
                        entry.percentRemaining = Double(value)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            Toggle("Reset time", isOn: resetEnabled)

            if entry.resetDate != nil {
                HStack(spacing: 8) {
                    DatePicker(
                        "",
                        selection: resetDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()

                    Button("In \(entry.provider.resetIntervalLabel)") {
                        entry.resetDate = entry.defaultResetDate
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Button("Clear") {
                        entry.resetDate = nil
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var rowLabel: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(entry.provider.tint.opacity(0.16))
                Image(systemName: entry.provider.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(entry.provider.tint)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(entry.provider.label)
                        .fontWeight(.medium)

                    if isLive {
                        Text("Live")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.green.opacity(0.14)))
                    }

                    if entry.isLow(threshold: lowThreshold) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }

                    if error != nil {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                }

                HStack(spacing: 4) {
                    Text(entry.displayPlanName)
                    Text("·")
                    Text(entry.resetText)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("\(Int(entry.clampedPercent.rounded()))%")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(entry.statusColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(entry.statusColor.opacity(0.14))
                )

            Toggle("", isOn: $entry.enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .help(entry.enabled ? "Hide from the notch" : "Show in the notch")
        }
    }
}

// MARK: - Sign-in sheet

struct AISignInSheet: View {
    let prompt: AISignInPrompt
    let onCancel: () -> Void

    @Environment(\.openURL) private var openURL

    private var provider: AIProvider { prompt.provider }

    private var title: String {
        switch prompt {
        case .browser:
            return "Sign in to \(provider.label)"
        case .deviceCode:
            return "Connect \(provider.label)"
        }
    }

    private var subtitle: String {
        switch prompt {
        case .browser:
            return "A browser window is open. Finish signing in there."
        case .deviceCode:
            return "Enter the code below on \(provider.label)’s website."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(provider.tint.opacity(0.16))
                    Image(systemName: provider.iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(provider.tint)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            switch prompt {
            case .browser(_, let url):
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your browser should have opened automatically. If it didn’t, use the button below.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Open Browser Again") {
                        openURL(url)
                    }
                }

            case .deviceCode(_, let userCode, let url):
                VStack(alignment: .leading, spacing: 10) {
                    Text("Enter this code on the provider’s site:")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Text(userCode)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )

                    Button(openButtonTitle(for: url)) {
                        openURL(url)
                    }
                }
            }

            HStack(spacing: 9) {
                ProgressView()
                    .controlSize(.small)
                Text("Waiting for approval…")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(22)
        .frame(width: 430)
        .interactiveDismissDisabled()
    }

    private func openButtonTitle(for url: URL) -> String {
        switch provider {
        case .copilot: return "Open GitHub"
        case .codex:   return "Open ChatGPT"
        case .claude:  return "Open Claude"
        case .antigravity: return "Open Google"
        default: return "Open Provider"
        }
    }
}
