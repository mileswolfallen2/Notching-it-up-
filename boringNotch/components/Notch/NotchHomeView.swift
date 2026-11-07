//
//  NotchHomeView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-18.
//  Modified by Harsh Vardhan Goswami & Richard Kunkli & Mustafa Ramadan
//

import Combine
import Defaults
import SwiftUI

// MARK: - Shared notch panel styling

/// Shared metrics for the panels inside the open notch. Keeping these in one
/// place keeps cards, headers, and focus states consistent as tabs are added.
enum NotchPanelStyle {
    static let cornerRadius: CGFloat = 12
    static let spacing: CGFloat = 7
    static let background = Color.white.opacity(0.045)
    static let activeBackground = Color.white.opacity(0.06)
    static let hoverBackground = Color.white.opacity(0.075)
    static let border = Color.white.opacity(0.10)
    static let activeBorder = Color.white.opacity(0.22)
    static let hoverBorder = Color.white.opacity(0.24)
    static let secondaryText = Color.white.opacity(0.42)
}

/// Icon, title, optional detail, and trailing controls for a notch tab.
struct NotchPanelHeader<Trailing: View>: View {
    let icon: String
    let title: String
    var detail: String = ""
    var detailTint: Color = NotchPanelStyle.secondaryText
    let trailing: Trailing

    init(
        icon: String,
        title: String,
        detail: String = "",
        detailTint: Color = NotchPanelStyle.secondaryText,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.detailTint = detailTint
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: NotchPanelStyle.spacing) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(detailTint)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            trailing
        }
    }
}

extension NotchPanelHeader where Trailing == EmptyView {
    init(
        icon: String,
        title: String,
        detail: String = "",
        detailTint: Color = NotchPanelStyle.secondaryText
    ) {
        self.init(icon: icon, title: title, detail: detail, detailTint: detailTint) {
            EmptyView()
        }
    }
}

// MARK: - Music Player Components

struct MusicPlayerView: View {
    @EnvironmentObject var vm: BoringViewModel
    let albumArtNamespace: Namespace.ID

    var body: some View {
        HStack {
            AlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace).padding(.all, 5)
            MusicControlsView().drawingGroup().compositingGroup()
        }
    }
}

struct AlbumArtView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var vm: BoringViewModel
    let albumArtNamespace: Namespace.ID

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if Defaults[.lightingEffect] {
                albumArtBackground
            }
            albumArtButton
        }
    }

    private var albumArtBackground: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Defaults[.cornerRadiusScaling]
                        ? MusicPlayerImageSizes.cornerRadiusInset.opened
                        : MusicPlayerImageSizes.cornerRadiusInset.closed)
            )
            .aspectRatio(1, contentMode: .fit)
            .scaleEffect(x: 1.3, y: 1.4)
            .rotationEffect(.degrees(92))
            .blur(radius: 40)
            .opacity(musicManager.isPlaying ? 0.5 : 0)
    }

    private var albumArtButton: some View {
        ZStack {
            Button {
                musicManager.openMusicApp()
            } label: {
                ZStack(alignment:.bottomTrailing) {
                    albumArtImage
                    appIconOverlay
                }
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(musicManager.isPlaying ? 1 : 0.85)
            
            albumArtDarkOverlay
        }
    }

    private var albumArtDarkOverlay: some View {
        Rectangle()
            .aspectRatio(1, contentMode: .fit)
            .foregroundColor(Color.black)
            .opacity(musicManager.isPlaying ? 0 : 0.8)
            .blur(radius: 50)
    }
                

    private var albumArtImage: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Defaults[.cornerRadiusScaling]
                        ? MusicPlayerImageSizes.cornerRadiusInset.opened
                        : MusicPlayerImageSizes.cornerRadiusInset.closed)
            )
    }

    @ViewBuilder
    private var appIconOverlay: some View {
        if vm.notchState == .open && !musicManager.usingAppIconForArtwork {
            AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 30, height: 30)
                .offset(x: 10, y: 10)
                .transition(.scale.combined(with: .opacity))
                .zIndex(2)
        }
    }
}

