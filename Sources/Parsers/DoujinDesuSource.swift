import Foundation

public enum DoujinDesuDecoder {
	private static let encField = "_enc_resp_"
	// shortcut: client-side salt mirrors doujin.desu.xxx frontend bundle; update if site rotates salt.
	private static let encSalt = "doujindesu-scrapers-cannot-read-this-super-secret-salt-2026-v2"
	private static let encPeriodMs: Int64 = 3_600_000

	public static func generateHourlyKey(slot: Int64) -> [UInt8] {
		let seed = "\(encSalt)_\(slot)"
		var hash: Int32 = 0
		for unit in seed.utf16 {
			hash = ((hash &<< 5) &- hash) &+ Int32(unit)
		}
		let absVal = abs(Int64(hash))
		var state: Int64 = absVal == 0 ? 123_456_789 : absVal
		var key: [UInt8] = []
		key.reserveCapacity(32)
		for _ in 0..<32 {
			state = (state &* 1_664_525 &+ 1_013_904_223) % 4_294_967_296
			if state < 0 { state += 4_294_967_296 }
			let code = UInt8(33 + (state % 93))
			key.append(code)
		}
		return key
	}

	public static func decodeResponse(raw: String, nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> String? {
		let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return nil }
		guard trimmed.hasPrefix("{") else { return trimmed }
		guard let rawData = trimmed.data(using: .utf8),
			  let obj = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any] else {
			return nil
		}
		guard let encryptedHex = obj[encField] as? String, !encryptedHex.isEmpty else {
			return trimmed
		}
		guard let rawBytes = hexToBytes(encryptedHex) else { return nil }
		let baseSlot = nowMs / encPeriodMs
		for slot in [baseSlot, baseSlot - 1, baseSlot + 1] {
			if let decoded = decodeWithSlot(rawBytes: rawBytes, slot: slot) {
				let clean = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
				if (clean.hasPrefix("{") || clean.hasPrefix("[")),
				   let checkData = clean.data(using: .utf8),
				   (try? JSONSerialization.jsonObject(with: checkData)) != nil {
					return clean
				}
			}
		}
		return nil
	}

	public static func percentDecodeUtf8(_ bytes: [UInt8]) -> String? {
		var out: [UInt8] = []
		out.reserveCapacity(bytes.count)
		var i = 0
		while i < bytes.count {
			if bytes[i] == 0x25 { // '%'
				guard i + 2 < bytes.count,
					  let hi = hexDigit(bytes[i + 1]),
					  let lo = hexDigit(bytes[i + 2]) else {
					return nil
				}
				out.append((hi << 4) | lo)
				i += 3
			} else {
				out.append(bytes[i])
				i += 1
			}
		}
		return String(bytes: out, encoding: .utf8)
	}

	private static func decodeWithSlot(rawBytes: [UInt8], slot: Int64) -> String? {
		let key = generateHourlyKey(slot: slot)
		var acc: Int = 42
		var decodedBytes: [UInt8] = []
		decodedBytes.reserveCapacity(rawBytes.count)
		for i in 0..<rawBytes.count {
			let b = Int(rawBytes[i])
			let k = Int(key[i % 32])
			let val = (b ^ k ^ (i * 13) ^ acc) & 0xFF
			acc = (acc + b) & 0xFF
			decodedBytes.append(UInt8(val))
		}
		return percentDecodeUtf8(decodedBytes)
	}

	private static func hexToBytes(_ hex: String) -> [UInt8]? {
		let utf8 = Array(hex.utf8)
		guard !utf8.isEmpty, utf8.count % 2 == 0 else { return nil }
		var result: [UInt8] = []
		result.reserveCapacity(utf8.count / 2)
		var i = 0
		while i < utf8.count {
			guard let hi = hexDigit(utf8[i]), let lo = hexDigit(utf8[i + 1]) else { return nil }
			result.append((hi << 4) | lo)
			i += 2
		}
		return result
	}

	private static func hexDigit(_ c: UInt8) -> UInt8? {
		switch c {
		case 48...57: return c - 48
		case 97...102: return c - 97 + 10
		case 65...70: return c - 65 + 10
		default: return nil
		}
	}
}

public struct DoujinDesuSource: ContentSource {
	public let sourceID: CatalogSourceID = .doujinDesu
	private let domain = "doujin.desu.xxx"

	public init() {}

