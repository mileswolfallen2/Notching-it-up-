import AppKit
import SwiftUI

/// Bluetooth audio devices and their battery levels, styled like the other
/// notch cards (shared chrome, hover feedback, and spring transitions).
struct BluetoothDevicesView: View {
    @ObservedObject private var bluetoothManager = BluetoothActivityManager.shared
    @State private var emptyStateHovering = false

    private var devices: [BluetoothActivityManager.Device] {
        bluetoothManager.connectedDevices
    }

    private var detail: String {
        switch devices.count {
        case 0: return "None connected"
        case 1: return "1 connected"
        default: return "\(devices.count) connected"
        }
    }

    private var lowestBattery: Int? {
        devices.compactMap(\.batteryLevel).min()
    }

    private var detailTint: Color {
        if let lowestBattery, lowestBattery <= 20 { return .orange }
        return NotchPanelStyle.secondaryText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NotchPanelStyle.spacing) {
            NotchPanelHeader(
                icon: "headphones",
                title: "Bluetooth devices",
                detail: detail,
                detailTint: detailTint
            ) {
                Button(action: openBluetoothSettings) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open Bluetooth settings")
            }

            if devices.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(devices) { device in
                            BluetoothDeviceRow(device: device)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.never)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(
            BoringMotion.animation(.spring(response: 0.32, dampingFraction: 0.82)),
            value: devices
        )
    }

    private var emptyState: some View {
        Button(action: openBluetoothSettings) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.06))
                    Image(systemName: "headphones")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text("No audio devices")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Connect headphones or speakers to see them here.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(emptyStateHovering ? 0.65 : 0.35))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: NotchPanelStyle.cornerRadius, style: .continuous)
                    .fill(emptyStateHovering ? Color.white.opacity(0.05) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: NotchPanelStyle.cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(emptyStateHovering ? 0.22 : 0.12),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { emptyStateHovering = $0 }
        .animation(BoringMotion.animation(.easeOut(duration: 0.15)), value: emptyStateHovering)
        .help("Open Bluetooth settings")
    }

    private func openBluetoothSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Bluetooth") else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Device row

private struct BluetoothDeviceRow: View {
    let device: BluetoothActivityManager.Device

    @State private var hovering = false
    @State private var appeared = false

    private var kindLabel: String {
        switch device.kind {
        case .headphones: return "Headphones"
        case .speaker: return "Speaker"
        case .other: return "Audio device"
        }
    }

    private var batteryColor: Color {
        guard let level = device.batteryLevel else { return NotchPanelStyle.secondaryText }
        return level <= 20 ? .orange : .white.opacity(0.72)
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.10 : 0.06))
                Image(systemName: device.kind.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(hovering ? 1 : 0.9))
                    .lineLimit(1)

                Text(kindLabel)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(NotchPanelStyle.secondaryText)
            }

            Spacer(minLength: 8)

            batteryBadge
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .bluetoothCardChrome(hovering: hovering)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Open Bluetooth Settings", action: openBluetoothSettings)
            Button("Copy Device Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(device.name, forType: .string)
            }
        }
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .onAppear {
            withAnimation(BoringMotion.animation(.easeOut(duration: 0.28))) {
                appeared = true
            }
        }
    }

    @ViewBuilder
    private var batteryBadge: some View {
        if let level = device.batteryLevel {
            HStack(spacing: 4) {
                Image(systemName: batteryIcon(for: level))
                    .font(.system(size: 11, weight: .semibold))
                Text("\(level)%")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .foregroundStyle(batteryColor)
            .animation(BoringMotion.animation(.easeOut(duration: 0.25)), value: level)
        } else {
            Text("Not reported")
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(NotchPanelStyle.secondaryText)
        }
    }

    private var helpText: String {
        if let level = device.batteryLevel {
            return "\(device.name) — \(kindLabel), \(level)% battery"
        }
        return "\(device.name) — \(kindLabel), battery not reported"
    }

    private var accessibilityLabel: String {
        if let level = device.batteryLevel {
            return "\(device.name), \(kindLabel), \(level) percent battery"
        }
        return "\(device.name), \(kindLabel), battery not reported"
    }

    private func batteryIcon(for level: Int) -> String {
        switch level {
        case 0..<20: return "battery.0"
        case 20..<50: return "battery.25"
        case 50..<75: return "battery.50"
        case 75..<95: return "battery.75"
        default: return "battery.100"
        }
    }

    private func openBluetoothSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Bluetooth") else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Card chrome

private extension View {
    /// Shared background, border, and hover treatment for device rows.
    func bluetoothCardChrome(hovering: Bool) -> some View {
        background(
            RoundedRectangle(cornerRadius: NotchPanelStyle.cornerRadius, style: .continuous)
                .fill(hovering ? NotchPanelStyle.hoverBackground : NotchPanelStyle.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NotchPanelStyle.cornerRadius, style: .continuous)
                .strokeBorder(
                    hovering ? NotchPanelStyle.hoverBorder : NotchPanelStyle.border,
                    lineWidth: 1
                )
        )
        .scaleEffect(hovering ? 1.01 : 1)
        .animation(BoringMotion.animation(.spring(response: 0.28, dampingFraction: 0.72)), value: hovering)
    }
}
