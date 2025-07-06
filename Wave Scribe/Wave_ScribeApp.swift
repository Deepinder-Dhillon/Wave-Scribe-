import SwiftUI
import SwiftData

@main
struct Wave_ScribeApp: App {
    @StateObject private var audioManager = AudioManager()
    @StateObject private var dataStack = CoreDataStack.shared
    
    
    var body: some Scene {
        
        WindowGroup {
            MainView()
                .environmentObject(audioManager)
                .environment(\.managedObjectContext,dataStack.viewContext)
                .onAppear {
                    requestMicPermission()
                }
            
            
        }
        
    }
}
