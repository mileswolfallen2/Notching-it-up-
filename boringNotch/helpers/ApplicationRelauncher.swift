//
//  ApplicationRelauncher.swift
//  boringNotch
//
//  Created by Corentin132 on 03/10/2025.
//

import AppKit
import LaunchAtLogin

enum ApplicationRelauncher {
    static func restart() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        let workspace = NSWorkspace.shared

        guard let appURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true

        workspace.openApplication(at: appURL, configuration: configuration, completionHandler: nil)

        NSApplication.shared.terminate(nil)
    }
}

/// Restores the app to a first-run state and relaunches it.
enum AppReset {
    @MainActor
    static func reset() {
        let defaults = UserDefaults.standard
        if let domain = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: domain)
        }
        defaults.synchronize()

        let fileManager = FileManager.default
        if let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            // Sign-ins and the shelf list are app-managed data. User files that
            // were added to the shelf are never deleted.
            try? fileManager.removeItem(
                at: support.appendingPathComponent("AI Usage", isDirectory: true)
            )
            try? fileManager.removeItem(
                at: support
                    .appendingPathComponent("boringNotch", isDirectory: true)
                    .appendingPathComponent("Shelf", isDirectory: true)
                    .appendingPathComponent("items.json", isDirectory: false)
            )
        }

        LaunchAtLogin.isEnabled = false
        ApplicationRelauncher.restart()
    }
}