struct MusicControlsView: View {
    @ObservedObject var musicManager = MusicManager.shared
        @EnvironmentObject var vm: BoringViewModel
        @ObservedObject var webcamManager = WebcamManager.shared
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    @Default(.musicControlSlots) private var slotConfig
    @Default(.musicControlSlotLimit) private var slotLimit

    var body: some View {
        VStack(alignment: .leading) {
            songInfoAndSlider
            slotToolbar
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var songInfoAndSlider: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 4) {
                songInfo(width: geo.size.width)
                musicSlider
            }
        }
        .padding(.top, 10)
        .padding(.leading, 5)
    }

    private func songInfo(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MarqueeText(
                $musicManager.songTitle, font: .headline, nsFont: .headline, textColor: .white,
                frameWidth: width)
            MarqueeText(
                $musicManager.artistName,
                font: .headline,
                nsFont: .headline,
                textColor: Defaults[.playerColorTinting]
                    ? Color(nsColor: musicManager.avgColor)
                        .ensureMinimumBrightness(factor: 0.6) : .gray,
                frameWidth: width
            )
            .fontWeight(.medium)
            if Defaults[.enableLyrics] {
                TimelineView(.animation(minimumInterval: 0.25)) { timeline in
                    let currentElapsed: Double = {
                        guard musicManager.isPlaying else { return musicManager.elapsedTime }
                        let delta = timeline.date.timeIntervalSince(musicManager.timestampDate)
                        let progressed = musicManager.elapsedTime + (delta * musicManager.playbackRate)
                        return min(max(progressed, 0), musicManager.songDuration)
                    }()
                    let line: String = {
                        if musicManager.isFetchingLyrics { return "Loading lyrics…" }
                        if !musicManager.syncedLyrics.isEmpty {
                            return musicManager.lyricLine(at: currentElapsed)
                        }
                        let trimmed = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
                        return trimmed.isEmpty ? "No lyrics found" : trimmed.replacingOccurrences(of: "\n", with: " ")
                    }()
                    let isPersian = line.unicodeScalars.contains { scalar in
                        let v = scalar.value
                        return v >= 0x0600 && v <= 0x06FF
                    }
                    let useBlur = Defaults[.lyricsBlurTransition]
                    if useBlur {
                        let blurDur = Defaults[.lyricsBlurDuration]
                        MarqueeText(
                            .constant(line),
                            font: .subheadline,
                            nsFont: .subheadline,
                            textColor: musicManager.isFetchingLyrics ? .gray.opacity(0.7) : .gray,
                            frameWidth: width
                        )
                        .font(isPersian ? .custom("Vazirmatn-Regular", size: NSFont.preferredFont(forTextStyle: .subheadline).pointSize) : .subheadline)
                        .lineLimit(1)
                        .opacity(musicManager.isPlaying ? 1 : 0)
                        .scaleEffect(musicManager.isPlaying ? 1 : 0.98)
                        .id(line)
                        .transition(.blurReplace.animation(.spring(response: blurDur, dampingFraction: 0.8)))
                    } else {
                        MarqueeText(
                            .constant(line),
                            font: .subheadline,
                            nsFont: .subheadline,
                            textColor: musicManager.isFetchingLyrics ? .gray.opacity(0.7) : .gray,
                            frameWidth: width
                        )
                        .font(isPersian ? .custom("Vazirmatn-Regular", size: NSFont.preferredFont(forTextStyle: .subheadline).pointSize) : .subheadline)
                        .lineLimit(1)
                        .opacity(musicManager.isPlaying ? 1 : 0)
                        .id(line)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
    }

    private var musicSlider: some View {
        TimelineView(.animation(minimumInterval: musicManager.playbackRate > 0 ? 0.1 : nil)) { timeline in
            MusicSliderView(
                sliderValue: $sliderValue,
                duration: $musicManager.songDuration,
                lastDragged: $lastDragged,
                color: musicManager.avgColor,
                dragging: $dragging,
                currentDate: timeline.date,
                timestampDate: musicManager.timestampDate,
                elapsedTime: musicManager.elapsedTime,
                playbackRate: musicManager.playbackRate,
                isPlaying: musicManager.isPlaying
            ) { newValue in
                MusicManager.shared.seek(to: newValue)
            }
            .padding(.top, 5)
            .frame(height: 36)
            .id(musicManager.songTitle)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .animation(
                BoringMotion.animation(.spring(response: 0.35, dampingFraction: 0.8)),
                value: musicManager.songTitle
            )
        }
    }

    private var slotToolbar: some View {
        let slots = activeSlots
        return HStack(spacing: 6) {
            ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                slotView(for: slot)
                    .frame(alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var activeSlots: [MusicControlButton] {
        let sanitizedLimit = min(
            max(slotLimit, MusicControlButton.minSlotCount),
            MusicControlButton.maxSlotCount
        )
        let padded = slotConfig.padded(to: sanitizedLimit, filler: .none)
        let result = Array(padded.prefix(sanitizedLimit))
        // If calendar and camera are both visible alongside music, hide the edge slots
        let shouldHideEdges = Defaults[.showCalendar] && Defaults[.showMirror] && webcamManager.cameraAvailable && vm.isCameraExpanded
        if shouldHideEdges && result.count >= 5 {
            return Array(result.dropFirst().dropLast())
        }

        return result
    }

    @ViewBuilder
    private func slotView(for slot: MusicControlButton) -> some View {
        switch slot {
        case .shuffle:
            HoverButton(
                icon: "shuffle",
                iconColor: musicManager.isShuffled ? .red : .primary,
                scale: .medium,
                accessibilityLabel: "Shuffle",
                accessibilityHint: "Toggles shuffle playback",
                accessibilityValue: musicManager.isShuffled ? "On" : "Off"
            ) {
                MusicManager.shared.toggleShuffle()
            }
        case .previous:
            HoverButton(
                icon: "backward.fill",
                scale: .medium,
                accessibilityLabel: "Previous track",
                accessibilityHint: "Skips to the previous track"
            ) {
                MusicManager.shared.previousTrack()
            }
        case .playPause:
            HoverButton(
                icon: musicManager.isPlaying ? "pause.fill" : "play.fill",
                scale: .large,
                accessibilityLabel: musicManager.isPlaying ? "Pause" : "Play",
                accessibilityHint: "Controls playback"
            ) {
                MusicManager.shared.togglePlay()
            }
        case .next:
            HoverButton(
                icon: "forward.fill",
                scale: .medium,
                accessibilityLabel: "Next track",
                accessibilityHint: "Skips to the next track"
            ) {
                MusicManager.shared.nextTrack()
            }
        case .repeatMode:
            HoverButton(
                icon: repeatIcon,
                iconColor: repeatIconColor,
                scale: .medium,
                accessibilityLabel: "Repeat",
                accessibilityHint: "Cycles repeat mode",
                accessibilityValue: repeatModeDescription
            ) {
                MusicManager.shared.toggleRepeat()
            }
        case .volume:
            VolumeControlView()
        case .favorite:
            FavoriteControlButton()
        case .goBackward:
            HoverButton(
                icon: "gobackward.15",
                scale: .medium,
                accessibilityLabel: "Skip back 15 seconds",
                accessibilityHint: "Moves playback back 15 seconds"
            ) {
                MusicManager.shared.skip(seconds: -15)
            }
        case .goForward:
            HoverButton(
                icon: "goforward.15",
                scale: .medium,
                accessibilityLabel: "Skip forward 15 seconds",
                accessibilityHint: "Moves playback forward 15 seconds"
            ) {
                MusicManager.shared.skip(seconds: 15)
            }
        case .none:
            Color.clear.frame(height: 1)
        }
    }

    private var repeatModeDescription: String {
        switch musicManager.repeatMode {
        case .off: return "Off"
        case .all: return "All"
        case .one: return "One"
        }
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off:
            return "repeat"
        case .all:
            return "repeat"
        case .one:
            return "repeat.1"
        }
    }

    private var repeatIconColor: Color {
        switch musicManager.repeatMode {
        case .off:
            return .primary
        case .all, .one:
            return .red
        }
    }
}

struct FavoriteControlButton: View {
    @ObservedObject var musicManager = MusicManager.shared

    var body: some View {
        HoverButton(
            icon: iconName,
            iconColor: iconColor,
            scale: .medium,
            accessibilityLabel: musicManager.isFavoriteTrack ? "Remove from favorites" : "Add to favorites",
            accessibilityHint: "Updates the favorite status of the current track",
            accessibilityValue: musicManager.isFavoriteTrack ? "Favorited" : "Not favorited"
        ) {
            MusicManager.shared.toggleFavoriteTrack()
        }
        .disabled(!musicManager.canFavoriteTrack)
        .opacity(musicManager.canFavoriteTrack ? 1 : 0.35)
    }

    private var iconName: String {
        musicManager.isFavoriteTrack ? "heart.fill" : "heart"
    }

    private var iconColor: Color {
        musicManager.isFavoriteTrack ? .red : .primary
    }
}

private extension Array where Element == MusicControlButton {
    func padded(to length: Int, filler: MusicControlButton) -> [MusicControlButton] {
        if count >= length { return self }
        return self + Array(repeating: filler, count: length - count)
    }
}

// MARK: - Volume Control View

struct VolumeControlView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @State private var volumeSliderValue: Double = 0.5
    @State private var dragging: Bool = false
    @State private var showVolumeSlider: Bool = false
    @State private var lastVolumeUpdateTime: Date = Date.distantPast
    private let volumeUpdateThrottle: TimeInterval = 0.1
    
    var body: some View {
        HStack(spacing: 4) {
            Button(action: {
                if musicManager.volumeControlSupported {
                    withAnimation(BoringMotion.animation(.easeInOut(duration: 0.12))) {
                        showVolumeSlider.toggle()
                    }
                }
            }) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(musicManager.volumeControlSupported ? .white : .gray)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!musicManager.volumeControlSupported)
            .frame(width: 24)
            .accessibilityLabel(showVolumeSlider ? "Hide volume slider" : "Show volume slider")
            .accessibilityHint(
                musicManager.volumeControlSupported
                    ? "Shows controls for the current player's volume"
                    : "The current player does not support volume control"
            )

            if showVolumeSlider && musicManager.volumeControlSupported {
                CustomSlider(
                    value: $volumeSliderValue,
                    range: 0.0...1.0,
                    color: .white,
                    dragging: $dragging,
                    lastDragged: .constant(Date.distantPast),
                    onValueChange: { newValue in
                        MusicManager.shared.setVolume(to: newValue)
                    },
                    onDragChange: { newValue in
                        let now = Date()
                        if now.timeIntervalSince(lastVolumeUpdateTime) > volumeUpdateThrottle {
                            MusicManager.shared.setVolume(to: newValue)
                            lastVolumeUpdateTime = now
                        }
                    }
                )
                .frame(width: 48, height: 8)
                .transition(.scale.combined(with: .opacity))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Volume")
                .accessibilityValue("\(Int((volumeSliderValue * 100).rounded())) percent")
                .accessibilityAdjustableAction { direction in
                    let step = 0.05
                    let newValue: Double
                    switch direction {
                    case .increment:
                        newValue = min(1, volumeSliderValue + step)
                    case .decrement:
                        newValue = max(0, volumeSliderValue - step)
                    @unknown default:
                        return
                    }
                    volumeSliderValue = newValue
                    MusicManager.shared.setVolume(to: newValue)
                }
            }
        }
        .clipped()
        .onReceive(musicManager.$volume) { volume in
            if !dragging {
                volumeSliderValue = volume
            }
        }
        .onReceive(musicManager.$volumeControlSupported) { supported in
            if !supported {
                withAnimation(BoringMotion.animation(.easeInOut(duration: 0.2))) {
                    showVolumeSlider = false
                }
            }
        }
        .onChange(of: showVolumeSlider) { _, isShowing in
            if isShowing {
                // Sync volume from app when slider appears
                Task {
                    await MusicManager.shared.syncVolumeFromActiveApp()
                }
            }
        }
        .onDisappear {
            // volumeUpdateTask?.cancel() // No longer needed
        }
    }
    
    
    private var volumeIcon: String {
        if !musicManager.volumeControlSupported {
            return "speaker.slash"
        } else if volumeSliderValue == 0 {
            return "speaker.slash.fill"
        } else if volumeSliderValue < 0.33 {
            return "speaker.1.fill"
        } else if volumeSliderValue < 0.66 {
            return "speaker.2.fill"
        } else {
            return "speaker.3.fill"
        }
    }
}

// MARK: - Main View

struct NotchHomeView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var webcamManager = WebcamManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    let albumArtNamespace: Namespace.ID

    var body: some View {
        Group {
            if !coordinator.firstLaunch {
                mainContent
            }
        }
        // simplified: use a straightforward opacity transition
        .transition(.opacity)
    }

    private var shouldShowCamera: Bool {
        Defaults[.showMirror] && webcamManager.cameraAvailable && vm.isCameraExpanded
    }

    private var mainContent: some View {
        HStack(alignment: .top, spacing: (shouldShowCamera && Defaults[.showCalendar]) ? 10 : 15) {
            MusicPlayerView(albumArtNamespace: albumArtNamespace)

            if Defaults[.showCalendar] {
                CalendarView()
                    .frame(width: shouldShowCamera ? 170 : 215)
                    .onHover { isHovering in
                        vm.isHoveringCalendar = isHovering
                    }
                    .environmentObject(vm)
                    .transition(.opacity)
            }

            if shouldShowCamera {
                CameraPreviewView(webcamManager: webcamManager)
                    .scaledToFit()
                    .opacity(vm.notchState == .closed ? 0 : 1)
                    .blur(radius: vm.notchState == .closed ? 20 : 0)
                    .animation(
                        BoringMotion.animation(
                            .interactiveSpring(response: 0.32, dampingFraction: 0.76, blendDuration: 0)
                        ),
                        value: shouldShowCamera
                    )
            }
        }
        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
        .blur(radius: vm.notchState == .closed ? 30 : 0)
    }
}

struct MusicSliderView: View {
    @Binding var sliderValue: Double
    @Binding var duration: Double
    @Binding var lastDragged: Date
    var color: NSColor
    @Binding var dragging: Bool
    let currentDate: Date
    let timestampDate: Date
    let elapsedTime: Double
    let playbackRate: Double
    let isPlaying: Bool
    var onValueChange: (Double) -> Void


    var body: some View {
        VStack {
            CustomSlider(
                value: $sliderValue,
                range: 0...duration,
                color: Defaults[.sliderColor] == SliderColorEnum.albumArt
                    ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.8)
                    : Defaults[.sliderColor] == SliderColorEnum.accent ? .effectiveAccent : .white,
                dragging: $dragging,
                lastDragged: $lastDragged,
                onValueChange: onValueChange
            )
            .frame(height: 10, alignment: .center)

            HStack {
                Text(timeString(from: sliderValue))
                Spacer()
                Text(timeString(from: duration))
            }
            .fontWeight(.medium)
            .foregroundColor(
                Defaults[.playerColorTinting]
                    ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.6) : .gray
            )
            .font(.caption)
        }
        .onChange(of: currentDate) {
           guard !dragging, timestampDate.timeIntervalSince(lastDragged) > -1 else { return }
            sliderValue = MusicManager.shared.estimatedPlaybackPosition(at: currentDate)
        }
    }

    func timeString(from seconds: Double) -> String {
        let totalMinutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
    }
}

