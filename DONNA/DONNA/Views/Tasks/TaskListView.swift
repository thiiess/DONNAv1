import SwiftUI
import SwiftData

struct TaskListView: View {
    @Query private var allTasks: [DONNATask]
    @Environment(\.modelContext) private var modelContext
    @State private var showingCreationSheet = false
    @State private var selectedTask: DONNATask?

    private let priorityOrder: [Priority] = [.high, .medium, .low, .none]

    private var openTasks: [DONNATask] {
        allTasks.filter { $0.status == .open }
    }

    private var groupedTasks: [(Priority, [DONNATask])] {
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
                    .background(DS.Colors.appBackground)
                } else {
                    List {
                        ForEach(groupedTasks, id: \.0) { priority, tasks in
                            Section {
                                ForEach(tasks) { task in
                                    Button { selectedTask = task } label: {
                                        TaskRow(task: task, onComplete: {
                                            _ = CommandHandler(modelContext: modelContext)
                                                .execute(.completeTask(id: task.id))
                                        })
                                    }
                                    .buttonStyle(.plain)
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
                                    .foregroundStyle(DS.Colors.warmAccent)
                                    .textCase(nil)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(DS.Colors.appBackground)
                }
            }
            .navigationTitle("Tasks")
            .background(DS.Colors.appBackground)
            #if os(iOS)
            .toolbarBackground(DS.Colors.appBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingCreationSheet = true } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(DS.Colors.warmAccent)
                    }
                }
            }
            .sheet(isPresented: $showingCreationSheet) {
                TaskCreationSheet()
            }
            .sheet(item: $selectedTask) { task in
                TaskDetailView(task: task)
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

// MARK: - Row

private struct TaskRow: View {
    let task: DONNATask
    let onComplete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onComplete) {
                Circle()
                    .stroke(DS.Colors.priority(task.priority), lineWidth: 2)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .padding(.leading, DS.Spacing.horizontal)
            .padding(.trailing, 12)

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
            .padding(.vertical, DS.Spacing.vertical)

            Spacer()
        }
        .background(DS.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card))
    }

    private func isOverdue(_ date: Date) -> Bool {
        date < .now && !Calendar.current.isDateInToday(date)
    }
}

#Preview {
    let schema = Schema([DONNATask.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    return TaskListView().modelContainer(container)
}
