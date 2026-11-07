//
//  MotionLabView.swift
//  boringNotch
//
//  Hidden developer panel for checking the app's animations with and without
//  Reduce Motion. Each row mirrors an animation used elsewhere in the app.
//

import Defaults
import SwiftUI

struct MotionLabView: View {
    @ObservedObject private var motion = MotionPreferences.shared
    @Default(.followSystemReduceMotion) private var followSystemReduceMotion
    @Default(.reduceMotion) private var reduceMotion
    @State private var replayCycle = 0

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .followSystemReduceMotion) {
                    Text("Follow system Reduce Motion")
                }
                Defaults.Toggle(key: .reduceMotion) {
                    Text("Reduce motion")
                }

                HStack {
                    Text("Current behavior")
                    Spacer()
                    Text(motion.shouldReduceMotion ? "Reduced" : "Full motion")
                        .foregroundStyle(motion.shouldReduceMotion ? .orange : .green)
                }

                if motion.systemPrefersReducedMotion {
                    Label("macOS Reduce Motion is on", systemImage: "accessibility")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    replayCycle += 1
                } label: {
                    Label("Replay all tests", systemImage: "play.circle")
                }
                .controlSize(.small)
            } header: {
                Text("Motion settings")
            } footer: {
                Text("Each preview uses the same motion helpers as the live app. Turn Reduce motion on and replay a test to confirm it becomes instant.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                MotionDemoRow(
                    title: "Notch open and close",
                    description: "The notch spring used when opening and closing, including the shadow."
                ) {
                    NotchSpringDemo(replayCycle: replayCycle)
                }

                MotionDemoRow(
                    title: "Tab capsule",
                    description: "Matched-geometry capsule movement between top-bar tabs."
                ) {
                    TabCapsuleDemo()
                }

                MotionDemoRow(
                    title: "Panel transition",
                    description: "Scale and fade used when a notch tab appears."
                ) {
                    PanelTransitionDemo(replayCycle: replayCycle)
                }

                MotionDemoRow(
                    title: "Live activity",
                    description: "Spring expansion and fade used for Bluetooth and music live activities."
                ) {
                    LiveActivityDemo(replayCycle: replayCycle)
                }
            } header: {
                Text("Notch and navigation")
            }

            Section {
                MotionDemoRow(
                    title: "Idle face",
                    description: "The blinking face shown when the closed notch is idle."
                ) {
                    BlinkingFaceDemo()
                }

                MotionDemoRow(
                    title: "Music visualizer",
                    description: "The four-bar spectrum animation from the closed-notch live activity."
                ) {
                    MusicVisualizerDemo()
                }

                MotionDemoRow(
                    title: "Marquee text",
                    description: "Long titles scroll in the notch. Reduce Motion keeps the text still."
                ) {
                    MarqueeDemo()
                }

                MotionDemoRow(
                    title: "Album art crossfade",
                    description: "Artwork and title transitions when the track changes."
                ) {
                    AlbumArtCrossfadeDemo(replayCycle: replayCycle)
                }
            } header: {
                Text("Live activity content")
            }

            Section {
                MotionDemoRow(
                    title: "Progress slider",
                    description: "The draggable music and volume slider spring."
                ) {
                    SliderDemo()
                }

                MotionDemoRow(
                    title: "AI usage ring",
                    description: "The trim animation used when AI usage percentages update."
                ) {
                    AIRingDemo(replayCycle: replayCycle)
                }

                MotionDemoRow(
                    title: "HUD indicator",
                    description: "The volume and brightness HUD fill animation."
                ) {
                    HUDBarDemo(replayCycle: replayCycle)
                }

                MotionDemoRow(
                    title: "Hover feedback",
                    description: "The shared hover highlight used by music controls and notch buttons."
                ) {
                    HoverDemo()
                }

                MotionDemoRow(
                    title: "Onboarding step",
                    description: "The opacity transition between first-run setup steps."
                ) {
                    OnboardingStepDemo()
                }
            } header: {
                Text("Controls and content")
            }
        }
        .navigationTitle("Motion")
    }
}

