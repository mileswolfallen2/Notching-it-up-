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
        // On a cold open the pane starts observing only after the window mounts.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .openAISettings, object: nil)
        }
    }
}

// MARK: - Notch panel

struct AIUsageView: View {
    @ObservedObject private var store = AIUsageStore.shared
    @Default(.aiSortByLowest) private var sortByLowest
    @Default(.aiCompactCards) private var compactCards

    private var visibleEntries: [AIUsageEntry] {
        let base = store.notchEntries
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
        let count = store.notchEntries.count
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
                .foregroundStyle(.white.opacity(0.9))

            Text("AI Usage")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Text(summaryText)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(store.lowPlanCount > 0 ? 0.9 : 0.42))
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
                        .foregroundStyle(.white.opacity(0.85))
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Track your AI limits")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Sign in to Claude, ChatGPT, Copilot or Antigravity, or show manual plans in AI settings.")
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
    @Default(.aiColorStyle) private var colorStyle
    @State private var appeared = false
    @State private var hovering = false

    private var progress: CGFloat {
        CGFloat(entry.clampedPercent / 100)
    }

    private var percentageText: String {
        "\(Int(entry.clampedPercent.rounded()))%"
    }

    private var ringColor: Color {
        colorStyle.color(for: entry.provider, percentRemaining: entry.clampedPercent)
    }

    var body: some View {
        VStack(spacing: 7) {
            ring

            Text(entry.provider.label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 106, height: 104)
        .background(cardBackground)
        .overlay(cardBorder)
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: hovering)
        .onHover { hovering = $0 }
        .contextMenu { AIUsageCardMenu(entry: entry) }
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.provider.label), \(percentageText) remaining, \(entry.resetText)")
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 4)

            Circle()
                .trim(from: 0, to: appeared ? progress : 0)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.65), value: appeared)
                .animation(.easeOut(duration: 0.35), value: entry.clampedPercent)

            Text(percentageText)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .frame(width: 62, height: 62)
        .onAppear { appeared = true }
    }

    private var helpText: String {
        var text = "\(entry.provider.label) — \(percentageText) left. \(entry.resetText)."
        if let error = store.error(for: entry.provider) {
            text += " \(error)"
        }
        return text
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(hovering ? 0.075 : 0.045))
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(
                Color.white.opacity(hovering ? 0.24 : 0.10),
                lineWidth: 1
            )
    }
}

private struct AICompactUsageCard: View {
    let entry: AIUsageEntry

    @ObservedObject private var store = AIUsageStore.shared
    @Default(.aiColorStyle) private var colorStyle
    @State private var appeared = false
    @State private var hovering = false

    private var progress: CGFloat {
        CGFloat(entry.clampedPercent / 100)
    }

    private var percentageText: String {
        "\(Int(entry.clampedPercent.rounded()))%"
    }

