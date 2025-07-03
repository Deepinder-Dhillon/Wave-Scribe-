//
//  Wave_ScribeApp.swift
//  Wave Scribe
//
//  Created by Deepinder on 2025-07-01.
//

import SwiftUI
import SwiftData

@main
struct Wave_ScribeApp: App {
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .onAppear {
                    requestMicPermission()
                }
            
        }
        
    }
}