	public func fetchList(page: Int, query: String, sort: SortMode) async throws -> [MangaItem] {
		let limit = 24
		let offset = max(0, page - 1) * limit
		let sortParam = sort == .popular ? "views" : "latest_chapter"
		var comps = URLComponents(string: "https://\(domain)/api/manga")!
		var qItems = [
			URLQueryItem(name: "limit", value: "\(limit)"),
			URLQueryItem(name: "offset", value: "\(offset)"),
			URLQueryItem(name: "sort", value: sortParam),
		]
		let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
		if !cleanQuery.isEmpty {
			qItems.append(URLQueryItem(name: "search", value: cleanQuery))
		}
		comps.queryItems = qItems
		let raw = try await HttpClient.shared.getString(
			url: comps.url!.absoluteString,
			headers: sourceID.defaultHeaders
		)
		guard let decoded = DoujinDesuDecoder.decodeResponse(raw: raw),
			  let data = decoded.data(using: .utf8),
			  let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
			return []
		}
		return array.compactMap { parseItem($0) }
	}

	public func fetchDetails(manga: MangaItem) async throws -> MangaItem {
		let slug = extractSlug(manga.url)
		let url = "https://\(domain)/api/manga/\(slug)"
		let raw = try await HttpClient.shared.getString(url: url, headers: sourceID.defaultHeaders)
		guard let decoded = DoujinDesuDecoder.decodeResponse(raw: raw),
			  let data = decoded.data(using: .utf8),
			  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			return manga
		}

		var authors: [String] = []
		if let a = (obj["author"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty {
			authors.append(a)
		}
		if let ar = (obj["artist"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !ar.isEmpty, !authors.contains(ar) {
			authors.append(ar)
		}

		var chapters: [ChapterItem] = []
		if let rawChapters = obj["chapters"] as? [[String: Any]] {
			let reversed = Array(rawChapters.reversed())
			for (idx, chObj) in reversed.enumerated() {
				guard let idStr = stringValue(chObj["id"]), !idStr.isEmpty else { continue }
				let chUrl = "/api/chapters/\(idStr)"
				let num = floatValue(chObj["chapter_number"]) ?? Float(idx + 1)
				let title = (chObj["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
					.nonEmptyOr("Chapter \(num.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(num)) : String(num))")
					?? "Chapter \(idx + 1)"
				chapters.append(
					ChapterItem(
						id: KotatsuUid.generate(sourceName: sourceID.rawValue, url: chUrl),
						title: title,
						number: num,
						url: chUrl,
						sourceName: sourceID.rawValue
					)
				)
			}
		}

		var updated = manga
		if let title = (obj["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
			updated.title = title
		}
		updated.coverUrl = (obj["cover_url"] as? String) ?? manga.coverUrl
		updated.description = (obj["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
		updated.authors = authors
		updated.tags = parseTags(obj["manga_genres"])
		updated.state = obj["status"] as? String
		updated.chapters = chapters
		return updated
	}

	public func fetchChapterPayload(chapter: ChapterItem) async throws -> ChapterPayload {
		let chapterId = chapter.url.split(separator: "/").last.map(String.init) ?? ""
		let url = "https://\(domain)/api/chapters/\(chapterId)"
		let raw = try await HttpClient.shared.getString(url: url, headers: sourceID.defaultHeaders)
		guard let decoded = DoujinDesuDecoder.decodeResponse(raw: raw),
			  let data = decoded.data(using: .utf8),
			  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
			  let urls = obj["content_urls"] as? [String] else {
			return .comicPages([])
		}
		let pages = urls.enumerated().compactMap { idx, rawUrl -> ComicPageItem? in
			let clean = rawUrl.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !clean.isEmpty else { return nil }
			return ComicPageItem(id: "\(chapter.id)_\(idx)", url: clean, headers: sourceID.defaultHeaders)
		}
		return .comicPages(pages)
	}

	private func parseItem(_ obj: [String: Any]) -> MangaItem? {
		guard let slug = (obj["slug"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !slug.isEmpty,
			  let title = (obj["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
			return nil
		}
		let relUrl = "/manga/\(slug)"
		return MangaItem(
			id: KotatsuUid.generate(sourceName: sourceID.rawValue, url: relUrl),
			title: title,
			url: relUrl,
			publicUrl: "https://\(domain)/manga/\(slug)",
			coverUrl: obj["cover_url"] as? String,
			tags: parseTags(obj["manga_genres"]),
			state: obj["status"] as? String,
			isNsfw: true,
			sourceName: sourceID.rawValue
		)
	}

	private func parseTags(_ raw: Any?) -> [String] {
		guard let arr = raw as? [[String: Any]] else { return [] }
		return arr.compactMap { entry in
			let g = (entry["genres"] as? [String: Any]) ?? entry
			let name = (g["name"] as? String)?
				.trimmingCharacters(in: CharacterSet(charactersIn: "\" \n\t"))
			return (name?.isEmpty == false) ? name : nil
		}
	}

	private func extractSlug(_ url: String) -> String {
		let trimmed = url.components(separatedBy: "?").first ?? url
		if let range = trimmed.range(of: "/manga/") {
			return String(trimmed[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		}
		return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
	}

	private func stringValue(_ raw: Any?) -> String? {
		if let s = raw as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
		if let n = raw as? NSNumber { return n.stringValue }
		return nil
	}

	private func floatValue(_ raw: Any?) -> Float? {
		if let n = raw as? NSNumber { return n.floatValue }
		if let s = raw as? String { return Float(s) }
		return nil
	}
}

private extension String {
	func nonEmptyOr(_ fallback: String) -> String {
		isEmpty ? fallback : self
	}
}
