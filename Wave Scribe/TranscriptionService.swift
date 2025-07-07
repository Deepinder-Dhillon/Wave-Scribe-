import Foundation

/**
 * Handles OpenAI Whisper API integration for audio transcription
 * Implements retry logic and proper error handling for network requests
 */
class TranscriptionService: NSObject {
    // MARK: - Configuration
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/audio/transcriptions"
    private let maxRetries = 5
    
    // MARK: - Delegation
    weak var delegate: TranscriptionServiceDelegate?
    
    init(apiKey: String) {
        self.apiKey = apiKey
        super.init()
    }
    
    // MARK: - Public Interface
    
    /**
     * Transcribes audio file using OpenAI Whisper API
     * Implements exponential backoff retry logic for failed requests
     */
    func transcribeAudio(fileURL: URL, segmentID: UUID) async {
        guard !apiKey.isEmpty else {
            await delegate?.transcriptionService(self, didEncounterError: TranscriptionError.apiError(0, "No API key configured"), for: segmentID)
            return
        }
        var retryCount = 0
        while retryCount < maxRetries {
            do {
                let transcript = try await performTranscription(fileURL: fileURL)
                await delegate?.transcriptionService(self, didCompleteTranscription: transcript, for: segmentID)
                return
            } catch {
                retryCount += 1
                if retryCount >= maxRetries {
                    await delegate?.transcriptionService(self, didEncounterError: error, for: segmentID)
                    return
                }
                let delay = pow(2.0, Double(retryCount))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }
    
    // MARK: - Network Operations
    
    /**
     * Performs the actual API request to OpenAI Whisper
     * Handles multipart form data and response parsing
     */
    private func performTranscription(fileURL: URL) async throws -> String {
        let boundary = UUID().uuidString
        guard let url = URL(string: baseURL) else {
            throw TranscriptionError.apiError(0, "Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        do {
            let fileHandle = try FileHandle(forReadingFrom: fileURL)
            let fileData = try fileHandle.readToEnd() ?? Data()
            try fileHandle.close()
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
            body.append(fileData)
            body.append("\r\n".data(using: .utf8)!)
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
            body.append("whisper-1\r\n".data(using: .utf8)!)
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        } catch {
            throw error
        }
        request.httpBody = body
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        let session = URLSession(configuration: config)
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw TranscriptionError.invalidResponse
            }
            guard httpResponse.statusCode == 200 else {
                throw TranscriptionError.apiError(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "Unknown error")
            }
            let transcriptionResponse = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
            return transcriptionResponse.text
        } catch {
            throw error
        }
    }
}

// MARK: - Response Models

/**
 * OpenAI Whisper API response structure
 */
struct TranscriptionResponse: Codable {
    let text: String
}

// MARK: - Error Types

/**
 * Custom error types for transcription failures
 */
enum TranscriptionError: Error, LocalizedError {
    case invalidResponse
    case apiError(Int, String)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from transcription service"
        case .apiError(let code, let message):
            return "API error \(code): \(message)"
        }
    }
}

// MARK: - Delegate Protocol

/**
 * Protocol for receiving transcription service events
 * Allows UI updates and error handling
 */
protocol TranscriptionServiceDelegate: AnyObject {
    func transcriptionService(_ service: TranscriptionService, didCompleteTranscription transcript: String, for segmentID: UUID)
    func transcriptionService(_ service: TranscriptionService, didEncounterError error: Error, for segmentID: UUID)
    func transcriptionService(_ service: TranscriptionService, didUpdateProgress progress: Double, for segmentID: UUID)
} 
