import Foundation
import SwiftOpenAI

protocol TranscriptionServiceDelegate: AnyObject {
    func transcriptionService(_ service: TranscriptionService, didCompleteTranscription text: String, for segmentID: UUID)
    func transcriptionService(_ service: TranscriptionService, didFailWithError error: Error, for segmentID: UUID)
}

final class TranscriptionService {
    weak var delegate: TranscriptionServiceDelegate?
    
    private var openAIService: OpenAIService?
    private var apiKey: String
    
    init(apiKey: String) {
        self.apiKey = apiKey
        self.openAIService = OpenAIServiceFactory.service(apiKey: apiKey)
    }
    
    func transcribeAudio(_ audioData: Data, segmentID: UUID) async {
        guard !apiKey.isEmpty else {
            let error = NSError(domain: "TranscriptionService", code: 1, userInfo: [NSLocalizedDescriptionKey: "API key not configured"])
            Task { @MainActor in
                delegate?.transcriptionService(self, didFailWithError: error, for: segmentID)
            }
            return
        }
        
        let maxRetries = 5
        for attempt in 1...maxRetries {
            do {
                let params = AudioTranscriptionParameters(
                    fileName: "\(segmentID.uuidString).m4a",
                    file: audioData
                )
                
                let service = openAIService ?? OpenAIServiceFactory.service(apiKey: apiKey)
                
                let startTime = Date()
                let result = try await service.createTranscription(parameters: params)
                let duration = Date().timeIntervalSince(startTime)
                
                Task { @MainActor in
                    delegate?.transcriptionService(self, didCompleteTranscription: result.text, for: segmentID)
                }
                return
                
            } catch {
                if attempt < maxRetries {
                    let delay = Double(attempt) * 2.0 // Exponential backoff: 2s, 4s, 6s, 8s
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    Task { @MainActor in
                        delegate?.transcriptionService(self, didFailWithError: error, for: segmentID)
                    }
                }
            }
        }
    }
} 
