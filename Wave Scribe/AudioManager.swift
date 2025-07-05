import AVFoundation
import Foundation

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

    init() {
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

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let filename = "rec_\(Int(Date().timeIntervalSince1970)).m4a"
        let url = docs.appendingPathComponent(filename)
        currentFileURL = url

        audioFile = try? AVAudioFile(
            forWriting: url,
            settings: settings.avSettings)

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
            try? self?.audioFile?.write(from: buffer)
            self?.updateLevel(from: buffer)
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
            print("Restart after route change failed:", error)
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

    private var targetFormat: AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: settings.sampleRate,
            channels: settings.channels,
            interleaved: false)!
    }
}

struct Settings {
    var sampleRate: Double = 48000
    var channels: AVAudioChannelCount = 1
    var bitRate: Int = 96000
    var formatType: AudioFormatID = kAudioFormatMPEG4AAC

    var avSettings: [String: Any] {
        [
            AVFormatIDKey: formatType, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: bitRate,
        ]
    }
}
