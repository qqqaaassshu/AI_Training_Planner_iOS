import Combine
import SwiftUI

struct RootView: View {
    @Environment(TrainingStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var store = store
        TabView {
            TodayView()
                .tabItem { Label("今日", systemImage: "checkmark.circle") }
            HistoryView()
                .tabItem { Label("记录", systemImage: "list.bullet.rectangle") }
            PlanView()
                .tabItem { Label("计划", systemImage: "doc.text") }
            AIView()
                .tabItem { Label("AI", systemImage: "sparkles") }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.refreshToday()
                Task { await store.runWeeklyReviewIfDue() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            store.refreshToday()
        }
        .alert("出错了", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
    }
}
