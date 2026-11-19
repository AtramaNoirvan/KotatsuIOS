import Foundation

public struct CachedNovelChapter: Codable {
	public let chapterId: Int64
	public let title: String?
	public let paragraphs: [String]
	public var translations: [String: [String]]
	public let savedAt: Int64
}

public struct NovelCacheStats {
	public let chapterCount: Int
	public let totalBytes: Int64

	public var formattedSize: String {
		let kb = Double(totalBytes) / 1024.0
		if kb >= 1024.0 {
			return String(format: "%.1f MB", kb / 1024.0)
		} else if totalBytes >= 1024 {
			return String(format: "%.1f KB", kb)
		}
		return "\(totalBytes) B"
	}
}

public enum NovelGlossaryEngine {
	/// Single-pass longest-term-first glossary replacement so multi-word rules
	/// (e.g. "Senior Brother Lin") are never corrupted by shorter overlapping rules ("Lin").
	public static func apply(paragraphs: [String], rules: [GlossaryRule]) -> [String] {
		guard !paragraphs.isEmpty, !rules.isEmpty else { return paragraphs }
		let cleanedRules = rules.compactMap { r -> GlossaryRule? in
			let src = r.sourceTerm.trimmingCharacters(in: .whitespacesAndNewlines)
			let rep = r.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !src.isEmpty, !rep.isEmpty else { return nil }
			return GlossaryRule(sourceTerm: src, replacement: rep, ignoreCase: r.ignoreCase)
		}.sorted { $0.sourceTerm.count > $1.sourceTerm.count }

		guard !cleanedRules.isEmpty else { return paragraphs }

		let branches: [String] = cleanedRules.map { rule in
			let escaped = NSRegularExpression.escapedPattern(for: rule.sourceTerm)
			let isWordTerm = rule.sourceTerm.allSatisfy { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" || $0 == "'" }
				&& (rule.sourceTerm.first?.isLetter == true || rule.sourceTerm.first?.isNumber == true)
				&& (rule.sourceTerm.last?.isLetter == true || rule.sourceTerm.last?.isNumber == true)
			let body = isWordTerm ? "\\b\(escaped)\\b" : escaped
			return rule.ignoreCase ? "(?i:\(body))" : "(?-i:\(body))"
		}

		guard let regex = try? NSRegularExpression(pattern: branches.joined(separator: "|")) else {
			return paragraphs
		}

		return paragraphs.map { text in
			let nsText = text as NSString
			let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
			guard !matches.isEmpty else { return text }
			let mutable = NSMutableString(string: text)
			for match in matches.reversed() {
				let matchedStr = nsText.substring(with: match.range)
				if let rule = cleanedRules.first(where: { r in
					r.ignoreCase
						? matchedStr.caseInsensitiveCompare(r.sourceTerm) == .orderedSame
						: matchedStr == r.sourceTerm
				}) {
					mutable.replaceCharacters(in: match.range, with: rule.replacement)
				}
			}
			return mutable as String
		}
	}
}

public final class NovelExtrasStore {
	public static let shared = NovelExtrasStore()

	private let rootDir: URL
	private let fm = FileManager.default
	private let encoder = JSONEncoder()
	private let decoder = JSONDecoder()

	public init(rootDir: URL? = nil) {
		if let rootDir {
			self.rootDir = rootDir
		} else {
			let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
				?? fm.temporaryDirectory
			self.rootDir = appSupport.appendingPathComponent("novel_offline", isDirectory: true)
		}
		try? fm.createDirectory(at: self.rootDir, withIntermediateDirectories: true)
	}

	private func novelDir(mangaId: Int64) -> URL {
		let dir = rootDir.appendingPathComponent(String(mangaId), isDirectory: true)
		try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
		return dir
	}

	private func chapterURL(mangaId: Int64, chapterId: Int64) -> URL {
		novelDir(mangaId: mangaId).appendingPathComponent("ch_\(chapterId).json")
	}

	private func glossaryURL(mangaId: Int64) -> URL {
		novelDir(mangaId: mangaId).appendingPathComponent("glossary.json")
	}

	private func bookmarksURL(mangaId: Int64) -> URL {
		novelDir(mangaId: mangaId).appendingPathComponent("bookmarks.json")
	}

	// MARK: - Offline Chapters

	public func saveChapter(
		mangaId: Int64,
		chapterId: Int64,
		title: String?,
		paragraphs: [String],
		translatedLang: String? = nil,
		translatedParagraphs: [String]? = nil
	) {
		var translations = loadChapter(mangaId: mangaId, chapterId: chapterId)?.translations ?? [:]
		if let lang = translatedLang, lang != NovelTranslator.langOff, let trans = translatedParagraphs, !trans.isEmpty {
			translations[lang] = trans
		}
		let payload = CachedNovelChapter(
			chapterId: chapterId,
			title: title,
			paragraphs: paragraphs,
			translations: translations,
			savedAt: Int64(Date().timeIntervalSince1970 * 1000)
		)
		if let data = try? encoder.encode(payload) {
			try? data.write(to: chapterURL(mangaId: mangaId, chapterId: chapterId), options: .atomic)
		}
	}

