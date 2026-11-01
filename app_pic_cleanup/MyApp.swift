import SwiftUI

@main struct MyApp: App {
    @State private var model = CleanupModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
    }
}
