import AVFoundation
import Foundation
import Observation

/** 一次只放一条语音（Android `ChatAudioPlayer`）：再点同一条停，点别的换。 */
@MainActor
@Observable
final class ChatAudioPlayer {
    private(set) var playingURL: URL?
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    func toggle(_ url: URL) {
        if playingURL == url {
            stop()
            return
        }
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        player.play()
        self.player = player
        playingURL = url
    }

    func stop() {
        player?.pause()
        player = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        playingURL = nil
    }
}

/** 按住说话的录音（Android `ChatVoiceRecorder`）：m4a 写到临时目录，松手后交给发送。 */
@MainActor
@Observable
final class ChatVoiceRecorder {
    /** 短于这个时长不发（提示「说话时间太短」）。 */
    static let minimumMs = 1000
    /** 录满这个时长自动停（和 Android 一样一分钟）。 */
    static let maximumSeconds: TimeInterval = 60

    private(set) var isRecording = false
    private(set) var startedAt: Date?
    @ObservationIgnored private var recorder: AVAudioRecorder?

    /** 要麦克风权限；拒绝了返回 false。 */
    func start() async -> Bool {
        guard await AVAudioApplication.requestRecordPermission() else { return false }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
            let recorder = try AVAudioRecorder(url: file, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ])
            recorder.record(forDuration: Self.maximumSeconds)
            self.recorder = recorder
            startedAt = .now
            isRecording = true
            return true
        } catch {
            return false
        }
    }

    /** 停下：[send] 时返回文件和时长（太短返回 nil），否则删掉。 */
    func stop(send: Bool) -> (URL, Int)? {
        guard let recorder else { return nil }
        let durationMs = Int((startedAt.map { Date.now.timeIntervalSince($0) } ?? 0) * 1000)
        recorder.stop()
        self.recorder = nil
        isRecording = false
        startedAt = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard send, durationMs >= Self.minimumMs else {
            try? FileManager.default.removeItem(at: recorder.url)
            return nil
        }
        return (recorder.url, durationMs)
    }
}
