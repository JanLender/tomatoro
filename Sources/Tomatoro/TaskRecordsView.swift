import SwiftUI

/// Shows every work record logged against a single task so far, grouped by
/// day (most recent first), with a per-day and grand total.
struct TaskRecordsView: View {
    @EnvironmentObject private var store: TaskStore
    let taskID: TaskItem.ID

    @Environment(\.dismiss) private var dismiss

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
                                    HStack {
                                        Text(record.startedAt, style: .time)
                                        Spacer()
                                        Text(record.durationSeconds.asClock)
                                            .monospacedDigit()
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
    }
}
