import SwiftUI
import SwiftData

struct TaskListView: View {
    @Query private var allTasks: [Task]
    @Environment(\.modelContext) private var modelContext
    @State private var showingCreationSheet = false

    private let priorityOrder: [Priority] = [.high, .medium, .low, .none]

    private var openTasks: [Task] {
        allTasks.filter { $0.status == .open }
    }

    private var groupedTasks: [(Priority, [Task])] {
        priorityOrder.compactMap { priority in
            let tasks = openTasks.filter { $0.priority == priority }
            return tasks.isEmpty ? nil : (priority, tasks)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if openTasks.isEmpty {
                    ContentUnavailableView(
                        "No Open Tasks",
                        systemImage: "checkmark.circle",
                        description: Text("All tasks are completed.")
                    )
                    .background(DS.Colors.backgroundPrimary)
                } else {
                    List {
                        ForEach(groupedTasks, id: \.0) { priority, tasks in
                            Section {
                                ForEach(tasks) { task in
                                    NavigationLink(destination: TaskDetailView(task: task)) {
                                        TaskRow(task: task)
                                    }
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 4, leading: DS.Spacing.horizontal, bottom: 4, trailing: DS.Spacing.horizontal))
                                    #if os(iOS)
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button {
                                            _ = CommandHandler(modelContext: modelContext)
                                                .execute(.completeTask(id: task.id))
                                        } label: {
                                            Label("Complete", systemImage: "checkmark")
                                        }
                                        .tint(DS.Colors.success)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            _ = CommandHandler(modelContext: modelContext)
                                                .execute(.deleteTask(id: task.id))
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    #endif
                                    .contextMenu {
                                        Button {
                                            _ = CommandHandler(modelContext: modelContext)
                                                .execute(.completeTask(id: task.id))
                                        } label: {
                                            Label("Mark as Complete", systemImage: "checkmark.circle")
                                        }
                                        Divider()
                                        Button(role: .destructive) {
                                            _ = CommandHandler(modelContext: modelContext)
                                                .execute(.deleteTask(id: task.id))
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            } header: {
                                Text(sectionTitle(for: priority))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(DS.Colors.textTertiary)
                                    .textCase(nil)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(DS.Colors.backgroundPrimary)
                }
            }
            .navigationTitle("Tasks")
            .background(DS.Colors.backgroundPrimary)
            #if os(iOS)
            .toolbarBackground(DS.Colors.backgroundPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingCreationSheet = true } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(DS.Colors.accent)
                    }
                }
            }
            .sheet(isPresented: $showingCreationSheet) {
                TaskCreationSheet()
            }
        }
    }

    private func sectionTitle(for priority: Priority) -> String {
        switch priority {
        case .high:   return "High Priority"
        case .medium: return "Medium Priority"
        case .low:    return "Low Priority"
        case .none:   return "No Priority"
        }
    }
}

// MARK: - Row (pure display, no gestures)

private struct TaskRow: View {
    let task: Task

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(DS.Colors.priority(task.priority))
                .frame(width: 3)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.textPrimary)

                    if let due = task.dueDate {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.caption2)
                            Text(due, style: .date)
                                .font(.caption.monospacedDigit())
                        }
                        .foregroundStyle(isOverdue(due) ? DS.Colors.destructive : DS.Colors.textSecondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, DS.Spacing.horizontal)
            .padding(.vertical, DS.Spacing.vertical)
        }
        .background(DS.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card))
    }

    private func isOverdue(_ date: Date) -> Bool {
        date < .now && !Calendar.current.isDateInToday(date)
    }
}

#Preview {
    let schema = Schema([Task.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    return TaskListView().modelContainer(container)
}
