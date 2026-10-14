import SwiftData
import SwiftUI

@main
struct AITrainingPlannerApp: App {
    private let container: ModelContainer
    @State private var store: TrainingStore

    init() {
        do {
            container = try TrainingSchema.makeContainer()
        } catch {
            fatalError("无法打开数据库：\(error)")
        }
        _store = State(initialValue: TrainingStore(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
        .modelContainer(container)
    }
}
