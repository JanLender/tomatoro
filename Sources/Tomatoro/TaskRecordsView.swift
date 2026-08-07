import SwiftUI

/// Shows every work record logged against a single task so far, grouped by
/// day (most recent first), with a per-day and grand total.
struct TaskRecordsView: View {
    @EnvironmentObject private var store: TaskStore
    let taskID: TaskItem.ID

    @Environment(\.dismiss) private var dismiss
    @State private var editingRecord: EditingRecord?

    private struct EditingRecord: Identifiable {
        let id: WorkRecord.ID
        let description: String
        let subtitle: String
    }

    private var task: TaskItem? {
        store.tasks.first { $0.id == taskID }
    }

    private struct DayGroup: Identifiable {
        let id: Date
        let records: [WorkRecord]
        var totalSeconds: Int { records.reduce(0) { $0 + $1.durationSeconds } }
    }

    private func groupedByDay(_ records: [WorkRecord]) -> [DayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: records) { calendar.startOfDay(for: $0.startedAt) }
        return grouped
            .map { DayGroup(id: $0.key, records: $0.value.sorted { $0.startedAt < $1.startedAt }) }
            .sorted { $0.id > $1.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Records")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            if let task {
                Text(task.name)
                    .foregroundStyle(.secondary)
                    .contextMenu {
                        Button("Copy name") {
                            copyToClipboard(task.name)
                        }
                    }

                if !task.description.isEmpty {
                    Text(task.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contextMenu {
                            Button("Copy description") {
                                copyToClipboard(task.description)
                            }
                        }
                }

                if task.records.isEmpty {
                    ContentUnavailableView(
                        "No records yet",
                        systemImage: "clock",
                        description: Text("Start a session or add one manually to see it here.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(groupedByDay(task.records)) { day in
                            Section {
                                ForEach(day.records) { record in
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(record.startedAt, style: .time)
                                            if !record.description.isEmpty {
                                                Text(record.description)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        Text(record.durationSeconds.asClock)
                                            .monospacedDigit()
                                    }
                                    .contentShape(Rectangle())
                                    .contextMenu {
                                        if !record.description.isEmpty {
                                            Button("Copy description") {
                                                copyToClipboard(record.description)
                                            }
                                            Divider()
                                        }
                                        Button(record.description.isEmpty ? "Add description" : "Edit description") {
                                            editingRecord = EditingRecord(
                                                id: record.id,
                                                description: record.description,
                                                subtitle: "\(record.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(record.durationSeconds.asHoursMinutes)"
                                            )
                                        }
                                        if !record.description.isEmpty {
                                            Button("Delete description", role: .destructive) {
                                                store.updateRecordDescription("", recordID: record.id, in: task)
                                            }
                                        }
                                    }
                                }
                            } header: {
                                HStack {
                                    Text(day.id, format: .dateTime.year().month().day())
                                    Spacer()
                                    Text(day.totalSeconds.asHoursMinutes)
                                }
                            }
                        }
                    }
                    .listStyle(.inset)

                    Divider()

                    HStack {
                        Text("Total")
                            .font(.headline)
                        Spacer()
                        Text(task.totalSeconds.asHoursMinutes)
                            .font(.headline)
                            .monospacedDigit()
                    }
                }
            } else {
                ContentUnavailableView("Task removed", systemImage: "trash")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
        .frame(width: 420, height: 520)
        .sheet(item: $editingRecord) { editing in
            if let task {
                EditRecordDescriptionSheet(subtitle: editing.subtitle, description: editing.description) { newDescription in
                    store.updateRecordDescription(newDescription, recordID: editing.id, in: task)
                }
            }
        }
    }
}

/// A small sheet for editing a single work record's free-form description.
struct EditRecordDescriptionSheet: View {
    let subtitle: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var description: String

    init(subtitle: String, description: String, onSave: @escaping (String) -> Void) {
        self.subtitle = subtitle
        self.onSave = onSave
        self._description = State(initialValue: description)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit record description")
                .font(.headline)
            Text(subtitle)
                .foregroundStyle(.secondary)

            TextEditor(text: $description)
                .font(.body)
                .frame(height: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    onSave(description.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
