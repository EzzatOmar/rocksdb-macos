import SwiftUI

struct SearchView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(title: "Search and Range Scan", subtitle: "Batches default to 256 rows with bounded retention")

            Form {
                Picker("Query mode", selection: $model.scanMode) {
                    ForEach(ScanMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Key encoding", selection: $model.keyEncoding) {
                    ForEach([ValueDisplayMode.utf8, .hex, .raw]) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Exact key", text: $model.exactKey)
                TextField("Prefix", text: $model.prefix)
                TextField("Lower bound", text: $model.lowerBound)
                TextField("Upper bound", text: $model.upperBound)

                Stepper("Limit: \(model.scanLimit)", value: $model.scanLimit, in: 1...10_000, step: 255)

                Picker("Direction", selection: $model.scanDirection) {
                    ForEach(ScanDirection.allCases) { direction in
                        Text(direction.rawValue).tag(direction)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Button {
                        model.refreshCurrentScan()
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }

                    Button {
                        model.cancelActiveOperation()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                }
            }
            .formStyle(.grouped)
            .padding()
        }
    }
}

struct SnapshotsBackupsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(title: "Snapshots and Backups", subtitle: "Snapshot handles and backup operations stay outside Swift value storage")

            HSplitView {
                List {
                    Section("Snapshots") {
                        ForEach(model.snapshots) { snapshot in
                            LabeledContent(snapshot.name, value: snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
                        }

                        Button {
                            model.snapshots.append(SnapshotRecord(id: UUID(), name: "Snapshot \(model.snapshots.count + 1)", createdAt: .now, activeQueryCount: 0))
                        } label: {
                            Label("Create Snapshot", systemImage: "camera")
                        }
                    }
                }

                List {
                    Section("Backups") {
                        ForEach(model.backups) { backup in
                            VStack(alignment: .leading) {
                                Text("Backup \(backup.id)")
                                Text("\(backup.location) | \(backup.status)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Button {
                            model.startBackup()
                        } label: {
                            Label("Backup Now", systemImage: "archivebox")
                        }

                        Button(role: .destructive) {} label: {
                            Label("Restore...", systemImage: "arrow.counterclockwise")
                        }
                        .disabled(true)
                    }
                }
            }
        }
    }
}

struct OperationsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(title: "Operation Log", subtitle: "\(model.operations.count) operations")

            List(model.operations) { operation in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(operation.name)
                            .font(.headline)
                        Spacer()
                        Text(operation.startedAt.formatted(date: .omitted, time: .standard))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(operation.detail)
                        .foregroundStyle(.secondary)
                    if let progress = operation.progress {
                        ProgressView(value: progress)
                    } else {
                        ProgressView()
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(title: "Settings and Comparators", subtitle: "Comparator identity is explicit and persisted with history")

            Form {
                Picker("Comparator profile", selection: $model.comparatorProfile) {
                    ForEach(ComparatorProfile.builtIns) { profile in
                        Text(profile.name).tag(profile)
                    }
                }

                LabeledContent("Comparator identifier", value: model.comparatorProfile.comparatorIdentifier)
                LabeledContent("History entries", value: model.recentDatabases.count.formatted())

                Button(role: .destructive) {
                    model.recentDatabases.removeAll()
                } label: {
                    Label("Clear History", systemImage: "trash")
                }
            }
            .formStyle(.grouped)
            .padding()
        }
    }
}

struct OpenDatabaseSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var path = ""
    @State private var mode: OpenMode = .readOnly
    @State private var createIfMissing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Open Database")
                .font(.title3.weight(.semibold))

            HStack {
                TextField("Database path", text: $path)
                Button("Browse...") {
                    browse()
                }
            }

            Picker("Open mode", selection: $mode) {
                ForEach(OpenMode.allCases) { openMode in
                    Text(openMode.displayName).tag(openMode)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Create if missing", isOn: $createIfMissing)
                .disabled(true)

            Picker("Comparator", selection: $model.comparatorProfile) {
                ForEach(ComparatorProfile.builtIns) { profile in
                    Text(profile.name).tag(profile)
                }
            }

            List(model.recentDatabases) { recent in
                Button {
                    path = recent.path
                    mode = recent.openMode
                } label: {
                    VStack(alignment: .leading) {
                        Text(recent.displayName)
                        Text(recent.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(height: 160)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Open") {
                    model.openPlaceholder(path: path, mode: mode)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(path.isEmpty || (!FileManager.default.fileExists(atPath: path) && !createIfMissing))
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
        }
    }
}

struct EditKeyValueSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let mode: EditSheetMode
    @State private var selectedEncoding: ValueDisplayMode = .utf8
    @State private var keyText = ""
    @State private var valueText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(mode == .add ? "Add Key-Value" : "Edit Key-Value")
                .font(.title3.weight(.semibold))

            Picker("Encoding", selection: $selectedEncoding) {
                ForEach(ValueDisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            TextField("Key", text: $keyText, axis: .vertical)
                .font(.system(.body, design: .monospaced))
            TextField("Value", text: $valueText, axis: .vertical)
                .font(.system(.body, design: .monospaced))
                .lineLimit(8...16)

            HStack {
                Text("Key bytes: \(Data(keyText.utf8).count)")
                Text("Value bytes: \(Data(valueText.utf8).count)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                Spacer()
                Button("Delete", role: .destructive) {}
                    .disabled(mode == .add || !model.canWrite)
                Button("Save") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canWrite || keyText.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 620)
        .onAppear {
            if case .edit = mode, let row = model.selectedRow {
                keyText = row.keyPreview.text
                valueText = row.valuePreview.text
            }
        }
    }
}

private struct HeaderBar: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
