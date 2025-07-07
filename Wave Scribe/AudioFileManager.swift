import AVFoundation
import Foundation

protocol AudioFileManagerDelegate: AnyObject {
    func audioFileManager(_ manager: AudioFileManager, didCreateSegmentFile file: AVAudioFile, at url: URL)
    func audioFileManager(_ manager: AudioFileManager, didEncounterError error: Error)
}

final class AudioFileManager {
    weak var delegate: AudioFileManagerDelegate?
    
    private let recordingsRootURL: URL
    private var currentSegmentFile: AVAudioFile?
    private var currentSegmentFrames: AVAudioFrameCount = 0
    private var currentSegmentIndex: Int = 0
    private let segmentDuration: Double = 30
    
    private var settings = Settings()
    
    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let root = docs.appendingPathComponent("Recordings")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        
        self.recordingsRootURL = root
    }
    
    // MARK: - File Management
    
    func updateSettings(
        sampleRate: Double,
        channels: AVAudioChannelCount,
        bitRate: Int,
        formatType: AudioFormatID
    ) {
        settings = Settings(
            sampleRate: sampleRate,
            channels: channels,
            bitRate: bitRate,
            formatType: formatType
        )
    }
    
    func startNewRecording(with recordingID: UUID) {
        currentSegmentIndex = 0
        currentSegmentFrames = 0
        createNewSegmentFile(for: recordingID)
    }
    
    private func createNewSegmentFile(for recordingID: UUID) {
        let name = "\(recordingID.uuidString)_seg_\(String(format: "%03d", currentSegmentIndex)).m4a"
        let url = recordingsRootURL.appendingPathComponent(name)
        
        do {
            currentSegmentFile = try AVAudioFile(forWriting: url, settings: settings.avSettings)
            if let file = currentSegmentFile {
                Task { @MainActor in
                    delegate?.audioFileManager(self, didCreateSegmentFile: file, at: url)
                }
            }
        } catch {
            Task { @MainActor in
                delegate?.audioFileManager(self, didEncounterError: error)
            }
        }
    }
    
    func writeBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let segmentFile = currentSegmentFile else { return }
        
        do {
            try segmentFile.write(from: buffer)
            currentSegmentFrames += buffer.frameLength
        } catch {
            Task { @MainActor in
                delegate?.audioFileManager(self, didEncounterError: error)
            }
        }
    }
    
    func saveCurrentSegment() -> (url: URL, duration: Double, index: Int)? {
        guard let segmentFile = currentSegmentFile else { return nil }
        
        let duration = Double(currentSegmentFrames) / settings.sampleRate
        let url = segmentFile.url
        let index = currentSegmentIndex
        
        currentSegmentFile = nil
        currentSegmentFrames = 0
        
        return (url: url, duration: duration, index: index)
    }
    
    func startNewSegment(for recordingID: UUID) {
        currentSegmentIndex += 1
        createNewSegmentFile(for: recordingID)
    }
    
    // MARK: - Public Interface
    
    var segmentTargetFrames: AVAudioFrameCount {
        AVAudioFrameCount(settings.sampleRate * segmentDuration)
    }
    
    var shouldCreateNewSegment: Bool {
        return currentSegmentFrames >= segmentTargetFrames
    }
    
    var currentSegmentURL: URL? {
        return currentSegmentFile?.url
    }
    
    func cleanup() {
        currentSegmentFile = nil
        currentSegmentFrames = 0
        currentSegmentIndex = 0
    }
} 