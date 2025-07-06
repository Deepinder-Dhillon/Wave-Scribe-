//
//  Settings.swift
//  Wave Scribe
//
//  Created by Deepinder on 2025-07-05.
//

import AVFAudio

struct Settings {
    var sampleRate: Double = 48000
    var channels: AVAudioChannelCount = 1
    var bitRate: Int = 96000
    var formatType: AudioFormatID = kAudioFormatMPEG4AAC
    
    var avSettings: [String: Any] {
        [
            AVFormatIDKey: formatType,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: bitRate,
        ]
    }
}