// MARK: - Shared row

private struct MotionDemoRow<Demo: View>: View {
    let title: String
    let description: String
    let demo: Demo

    init(title: String, description: String, @ViewBuilder demo: () -> Demo) {
        self.title = title
        self.description = description
        self.demo = demo()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            demo
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Demo views

private struct NotchSpringDemo: View {
    let replayCycle: Int
    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: isOpen ? 18 : 12, style: .continuous)
                    .fill(Color.black)
                    .frame(width: isOpen ? 360 : 160, height: isOpen ? 74 : 24)
                    .overlay {
                        if isOpen {
                            HStack(spacing: 8) {
                                Image(systemName: "cloud.sun.fill")
                                Text("Weather, music, calendar")
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .transition(.opacity)
                        }
                    }
                    .shadow(color: .black.opacity(0.5), radius: isOpen ? 8 : 3, y: 2)
            }
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .top)
            .animation(
                BoringMotion.animation(
                    isOpen
                        ? .spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
                        : .spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
                ),
                value: isOpen
            )

            Button(isOpen ? "Close preview" : "Open preview") {
                isOpen.toggle()
            }
            .controlSize(.small)
        }
        .onChange(of: replayCycle) { _, _ in
            isOpen = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isOpen = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notch open and close preview")
    }
}

private struct TabCapsuleDemo: View {
    @Namespace private var namespace
    @State private var selected = 0
    private let tabs: [(label: String, icon: String)] = [
        ("Home", "house.fill"),
        ("Weather", "cloud.sun.fill"),
        ("Shelf", "tray.fill"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                Button {
                    withAnimation(BoringMotion.animation(.smooth)) {
                        selected = index
                    }
                } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background {
                            if selected == index {
                                Capsule()
                                    .fill(Color.primary.opacity(0.12))
                                    .matchedGeometryEffect(id: "capsule", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.label)
                .accessibilityAddTraits(selected == index ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
        .clipShape(Capsule())
    }
}

private struct PanelTransitionDemo: View {
    let replayCycle: Int
    @State private var isVisible = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                if isVisible {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.12))
                        .overlay {
                            Text("Panel content")
                                .font(.caption.weight(.medium))
                        }
                        .transition(.scale(scale: 0.8, anchor: .top).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .top)
            .animation(BoringMotion.animation(.smooth(duration: 0.35)), value: isVisible)

            Button(isVisible ? "Hide panel" : "Show panel") {
                isVisible.toggle()
            }
            .controlSize(.small)
        }
        .onChange(of: replayCycle) { _, _ in
            isVisible = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isVisible = true
            }
        }
    }
}

private struct LiveActivityDemo: View {
    let replayCycle: Int
    @State private var isConnected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black)
                    .frame(width: isConnected ? 250 : 140, height: 44)
                    .overlay {
                        if isConnected {
                            HStack(spacing: 7) {
                                Image(systemName: "headphones")
                                Text("Headphones connected")
                                Spacer(minLength: 0)
                                Image(systemName: "battery.75")
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                        }
                    }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(
                BoringMotion.animation(.spring(response: 0.36, dampingFraction: 0.66, blendDuration: 0)),
                value: isConnected
            )

            Button(isConnected ? "Disconnect" : "Connect") {
                isConnected.toggle()
            }
            .controlSize(.small)
        }
        .onChange(of: replayCycle) { _, _ in
            isConnected = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isConnected = true
            }
        }
    }
}

