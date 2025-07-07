# Wave Scribe - iOS Audio Recording & Transcription App

## Overview
Wave Scribe is an iOS application for high-quality audio recording, automatic segmentation, real-time transcription using OpenAI's Whisper API, and robust recording management using Core Data. The app is built with SwiftUI and follows the MVVM (Model-View-ViewModel) architecture, emphasizing maintainability, testability, and extensibility.

---

## Prerequisites
- Xcode 15.0 or later
- iOS 16.0 or later
- Swift 5.9 or later
- [Swift Package Manager](https://swift.org/package-manager/)
- [SwiftOpenAI](https://github.com/jamesrochabrun/SwiftOpenAI) package (for OpenAI API integration)
- OpenAI API key (see below)

### Installing SwiftOpenAI
Add the following dependency to your `Package.swift` or use Xcode's Swift Package Manager integration:

```
.package(url: "https://github.com/jamesrochabrun/SwiftOpenAI.git", from: "4.3.0")
```

For more details, see the [SwiftOpenAI documentation](https://github.com/jamesrochabrun/SwiftOpenAI).

---

## OpenAI API Key Management
- An OpenAI API key is required to use the transcription features of the app.
- The app uses **CloudKit** to securely store and retrieve the API key. This allows the key to be managed outside of the app bundle and synchronized across devices.
- On first launch, you will be prompted to provide your API key, which will be saved in your private CloudKit database.

---

## Credits
- **Waveform Visualization**: This app uses [SCSiriWaveformView](https://github.com/stefanceriu/SCSiriWaveformView) by Stefan Ceriu for waveform rendering in the UI. Copyright (c) 2014 Stefan Ceriu.
- **OpenAI API Integration**: Powered by [SwiftOpenAI](https://github.com/jamesrochabrun/SwiftOpenAI) by James Rochabrun and contributors.

---

## Architecture

### MVVM Pattern
- **Model**: Core Data entities (`Recording`, `Segment`) represent persistent data.
- **View**: SwiftUI views present the UI and bind to view models.
- **ViewModel**: ObservableObject classes encapsulate business logic and UI state, mediating between views and models.

### Core Data
- **Entities**: `Recording` (audio session), `Segment` (audio chunk for transcription)
- **Relationships**: Each `Recording` has multiple `Segment` objects.
- **Persistence**: Managed via `CoreDataStack` with background contexts for non-blocking UI.

### Concurrency
- **Actors**: Used for thread-safe task management (e.g., `TaskTracker` for transcription concurrency limits).
- **Async/Await**: Modern Swift concurrency for network and background operations.
- **MainActor**: Ensures UI updates are performed on the main thread.

### Data Flow
1. **Recording**: User initiates recording. Audio is captured and segmented in real time.
2. **Segmentation**: Audio is split into fixed-duration segments (default: 30 seconds).
3. **Transcription**: Each segment is sent to the OpenAI Whisper API for transcription, with concurrency and retry logic.
4. **Persistence**: Segments and their transcripts are stored in Core Data. The final transcript is aggregated and attached to the recording.
5. **UI Update**: The UI is updated in real time as segments are processed and transcriptions are received.

---

## Component/Class Reference

### AudioManager
**Role:** Manages the audio session lifecycle, recording state, audio interruptions, and coordinates with the transcription system.

**Key Methods:**
- `start() throws`: Begins audio recording and sets up the audio engine.
- `stop()`: Stops recording, finalizes the last segment, and updates Core Data.
- `userResume()`: Resumes recording after an interruption.
- `userStop()`: Stops recording and cleans up state.
- `configureTranscription(apiKey:)`: Sets up the transcription coordinator with the provided API key.

### RecordingManager
**Role:** Handles Core Data operations for recordings and segments, manages the list of recordings, and aggregates segment transcripts.

**Key Methods:**
- `loadRecordings()`: Loads all recordings from Core Data and updates the UI.
- `refreshRecordings()`: Reloads recordings, typically after changes.
- `deleteRecording(_:)`: Deletes a recording and its associated segments and files.
- `updateRecordingTitle(_:title:)`: Updates the title of a recording.
- `getRecordingDetails(for:)`: Returns detailed information for a recording, including all segments and transcripts.

### TranscriptionCoordinator
**Role:** Manages concurrent transcription tasks, rate limiting, retry logic, and communication with the OpenAI Whisper API.

**Key Methods:**
- `transcribeSegment(segmentID:fileURL:)`: Initiates transcription for a segment, handling queuing and concurrency.
- `updateSegmentStatus(segmentID:status:)`: Updates the status of a segment in Core Data.
- Implements `TranscriptionServiceDelegate` to handle transcription results and errors.

### TranscriptionService
**Role:** Handles integration with the OpenAI Whisper API, including network requests, retry logic, and error handling.

**Key Methods:**
- `transcribeAudio(fileURL:segmentID:)`: Sends an audio segment to the API and handles the response.
- `performTranscription(fileURL:)`: Performs the actual network request and parses the response.

### RecordingUIStateManager
**Role:** Manages UI state for recording, including audio level, error prompts, and recording state transitions.

**Key Methods:**
- `updateRecordingState(_:)`: Sets the current recording state.
- `updateAudioLevel(_:)`: Updates the UI with the current audio level.
- `showError(title:message:)`: Displays an error message in the UI.
- `startRecording()`, `pauseRecording()`, `resumeRecording()`, `stopRecording()`: Convenience methods for state transitions.

### CoreDataStack
**Role:** Manages the Core Data stack, including persistent containers and context configuration.

**Key Methods:**
- `persistentContainer`: The main NSPersistentContainer instance.
- `viewContext`: The main context for UI operations.
- `backgroundContext`: For background data operations.

### TaskTracker (Actor)
**Role:** Limits the number of concurrent transcription tasks, manages a queue for pending tasks, and ensures thread safety.

**Key Methods:**
- `waitForAvailableSlot()`: Suspends until a slot is available for a new task.
- `taskDidFinish(for:)`: Marks a task as finished and processes the next waiting task.

---

## Data Flow: Step-by-Step
1. **User taps record**: `AudioManager.start()` is called, initializing the audio engine and starting a new `Recording` in Core Data.
2. **Audio is segmented**: As audio is captured, it is split into segments. Each segment is saved as a `Segment` entity and a file.
3. **Transcription**: For each segment, `TranscriptionCoordinator.transcribeSegment()` is called. The segment is queued if concurrency limits are reached.
4. **API Call**: `TranscriptionService.transcribeAudio()` sends the segment to the Whisper API. On success, the transcript is saved to the segment; on failure, retry logic is applied.
5. **Aggregation**: When all segments are transcribed, `RecordingManager` aggregates the transcripts into the final recording transcript.
6. **UI Update**: The UI is updated in real time via published properties and Core Data notifications.

---

## Extensibility
- **Adding Features**: New features can be added by extending view models or adding new SwiftUI views. Business logic should be placed in view models for testability.
- **Modifying Data Model**: Update the Core Data model and corresponding entities. Use migration strategies for existing data.
- **API Integration**: To support new transcription providers, implement a new service class and update the coordinator.
- **Testing**: All business logic is grouped in view models, making it easy to write unit tests for new features.

---

## Testing

### Manual Testing
- Start/stop recording
- Background recording
- Audio interruptions (phone calls, Siri)
- Audio route changes (headphones, Bluetooth)
- Network connectivity changes
- App termination during recording
- Multiple concurrent recordings
- Large dataset performance

### Automated Testing
- Unit tests are provided in the `Wave ScribeTests` directory. Use Xcode's test navigator to run tests.
- View models and business logic are designed for easy unit testing.

---

## Missing Features and Known Issues
- **Local transcription fallback**: No support for on-device transcription
- **Audio file encryption**: Audio files are not encrypted at rest
- **Export functionality**: No ability to export recordings or transcripts
- **Accessibility**: Limited accessibility features; improvements
- **Advanced search**: No full-text search across transcriptions


---

## Setup & Configuration

### Installation
1. Clone the repository:
   ```bash
   git clone [repository-url]
   cd Wave-Scribe
   ```
2. Open in Xcode:
   ```bash
   open "Wave Scribe.xcodeproj"
   ```
3. Configure API Key:
   - Open `Wave_ScribeApp.swift`
   - Replace `"your-api-key-here"` with your OpenAI API key
   - Or set up environment variables for production
4. Build and run on your device or simulator.

### Configuration
- Edit `Settings.swift` to customize sample rate, channels, and segment duration.
- Adjust transcription concurrency and retry settings in `TranscriptionCoordinator` and `TranscriptionService`.

---

## Contribution Guidelines
- Fork the repository and create a feature branch.
- Make your changes, following the existing code style and architecture.
- Add or update documentation and tests as appropriate.
- Submit a pull request for review.

---

## License
This project is licensed under the MIT License. See the LICENSE file for details.

