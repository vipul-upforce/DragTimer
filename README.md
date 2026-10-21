# DragTimer

A native macOS menu-bar timer inspired by the interaction idea behind Gestimer: drag the menu-bar icon, release, and your timer starts.

This project is an original implementation. It does not use Gestimer source code, name, logo, or proprietary assets.

## V1 features

- Drag the menu-bar timer icon to choose a duration.
- Floating duration HUD follows the pointer while dragging.
- Option while dragging = 4× longer timer.
- Shift while dragging = precision mode.
- Multiple simultaneous timers.
- Nearest timer countdown directly in the menu bar.
- macOS notifications with sound.
- Editable timer titles.
- Quick-start 5m / 15m / 30m / 1h buttons.
- Cancel and reset-to-5-minute controls.
- Optional Apple Reminders integration.
- Optional Launch at Login.
- Timers persist across relaunches.
- No Dock icon; menu-bar only.

## Build

### Easiest

1. Install Xcode from the Mac App Store.
2. Install XcodeGen:

```bash
brew install xcodegen
```

3. In this folder:

```bash
./make-project.sh
open DragTimer.xcodeproj
```

4. In Xcode, choose your Development Team under **Signing & Capabilities**, then Run.

### Build a local .app

```bash
./build-app.sh
```

The app is copied to `./dist/DragTimer.app`.

> If code signing is not configured, use Xcode Run during development. For distribution to other Macs, sign and notarize with your Apple Developer account.

## How to use

- **Drag** the menu-bar timer icon. The farther you drag, the longer the duration.
- **Release** to create the timer.
- Click the icon to view all active timers and edit names.
- Hold **Option** during a drag for long timers.
- Hold **Shift** for finer timer control.
- Right-click for quick timers and Quit.
- On macOS 27+, you can also drag from the **Drag here to set a timer** strip at the top of the popover (menu-bar drags are restricted by the system).

## Notes

- Requires macOS 13 Ventura or later.
- Apple Reminders permission is requested only when you enable Reminders sync.
- Notification permission is requested on first launch.
