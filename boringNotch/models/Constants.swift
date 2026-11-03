//
//  Constants.swift
//  boringNotch
//
//  Created by Richard Kunkli on 2024. 10. 17..
//

import SwiftUI
import Defaults
import Foundation

private let availableDirectories = FileManager
    .default
    .urls(for: .documentDirectory, in: .userDomainMask)
let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
let bundleIdentifier = Bundle.main.bundleIdentifier!
let appVersion = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))"

let temporaryDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
let spacing: CGFloat = 16

struct CustomVisualizer: Codable, Hashable, Equatable, Defaults.Serializable {
    let UUID: UUID
    var name: String
    var url: URL
    var speed: CGFloat = 1.0
}

enum CalendarSelectionState: Codable, Defaults.Serializable {
    case all
    case selected(Set<String>)
}

enum HideNotchOption: String, Defaults.Serializable {
    case always
    case nowPlayingOnly
    case never
}

// Define notification names at file scope
extension Notification.Name {
    static let mediaControllerChanged = Notification.Name("mediaControllerChanged")
}

// Media controller types for selection in settings
enum MediaControllerType: String, CaseIterable, Identifiable, Defaults.Serializable {
    case nowPlaying = "Now Playing"
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
    case youtubeMusic = "YouTube Music"
    
    var id: String { self.rawValue }
}

// Sneak peek styles for selection in settings
enum SneakPeekStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case standard = "Default"
    case inline = "Inline"
    
    var id: String { self.rawValue }
}

// Action to perform when Option (⌥) is held while pressing media keys
enum OptionKeyAction: String, CaseIterable, Identifiable, Defaults.Serializable {
    case openSettings = "Open System Settings"
    case showHUD = "Show HUD"
    case none = "No Action"

    var id: String { self.rawValue }
}

/// Represents a configurable item in the top bar (header tab strip).
enum TopBarTab: String, CaseIterable, Codable, Identifiable, Defaults.Serializable {
    case home  = "home"
    case shelf = "shelf"
    case timer = "timer"
    case notes = "notes"
    case ai    = "ai"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home:  return "Home"
        case .shelf: return "Shelf"
        case .timer: return "Timer"
        case .notes: return "Notes"
        case .ai:    return "AI"
        }
    }

    var iconName: String {
        switch self {
        case .home:  return "house.fill"
        case .shelf: return "tray.fill"
        case .timer: return "timer"
        case .notes: return "note.text"
        case .ai:    return "sparkles"
        }
    }

    var notchView: NotchViews {
        switch self {
        case .home:  return .home
        case .shelf: return .shelf
        case .timer: return .timer
        case .notes: return .notes
        case .ai:    return .ai
        }
    }

    /// Default ordered layout shown in the top bar.
    static let defaultLayout: [TopBarTab] = [.home, .shelf, .timer, .ai, .notes]

    /// Returns the stored order with any missing tabs appended, then filters out
    /// tabs the user has hidden. This keeps existing installations working when
    /// new tabs are introduced.
    static func orderedVisibleTabs(
        slots: [TopBarTab],
        showHome: Bool,
        showShelf: Bool,
        showTimer: Bool,
        showNotes: Bool,
        showAI: Bool,
        shelfEnabled: Bool
    ) -> [TopBarTab] {
        var ordered = slots
        for tab in allCases where !ordered.contains(tab) {
            ordered.append(tab)
        }
        return ordered.filter { tab in
            switch tab {
            case .home:  return showHome
            case .shelf: return showShelf && shelfEnabled
            case .timer: return showTimer
            case .notes: return showNotes
            case .ai:    return showAI
            }
        }
    }
}

// MARK: - AI usage tracking

/// Providers whose plan usage can be surfaced in the AI tab.
enum AIProvider: String, CaseIterable, Codable, Identifiable, Defaults.Serializable, Hashable, Sendable {
    case claude
    case codex
    case cursor
    case antigravity
    case copilot
    case gemini
    case opencode

    var id: String { rawValue }

    var label: String {
        switch self {
        case .claude:      return "Claude"
        case .codex:       return "Codex"
        case .cursor:      return "Cursor"
        case .antigravity: return "Antigravity"
        case .copilot:     return "Copilot"
        case .gemini:      return "Gemini"
        case .opencode:    return "OpenCode"
        }
    }

