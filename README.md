<h1 align="center">
  <br>
  Notching it up
  <br>
</h1>

<p align="center">
  A fork of <a href="https://github.com/TheBoredTeam/boring.notch"><strong>Boring Notch</strong></a> by <a href="https://github.com/TheBoredTeam">TheBoredTeam</a>
</p>

<p align="center">
  Make your MacBook's notch useful again. Notching it up transforms the notch into a dynamic music player, calendar, file shelf with AirDrop, system HUD replacement, and more.
</p>

<p align="center">
  <img src="https://github.com/user-attachments/assets/2d5f69c1-6e7b-4bc2-a6f1-bb9e27cf88a8" alt="Demo GIF" />
</p>
## Why this fork

I've become increasingly unhappy with the direction Boring Notch is heading. It feels like the focus is shifting away from improving the actual application and delivering the features and polish that made it worth using in the first place, and more toward building an extension/plugin ecosystem and introducing paid features.

I believe the core app should come first. It should be fast, polished, useful, customizable, and feel like a natural part of macOS without requiring add-ons to make it great. That's exactly why I decided to start **Notching it up**: to take what makes Boring Notch great, build on it, and focus on making the actual notch experience better.

---

## Features

- **Music Control** - Control Apple Music, Spotify, and other media apps right from the notch with album art, playback controls, and lyrics
- **Calendar & Reminders** - View upcoming events and reminders in one place, with one-click Join for supported meeting links
- **Weather** - Check current conditions and a five-day forecast for a city you choose, in Celsius or Fahrenheit, powered by Open-Meteo without an API key or location permission
- **File Shelf** - Drag and drop files for quick AirDrop or temporary storage
- **HUD Replacement** - Replace macOS volume, brightness, and keyboard backlight HUDs with sleek notch overlays (enabled by default)
- **Camera Mirror** - Quick mirror view right from the notch
- **Pomodoro Timer** - Run focused work and break sessions without leaving the notch
- **Quick Notes** - Keep a persistent scratchpad in the notch for short notes and reminders
- **AI Usage Dashboard** - Sign in to Claude, ChatGPT, GitHub Copilot, or Antigravity for live limits, choose a ring color style, track other plans manually, and keep credentials in local app storage. Signed-in accounts appear in the notch automatically; manual plans are opt-in.
- **Customizable** - Tweak the notch to fit your needs with gestures, sizing, and more
- **Configurable layout** - Choose which tabs appear in the open notch and arrange them to fit your workflow
- **Keyboard shortcuts** - Open the notch, trigger sneak peek, and access supported panels without reaching for the mouse
- **Accessibility** - Follow macOS Reduce Motion or opt into reduced motion, with VoiceOver labels and keyboard navigation across the notch
- **Advanced Options** - Keep the default settings simple, with advanced controls available when you need them

## Project status

Notching it up is an actively developed fork. The core notch, media controls, shelf, calendar, HUD replacement, lyrics, timer, notes, AI usage, and customization features are usable today. Some integrations and advanced ideas below are still exploratory, so the roadmap is directional rather than a promise of release dates.

---

## Installation

### System Requirements
- macOS 14 Sonoma or later
- Apple Silicon or Intel Mac

