# Unified Messenger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS app that hosts the Messenger and Instagram web apps in one window, with persistent logins, macOS notifications, unread badges and launch at login.

**Architecture:** AppKit app lifecycle (`main.swift` + `NSApplication`) with a single `NSWindow`. The sidebar is SwiftUI in an `NSHostingController`, and the content area holds one long-lived `WKWebView` per service. Pure logic (unread parsing, link routing, notification rules, the injected JS bridge source) lives in `Sources/Core` with no AppKit/WebKit imports, so the test runner can compile it alone. AppKit/WebKit glue lives in `Sources/App`.

**Tech Stack:** Swift 6.4, AppKit, SwiftUI, WebKit, UserNotifications, ServiceManagement, JavaScriptCore (tests only). Built with plain `swiftc` from shell scripts.

**Spec:** `docs/superpowers/specs/2026-11-25-unified-messenger-design.md`

## Global Constraints

- **Toolchain:** Command Line Tools only. **SwiftPM is broken on this machine** (manifest linking fails) and `import Testing` won't link, so there's no `Package.swift`, no `swift build` and no `swift test`. Build with `swiftc` from `scripts/build.sh` and test with `scripts/test.sh`. (This is a change from the spec, which assumed SwiftPM.)
- Target: `-target arm64-apple-macosx14.0` (minimum macOS 14).
- Bundle id: `com.local.unifiedmessenger`. App name: `Unified Messenger`. Ad-hoc signed (`codesign --force --deep -s -`), not notarized.
- `Sources/Core/*.swift` may import **Foundation only**.
- Service start URLs: Messenger `https://www.messenger.com/` (fallback `https://www.facebook.com/messages/`), Instagram `https://www.instagram.com/direct/inbox/`.
- User agent: `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15`.
- Fallback banner copy: title `New message on <Service name>`, body `<N> unread`.
- Fallback wait: 3 seconds.
- Never read sender names or message text from the page DOM. Never call Meta endpoints from Swift.
- Shortcuts: ⌘1 Messenger, ⌘2 Instagram, ⌘R reload current, ⌘W hide window, ⌘Q quit.

## Review Focus

1. **Meta login, 2FA and checkpoint flows** move across hosts (`facebook.com/checkpoint`, `accountscenter.facebook.com`, `www.instagram.com/challenge`, `auth.meta.com`). These must stay in the app or the user can't log in. Pinned in Task 2's tests.
2. **Meta's outbound link wrapper** (`l.facebook.com/l.php?u=…`, `l.messenger.com`, `l.instagram.com`). Users expect the real destination to open in their browser, not a blank in-app page. Pinned in Task 2.
3. **Unread count bursts and drops.** 1→2→3 within seconds should give one banner per service, with the newest replacing the older (stable notification identifier). A count that drops (read on the phone) only updates badges. Pinned in Task 3.
4. **Title variants** like `(99+) Messenger`, `(3) Instagram • Chats` and titles without a count. The badge must never show garbage. Pinned in Task 1.
5. **Web content process crash or sleep/wake.** The page should recover on its own rather than show a blank view that never notifies. Reload on `webViewWebContentProcessDidTerminate` (Task 5), checked by hand in Task 5's checklist.

---

## File Structure

```
.gitignore                       build/
Resources/Info.plist             bundle metadata, usage strings
scripts/build.sh                 compile Core+App → build/Unified Messenger.app, codesign; --install copies to /Applications
scripts/test.sh                  compile Core+Tests → build/run-tests, run it
Sources/Core/UnreadCount.swift   title → unread count
Sources/Core/Service.swift       ServiceID, Service, Service.all
Sources/Core/LinkRouter.swift    in-app vs external decisions
Sources/Core/NotificationRules.swift  suppression, fallback gate, copy, identifiers
Sources/Core/BridgeScript.swift  injected JS source
Sources/App/main.swift           NSApplication bootstrap
Sources/App/AppDelegate.swift    window, menus, Dock reopen, App Nap, login item
Sources/App/AppModel.swift       @Observable selection + unread state
Sources/App/SidebarView.swift    SwiftUI sidebar with badges
Sources/App/ServiceWebView.swift WKWebView factory + delegates for one service
Sources/App/Notifier.swift       UNUserNotificationCenter wrapper
Tests/TestSupport.swift          check(), test registry
Tests/*Tests.swift               one file per Core unit
Tests/main.swift                 runs all, exits non-zero on failure
```

