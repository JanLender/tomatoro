import SwiftUI

/// Shows every work record logged against a single task so far, grouped by
/// day (most recent first), with a per-day and grand total.
struct TaskRecordsView: View {
    @EnvironmentObject private var store: TaskStore
    let taskID: TaskItem.ID

    @State private var editingRecord: EditingRecord?
    @State private var recordIDPendingDeletion: WorkRecord.ID?

    private struct EditingRecord: Identifiable {
        let id: WorkRecord.ID
        let startedAt: Date
        let durationSeconds: Int
        let description: String
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
                                        Button("Edit record") {
                                            editingRecord = EditingRecord(
                                                id: record.id,
                                                startedAt: record.startedAt,
                                                durationSeconds: record.durationSeconds,
                                                description: record.description
                                            )
                                        }
                                        if !record.description.isEmpty {
                                            Button("Delete description", role: .destructive) {
                                                store.updateRecordDescription("", recordID: record.id, in: task)
                                            }
                                        }
                                        Divider()
                                        Button("Delete record…", role: .destructive) {
                                            recordIDPendingDeletion = record.id
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
        .frame(minWidth: 380, idealWidth: 440, minHeight: 400, idealHeight: 540)
        .navigationTitle(task?.name ?? "Task Records")
        .sheet(item: $editingRecord) { editing in
            if let task {
                EditRecordSheet(
                    taskName: task.name,
                    startedAt: editing.startedAt,
                    durationSeconds: editing.durationSeconds,
                    description: editing.description
                ) { startedAt, durationSeconds, description in
                    store.updateRecord(recordID: editing.id, in: task, startedAt: startedAt, durationSeconds: durationSeconds, description: description)
                }
            }
        }
        .alert(
            "Delete this record?",
            isPresented: Binding(
                get: { recordIDPendingDeletion != nil },
                set: { isPresented in if !isPresented { recordIDPendingDeletion = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let task, let recordIDPendingDeletion {
                    store.deleteRecord(recordID: recordIDPendingDeletion, in: task)
                }
            }
        } message: {
            Text("This permanently removes the record, including its time and description. This can't be undone.")
        }
    }
}

/// A sheet for editing a work record's start time, duration, and description.
struct EditRecordSheet: View {
    let taskName: String
    let onSave: (Date, Int, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var startedAt: Date
    @State private var hours: Int
    @State private var minutes: Int
    @State private var hoursValid = true
    @State private var minutesValid = true
    @State private var description: String

    init(taskName: String, startedAt: Date, durationSeconds: Int, description: String, onSave: @escaping (Date, Int, String) -> Void) {
        self.taskName = taskName
        self.onSave = onSave
        self._startedAt = State(initialValue: startedAt)
        self._hours = State(initialValue: durationSeconds / 3600)
        self._minutes = State(initialValue: (durationSeconds % 3600) / 60)
        self._description = State(initialValue: description)
    }

    private var durationSeconds: Int { hours * 3600 + minutes * 60 }
    private var inputsValid: Bool { hoursValid && minutesValid }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit record")
                .font(.headline)
            Text(taskName)
                .foregroundStyle(.secondary)

            HStack {
                DatePicker("Started", selection: $startedAt)
                RoundToFiveButtons(
                    onRoundDown: { startedAt = TimeRounding.roundedDown(startedAt) },
                    onRoundUp: { startedAt = TimeRounding.roundedUp(startedAt) }
                )
            }

            HStack(spacing: 16) {
                NumberStepperField(label: "Hours", value: $hours, range: 0...99, isValid: $hoursValid)
                NumberStepperField(label: "Minutes", value: $minutes, range: 0...59, isValid: $minutesValid)
                RoundToFiveButtons(
                    onRoundDown: { roundDuration(down: true) },
                    onRoundUp: { roundDuration(down: false) }
                )
            }

            if inputsValid {
                Text("Duration: \(durationSeconds.asHoursMinutes)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Enter whole numbers (hours 0–99, minutes 0–59).")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            TextEditor(text: $description)
                .font(.body)
                .frame(height: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    onSave(startedAt, durationSeconds, description.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!inputsValid || durationSeconds == 0)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func roundDuration(down: Bool) {
        let total = hours * 60 + minutes
        let rounded = down
            ? TimeRounding.roundedDown(minutes: total)
            : TimeRounding.roundedUp(minutes: total, maxMinutes: 99 * 60 + 55)
        hours = rounded / 60
        minutes = rounded % 60
    }
}
