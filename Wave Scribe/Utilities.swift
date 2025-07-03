import AVFAudio

func requestMicPermission() {
    let status = AVAudioApplication.shared.recordPermission
    guard status == .undetermined else { return }

    Task {
        _ = await AVAudioApplication.requestRecordPermission()
    }
}

func canRecordAudio() -> Bool {
    AVAudioApplication.shared.recordPermission == .granted
}
