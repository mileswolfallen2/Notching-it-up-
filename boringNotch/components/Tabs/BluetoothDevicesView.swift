import SwiftUI

struct BluetoothDevicesView: View {
    @ObservedObject private var bluetoothManager = BluetoothActivityManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: NotchPanelStyle.spacing) {
            NotchPanelHeader(
                icon: "headphones",
                title: "Bluetooth devices",
                detail: bluetoothManager.connectedDevices.isEmpty
                    ? "None connected"
                    : "\(bluetoothManager.connectedDevices.count) connected"
            )

            if bluetoothManager.connectedDevices.isEmpty {
                Text("Connect headphones or speakers to see them here.")
                    .font(.caption)
                    .foregroundStyle(NotchPanelStyle.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            } else {
                ForEach(bluetoothManager.connectedDevices) { device in
                    HStack(spacing: 10) {
                        Image(systemName: device.kind.iconName)
                            .frame(width: 20)
                            .foregroundStyle(.white.opacity(0.85))

                        Text(device.name)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        if let batteryLevel = device.batteryLevel {
                            Label("\(batteryLevel)%", systemImage: batteryIcon(for: batteryLevel))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(batteryLevel <= 20 ? .orange : .secondary)
                        } else {
                            Text("Battery unavailable")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: NotchPanelStyle.cornerRadius)
                            .fill(NotchPanelStyle.background)
                    )
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .foregroundStyle(.white)
        .animation(.smooth, value: bluetoothManager.connectedDevices)
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
}
