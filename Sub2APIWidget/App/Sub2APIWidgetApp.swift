import SwiftUI

@main
struct Sub2APIWidgetApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        Window("Sub2API Widget", id: "main") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 980, minHeight: 680)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        .windowStyle(.hiddenTitleBar)
    }
}
