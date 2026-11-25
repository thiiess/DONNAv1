//
//  DONNAApp.swift
//  DONNA
//
//  Created by Thies Kleber on 19.05.26.
//

import SwiftUI
import SwiftData
#if os(iOS)
import BackgroundTasks
#endif

@main
struct DONNAApp: App {
    @AppStorage("donna_onboarding_completed") private var onboardingCompleted = false
    /// Changing the theme rebuilds the view tree so every DS colour is read fresh.
    @AppStorage(DONNATheme.storageKey) private var themeRaw = DONNATheme.default.rawValue

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            DONNATask.self,
            CalendarEvent.self,
            Routine.self,
            RoutineOccurrence.self,
            SleepWindow.self,
            Preference.self,
            LearnedProfile.self,
            ChatMessage.self,
            ContextMode.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .id(themeRaw)
                .tint(DS.Colors.warmAccent)
                .preferredColorScheme(.dark)
                #if os(macOS)
                // Bound the root view so AppKit's window-sizes-to-content behavior
                // cannot grow the window with chat content (maxHeight .infinity lets
                // the window fill fullscreen while the scroll view clips inside).
                .frame(
                    minWidth: 800, idealWidth: 1000, maxWidth: .infinity,
                    minHeight: 560, idealHeight: 720, maxHeight: .infinity
                )
                #endif
                .sheet(isPresented: Binding(
                    get: { !onboardingCompleted },
                    set: { _ in }
                )) {
                    OnboardingView()
                        .modelContainer(sharedModelContainer)
                }
                .onAppear {
                    deleteTestMessagesOnce()
                    NotificationScheduler.shared.requestPermissionIfNeeded()
                    runProactiveMonitor()
                }
        }
        .modelContainer(sharedModelContainer)
        #if os(macOS)
        .defaultSize(width: 1000, height: 720)
        .commands {
            // Keeps undo reachable after the toast has faded — until the next action.
            CommandGroup(after: .undoRedo) {
                Button(DONNAUndoManager.shared.actionLabel.map { "Rückgängig: \($0)" } ?? "Letzte DONNA-Aktion rückgängig") {
                    _ = CommandHandler(modelContext: sharedModelContainer.mainContext).execute(.undo)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!DONNAUndoManager.shared.canUndo)
            }
        }
        #endif
        #if os(iOS)
        .backgroundTask(.appRefresh(ProactiveMonitor.bgRefreshIdentifier)) {
            await MainActor.run {
                let context = sharedModelContainer.mainContext
                let monitor = ProactiveMonitor()
                monitor.run(modelContext: context)
                monitor.generateMorningBriefingIfDue(modelContext: context)
                monitor.generateWeeklySummaryIfDue(modelContext: context)
                ProactiveMonitor.scheduleNextBackgroundRefresh()
                NotificationScheduler.shared.updateBadgeCount(modelContext: context)
            }
        }
        #endif
    }

    @MainActor
    private func runProactiveMonitor() {
        let context = sharedModelContainer.mainContext
        _ = CommandHandler(modelContext: context).execute(.purgeOrphanedOccurrences)
        _ = CommandHandler(modelContext: context).execute(.extendEventSeries)
        _ = CommandHandler(modelContext: context).execute(.extendRoutineOccurrences)
        let monitor = ProactiveMonitor()
        monitor.run(modelContext: context)
        monitor.generateMorningBriefingIfDue(modelContext: context)
        monitor.generateWeeklySummaryIfDue(modelContext: context)
        NotificationScheduler.shared.updateBadgeCount(modelContext: context)
        DataLifecycleManager.shared.runIfNeeded(modelContext: context)
        #if os(iOS)
        ProactiveMonitor.scheduleNextBackgroundRefresh()
        #endif
    }

    @MainActor
    private func deleteTestMessagesOnce() {
        guard !UserDefaults.standard.bool(forKey: "didCleanTestMessages3") else { return }
        _ = CommandHandler(modelContext: sharedModelContainer.mainContext)
            .execute(.clearChatHistory)
        UserDefaults.standard.set(true, forKey: "didCleanTestMessages3")
    }
}
