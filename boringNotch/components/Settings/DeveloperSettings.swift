//
//  DeveloperSettings.swift
//  boringNotch
//

import AppKit
import AVFoundation
import CoreBluetooth
import EventKit
import SwiftUI
import UserNotifications

/// Hidden settings pane used while testing the app. It is only reachable after
/// selecting About and pressing Command-7.
struct DeveloperSettings: View {
    private enum PermissionKind: String, CaseIterable, Identifiable {
        case calendar
        case reminders
        case camera
        case bluetooth
        case accessibility
        case notifications
        case automation

        var id: String { rawValue }

        var title: String {
            switch self {
            case .calendar:
                return "Calendar"
            case .reminders:
                return "Reminders"
            case .camera:
                return "Camera"
            case .bluetooth:
                return "Bluetooth"
            case .accessibility:
                return "Accessibility"
            case .notifications:
                return "Notifications"
            case .automation:
                return "Automation"
            }
        }

        var icon: String {
            switch self {
            case .calendar:
                return "calendar"
            case .reminders:
                return "checklist"
            case .camera:
                return "camera"
            case .bluetooth:
                return "antenna.radiowaves.left.and.right"
            case .accessibility:
                return "accessibility"
            case .notifications:
                return "bell"
            case .automation:
                return "terminal"
            }
        }

        var tccService: String? {
            switch self {
            case .calendar:
                return "Calendar"
            case .reminders:
                return "Reminders"
            case .camera:
                return "Camera"
            case .bluetooth:
                return "Bluetooth"
            case .accessibility:
                return "Accessibility"
            case .automation:
                return "AppleEvents"
            case .notifications:
                return nil
            }
        }

        var privacyURL: URL? {
            switch self {
            case .calendar:
                return URL(
                    string:
                        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Calendars"
                )
            case .reminders:
                return URL(
                    string:
                        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Reminders"
                )
            case .camera:
                return URL(
                    string:
                        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Camera"
                )
            case .bluetooth:
                return URL(
                    string:
                        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Bluetooth"
                )
            case .accessibility:
                return URL(
                    string:
                        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
                )
            case .notifications:
                return URL(
                    string:
                        "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
                )
            case .automation:
                return URL(
                    string:
                        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation"
                )
            }
        }
    }

    private enum PermissionAction {
        case request
        case resetAndRequest
        case openSettings
    }

    private struct PermissionState {
        let text: String
        let tint: Color
        let action: PermissionAction
    }

    @State private var calendarStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(
        for: .event)
    @State private var reminderStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(
        for: .reminder)
    @State private var cameraStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(
        for: .video)
    @State private var bluetoothAuthorization: CBManagerAuthorization = CBManager.authorization
    @State private var accessibilityGranted = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    @State private var eventStore = EKEventStore()
    @State private var bluetoothRequester = BluetoothPermissionRequester()
    @State private var busyPermission: PermissionKind?
    @State private var actionMessage: String?
    @State private var didCopyReport = false
    @State private var showResetPermissionsConfirmation = false
    @State private var showResetPermissionsResult = false
    @State private var showResetDataConfirmation = false

    let lock: () -> Void

