# Unified Messenger — Design

Date: 2026-11-25
Status: Draft, awaiting approval

## Intent

One native macOS app for the user's **personal** Facebook Messenger and Instagram DM conversations with friends and family. It replaces keeping two browser tabs open. The user wants native macOS notifications and full chat history, all running locally on their Mac with no server.

## Why this approach (Approaches)

| Option | What it is | Verdict |
|---|---|---|
| A. Native wrapper around Meta's web apps | A Swift app that hosts messenger.com and instagram.com/direct in WebKit views, bridging notifications and unread counts to macOS | **Chosen.** Works with personal accounts, stays within Meta's terms, handles end-to-end-encrypted chats and history because Meta's own web code runs it, needs no server or developer account |
| B. Unofficial client on reverse-engineered protocol (e.g. mautrix-meta) | A fully custom chat UI | Rejected: breaks Meta's terms, risks a ban on the user's main account, breaks often, and Messenger's default E2EE makes it much harder |
| C. Official Graph API (Messenger Platform / Instagram Messaging) | API calls with a Meta developer app | Impossible: only covers Facebook Page and Instagram Professional inboxes, not personal chats |

The user picked A.

## Goals

- One window with a sidebar to switch between **Messenger** and **Instagram**.
- Stay logged in across app restarts (persistent, separate cookie storage for each service).
- **Native macOS notifications** for new messages from either service, even while the app's window is closed or the other service is showing. Clicking a notification brings the app forward on the right service.
- **Unread badges** on each sidebar item and the total on the Dock icon.
- Full chat history: whatever the web apps show, including scrolling back and search.
- Sending text, emoji, photos and files (file picker and drag-and-drop work), opening links in the default browser.
- Keyboard shortcuts: ⌘1 Messenger, ⌘2 Instagram, ⌘R reload, ⌘W hide window (app keeps running).
- Runs entirely locally, with no backend of its own.

## Non-goals

- No custom chat UI. The app shows Meta's own web interface.
- No Graph API or Meta developer account.
- Voice/video calls aren't guaranteed. Camera and microphone permission will be granted if the page asks, but calls in WebKit are best effort.
- No Mac App Store distribution, no Windows/Linux.
- No other services (WhatsApp, Telegram, etc.) in v1. The service list is data-driven so more could be added later.

## Anti-goals (failure even if it "works")

- Anything that automates, scrapes or calls Meta's private endpoints. The app must behave like an ordinary browser tab, so the user's account isn't flagged.
- Missed notifications because a page was unloaded or suspended in the background.
- Logging the user out on every launch.
- Sending any data anywhere other than Meta's own sites.

## Constraints

- Machine: macOS 27.2, Swift 6.4 **Command Line Tools only (no Xcode)**. The project must build with `swift build` plus a script that assembles and ad-hoc signs a `.app` bundle. Notifications require a real bundle with a bundle identifier, so running the bare binary isn't enough.
- Minimum macOS: 14 (for `WKWebsiteDataStore(forIdentifier:)` persistent per-service storage).
- Meta's sites may reject unfamiliar browsers, so the web views send a current Safari user agent.
- Meta has been moving Messenger on the web from messenger.com toward facebook.com/messages. The Messenger URL is configuration; if messenger.com redirects or stops working, use `https://www.facebook.com/messages/`.

## How it works

**App shell (SwiftUI + AppKit).**
- `NavigationSplitView`: a narrow sidebar with one row per service (icon, name, unread badge) and a detail area.
- Both web views are created at launch and **kept alive**. Switching only changes which one is visible, so the hidden one keeps receiving messages.
- Closing the window hides it; the app keeps running in the Dock. Clicking the Dock icon re-opens the window. Quitting is ⌘Q.
- **Start at login** via `SMAppService.mainApp`, toggled from the app menu, **on by default**. When launched at login the app starts with its window hidden, loads both services in the background, and shows the window on Dock click.

**Service definition (data-driven).** `Service { id, name, icon, startURL, allowedHosts }`:
- Messenger: `https://www.messenger.com/`, hosts messenger.com, facebook.com, fbcdn.net, fbsbx.com.
- Instagram: `https://www.instagram.com/direct/inbox/`, hosts instagram.com, cdninstagram.com, fbcdn.net, facebook.com.

Navigations inside a service's hosts (including Meta login/checkpoint pages) stay in the web view. Anything else opens in the default browser.

