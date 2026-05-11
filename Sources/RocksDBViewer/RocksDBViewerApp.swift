import SwiftUI

@main
struct RocksDBViewerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            MainWindowView(model: model)
                .frame(minWidth: 1120, minHeight: 720)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Database...") {
                    model.presentOpenDatabase()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Add Key-Value") {
                    model.presentEditSheet(mode: .add)
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!model.canWrite)
            }

            CommandGroup(after: .textEditing) {
                Button("Focus Search") {
                    model.selectedSection = .search
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Edit Selected Row") {
                    model.presentEditSheet(mode: .edit)
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(!model.canEditSelection)

                Button("Refresh Scan") {
                    model.refreshCurrentScan()
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Cancel Operation") {
                    model.cancelActiveOperation()
                }
                .keyboardShortcut(".", modifiers: .command)

                Button("Backup Now") {
                    model.selectedSection = .snapshotsBackups
                    model.startBackup()
                }
                .keyboardShortcut("b", modifiers: .command)
            }
        }
    }
}
