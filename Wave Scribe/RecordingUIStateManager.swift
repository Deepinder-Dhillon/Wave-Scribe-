import Foundation
import SwiftUI

@MainActor
final class RecordingUIStateManager: ObservableObject {
    enum RecordingState {
        case recording, paused, stopped
    }
    
    @Published private(set) var state: RecordingState = .stopped
    @Published var audioLevel: CGFloat = 0.0
    @Published private(set) var isUIDisabled = false
    @Published var resumePrompt = false
    @Published private(set) var currentFileURL: URL?
    @Published var showError = false
    @Published var errorTitle = ""
    @Published var errorMessage = ""
    
    // MARK: - State Management
    
    func updateRecordingState(_ newState: RecordingState) {
        state = newState
    }
    
    func updateAudioLevel(_ level: CGFloat) {
        audioLevel = level
    }
    
    func updateUIDisabled(_ disabled: Bool) {
        isUIDisabled = disabled
    }
    
    func updateResumePrompt(_ show: Bool) {
        resumePrompt = show
    }
    
    func updateCurrentFileURL(_ url: URL?) {
        currentFileURL = url
    }
    
    func showError(_ title: String, message: String) {
        errorTitle = title
        errorMessage = message
        showError = true
    }
    
    func dismissError() {
        showError = false
    }
    
    // MARK: - Convenience Methods
    
    func startRecording() {
        updateRecordingState(.recording)
        updateUIDisabled(false)
        updateResumePrompt(false)
        updateAudioLevel(0.0)
    }
    
    func pauseRecording() {
        state = .paused
        audioLevel = 0.0
    }
    
    func resumeRecording() {
        updateRecordingState(.recording)
        updateUIDisabled(false)
    }
    
    func stopRecording() {
        updateRecordingState(.stopped)
        updateAudioLevel(0.0)
        updateResumePrompt(false)
        updateUIDisabled(false)
    }
    
    func handleInterruption() {
        updateUIDisabled(true)
        updateResumePrompt(true)
    }
    
    func handleResumeFromInterruption() {
        updateUIDisabled(false)
        updateResumePrompt(false)
    }
    
    // MARK: - Reset State
    
    func resetState() {
        updateRecordingState(.stopped)
        updateAudioLevel(0.0)
        updateUIDisabled(false)
        updateResumePrompt(false)
        updateCurrentFileURL(nil)
        showError = false
    }
} 