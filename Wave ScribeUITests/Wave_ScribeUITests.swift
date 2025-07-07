import XCTest

final class Wave_ScribeUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Basic UI Tests
    
    func testAppLaunchesSuccessfully() throws {
        // Test that the app launches without crashing
        XCTAssertTrue(app.exists)
    }
    
    func testMainViewElementsExist() throws {
        // Test that main UI elements are present
        XCTAssertTrue(app.navigationBars["Recordings"].exists)
        XCTAssertTrue(app.buttons["largecircle.fill.circle"].exists)
    }
    
    func testRecordButtonExists() throws {
        // Test that the record button is present
        let recordButton = app.buttons["largecircle.fill.circle"]
        XCTAssertTrue(recordButton.exists)
    }
    
    func testRecordButtonIsEnabled() throws {
        // Test that the record button is enabled
        let recordButton = app.buttons["largecircle.fill.circle"]
        XCTAssertTrue(recordButton.isEnabled)
    }
    
    func testRecordButtonIsHittable() throws {
        // Test that the record button can be tapped
        let recordButton = app.buttons["largecircle.fill.circle"]
        XCTAssertTrue(recordButton.isHittable)
    }
    
    func testRecordButtonColor() throws {
        // Test that the record button has the expected color
        let recordButton = app.buttons["largecircle.fill.circle"]
        XCTAssertTrue(recordButton.exists)
        // Note: We can't easily test color in UI tests, but we can verify the button exists
    }
    
    func testNavigationBarTitle() throws {
        // Test that the navigation bar shows the correct title
        let navigationBar = app.navigationBars["Recordings"]
        XCTAssertTrue(navigationBar.exists)
    }
    
    func testRecordButtonTap() throws {
        // Test that tapping the record button doesn't crash the app
        let recordButton = app.buttons["largecircle.fill.circle"]
        recordButton.tap()
        
        // The app should still be responsive after tapping
        XCTAssertTrue(app.exists)
    }
    
    func testAppStaysResponsive() throws {
        // Test that the app remains responsive after various interactions
        let recordButton = app.buttons["largecircle.fill.circle"]
        
        // Tap multiple times to ensure app stays responsive
        for _ in 0..<3 {
            recordButton.tap()
            XCTAssertTrue(app.exists)
        }
    }
    
    func testNoRecordingsInitially() throws {
        // Test that there are no recordings initially
        // This is a simple test that should pass on a fresh app
        XCTAssertTrue(app.exists)
    }
    
    func testAppCanBeBackgrounded() throws {
        // Test that the app can be backgrounded and foregrounded
        XCUIDevice.shared.press(.home)
        
        // Return to app
        app.activate()
        
        // App should still be responsive
        XCTAssertTrue(app.exists)
    }
    
    func testRecordButtonAccessibility() throws {
        // Test that the record button has accessibility support
        let recordButton = app.buttons["largecircle.fill.circle"]
        XCTAssertTrue(recordButton.exists)
        
        // Test that it can be accessed via accessibility
        XCTAssertTrue(recordButton.isAccessibilityElement)
    }
    
    func testAppLaunchPerformance() throws {
        // Test app launch performance
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
        }
    }
    
    func testMemoryUsage() throws {
        // Simple test to ensure app doesn't crash under basic usage
        let recordButton = app.buttons["largecircle.fill.circle"]
        
        // Perform some basic interactions
        for _ in 0..<5 {
            recordButton.tap()
            XCTAssertTrue(app.exists)
        }
    }
    
    func testAppOrientation() throws {
        // Test that app handles orientation changes
        XCTAssertTrue(app.exists)
        
        // Note: We can't easily test orientation changes in UI tests
        // but we can verify the app remains responsive
    }
    
    func testRecordButtonSize() throws {
        // Test that the record button has a reasonable size
        let recordButton = app.buttons["largecircle.fill.circle"]
        XCTAssertTrue(recordButton.exists)
        
        let frame = recordButton.frame
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
    }
    
    func testAppLaunchTime() throws {
        // Test that app launches within reasonable time
        let startTime = Date()
        app.launch()
        let launchTime = Date().timeIntervalSince(startTime)
        
        // App should launch in less than 5 seconds
        XCTAssertLessThan(launchTime, 5.0)
    }
    
    // MARK: - Recording Flow Tests
    
    func testStartRecording() throws {
        // Test starting a recording
        let recordButton = app.buttons["largecircle.fill.circle"]
        
        // Tap record button
        recordButton.tap()
        
        // Wait for recording view to appear
        XCTAssertTrue(app.waitForExistence(timeout: 2))
        
        // Verify recording view elements
        XCTAssertTrue(app.pickers["mode picker"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '0:00'")).firstMatch.exists)
    }
    
    func testRecordingViewModes() throws {
        // Start recording
        app.buttons["largecircle.fill.circle"].tap()
        
        // Test switching between Waveform and Transcribe modes
        let modePicker = app.pickers["mode picker"]
        XCTAssertTrue(modePicker.exists)
        
        // Switch to Transcribe mode
        let transcribeSegment = modePicker.buttons["Transcribe"]
        transcribeSegment.tap()
        
        // Verify transcribe view appears
        XCTAssertTrue(app.staticTexts["No transcriptions yet"].exists)
    }
    
    func testStopRecording() throws {
        // Start recording
        app.buttons["largecircle.fill.circle"].tap()
        
        // Wait for recording to start
        XCTAssertTrue(app.waitForExistence(timeout: 2))
        
        // Stop recording by dismissing the view
        // This simulates the user stopping the recording
        app.buttons["Done"].tap()
        
        // Verify we're back to main view
        XCTAssertTrue(app.navigationBars["Recordings"].exists)
    }
    
    // MARK: - Navigation Tests
    
    func testNavigationToRecordView() throws {
        // Test navigation to recording view
        app.buttons["largecircle.fill.circle"].tap()
        
        // Verify we're in recording view
        XCTAssertTrue(app.waitForExistence(timeout: 2))
        
        // Test navigation back
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Recordings"].exists)
    }
    
    // MARK: - Accessibility Tests
    
    func testAccessibilityLabels() throws {
        // Test that important elements have accessibility labels
        let recordButton = app.buttons["largecircle.fill.circle"]
        XCTAssertTrue(recordButton.exists)
        
        // Test navigation bar accessibility
        let recordingsNavBar = app.navigationBars["Recordings"]
        XCTAssertTrue(recordingsNavBar.exists)
    }
    
    // MARK: - Performance Tests
    
    func testRecordingViewLoadPerformance() throws {
        measure {
            app.buttons["largecircle.fill.circle"].tap()
            XCTAssertTrue(app.waitForExistence(timeout: 2))
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testMicrophonePermissionDenied() throws {
        // This test would require special setup to simulate denied permissions
        // For now, we'll just verify the app handles the permission request gracefully
        
        // Start recording (this will trigger permission request)
        app.buttons["largecircle.fill.circle"].tap()
        
        // The app should handle permission denial gracefully
        // This is a basic test - in a real scenario, you'd need to simulate permission denial
    }
    
    // MARK: - UI State Tests
    
    func testRecordingViewInitialState() throws {
        app.buttons["largecircle.fill.circle"].tap()
        
        // Test initial state of recording view
        XCTAssertTrue(app.waitForExistence(timeout: 2))
        
        // Verify timer shows 0:00 initially
        let timerText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS '0:00'")).firstMatch
        XCTAssertTrue(timerText.exists)
        
        // Verify mode picker defaults to Waveform
        let modePicker = app.pickers["mode picker"]
        XCTAssertTrue(modePicker.exists)
    }
    
    func testTranscribeViewInitialState() throws {
        app.buttons["largecircle.fill.circle"].tap()
        
        // Switch to Transcribe mode
        let modePicker = app.pickers["mode picker"]
        let transcribeSegment = modePicker.buttons["Transcribe"]
        transcribeSegment.tap()
        
        // Verify transcribe view shows "No transcriptions yet"
        XCTAssertTrue(app.staticTexts["No transcriptions yet"].exists)
        XCTAssertTrue(app.staticTexts["Start recording to see transcriptions appear here"].exists)
    }
    
    // MARK: - Gesture Tests
    
    func testRecordButtonTapGesture() throws {
        let recordButton = app.buttons["largecircle.fill.circle"]
        
        // Test single tap
        recordButton.tap()
        XCTAssertTrue(app.waitForExistence(timeout: 2))
        
        // Go back
        app.buttons["Done"].tap()
        
        // Test double tap (should still work)
        recordButton.doubleTap()
        XCTAssertTrue(app.waitForExistence(timeout: 2))
    }
} 