---

### Task 1: Skeleton, test runner, unread-count parsing

**Files:**
- Create: `.gitignore`, `scripts/test.sh`, `Tests/TestSupport.swift`, `Tests/main.swift`, `Tests/UnreadCountTests.swift`, `Sources/Core/UnreadCount.swift`

**Interfaces:**
- Produces: `func check(_ condition: Bool, _ message: String, file: String = #fileID, line: Int = #line)`, `func test(_ name: String, _ body: () -> Void)` (registers and runs, counting failures), `var testFailures: Int`. Each test file exposes `func runXTests()`, called from `Tests/main.swift`.
- Produces: `enum UnreadCount { static func parse(title: String) -> Int }`

- [ ] **Step 1:** `git init`, add `.gitignore` containing `build/`.
- [ ] **Step 2:** Write `scripts/test.sh` (`set -euo pipefail`; `mkdir -p build`; `swiftc -target arm64-apple-macosx14.0 Sources/Core/*.swift Tests/*.swift -o build/run-tests && build/run-tests`), plus `TestSupport.swift` and `main.swift` (prints `N failures` and `exit(1)` if any, else `All tests passed`).
- [ ] **Step 3: Write failing tests** in `UnreadCountTests.swift`:

```swift
func runUnreadCountTests() {
    test("plain count") { check(UnreadCount.parse(title: "(3) Messenger") == 3, "3") }
    test("no count") { check(UnreadCount.parse(title: "Messenger") == 0, "0") }
    test("trailing text") { check(UnreadCount.parse(title: "(12) Instagram • Chats") == 12, "12") }
    test("99+") { check(UnreadCount.parse(title: "(99+) Messenger") == 99, "99") }
    test("leading whitespace") { check(UnreadCount.parse(title: "  (2) Messenger") == 2, "2") }
    test("non-numeric parens") { check(UnreadCount.parse(title: "(beta) Messenger") == 0, "0") }
    test("count not at start") { check(UnreadCount.parse(title: "Messenger (4)") == 0, "0") }
    test("empty") { check(UnreadCount.parse(title: "") == 0, "0") }
}
```

- [ ] **Step 4:** Run `scripts/test.sh`. Expected: compile error, because `UnreadCount` is undefined.
- [ ] **Step 5:** Implement `UnreadCount.parse`: trim leading whitespace, match `^\((\d+)\+?\)`, otherwise 0.
- [ ] **Step 6:** Run `scripts/test.sh`. Expected: `All tests passed`.
- [ ] **Step 7:** Commit `feat: test runner and unread count parsing`.

### Task 2: Services and link routing

**Files:**
- Create: `Sources/Core/Service.swift`, `Sources/Core/LinkRouter.swift`, `Tests/LinkRouterTests.swift`. Modify: `Tests/main.swift`.

**Interfaces:**
- Produces:
  - `enum ServiceID: String, CaseIterable, Sendable { case messenger, instagram }`
  - `struct Service: Identifiable, Hashable, Sendable { let id: ServiceID; let name: String; let symbolName: String; let startURL: URL; let allowedHostSuffixes: [String]; let dataStoreID: UUID }`
  - `extension Service { static let messenger: Service; static let instagram: Service; static let all: [Service]; static func with(_ id: ServiceID) -> Service }`
  - `enum LinkDecision: Equatable { case inApp; case external(URL) }`
  - `enum LinkRouter { static func decide(_ url: URL, for service: Service) -> LinkDecision }`. Called only for **main-frame** navigations and new-window requests. Subframes are always allowed by the caller.

Values:
- Messenger: name `Messenger`, symbol `message.fill`, hosts `messenger.com`, `facebook.com`, `fbcdn.net`, `fbsbx.com`, `meta.com`, dataStoreID `8E1C6A62-3B0F-4C2D-9C55-0A7E5B1D2F01`.
- Instagram: name `Instagram`, symbol `camera.fill`, hosts `instagram.com`, `cdninstagram.com`, `fbcdn.net`, `facebook.com`, `meta.com`, dataStoreID `8E1C6A62-3B0F-4C2D-9C55-0A7E5B1D2F02`.