	public func loadChapter(mangaId: Int64, chapterId: Int64) -> CachedNovelChapter? {
		let url = chapterURL(mangaId: mangaId, chapterId: chapterId)
		guard let data = try? Data(contentsOf: url) else { return nil }
		return try? decoder.decode(CachedNovelChapter.self, from: data)
	}

	public func cachedChapterIds(mangaId: Int64) -> Set<Int64> {
		let dir = novelDir(mangaId: mangaId)
		let files = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
		var ids = Set<Int64>()
		for name in files where name.hasPrefix("ch_") && name.hasSuffix(".json") {
			let raw = name.dropFirst(3).dropLast(5)
			if let val = Int64(raw) {
				ids.insert(val)
			}
		}
		return ids
	}

	public func cacheStats(mangaId: Int64) -> NovelCacheStats {
		let dir = novelDir(mangaId: mangaId)
		let urls = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
		var count = 0
		var bytes: Int64 = 0
		for u in urls where u.lastPathComponent.hasPrefix("ch_") && u.pathExtension == "json" {
			count += 1
			if let size = (try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
				bytes += Int64(size)
			}
		}
		return NovelCacheStats(chapterCount: count, totalBytes: bytes)
	}

	@discardableResult
	public func deleteNovelCache(mangaId: Int64) -> Int {
		let dir = novelDir(mangaId: mangaId)
		let urls = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
		var removed = 0
		for u in urls where u.lastPathComponent.hasPrefix("ch_") && u.pathExtension == "json" {
			if (try? fm.removeItem(at: u)) != nil {
				removed += 1
			}
		}
		return removed
	}

	// MARK: - Glossary

	public func loadGlossary(mangaId: Int64) -> [GlossaryRule] {
		guard let data = try? Data(contentsOf: glossaryURL(mangaId: mangaId)) else { return [] }
		return (try? decoder.decode([GlossaryRule].self, from: data)) ?? []
	}

	@discardableResult
	public func upsertGlossaryRule(mangaId: Int64, rule: GlossaryRule) -> [GlossaryRule] {
		let src = rule.sourceTerm.trimmingCharacters(in: .whitespacesAndNewlines)
		let rep = rule.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !src.isEmpty, !rep.isEmpty else { return loadGlossary(mangaId: mangaId) }
		var list = loadGlossary(mangaId: mangaId).filter {
			$0.sourceTerm.caseInsensitiveCompare(src) != .orderedSame
		}
		list.append(GlossaryRule(sourceTerm: src, replacement: rep, ignoreCase: rule.ignoreCase))
		if let data = try? encoder.encode(list) {
			try? data.write(to: glossaryURL(mangaId: mangaId), options: .atomic)
		}
		return list
	}

	@discardableResult
	public func removeGlossaryRule(mangaId: Int64, sourceTerm: String) -> [GlossaryRule] {
		let list = loadGlossary(mangaId: mangaId).filter {
			$0.sourceTerm.caseInsensitiveCompare(sourceTerm) != .orderedSame
		}
		if let data = try? encoder.encode(list) {
			try? data.write(to: glossaryURL(mangaId: mangaId), options: .atomic)
		}
		return list
	}

	// MARK: - Bookmarks

	public func loadBookmarks(mangaId: Int64) -> [NovelBookmark] {
		guard let data = try? Data(contentsOf: bookmarksURL(mangaId: mangaId)) else { return [] }
		return ((try? decoder.decode([NovelBookmark].self, from: data)) ?? [])
			.sorted { $0.createdAt > $1.createdAt }
	}

	@discardableResult
	public func addBookmark(mangaId: Int64, bookmark: NovelBookmark) -> [NovelBookmark] {
		var list = loadBookmarks(mangaId: mangaId).filter { $0.id != bookmark.id }
		list.insert(bookmark, at: 0)
		if let data = try? encoder.encode(list) {
			try? data.write(to: bookmarksURL(mangaId: mangaId), options: .atomic)
		}
		return list
	}

	@discardableResult
	public func removeBookmark(mangaId: Int64, bookmarkId: Int64) -> [NovelBookmark] {
		let list = loadBookmarks(mangaId: mangaId).filter { $0.id != bookmarkId }
		if let data = try? encoder.encode(list) {
			try? data.write(to: bookmarksURL(mangaId: mangaId), options: .atomic)
		}
		return list
	}
}
