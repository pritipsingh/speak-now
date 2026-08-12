import AVFoundation
import Foundation

/// Records the microphone to a temporary `.m4a` file while the hotkey is held.
///
/// Uses `AVAudioRecorder`, which handles microphone capture and file encoding with
/// no manual buffer or format juggling. AAC/m4a is accepted by the OpenAI
/// transcription endpoint and keeps uploads small.
final class AudioRecorder {
    private var recorder: AVAudioRecorder?
    private var currentURL: URL?

    enum RecorderError: Error { case couldNotCreateRecorder }

    /// Begin recording. Throws if the recorder cannot be created.
    func start() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wisprflow-\(UUID().uuidString).m4a")

        // 16 kHz mono AAC — plenty for speech, small to upload.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            throw RecorderError.couldNotCreateRecorder
        }
        self.recorder = recorder
        self.currentURL = url
    }

    /// Current input loudness as a normalized 0...1 value, for driving a live
    /// waveform. Reads the average power meter (dBFS) and maps it onto a curve
    /// that feels responsive to speech.
    func currentLevel() -> Float {
        guard let recorder else { return 0 }
        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0)  // ~ -160 (silence) ... 0 (max)
        let minDb: Float = -55
        if db < minDb { return 0 }
        if db >= 0 { return 1 }
        // Normalize -55...0 dB to 0...1, then ease so quiet speech still moves bars.
        let linear = (db - minDb) / -minDb
        return powf(linear, 0.6)
    }

    /// Stop recording and return the URL of the recorded file (nil if nothing recorded).
    @discardableResult
    func stop() -> URL? {
        recorder?.stop()
        recorder = nil
        let url = currentURL
        currentURL = nil
        // Guard against empty/near-empty recordings (e.g. an accidental tap).
        if let url, let size = try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? Int, size < 1_200
        {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }
}
