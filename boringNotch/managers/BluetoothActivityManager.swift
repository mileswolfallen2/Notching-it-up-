//
//  BluetoothActivityManager.swift
//  boringNotch
//

import Combine
import IOBluetooth

@MainActor
final class BluetoothActivityManager: ObservableObject {
    enum DeviceKind: Equatable {
        case headphones
        case speaker
        case other

        var iconName: String {
            switch self {
            case .headphones:
                return "headphones"
            case .speaker:
                return "speaker.wave.3.fill"
            case .other:
                return "wave.3.right"
            }
        }
    }

    struct Activity: Equatable {
        let name: String
        let kind: DeviceKind
        let connected: Bool
    }

    static let shared = BluetoothActivityManager()

    @Published private(set) var activity: Activity?

    private var pollTask: Task<Void, Never>?
    private var connectedDevices: [String: (name: String, kind: DeviceKind)] = [:]
    private var dismissTask: Task<Void, Never>?

    private init() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    deinit {
        pollTask?.cancel()
        dismissTask?.cancel()
    }

    private func refresh() {
        let currentDevices = connectedBluetoothDevices()

        if let connected = currentDevices.first(where: { connectedDevices[$0.key] == nil }) {
            showActivity(
                name: connected.value.name,
                kind: connected.value.kind,
                connected: true
            )
        } else if let disconnected = connectedDevices.first(where: { currentDevices[$0.key] == nil }) {
            showActivity(
                name: disconnected.value.name,
                kind: disconnected.value.kind,
                connected: false
            )
        }

        connectedDevices = currentDevices
    }

    private func connectedBluetoothDevices() -> [String: (name: String, kind: DeviceKind)] {
        IOBluetoothDevice.pairedDevices().reduce(into: [:]) { devices, item in
            guard let device = item as? IOBluetoothDevice, device.isConnected() else { return }
            let address = device.addressString ?? UUID().uuidString
            let name = device.name ?? "Bluetooth device"
            guard let kind = deviceKind(for: device, name: name) else { return }
            devices[address] = (name: name, kind: kind)
        }
    }

    private func deviceKind(for device: IOBluetoothDevice, name: String) -> DeviceKind? {
        let deviceClass = UInt32(device.classOfDevice)
        let majorClass = (deviceClass >> 8) & 0x1F
        let minorClass = (deviceClass >> 2) & 0x3F

        if majorClass == UInt32(kBluetoothDeviceClassMajorAudio) {
            switch minorClass {
            case UInt32(kBluetoothDeviceClassMinorAudioHeadset),
                 UInt32(kBluetoothDeviceClassMinorAudioHandsFree),
                 UInt32(kBluetoothDeviceClassMinorAudioHeadphones):
                return .headphones
            case UInt32(kBluetoothDeviceClassMinorAudioLoudspeaker),
                 UInt32(kBluetoothDeviceClassMinorAudioPortable),
                 UInt32(kBluetoothDeviceClassMinorAudioHiFi),
                 UInt32(kBluetoothDeviceClassMinorAudioVideoDisplayAndLoudspeaker):
                return .speaker
            default:
                break
            }
        } else if majorClass != UInt32(kBluetoothDeviceClassMajorUnclassified) {
            return nil
        }

        let normalizedName = name.lowercased()
        if normalizedName.contains("headphone")
            || normalizedName.contains("headset")
            || normalizedName.contains("airpods")
            || normalizedName.contains("earbuds")
            || normalizedName.contains("buds")
        {
            return .headphones
        }
        if normalizedName.contains("speaker")
            || normalizedName.contains("sonos")
            || normalizedName.contains("homepod")
            || normalizedName.contains("soundbar")
        {
            return .speaker
        }
        return nil
    }

    private func showActivity(name: String, kind: DeviceKind, connected: Bool) {
        dismissTask?.cancel()
        activity = Activity(name: name, kind: kind, connected: connected)
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.activity = nil
        }
    }
}
