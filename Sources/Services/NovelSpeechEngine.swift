import AVFoundation
import Foundation

@MainActor
public final class NovelSpeechEngine: NSObject, ObservableObject {
	@Published public private(set) var isActive: Bool = false
	@Published public private(set) var isPaused: Bool = false
	@Published public private(set) var currentParagraphIndex: Int = 0
	@Published public var speechRateMultiplier: Float = 1.0
	@Published public private(set) var sleepMinutesRemaining: Int = 0

	public var onChapterFinished: (() -> Void)?

	private let synthesizer = AVSpeechSynthesizer()
	private var paragraphs: [String] = []
	private var languageLocale: String = "id-ID"
	private var sleepTask: Task<Void, Never>?

	public static let speedPresets: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
	public static let sleepPresets: [Int] = [0, 15, 30, 45, 60]

	public override init() {
		super.init()
		synthesizer.delegate = self
	}

	public func start(paragraphs: [String], startIndex: Int, locale: String) {
		guard !paragraphs.isEmpty else { return }
		configureAudioSession()
		self.paragraphs = paragraphs
		self.languageLocale = locale
		self.currentParagraphIndex = min(max(0, startIndex), paragraphs.count - 1)
		self.isActive = true
		self.isPaused = false
		speakCurrent()
	}

	public func updateParagraphs(_ paragraphs: [String], locale: String) {
		self.paragraphs = paragraphs
		self.languageLocale = locale
		if isActive && !isPaused {
			currentParagraphIndex = min(currentParagraphIndex, max(0, paragraphs.count - 1))
			speakCurrent()
		}
	}

	public func togglePause() {
		guard isActive else { return }
		isPaused.toggle()
		if isPaused {
			synthesizer.stopSpeaking(at: .immediate)
		} else {
			speakCurrent()
		}
	}

	public func skip(by delta: Int) {
		guard isActive, !paragraphs.isEmpty else { return }
		currentParagraphIndex = min(max(0, currentParagraphIndex + delta), paragraphs.count - 1)
		isPaused = false
		speakCurrent()
	}

	public func cycleSpeed() {
		let idx = Self.speedPresets.firstIndex { abs($0 - speechRateMultiplier) < 0.05 } ?? 1
		speechRateMultiplier = Self.speedPresets[(idx + 1) % Self.speedPresets.count]
		if isActive && !isPaused {
			speakCurrent()
		}
	}

	public func cycleSleepTimer() {
		sleepTask?.cancel()
		let idx = Self.sleepPresets.firstIndex(of: sleepMinutesRemaining > 0 ? nearestPreset(sleepMinutesRemaining) : 0) ?? 0
		let nextMinutes = Self.sleepPresets[(idx + 1) % Self.sleepPresets.count]
		sleepMinutesRemaining = nextMinutes
		guard nextMinutes > 0 else { return }
		let targetEnd = Date().addingTimeInterval(TimeInterval(nextMinutes * 60))
		sleepTask = Task { [weak self] in
			while !Task.isCancelled {
				let remaining = targetEnd.timeIntervalSinceNow
				if remaining <= 0 {
					await MainActor.run {
						self?.sleepMinutesRemaining = 0
						if self?.isActive == true && self?.isPaused == false {
							self?.togglePause()
						}
					}
					break
				}
				await MainActor.run {
					self?.sleepMinutesRemaining = max(1, Int(ceil(remaining / 60.0)))
				}
				try? await Task.sleep(nanoseconds: 15_000_000_000)
			}
		}
	}

	public func stop() {
		sleepTask?.cancel()
		sleepMinutesRemaining = 0
		isActive = false
		isPaused = false
		synthesizer.stopSpeaking(at: .immediate)
	}

	private func speakCurrent() {
		synthesizer.stopSpeaking(at: .immediate)
		guard isActive, !isPaused, paragraphs.indices.contains(currentParagraphIndex) else { return }
		let text = paragraphs[currentParagraphIndex]
		let utterance = AVSpeechUtterance(string: text)
		utterance.voice = AVSpeechSynthesisVoice(language: languageLocale)
			?? AVSpeechSynthesisVoice(language: "en-US")
		let mappedRate = AVSpeechUtteranceDefaultSpeechRate * speechRateMultiplier
		utterance.rate = min(max(mappedRate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
		synthesizer.speak(utterance)
	}

	private func configureAudioSession() {
		let session = AVAudioSession.sharedInstance()
		try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
		try? session.setActive(true)
	}

	private func nearestPreset(_ mins: Int) -> Int {
		Self.sleepPresets.first { $0 >= mins } ?? Self.sleepPresets.last ?? 0
	}
}

extension NovelSpeechEngine: AVSpeechSynthesizerDelegate {
	nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
		Task { @MainActor [weak self] in
			guard let self, self.isActive, !self.isPaused else { return }
			if self.currentParagraphIndex + 1 < self.paragraphs.count {
				self.currentParagraphIndex += 1
				self.speakCurrent()
			} else {
				self.onChapterFinished?()
			}
		}
	}
}
