import BackgroundTasks
import SwiftUI

@main
struct CadenceApp: App {
    @StateObject private var store = Store.shared
    @Environment(\.scenePhase) private var phase

    init() {
        Reminders.shared.setUp()
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.jjguve5.cadence.refresh", using: nil) { task in
            Task { @MainActor in
                await Store.shared.refreshAll()
                Reminders.shared.reschedule()
                CadenceApp.scheduleRefresh()
                task.setTaskCompleted(success: true)
            }
        }
    }

    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.jjguve5.cadence.refresh")
        request.earliestBeginDate = Date().addingTimeInterval(60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .onOpenURL { store.handle($0) }
        }
        .onChange(of: phase) { _, now in
            if now == .active {
                store.migrateAnchors()
                store.migrateEvenings()
                store.seedPlan()
                Task { await store.refreshAll() }
                Reminders.shared.reschedule()
            } else if now == .background {
                CadenceApp.scheduleRefresh()
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @State private var tab = 0
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if store.connection.configured {
                TabView(selection: $tab) {
                    TodayView().tabItem { Label("Today", systemImage: "house") }.tag(0)
                    PlanView().tabItem { Label("Plan", systemImage: "calendar") }.tag(1)
                    BodyView().tabItem { Label("Body", systemImage: "heart.text.square") }.tag(2)
                    LifeView().tabItem { Label("Life", systemImage: "square.stack.3d.up") }.tag(3)
                    YouView().tabItem { Label("You", systemImage: "person") }.tag(4)
                }
                .tint(.mint)
            } else {
                SetupView()
            }
        }
        .onReceive(timer) { store.tick = $0 }
    }
}
