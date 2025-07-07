
import AVFAudio

struct Settings {
    var sampleRate: Double = 48000
    var channels: AVAudioChannelCount = 1
    var bitRate: Int = 96000
    var formatType: AudioFormatID = kAudioFormatMPEG4AAC
    var segmentDuration: TimeInterval = 10.0
    
    var avSettings: [String: Any] {
        [
            AVFormatIDKey: formatType,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: bitRate,
        ]
    }
}
