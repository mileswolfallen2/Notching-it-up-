//
//  OnboardingView.swift
//  boringNotch
//
//  Created by Alexander on 2025-06-23.
//

import SwiftUI
import AVFoundation
import Defaults

enum OnboardingStep {
    case welcome
    case featureSelection
    case permissionsGuide
    case cameraPermission
    case calendarPermission
    case remindersPermission
    case accessibilityPermission
    case musicPermission
    case finished
}

private let calendarService = CalendarService()

struct OnboardingView: View {
    @State var step: OnboardingStep = .welcome
    let onFinish: () -> Void
    let onOpenSettings: () -> Void
    let onOpenAISettings: () -> Void
    @State private var shouldOpenAISettings = false

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                WelcomeView {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        step = .featureSelection
                    }
                }
                .transition(.opacity)

            case .featureSelection:
                FeatureSelectionView { openAISettings in
                    shouldOpenAISettings = openAISettings
                    withAnimation(.easeInOut(duration: 0.6)) {
                        step = .permissionsGuide
                    }
                }
                .transition(.opacity)

            case .permissionsGuide:
                PermissionsGuideView {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        step = .cameraPermission
                    }
                }
                .transition(.opacity)

            case .cameraPermission:
                PermissionRequestView(
                    icon: Image(systemName: "camera.fill"),
                    title: "Enable Camera Access",
                    description: "Notching it up includes a mirror feature that lets you quickly check your appearance using your camera, right from the notch. Camera access is required only to show this live preview. You can turn the mirror feature on or off at any time in the app.",
                    privacyNote: "Your camera is never used without your consent, and nothing is recorded or stored.",
                    onAllow: {
                        Task {
                            await requestCameraPermission()
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .calendarPermission
                            }
                        }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .calendarPermission
                        }
                    }
                )
                .transition(.opacity)

            case .calendarPermission:
                PermissionRequestView(
                    icon: Image(systemName: "calendar"),
                    title: "Enable Calendar Access",
                    description: "Notching it up can show all your upcoming events in one place. Access to your calendar is needed to display your schedule.",
                    privacyNote: "Your calendar data is only used to show your events and is never shared.",
                    onAllow: {
                        Task {
                                await requestCalendarPermission()
                                withAnimation(.easeInOut(duration: 0.6)) {
                                    step = .remindersPermission
                                }
                        }
                    },
                    onSkip: {
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .remindersPermission
                            }
                    }
                )
                .transition(.opacity)

                case .remindersPermission:
                    PermissionRequestView(
                        icon: Image(systemName: "checklist"),
                        title: "Enable Reminders Access",
                        description: "Notching it up can show your scheduled reminders alongside your calendar events. Access to Reminders is needed to display your reminders.",
                        privacyNote: "Your reminders data is only used to show your reminders and is never shared.",
                        onAllow: {
                            Task {
                                await requestRemindersPermission()
                                withAnimation(.easeInOut(duration: 0.6)) {
                                    step = .accessibilityPermission
                                }
                            }
                        },
                        onSkip: {
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .accessibilityPermission
                            }
                        }
                    )
                    .transition(.opacity)
                
            case .accessibilityPermission:
                PermissionRequestView(
                    icon: Image(systemName: "hand.raised.fill"),
                    title: "Enable Accessibility Access",
                    description: "Accessibility access is required to replace system notifications with the Notching it up HUD. This allows the app to intercept media and brightness events to display custom HUD overlays.",
                    privacyNote: "Accessibility access is used only to improve media and brightness notifications. No data is collected or shared.",
                    onAllow: {
                        Task {
                            await requestAccessibilityPermission()
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .musicPermission
                            }
                        }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .musicPermission
                        }
                    }
                )
                .transition(.opacity)
                
            case .musicPermission:
                MusicControllerSelectionView(
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            BoringViewCoordinator.shared.firstLaunch = false
                            step = .finished
                        }
                    }
                )
                .transition(.opacity)

            case .finished:
                OnboardingFinishView(
                    onFinish: onFinish,
                    onOpenSettings: shouldOpenAISettings ? onOpenAISettings : onOpenSettings,
                    settingsButtonTitle: shouldOpenAISettings ? "Set Up AI" : "Customize in Settings"
                )
            }

        }
        .frame(width: 400, height: 600)
    }

    // MARK: - Permission Request Logic

    func requestCameraPermission() async {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func requestCalendarPermission() async {
        _ = try? await calendarService.requestAccess(to: .event)
    }

    func requestRemindersPermission() async {
        _ = try? await calendarService.requestAccess(to: .reminder)
    }
    
    func requestAccessibilityPermission() async {
        await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
    }
}

private struct FeatureSelectionView: View {
    let onContinue: (_ shouldOpenAISettings: Bool) -> Void

    @State private var showHomeTab = Defaults[.showHomeTab]
    @State private var showShelfTab = Defaults[.showShelfTab]
    @State private var showTimerTab = Defaults[.showTimerTab]
    @State private var showNotesTab = Defaults[.showNotesTab]
    @State private var showAITab = Defaults[.showAITab]
    @State private var showDevicesTab = Defaults[.showDevicesTab]

    private var hasSelection: Bool {
        showHomeTab || showShelfTab || showTimerTab || showNotesTab || showAITab || showDevicesTab
    }

    var body: some View {
        VStack(spacing: 18) {
            Text("Choose what to use")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top, 24)

            Text("Choose the tabs you want to see in the notch. You can change this later in Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            ScrollView {
                VStack(spacing: 10) {
                    featureToggle("Home", icon: "house.fill", isOn: $showHomeTab)
                    featureToggle("Files", icon: "tray.fill", isOn: $showShelfTab)
                    featureToggle("Timer", icon: "timer", isOn: $showTimerTab)
                    featureToggle("Notes", icon: "note.text", isOn: $showNotesTab)
                    featureToggle("AI", icon: "sparkles", isOn: $showAITab)
                    featureToggle("Devices", icon: "headphones", isOn: $showDevicesTab)
                }
                .padding()
            }

            Button("Continue") {
                Defaults[.showHomeTab] = showHomeTab
                Defaults[.showShelfTab] = showShelfTab
                Defaults[.showTimerTab] = showTimerTab
                Defaults[.showNotesTab] = showNotesTab
                Defaults[.showAITab] = showAITab
                Defaults[.showDevicesTab] = showDevicesTab
                onContinue(showAITab)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!hasSelection)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }

    private func featureToggle(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label(title, systemImage: icon)
                .font(.headline)
        }
        .toggleStyle(.switch)
        .padding()
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}
