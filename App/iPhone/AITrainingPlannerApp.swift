import SwiftData
import SwiftUI
import TrainingCore

@main
struct AITrainingPlannerApp: App {
    private let container: ModelContainer
    @State private var store: TrainingStore
    private let connectivity: PhoneConnectivity

    init() {
        do {
            // 截图测试用内存数据库，不影响真实数据
            container = try TrainingSchema.makeContainer(inMemory: DemoData.isActive)
        } catch {
            fatalError("无法打开数据库：\(error)")
        }
        let store = TrainingStore(context: container.mainContext)
        if DemoData.isActive { store.loadDemoData() }
        let connectivity = PhoneConnectivity(store: store)
        store.onChange = { [weak connectivity] in connectivity?.push() }
        connectivity.activate()
        _store = State(initialValue: store)
        self.connectivity = connectivity
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
        .modelContainer(container)
    }
}
