import SwiftUI
import SwiftData

private enum AppTab: String, CaseIterable {
    case calendar, tasks, routines, donna, settings

    var title: String {
        switch self {
        case .calendar: return "Kalender"
        case .tasks:    return "Aufgaben"
        case .routines: return "Routinen"
        case .donna:    return "DONNA"
        case .settings: return "Einstellungen"
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
    #if os(macOS)
    // SceneStorage survives the view-tree rebuild a theme change triggers (DONNAApp .id).
    @SceneStorage("donna_selected_tab") private var selectedTab: AppTab = .calendar
    #endif

    var body: some View {
        #if os(iOS)
        TabView {
            // DONNA first on the phone: the chat is the front door, the lists are the filing cabinet.
            ChatView()
                .tabItem { Label("DONNA", systemImage: "bubble.left.and.bubble.right") }
                .modifier(UnreadTabBadge())
            CalendarView()
                .tabItem { Label("Kalender", systemImage: "calendar") }
            TaskListView()
                .tabItem { Label("Aufgaben", systemImage: "checkmark.circle") }
            RoutineListView()
                .tabItem { Label("Routinen", systemImage: "arrow.clockwise") }
            SettingsView()
                .tabItem { Label("Mehr", systemImage: "slider.horizontal.3") }
        }
        .tint(DS.Colors.warmAccent)
        .overlay(alignment: .bottom) { UndoToastView().padding(.bottom, 72) }
        #else
        NavigationSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    // Wordmark — DONNA's own signature instead of a stock title.
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("Donna")
                            .font(.system(size: 26, weight: .semibold, design: .serif))
                            .foregroundStyle(DS.Colors.textPrimary)
                        Circle()
                            .fill(DS.Colors.warmAccent)
                            .frame(width: 7, height: 7)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 14)

                    ForEach(AppTab.allCases, id: \.self) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: tab.icon)
                                    .frame(width: 20)
                                Text(tab.title)
                                Spacer()
                                if tab == .donna {
                                    SidebarUnreadBadge()
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
            .background(DS.Colors.backgroundSecondary)
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            switch selectedTab {
            case .calendar: CalendarView()
            case .tasks:    TaskListView()
            case .routines: RoutineListView()
            case .donna:    ChatView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .settings: SettingsView()
            }
        }
        // A view pushed inside a detail-column NavigationStack (RoutineDetailView) is
        // retained by the split view's own column state, so swapping the detail content
        // — even with a fresh .id — leaves the pushed view on screen. Re-creating the
        // split view per tab discards that column state along with it.
        .id(selectedTab)
        .tint(DS.Colors.warmAccent)
        .overlay(alignment: .bottom) { UndoToastView().padding(.bottom, 64) }
        #endif
    }
}

// The unread count lives in these small leaf views so a ChatMessage insert only
// re-renders the badge, not the entire TabView / NavigationSplitView.
#if os(iOS)
private struct UnreadTabBadge: ViewModifier {
    @Query(filter: #Predicate<ChatMessage> { !$0.isRead })
    private var unreadMessages: [ChatMessage]

    func body(content: Content) -> some View {
        let count = unreadMessages.filter { $0.role == .assistant }.count
        content.badge(count > 0 ? count : 0)
    }
}
#else
private struct SidebarUnreadBadge: View {
    @Query(filter: #Predicate<ChatMessage> { !$0.isRead })
    private var unreadMessages: [ChatMessage]

    var body: some View {
        let count = unreadMessages.filter { $0.role == .assistant }.count
        if count > 0 {
            Text("\(count)")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DS.Colors.warmAccent, in: Capsule())
                .foregroundStyle(DS.Colors.onAccent)
        }
    }
}
#endif

#Preview {
    ContentView()
}