Rules, in order:
1. `about:`, `blob:` and `data:` URLs → `.inApp`.
2. Host is `l.facebook.com`, `l.messenger.com` or `l.instagram.com` and has a `u` query item that parses as an http(s) URL → `.external(that URL)`.
3. http(s) URL whose host equals an allowed suffix or ends with `.` + suffix → `.inApp`.
4. Everything else → `.external(url)`.

- [ ] **Step 1: Write failing tests:**

```swift
func runLinkRouterTests() {
    let m = Service.messenger, i = Service.instagram
    func u(_ s: String) -> URL { URL(string: s)! }
    test("thread stays") { check(LinkRouter.decide(u("https://www.messenger.com/t/123"), for: m) == .inApp, "") }
    test("fb checkpoint stays") { check(LinkRouter.decide(u("https://www.facebook.com/checkpoint/1"), for: m) == .inApp, "") }
    test("accounts center stays") { check(LinkRouter.decide(u("https://accountscenter.facebook.com/x"), for: i) == .inApp, "") }
    test("auth.meta stays") { check(LinkRouter.decide(u("https://auth.meta.com/login"), for: m) == .inApp, "") }
    test("ig challenge stays") { check(LinkRouter.decide(u("https://www.instagram.com/challenge/"), for: i) == .inApp, "") }
    test("lookalike host external") { check(LinkRouter.decide(u("https://evilfacebook.com/"), for: m) == .external(u("https://evilfacebook.com/")), "") }
    test("instagram not in messenger") { check(LinkRouter.decide(u("https://www.instagram.com/"), for: m) == .external(u("https://www.instagram.com/")), "") }
    test("link shim unwrapped") {
        check(LinkRouter.decide(u("https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.com%2Fa&h=x"), for: m) == .external(u("https://example.com/a")), "")
    }
    test("ig link shim") { check(LinkRouter.decide(u("https://l.instagram.com/?u=https%3A%2F%2Fexample.com"), for: i) == .external(u("https://example.com")), "") }
    test("mailto external") { check(LinkRouter.decide(u("mailto:a@b.c"), for: m) == .external(u("mailto:a@b.c")), "") }
    test("blob in app") { check(LinkRouter.decide(u("blob:https://www.messenger.com/abc"), for: m) == .inApp, "") }
}
```

- [ ] **Step 2:** Run `scripts/test.sh`. Expected: compile failure.
- [ ] **Step 3:** Implement `Service.swift` and `LinkRouter.swift` per the values and rules above.
- [ ] **Step 4:** Run `scripts/test.sh`. Expected: `All tests passed`.
- [ ] **Step 5:** Commit `feat: service definitions and link routing`.

### Task 3: Notification rules

**Files:**
- Create: `Sources/Core/NotificationRules.swift`, `Tests/NotificationRulesTests.swift`. Modify: `Tests/main.swift`.

**Interfaces:**
- Consumes: `ServiceID`, `Service.with(_:)`.
- Produces:
  - `enum NotificationRules`
    - `static func isUserLooking(at s: ServiceID, appIsActive: Bool, windowVisible: Bool, selected: ServiceID) -> Bool`: true only when all three hold. Used both to suppress banners and to drive the page visibility shim.
    - `static let fallbackDelay: TimeInterval = 3`
    - `static func fallbackText(for s: ServiceID, unread: Int) -> (title: String, body: String)`
    - `static func fallbackIdentifier(for s: ServiceID) -> String`, returns `"fallback-\(s.rawValue)"` (stable, so a newer banner replaces an older one)
    - `static func pageIdentifier(for s: ServiceID, notificationID: String) -> String`, returns `"page-\(s.rawValue)-\(notificationID)"`
  - `struct FallbackGate`
    - `mutating func notePageNotification(_ s: ServiceID, at: Date)`
    - `mutating func noteUnread(_ s: ServiceID, count: Int, at: Date) -> Date?`: returns the time to re-check (`at + fallbackDelay`) only when the count **rose** compared with the last count it saw for `s`. The first count it sees for a service (page load) is treated as a baseline, never a rise.
    - `func shouldPostFallback(_ s: ServiceID, roseAt: Date, now: Date) -> Bool`: false if a page notification for `s` was noted in `[roseAt - fallbackDelay, now]`.

