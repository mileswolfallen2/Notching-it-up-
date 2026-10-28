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

---

## Features

- **Music Control** - Control Apple Music, Spotify, and other media apps right from the notch with album art, playback controls, and lyrics
- **Calendar & Reminders** - View upcoming events and reminders in one place
- **File Shelf** - Drag and drop files for quick AirDrop or temporary storage
- **HUD Replacement** - Replace macOS volume, brightness, and keyboard backlight HUDs with sleek notch overlays (enabled by default)
- **Camera Mirror** - Quick mirror view right from the notch
- **Customizable** - Tweak the notch to fit your needs with gestures, sizing, and more
- **Advanced Options** - Simplified UI for casual users, with advanced settings hidden behind an "Advanced options" toggle

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
   tag), and provide the repository's Sparkle private-key secret.
3. Confirm the draft release's DMG downloads and the generated appcast entry
   points to that exact asset before publishing.
4. Install the published DMG over an older version and choose **Check for
   Updates…** to verify the update.

---

## Usage

- Launch the app - it will appear in your menu bar (this is a menu bar app)
- Hover over the notch to expand it and access all features
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

### Low Effort (High Impact)
- [x] **Progress bar in the closed notch** - Add a thin progress bar to the music live activity showing track progress
- [ ] **Track change animations** - Crossfade album art and animate lyrics/text when switching tracks
- [ ] **Better sneak peek** - Show album art, artist + title, and progress bar on track changes
- [ ] **Per-app hiding** - UI to blacklist certain apps from opening the notch or showing live activity

### Medium Effort (Really Useful)
- [ ] **Clipboard history in the Shelf** - Store copied text/images and drag/paste from the shelf
- [ ] **Quick toggles panel** - Control Center lite for WiFi, Bluetooth, Do Not Disturb, AirDrop, etc.
- [ ] **Calendar glance** - Show next upcoming event with "Join" button for Zoom/Meet/Teams links
- [ ] **Karaoke style lyrics** - Highlight individual words as they're sung (where timing data available)
- [ ] **Timer/Pomodoro** - Compact timer that can live in the notch or open panel

### High Effort (Ambitious, But Cool)
- [ ] **True system audio reactive visualizer** - Tap system audio via CoreAudio/ScreenCaptureKit for real music visualization
- [ ] **Widget system** - Extensible widgets for the open notch (weather, system stats, custom widgets)
- [ ] **App Switcher** - Swipe gesture to bring up a compact app switcher in the notch
- [ ] **Focus Mode integration** - Show and change Focus Mode from the notch/quick toggles

### Completed
- [x] Rebrand from Boring Notch to Notching it up with original credits preserved
- [x] New auto-updater with fresh Sparkle keys
- [x] Advanced options toggle for cleaner UI
- [x] Customizable lyrics blur transition with intensity/speed controls
- [x] HUD replacement enabled by default
- [x] Synced lyrics (line-by-line) with LRCLIB integration
- [x] Built-in music-reactive spectrum visualizer
- [x] Lyrics display in closed notch live activity
