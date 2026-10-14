import SwiftData
import SwiftUI

@main
struct AITrainingPlannerApp: App {
    private let container: ModelContainer
    @State private var store: TrainingStore
    private let connectivity: PhoneConnectivity

    init() {
        do {
            container = try TrainingSchema.makeContainer()
        } catch {
            fatalError("无法打开数据库：\(error)")
        }
        let store = TrainingStore(context: container.mainContext)
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
