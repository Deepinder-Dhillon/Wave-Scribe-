import AVFoundation
import Foundation
import CoreData


final class AudioManager: ObservableObject {
    enum RecordingState {
        case recording, paused, stopped
    }
    
    @Published private(set) var state: RecordingState = .stopped
    @Published private(set) var currentFileURL: URL?
    @Published private(set) var isUIDisabled = false
    @Published var resumePrompt = false
    @Published var audioLevel: CGFloat = 0.0
    
    private var engine = AVAudioEngine()
    private var mixerNode = AVAudioMixerNode()
    private let session = AVAudioSession.sharedInstance()
    private var audioFile: AVAudioFile?
    private var tapInstalled = false
    private var wasInterrupted = false
    private var settings = Settings()
    
    private var currentSegmentIndex: Int = 0
    private var currentSegmentFrames: AVAudioFrameCount = 0
    private let segmentDuration: Double = 30
    private var segmentTargetFrames: AVAudioFrameCount {
        AVAudioFrameCount(settings.sampleRate * segmentDuration)
    }
    private var currentSegmentFile: AVAudioFile?
    private var recordingStartTime: Date?
    
    private let backgroundContext: NSManagedObjectContext
    private var currentRecording: Recording?
    private var currentRecordingID: UUID?
    private let recordingsRootURL: URL
    
    private let transcriptionManager: TranscriptionManager
    
    
    init() {
        self.backgroundContext = CoreDataStack.shared.persistentContainer.newBackgroundContext()
        self.transcriptionManager = TranscriptionManager(context: backgroundContext)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let root = docs.appendingPathComponent("Recordings")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        
        self.recordingsRootURL = root
        
        configureAudioSession()
        setupNotifications()
    }
    