- [ ] **Step 1: Write failing tests:**

```swift
func runNotificationRulesTests() {
    let t0 = Date(timeIntervalSince1970: 1000)
    test("looking requires all three") {
        check(NotificationRules.isUserLooking(at: .messenger, appIsActive: true, windowVisible: true, selected: .messenger), "all")
        check(!NotificationRules.isUserLooking(at: .messenger, appIsActive: true, windowVisible: true, selected: .instagram), "other selected")
        check(!NotificationRules.isUserLooking(at: .messenger, appIsActive: false, windowVisible: true, selected: .messenger), "inactive")
        check(!NotificationRules.isUserLooking(at: .messenger, appIsActive: true, windowVisible: false, selected: .messenger), "hidden")
    }
    test("fallback copy") {
        let t = NotificationRules.fallbackText(for: .instagram, unread: 3)
        check(t.title == "New message on Instagram" && t.body == "3 unread", "\(t)")
    }
    test("stable fallback id") { check(NotificationRules.fallbackIdentifier(for: .messenger) == "fallback-messenger", "") }
    test("first count is baseline") { var g = FallbackGate(); check(g.noteUnread(.messenger, count: 5, at: t0) == nil, "") }
    test("rise schedules check") {
        var g = FallbackGate(); _ = g.noteUnread(.messenger, count: 1, at: t0)
        check(g.noteUnread(.messenger, count: 2, at: t0) == t0.addingTimeInterval(3), "")
    }
    test("drop does not schedule") {
        var g = FallbackGate(); _ = g.noteUnread(.messenger, count: 3, at: t0)
        check(g.noteUnread(.messenger, count: 0, at: t0) == nil, "")
    }
    test("page notification before rise suppresses") {
        var g = FallbackGate(); g.notePageNotification(.instagram, at: t0)
        check(!g.shouldPostFallback(.instagram, roseAt: t0.addingTimeInterval(1), now: t0.addingTimeInterval(4)), "")
    }
    test("page notification after rise suppresses") {
        var g = FallbackGate(); g.notePageNotification(.instagram, at: t0.addingTimeInterval(2))
        check(!g.shouldPostFallback(.instagram, roseAt: t0, now: t0.addingTimeInterval(3)), "")
    }
    test("old page notification does not suppress") {
        var g = FallbackGate(); g.notePageNotification(.instagram, at: t0)
        check(g.shouldPostFallback(.instagram, roseAt: t0.addingTimeInterval(10), now: t0.addingTimeInterval(13)), "")
    }
    test("other service does not suppress") {
        var g = FallbackGate(); g.notePageNotification(.messenger, at: t0)
        check(g.shouldPostFallback(.instagram, roseAt: t0, now: t0.addingTimeInterval(3)), "")
    }
}
```

- [ ] **Step 2:** Run `scripts/test.sh`. Expected: compile failure.
- [ ] **Step 3:** Implement `NotificationRules.swift`.
- [ ] **Step 4:** Run `scripts/test.sh`. Expected: `All tests passed`.
- [ ] **Step 5:** Commit `feat: notification suppression and fallback rules`.

### Task 4: Injected JS bridge

**Files:**
- Create: `Sources/Core/BridgeScript.swift`, `Tests/BridgeScriptTests.swift`. Modify: `Tests/main.swift`.