### Option 1: Download and Install Manually
1. Download the latest DMG from the [Releases](https://github.com/mileswolfallen2/Notching-it-up-/releases) page
2. Open the `.dmg` and move **Notching it up** to your `/Applications` folder
3. Since this app isn't notarized with an Apple Developer account, you'll need to bypass Gatekeeper on first launch

#### Recommended: Terminal (Always Works)
```bash
xattr -dr com.apple.quarantine "/Applications/Notching it up.app"
```

Then open the app normally.

#### Alternative: System Settings
1. Try to open the app - you'll see a security warning
2. Click **OK** to dismiss it
3. Open **System Settings** > **Privacy & Security**
4. Scroll to the bottom and click **Open Anyway** next to the Notching it up warning
5. Confirm if prompted

### Option 2: Build from Source

#### Prerequisites
- macOS 15.6 or later
- Xcode 26 or later

#### Steps
1. Clone the repository:
   ```bash
   git clone https://github.com/mileswolfallen2/Notching-it-up-.git
   cd Notching-it-up-
   ```

2. Open the project in Xcode:
   ```bash
   open noching.xcodeproj
   ```

3. Build and run with `Cmd + R`

### Command-line build

From the repository root, resolve Swift packages and build the release
configuration with:

```bash
xcodebuild -resolvePackageDependencies -project noching.xcodeproj
xcodebuild \
  -project noching.xcodeproj \
  -scheme boringNotch \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  build
```

The project file is named `noching.xcodeproj`; `boringNotch` is the app
scheme and target.

### Auto-updates

The app uses Sparkle. It starts the updater at launch and the **Check for
Updates…** menu item checks the feed at
[`updater/appcast.xml`](updater/appcast.xml). Releases must be published
through the **Deploy Notching it up** workflow so the final signed DMG,
Sparkle EdDSA signature, embedded release notes, and appcast entry are
generated together. Do not edit the signature or DMG URL by hand: the
signature is specific to the final DMG.

To publish a release:

1. Merge the reviewed release changes into `main`.
2. Run **Deploy Notching it up** with `0.2.2` (the workflow adds the `v`
   tag), and provide the repository's Sparkle private-key secret.(If you don't have this, you shouldn't be trying to push an update. Please contact mileswolfallen2 to push an update to all client apps)
3. Confirm the draft release's DMG downloads and the generated appcast entry
   points to that exact asset before publishing.
4. Install the published DMG over an older version and choose **Check for
   Updates…** to verify the update.

---

## Usage

- Launch the app - it will appear in your menu bar (this is a menu bar app)
- Click the notch to expand it, or turn on **Open notch on hover** in Settings to expand it by hovering
- Right-click the menu bar icon or open Settings to customize
- Use the "Advanced options" toggle in General settings to show/hide more complex options

---

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.

---

## License

This project is licensed under the **GNU General Public License v3.0**. See the [LICENSE](LICENSE) file for details.

---

## Acknowledgments

This project is a fork of [**Boring Notch**](https://github.com/TheBoredTeam/boring.notch) by [TheBoredTeam](https://github.com/TheBoredTeam). Huge thanks to the original authors and contributors for creating this amazing project.

### Notable Projects Used
- **[MediaRemoteAdapter](https://github.com/ungive/mediaremote-adapter)** - Now Playing source for macOS 15.4+
- **[NotchDrop](https://github.com/Lakr233/NotchDrop)** - Inspired the Shelf feature
- **[Sparkle](https://sparkle-project.org/)** - Auto-updates

### Original Credits
- Icon credits: [@maxtron95](https://github.com/maxtron95)
- Website credits: [@himanshhhhuv](https://github.com/himanshhhhuv)

For a full list of licenses and attributions, see [Third-Party Licenses](./THIRD_PARTY_LICENSES.md).

---

**Made with ❤️ as a fork of Boring Notch**

## Roadmap

### Near term: polish and reliability
- [x] **First-run permissions guide** - Explain calendar, media, accessibility, and notification permissions when each feature is enabled
- [ ] **Improved empty states** - Add clear setup guidance when no media, events, files, or AI accounts are available
- [ ] **Remember user context** - Restore the last selected tab and panel state after relaunch
- [x] **Reduced motion and accessibility options** - Respect macOS motion preferences and improve VoiceOver labels and keyboard navigation
- [ ] **Performance pass** - Reduce unnecessary updates while the notch is closed and improve energy usage over long sessions
- [ ] **Error and diagnostics view** - Make integration failures actionable without requiring users to inspect logs
- [ ] **Release quality checklist** - Add regression coverage for updater, permissions, media controls, and shelf workflows

### Low effort, high impact
- [x] **Progress bar in the closed notch** - Add a thin progress bar to the music live activity showing track progress
- [ ] **Track change animations** - Crossfade album art and animate lyrics/text when switching tracks
- [x] **Better sneak peek** - Show album art, artist + title, and progress bar on track changes
- [ ] **Per-app hiding** - UI to blacklist certain apps from opening the notch or showing live activity
- [ ] **More sneak-peek sources** - Add compact previews for downloads, timers, calendar events, and file transfers
- [ ] **Customizable gestures** - Let users choose actions for hover, click, swipe, and keyboard shortcuts
- [ ] **Theme presets** - Offer curated visual styles alongside the existing sizing and blur controls

### Medium effort: daily workflows
- [ ] **Clipboard history in the Shelf** - Store copied text/images and drag/paste from the shelf
- [ ] **Quick toggles panel** - Control Center lite for WiFi, Bluetooth, Do Not Disturb, AirDrop, etc.
- [x] **Calendar glance** - Show next upcoming event with "Join" button for Zoom/Meet/Teams links
- [ ] **Karaoke style lyrics** - Highlight individual words as they're sung (where timing data available)
- [x] **Timer/Pomodoro** - Compact timer that can live in the notch or open panel
- [ ] **Shelf collections** - Pin, label, reorder, and expire shelf items without losing useful files
- [ ] **Notification summaries** - Show a compact, user-controlled summary of recent notifications
- [ ] **More media integrations** - Improve parity across Apple Music, Spotify, YouTube Music, and browser playback
- [ ] **Shortcuts integration** - Expose notch actions to macOS Shortcuts and support automation triggers
- [ ] **AI provider expansion** - Add more providers and clearer account-health and reset-time details to the usage dashboard
- [x]  Weather integration
- [ ]  Lock Screen Widgets 🔒
- [ ]  Extension system 🧩
- [ ]  Notifications (under consideration) 🔔

### High effort: ambitious, but cool
- [ ] **True system audio reactive visualizer** - Tap system audio via CoreAudio/ScreenCaptureKit for real music visualization
- [ ] **Widget system** - Extensible widgets for the open notch (weather, system stats, custom widgets)
- [ ] **App Switcher** - Swipe gesture to bring up a compact app switcher in the notch
- [ ] **Focus Mode integration** - Show and change Focus Mode from the notch/quick toggles
- [ ] **Multi-display improvements** - Make notch placement and behavior predictable when displays are connected or disconnected
- [ ] **Window and stage controls** - Provide optional, privacy-conscious controls for common window-management tasks
- [ ] **Plugin-free extension points** - Support safe, local customization without requiring a paid extension ecosystem
- [ ] **Signed and notarized distribution** - Simplify installation by reducing Gatekeeper friction for stable releases

### Completed
- [x] Rebrand from Boring Notch to Notching it up with original credits preserved
- [x] New auto-updater with fresh Sparkle keys
- [x] Advanced options toggle for cleaner UI
- [x] Customizable lyrics blur transition with intensity/speed controls
- [x] HUD replacement enabled by default
- [x] Synced lyrics (line-by-line) with LRCLIB integration
- [x] Built-in music-reactive spectrum visualizer
- [x] Lyrics display in closed notch live activity
- [x] **Configurable top-bar tabs** - Choose and reorder the panels shown in the open notch
- [x] **Pomodoro timer foundation** - Configure work, short-break, and long-break durations
- [x] **Quick notes tab** - Keep a persistent scratchpad in the notch
- [x] **AI usage dashboard** - Live account sync for supported providers, manual fallback, reset countdowns, and low-usage alerts
- [x] **Weather tab** - Manual city lookup, current conditions, five-day forecast, Celsius or Fahrenheit, and Open-Meteo attribution
- [x] **Reduced motion and VoiceOver support** - Follow macOS Reduce Motion, opt into reduced motion, and use accessible labels and keyboard navigation across the notch
- [x] **Developer Motion tab** - Preview every app animation with and without reduced motion
- [x] **Calendar Join button** - Open Zoom, Google Meet, Microsoft Teams, Webex, Whereby, and Jitsi links 15 minutes before an event
- [x] Customizable Layout options 🛠️
- [x]  Bluetooth device activity and Devices tab (connected headphones/speakers with battery status when reported by macOS)
