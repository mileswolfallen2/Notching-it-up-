//
//  drop.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on  04/08/24.
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

// MARK: - Motion preferences

/// Central place to decide whether the app should avoid decorative motion.
/// The user can always opt in with the "Reduce motion" setting, and the
/// setting can also follow the macOS accessibility preference.
enum BoringMotion {
    static var followsSystem: Bool {
        Defaults[.followSystemReduceMotion]
    }

    static var systemPrefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static var shouldReduceMotion: Bool {
        Defaults[.reduceMotion] || (followsSystem && systemPrefersReducedMotion)
    }

    /// Returns the supplied animation unless reduced motion is requested.
    static func animation(_ animation: Animation?) -> Animation? {
        shouldReduceMotion ? nil : animation
    }
}

/// Observable wrapper so SwiftUI views can update when the macOS Reduce Motion
/// setting or the app-level accessibility toggles change.
@MainActor
final class MotionPreferences: ObservableObject {
    static let shared = MotionPreferences()

    @Published private(set) var shouldReduceMotion: Bool = BoringMotion.shouldReduceMotion
    @Published private(set) var systemPrefersReducedMotion: Bool =
        BoringMotion.systemPrefersReducedMotion

    private var cancellables = Set<AnyCancellable>()

    private init() {
        Defaults.publisher(.reduceMotion)
            .sink { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            .store(in: &cancellables)

        Defaults.publisher(.followSystemReduceMotion)
            .sink { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @objc private func accessibilityDisplayOptionsDidChange() {
        refresh()
    }

    private func refresh() {
        systemPrefersReducedMotion = BoringMotion.systemPrefersReducedMotion
        shouldReduceMotion = BoringMotion.shouldReduceMotion
    }
}

// MARK: - Notch animations

public class BoringAnimations {
    @Published var notchStyle: Style = .notch

    init() {
        self.notchStyle = .notch
    }

    var animation: Animation? {
        guard !BoringMotion.shouldReduceMotion else { return nil }

        if #available(macOS 14.0, *), notchStyle == .notch {
            return Animation.spring(.bouncy(duration: 0.4))
        } else {
            return Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.7)
        }
    }

    // TODO: Move all animations to this file
}