    var iconName: String {
        switch self {
        case .claude:      return "sparkles"
        case .codex:       return "terminal"
        case .cursor:      return "cursorarrow.rays"
        case .antigravity: return "atom"
        case .copilot:     return "chevron.left.forwardslash.chevron.right"
        case .gemini:      return "diamond.fill"
        case .opencode:    return "brain.head.profile"
        }
    }

    /// Optional brand tint used when the user enables provider colors.
    var tint: Color {
        switch self {
        case .claude:      return Color(red: 0.85, green: 0.48, blue: 0.35)
        case .codex:       return Color(red: 0.10, green: 0.72, blue: 0.54)
        case .cursor:      return Color(red: 0.30, green: 0.72, blue: 0.95)
        case .antigravity: return Color(red: 0.60, green: 0.48, blue: 0.98)
        case .copilot:     return Color(red: 0.42, green: 0.62, blue: 0.98)
        case .gemini:      return Color(red: 0.36, green: 0.66, blue: 1.0)
        case .opencode:    return Color(red: 0.72, green: 0.72, blue: 0.78)
        }
    }

    var defaultPlanName: String {
        switch self {
        case .claude:      return "Claude Pro"
        case .codex:       return "ChatGPT Plus"
        case .cursor:      return "Cursor Pro"
        case .antigravity: return "Antigravity"
        case .copilot:     return "GitHub Copilot"
        case .gemini:      return "Google AI Pro"
        case .opencode:    return "OpenCode"
        }
    }

    /// Typical length of a usage window before the plan limits reset.
    var resetInterval: TimeInterval {
        switch self {
        case .claude, .codex, .antigravity, .opencode:
            return 5 * 60 * 60
        case .gemini:
            return 24 * 60 * 60
        case .cursor, .copilot:
            return 30 * 24 * 60 * 60
        }
    }

    var resetIntervalLabel: String {
        switch self {
        case .claude, .codex, .antigravity, .opencode:
            return "5 hours"
        case .gemini:
            return "24 hours"
        case .cursor, .copilot:
            return "30 days"
        }
    }

    /// Providers that expose a personal usage endpoint we can read after signing in.
    var supportsLiveUsage: Bool {
        switch self {
        case .claude, .codex, .antigravity, .copilot:
            return true
        case .cursor, .gemini, .opencode:
            return false
        }
    }

    static var liveProviders: [AIProvider] {
        allCases.filter(\.supportsLiveUsage)
    }

    var signInHint: String {
        switch self {
        case .claude:      return "Sign in with your Claude account"
        case .codex:       return "Sign in with your ChatGPT account"
        case .antigravity: return "Sign in with your Google account"
        case .copilot:     return "Connect with a GitHub device code"
        case .cursor:      return "Cursor is tracked manually"
        case .gemini:      return "Gemini is tracked manually"
        case .opencode:    return "OpenCode is tracked manually"
        }
    }
}

/// How AI usage rings are tinted in the notch.
enum AIUsageColorStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case monochrome
    case provider
    case accent
    case usage

    var id: String { rawValue }

    var label: String {
        switch self {
        case .monochrome: return "Monochrome"
        case .provider:   return "Provider"
        case .accent:     return "Accent"
        case .usage:      return "Usage"
        }
    }

    func color(for provider: AIProvider, percentRemaining: Double) -> Color {
        switch self {
        case .monochrome:
            return .white.opacity(0.88)
        case .provider:
            return provider.tint
        case .accent:
            return .effectiveAccent
        case .usage:
            let percent = percentRemaining.isFinite ? percentRemaining : 0
            if percent <= 20 {
                return Color(red: 0.95, green: 0.42, blue: 0.42)
            }
            if percent <= 50 {
                return Color(red: 0.95, green: 0.75, blue: 0.30)
            }
            return Color(red: 0.35, green: 0.82, blue: 0.55)
        }
    }
}

/// A single tracked AI plan. Usage is kept locally so no credentials or
/// network requests are required.
struct AIUsageEntry: Codable, Hashable, Identifiable, Defaults.Serializable {
    var id: UUID = UUID()
    var provider: AIProvider
    var planName: String = ""
    var percentRemaining: Double = 100
    var resetDate: Date? = nil
    var enabled: Bool = true
    /// When the last low-usage alert was posted for the current window.
    /// Optional so existing stored entries keep decoding.
    var lastAlertDate: Date? = nil
    /// Signed-in account this entry last synced with, when live usage is enabled.
    var accountLabel: String? = nil
    /// Last successful live sync.
    var lastSyncDate: Date? = nil
    /// Last live sync failure, kept so the settings pane can explain stale data.
    var syncError: String? = nil

