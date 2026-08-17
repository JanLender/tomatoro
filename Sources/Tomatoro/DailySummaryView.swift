import SwiftUI

/// Lets the user pick a day and review every work record logged on it,
/// broken down by task with per-task and grand totals.
struct DailySummaryView: View {
    @EnvironmentObject private var store: TaskStore

    @State private var selectedDate: Date = Date()
    @State private var editingRecord: EditingRecord?

    /// A snapshot of the selected day's records, deliberately *not* a computed
    /// property reading live from `store`. It's captured once when the view
    /// appears or the date changes (see `refreshEntries()`), and again after
    /// an edit made right here in this view — but never merely because
    /// `store.tasks` changed elsewhere (e.g. a stopwatch/countdown finishing
    /// and logging a new record for today while this window stays open).
    @State private var entriesForDay: [Entry] = []

    private struct Entry: Identifiable {
        let id: UUID
        let taskID: TaskItem.ID
        let taskName: String
        let taskDescription: String
        let startedAt: Date
        let durationSeconds: Int
        let description: String
    }

    private struct EditingRecord: Identifiable {
        let id: WorkRecord.ID
        let taskID: TaskItem.ID
        let taskName: String
        let startedAt: Date
        let durationSeconds: Int
        let description: String
    }

    private func changeDay(by dayOffset: Int) {
        guard let newDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: selectedDate) else { return }
        selectedDate = newDate
    }

    private func refreshEntries() {
        let calendar = Calendar.current
        entriesForDay = store.tasks
            .flatMap { task in
                task.records
                    .filter { calendar.isDate($0.startedAt, inSameDayAs: selectedDate) }
                    .map { Entry(id: $0.id, taskID: task.id, taskName: task.name, taskDescription: task.description, startedAt: $0.startedAt, durationSeconds: $0.durationSeconds, description: $0.description) }
            }
            .sorted { $0.startedAt < $1.startedAt }
    }

    private var totalsByTask: [(name: String, description: String, recordDescriptions: [String], seconds: Int)] {
        let grouped = Dictionary(grouping: entriesForDay, by: \.taskName)
        return grouped
            .map {
                (
                    name: $0.key,
                    description: $0.value.first?.taskDescription ?? "",
                    recordDescriptions: uniqueDescriptions($0.value),
                    seconds: $0.value.reduce(0) { $0 + $1.durationSeconds }
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The non-empty record descriptions for a task's entries, in first-seen
    /// order, with case-insensitive duplicates ("Implementation" / "implementation")
    /// collapsed to a single line.
    private func uniqueDescriptions(_ entries: [Entry]) -> [String] {
        var seenLowercased = Set<String>()
        var result: [String] = []
        for entry in entries where !entry.description.isEmpty {
            let key = entry.description.lowercased()
            if seenLowercased.insert(key).inserted {
                result.append(entry.description)
            }
        }
        return result
    }

    private var totalSeconds: Int {
        entriesForDay.reduce(0) { $0 + $1.durationSeconds }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Button {
                    changeDay(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .help("Previous day")

                DatePicker("Day", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.field)
                    .frame(maxWidth: 220)

                Button {
                    changeDay(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
                .help("Next day")
            }

            if entriesForDay.isEmpty {
                ContentUnavailableView(
                    "No records",
                    systemImage: "calendar",
                    description: Text("No work was logged on this day.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section("By task") {
                        ForEach(totalsByTask, id: \.name) { item in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                    ForEach(item.recordDescriptions, id: \.self) { description in
                                        Text(description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(item.seconds.asHoursMinutes)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button("Copy name") {
                                    copyToClipboard(item.name)
                                }
                                if !item.description.isEmpty {
                                    Button("Copy task description") {
                                        copyToClipboard(item.description)
                                    }
                                }
                                if !item.recordDescriptions.isEmpty {
                                    Divider()
                                    Button("Copy name and descriptions") {
                                        copyToClipboard(([item.name] + item.recordDescriptions).joined(separator: "\n"))
                                    }
                                    Button("Copy descriptions") {
                                        copyToClipboard(item.recordDescriptions.joined(separator: "\n"))
                                    }
                                }
                            }
                        }
                    }

                    Section("Records") {
                        ForEach(entriesForDay) { entry in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.taskName)
                                    Text(entry.startedAt, style: .time)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if !entry.description.isEmpty {
                                        Text(entry.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(entry.durationSeconds.asClock)
                                    .monospacedDigit()
                            }
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button("Copy task name") {
                                    copyToClipboard(entry.taskName)
                                }
                                if !entry.description.isEmpty {
                                    Button("Copy description") {
                                        copyToClipboard(entry.description)
                                    }
                                }
                                Divider()
                                Button("Edit record") {
                                    editingRecord = EditingRecord(
                                        id: entry.id,
                                        taskID: entry.taskID,
                                        taskName: entry.taskName,
                                        startedAt: entry.startedAt,
                                        durationSeconds: entry.durationSeconds,
                                        description: entry.description
                                    )
                                }
                                if !entry.description.isEmpty {
                                    Button("Delete description", role: .destructive) {
                                        if let task = store.tasks.first(where: { $0.id == entry.taskID }) {
                                            store.updateRecordDescription("", recordID: entry.id, in: task)
                                            refreshEntries()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            HStack {
                Text("Total")
                    .font(.headline)
                Spacer()
                Text(totalSeconds.asHoursMinutes)
                    .font(.headline)
                    .monospacedDigit()
            }
        }
        .padding(20)
        .frame(minWidth: 380, idealWidth: 440, minHeight: 400, idealHeight: 540)
        .onAppear {
            refreshEntries()
        }
        .onChange(of: selectedDate) { _, _ in
            refreshEntries()
        }
        .sheet(item: $editingRecord) { editing in
            if let task = store.tasks.first(where: { $0.id == editing.taskID }) {
                EditRecordSheet(
                    taskName: editing.taskName,
                    startedAt: editing.startedAt,
                    durationSeconds: editing.durationSeconds,
                    description: editing.description
                ) { startedAt, durationSeconds, description in
                    store.updateRecord(recordID: editing.id, in: task, startedAt: startedAt, durationSeconds: durationSeconds, description: description)
                    refreshEntries()
                }
            }
        }
    }
}
