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
                .preferredColorScheme(.dark)
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
        #if os(iOS)
        .backgroundTask(.appRefresh(ProactiveMonitor.bgRefreshIdentifier)) {
            await MainActor.run {
                let context = sharedModelContainer.mainContext
                let monitor = ProactiveMonitor()
                monitor.run(modelContext: context)
                monitor.generateMorningBriefingIfDue(modelContext: context)
                ProactiveMonitor.scheduleNextBackgroundRefresh()
                NotificationScheduler.shared.updateBadgeCount(modelContext: context)
            }
        }
        #endif
    }

    @MainActor
    private func runProactiveMonitor() {
        let context = sharedModelContainer.mainContext
        let monitor = ProactiveMonitor()
        monitor.run(modelContext: context)
        monitor.generateMorningBriefingIfDue(modelContext: context)
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
