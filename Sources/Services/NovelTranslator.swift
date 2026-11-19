import Foundation

public struct TargetLanguage: Identifiable, Hashable {
	public var id: String { code }
	public let code: String
	public let label: String
	public let badge: String
	public let speechLocale: String
}

public actor NovelTranslator {
	public static let shared = NovelTranslator()

	public static let langOff = "off"
	private static let firstBatchMaxChars = 1200
	private static let firstBatchMaxParagraphs = 8
	public static let maxCharsPerBatch = 3800
	public static let maxParagraphsPerBatch = 60

	private static let endpoints: [(String, String)] = [
		("https://translate.googleapis.com/translate_a/single", "gtx"),
		("https://translate.google.com/translate_a/single", "at"),
	]

	public static let supportedLanguages: [TargetLanguage] = [
		TargetLanguage(code: langOff, label: "Teks Asli (Tanpa Terjemahan)", badge: "ASLI", speechLocale: "en-US"),
		TargetLanguage(code: "id", label: "Bahasa Indonesia", badge: "ID", speechLocale: "id-ID"),
		TargetLanguage(code: "en", label: "English", badge: "EN", speechLocale: "en-US"),
		TargetLanguage(code: "ms", label: "Bahasa Melayu", badge: "MS", speechLocale: "ms-MY"),
		TargetLanguage(code: "ja", label: "日本語 (Japanese)", badge: "JA", speechLocale: "ja-JP"),
		TargetLanguage(code: "ko", label: "한국어 (Korean)", badge: "KO", speechLocale: "ko-KR"),
		TargetLanguage(code: "zh-CN", label: "中文 (Chinese Simplified)", badge: "ZH", speechLocale: "zh-CN"),
		TargetLanguage(code: "zh-TW", label: "繁體中文 (Chinese Traditional)", badge: "ZHT", speechLocale: "zh-TW"),
		TargetLanguage(code: "es", label: "Español (Spanish)", badge: "ES", speechLocale: "es-ES"),
		TargetLanguage(code: "fr", label: "Français (French)", badge: "FR", speechLocale: "fr-FR"),
		TargetLanguage(code: "de", label: "Deutsch (German)", badge: "DE", speechLocale: "de-DE"),
		TargetLanguage(code: "pt", label: "Português (Portuguese)", badge: "PT", speechLocale: "pt-BR"),
		TargetLanguage(code: "ru", label: "Русский (Russian)", badge: "RU", speechLocale: "ru-RU"),
		TargetLanguage(code: "ar", label: "العربية (Arabic)", badge: "AR", speechLocale: "ar-SA"),
		TargetLanguage(code: "hi", label: "हिन्दी (Hindi)", badge: "HI", speechLocale: "hi-IN"),
		TargetLanguage(code: "th", label: "ไทย (Thai)", badge: "TH", speechLocale: "th-TH"),
		TargetLanguage(code: "vi", label: "Tiếng Việt (Vietnamese)", badge: "VI", speechLocale: "vi-VN"),
		TargetLanguage(code: "tr", label: "Türkçe (Turkish)", badge: "TR", speechLocale: "tr-TR"),
		TargetLanguage(code: "it", label: "Italiano (Italian)", badge: "IT", speechLocale: "it-IT"),
		TargetLanguage(code: "tl", label: "Filipino / Tagalog", badge: "TL", speechLocale: "fil-PH"),
	]

	private var cache: [String: [String]] = [:]
	private var cacheOrder: [String] = []
	private let maxCacheItems = 32

	public static func findLanguage(_ code: String) -> TargetLanguage {
		supportedLanguages.first { $0.code == code } ?? supportedLanguages[0]
	}

	public func translateParagraphs(
		chapterKey: String,
		paragraphs: [String],
		targetLang: String,
		onProgress: (@Sendable ([String], Int, Int) async -> Void)? = nil
	) async throws -> [String] {
		guard !targetLang.isEmpty, targetLang != Self.langOff, !paragraphs.isEmpty else {
			return paragraphs
		}
		let cacheKey = "\(chapterKey)|\(targetLang)|\(paragraphs.count)"
		if let hit = cache[cacheKey] {
			await onProgress?(hit, 1, 1)
			return hit
		}

		let batches = Self.chunkParagraphs(paragraphs)
		var translatedBatches: [[String]] = []
		translatedBatches.reserveCapacity(batches.count)

		for (idx, batch) in batches.enumerated() {
			try Task.checkCancellation()
			let normalized = batch.map { Self.collapseWhitespace($0) }
			let joined = normalized.joined(separator: "\n\n")
			let raw = try await requestWithFailover(text: joined, targetLang: targetLang)
			let decoded = Self.parseGtxResponse(raw)
			let split = decoded
				.components(separatedBy: .newlines)
				.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
				.filter { !$0.isEmpty }
			translatedBatches.append(split.isEmpty ? normalized : split)

			if let onProgress {
				var partial: [String] = []
				for done in translatedBatches {
					partial.append(contentsOf: done)
				}
				if idx + 1 < batches.count {
					for rem in (idx + 1)..<batches.count {
						partial.append(contentsOf: batches[rem])
					}
				}
				await onProgress(partial, idx + 1, batches.count)
			}
		}

		let finalResult = translatedBatches.flatMap { $0 }
		storeInCache(key: cacheKey, value: finalResult)
		return finalResult
	}

	public func translateQuickText(_ text: String, targetLang: String) async throws -> String {
		let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !cleaned.isEmpty, targetLang != Self.langOff else { return cleaned }
		let raw = try await requestWithFailover(text: cleaned, targetLang: targetLang)
		let parsed = Self.parseGtxResponse(raw).trimmingCharacters(in: .whitespacesAndNewlines)
		return parsed.isEmpty ? cleaned : parsed
	}

	private func storeInCache(key: String, value: [String]) {
		cache[key] = value
		cacheOrder.removeAll { $0 == key }
		cacheOrder.append(key)
		while cacheOrder.count > maxCacheItems {
			let evicted = cacheOrder.removeFirst()
			cache.removeValue(forKey: evicted)
		}
	}

	private func requestWithFailover(text: String, targetLang: String) async throws -> String {
		var lastError: Error?
		for (endpoint, clientName) in Self.endpoints {
			do {
				var comps = URLComponents(string: endpoint)!
				comps.queryItems = [
					URLQueryItem(name: "client", value: clientName),
					URLQueryItem(name: "sl", value: "auto"),
					URLQueryItem(name: "tl", value: targetLang),
					URLQueryItem(name: "dt", value: "t"),
				]
				return try await HttpClient.shared.postForm(
					url: comps.url!.absoluteString,
					fields: [("q", text)]
				)
			} catch {
				lastError = error
			}
		}
		throw lastError ?? HttpClientError.emptyBody
	}

	public static func parseGtxResponse(_ rawJson: String) -> String {
		guard let data = rawJson.data(using: .utf8),
			  let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
			  let sentences = root.first as? [Any] else {
			return ""
		}
		var out = ""
		for item in sentences {
			guard let seg = item as? [Any],
				  let piece = seg.first as? String,
				  !piece.isEmpty,
				  piece != "null" else { continue }
			out.append(piece)
		}
		return out
	}

	public static func chunkParagraphs(
		_ paragraphs: [String],
		maxChars: Int = maxCharsPerBatch,
		maxCount: Int = maxParagraphsPerBatch
	) -> [[String]] {
		guard !paragraphs.isEmpty else { return [] }
		var result: [[String]] = []
		var current: [String] = []
		var currentChars = 0

		for p in paragraphs {
			let trimmed = p.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !trimmed.isEmpty else { continue }
			let activeMaxChars = (result.isEmpty && maxChars == maxCharsPerBatch) ? firstBatchMaxChars : maxChars
			let activeMaxCount = (result.isEmpty && maxCount == maxParagraphsPerBatch) ? firstBatchMaxParagraphs : maxCount

			if !current.isEmpty && (currentChars + trimmed.count > activeMaxChars || current.count >= activeMaxCount) {
				result.append(current)
				current = []
				currentChars = 0
			}
			current.append(trimmed)
			currentChars += trimmed.count + 2
		}
		if !current.isEmpty {
			result.append(current)
		}
		return result
	}

	public static func estimateReadingMinutes(_ paragraphs: [String], wordsPerMinute: Int = 220) -> Int {
		guard !paragraphs.isEmpty else { return 0 }
		var words = 0
		for p in paragraphs {
			words += p.split { $0.isWhitespace }.count
		}
		return max(1, (words + wordsPerMinute - 1) / wordsPerMinute)
	}

	private static func collapseWhitespace(_ input: String) -> String {
		input.components(separatedBy: .whitespacesAndNewlines)
			.filter { !$0.isEmpty }
			.joined(separator: " ")
	}
}
