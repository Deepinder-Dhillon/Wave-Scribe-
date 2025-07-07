import AVFoundation
import Foundation
import CoreData

final class AudioManager: ObservableObject, AudioEngineServiceDelegate, AudioFileManagerDelegate, RecordingDataManagerDelegate, RecordingUIStateManagerDelegate {
    enum RecordingState {
        case recording, paused, stopped
    }
    
    // UI State Manager provides all UI state
    public var uiStateManager = RecordingUIStateManager()
    
    private let audioEngineService = AudioEngineService()
    private let audioFileManager = AudioFileManager()
    private var recordingDataManager: RecordingDataManager!
    private var settings = Settings()
    
    private var recordingStartTime: Date?
    private var currentRecording: Recording?
    private var currentRecordingID: UUID?
    
    
    init() {
        audioEngineService.delegate = self
        audioFileManager.delegate = self
        uiStateManager.delegate = self
    }
    
    func configure(apiKey: String) {
        self.recordingDataManager = RecordingDataManager(apiKey: apiKey)
    }
    
    func start() {
        guard uiStateManager.state == .stopped else { return }
        
        do {
            try audioEngineService.start()
            currentRecordingID = UUID()
            currentRecording = recordingDataManager.createRecording(with: currentRecordingID!)
            audioFileManager.startNewRecording(with: currentRecordingID!)
            uiStateManager.startRecording()
        } catch {
            print("engine start failed:", error)
        }
    }
    
    func pause() {
        guard uiStateManager.state == .recording else { return }
        
        audioEngineService.pause()
        uiStateManager.pauseRecording()
    }
    
    func resume() {
        guard uiStateManager.state == .paused else { return }
        
        do {
            try audioEngineService.resume()
            uiStateManager.resumeRecording()
        } catch {
            print("Resume failed:", error)
        }
    }
    
    func stop() {
        guard uiStateManager.state != .stopped else { return }
        
        audioEngineService.stop()
        saveCurrentSegment()
        
        if let recording = currentRecording {
            recordingDataManager.updateRecordingStatus(recording, status: "recorded")
        }
        
        audioFileManager.cleanup()
        uiStateManager.stopRecording()
    }
    
    func userResume() {
        guard audioEngineService.isInterrupted && uiStateManager.state == .paused else { return }
        
        audioEngineService.userResume()
        resume()
        uiStateManager.handleResumeFromInterruption()
    }
    
    func userStop() {
        uiStateManager.updateResumePrompt(false)
        stop()
    }
    

    
    func updateSettings(
        sampleRate: Double, channels: AVAudioChannelCount, bitRate: Int, formatType: AudioFormatID
    ) {
        guard uiStateManager.state == .stopped else { return }
        
        settings = Settings(
            sampleRate: sampleRate, channels: channels, bitRate: bitRate,
            formatType: formatType)
        
        audioEngineService.updateSettings(
            sampleRate: sampleRate,
            channels: channels,
            bitRate: bitRate,
            formatType: formatType
        )
        
        audioFileManager.updateSettings(
            sampleRate: sampleRate,
            channels: channels,
            bitRate: bitRate,
            formatType: formatType
        )
    }
    
    private func saveCurrentSegment() {
        guard let segmentData = audioFileManager.saveCurrentSegment(),
              let recordingID = currentRecordingID else { return }
        
        recordingDataManager.saveSegment(
            url: segmentData.url,
            duration: segmentData.duration,
            index: segmentData.index,
            for: recordingID
        )
    }
    

    
    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard uiStateManager.state == .recording else { return }
        
        audioFileManager.writeBuffer(buffer)
        
        if audioFileManager.shouldCreateNewSegment {
            saveCurrentSegment()
            audioFileManager.startNewSegment(for: currentRecordingID!)
        }
    }
    
    // MARK: - AudioEngineServiceDelegate
    
    func audioEngineService(_ service: AudioEngineService, didUpdateAudioLevel level: CGFloat) {
        Task { @MainActor in
            uiStateManager.updateAudioLevel(level)
        }
    }
    
    func audioEngineService(_ service: AudioEngineService, didEncounterError error: Error) {
        print("Audio engine error:", error)
        // Handle error appropriately - could show alert, etc.
    }
    
    func audioEngineService(_ service: AudioEngineService, didProcessBuffer buffer: AVAudioPCMBuffer) {
        processBuffer(buffer)
    }
    
    // MARK: - AudioFileManagerDelegate
    
    func audioFileManager(_ manager: AudioFileManager, didCreateSegmentFile file: AVAudioFile, at url: URL) {
        // Optional: Handle segment file creation if needed
    }
    
    func audioFileManager(_ manager: AudioFileManager, didEncounterError error: Error) {
        print("Audio file manager error:", error)
        // Handle error appropriately - could show alert, etc.
    }
    
    // MARK: - RecordingDataManagerDelegate
    
    func recordingDataManager(_ manager: RecordingDataManager, didCreateRecording recording: Recording) {
        Task { @MainActor in
            self.currentRecording = recording
        }
    }
    
    func recordingDataManager(_ manager: RecordingDataManager, didEncounterError error: Error) {
        print("Recording data manager error:", error)
        // Handle error appropriately - could show alert, etc.
    }
    
    // MARK: - RecordingUIStateManagerDelegate
    
    func uiStateManager(_ manager: RecordingUIStateManager, didUpdateState state: RecordingUIStateManager.RecordingState) {
        // Optional: Handle state changes if needed
    }
    
    func uiStateManager(_ manager: RecordingUIStateManager, didUpdateAudioLevel level: CGFloat) {
        // Optional: Handle audio level changes if needed
    }
    
    func uiStateManager(_ manager: RecordingUIStateManager, didUpdateUIDisabled disabled: Bool) {
        // Optional: Handle UI disabled changes if needed
    }
    
    func uiStateManager(_ manager: RecordingUIStateManager, didUpdateResumePrompt show: Bool) {
        // Optional: Handle resume prompt changes if needed
    }
    
}

