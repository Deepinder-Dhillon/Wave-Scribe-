import Foundation
import SwiftUI

@MainActor
protocol RecordingUIStateManagerDelegate: AnyObject {
    func uiStateManager(_ manager: RecordingUIStateManager, didUpdateState state: RecordingUIStateManager.RecordingState)
    func uiStateManager(_ manager: RecordingUIStateManager, didUpdateAudioLevel level: CGFloat)
    func uiStateManager(_ manager: RecordingUIStateManager, didUpdateUIDisabled disabled: Bool)
    func uiStateManager(_ manager: RecordingUIStateManager, didUpdateResumePrompt show: Bool)
}

@MainActor
final class RecordingUIStateManager: ObservableObject {
    enum RecordingState {
        case recording, paused, stopped
    }
    
    weak var delegate: RecordingUIStateManagerDelegate?
    
    @Published private(set) var state: RecordingState = .stopped
    @Published var audioLevel: CGFloat = 0.0
    @Published private(set) var isUIDisabled = false
    @Published var resumePrompt: Bool = false
    @Published private(set) var currentFileURL: URL?
    
    // MARK: - State Management
    
    func updateRecordingState(_ newState: RecordingState) {
        state = newState
        delegate?.uiStateManager(self, didUpdateState: newState)
    }
    
    func updateAudioLevel(_ level: CGFloat) {
        audioLevel = level
        delegate?.uiStateManager(self, didUpdateAudioLevel: level)
    }
    
    func updateUIDisabled(_ disabled: Bool) {
        isUIDisabled = disabled
        delegate?.uiStateManager(self, didUpdateUIDisabled: disabled)
    }
    
    func updateResumePrompt(_ show: Bool) {
        resumePrompt = show
        delegate?.uiStateManager(self, didUpdateResumePrompt: show)
    }
    
    func updateCurrentFileURL(_ url: URL?) {
        currentFileURL = url
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
        audioLevel = 0.0  // Reset audio level immediately when paused
        delegate?.uiStateManager(self, didUpdateState: state)
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
    }
} 