struct CustomSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color = .white
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    var onValueChange: ((Double) -> Void)?
    var onDragChange: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = CGFloat(dragging ? 9 : 5)
            let rangeSpan = range.upperBound - range.lowerBound

            let progress = rangeSpan == .zero ? 0 : (value - range.lowerBound) / rangeSpan
            let filledTrackWidth = min(max(progress, 0), 1) * width

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.gray.opacity(0.3))
                    .frame(height: height)

                Rectangle()
                    .fill(color)
                    .frame(width: filledTrackWidth, height: height)
            }
            .cornerRadius(height / 2)
            .frame(height: 10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        withAnimation(BoringMotion.animation(.default)) {
                            dragging = true
                        }
                        let newValue = range.lowerBound + Double(gesture.location.x / width) * rangeSpan
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                        onDragChange?(value)
                    }
                    .onEnded { _ in
                        onValueChange?(value)
                        dragging = false
                        lastDragged = Date()
                    }
            )
            .animation(
                BoringMotion.animation(.spring(response: 0.35, dampingFraction: 0.7)),
                value: dragging
            )
        }
    }
}


struct PomodoroTimerView: View {
    @ObservedObject private var timer = PomodoroTimer.shared

    var body: some View {
        VStack(spacing: 4) {
            VStack(spacing: 0) {
                Text(timer.phase.rawValue)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(timer.formattedRemaining)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }

            ProgressView(value: timer.progress)
                .tint(.effectiveAccent)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .frame(maxWidth: 200)
                .accessibilityLabel("Pomodoro progress")
                .accessibilityValue("\(Int((timer.progress * 100).rounded())) percent")

            HStack(spacing: 4) {
                Button(timer.isRunning ? "Pause" : "Start") {
                    timer.toggle()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .accessibilityHint("Starts or pauses the current Pomodoro phase")

                Button("Reset") {
                    timer.reset()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .accessibilityHint("Resets the current phase")

                Button {
                    timer.skipPhase()
                } label: {
                    Image(systemName: "forward.end.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Skip phase")
                .accessibilityLabel("Skip phase")
                .accessibilityHint("Moves to the next Pomodoro phase")
            }

            Text("Sessions: \(timer.completedWorkSessions)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(timer.completedWorkSessions) completed work sessions")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .frame(maxWidth: 240)
        .background(
            RoundedRectangle(cornerRadius: NotchPanelStyle.cornerRadius)
                .fill(.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NotchPanelStyle.cornerRadius)
                .strokeBorder(NotchPanelStyle.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: NotchPanelStyle.cornerRadius))
    }
}

// MARK: - Quick notes

struct NotchNotesView: View {
    @Default(.notesText) private var notes
    @FocusState private var isFocused: Bool

    private var detail: String {
        guard !notes.isEmpty else { return "Saved locally" }
        return notes.count == 1 ? "1 character" : "\(notes.count) characters"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NotchPanelStyle.spacing) {
            NotchPanelHeader(icon: "note.text", title: "Notes", detail: detail) {
                if !notes.isEmpty {
                    Button {
                        withAnimation(BoringMotion.animation(.easeOut(duration: 0.15))) {
                            notes = ""
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.65))
                            .padding(4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Clear notes")
                    .accessibilityLabel("Clear notes")
                    .accessibilityHint("Deletes the saved note")
                    .transition(.opacity)
                }
            }

            ZStack(alignment: .topLeading) {
                if notes.isEmpty {
                    Text("Type a quick note…")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.top, 8)
                        .padding(.leading, 9)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $notes)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .focused($isFocused)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .accessibilityLabel("Quick notes")
                    .accessibilityHint("Type a note. Changes are saved automatically.")
            }
            .background(
                RoundedRectangle(cornerRadius: NotchPanelStyle.cornerRadius, style: .continuous)
                    .fill(isFocused ? NotchPanelStyle.activeBackground : NotchPanelStyle.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: NotchPanelStyle.cornerRadius, style: .continuous)
                    .strokeBorder(
                        isFocused ? NotchPanelStyle.activeBorder : NotchPanelStyle.border,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { isFocused = true })
            .animation(BoringMotion.animation(.easeOut(duration: 0.18)), value: isFocused)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 3)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { NotchTextInput.begin() }
        .onDisappear { NotchTextInput.end() }
    }
}