    private var ringColor: Color {
        colorStyle.color(for: entry.provider, percentRemaining: entry.clampedPercent)
    }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 3)

                Circle()
                    .trim(from: 0, to: appeared ? progress : 0)
                    .stroke(
                        ringColor,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.55), value: appeared)
                    .animation(.easeOut(duration: 0.35), value: entry.clampedPercent)

                Text(percentageText)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)
            .onAppear { appeared = true }

            Text(entry.provider.label)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 84, height: 80)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.075 : 0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(hovering ? 0.24 : 0.10),
                    lineWidth: 1
                )
        )
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: hovering)
        .onHover { hovering = $0 }
        .contextMenu { AIUsageCardMenu(entry: entry) }
        .help(
            store.error(for: entry.provider).map { "\(entry.provider.label) — \(percentageText) left. \($0)" }
                ?? "\(entry.provider.label) — \(percentageText) left. \(entry.resetText)."
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.provider.label), \(percentageText) remaining, \(entry.resetText)")
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
        } else if entry.provider.supportsLiveUsage {
            Button("Sign in for live usage…") {
                openAIUsageSettings()
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
    @Default(.aiSortByLowest) private var sortByLowest
    @Default(.aiCompactCards) private var compactCards
    @Default(.aiColorStyle) private var colorStyle
    @Default(.aiShowManualPlans) private var showManualPlans
    @Default(.aiAutoReset) private var autoReset
    @Default(.aiLowUsageAlerts) private var lowUsageAlerts
    @Default(.aiLowUsageThreshold) private var lowThreshold

    private var availableProviders: [AIProvider] {
        AIProvider.allCases.filter { provider in
            !store.entries.contains { $0.provider == provider }
        }
    }

    private var previewEntries: [AIUsageEntry] {
        let base = store.notchEntries
        return sortByLowest
            ? base.sorted { $0.clampedPercent < $1.clampedPercent }
            : base
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
        .tint(.primary)
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
                        for provider in AIProvider.liveProviders where store.isConnected(provider) {
                            Task { await store.fetchLive(provider: provider, force: true) }
                        }
                    }
                    .controlSize(.small)
                }
            }
        } header: {
            Text("Accounts")
        } footer: {
            Text("Sign in once and Notching it up reads the same usage numbers your provider shows. Tokens stay in this app’s private storage and are only sent to your provider. Cursor, Gemini and OpenCode are tracked manually.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func accountRow(for provider: AIProvider) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                Image(systemName: provider.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.7))
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(provider.label)
                        .fontWeight(.medium)

                    if store.isConnected(provider) {
                        Text("Live")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }
                }

                if let account = store.account(for: provider) {
                    Text(account.accountLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(provider.signInHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = store.error(for: provider) {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
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

                Button("Sign out") {
                    store.disconnect(provider)
                }
                .controlSize(.small)
                .foregroundStyle(.secondary)
            } else {
                Button(store.error(for: provider) == nil ? "Sign in" : "Sign in again") {
                    store.connect(provider)
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
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
            Text("Signed-in providers appear automatically. Manual plans stay out of the notch unless you turn them on below.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notch preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    if previewEntries.isEmpty {
                        Text("No plans visible")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.45))
                            .padding(.vertical, 30)
                            .padding(.horizontal, 12)
                    } else {
                        ForEach(previewEntries) { entry in
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
            .frame(height: compactCards ? 100 : 124)
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
            Toggle("Compact rings", isOn: $compactCards)

            Picker("Ring color", selection: $colorStyle) {
                ForEach(AIUsageColorStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Show manual plans in the notch", isOn: $showManualPlans)
        } header: {
            Text("Display")
        } footer: {
            Text("Signed-in providers always appear. Manual plans stay hidden until you turn them on. Sorting and card size apply to the notch panel and the preview above.")
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
                        if store.accounts[provider] == nil {
                            showManualPlans = true
                        }
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
            Text("Click a provider to view live usage or adjust a manual plan.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Maintenance

    private var maintenanceSection: some View {
        Section {
            Menu {
                Button("Mark all plans as full") {
                    store.markAllFull()
                }
                Button("Restart all countdowns") {
                    store.restartCountdowns()
                }
                Button("Restore default providers") {
                    store.restoreDefaults()
                }
            } label: {
                Text("Maintenance actions")
            }
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
                    Button(action: onRemove) {
                        Label("Remove", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)

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
                    .foregroundStyle(.primary.opacity(0.7))
                Text(entry.lastSyncDate == nil ? "Checking your account…" : "Synced automatically")
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
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(.primary)
            }

            Slider(value: $entry.percentRemaining, in: 0...100, step: 1)
                .tint(.primary)

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
                    .fill(Color.primary.opacity(0.06))
                Image(systemName: entry.provider.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.7))
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(entry.provider.label)
                        .fontWeight(.medium)

                    if isLive {
                        Text("Live")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }

                    if entry.isLow(threshold: lowThreshold) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.primary.opacity(0.7))
                    }

                    if error != nil {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.primary.opacity(0.7))
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
                .foregroundStyle(.primary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.07))
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
                        .fill(Color.primary.opacity(0.06))
                    Image(systemName: provider.iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.7))
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
