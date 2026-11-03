# Changelog

All notable changes to Notching it up are documented here.

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