**Interfaces:**
- Produces: `enum BridgeScript { static let handlerName = "um"; static func source(for s: ServiceID) -> String }`
- JS contract, which Task 6 relies on:
  - Posts to `window.webkit.messageHandlers.um.postMessage(msg)`:
    - `{type: "title", title: String}` at start, then on every `<title>` change (MutationObserver on `document.head` subtree + `characterData`, plus a 2 s interval fallback that only posts on change)
    - `{type: "notify", id: String, title: String, body: String, tag: String}` from `new Notification(title, opts)` and from `ServiceWorkerRegistration.prototype.showNotification`, if that exists
  - `window.Notification` replacement: `permission` getter returns `"granted"`, static `requestPermission()` returns `Promise.resolve("granted")` and also calls a callback argument if one is given. Instances keep `onclick`/`onclose`, support `addEventListener('click')` and `close()`, and are stored by `id` in a map.
  - `window.__umNotificationClicked(id)` calls the instance's `onclick` and `click` listeners with a dummy event, then `window.focus()`.
  - `window.__umSetVisible(visible: Bool)` overrides `document.visibilityState`/`document.hidden` via `Object.defineProperty(document, …, {configurable: true, get})` and `document.hasFocus`, then dispatches `visibilitychange` on `document` and `focus`/`blur` on `window`. The initial state is hidden.
  - Every DOM access is guarded (`if (document.head)`, `typeof MutationObserver !== "undefined"`), so the script runs against test stubs.
  - The whole script is wrapped in an IIFE and does nothing if `window.__umInstalled` is already set.

- [ ] **Step 1: Write failing tests** in `BridgeScriptTests.swift` (imports `JavaScriptCore`). Set up a `JSContext` with stubs: `window = globalThis`, a `document` object with `title`, `head: null`, `addEventListener`, `dispatchEvent`; `window.addEventListener`/`dispatchEvent`/`focus`; `window.webkit.messageHandlers.um.postMessage` that pushes `JSON.stringify(msg)` into a `posted` array; `setInterval` no-op. Then evaluate `BridgeScript.source(for: .messenger)` and assert:
  - `context.exception == nil` after loading
  - `Notification.permission === "granted"`
  - after `var n = new Notification("Ann", {body: "hi", tag: "t1"}); var clicked = false; n.onclick = function(){clicked = true}`, the last `posted` entry has type `notify`, title `Ann`, body `hi`, tag `t1` and a non-empty id
  - `__umNotificationClicked(<that id>)` sets `clicked === true`
  - `__umSetVisible(true)` makes `document.visibilityState === "visible"`, `document.hidden === false`, `document.hasFocus() === true`, and `__umSetVisible(false)` reverses all three
  - evaluating the source a second time adds no extra `title` post (the install guard works)
- [ ] **Step 2:** Run `scripts/test.sh`. Expected: compile failure.
- [ ] **Step 3:** Implement `BridgeScript.source(for:)` as a Swift multi-line string.
- [ ] **Step 4:** Run `scripts/test.sh`. Expected: `All tests passed`.
- [ ] **Step 5:** Commit `feat: injected notification, title and visibility bridge`.

### Task 5: App shell with persistent web views, packaged as an .app

**Files:**
- Create: `Resources/Info.plist`, `scripts/build.sh`, `Sources/App/main.swift`, `Sources/App/AppDelegate.swift`, `Sources/App/AppModel.swift`, `Sources/App/SidebarView.swift`, `Sources/App/ServiceWebView.swift`

**Interfaces:**
- Consumes: `Service`, `ServiceID`, `LinkRouter.decide`, `BridgeScript.source(for:)`, `BridgeScript.handlerName`.
- Produces:
  - `@MainActor @Observable final class AppModel { var selected: ServiceID = .messenger; var unread: [ServiceID: Int] = [:]; var totalUnread: Int { get } }`
  - `@MainActor final class ServiceWebController: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate { let service: Service; let webView: WKWebView; var onMessage: (([String: Any]) -> Void)?; init(service: Service); func reload(); func setPageVisible(_ visible: Bool); func notificationClicked(id: String) }`
  - `AppDelegate` with `func show(_ s: ServiceID)` (shows and activates the window, selects `s`)