**Web view per service.**
- `WKWebView` with its own persistent `WKWebsiteDataStore(forIdentifier:)` (stable UUID per service), so logins persist and the two services' cookies are separate.
- Safari user agent.
- `WKUIDelegate`: file open panel for uploads; `window.open` / new-window requests open in the default browser if outside the allowed hosts, otherwise load in place; camera/mic permission granted for the service's own origin.
- Downloads go to `~/Downloads`.

**Notification bridge.**
- A user script injected at document start replaces `window.Notification` with a shim:
  - `Notification.permission` returns `"granted"`; `requestPermission()` resolves `"granted"`.
  - `new Notification(title, {body, icon, tag})` posts `{service, title, body, tag}` to a `WKScriptMessageHandler`, keeps the instance, and wires its `onclick` so a click on the macOS banner can call it back (so the web app opens the right thread).
  - Service-worker `showNotification` is shimmed the same way where it's reachable from the page.
- Swift side: `UNUserNotificationCenter` asks for permission at first launch, posts a banner with the title/body, and stores service + tag in `userInfo`. On click it activates the app, shows that service and calls the stored JS `onclick`.
- Notifications are suppressed when the app is frontmost **and** that service is the one showing, since the web app already shows it.

**Visibility shim.** Messenger and Instagram usually skip page notifications while they think the tab is visible and focused. The injected script reports `document.visibilityState = "hidden"`, `document.hidden = true` and `document.hasFocus() = false` (firing `visibilitychange`) for a service whenever it isn't the one you're looking at in the frontmost window, and the real values when it is. A normal browser tab reports the same thing when it's in the background.

**Fallback: unread-count banners (decided by the user).** If a service's unread count goes up and no page notification arrived from that service within ~3 seconds, post a generic banner: "New message on Instagram" with "N unread" as the body. This catches anything the page doesn't announce, e.g. notifications Meta sends only through Web Push from a service worker, which this app can't receive. The app **does not** read sender names or message text from the page DOM.

**Feasibility spike first.** Before building the full app, a throwaway spike checks for each service whether `new Notification` fires inside the web view (with the visibility shim) when a message arrives in a hidden view. The result decides only whether the generic fallback is the main path or a safety net; the design covers both.

**Unread counts.**
- A script message reports `document.title` on change (MutationObserver on `<title>`). Parse a leading `(N)` as the unread count; no number means 0.
- Sidebar badge per service; Dock badge = sum (hidden at 0).
- If the title doesn't carry a count for a service, fall back to "has unread" based on the last notification since that service was last viewed.

**Keeping background pages awake.**
- Hidden web views stay in the window's view hierarchy (hidden, not removed), so WebKit doesn't suspend them.
- App Nap disabled for the process via `ProcessInfo.beginActivity(options: .userInitiated...)` while running, so timers and sockets aren't throttled when the window is hidden.

**Build and packaging.**
- Swift Package (`Package.swift`) with an executable target `UnifiedMessenger` and a library target for logic that can be tested (title → unread-count parsing, URL routing to in-app vs browser, notification suppression rule).
- `scripts/build-app.sh`: `swift build -c release`, assembles `build/Unified Messenger.app` (Info.plist with bundle id `com.local.unifiedmessenger`, camera/mic usage strings, app icon), ad-hoc `codesign`, optional copy to `/Applications`.
- Unit tests via `swift test` for the logic targets. Web/notification behavior is verified by hand with a checklist.

## Decided by the user

- Personal chats with friends and family (not business Pages).
- Approach A: native wrapper around Meta's web apps.
- Local only, no server.
- When the sites' own notifications don't come through, a generic "New message on <service>" banner is enough; no reading sender or message text from the page.

## Claude's calls (user can override)

- SwiftUI + WKWebView, macOS 14+, built without Xcode.
- Sidebar layout, ⌘1/⌘2 switching, close-to-hide.
- Messenger URL messenger.com with facebook.com/messages as fallback.
- Notifications suppressed only for the service you're looking at.
- Visibility shim so hidden services behave like background tabs.
- Start at login, on by default, launching hidden.
- Bundle id `com.local.unifiedmessenger`; ad-hoc signed, not notarized.

## Left to the builder

- Exact sidebar styling and icons (SF Symbols or simple bundled images).
- How the JS shim is structured internally, as long as it meets the behavior above.
- App icon design.
