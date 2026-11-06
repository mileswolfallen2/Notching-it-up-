//
//  BluetoothActivityManager.swift
//  boringNotch
//

import Combine
import Foundation
import IOBluetooth
import SwiftUI

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

    struct Device: Identifiable, Equatable {
        let id: String
        let name: String
        let kind: DeviceKind
        let batteryLevel: Int?
    }

    private struct RawDevice: Sendable {
        let address: String
        let name: String
        let kind: String
        let batteryLevel: Int?
    }

    static let shared = BluetoothActivityManager()

    @Published private(set) var activity: Activity?
    @Published private(set) var connectedDevices: [Device] = []

    private var pollTask: Task<Void, Never>?
    private var previousConnectedDevices: [String: (id: String, name: String, kind: DeviceKind, batteryLevel: Int?)] = [:]
    private var dismissTask: Task<Void, Never>?
    private var hasInitialSnapshot = false
    private var lastDeviceSignature = ""

    private init() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshDevices()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    deinit {
        pollTask?.cancel()
        dismissTask?.cancel()
    }

    private func refreshDevices() async {
        let profileDevices = await Task.detached(priority: .utility) {
            Self.connectedBluetoothDevices()
        }.value
        let devices = merge(
            directConnectedBluetoothDevices(),
            with: profileDevices
        )
        let signature = devices.map { "\($0.address):\($0.name)" }.sorted().joined(separator: "|")
        if signature != lastDeviceSignature {
            lastDeviceSignature = signature
            NSLog("Bluetooth audio devices changed: \(signature.isEmpty ? "none" : signature)")
        }
        updateConnectedDevices(devices)
    }

    private func merge(_ directDevices: [RawDevice], with profileDevices: [RawDevice]) -> [RawDevice] {
        var merged = Dictionary(
            directDevices.map { ($0.address, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        for device in profileDevices {
            merged[device.address] = device
        }
        return Array(merged.values)
    }

    private func updateConnectedDevices(_ rawDevices: [RawDevice]) {
        var currentDevices: [String: (id: String, name: String, kind: DeviceKind, batteryLevel: Int?)] = [:]
        for raw in rawDevices {
            let kind: DeviceKind = raw.kind.localizedCaseInsensitiveContains("speaker")
                ? .speaker
                : .headphones
            currentDevices[raw.address] = (
                id: raw.address,
                name: raw.name,
                kind: kind,
                batteryLevel: raw.batteryLevel
            )
        }
        connectedDevices = currentDevices.values
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { Device(id: $0.id, name: $0.name, kind: $0.kind, batteryLevel: $0.batteryLevel) }

        if !hasInitialSnapshot {
            hasInitialSnapshot = true
        } else if let connected = currentDevices.first(where: { previousConnectedDevices[$0.key] == nil }) {
            showActivity(
                name: connected.value.name,
                kind: connected.value.kind,
                connected: true
            )
        } else if let disconnected = previousConnectedDevices.first(where: { currentDevices[$0.key] == nil }) {
            showActivity(
                name: disconnected.value.name,
                kind: disconnected.value.kind,
                connected: false
            )
        }

        previousConnectedDevices = currentDevices
    }

    private nonisolated static func connectedBluetoothDevices() -> [RawDevice] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        process.standardOutput = output

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                return []
            }

            return extractConnectedDevices(from: object)
        } catch {
            NSLog("Bluetooth device lookup failed: \(error.localizedDescription)")
            return []
        }
    }

    private func directConnectedBluetoothDevices() -> [RawDevice] {
        IOBluetoothDevice.pairedDevices().compactMap { item in
            guard let device = item as? IOBluetoothDevice,
                  device.isConnected(),
                  let address = device.addressString,
                  let name = device.name,
                  Self.isAudioDevice(name: name, kind: "") else {
                return nil
            }

            let kind = name.localizedCaseInsensitiveContains("speaker") ? "Speaker" : "Headset"
            return RawDevice(
                address: address,
                name: name,
                kind: kind,
                batteryLevel: nil
            )
        }
    }

    private nonisolated static func extractConnectedDevices(from value: Any) -> [RawDevice] {
        var devices: [RawDevice] = []
        if let dictionary = value as? [String: Any] {
            if let connected = dictionary["device_connected"] as? [Any] {
                for case let entry as [String: Any] in connected {
                    for (name, value) in entry {
                        guard let details = value as? [String: Any],
                              let address = details["device_address"] as? String,
                              let kind = details["device_minorType"] as? String,
                              isAudioDevice(name: name, kind: kind)
                        else { continue }
                        let battery = details.first { key, _ in
                            key.lowercased().contains("batterylevel")
                        }.flatMap { batteryLevel(from: $0.value) }
                        devices.append(
                            RawDevice(
                                address: address,
                                name: name,
                                kind: kind,
                                batteryLevel: battery
                            )
                        )
                    }
                }
            }
            for child in dictionary.values {
                devices.append(contentsOf: extractConnectedDevices(from: child))
            }
        } else if let array = value as? [Any] {
            for child in array {
                devices.append(contentsOf: extractConnectedDevices(from: child))
            }
        }
        return devices
    }

    private nonisolated static func batteryLevel(from value: Any) -> Int? {
        if let number = value as? NSNumber {
            return min(max(number.intValue, 0), 100)
        }
        if let string = value as? String {
            let digits = string.filter(\.isNumber)
            if let number = Int(digits) {
                return min(max(number, 0), 100)
            }
        }
        return nil
    }

    private nonisolated static func isAudioDevice(name: String, kind: String) -> Bool {
        let value = "\(name) \(kind)".lowercased()
        return value.contains("head")
            || value.contains("earbud")
            || value.contains("speaker")
            || value.contains("soundbar")
            || value.contains("homepod")
            || value.contains("airpods")
            || value.contains("buds")
    }

    private func showActivity(name: String, kind: DeviceKind, connected: Bool) {
        dismissTask?.cancel()
        activity = Activity(name: name, kind: kind, connected: connected)
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86, blendDuration: 0)) {
                self?.activity = nil
            }
        }
    }
}