    private func configureAudioSession() {
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth])
        } catch { print("audio session configuration failed:", error) }
    }
    
    private func activateSession() throws {
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }
    
    private func connectGraph() {
        let input = engine.inputNode
        let HWFormat = input.outputFormat(forBus: 0)
        
        engine.connect(input, to: mixerNode, format: HWFormat)
        if session.category != .record {
            engine.connect(
                mixerNode, to: engine.mainMixerNode,
                format:
                    AVAudioFormat(
                        commonFormat: .pcmFormatFloat32,
                        sampleRate: settings.sampleRate,
                        channels: settings.channels,
                        interleaved: false)!)
            
        }
    }
    
    private func setupEngine() {
        engine = AVAudioEngine()
        mixerNode = AVAudioMixerNode()
        mixerNode.volume = 0
        
        engine.attach(mixerNode)
        connectGraph()
        engine.prepare()
    }
    
    private func rebuildEngine() {
        setupEngine()
        addInputTap()
    }
    
    
    func start() {
        guard state == .stopped else { return }
        
        setupEngine()
        wasInterrupted = false
        resumePrompt = false
        isUIDisabled = false
        
        do { try activateSession() } catch {
            print("Session activate failed:", error)
            return
        }
        
        currentRecordingID = UUID()
        createRecordingEntity()
        startNewSegment()
        addInputTap()
        
        do {
            try engine.start()
            state = .recording
        } catch {
            print("engine start failed:", error)
        }
        
    }
    
    func pause() {
        guard state == .recording else { return }
        
        engine.pause()
        audioLevel = 0.0
        state = .paused
    }
    
    func resume() {
        guard state == .paused else { return }
        
        do {
            try activateSession()
            try engine.start()
            state = .recording
        } catch {
            print("Resume failed:", error)
        }
    }
    
    func stop() {
        guard state != .stopped else { return }
        
        engine.stop()
        if tapInstalled {
            mixerNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        saveCurrentSegment()
        
        backgroundContext.perform {
            self.currentRecording?.status = "recorded"
            try? self.backgroundContext.save()
        }
        
        try? session.setActive(false)
        audioFile = nil
        audioLevel = 0.0
        state = .stopped
        wasInterrupted = false
        resumePrompt = false
        isUIDisabled = false
    }
    
    func userResume() {
        guard wasInterrupted && state == .paused else { return }
        
        rebuildEngine()
        resume()
        isUIDisabled = false
        wasInterrupted = false
    }
    
    func userStop() {
        resumePrompt = false
        stop()
    }
    
    private func addInputTap() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        
        mixerNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }
        
        tapInstalled = true
    }
    private func setupNotifications() {
        let nc = NotificationCenter.default
        nc.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil)
        
        nc.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: session)
    }
    
    @objc func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else {
            return
        }
        
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable:
            routeChange(wasRecording: state == .recording)
            
        default: ()
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
        } catch {
            print("restart after route change failed:", error)
            resumePrompt = true
        }
    }
    
    @objc func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else {
            return
        }
        
        switch type {
            
        case .began:
            wasInterrupted = true
            if state == .recording {
                isUIDisabled = true
                pause()
            }
            
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                self.resumePrompt = true
                return
            }
            
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            
            if wasInterrupted && state == .paused {
                if options.contains(.shouldResume) {
                    userResume()
                } else {
                    self.resumePrompt = true
                }
            }
            
        default: ()
        }
    }
    
    private func updateLevel(from buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count {
            sum += data[i] * data[i]
        }
        let rms = sqrt(sum / Float(count))
        DispatchQueue.main.async {
            self.audioLevel = CGFloat(rms) * 4
        }
    }
    
    func updateSettings(
        sampleRate: Double, channels: AVAudioChannelCount, bitRate: Int, formatType: AudioFormatID
    ) {
        guard state == .stopped else { return }
        
        settings = Settings(
            sampleRate: sampleRate, channels: channels, bitRate: bitRate,
            formatType: formatType)
        
    }
    
    private func createNewSegmentFile() {
        guard let recID = currentRecordingID else { return }
        
        let name = "\(recID.uuidString)_seg_\(String(format: "%03d", currentSegmentIndex)).m4a"
        let url  = recordingsRootURL.appendingPathComponent(name)
        currentSegmentFile = try? AVAudioFile(forWriting: url, settings: settings.avSettings)
    }
    
    private func saveCurrentSegment() {
        guard let segFile = currentSegmentFile else { return }
        
        // actual duration
        let dur = Double(currentSegmentFrames) / settings.sampleRate
        let segURL = segFile.url
        
        currentSegmentFile = nil
        currentSegmentFrames = 0
        
        backgroundContext.perform {
            let seg = Segment(context: self.backgroundContext)
            seg.id = UUID()
            seg.index = Int16(self.currentSegmentIndex)
            seg.duration = dur
            seg.fileURL = segURL.path
            seg.createdAt = Date()
            seg.state = "pendingUpload"
            seg.retryCount = 0
            seg.recording = self.currentRecording
            seg.startTime = Double(self.currentSegmentIndex - 1) * self.segmentDuration
            
            if let rec = self.currentRecording {
                rec.totalSegments += 1
                rec.duration += dur
            }
            
            try? self.backgroundContext.save()
            DispatchQueue.main.async {
                Task {
                    await self.transcriptionManager.resumeQueuedWork()
                }
            }
        }
    }
    
    private func startNewSegment() {
        currentSegmentIndex += 1
        createNewSegmentFile()
    }
    
    private func createRecordingEntity() {
        backgroundContext.performAndWait {
            let rec = Recording(context: self.backgroundContext)
            rec.id = self.currentRecordingID
            rec.startTime = Date()
            rec.status = "recording"
            rec.totalSegments = 0
            rec.duration = 0
            rec.title = ""
            rec.transcript = ""
            try? self.backgroundContext.save()
            
            DispatchQueue.main.async { self.currentRecording = rec }
        }
    }
    
    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard state == .recording else { return }
        
        do {
            try currentSegmentFile?.write(from: buffer)
        }
        catch {
            print("failed to write to file", error);
            return
        }
        currentSegmentFrames += buffer.frameLength
        
        if currentSegmentFrames >= segmentTargetFrames {
            saveCurrentSegment()
            startNewSegment()
        }
        updateLevel(from: buffer)
    }
    
}

