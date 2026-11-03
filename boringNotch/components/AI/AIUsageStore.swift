//
//  AIUsageStore.swift
//  boringNotch
//
//  Single source of truth for tracked AI plans. Handles persistence,
//  signed-in account syncing, scheduled resets, and low-usage alerts.
//

import AppKit
import Combine
import Defaults
import Foundation
@preconcurrency import UserNotifications

@MainActor
final class AIUsageStore: ObservableObject {
    static let shared = AIUsageStore()

    @Published private(set) var entries: [AIUsageEntry]
    @Published private(set) var accounts: [AIProvider: AIAccount] = [:]
    @Published private(set) var syncing: Set<AIProvider> = []
    @Published private(set) var lastError: [AIProvider: String] = [:]
    @Published private(set) var lastLiveFetch: Date?
    /// Drives the sign-in sheet from `AIUsageSettings`.
    @Published var authPrompt: AISignInPrompt?

    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var signInTask: Task<Void, Never>?
    /// Guards against a cancelled sign-in finishing after a newer one starts.
    private var signInGeneration = 0

    private init() {
        entries = Defaults[.aiUsageEntries]

        for provider in AIProvider.liveProviders {
            if let account = AIAccountStore.load(provider) {
                accounts[provider] = account
            }
        }

        AIAuthService.shared.onPrompt = { [weak self] prompt in
            self?.authPrompt = prompt
        }

        refresh(notify: false)
        startTimer()

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                self?.refreshLiveIfNeeded()
            }
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            self?.refreshLiveIfNeeded(force: true)
        }
    }

    // MARK: - Read helpers

    var enabledEntries: [AIUsageEntry] {
        entries.filter(\.enabled)
    }

    var lowestRemaining: Double? {
        enabledEntries.map(\.clampedPercent).min()
    }

    var lowPlanCount: Int {
        let threshold = Defaults[.aiLowUsageThreshold]
        return enabledEntries.filter { $0.isLow(threshold: threshold) }.count
    }

    func entry(with id: UUID) -> AIUsageEntry? {
        entries.first { $0.id == id }
    }

    func account(for provider: AIProvider) -> AIAccount? {
        accounts[provider]
    }

    func isConnected(_ provider: AIProvider) -> Bool {
        accounts[provider] != nil
    }

    func isSyncing(_ provider: AIProvider) -> Bool {
        syncing.contains(provider)
    }

    func error(for provider: AIProvider) -> String? {
        lastError[provider]
    }

    // MARK: - Sign-in

    func connect(_ provider: AIProvider) {
        guard provider.supportsLiveUsage else { return }
        cancelSignIn()
        lastError[provider] = nil

        let addedEntry = !entries.contains(where: { $0.provider == provider })
        if addedEntry {
            add(provider)
        }

        let generation = signInGeneration
        signInTask = Task { [weak self] in
            guard let self else { return }
            do {
                let account = try await AIAuthService.shared.signIn(provider: provider)
                guard self.signInGeneration == generation else { return }
                try AIAccountStore.save(account)
                self.accounts[provider] = account
                self.authPrompt = nil
                self.syncEntry(with: account)
                await self.fetchLive(provider: provider, force: true)
            } catch is CancellationError {
                guard self.signInGeneration == generation else { return }
                self.authPrompt = nil
                if addedEntry { self.removePlaceholder(for: provider) }
            } catch AIAuthError.cancelled {
                guard self.signInGeneration == generation else { return }
                self.authPrompt = nil
                if addedEntry { self.removePlaceholder(for: provider) }
            } catch {
                guard self.signInGeneration == generation else { return }
                self.authPrompt = nil
                if addedEntry { self.removePlaceholder(for: provider) }
                self.lastError[provider] = error.localizedDescription
            }
        }
    }

    /// Drops a card that was only added to hold a sign-in that never completed.
    private func removePlaceholder(for provider: AIProvider) {
        guard let entry = entries.first(where: { $0.provider == provider }),
              entry.lastSyncDate == nil,
              entry.accountLabel == nil
        else { return }
        remove(id: entry.id)
    }

    func cancelSignIn() {
        signInGeneration &+= 1
        signInTask?.cancel()
        signInTask = nil
        authPrompt = nil
    }

    func disconnect(_ provider: AIProvider) {
        AIAccountStore.delete(provider)
        accounts[provider] = nil
        syncing.remove(provider)
        lastError[provider] = nil

        var updated = entries
        if let index = updated.firstIndex(where: { $0.provider == provider }) {
            updated[index].accountLabel = nil
            updated[index].lastSyncDate = nil
            updated[index].syncError = nil
            persist(updated)
        }
    }

    // MARK: - Live usage

    func refreshLiveIfNeeded(force: Bool = false) {
        guard Defaults[.aiLiveSync] else { return }

        let providers = AIProvider.liveProviders.filter { provider in
            accounts[provider] != nil && entries.contains { $0.provider == provider }
        }
        guard !providers.isEmpty else { return }

        if !force, let lastLiveFetch, Date().timeIntervalSince(lastLiveFetch) < 120 {
            return
        }

        lastLiveFetch = Date()
        for provider in providers {
            Task { [weak self] in
                await self?.fetchLive(provider: provider)
            }
        }
    }

    func fetchLive(provider: AIProvider, force: Bool = false) async {
        guard accounts[provider] != nil else { return }
        guard !syncing.contains(provider) else { return }

        if !force,
           let entry = entries.first(where: { $0.provider == provider }),
           let lastSync = entry.lastSyncDate,
           Date().timeIntervalSince(lastSync) < 60 {
            return
        }

        syncing.insert(provider)
        defer { syncing.remove(provider) }

        do {
            let account = try await AIAuthService.shared.validAccount(for: provider)
            accounts[provider] = account
            try? AIAccountStore.save(account)

            let usage = try await AIUsageAPI.fetch(provider: provider, account: account)
            apply(usage, provider: provider, account: account)
            lastError[provider] = nil
            lastLiveFetch = Date()
        } catch let error as AIAuthError {
            switch error {
            case .notSignedIn, .signInExpired:
                AIAccountStore.delete(provider)
                accounts[provider] = nil
            default:
                break
            }
            record(error.localizedDescription, for: provider)
        } catch {
            record(error.localizedDescription, for: provider)
        }
    }

    private func apply(_ usage: AILiveUsage, provider: AIProvider, account: AIAccount) {
        var updated = entries
        let percent = min(max(usage.percentRemaining, 0), 100)
        let planName = usage.planName ?? account.planName ?? ""
        let threshold = Defaults[.aiLowUsageThreshold]

        if let index = updated.firstIndex(where: { $0.provider == provider }) {
            let previousReset = updated[index].resetDate
            let resetChanged: Bool
            switch (previousReset, usage.resetDate) {
            case let (old?, new?):
                resetChanged = abs(old.timeIntervalSince(new)) > 60
            case (nil, nil):
                resetChanged = false
            default:
                resetChanged = true
            }

            updated[index].percentRemaining = percent
            updated[index].resetDate = usage.resetDate
            if !planName.isEmpty {
                updated[index].planName = planName
            }
            updated[index].accountLabel = account.accountLabel
            updated[index].lastSyncDate = Date()
            updated[index].syncError = nil
            if resetChanged || updated[index].clampedPercent > threshold {
                updated[index].lastAlertDate = nil
            }

            persist(updated)
            notifyIfNeeded(for: provider)
        }
    }

    private func syncEntry(with account: AIAccount) {
        var updated = entries
        if let index = updated.firstIndex(where: { $0.provider == account.provider }) {
            updated[index].accountLabel = account.accountLabel
            if let plan = account.planName, !plan.isEmpty {
                updated[index].planName = plan
            }
        } else {
            updated.append(
                AIUsageEntry(
                    provider: account.provider,
                    planName: account.planName ?? "",
                    accountLabel: account.accountLabel
                )
            )
        }
        persist(updated)
    }

    private func record(_ message: String, for provider: AIProvider) {
        lastError[provider] = message

        var updated = entries
        guard let index = updated.firstIndex(where: { $0.provider == provider }) else { return }
        updated[index].syncError = message
        persist(updated)
    }

    // MARK: - Mutations

    func update(id: UUID, _ change: (inout AIUsageEntry) -> Void) {
        var updated = entries
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        let previousReset = updated[index].resetDate
        change(&updated[index])
        updated[index].percentRemaining = updated[index].clampedPercent
        if updated[index].resetDate != previousReset {
            updated[index].lastAlertDate = nil
        }
        if updated[index].percentRemaining > Defaults[.aiLowUsageThreshold] {
            updated[index].lastAlertDate = nil
        }
        persist(updated)
    }

    func setPercent(id: UUID, to value: Double) {
        update(id: id) { $0.percentRemaining = min(max(value, 0), 100) }
    }

    func decrement(id: UUID, by amount: Double) {
        update(id: id) { $0.percentRemaining = max($0.clampedPercent - amount, 0) }
    }

    func add(_ provider: AIProvider) {
        guard !entries.contains(where: { $0.provider == provider }) else { return }
        var updated = entries
        let account = accounts[provider]
        updated.append(
            AIUsageEntry(
                provider: provider,
                planName: account?.planName ?? "",
                resetDate: Date().addingTimeInterval(provider.resetInterval),
                accountLabel: account?.accountLabel
            )
        )
        persist(updated)

        // A re-added provider that is already signed in should show real numbers right away.
        if account != nil {
            Task { [weak self] in
                await self?.fetchLive(provider: provider, force: true)
            }
        }
    }

    func remove(id: UUID) {
        persist(entries.filter { $0.id != id })
    }

    func remove(provider: AIProvider) {
        persist(entries.filter { $0.provider != provider })
    }

    func markAllFull() {
        var updated = entries
        for index in updated.indices {
            updated[index].percentRemaining = 100
            updated[index].lastAlertDate = nil
        }
        persist(updated)
    }

    func restartCountdowns() {
        var updated = entries
        let now = Date()
        for index in updated.indices where updated[index].resetDate != nil {
            updated[index].resetDate = now.addingTimeInterval(updated[index].provider.resetInterval)
            updated[index].lastAlertDate = nil
        }
        persist(updated)
    }

    func restoreDefaults() {
        persist(AIUsageEntry.defaultEntries)
    }

    // MARK: - Reset logic

    /// Advances expired manual windows, clears stale alert markers, and posts
    /// low-usage notifications when needed. Signed-in providers are left alone:
    /// their next sync supplies the authoritative window.
    func refresh(notify: Bool = true, now: Date = .now) {
        var updated = entries
        var didChange = false

        let autoReset = Defaults[.aiAutoReset]
        let alertsEnabled = Defaults[.aiLowUsageAlerts]
        let threshold = Defaults[.aiLowUsageThreshold]
        let liveProviders = Set(accounts.keys)

        for index in updated.indices {
            if !liveProviders.contains(updated[index].provider),
               let reset = updated[index].resetDate,
               reset <= now,
               autoReset {
                updated[index].resetDate = AIUsageEntry.nextReset(
                    after: now,
                    from: reset,
                    interval: updated[index].provider.resetInterval
                )
                updated[index].percentRemaining = 100
                updated[index].lastAlertDate = nil
                didChange = true
            }

            if updated[index].clampedPercent > threshold,
               updated[index].lastAlertDate != nil {
                updated[index].lastAlertDate = nil
                didChange = true
            }
        }

        if alertsEnabled && notify {
            for entry in updated
            where entry.enabled && entry.isLow(threshold: threshold) && entry.lastAlertDate == nil {
                postLowUsageAlert(for: entry)
                if let index = updated.firstIndex(where: { $0.id == entry.id }) {
                    updated[index].lastAlertDate = now
                    didChange = true
                }
            }
        }

        if didChange {
            persist(updated)
        }
    }

    private func notifyIfNeeded(for provider: AIProvider, now: Date = .now) {
        guard Defaults[.aiLowUsageAlerts] else { return }
        let threshold = Defaults[.aiLowUsageThreshold]

        var updated = entries
        guard let index = updated.firstIndex(where: { $0.provider == provider }) else { return }
        guard updated[index].enabled,
              updated[index].isLow(threshold: threshold),
              updated[index].lastAlertDate == nil
        else { return }

        postLowUsageAlert(for: updated[index])
        updated[index].lastAlertDate = now
        persist(updated)
    }

    // MARK: - Notifications

    func requestAlertAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func sendTestAlert() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "AI Usage is ready"
            content.body = "Low-usage alerts will appear here when a plan drops below your threshold."
            content.sound = .default
            center.add(
                UNNotificationRequest(
                    identifier: "ai-usage-test-\(UUID().uuidString)",
                    content: content,
                    trigger: nil
                )
            )
        }
    }

    private func postLowUsageAlert(for entry: AIUsageEntry) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "\(entry.provider.label) is running low"
            content.body = "\(Int(entry.clampedPercent.rounded()))% left — \(entry.resetText)."
            content.sound = .default

            let windowKey = entry.resetDate?.timeIntervalSince1970 ?? 0
            let request = UNNotificationRequest(
                identifier: "ai-low-\(entry.id.uuidString)-\(Int(windowKey))",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }

    // MARK: - Private

    private func persist(_ updated: [AIUsageEntry]) {
        entries = updated
        Defaults[.aiUsageEntries] = updated
    }

    private func startTimer() {
        let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refresh()
                if Date().timeIntervalSince(self.lastLiveFetch ?? .distantPast) >= 300 {
                    self.refreshLiveIfNeeded(force: true)
                }
            }
        }
        timer.tolerance = 5
        self.timer = timer
    }
}
