import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = AppModel()
    private var window: NSWindow?
    private var hasConfiguredApplication = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureApplication()
    }

    func configureApplication() {
        guard !hasConfiguredApplication else { return }
        hasConfiguredApplication = true

        NSApp.setActivationPolicy(.regular)
        NSWindow.allowsAutomaticWindowTabbing = false
        configureMenu()

        let rootView = MainWindowView(model: model)
            .frame(minWidth: 1120, minHeight: 720)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "RocksDB Viewer"
        window.contentView = NSHostingView(rootView: rootView)
        window.center()
        window.delegate = self
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)

        if let openPath = ProcessInfo.processInfo.environment["ROCKSDB_VIEWER_OPEN_PATH"], !openPath.isEmpty {
            let openMode: OpenMode = ProcessInfo.processInfo.environment["ROCKSDB_VIEWER_OPEN_MODE"] == "readWrite" ? .readWrite : .readOnly
            model.openPlaceholder(path: openPath, mode: openMode)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc private func openDatabase() {
        model.presentOpenDatabase()
        showWindow()
    }

    @objc private func focusSearch() {
        model.selectedSection = .search
        showWindow()
    }

    @objc private func addKeyValue() {
        model.presentEditSheet(mode: .add)
        showWindow()
    }

    @objc private func editSelectedRow() {
        guard model.canEditSelection else { return }
        model.presentEditSheet(mode: .edit)
        showWindow()
    }

    @objc private func deleteSelectedRow() {
        guard model.canEditSelection else { return }
        model.deleteConfirmationPresented = true
        showWindow()
    }

    @objc private func refreshScan() {
        model.refreshCurrentScan()
    }

    @objc private func cancelOperation() {
        model.cancelActiveOperation()
    }

    @objc private func backupNow() {
        model.selectedSection = .snapshotsBackups
        model.startBackup()
        showWindow()
    }

    private func showWindow() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit RocksDB Viewer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(menuItem("Open Database...", action: #selector(openDatabase), key: "o"))
        fileMenu.addItem(menuItem("Add Key-Value", action: #selector(addKeyValue), key: "n"))
        fileMenu.addItem(menuItem("Backup Now", action: #selector(backupNow), key: "b"))
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(menuItem("Focus Search", action: #selector(focusSearch), key: "f"))
        editMenu.addItem(menuItem("Edit Selected Row", action: #selector(editSelectedRow), key: "e"))
        editMenu.addItem(menuItem("Delete Selected Row", action: #selector(deleteSelectedRow), key: "\u{8}", modifiers: []))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(menuItem("Refresh Scan", action: #selector(refreshScan), key: "r"))
        editMenu.addItem(menuItem("Cancel Operation", action: #selector(cancelOperation), key: "."))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    private func menuItem(_ title: String, action: Selector, key: String, modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }
}
