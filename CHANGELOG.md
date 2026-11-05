# Changelog

All notable changes to Notching it up are documented here.
## [Unreleased]

## [0.2.6.2]

### Added

- Bluetooth support across the notch:
  - First-run setup now asks for Bluetooth access, and the permissions guide explains what it is used for. The prompt is part of setup only, so normal launches do not ask again.
  - Devices tab for connected headphones and speakers, with battery levels, hover details, and a shortcut to Bluetooth settings. The tab is optional and can be enabled during setup or in Settings.
  - Bluetooth Live Activity for speaker and headphone connect and disconnect events. Non-audio Bluetooth devices, including cameras, are ignored, and the activity can be turned off in Settings.
- Hidden Developer settings panel. Select About and press Command-7 to unlock permission controls, including Bluetooth request and reset, plus app diagnostics for the current session. Press Command-7 again to relock it.
- First-run setup now defaults to Home and Files, lets users choose which tabs to enable, and opens AI settings when AI is selected. It also walks through Camera, Calendar, Reminders, Bluetooth, Accessibility, and media access.
- First-run permissions guide that explains when Calendar, Media, Bluetooth, Accessibility, and Notification access is requested as features are enabled.
- “Reset Notching it up” in Advanced. The red destructive action restores every setting, removes local AI sign-ins, notes, and saved shelf entries, then restarts the app.

### Changed

- Improved tab switching: the selection capsule glides between tabs with a smooth animation, drag gestures switch tabs and settle cleanly, and tab spacing compacts automatically so every enabled tab fits around the physical notch.
- Bluetooth connection activity now enters with a softer spring, dismisses with a gentler fade and scale, and resizes the notch chin in step with the activity. The animation can be disabled in Settings.
- Bluetooth device rows now show connection state and battery details with clearer hover feedback, while the live activity shows the device name and a clear connected or disconnected state.
- Developer permission tools can reset individual privacy decisions through the helper, reset all permissions at once, and copy a full diagnostics snapshot.
- Local test builds can be packaged as a DMG with `make_test_dmg.sh`. Test DMGs use an ad-hoc signature with hardened runtime disabled so the bundled MediaRemote adapter loads, and they are excluded from git.

### Fixed

- Kept onboarding and Bluetooth prompts first-run only. Completing setup prevents them from appearing on later launches.
- Fixed the test DMG failing to launch because of library validation on the ad-hoc-signed MediaRemote adapter.
- Fixed Bluetooth activity removal leaving a visible pop or clipped chin by fading and scaling it out inside the existing spring animation.

## [0.2.6.1]

### Added

- AI ring color styles: Monochrome (default), Provider, Accent, and Usage. The Usage style switches from green to amber to red as a plan runs low.
- “Show manual plans in the notch” setting. Adding a provider that is not signed in turns it on automatically.

### Changed

- The notch now shows signed-in AI providers by default. Manual plans stay hidden until you enable them in AI settings.
- Monochrome remains the default AI card style. Color is only applied when a different ring style is chosen.
- Standardized notch panel headers, card corners, focus states, and tab hover feedback, and clarified AI settings labels and copy.

### Fixed

- Fixed Notes not accepting keyboard input. The notch panel can become key only while the Notes tab is visible, so typing works without changing how the other tabs behave.
- Fixed the top bar running under the physical notch when all five tabs were enabled. Tab buttons now tighten their spacing as more tabs are shown.
- Hardened AI sync and storage: stale sign-in results are discarded, provider requests time out cleanly, and an unreadable account file is preserved as a backup instead of being overwritten.

## [0.2.6] - 2026-11-02

### Added

- Live AI usage for signed-in accounts. Connect Claude, ChatGPT (Codex), Antigravity, or GitHub Copilot once and the notch reads the same limits your provider shows.
- Automatic AI usage refresh every five minutes, when the app activates, and on demand. Manual plans keep their own reset countdowns.
- New Notes tab: a persistent local scratchpad that stays available between launches and can be shown, hidden, or reordered with the other notch tabs.
- Low-usage alerts and reset countdowns for tracked AI plans.

### Changed

- Redesigned AI usage cards around a simple monochrome ring, a centered percentage, and the provider name. Plan, account, and reset details moved to hover text and the context menu.
- Simplified AI settings by removing redundant display toggles and folding maintenance actions into a menu.
- AI cards and settings now stay monochrome instead of using per-provider accent colors.
- AI sign-ins now use the new local credential store, so sign in once after updating.

### Fixed

- Removed the repeated Keychain approval prompt. Provider tokens are now stored in the app's private Application Support folder with restricted permissions, so rebuilding or updating the ad-hoc signed app no longer asks for Keychain access.
- Fixed the AI Usage settings pane jumping upward when opened. Each settings pane now starts at the top instead of inheriting the previous pane's scroll position.
- Fixed top-bar tab drag reordering. Dragging a tab now inserts it at the drop position instead of swapping it with the target and scrambling the surrounding order.
- Fixed calendar date-range comparisons that could misclassify all-day and multi-day events.

### Security

- AI credentials no longer use the login Keychain. The local account file is excluded from backups and written atomically with owner-only permissions.
