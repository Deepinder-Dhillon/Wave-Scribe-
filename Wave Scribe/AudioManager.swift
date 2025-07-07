import AVFoundation
import Foundation
import CoreData

/**
 * Core audio recording and transcription manager
 * Handles audio session lifecycle, recording state, and coordinates transcription
 */
@MainActor
final class AudioManager: ObservableObject {
    enum RecordingState {
        case recording, paused, stopped
    }
    
    @Published private(set) var state: RecordingState = .stopped
    @Published private(set) var currentFileURL: URL?
    @Published private(set) var isUIDisabled = false
    @Published var resumePrompt = false
    @Published var audioLevel: CGFloat = 0.0
    
    public var uiStateManager = RecordingUIStateManager()
    public let transcriptionViewModel = TranscriptionViewModel()
    public var recordingManager: RecordingManager?
    
    private var engine = AVAudioEngine()
    private var mixerNode = AVAudioMixerNode()
    private let session = AVAudioSession.sharedInstance()
    private var audioFile: AVAudioFile?
    private var tapInstalled = false
    private var wasInterrupted = false
    public var settings = Settings()
    
    private var currentSegmentIndex: Int = 0
    private var currentSegmentFrames: AVAudioFrameCount = 0
    private var segmentTargetFrames: AVAudioFrameCount {
        AVAudioFrameCount(settings.sampleRate * settings.segmentDuration)
    }
    private var currentSegmentFile: AVAudioFile?
    private var recordingStartTime: Date?
    
    private let backgroundContext: NSManagedObjectContext
    private var currentRecording: Recording?
    private var currentRecordingID: UUID?
    private let recordingsRootURL: URL
    
    private var transcriptionCoordinator: TranscriptionCoordinator?
    
    init() {
        self.backgroundContext = CoreDataStack.shared.persistentContainer.newBackgroundContext()
        self.backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        self.backgroundContext.automaticallyMergesChangesFromParent = true
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let root = docs.appendingPathComponent("Recordings")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        
        self.recordingsRootURL = root
        
        configureAudioSession()
        setupNotifications()
    }
    
    // MARK: - Audio Session Configuration
    