    var body: some View {
        Form {
            developerModeSection
            permissionsSection
            diagnosticsSection
            maintenanceSection
            dangerZoneSection
        }
        .navigationTitle("Developer")
        .task {
            await refreshPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
        { _ in
            Task { await refreshPermissions() }
        }
        .confirmationDialog(
            "Reset all permissions?",
            isPresented: $showResetPermissionsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset Permissions", role: .destructive) {
                Task { await resetAllPermissions() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Calendar, Reminders, Camera, Bluetooth, Accessibility, and Automation decisions will be cleared. macOS will ask again the next time the app requests access. Notification settings must be changed in System Settings."
            )
        }
        .confirmationDialog(
            "Reset all app data?",
            isPresented: $showResetDataConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset and Relaunch", role: .destructive) {
                AppReset.reset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This clears settings, AI sign-ins, and the shelf index. Files on disk are not deleted. The app will relaunch."
            )
        }
        .alert("Permissions reset", isPresented: $showResetPermissionsResult) {
            Button("Restart Now") {
                ApplicationRelauncher.restart()
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text(
                "Some permissions may require a restart before they can be requested again."
            )
        }
    }

    // MARK: - Sections

    private var developerModeSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Developer mode")
                    Text("Select About and press Command-7 to unlock this panel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Lock Panel") {
                    lock()
                }
                .controlSize(.small)
            }
        }
    }

    private var permissionsSection: some View {
        Section {
            ForEach(PermissionKind.allCases) { kind in
                permissionRow(kind)
            }

            if let actionMessage {
                Text(actionMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Open Privacy Settings") {
                openURL("x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension")
            }
            .controlSize(.small)
        } header: {
            Text("Permissions")
        } footer: {
            Text(
                "Reset & Ask clears the saved permission decision so macOS can prompt again. Notifications are managed by System Settings and cannot be reset from the app."
            )
        }
    }

    private var diagnosticsSection: some View {
        Section {
            diagnosticRow("Version", Bundle.main.releaseVersionNumber ?? "Unknown")
            diagnosticRow("Build", Bundle.main.buildVersionNumber ?? "Unknown")
            diagnosticRow("Bundle ID", Bundle.main.bundleIdentifier ?? "Unknown")
            diagnosticRow("macOS", ProcessInfo.processInfo.operatingSystemVersionString)
            diagnosticRow("Architecture", architecture)
            diagnosticRow("Sandbox", isSandboxed ? "Enabled" : "Disabled")
            diagnosticRow("Displays", "\(NSScreen.screens.count)")
            diagnosticRow("AI accounts", "\(AIUsageStore.shared.accounts.count)")
            diagnosticRow("Bluetooth devices", "\(BluetoothActivityManager.shared.connectedDevices.count)")

            pathRow("App bundle", Bundle.main.bundleURL.path)
            pathRow("Data folder", dataFolder.path)
            pathRow("Crash reports", crashReportsFolder.path)

            HStack {
                Button {
                    copyDiagnostics()
                } label: {
                    Label(
                        didCopyReport ? "Copied" : "Copy Report",
                        systemImage: didCopyReport ? "checkmark" : "doc.on.doc"
                    )
                }
                .controlSize(.small)

                Spacer()

                Button {
                    NSWorkspace.shared.open(dataFolder)
                } label: {
                    Label("Data Folder", systemImage: "folder")
                }
                .controlSize(.small)

                Button {
                    NSWorkspace.shared.open(crashReportsFolder)
                } label: {
                    Label("Crash Reports", systemImage: "doc.text.magnifyingglass")
                }
                .controlSize(.small)
            }
        } header: {
            Text("Diagnostics")
        } footer: {
            Text("Copy Report includes the values above and the current permission states.")
        }
    }

    private var maintenanceSection: some View {
        Section {
            Button {
                ApplicationRelauncher.restart()
            } label: {
                Label("Restart App", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
        } header: {
            Text("Maintenance")
        }
    }

    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                showResetPermissionsConfirmation = true
            } label: {
                Label("Reset All Permissions", systemImage: "arrow.counterclockwise")
            }
            .controlSize(.small)

            Button(role: .destructive) {
                showResetDataConfirmation = true
            } label: {
                Label("Reset All App Data", systemImage: "trash")
            }
            .controlSize(.small)
        } header: {
            Text("Danger Zone")
        } footer: {
            Text(
                "Resetting app data restores the first-run state and relaunches the app. It does not delete files that were added to the shelf."
            )
        }
    }

    // MARK: - Permission rows

    private func permissionRow(_ kind: PermissionKind) -> some View {
        let state = permissionState(for: kind)

        return HStack(spacing: 12) {
            Image(systemName: kind.icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title)
                Text(state.text)
                    .font(.caption)
                    .foregroundStyle(state.tint)
            }

            Spacer(minLength: 8)

            if busyPermission == kind {
                ProgressView()
                    .controlSize(.small)
            } else if let title = actionTitle(for: state.action) {
                Button(title) {
                    Task { await perform(state.action, for: kind) }
                }
                .controlSize(.small)
                .disabled(busyPermission != nil)
            }
        }
    }

    private func actionTitle(for action: PermissionAction) -> String? {
        switch action {
        case .request:
            return "Request"
        case .resetAndRequest:
            return "Reset & Ask"
        case .openSettings:
            return "Open Settings"
        }
    }

    private func permissionState(for kind: PermissionKind) -> PermissionState {
        switch kind {
        case .calendar:
            return eventState(calendarStatus)
        case .reminders:
            return eventState(reminderStatus)
        case .camera:
            switch cameraStatus {
            case .authorized:
                return PermissionState(text: "Granted", tint: .green, action: .openSettings)
            case .denied:
                return PermissionState(text: "Denied", tint: .red, action: .resetAndRequest)
            case .restricted:
                return PermissionState(text: "Restricted", tint: .red, action: .openSettings)
            case .notDetermined:
                return PermissionState(text: "Not requested", tint: .secondary, action: .request)
            @unknown default:
                return PermissionState(text: "Unknown", tint: .secondary, action: .openSettings)
            }
        case .bluetooth:
            switch bluetoothAuthorization {
            case .allowedAlways:
                return PermissionState(text: "Granted", tint: .green, action: .openSettings)
            case .denied:
                return PermissionState(text: "Denied", tint: .red, action: .resetAndRequest)
            case .restricted:
                return PermissionState(text: "Restricted", tint: .red, action: .openSettings)
            case .notDetermined:
                return PermissionState(text: "Not requested", tint: .secondary, action: .request)
            @unknown default:
                return PermissionState(text: "Unknown", tint: .secondary, action: .openSettings)
            }
        case .accessibility:
            return accessibilityGranted
                ? PermissionState(text: "Granted", tint: .green, action: .openSettings)
                : PermissionState(text: "Not granted", tint: .orange, action: .request)
        case .notifications:
            switch notificationStatus {
            case .authorized:
                return PermissionState(text: "Allowed", tint: .green, action: .openSettings)
            case .provisional:
                return PermissionState(text: "Allowed quietly", tint: .orange, action: .openSettings)
            case .ephemeral:
                return PermissionState(text: "Temporary", tint: .orange, action: .openSettings)
            case .denied:
                return PermissionState(text: "Denied", tint: .red, action: .openSettings)
            case .notDetermined:
                return PermissionState(text: "Not requested", tint: .secondary, action: .request)
            @unknown default:
                return PermissionState(text: "Unknown", tint: .secondary, action: .openSettings)
            }
        case .automation:
            return PermissionState(
                text: "Ask on first use", tint: .secondary, action: .openSettings)
        }
    }

    private func eventState(_ status: EKAuthorizationStatus) -> PermissionState {
        switch status {
        case .fullAccess:
            return PermissionState(text: "Full access", tint: .green, action: .openSettings)
        case .writeOnly:
            return PermissionState(text: "Write only", tint: .orange, action: .openSettings)
        case .denied:
            return PermissionState(text: "Denied", tint: .red, action: .resetAndRequest)
        case .restricted:
            return PermissionState(text: "Restricted", tint: .red, action: .openSettings)
        case .notDetermined:
            return PermissionState(text: "Not requested", tint: .secondary, action: .request)
        default:
            return PermissionState(text: "Unknown", tint: .secondary, action: .openSettings)
        }
    }

    // MARK: - Permission actions

    private func perform(_ action: PermissionAction, for kind: PermissionKind) async {
        switch action {
        case .openSettings:
            openPrivacySettings(for: kind)
        case .request:
            busyPermission = kind
            await requestPermission(kind)
            await refreshPermissions()
            busyPermission = nil
        case .resetAndRequest:
            busyPermission = kind
            await resetPermission(kind)
            try? await Task.sleep(for: .milliseconds(650))
            await requestPermission(kind)
            await refreshPermissions()
            busyPermission = nil
        }
    }

    private func requestPermission(_ kind: PermissionKind) async {
        switch kind {
        case .calendar:
            let granted = (try? await eventStore.requestFullAccessToEvents()) ?? false
            actionMessage =
                granted ? "Calendar access granted." : "Calendar access was not granted."
        case .reminders:
            let granted = (try? await eventStore.requestFullAccessToReminders()) ?? false
            actionMessage =
                granted ? "Reminders access granted." : "Reminders access was not granted."
        case .camera:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            actionMessage = granted ? "Camera access granted." : "Camera access was not granted."
        case .bluetooth:
            let authorization = await bluetoothRequester.request()
            bluetoothAuthorization = authorization
            switch authorization {
            case .allowedAlways:
                actionMessage = "Bluetooth access granted."
            case .denied:
                actionMessage = "Bluetooth access was denied."
            case .restricted:
                actionMessage = "Bluetooth access is restricted."
            case .notDetermined:
                actionMessage =
                    "Bluetooth permission is still pending. Respond to the system prompt, then return to Settings."
            @unknown default:
                actionMessage = "Bluetooth permission could not be determined."
            }
        case .accessibility:
            let granted = await XPCHelperClient.shared.ensureAccessibilityAuthorization(
                promptIfNeeded: true)
            actionMessage =
                granted ? "Accessibility access granted." : "Accessibility access was not granted."
        case .notifications:
            let granted =
                (try? await UNUserNotificationCenter.current().requestAuthorization(options: [
                    .alert, .sound,
                ])) ?? false
            actionMessage = granted ? "Notifications allowed." : "Notifications were not allowed."
        case .automation:
            break
        }
    }

    private func resetPermission(_ kind: PermissionKind) async {
        guard let tccService = kind.tccService else { return }

        let bundleIdentifier: String
        if kind == .accessibility {
            bundleIdentifier = "com.notchingitup.BoringNotchXPCHelper"
        } else {
            bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.notchingitup.notchingitup"
        }

        let success = await XPCHelperClient.shared.resetPrivacyPermission(
            tccService,
            bundleIdentifier: bundleIdentifier
        )
        if !success {
            actionMessage =
                "Could not reset \(kind.title) automatically. Use System Settings to change it."
        }
    }

    private func resetAllPermissions() async {
        let mainBundleIdentifier =
            Bundle.main.bundleIdentifier ?? "com.notchingitup.notchingitup"
        let helperBundleIdentifier = "com.notchingitup.BoringNotchXPCHelper"

        for service in ["Calendar", "Reminders", "Camera", "Bluetooth", "AppleEvents"] {
            _ = await XPCHelperClient.shared.resetPrivacyPermission(
                service,
                bundleIdentifier: mainBundleIdentifier
            )
        }

        // Reset the helper last. Revoking accessibility can terminate the helper
        // before it can send a reply, so the result is intentionally ignored.
        _ = await XPCHelperClient.shared.resetPrivacyPermission(
            "Accessibility",
            bundleIdentifier: helperBundleIdentifier
        )

        await refreshPermissions()
        showResetPermissionsResult = true
    }

    private func refreshPermissions() async {
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
        reminderStatus = EKEventStore.authorizationStatus(for: .reminder)
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        bluetoothAuthorization = CBManager.authorization

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus

        accessibilityGranted = await XPCHelperClient.shared.isAccessibilityAuthorized()
    }

    private func openPrivacySettings(for kind: PermissionKind) {
        guard let url = kind.privacyURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Diagnostics

    private var architecture: String {
        #if arch(arm64)
            return "arm64"
        #elseif arch(x86_64)
            return "x86_64"
        #else
            return "Unknown"
        #endif
    }

    private var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
            || NSHomeDirectory().contains("/Library/Containers/")
    }

    private var dataFolder: URL {
        if let url = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            return url
        }
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    private var crashReportsFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
    }

    private func diagnosticRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 16)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func pathRow(_ title: String, _ path: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
            Text(path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private func copyDiagnostics() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(diagnosticsReport, forType: .string)

        didCopyReport = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            didCopyReport = false
        }
    }

    private var diagnosticsReport: String {
        """
        Notching it up Developer Diagnostics
        Generated: \(ISO8601DateFormatter().string(from: Date()))
        Version: \(Bundle.main.releaseVersionNumber ?? "Unknown") (\(Bundle.main.buildVersionNumber ?? "Unknown"))
        Bundle ID: \(Bundle.main.bundleIdentifier ?? "Unknown")
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Architecture: \(architecture)
        Sandboxed: \(isSandboxed ? "Yes" : "No")
        Displays: \(NSScreen.screens.count)
        App bundle: \(Bundle.main.bundleURL.path)
        Data folder: \(dataFolder.path)
        Crash reports: \(crashReportsFolder.path)

        Calendar: \(permissionState(for: .calendar).text)
        Reminders: \(permissionState(for: .reminders).text)
        Camera: \(permissionState(for: .camera).text)
        Bluetooth: \(permissionState(for: .bluetooth).text)
        Accessibility: \(permissionState(for: .accessibility).text)
        Notifications: \(permissionState(for: .notifications).text)
        Automation: \(permissionState(for: .automation).text)
        AI accounts: \(AIUsageStore.shared.accounts.count)
        Bluetooth devices: \(BluetoothActivityManager.shared.connectedDevices.count)
        """
    }
}

/// Creates a Core Bluetooth manager so macOS can present the Bluetooth privacy
/// prompt. The manager is retained while permission is pending so the prompt is
/// not dismissed before the user answers it.
@MainActor
private final class BluetoothPermissionRequester: NSObject, CBCentralManagerDelegate {
    private var manager: CBCentralManager?
    private var continuation: CheckedContinuation<CBManagerAuthorization, Never>?
    private var timeoutTask: Task<Void, Never>?

    func request() async -> CBManagerAuthorization {
        if manager == nil {
            manager = CBCentralManager(
                delegate: self,
                queue: .main,
                options: [CBCentralManagerOptionShowPowerAlertKey: false]
            )
        }
        manager?.scanForPeripherals(withServices: nil)

        return await withCheckedContinuation { continuation in
            self.continuation = continuation

            timeoutTask?.cancel()
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.finish()
            }
        }
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor [weak self] in
            guard CBManager.authorization != .notDetermined else { return }
            self?.finish()
        }
    }

    private func finish() {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        manager?.stopScan()

        let authorization = CBManager.authorization
        if authorization != .notDetermined {
            manager = nil
        }
        continuation.resume(returning: authorization)
    }
}
