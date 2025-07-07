import AVFAudio
import CloudKit

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


func saveAPIKeyRecord() async{
    let recordID = CKRecord.ID(recordName: "whisper-api")
    let record = CKRecord(recordType: "APIKey", recordID: recordID)

   // save your own key
    record.encryptedValues["key"] = "your key" as NSString

    let privateDB = CKContainer.default().privateCloudDatabase
    do {
        try await privateDB.save(record)
    } catch {
        print("failed to save key:", error)
    }
}


func fetchAPIKey() async -> String {
    let recordID = CKRecord.ID(recordName: "whisper-api")
    let privateDB = CKContainer.default().privateCloudDatabase
    
    do {
        let record = try await privateDB.record(for: recordID)
        if let key = record.encryptedValues["key"] as? String, !key.isEmpty {
            return key
        }
    } catch {
        print("No API key found in CloudKit")
    }
    return ""
}
