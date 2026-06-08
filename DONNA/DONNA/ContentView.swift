import SwiftUI
import SwiftData

private enum AppTab: String, CaseIterable {
    case calendar, tasks, routines, donna, settings

    var title: String {
        switch self {
        case .calendar: return "Calendar"
        case .tasks:    return "Tasks"
        case .routines: return "Routines"
        case .donna:    return "DONNA"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .calendar: return "calendar"
        case .tasks:    return "checkmark.circle"
        case .routines: return "arrow.clockwise"
        case .donna:    return "bubble.left.and.bubble.right"
        case .settings: return "gear"
        }
    }
}

struct ContentView: View {
    @Query private var allMessages: [ChatMessage]

    #if os(macOS)
    @State private var selectedTab: AppTab? = .calendar
    #endif

    private var unreadCount: Int {
        allMessages.filter { $0.role == .assistant && !$0.isRead }.count
    }

    var body: some View {
        #if os(iOS)
        TabView {
            CalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
            TaskListView()
                .tabItem { Label("Tasks", systemImage: "checkmark.circle") }
            RoutineListView()
                .tabItem { Label("Routines", systemImage: "arrow.clockwise") }
            ChatView()
                .tabItem { Label("DONNA", systemImage: "bubble.left.and.bubble.right") }
                .badge(unreadCount > 0 ? unreadCount : 0)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .tint(DS.Colors.accent)
        #else
        NavigationSplitView {
            List(AppTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.title, systemImage: tab.icon)
            }
            .navigationTitle("DONNA")
        } detail: {
            switch selectedTab ?? .calendar {
            case .calendar: CalendarView()
            case .tasks:    TaskListView()
            case .routines: RoutineListView()
            case .donna:    ChatView()
            case .settings: SettingsView()
            }
        }
        .tint(DS.Colors.accent)
        #endif
    }
}

#Preview {
    ContentView()
}
