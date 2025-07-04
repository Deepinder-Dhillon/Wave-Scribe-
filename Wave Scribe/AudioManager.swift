import Foundation
import AVFoundation

final class AudioManager: ObservableObject {
    enum RecordingState {
        case recording, paused, stopped
    }
    
    @Published private(set) var state: RecordingState = .stopped
    @Published private(set) var currentFileURL: URL?
    @Published private(set) var isUIDisabled = false
    @Published var resumePrompt = false
    @Published var audioLevel: CGFloat = 0.0
    
    private var engine  = AVAudioEngine()
    private var mixerNode = AVAudioMixerNode()
    private let session = AVAudioSession.sharedInstance()
    private var audioFile: AVAudioFile?
    private var tapInstalled = false
    private var wasInterrupted = false
    private var settings = Settings()
    
    init(){
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleInterruption),
                                               name: AVAudioSession.interruptionNotification,
                                               object: session)
    }
    
    private func connectGraph() {
        let input = engine.inputNode
        let inputFmt = input.outputFormat(forBus: 0)
        
        engine.connect(input, to: mixerNode, format: inputFmt)
        
        let mainMixer = engine.mainMixerNode
        let mixFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputFmt.sampleRate,
                                      channels: settings.channels, interleaved: false)!
        
        engine.connect(mixerNode, to: mainMixer, format: mixFormat)
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
        
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
        
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let filename = "rec_\(Int(Date().timeIntervalSince1970)).m4a"
        let url = docs.appendingPathComponent(filename)
        currentFileURL = url
        
        
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        audioFile = try? AVAudioFile(forWriting: url, settings: settings.avSettings, commonFormat: inputFormat.commonFormat,
                                     interleaved: inputFormat.isInterleaved)
        addInputTap()
        do {
            try engine.start()
            state = .recording
        } catch {
            print("start failed: \(error.localizedDescription)")
        }
        
    }
    
    func pause() {
        guard state == .recording  else { return }
        
        engine.pause()
        audioLevel = 0.0
        state = .paused
    }
    
    func resume() {
        guard state == .paused else { return }
        
        do {
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            try engine.start()
            state = .recording
        } catch {
            print("resume failed: \(error.localizedDescription)")
        }
    }
    
    func stop() {
        guard state != .stopped else { return }
        
        engine.stop()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
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
        isUIDisabled = false
        wasInterrupted = false
    }
    
    private func addInputTap() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        
        if audioFile == nil, let url = currentFileURL {
            audioFile = try? AVAudioFile(forWriting: url,
                                         settings: settings.avSettings,
                                         commonFormat: inputFormat.commonFormat,
                                         interleaved: inputFormat.isInterleaved)
        }
        
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) {
            [weak self] buffer, _ in self?.updateLevel(from: buffer)
        }
        
        tapInstalled = true
    }
    
    @objc func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
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
            
            if wasInterrupted && state == .paused  {
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
    
    func updateSettings(sampleRate: Double, channels: AVAudioChannelCount, bitRate: Int, formatType: AudioFormatID) {
        guard state == .stopped else { return }
        
        settings = Settings(sampleRate: sampleRate, channels: channels, bitRate: bitRate,
                            formatType: formatType)
        
        try? session.setPreferredSampleRate(settings.sampleRate)
    }
}

struct Settings {
    var sampleRate: Double = 48000
    var channels: AVAudioChannelCount = 1
    var bitRate: Int = 96000
    var formatType: AudioFormatID = kAudioFormatMPEG4AAC
    
    var avSettings: [String: Any] {
        [AVFormatIDKey: formatType, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: channels, AVEncoderBitRateKey: bitRate]
    }
}


