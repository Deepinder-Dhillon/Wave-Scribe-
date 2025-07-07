import AVFoundation
import Foundation

protocol AudioEngineServiceDelegate: AnyObject {
    func audioEngineService(_ service: AudioEngineService, didUpdateAudioLevel level: CGFloat)
    func audioEngineService(_ service: AudioEngineService, didEncounterError error: Error)
    func audioEngineService(_ service: AudioEngineService, didProcessBuffer buffer: AVAudioPCMBuffer)
}

final class AudioEngineService: NSObject {
    enum RecordingState {
        case recording, paused, stopped
    }
    
    weak var delegate: AudioEngineServiceDelegate?
    
    private(set) var state: RecordingState = .stopped
    private var engine = AVAudioEngine()
    private var mixerNode = AVAudioMixerNode()
    private let session = AVAudioSession.sharedInstance()
    private var tapInstalled = false
    private var wasInterrupted = false
    
    private var settings = Settings()
    
    // Audio level monitoring
    private var audioLevel: CGFloat = 0.0
    
    override init() {
        super.init()
        configureAudioSession()
        setupNotifications()
    }
    
    // MARK: - Audio Session Management
    
    private func configureAudioSession() {
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth])
        } catch {
            Task { @MainActor in
                self.delegate?.audioEngineService(self, didEncounterError: error)
            }
        }
    }
    
    private func activateSession() throws {
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }
    
    // MARK: - Engine Setup
    
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
                    interleaved: false)!
            )
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
    
    func rebuildEngine() {
        setupEngine()
        addInputTap()
    }
    
    // MARK: - Recording Control
    
    func start() throws {
        guard state == .stopped else { return }
        
        setupEngine()
        wasInterrupted = false
        
        try activateSession()
        addInputTap()
        
        try engine.start()
        state = .recording
    }
    
    func pause() {
        guard state == .recording else { return }
        
        engine.pause()
        audioLevel = 0.0
        state = .paused
    }
    
    func resume() throws {
        guard state == .paused else { return }
        
        try activateSession()
        try engine.start()
        state = .recording
    }
    
    func stop() {
        guard state != .stopped else { return }
        
        engine.stop()
        if tapInstalled {
            mixerNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        
        try? session.setActive(false)
        audioLevel = 0.0
        state = .stopped
        wasInterrupted = false
    }
    
    // MARK: - Audio Processing
    
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
    
    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard state == .recording else { return }
        
        updateLevel(from: buffer)
        Task { @MainActor in
            self.delegate?.audioEngineService(self, didProcessBuffer: buffer)
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
        let newLevel = CGFloat(rms) * 4
        
        Task { @MainActor in
            self.audioLevel = newLevel
            self.delegate?.audioEngineService(self, didUpdateAudioLevel: newLevel)
        }
    }
    
    // MARK: - Settings
    
    func updateSettings(
        sampleRate: Double, 
        channels: AVAudioChannelCount, 
        bitRate: Int, 
        formatType: AudioFormatID
    ) {
        guard state == .stopped else { return }
        
        settings = Settings(
            sampleRate: sampleRate, 
            channels: channels, 
            bitRate: bitRate,
            formatType: formatType
        )
    }
    
    // MARK: - Interruption Handling
    
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
    
    @objc private func handleRouteChange(notification: Notification) {
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
            Task { @MainActor in
                self.delegate?.audioEngineService(self, didEncounterError: error)
            }
        }
    }
    
    @objc private func handleInterruption(notification: Notification) {
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
                pause()
            }
            
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                return
            }
            
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            
            if wasInterrupted && state == .paused {
                if options.contains(.shouldResume) {
                    try? resume()
                }
            }
            
        default: ()
        }
    }
    
    // MARK: - Public Interface
    
    func userResume() {
        guard wasInterrupted && state == .paused else { return }
        
        rebuildEngine()
        try? resume()
        wasInterrupted = false
    }
    
    var isInterrupted: Bool {
        return wasInterrupted
    }
    
    var currentAudioLevel: CGFloat {
        return audioLevel
    }
} 