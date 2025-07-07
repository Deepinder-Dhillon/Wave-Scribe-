import SwiftUI
import SwiftData

@main
struct Wave_ScribeApp: App {

    @StateObject private var audioManager = AudioManager()
    @State private var apiKey: String = ""
    
    init() {
        // No async work in init
    }
    
    var body: some Scene {
        WindowGroup {
            if !apiKey.isEmpty {
                MainView(apiKey: apiKey)
                    .environmentObject(audioManager)
                    .environment(\.managedObjectContext,
                                  CoreDataStack.shared.persistentContainer.viewContext)
            } else {
                ProgressView("Loading API Key...")
                    .onAppear {
                        requestMicPermission()
                        Task {
                            apiKey = await fetchAPIKey()
                        }
                    }
            }
        }
    }
}