Details the implementer can't infer:
- `Info.plist`: `CFBundleIdentifier` `com.local.unifiedmessenger`, `CFBundleName`/`CFBundleDisplayName` `Unified Messenger`, `CFBundleExecutable` `UnifiedMessenger`, `CFBundlePackageType` `APPL`, `LSMinimumSystemVersion` `14.0`, `NSPrincipalClass` `NSApplication`, `NSHighResolutionCapable` true, `NSCameraUsageDescription` and `NSMicrophoneUsageDescription` ("Used for calls in Messenger and Instagram.").
- `scripts/build.sh`: `swiftc -O -target arm64-apple-macosx14.0 Sources/Core/*.swift Sources/App/*.swift -o "build/Unified Messenger.app/Contents/MacOS/UnifiedMessenger"`, copy Info.plist, run `codesign --force --deep -s - "build/Unified Messenger.app"`. With `--install`, replace `/Applications/Unified Messenger.app`.
- Web view config: `WKWebsiteDataStore(forIdentifier: service.dataStoreID)`, `customUserAgent` = the Global Constraints UA, user script `BridgeScript.source(for:)` injected at `.atDocumentStart` for **main frame only**, script handler `BridgeScript.handlerName`, `preferences.isElementFullscreenEnabled = true`.
- Navigation policy: main-frame actions go through `LinkRouter`; `.external(url)` → `NSWorkspace.shared.open(url)` and cancel. Subframe actions are always allowed. `createWebViewWith` (target=_blank / window.open): `.inApp` loads in the same web view, `.external` opens in the browser. Return nil either way.
- `navigationAction.shouldPerformDownload` or `navigationResponse.canShowMIMEType == false` → `.download`. The download destination is `~/Downloads/<suggestedFilename>`, made unique with ` (n)`.
- `runOpenPanelWith` → `NSOpenPanel` honoring `allowsMultipleSelection`. `requestMediaCapturePermissionFor` → `.grant` if the origin host passes `LinkRouter` as `.inApp`, otherwise `.deny`.
- `webViewWebContentProcessDidTerminate` → `reload()`.
- Layout: `NSSplitViewController` with a sidebar item (`NSHostingController(rootView: SidebarView(model:))`, ~180 pt wide) and a content item whose view contains **both** web views pinned to the edges. Only the selected one has `isHidden = false`; never remove either from the view hierarchy.
- Sidebar: one row per `Service.all` (SF Symbol, name, a trailing capsule badge with `unread[id]` when > 0). Selection binds to `model.selected`.
- Window: titled "Unified Messenger", autosave name `MainWindow`, default size 1100×750. `windowShouldClose` → `orderOut` and return false. `applicationShouldHandleReopen` → show the window. `applicationShouldTerminateAfterLastWindowClosed` → false.
- Menus: App menu (About, Quit ⌘Q), Edit menu (standard undo/cut/copy/paste/select-all, so typing shortcuts work in the web view), View menu (Messenger ⌘1, Instagram ⌘2, Reload ⌘R), Window menu (Hide Window ⌘W, Minimize ⌘M).
- App Nap: hold `ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Receive messages")` for the app's lifetime. It doesn't prevent system sleep.
- Messenger fallback URL: if the Messenger main frame ends up on a host other than messenger.com/facebook.com after the first load, or the first load fails, load `https://www.facebook.com/messages/` once.

- [ ] **Step 1:** Write `Info.plist`, `build.sh` and the App sources per the details above.
- [ ] **Step 2:** Run `scripts/build.sh`. Expected: it exits 0 and `codesign -v "build/Unified Messenger.app"` prints nothing (valid).
- [ ] **Step 3:** Run `scripts/test.sh`. Expected: `All tests passed` (Core is unchanged).
- [ ] **Step 4: Manual checklist.** Run `open "build/Unified Messenger.app"` and ask the user to:
  - [ ] log into Messenger and Instagram (2FA/checkpoints stay in the app)
  - [ ] quit with ⌘Q and relaunch: both are still logged in
  - [ ] ⌘1/⌘2 switch services, ⌘R reloads, ⌘W hides, clicking the Dock icon brings the window back
  - [ ] a link in a chat opens in the default browser
  - [ ] attaching a photo opens a file picker and sends
  - [ ] scrolling back loads older history
- [ ] **Step 5:** Commit `feat: app shell with persistent Messenger and Instagram web views`.

### Task 6: Notifications, badges and visibility

**Files:**
- Create: `Sources/App/Notifier.swift`. Modify: `Sources/App/AppDelegate.swift`, `Sources/App/ServiceWebView.swift`

**Interfaces:**
- Consumes: `NotificationRules`, `FallbackGate`, `UnreadCount.parse`, `ServiceWebController.onMessage/setPageVisible/notificationClicked`, `AppModel`.
- Produces: `@MainActor final class Notifier: NSObject, UNUserNotificationCenterDelegate { var onClick: ((ServiceID, String?) -> Void)?; func requestAuthorization(); func post(identifier: String, title: String, body: String, service: ServiceID, pageNotificationID: String?) }`. `userInfo` keys are `service` and `pageID`.

