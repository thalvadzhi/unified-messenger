# Unified Messenger

A native macOS app for your personal **Facebook Messenger** and **Instagram** chats in one window. It shows Meta's own web apps (messenger.com and instagram.com/direct). It also sends macOS notifications, puts unread badges in the sidebar and on the Dock icon, and can open at login.

Everything runs on your Mac. No server, no Meta developer account and no API keys are needed. You log in to Messenger and Instagram the normal way, inside the app.

## Requirements

- macOS 14 or later, on Apple silicon (the build targets `arm64`)
- Swift toolchain: either the Xcode Command Line Tools (`xcode-select --install`) or Xcode

SwiftPM and Xcode project files are not used. The app is compiled directly with `swiftc` by the scripts in `scripts/`.

## Install

```sh
git clone https://github.com/thalvadzhi/unified-messenger.git
cd unified-messenger
scripts/build.sh --install
```

This builds `build/Unified Messenger.app`, signs it for your Mac only (ad-hoc), and copies it to `/Applications`. If the app is already running, it quits it first. Run the same command again to update after pulling changes.

## Run

```sh
open "/Applications/Unified Messenger.app"
```

You can also start it from Launchpad or Spotlight like any other app.

On first launch:

1. **Allow notifications** when macOS asks. If you miss the prompt, turn notifications on in System Settings → Notifications → Unified Messenger.
2. **Log in** to Messenger and Instagram in their panes. Logins are kept separate for each service and survive restarts.
3. **Open at Login** is turned on automatically. When the app starts at login, it runs in the background with no window. Click the Dock icon to show it. To turn this off, use the app menu → Open at Login. If macOS asks you to approve it, use System Settings → General → Login Items.

To run without installing (for development), use `scripts/build.sh` and then `open "build/Unified Messenger.app"`. Turn off "Open at Login" if you do this, so the login item doesn't point at the build folder.

## Using it

| Shortcut | Action |
|---|---|
| ⌘1 / ⌘2 | Switch to Messenger / Instagram. Pressing it again on the current service returns it to the inbox |
| ⇧⌘H | Go to Inbox |
| ⌘[ | Back |
| ⌘R | Reload |
| ⌘W | Hide the window. The app keeps running and receiving messages |
| ⌘Q | Quit. Notifications stop until you open the app again |

- **Notifications:** you get a banner for new messages on the service you're not looking at, or for both when the window is hidden. Clicking a banner opens that service.
  - If a site doesn't send its own notifications, the app falls back to a generic "New message on Messenger/Instagram" banner, based on the unread count. Message text is never read from the page.
- **Links** in chats open in your default browser.
- **Downloads** go to `~/Downloads`.

## Troubleshooting

- **No banners:** check System Settings → Notifications → Unified Messenger. To see which notification path is firing, run:
  ```sh
  log stream --predicate 'process == "UnifiedMessenger"' | grep '\[um\]'
  ```
- **A pane is blank after login or a network drop:** the app retries automatically. Press ⌘R to retry right away.
- **Stuck on a Facebook or Instagram page:** press ⇧⌘H, or ⌘1 / ⌘2, to return to the inbox.
- **"App can't be opened" warning:** the app is signed only for your Mac and isn't notarized. Build it yourself with the steps above rather than copying the `.app` from another machine.

## Development

```sh
scripts/test.sh    # build and run the unit tests (Core logic + JS bridge in JavaScriptCore)
scripts/build.sh   # build the app without installing
```

- `Sources/Core/` contains logic that can be tested on its own, with no AppKit or WebKit:
  - unread-count parsing
  - link routing
  - notification rules
  - load and retry rules
  - the injected JS bridge
- `Sources/App/` contains the AppKit, SwiftUI and WebKit app.
- `Tests/` contains a small custom test runner. Neither XCTest nor Swift Testing is needed.
- The design and plan are in `docs/superpowers/`.