private struct BlinkingFaceDemo: View {
    var body: some View {
        HStack(spacing: 12) {
            MinimalFaceFeatures()
                .frame(width: 40, height: 40)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text("The face blinks every three seconds. Reduce Motion stops the timer.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MusicVisualizerDemo: View {
    @State private var isPlaying = true

    var body: some View {
        HStack(spacing: 12) {
            AudioSpectrumView(isPlaying: $isPlaying)
                .frame(width: 24, height: 24)
                .padding(6)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button(isPlaying ? "Pause bars" : "Play bars") {
                isPlaying.toggle()
            }
            .controlSize(.small)

            Text(isPlaying ? "Bars animate while playing." : "Bars are still.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MarqueeDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MarqueeText(
                .constant("A long track title that keeps moving across the notch — Motion Lab"),
                font: .subheadline,
                nsFont: .subheadline,
                textColor: .primary,
                frameWidth: 280
            )
            .frame(width: 280, alignment: .leading)

            Text("Reduce Motion freezes scrolling and keeps the full title readable.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AlbumArtCrossfadeDemo: View {
    let replayCycle: Int
    @State private var showSecond = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                artwork(color: .blue, icon: "music.note")
                    .opacity(showSecond ? 0 : 1)
                    .scaleEffect(showSecond ? 0.94 : 1)
                artwork(color: .purple, icon: "opticaldisc")
                    .opacity(showSecond ? 1 : 0)
                    .scaleEffect(showSecond ? 1 : 0.94)
            }
            .frame(width: 68, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .animation(BoringMotion.animation(.spring(response: 0.35, dampingFraction: 0.8)), value: showSecond)

            Button("Switch artwork") {
                showSecond.toggle()
            }
            .controlSize(.small)
        }
        .onChange(of: replayCycle) { _, _ in
            showSecond.toggle()
        }
    }

    private func artwork(color: Color, icon: String) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.9), color.opacity(0.45)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
    }
}

private struct SliderDemo: View {
    @State private var value = 0.35
    @State private var dragging = false
    @State private var lastDragged = Date.distantPast

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CustomSlider(
                value: $value,
                range: 0...1,
                color: .blue,
                dragging: $dragging,
                lastDragged: $lastDragged,
                onValueChange: { _ in },
                onDragChange: { _ in }
            )
            .frame(height: 20)

            Text("\(Int((value * 100).rounded())) percent")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private struct AIRingDemo: View {
    let replayCycle: Int
    @State private var progress = 0.35

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color.blue,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
            }
            .frame(width: 58, height: 58)
            .animation(BoringMotion.animation(.easeOut(duration: 0.55)), value: progress)

            Button("Change usage") {
                progress = progress < 0.5 ? 0.9 : 0.35
            }
            .controlSize(.small)
        }
        .onChange(of: replayCycle) { _, _ in
            progress = progress < 0.5 ? 0.9 : 0.35
        }
    }
}

private struct HUDBarDemo: View {
    let replayCycle: Int
    @State private var value: CGFloat = 0.4

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.white)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.16))
                        Capsule()
                            .fill(Color.white)
                            .frame(width: geometry.size.width * value)
                    }
                }
                .frame(height: 6)
                .frame(maxWidth: 160)

                Text("\(Int((value * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 250, alignment: .leading)
            .background(Capsule().fill(Color.black))
            .animation(BoringMotion.animation(.smooth(duration: 0.3)), value: value)

            Button("Change volume") {
                value = value > 0.7 ? 0.25 : min(1, value + 0.25)
            }
            .controlSize(.small)
        }
        .onChange(of: replayCycle) { _, _ in
            value = value > 0.7 ? 0.25 : min(1, value + 0.25)
        }
    }
}

private struct HoverDemo: View {
    var body: some View {
        HStack(spacing: 12) {
            HoverButton(
                icon: "heart.fill",
                iconColor: .pink,
                scale: .large,
                accessibilityLabel: "Hover feedback",
                accessibilityHint: "Highlights when the pointer is over the control"
            ) {}
            Text("Hover the heart to check the shared highlight animation.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct OnboardingStepDemo: View {
    @State private var step = 0
    private let steps = ["Welcome", "Permissions", "Finished"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Text(steps[step])
                    .font(.headline)
                    .id(step)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .animation(BoringMotion.animation(.easeInOut(duration: 0.6)), value: step)

            Button("Next step") {
                step = (step + 1) % steps.count
            }
            .controlSize(.small)
        }
    }
}