    /**
     * Configures audio session for recording with proper category and options
     * Handles background recording and audio route changes
     */
    private func configureAudioSession() {
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker])
            try session.setActive(true)
            
            // Configure for background recording
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker, .mixWithOthers])
            
        } catch {}
    }
    
    // MARK: - Notification Setup
    
    /**
     * Sets up observers for audio interruptions and route changes
     * Enables automatic recovery from phone calls, Siri, etc.
     */
    private func setupNotifications() {
        let nc = NotificationCenter.default
        nc.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        
        nc.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: session
        )
    }
    
    // MARK: - Audio Interruption Handling
    
    /**
     * Handles audio interruptions (phone calls, Siri, etc.)
     * Automatically resumes recording when interruption ends
     */
    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            wasInterrupted = true
            if state == .recording {
                pause()
            }
            
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                return
            }
            
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            
            if wasInterrupted && state == .paused {
                if options.contains(.shouldResume) {
                    do {
                        try engine.start()
                        state = .recording
                    } catch {}
                }
            }
            
        @unknown default:
            break
        }
    }
    
    // MARK: - Route Change Handling
    
    /**
     * Handles audio route changes (headphones, Bluetooth, etc.)
     * Reconfigures audio session and resumes recording if needed
     */
    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable:
            routeChange(wasRecording: state == .recording)
        default:
            break
        }
    }
    
    private func routeChange(wasRecording: Bool) {
        if wasRecording {
            engine.pause()
            state = .paused
        }
        rebuildEngine()
        
        do {
            try activateSession()
            try engine.start()
            if wasRecording { state = .recording }
        } catch {}
    }
    
    // MARK: - Recording Control
    
    /**
     * Starts audio recording with automatic segmentation
     * Creates new recording session and begins first segment
     */
    func start() throws {
        guard state == .stopped else { return }
        
        setupEngine()
        wasInterrupted = false
        
        // Create recording file
        let recordingID = UUID()
        let timestamp = Int(Date().timeIntervalSince1970)
        let fileName = "\(recordingID.uuidString)_\(timestamp).wav"
        let fileURL = recordingsRootURL.appendingPathComponent(fileName)
        
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                 sampleRate: settings.sampleRate,
                                 channels: settings.channels,
                                 interleaved: false)!
        
        currentSegmentFile = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        currentFileURL = fileURL
        currentSegmentIndex = 0
        currentSegmentFrames = 0
        recordingStartTime = Date()
        
        // Setup transcription
        setupTranscription(for: recordingID)
        
        try activateSession()
        addInputTap()
        
        try engine.start()
        state = .recording
    }
    
    private func setupTranscription(for recordingID: UUID) {
        currentRecordingID = recordingID
        
        // Create recording in Core Data
        backgroundContext.perform {
            let recording = Recording(context: self.backgroundContext)
            recording.id = recordingID
            recording.startTime = Date()
            recording.status = "recording"
            recording.totalSegments = 0
            recording.duration = 0
            recording.title = ""
            recording.transcript = ""
            
            do {
                try self.backgroundContext.save()
                DispatchQueue.main.async {
                    self.currentRecording = recording
                }
            } catch {}
        }
        
        // Reset transcription view model
        transcriptionViewModel.resetStatusTracking()
        
        if transcriptionCoordinator == nil {
        }
    }
    
    func configureTranscription(apiKey: String) {
        transcriptionCoordinator = TranscriptionCoordinator(context: backgroundContext, apiKey: apiKey)
        transcriptionCoordinator?.delegate = self
    }
    
    func ensureTranscriptionCoordinator(apiKey: String) {
        if transcriptionCoordinator == nil {
            configureTranscription(apiKey: apiKey)
        }
    }
    
    /**
     * Stops recording and finalizes the recording session
     * Completes current segment and triggers transcription
     */
    func stop() {
        guard state != .stopped else { return }
        
        engine.stop()
        if tapInstalled {
            mixerNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        
        // Complete final segment if recording
        if state == .recording && currentSegmentFrames > 0 {
            completeCurrentSegment()
        }
        
        // Complete recording in Core Data
        if let recording = currentRecording {
            backgroundContext.perform {
                recording.status = "finished"
                recording.duration = Date().timeIntervalSince(recording.startTime ?? Date())
                
                do {
                    try self.backgroundContext.save()
                } catch {}
            }
        }
        
        // Update transcription view model
        transcriptionViewModel.updateRecordingState(false)
        
        try? session.setActive(false)
        audioLevel = 0.0
        state = .stopped
        wasInterrupted = false
        
        // Clean up
        currentSegmentFile = nil
        currentFileURL = nil
        currentRecording = nil
        currentRecordingID = nil
    }
    
    func userResume() {
        guard wasInterrupted && state == .paused else { return }
        
        rebuildEngine()
        do {
            try engine.start()
            state = .recording
        } catch {}
    }
    
    func userStop() {
        stop()
        currentSegmentFile = nil
        currentFileURL = nil
    }
    
    var isInterrupted: Bool {
        return wasInterrupted
    }
    
    private func addInputTap() {
        if tapInstalled {
            mixerNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        
        mixerNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }
        
        tapInstalled = true
    }
    
    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard state == .recording else { return }
        
        updateLevel(from: buffer)
        writeBuffer(buffer)
    }
    
    private func updateLevel(from buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count {
            sum += data[i] * data[i]
        }
        let rms = sqrt(sum / Float(count))
        let newLevel = CGFloat(rms) * 4
        
        DispatchQueue.main.async {
            self.audioLevel = newLevel
        }
    }
    
    private func writeBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let segmentFile = currentSegmentFile else { return }
        
        do {
            try segmentFile.write(from: buffer)
            currentSegmentFrames += buffer.frameLength
            
            // Check if segment is complete
            if currentSegmentFrames >= segmentTargetFrames {
                completeCurrentSegment()
            }
        } catch {}
    }
    
    private func completeCurrentSegment() {
        guard let segmentFile = currentSegmentFile,
              let recordingID = currentRecordingID else { return }
        
        // Create segment in Core Data
        let segmentID = UUID()
        let segmentTimestamp = Int(Date().timeIntervalSince1970) // Use current timestamp for each segment
        let segmentFileName = "\(recordingID.uuidString)_segment_\(currentSegmentIndex)_\(segmentTimestamp).wav"
        let segmentFileURL = recordingsRootURL.appendingPathComponent(segmentFileName)
        
        // Close the current segment file before moving it
        currentSegmentFile = nil
        
        // Move current segment file to final location
        do {
            try FileManager.default.moveItem(at: segmentFile.url, to: segmentFileURL)
        } catch {}
        
        // Calculate actual segment duration based on frames recorded
        let actualSegmentDuration = Double(currentSegmentFrames) / settings.sampleRate
        
        // Save segment to Core Data
        backgroundContext.perform {
            let segment = Segment(context: self.backgroundContext)
            segment.id = segmentID
            segment.index = Int16(self.currentSegmentIndex)
            segment.fileURL = segmentFileURL.path
            segment.state = "completed"
            segment.transcript = ""
            segment.createdAt = Date()
            segment.startTime = Double(self.currentSegmentIndex) * self.settings.segmentDuration
            segment.duration = actualSegmentDuration
            
            // Link to recording
            if let recording = self.currentRecording {
                segment.recording = recording
                recording.totalSegments = Int16(self.currentSegmentIndex + 1)
            }
            
            do {
                try self.backgroundContext.save()
                
                // Trigger transcription with a small delay to ensure file is ready
                DispatchQueue.main.async {
                    print("🎯 Triggering transcription for segment \(segmentID)")
                    print("🎯 Transcription coordinator: \(self.transcriptionCoordinator != nil ? "EXISTS" : "NIL")")
                    self.transcriptionViewModel.addSegment(id: segmentID, index: self.currentSegmentIndex)
                    Task {
                        // Small delay to ensure file system has processed the move operation
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                        await self.transcriptionCoordinator?.transcribeSegment(segmentID: segment.id!, fileURL: URL(string: segment.fileURL!)!)
                    }
                }
                
            } catch {}
        }
        
        // Start new segment
        currentSegmentIndex += 1
        currentSegmentFrames = 0
        
        let newSegmentTimestamp = Int(Date().timeIntervalSince1970) // Use new timestamp for new segment
        let newSegmentFileName = "\(recordingID.uuidString)_segment_\(currentSegmentIndex)_\(newSegmentTimestamp).wav"
        let newSegmentFileURL = recordingsRootURL.appendingPathComponent(newSegmentFileName)
        
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                 sampleRate: settings.sampleRate,
                                 channels: settings.channels,
                                 interleaved: false)!
        
        do {
            currentSegmentFile = try AVAudioFile(forWriting: newSegmentFileURL, settings: format.settings)
        } catch {}
    }
    
    private func activateSession() throws {
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }
    
    private func rebuildEngine() {
        setupEngine()
        addInputTap()
    }
    
    private func setupEngine() {
        engine = AVAudioEngine()
        mixerNode = AVAudioMixerNode()
        mixerNode.volume = 0
        
        engine.attach(mixerNode)
        connectGraph()
        engine.prepare()
    }
    
    private func connectGraph() {
        let input = engine.inputNode
        let HWFormat = input.outputFormat(forBus: 0)
        
        engine.connect(input, to: mixerNode, format: HWFormat)
        if session.category != .record {
            engine.connect(
                mixerNode, to: engine.mainMixerNode,
                format: AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: settings.sampleRate,
                    channels: settings.channels,
                    interleaved: false
                )!
            )
        }
    }
    
    // Pauses the audio engine and updates state
    func pause() {
        guard state == .recording else { return }
        engine.pause()
        state = .paused
    }
}

// MARK: - TranscriptionCoordinatorDelegate

/**
 * Handles transcription completion and error callbacks
 * Updates recording status and manages segment lifecycle
 */
extension AudioManager: TranscriptionCoordinatorDelegate {
    func transcriptionCoordinator(_ coordinator: TranscriptionCoordinator, didUpdateProgress progress: Double) async {}
    
    func transcriptionCoordinator(_ coordinator: TranscriptionCoordinator, didEncounterError error: Error) async {}
    
    func transcriptionCoordinator(_ coordinator: TranscriptionCoordinator, didCompleteSegment segment: Segment) async {
        // Update the transcription view model with the completed segment
        if let segmentID = segment.id {
            transcriptionViewModel.updateSegmentCompleted(id: segmentID, transcript: segment.transcript ?? "")
        }
        
        // Check if all segments for the current recording are complete
        if let recording = currentRecording {
            recordingManager?.checkAndUpdateRecordingStatus(recording)
        }
    }
}

