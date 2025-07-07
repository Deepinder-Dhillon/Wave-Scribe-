import XCTest
import AVFAudio
@testable import Wave_Scribe

final class Wave_ScribeTests: XCTestCase {
    func testSettingsDefaultValues() throws {
        let settings = Settings()
        XCTAssertEqual(settings.sampleRate, 48000)
        XCTAssertEqual(settings.channels, 1)
        XCTAssertEqual(settings.segmentDuration, 10.0)
        XCTAssertEqual(settings.bitRate, 96000)
        XCTAssertEqual(settings.formatType, kAudioFormatMPEG4AAC)
    }

    func testSettingsAVSettings() throws {
        let settings = Settings()
        let avSettings = settings.avSettings
        XCTAssertEqual(avSettings[AVSampleRateKey] as? Double, 48000)
        if let channels = avSettings[AVNumberOfChannelsKey] as? NSNumber {
            XCTAssertEqual(channels.intValue, 1)
        } else if let channels = avSettings[AVNumberOfChannelsKey] as? UInt32 {
            XCTAssertEqual(channels, 1)
        } else {
            XCTFail("AVNumberOfChannelsKey not found or wrong type")
        }
        XCTAssertEqual(avSettings[AVFormatIDKey] as? AudioFormatID, kAudioFormatMPEG4AAC)
        XCTAssertEqual(avSettings[AVEncoderBitRateKey] as? Int, 96000)
    }

    func testSegmentStatusInitialization() throws {
        let id = UUID()
        let index = 5
        let status = "uploading"
        let transcript = "Hello world"
        let segmentStatus = SegmentStatus(id: id, index: index, status: status, transcript: transcript)
        XCTAssertEqual(segmentStatus.id, id)
        XCTAssertEqual(segmentStatus.index, index)
        XCTAssertEqual(segmentStatus.status, status)
        XCTAssertEqual(segmentStatus.transcript, transcript)
    }

    func testSegmentStatusDefaultValues() throws {
        let id = UUID()
        let index = 10
        let segmentStatus = SegmentStatus(id: id, index: index)
        XCTAssertEqual(segmentStatus.id, id)
        XCTAssertEqual(segmentStatus.index, index)
        XCTAssertEqual(segmentStatus.status, "recording")
        XCTAssertNil(segmentStatus.transcript)
    }

    @MainActor
    func testRecordingUIStateManagerStateTransitions() throws {
        let manager = RecordingUIStateManager()
        // Initial state
        XCTAssertEqual(manager.state, .stopped)
        XCTAssertEqual(manager.audioLevel, 0.0)
        XCTAssertFalse(manager.isUIDisabled)
        XCTAssertFalse(manager.resumePrompt)
        XCTAssertNil(manager.currentFileURL)
        XCTAssertFalse(manager.showError)
        XCTAssertEqual(manager.errorTitle, "")
        XCTAssertEqual(manager.errorMessage, "")

        // Test state update
        manager.updateRecordingState(.recording)
        XCTAssertEqual(manager.state, .recording)
        manager.updateRecordingState(.paused)
        XCTAssertEqual(manager.state, .paused)
        manager.updateRecordingState(.stopped)
        XCTAssertEqual(manager.state, .stopped)

        // Test audio level
        manager.updateAudioLevel(0.5)
        XCTAssertEqual(manager.audioLevel, 0.5)

        // Test UI disabled
        manager.updateUIDisabled(true)
        XCTAssertTrue(manager.isUIDisabled)
        manager.updateUIDisabled(false)
        XCTAssertFalse(manager.isUIDisabled)

        // Test resume prompt
        manager.updateResumePrompt(true)
        XCTAssertTrue(manager.resumePrompt)
        manager.updateResumePrompt(false)
        XCTAssertFalse(manager.resumePrompt)

        // Test file URL
        let url = URL(fileURLWithPath: "/tmp/test.m4a")
        manager.updateCurrentFileURL(url)
        XCTAssertEqual(manager.currentFileURL, url)
        manager.updateCurrentFileURL(nil)
        XCTAssertNil(manager.currentFileURL)

        // Test error
        manager.showError("Test Error", message: "Something went wrong")
        XCTAssertTrue(manager.showError)
        XCTAssertEqual(manager.errorTitle, "Test Error")
        XCTAssertEqual(manager.errorMessage, "Something went wrong")
        manager.dismissError()
        XCTAssertFalse(manager.showError)
    }

}
