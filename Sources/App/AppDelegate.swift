import AppKit
import Observation
import SwiftUI
import WebKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    private(set) var controllers: [ServiceID: ServiceWebController] = [:]
    private var window: NSWindow!
    /// Keeps App Nap from throttling the background web views. Held for the app's lifetime.
    private var activity: NSObjectProtocol?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Receive messages")

        for service in Service.all {
            let controller = ServiceWebController(service: service)
            controller.onMessage = { _ in } // Task 6 wires titles and notifications.
            controllers[service.id] = controller
        }

        NSApp.mainMenu = makeMainMenu()
        window = makeWindow()
        observeSelection()
        show(model.selected)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show(model.selected)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    // MARK: - Showing services

    /// Shows and activates the window with `id` selected.
    func show(_ id: ServiceID) {
        model.selected = id
        applySelection()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
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
            let isSelected = id == model.selected
            controller.webView.isHidden = !isSelected
            controller.setPageVisible(isSelected) // Task 6 refines this with window/app visibility.
        }
        if let selected = controllers[model.selected]?.webView, window?.isVisible == true {
            window.makeFirstResponder(selected)
        }
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
    @objc private func hideWindow(_ sender: Any?) { window.orderOut(nil) }

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
