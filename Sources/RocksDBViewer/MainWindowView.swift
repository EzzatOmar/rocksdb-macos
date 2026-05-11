import SwiftUI

struct MainWindowView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            DetailRouterView(model: model)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.presentOpenDatabase()
                } label: {
                    Label("Open Database", systemImage: "folder")
                }
                .accessibilityLabel("Open database")

                Picker("Snapshot", selection: .constant(UUID?.none)) {
                    Text("Live").tag(UUID?.none)
                    ForEach(model.snapshots) { snapshot in
                        Text(snapshot.name).tag(Optional(snapshot.id))
                    }
                }
                .frame(width: 170)
                .accessibilityLabel("Snapshot selector")

                Button {
                    model.selectedSection = .search
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .accessibilityLabel("Search")

                Button {
                    model.presentEditSheet(mode: .add)
                } label: {
                    Label("Add Key", systemImage: "plus")
                }
                .disabled(!model.canWrite)
                .accessibilityLabel("Add key-value")

                Button {
                    model.startBackup()
                } label: {
                    Label("Backup", systemImage: "archivebox")
                }
                .accessibilityLabel("Backup now")
            }
        }
        .sheet(isPresented: $model.openDatabaseSheetPresented) {
            OpenDatabaseSheet(model: model)
        }
        .sheet(item: $model.editSheetMode) { mode in
            EditKeyValueSheet(model: model, mode: mode)
        }
    }
}

private struct DetailRouterView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        switch model.selectedSection {
        case .browser:
            BrowserView(model: model)
        case .search:
            SearchView(model: model)
        case .snapshotsBackups:
            SnapshotsBackupsView(model: model)
        case .operations:
            OperationsView(model: model)
        case .settings:
            SettingsView(model: model)
        }
    }
}

private struct SidebarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        List(selection: $model.selectedSection) {
            Section("Database") {
                ForEach(NavigationSection.allCases) { section in
                    Label(section.rawValue, systemImage: icon(for: section))
                        .tag(section)
                }
            }

            Section("Recent") {
                if model.recentDatabases.isEmpty {
                    Text("No recent databases")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.recentDatabases) { recent in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recent.displayName)
                                .lineLimit(1)
                            Text(recent.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Section("Column Families") {
                ForEach(model.columnFamilies, id: \.self) { columnFamily in
                    HStack {
                        Image(systemName: columnFamily == model.selectedColumnFamily ? "checkmark.circle.fill" : "circle")
                        Text(columnFamily)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.selectedColumnFamily = columnFamily
                    }
                }
            }

            Section("Comparator") {
                Label(model.comparatorProfile.name, systemImage: "arrow.up.arrow.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
    }

    private func icon(for section: NavigationSection) -> String {
        switch section {
        case .browser: "tablecells"
        case .search: "magnifyingglass"
        case .snapshotsBackups: "externaldrive"
        case .operations: "list.bullet.rectangle"
        case .settings: "gearshape"
        }
    }
}

private struct BrowserView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(
                title: model.activeDatabasePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "No Database Open",
                subtitle: "\(model.openMode.displayName) | \(model.selectedColumnFamily) | \(model.rows.count) retained rows"
            )

            HSplitView {
                Table(model.rows, selection: $model.selectedRowID) {
                    TableColumn("Key") { row in
                        Text(row.keyPreview.text)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                    }
                    TableColumn("Value Preview") { row in
                        Text(row.valuePreview.text)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                    }
                    TableColumn("Key Size") { row in
                        Text(row.keySize.formatted())
                            .monospacedDigit()
                    }
                    .width(80)
                    TableColumn("Value Size") { row in
                        Text(row.valueSize.formatted())
                            .monospacedDigit()
                    }
                    .width(90)
                    TableColumn("Source") { row in
                        Text(row.source.rawValue)
                    }
                    .width(80)
                }
                .accessibilityLabel("Key-value table")

                InspectorView(row: model.selectedRow)
                    .frame(minWidth: 280, idealWidth: 340, maxWidth: 440)
            }
        }
    }
}

private struct InspectorView: View {
    let row: KeyValueRow?
    @State private var displayMode: ValueDisplayMode = .utf8

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Inspector")
                .font(.headline)

            if let row {
                LabeledContent("Sequence", value: row.sequenceIndex.formatted())
                LabeledContent("Key bytes", value: row.keySize.formatted())
                LabeledContent("Value bytes", value: row.valueSize.formatted())
                LabeledContent("Source", value: row.source.rawValue)

                Picker("Preview", selection: $displayMode) {
                    ForEach(ValueDisplayMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                ScrollView {
                    Text(previewText(row.valuePreview, mode: displayMode))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 180)

                if row.valuePreview.isTruncated {
                    Text("Preview limited to \(BytePreview.defaultLimit.formatted()) bytes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Load Full Value") {}
                        .disabled(true)
                    Button("Edit") {}
                        .disabled(true)
                    Button("Delete", role: .destructive) {}
                        .disabled(true)
                }
            } else {
                ContentUnavailableView("No Row Selected", systemImage: "cursorarrow.click")
            }
        }
        .padding(14)
    }

    private func previewText(_ preview: BytePreview, mode: ValueDisplayMode) -> String {
        var copy = preview
        copy.preferredDisplay = mode
        return copy.text
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