    var isLiveSynced: Bool { lastSyncDate != nil }

    var displayPlanName: String {
        planName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? provider.defaultPlanName
            : planName
    }

    var clampedPercent: Double {
        guard percentRemaining.isFinite else { return 0 }
        return min(max(percentRemaining, 0), 100)
    }

    func isLow(threshold: Double) -> Bool {
        clampedPercent <= threshold
    }

    /// The next reset time after `now`, keeping the original anchor while
    /// advancing by whole windows.
    static func nextReset(after now: Date, from anchor: Date, interval: TimeInterval) -> Date {
        guard interval > 60 else { return now.addingTimeInterval(interval) }
        var next = anchor
        // Guard against absurd loops from corrupt data.
        var safety = 0
        while next <= now && safety < 10_000 {
            next = next.addingTimeInterval(interval)
            safety += 1
        }
        return next
    }

    var defaultResetDate: Date {
        Date().addingTimeInterval(provider.resetInterval)
    }

    var resetText: String {
        guard let resetDate else { return "No reset time" }
        let interval = resetDate.timeIntervalSinceNow
        if interval <= 0 { return "Reset ready" }
        if interval < 60 * 60 {
            return "Resets in \(max(1, Int(interval / 60)))m"
        }
        if interval < 24 * 60 * 60 {
            let hours = Int(interval / 3600)
            let minutes = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
            return minutes == 0 ? "Resets in \(hours)h" : "Resets in \(hours)h \(minutes)m"
        }
        return "Resets \(resetDate.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
    }

    static let defaultEntries: [AIUsageEntry] = [
        AIUsageEntry(provider: .claude, planName: "Claude Pro", resetDate: Date().addingTimeInterval(AIProvider.claude.resetInterval)),
        AIUsageEntry(provider: .codex, planName: "ChatGPT Plus", resetDate: Date().addingTimeInterval(AIProvider.codex.resetInterval)),
        AIUsageEntry(provider: .cursor, planName: "Cursor Pro", resetDate: Date().addingTimeInterval(AIProvider.cursor.resetInterval)),
        AIUsageEntry(provider: .antigravity, planName: "Antigravity", resetDate: Date().addingTimeInterval(AIProvider.antigravity.resetInterval))
    ]
}

extension Defaults.Keys {
    // MARK: General
    static let menubarIcon = Key<Bool>("menubarIcon", default: true)
    static let showOnAllDisplays = Key<Bool>("showOnAllDisplays", default: false)
    static let automaticallySwitchDisplay = Key<Bool>("automaticallySwitchDisplay", default: true)
    static let releaseName = Key<String>("releaseName", default: "A whole new world")
    static let showAdvancedSettings = Key<Bool>("showAdvancedSettings", default: false)
    
    // MARK: Behavior
    static let minimumHoverDuration = Key<TimeInterval>("minimumHoverDuration", default: 0.3)
    static let enableHaptics = Key<Bool>("enableHaptics", default: true)
    static let openNotchOnHover = Key<Bool>("openNotchOnHover", default: true)
    static let extendHoverArea = Key<Bool>("extendHoverArea", default: false)
    static let notchHeightMode = Key<WindowHeightMode>(
        "notchHeightMode",
        default: WindowHeightMode.matchRealNotchSize
    )
    static let nonNotchHeightMode = Key<WindowHeightMode>(
        "nonNotchHeightMode",
        default: WindowHeightMode.matchMenuBar
    )
    static let nonNotchHeight = Key<CGFloat>("nonNotchHeight", default: 32)
    static let notchHeight = Key<CGFloat>("notchHeight", default: 32)
    //static let openLastTabByDefault = Key<Bool>("openLastTabByDefault", default: false)
    static let showOnLockScreen = Key<Bool>("showOnLockScreen", default: false)
    static let hideFromScreenRecording = Key<Bool>("hideFromScreenRecording", default: false)
    static let enableClipboardHistory = Key<Bool>("enableClipboardHistory", default: false)
    
    // MARK: Top bar tab layout
    static let topBarSlots = Key<[TopBarTab]>("topBarSlots", default: TopBarTab.defaultLayout)

