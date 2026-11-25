import AppKit
import Observation
import SwiftUI
import WebKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    /// Created with the delegate so it is the notification center's delegate before launch completes.
    let notifier = Notifier()
    private var gate = FallbackGate()
    /// Last real "(N)" badge per service; a flashing title mustn't zero the fallback banner's count.
    private var lastBadge: [ServiceID: Int] = [:]
    private(set) var controllers: [ServiceID: ServiceWebController] = [:]
    private var window: NSWindow!
    /// Keeps App Nap from throttling the background web views. Held for the app's lifetime.
    private var activity: NSObjectProtocol?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Receive messages")

        for service in Service.all {
            let id = service.id
            let controller = ServiceWebController(service: service)
            controller.onMessage = { [weak self] message in self?.handle(message, from: id) }
            // Each new document reports its count afresh; its first real count is a new baseline.
            controller.onDocumentCommitted = { [weak self] in self?.gate.resetBaseline(id, at: Date()) }
            controller.onLoadFinished = { [weak self] in self?.updatePageVisibility() }
            controllers[id] = controller
        }

        notifier.onClick = { [weak self] service, pageID in
            guard let self else { return }
            self.show(service)
            if let pageID { self.controllers[service]?.notificationClicked(id: pageID) }
        }
        notifier.requestAuthorization()

        NSApp.mainMenu = makeMainMenu()
        window = makeWindow()
        observeSelection()
        show(model.selected)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show(model.selected)
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) { updatePageVisibility() }
    func applicationDidResignActive(_ notification: Notification) { updatePageVisibility() }
    func applicationDidHide(_ notification: Notification) { updatePageVisibility() }
    func applicationDidUnhide(_ notification: Notification) { updatePageVisibility() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        updatePageVisibility()
        return false
    }

    func windowDidMiniaturize(_ notification: Notification) { updatePageVisibility() }
    func windowDidDeminiaturize(_ notification: Notification) { updatePageVisibility() }

    // MARK: - Showing services

    /// Shows and activates the window with `id` selected.
    func show(_ id: ServiceID) {
        model.selected = id
        applySelection()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        updatePageVisibility()
    }

    private func observeSelection() {
        withObservationTracking {
            _ = model.selected
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applySelection()
                self?.observeSelection()
            }
        }
    }

    /// Unhides only the selected web view. Both stay in the view hierarchy so their pages keep running.
    private func applySelection() {
        for (id, controller) in controllers {
            controller.webView.isHidden = id != model.selected
        }
        if let selected = controllers[model.selected]?.webView, window?.isVisible == true {
            window.makeFirstResponder(selected)
        }
        updatePageVisibility()
    }

    // MARK: - Visibility

    /// True when the app is frontmost, the window is on screen and `id` is the selected service.
    private func isUserLooking(at id: ServiceID) -> Bool {
        let windowVisible = window.map { $0.isVisible && !$0.isMiniaturized } ?? false
        return NotificationRules.isUserLooking(
            at: id, appIsActive: NSApp.isActive, windowVisible: windowVisible, selected: model.selected
        )
    }

    /// Tells every page whether the user is looking at it. The bridge fakes a focused, visible
    /// page when told visible, so this must turn false whenever the user switches away.
    private func updatePageVisibility() {
        for (id, controller) in controllers {
            controller.setPageVisible(isUserLooking(at: id))
        }
    }

    // MARK: - Bridge messages, badges and notifications

    private func handle(_ message: [String: Any], from id: ServiceID) {
        switch message["type"] as? String {
        case "title":
            handleTitle(message["title"] as? String ?? "", from: id)
        case "notify":
            handlePageNotification(message, from: id)
        default:
            break
        }
    }

    private func handleTitle(_ title: String, from id: ServiceID) {
        // Documents report an empty title at start; treating it as "0 unread" would make the
        // real count look like a rise (a launch banner) and flicker the badges.
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // A badge-less title ("Messenger", "Ann messaged you") shows 0 but is not a gate count.
        let badge = UnreadCount.badge(title: title)
        model.unread[id] = badge ?? 0
        if let badge { lastBadge[id] = badge }
        let total = model.totalUnread
        NSApp.dockTile.badgeLabel = total > 0 ? "\(total)" : nil

        let now = Date()
        guard let due = gate.noteUnread(id, badge: badge, at: now) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + max(due.timeIntervalSince(now), 0)) { [weak self] in
            MainActor.assumeIsolated {
                self?.checkFallback(for: id, roseAt: now)
            }
        }
    }

    private func checkFallback(for id: ServiceID, roseAt: Date) {
        guard gate.shouldPostFallback(id, roseAt: roseAt, now: Date()) else { return }
        let count = lastBadge[id] ?? 0
        guard count > 0 else { return } // read elsewhere in the meantime
        guard !isUserLooking(at: id) else {
            NSLog("[um] %@ fallback (suppressed: user is looking)", id.rawValue)
            return
        }
        NSLog("[um] %@ fallback", id.rawValue)
        let text = NotificationRules.fallbackText(for: id, unread: count)
        notifier.post(
            identifier: NotificationRules.fallbackIdentifier(for: id),
            title: text.title, body: text.body, service: id, pageNotificationID: nil
        )
    }

    private func handlePageNotification(_ message: [String: Any], from id: ServiceID) {
        gate.notePageNotification(id, at: Date())
        guard let pageID = message["id"] as? String else { return }
        guard !isUserLooking(at: id) else {
            NSLog("[um] %@ page notification (suppressed: user is looking)", id.rawValue)
            return
        }
        NSLog("[um] %@ page notification", id.rawValue)
        notifier.post(
            identifier: NotificationRules.pageIdentifier(for: id, notificationID: pageID),
            title: message["title"] as? String ?? "",
            body: message["body"] as? String ?? "",
            service: id, pageNotificationID: pageID
        )
    }

    // MARK: - Window

    private func makeWindow() -> NSWindow {
        let split = NSSplitViewController()

        let sidebar = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: SidebarView(model: model)))
        sidebar.minimumThickness = 180
        sidebar.maximumThickness = 260
        sidebar.canCollapse = false
        split.addSplitViewItem(sidebar)

        let content = NSViewController()
        content.view = NSView(frame: NSRect(x: 0, y: 0, width: 920, height: 750))
        for service in Service.all {
            guard let webView = controllers[service.id]?.webView else { continue }
            webView.translatesAutoresizingMaskIntoConstraints = false
            content.view.addSubview(webView)
            NSLayoutConstraint.activate([
                webView.leadingAnchor.constraint(equalTo: content.view.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: content.view.trailingAnchor),
                // Safe-area pin keeps pages below the titlebar even if .fullSizeContentView is ever added back.
                webView.topAnchor.constraint(equalTo: content.view.safeAreaLayoutGuide.topAnchor),
                webView.bottomAnchor.constraint(equalTo: content.view.bottomAnchor),
            ])
        }
        let contentItem = NSSplitViewItem(viewController: content)
        contentItem.minimumThickness = 480
        split.addSplitViewItem(contentItem)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
            // No .fullSizeContentView: web content must never sit under the titlebar (clicks there drag the window).
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Unified Messenger"
        window.isReleasedWhenClosed = false
        window.contentViewController = split
        window.setContentSize(NSSize(width: 1100, height: 750))
        window.minSize = NSSize(width: 700, height: 450)
        window.center()
        window.setFrameAutosaveName("MainWindow") // restores the saved frame, if any
        window.delegate = self
        return window
    }

    // MARK: - Menu actions

    @objc private func showMessenger(_ sender: Any?) { show(.messenger) }
    @objc private func showInstagram(_ sender: Any?) { show(.instagram) }
    @objc private func reloadCurrent(_ sender: Any?) { controllers[model.selected]?.reload() }
    @objc private func hideWindow(_ sender: Any?) {
        window.orderOut(nil)
        updatePageVisibility()
    }

    // MARK: - Menus

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appName = "Unified Messenger"

        let appMenu = NSMenu(title: appName)
        appMenu.addItem(withTitle: "About \(appName)",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        addSubmenu(appMenu, to: main)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        addSubmenu(editMenu, to: main)

        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Messenger", action: #selector(showMessenger(_:)), keyEquivalent: "1").target = self
        viewMenu.addItem(withTitle: "Instagram", action: #selector(showInstagram(_:)), keyEquivalent: "2").target = self
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Reload", action: #selector(reloadCurrent(_:)), keyEquivalent: "r").target = self
        addSubmenu(viewMenu, to: main)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Hide Window", action: #selector(hideWindow(_:)), keyEquivalent: "w").target = self
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        addSubmenu(windowMenu, to: main)
        NSApp.windowsMenu = windowMenu

        return main
    }

    private func addSubmenu(_ submenu: NSMenu, to main: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        main.addItem(item)
    }
}