Wiring in `AppDelegate`:
- `title` message → `count = UnreadCount.parse`, `model.unread[s] = count`, `NSApp.dockTile.badgeLabel = total > 0 ? "\(total)" : nil`. If `gate.noteUnread` returns a date, schedule a check at that date (`DispatchQueue.main.asyncAfter`). If `shouldPostFallback` is true and the user isn't looking at `s`, post with `fallbackIdentifier` and `fallbackText` (using the latest count).
- `notify` message → `gate.notePageNotification`. If the user isn't looking at `s`, post with `pageIdentifier(for:notificationID:)`, the page title/body and `pageNotificationID: id`.
- "Looking" is `NotificationRules.isUserLooking(at:appIsActive: NSApp.isActive, windowVisible: window.isVisible && !window.isMiniaturized, selected: model.selected)`. Recompute it and call `setPageVisible` on **every** controller whenever the selection changes, on `didBecomeActive`/`didResignActive`, on window `didMiniaturize`/`didDeminiaturize`, on hide/show, and after each page load finishes.
- Banner click (`didReceive`) → `show(service)`, then `notificationClicked(id:)` if a `pageID` is present. `willPresent` returns `[.banner, .sound]` (suppression already happened before posting).
- Each controller logs `[um] <service> page notification` / `[um] <service> fallback` with `os_log`/`NSLog`, for the feasibility check below.

- [ ] **Step 1:** Implement `Notifier.swift` and the wiring.
- [ ] **Step 2:** Run `scripts/build.sh` and `scripts/test.sh`. Expected: both succeed.
- [ ] **Step 3: Feasibility check (the spec's spike).** Launch the app, select Instagram, then have someone send a Messenger message. Repeat the other way round and with the window hidden (⌘W). Watch `log stream --predicate 'process == "UnifiedMessenger"' | grep '\[um\]'`. Record for each service whether the page-notification or fallback path fired, and note the result in the commit message. Either result is acceptable. **Not acceptable:** no banner at all, or two banners for one message.
- [ ] **Step 4: Manual checklist:**
  - [ ] a banner appears for a message to the service you're not looking at, and with the window hidden
  - [ ] no banner while you're looking at the chat's service in the frontmost window
  - [ ] clicking a banner opens the app on the right service (and the right chat, for page notifications)
  - [ ] the sidebar badges and Dock badge match the unread counts and clear after you read
  - [ ] reading on your phone lowers the badge and doesn't produce a banner
- [ ] **Step 5:** Commit `feat: native notifications, unread badges and background visibility`.

### Task 7: Launch at login

**Files:**
- Modify: `Sources/App/AppDelegate.swift`

**Interfaces:**
- Consumes: `AppDelegate.show(_:)`.
- Produces: an App-menu item "Open at Login" (checkmark reflects `SMAppService.mainApp.status == .enabled`), toggling `register()`/`unregister()`.

Details:
- First launch default on: if `UserDefaults` key `loginItemInitialized` is false, call `SMAppService.mainApp.register()` (ignore errors, log them) and set the key.
- Hidden at login: in `applicationWillFinishLaunching`, read `NSAppleEventManager.shared().currentAppleEvent`. If it is `kAEOpenApplication` with `paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem`, don't show the window (the web views still load). Otherwise show it.
- If registration needs user approval (`.requiresApproval`), the menu item shows unchecked and clicking it calls `SMAppService.openSystemSettingsLoginItems()`.

- [ ] **Step 1:** Implement.
- [ ] **Step 2:** Run `scripts/build.sh --install`, then `scripts/test.sh`. Expected: both succeed.
- [ ] **Step 3: Manual checklist** (using `/Applications/Unified Messenger.app`):
  - [ ] first launch: "Open at Login" is checked, and the app appears in System Settings → General → Login Items
  - [ ] after logging out and back in, the app is running with no window, and a message produces a banner
  - [ ] unchecking removes it from Login Items
- [ ] **Step 4:** Commit `feat: open at login, hidden`.