    // MARK: AI usage
    static let aiUsageEntries = Key<[AIUsageEntry]>("aiUsageEntries", default: AIUsageEntry.defaultEntries)
    static let showAITab = Key<Bool>("showAITab", default: true)
    static let aiSortByLowest = Key<Bool>("aiSortByLowest", default: false)
    static let aiCompactCards = Key<Bool>("aiCompactCards", default: false)
    static let aiColorStyle = Key<AIUsageColorStyle>("aiColorStyle", default: .monochrome)
    static let aiShowManualPlans = Key<Bool>("aiShowManualPlans", default: false)
    static let aiAutoReset = Key<Bool>("aiAutoReset", default: true)
    static let aiLiveSync = Key<Bool>("aiLiveSync", default: true)
    static let aiLowUsageAlerts = Key<Bool>("aiLowUsageAlerts", default: true)
    static let aiLowUsageThreshold = Key<Double>("aiLowUsageThreshold", default: 20)

    // MARK: Timer
    static let timerWorkDuration = Key<Int>("timerWorkDuration", default: 25)
    static let timerShortBreakDuration = Key<Int>("timerShortBreakDuration", default: 5)
    static let timerLongBreakDuration = Key<Int>("timerLongBreakDuration", default: 15)
    static let timerSessionsBeforeLongBreak = Key<Int>("timerSessionsBeforeLongBreak", default: 4)
    static let timerAutoStartBreaks = Key<Bool>("timerAutoStartBreaks", default: false)
    static let timerAutoStartWork = Key<Bool>("timerAutoStartWork", default: false)
    static let timerShowInClosedNotch = Key<Bool>("timerShowInClosedNotch", default: true)
    static let showHomeTab = Key<Bool>("showHomeTab", default: true)
    static let showShelfTab = Key<Bool>("showShelfTab", default: true)
    static let showTimerTab = Key<Bool>("showTimerTab", default: true)
    static let showNotesTab = Key<Bool>("showNotesTab", default: true)
    static let notesText = Key<String>("notesText", default: "")
    // MARK: Appearance
    static let showEmojis = Key<Bool>("showEmojis", default: false)
    //static let alwaysShowTabs = Key<Bool>("alwaysShowTabs", default: true)
    static let showMirror = Key<Bool>("showMirror", default: false)
    static let mirrorShape = Key<MirrorShapeEnum>("mirrorShape", default: MirrorShapeEnum.rectangle)
    static let settingsIconInNotch = Key<Bool>("settingsIconInNotch", default: true)
    static let lightingEffect = Key<Bool>("lightingEffect", default: true)
    static let enableShadow = Key<Bool>("enableShadow", default: true)
    static let cornerRadiusScaling = Key<Bool>("cornerRadiusScaling", default: true)

    static let showNotHumanFace = Key<Bool>("showNotHumanFace", default: false)
    static let tileShowLabels = Key<Bool>("tileShowLabels", default: false)
    static let showCalendar = Key<Bool>("showCalendar", default: false)
    static let hideCompletedReminders = Key<Bool>("hideCompletedReminders", default: true)
    static let sliderColor = Key<SliderColorEnum>(
        "sliderUseAlbumArtColor",
        default: SliderColorEnum.white
    )
    static let playerColorTinting = Key<Bool>("playerColorTinting", default: true)
    static let useMusicVisualizer = Key<Bool>("useMusicVisualizer", default: true)
    static let customVisualizers = Key<[CustomVisualizer]>("customVisualizers", default: [])
    static let selectedVisualizer = Key<CustomVisualizer?>("selectedVisualizer", default: nil)
    
    // MARK: Gestures
    static let enableGestures = Key<Bool>("enableGestures", default: true)
    static let closeGestureEnabled = Key<Bool>("closeGestureEnabled", default: true)
    static let gestureSensitivity = Key<CGFloat>("gestureSensitivity", default: 200.0)
    
    // MARK: Media playback
    static let coloredSpectrogram = Key<Bool>("coloredSpectrogram", default: true)
    static let enableSneakPeek = Key<Bool>("enableSneakPeek", default: true)
    static let betterSneakPeek = Key<Bool>("betterSneakPeek", default: false)
    static let sneakPeekStyles = Key<SneakPeekStyle>("sneakPeekStyles", default: .standard)
    static let waitInterval = Key<Double>("waitInterval", default: 3)
    static let showShuffleAndRepeat = Key<Bool>("showShuffleAndRepeat", default: false)
    static let showMusicProgressBar = Key<Bool>("showMusicProgressBar", default: true)
    static let musicProgressBarThickness = Key<Double>("musicProgressBarThickness", default: 2)
    static let enableLyrics = Key<Bool>("enableLyrics", default: false)
    static let lyricsBlurTransition = Key<Bool>("lyricsBlurTransition", default: true)
    static let lyricsBlurIntensity = Key<Double>("lyricsBlurIntensity", default: 12)
    static let lyricsBlurDuration = Key<Double>("lyricsBlurDuration", default: 0.32)
    static let musicControlSlots = Key<[MusicControlButton]>(
        "musicControlSlots",
        default: MusicControlButton.defaultLayout
    )
    static let musicControlSlotLimit = Key<Int>(
        "musicControlSlotLimit",
        default: MusicControlButton.defaultLayout.count
    )
    
