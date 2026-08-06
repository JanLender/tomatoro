import SwiftUI

/// Lets the user pick a day and review every work record logged on it,
/// broken down by task with per-task and grand totals.
struct DailySummaryView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDate: Date = Date()

    private struct Entry: Identifiable {
        let id: UUID
        let taskName: String
        let startedAt: Date
        let durationSeconds: Int
        let description: String
    }

    private var entriesForDay: [Entry] {
        let calendar = Calendar.current
        return store.tasks
            .flatMap { task in
                task.records
                    .filter { calendar.isDate($0.startedAt, inSameDayAs: selectedDate) }
                    .map { Entry(id: $0.id, taskName: task.name, startedAt: $0.startedAt, durationSeconds: $0.durationSeconds, description: $0.description) }
            }
            .sorted { $0.startedAt < $1.startedAt }
    }

    private var totalsByTask: [(name: String, seconds: Int)] {
        let grouped = Dictionary(grouping: entriesForDay, by: \.taskName)
        return grouped
            .map { (name: $0.key, seconds: $0.value.reduce(0) { $0 + $1.durationSeconds }) }
            .sorted { $0.seconds > $1.seconds }
    }

    private var totalSeconds: Int {
        entriesForDay.reduce(0) { $0 + $1.durationSeconds }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Daily Summary")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            DatePicker("Day", selection: $selectedDate, displayedComponents: .date)
                .datePickerStyle(.field)
                .frame(maxWidth: 220)

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
                            HStack {
                                Text(item.name)
                                Spacer()
                                Text(item.seconds.asHoursMinutes)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
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
        .frame(width: 420, height: 520)
    }
}
