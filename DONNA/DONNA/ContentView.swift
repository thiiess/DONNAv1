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
    @State private var selectedTab: AppTab = .calendar
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
        .tint(DS.Colors.warmAccent)
        #else
        NavigationSplitView {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(AppTab.allCases, id: \.self) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: tab.icon)
                                    .frame(width: 20)
                                Text(tab.title)
                                Spacer()
                                if tab == .donna && unreadCount > 0 {
                                    Text("\(unreadCount)")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(DS.Colors.warmAccent, in: Capsule())
                                        .foregroundStyle(.white)
                                }
                            }
                            .foregroundStyle(
                                selectedTab == tab ? DS.Colors.warmAccent : DS.Colors.textSecondary
                            )
                            .font(.body.weight(selectedTab == tab ? .medium : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                selectedTab == tab
                                    ? DS.Colors.warmAccent.opacity(0.15)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .background(DS.Colors.appBackground)
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
            .navigationTitle("DONNA")
        } detail: {
            switch selectedTab {
            case .calendar: CalendarView()
            case .tasks:    TaskListView()
            case .routines: RoutineListView()
            case .donna:    ChatView()
            case .settings: SettingsView()
            }
        }
        .tint(DS.Colors.warmAccent)
        #endif
    }
}

#Preview {
    ContentView()
}
