import Foundation
import AVFAudio

// MARK: - Audio Capture Service
final class AudioCaptureService: NSObject {
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    override init() {
        super.init()
    }

    /// Returns `true` if recording started successfully.
    func startRecording() -> Bool {
        // Permission is checked before calling this

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "recording_\(Int(Date().timeIntervalSince1970)).m4a"
        let fileURL = tempDir.appendingPathComponent(fileName)
        self.recordingURL = fileURL

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 128000,
        ]

        do {
            recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder?.delegate = self
            recorder?.isMeteringEnabled = true
            return recorder?.record() ?? false
        } catch {
            print("AudioCapture: failed to start recording: \(error)")
            return false
        }
    }

    /// Stops recording and returns the URL of the recorded file (or nil).
    func stopRecording() -> URL? {
        recorder?.stop()
        recorder = nil
        return recordingURL
    }

    /// Returns current recording power (0–1), 0 if not recording.
    func averagePower() -> Float {
        guard let r = recorder, r.isRecording else { return 0 }
        r.updateMeters()
        let level = r.averagePower(forChannel: 0)
        // Convert dB (-160 to 0) to 0–1
        return max(0, min(1, (level + 50) / 50))
    }

    static func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }
}

// MARK: - AVAudioRecorderDelegate
extension AudioCaptureService: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("AudioCapture: recording finished unsuccessfully")
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        print("AudioCapture: encode error: \(error?.localizedDescription ?? "unknown")")
    }
}