    // MARK: Battery
    static let showPowerStatusNotifications = Key<Bool>("showPowerStatusNotifications", default: true)
    static let showBatteryIndicator = Key<Bool>("showBatteryIndicator", default: true)
    static let showBatteryPercentage = Key<Bool>("showBatteryPercentage", default: true)
    static let showPowerStatusIcons = Key<Bool>("showPowerStatusIcons", default: true)
    
    // MARK: Downloads
    static let enableDownloadListener = Key<Bool>("enableDownloadListener", default: true)
    static let enableSafariDownloads = Key<Bool>("enableSafariDownloads", default: true)
    static let selectedDownloadIndicatorStyle = Key<DownloadIndicatorStyle>("selectedDownloadIndicatorStyle", default: DownloadIndicatorStyle.progress)
    static let selectedDownloadIconStyle = Key<DownloadIconStyle>("selectedDownloadIconStyle", default: DownloadIconStyle.onlyAppIcon)
    
    // MARK: HUD
    static let hudReplacement = Key<Bool>("hudReplacement", default: true)
    static let inlineHUD = Key<Bool>("inlineHUD", default: false)
    static let enableGradient = Key<Bool>("enableGradient", default: false)
    static let systemEventIndicatorShadow = Key<Bool>("systemEventIndicatorShadow", default: false)
    static let systemEventIndicatorUseAccent = Key<Bool>("systemEventIndicatorUseAccent", default: false)
    static let showOpenNotchHUD = Key<Bool>("showOpenNotchHUD", default: true)
    static let showOpenNotchHUDPercentage = Key<Bool>("showOpenNotchHUDPercentage", default: true)
    static let showClosedNotchHUDPercentage = Key<Bool>("showClosedNotchHUDPercentage", default: false)
    // Option key modifier behaviour for media keys
    static let optionKeyAction = Key<OptionKeyAction>("optionKeyAction", default: OptionKeyAction.openSettings)
    
    // MARK: Shelf
    static let boringShelf = Key<Bool>("boringShelf", default: true)
    static let openShelfByDefault = Key<Bool>("openShelfByDefault", default: true)
    static let shelfTapToOpen = Key<Bool>("shelfTapToOpen", default: true)
    static let quickShareProvider = Key<String>("quickShareProvider", default: QuickShareProvider.defaultProvider.id)
    static let copyOnDrag = Key<Bool>("copyOnDrag", default: false)
    static let autoRemoveShelfItems = Key<Bool>("autoRemoveShelfItems", default: false)
    static let expandedDragDetection = Key<Bool>("expandedDragDetection", default: true)
    
    // MARK: Calendar
    static let calendarSelectionState = Key<CalendarSelectionState>("calendarSelectionState", default: .all)
    static let hideAllDayEvents = Key<Bool>("hideAllDayEvents", default: false)
    static let showFullEventTitles = Key<Bool>("showFullEventTitles", default: false)
    static let autoScrollToNextEvent = Key<Bool>("autoScrollToNextEvent", default: true)
    
    // MARK: Fullscreen Media Detection
    static let hideNotchOption = Key<HideNotchOption>("hideNotchOption", default: .nowPlayingOnly)
    
    // MARK: Media Controller
    static let mediaController = Key<MediaControllerType>("mediaController", default: defaultMediaController)
    
    // MARK: Advanced Settings
    static let useCustomAccentColor = Key<Bool>("useCustomAccentColor", default: false)
    static let customAccentColorData = Key<Data?>("customAccentColorData", default: nil)
    // Show or hide the title bar
    static let hideTitleBar = Key<Bool>("hideTitleBar", default: true)
    
    // Helper to determine the default media controller based on NowPlaying deprecation status
    static var defaultMediaController: MediaControllerType {
        if MusicManager.shared.isNowPlayingDeprecated {
            return .appleMusic
        } else {
            return .nowPlaying
        }
    }

    static let didClearLegacyURLCacheV1 = Key<Bool>("didClearLegacyURLCache_v1", default: false)
}
