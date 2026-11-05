//
//  PermissionsRequestView.swift
//  boringNotch
//
//  Created by Alexander on 2025-06-23.
//

import CoreBluetooth
import SwiftUI

// MARK: - Permissions guide

private struct PermissionGuideItem: Identifiable {
    let icon: String
    let title: String
    let detail: String

    var id: String { title }
}

private let permissionGuideItems: [PermissionGuideItem] = [
    PermissionGuideItem(
        icon: "calendar",
        title: "Calendar",
        detail: "Shows upcoming events and reminders in the notch. macOS asks when you turn on the Calendar tab."
    ),
    PermissionGuideItem(
        icon: "music.note",
        title: "Media",
        detail: "Reads and controls Spotify or Apple Music. macOS asks for Automation access when you choose a direct music source."
    ),
    PermissionGuideItem(
        icon: "antenna.radiowaves.left.and.right",
        title: "Bluetooth",
        detail: "Shows connected headphones and speakers, battery levels, and connection activity. macOS asks during setup so the notch can detect your audio devices."
    ),
    PermissionGuideItem(
        icon: "hand.raised.fill",
        title: "Accessibility",
        detail: "Powers volume, brightness, and media-key HUDs in the notch. macOS asks when you enable HUD replacement or media-key handling."
    ),
    PermissionGuideItem(
        icon: "bell.badge.fill",
        title: "Notifications",
        detail: "Sends low-usage alerts for AI plans. macOS asks when you turn on “Notify when a plan runs low.”"
    )
]

/// First-run overview that explains when each macOS permission is requested.
struct PermissionsGuideView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(Color.effectiveAccent)
                .padding(.top, 24)

            VStack(spacing: 6) {
                Text("A quick permissions guide")
                    .font(.title)
                    .fontWeight(.semibold)

                Text("macOS only asks when a feature needs access. Here is what each permission is for.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(permissionGuideItems) { item in
                        PermissionGuideRow(item: item)
                    }
                }
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.never)

            Text("You can review or revoke access anytime in System Settings > Privacy & Security.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }
}

private struct PermissionGuideRow: View {
    let item: PermissionGuideItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.effectiveAccent)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.headline)

                Text(item.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Permission request

struct PermissionRequestView: View {
    let icon: Image
    let title: String
    let description: String
    let privacyNote: String?
    let onAllow: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            icon
                .resizable()
                .scaledToFit()
                .frame(width: 70, height: 56)
                .foregroundColor(.effectiveAccent)
                .padding(.top, 32)

            Text(title)
                .font(.title)
                .fontWeight(.semibold)

            Text(description)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let privacyNote = privacyNote {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .foregroundColor(.secondary)
                    Text(privacyNote)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .padding(.bottom, 8)
                .padding(.horizontal)
            }

            HStack {
                Button("Not Now") { onSkip() }
                    .buttonStyle(.bordered)
                Button("Allow Access") { onAllow() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }
}

// MARK: - Bluetooth permission

/// Creates a Core Bluetooth manager so macOS can present the Bluetooth privacy
/// prompt. The manager is retained while permission is pending so the prompt is
/// not dismissed before the user answers it.
@MainActor
final class BluetoothPermissionRequester: NSObject, CBCentralManagerDelegate {
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
