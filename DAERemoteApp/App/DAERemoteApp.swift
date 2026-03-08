import SwiftUI

@main
struct DAERemoteApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
        }
    }
}
