import Foundation
import AVFoundation
import Combine

final class AudioManager: ObservableObject {
    enum RecordingState {
        case recording, paused, stopped
    }
    
    @Published private(set) var state: RecordingState = .stopped
    @Published private(set) var currentFileURL: URL?
    
    private let engine  = AVAudioEngine()
    private let mixerNode = AVAudioMixerNode()
    private let session = AVAudioSession.sharedInstance()
    private var audioFile: AVAudioFile?
    private var tapInstalled = false
    
    struct Settings {
        var sampleRate: Double = 48000
        var channels: AVAudioChannelCount = 1
        var bitRate: Int = 96000
        var formatType: AudioFormatID = kAudioFormatMPEG4AAC
        
        var avSettings: [String: Any] {
            [AVFormatIDKey: formatType, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: channels, AVEncoderBitRateKey: bitRate]
        }
    }
    
    private var settings = Settings()
    
    init(){
        mixerNode.volume = 0
        engine.attach(mixerNode)
        connectGraph()
        engine.prepare()
    }
    
    private func connectGraph() {
        let input = engine.inputNode
        let inputFmt = input.outputFormat(forBus: 0)
        
        engine.connect(input, to: mixerNode, format: inputFmt)
        
        let mainMixer = engine.mainMixerNode
        let mixFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputFmt.sampleRate,
                                   channels: settings.channels, interleaved: false)!
        
        engine.connect(mixerNode, to: mainMixer, format: mixFmt)
    }
    
    
    func updateSettings(sampleRate: Double, channels: AVAudioChannelCount, bitRate: Int, formatType: AudioFormatID) {
        guard state == .stopped else { return }
        
        settings = Settings(sampleRate: sampleRate, channels: channels, bitRate: bitRate,
                                   formatType: formatType)
        
        try? session.setPreferredSampleRate(settings.sampleRate)
    }
    
    func start() {
        guard state == .stopped else { return }
        
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? session.setActive(true)
        
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let filename = "rec_\(Int(Date().timeIntervalSince1970)).m4a"
        let url = docs.appendingPathComponent(filename)
        currentFileURL = url
        
        
        let inputFmt = engine.inputNode.outputFormat(forBus: 0)
        audioFile = try? AVAudioFile(forWriting: url, settings: settings.avSettings, commonFormat: inputFmt.commonFormat,
                                     interleaved: inputFmt.isInterleaved)
        
        if tapInstalled {
                engine.inputNode.removeTap(onBus: 0)
                tapInstalled = false
            }
        
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            try? self?.audioFile?.write(from: buffer)
        }
        
        tapInstalled = true
        
        try? engine.start()
        state = .recording
        
    }
    
    func pause() {
        guard state == .recording  else { return }
        
        engine.pause()
        state = .paused
    }
    
    func resume() {
        guard state == .paused else { return }
        
        try? engine.start()
        state = .recording
    }
    
    func stop() {
        guard state != .stopped else { return }
        
        engine.stop()
        if tapInstalled {
                engine.inputNode.removeTap(onBus: 0)
            }
        tapInstalled = false
        audioFile = nil
        try? session.setActive(false)
        state = .stopped
    }
    
}


