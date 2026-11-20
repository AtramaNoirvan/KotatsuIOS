import Foundation
import SwiftSoup

private enum SourceJSON {
	static func object(from raw: String) -> [String: Any]? {
		guard let data = raw.data(using: .utf8) else { return nil }
		return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
	}

	static func string(_ value: Any?) -> String? {
		if let s = value as? String {
			let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
			return t.isEmpty ? nil : t
		}
		if let n = value as? NSNumber {
			return n.stringValue
		}
		return nil
	}

	static func float(_ value: Any?, default fallback: Float = 0) -> Float {
		if let n = value as? NSNumber {
			return n.floatValue
		}
		if let s = value as? String, let parsed = Float(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
			return parsed
		}
		return fallback
	}

	static func formatNumber(_ number: Float) -> String {
		if number.rounded(.towardZero) == number {
			return String(Int(number))
		}
		return String(format: "%g", number)
	}

	static func stripHost(_ raw: String, domain: String) -> String {
		let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
		if trimmed.hasPrefix("/") {
			return trimmed
		}
		for scheme in ["https://", "http://"] {
			let prefix = "\(scheme)\(domain)"
			if trimmed.lowercased().hasPrefix(prefix.lowercased()) {
				let rest = String(trimmed.dropFirst(prefix.count))
				return rest.hasPrefix("/") ? rest : "/\(rest)"
			}
		}
		return ParserUtils.toRelativeUrl(trimmed, domain: domain)
	}
}

public struct ShinigamiSource: ContentSource {
	public let sourceID: CatalogSourceID = .shinigami
	private let domain = "s1.shinigami.mx"
	private let apiBase = "https://api.shinigami.io/v1"
	private let cdnBase = "https://cdn.shinigami.gg"

	public init() {}

	private var requestHeaders: [String: String] {
		[
			"Referer": "https://\(domain)/",
			"sec-fetch-dest": "empty",
		]
	}

	public func fetchList(page: Int, query: String, sort: SortMode) async throws -> [MangaItem] {
		let limit = 24
		let offset = max(0, page - 1) * limit
		var comps = URLComponents(string: "\(apiBase)/manga/list")!
		var items: [URLQueryItem] = [
			URLQueryItem(name: "limit", value: "\(limit)"),
			URLQueryItem(name: "offset", value: "\(offset)"),
			URLQueryItem(name: "sort", value: sort == .popular ? "popularity" : "latest"),
			URLQueryItem(name: "sort_order", value: "desc"),
		]
		let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
		if !cleanQuery.isEmpty {
			items.append(URLQueryItem(name: "q", value: cleanQuery))
		}
		comps.queryItems = items
		let raw = try await HttpClient.shared.getString(url: comps.url!.absoluteString, headers: requestHeaders)
		return Self.parseListJSON(raw, domain: domain)
	}

	public func fetchDetails(manga: MangaItem) async throws -> MangaItem {
		let rawPath = manga.url.components(separatedBy: "?").first ?? manga.url
		let mangaId = rawPath.split(separator: "/").last.map(String.init) ?? ""
		guard !mangaId.isEmpty else { return manga }

		let detailRaw = try await HttpClient.shared.getString(
			url: "\(apiBase)/manga/detail/\(mangaId)",
			headers: requestHeaders
		)
		var updated = Self.parseDetailJSON(detailRaw, base: manga, domain: domain)

		var chapters: [ChapterItem] = []
		var seenIds = Set<Int64>()
		var cursor: String?
		for _ in 0..<25 {
			var comps = URLComponents(string: "\(apiBase)/chapter/\(mangaId)/list")!
			var qItems = [
				URLQueryItem(name: "limit", value: "100"),
				URLQueryItem(name: "sort_by", value: "chapter_number"),
				URLQueryItem(name: "sort_order", value: "asc"),
			]
			if let cursor, !cursor.isEmpty {
				qItems.append(URLQueryItem(name: "cursor", value: cursor))
			}
			comps.queryItems = qItems
			let raw = try await HttpClient.shared.getString(url: comps.url!.absoluteString, headers: requestHeaders)
			let pageResult = Self.parseChaptersJSON(raw, seenIds: &seenIds)
			chapters.append(contentsOf: pageResult.chapters)
			guard let next = pageResult.nextCursor, !next.isEmpty else { break }
			cursor = next
		}
		updated.chapters = chapters
		return updated
	}

	public func fetchChapterPayload(chapter: ChapterItem) async throws -> ChapterPayload {
		let rawPath = chapter.url.components(separatedBy: "?").first ?? chapter.url
		let chapterId = rawPath.split(separator: "/").last.map(String.init) ?? ""
		guard !chapterId.isEmpty else { return .comicPages([]) }

		let raw = try await HttpClient.shared.getString(
			url: "\(apiBase)/chapter/detail/\(chapterId)",
			headers: requestHeaders
		)
		let urls = Self.parsePagesJSON(raw, fallbackCdn: cdnBase)
		let pageHeaders = ["Referer": "https://\(domain)/"]
		return .comicPages(urls.enumerated().map { idx, url in
			ComicPageItem(id: "\(chapter.id)_\(idx)", url: url, headers: pageHeaders)
		})
	}

	public static func parseListJSON(_ raw: String, domain: String = "s1.shinigami.mx") -> [MangaItem] {
		guard let root = SourceJSON.object(from: raw),
			  let data = root["data"] as? [[String: Any]] else {
			return []
		}
		return data.compactMap { parseMangaObject($0, domain: domain) }
	}

	public static func parseDetailJSON(_ raw: String, base: MangaItem, domain: String = "s1.shinigami.mx") -> MangaItem {
		guard let root = SourceJSON.object(from: raw),
			  let jo = root["data"] as? [String: Any],
			  let parsed = parseMangaObject(jo, domain: domain) else {
			return base
		}
		var updated = base
		updated.title = parsed.title.isEmpty ? base.title : parsed.title
		updated.coverUrl = parsed.coverUrl ?? base.coverUrl
		updated.description = parsed.description ?? base.description
		updated.authors = parsed.authors.isEmpty ? base.authors : parsed.authors
		updated.tags = parsed.tags.isEmpty ? base.tags : parsed.tags
		updated.state = parsed.state ?? base.state
		return updated
	}

	public static func parseChaptersJSON(
		_ raw: String,
		seenIds: inout Set<Int64>
	) -> (chapters: [ChapterItem], nextCursor: String?) {
		guard let root = SourceJSON.object(from: raw),
			  let data = root["data"] as? [[String: Any]] else {
			return ([], nil)
		}
		var items: [ChapterItem] = []
		for jo in data {
			guard let chapterId = SourceJSON.string(jo["chapter_id"]) else { continue }
			// Match Android Shinigami.kt generateUid(chapterId) for Gist history compatibility.
			let uid = KotatsuUid.generate(sourceName: CatalogSourceID.shinigami.rawValue, url: chapterId)
			guard seenIds.insert(uid).inserted else { continue }
			let num = SourceJSON.float(jo["chapter_number"], default: 0)
			let rawTitle = SourceJSON.string(jo["chapter_title"])
			let title = rawTitle ?? "Chapter \(SourceJSON.formatNumber(num))"
			items.append(
				ChapterItem(
					id: uid,
					title: title,
					number: num,
					url: "chapter/detail/\(chapterId)",
					sourceName: CatalogSourceID.shinigami.rawValue
				)
			)
		}
		let meta = root["meta"] as? [String: Any]
		let hasNext = (meta?["has_next"] as? Bool) == true
		let nextCursor = hasNext ? SourceJSON.string(meta?["next_cursor"]) : nil
		return (items, data.isEmpty ? nil : nextCursor)
	}

	public static func parsePagesJSON(_ raw: String, fallbackCdn: String = "https://cdn.shinigami.gg") -> [String] {
		guard let root = SourceJSON.object(from: raw),
			  let data = root["data"] as? [String: Any],
			  let chapter = data["chapter"] as? [String: Any],
			  let files = chapter["data"] as? [String] else {
			return []
		}
		let baseUrl = (SourceJSON.string(data["base_url"]) ?? fallbackCdn)
			.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		let basePath = (SourceJSON.string(chapter["path"]) ?? "")
			.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		return files.compactMap { file in
			let clean = file.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
			guard !clean.isEmpty else { return nil }
			return basePath.isEmpty ? "\(baseUrl)/\(clean)" : "\(baseUrl)/\(basePath)/\(clean)"
		}
	}

	private static func parseMangaObject(_ jo: [String: Any], domain: String) -> MangaItem? {
		guard let mangaId = SourceJSON.string(jo["manga_id"]),
			  let title = SourceJSON.string(jo["title"]) else {
			return nil
		}
		let taxonomy = jo["taxonomy"] as? [String: Any]
		let authors = (taxonomy?["Author"] as? [[String: Any]] ?? [])
			.compactMap { SourceJSON.string($0["name"]) }
		let tags = (taxonomy?["Genre"] as? [[String: Any]] ?? [])
			.compactMap { SourceJSON.string($0["name"]) }
		let statusCode = (jo["status"] as? NSNumber)?.intValue ?? 0
		let state: String?
		switch statusCode {
		case 1: state = "ONGOING"
		case 2: state = "FINISHED"
		case 3: state = "PAUSED"
		default: state = nil
		}
		let cover = SourceJSON.string(jo["cover_image_url"]) ?? SourceJSON.string(jo["cover_portrait_url"])
		return MangaItem(
			// Match Android Shinigami.kt generateUid(id) for Gist sync continuity.
			id: KotatsuUid.generate(sourceName: CatalogSourceID.shinigami.rawValue, url: mangaId),
			title: title,
			url: "/manga/detail/\(mangaId)",
			publicUrl: "https://\(domain)/series/\(mangaId)",
			coverUrl: cover,
			description: SourceJSON.string(jo["description"]),
			authors: authors,
			tags: tags,
			state: state,
			isNsfw: false,
			sourceName: CatalogSourceID.shinigami.rawValue
		)
	}
}

private actor NatsuNonceStore {
	static let shared = NatsuNonceStore()

	private var cache: [String: (nonce: String, expiresAt: Date)] = [:]

	func cachedNonce(for domain: String) -> String? {
		guard let entry = cache[domain], Date() < entry.expiresAt else { return nil }
		return entry.nonce
	}

	func fetchNonce(domain: String, forceRefresh: Bool, failedNonce: String? = nil) async throws -> String {
		if !forceRefresh, let cached = cachedNonce(for: domain) {
			return cached
		}
		if forceRefresh, let entry = cache[domain], Date() < entry.expiresAt,
		   let failedNonce, entry.nonce != failedNonce {
			return entry.nonce
		}
		let html = try await HttpClient.shared.getString(
			url: "https://\(domain)/wp-admin/admin-ajax.php?type=search_form&action=get_nonce",
			headers: ["Referer": "https://\(domain)/"]
		)
		let doc = try SwiftSoup.parse(html)
		let nonce = (try? doc.select("input[name=search_nonce]").first()?.attr("value"))?
			.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		if !nonce.isEmpty {
			cache[domain] = (nonce, Date().addingTimeInterval(25 * 60))
		} else {
			cache[domain] = nil
		}
		return nonce
	}
}

public struct NatsuWpSource: ContentSource {
	public let sourceID: CatalogSourceID

	public init(sourceID: CatalogSourceID) {
		self.sourceID = sourceID
	}

	private var domain: String { sourceID.defaultDomain }

	public func fetchList(page: Int, query: String, sort: SortMode) async throws -> [MangaItem] {
		var fields: [(String, String)] = [
			("action", "advanced_search"),
			("page", "\(page)"),
			("orderby", sort == .popular ? "popular" : "updated"),
		]
		let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
		if !cleanQuery.isEmpty {
			fields.append(("query", cleanQuery))
		}
		let html = try await postSearchForm(baseFields: fields)
		let doc = try SwiftSoup.parse(html)
		var items: [MangaItem] = []
		var seen = Set<String>()
		for card in try doc.select("div.flex.rounded-lg.overflow-hidden").array() {
			guard let coverLink = try card.select("a[href*='/manga/']").first(),
				  let rawHref = try? coverLink.attr("href").trimmingCharacters(in: .whitespacesAndNewlines),
				  !rawHref.isEmpty else { continue }
			let relUrl = SourceJSON.stripHost(rawHref, domain: domain)
			guard seen.insert(relUrl).inserted else { continue }
			let titleLink = (try? card.select("a[href*='/manga/']:not(:has(img))").first()) ?? coverLink
			let title = (try? titleLink.text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
			guard !title.isEmpty else { continue }
			let cover = ParserUtils.imageSrc(try card.select("img").first(), domain: domain)
			items.append(
				MangaItem(
					id: KotatsuUid.generate(sourceName: sourceID.rawValue, url: relUrl),
					title: title,
					url: relUrl,
					publicUrl: ParserUtils.toAbsoluteUrl(relUrl, domain: domain),
					coverUrl: cover,
					isNsfw: false,
					sourceName: sourceID.rawValue
				)
			)
		}
		return items
	}

	public func fetchDetails(manga: MangaItem) async throws -> MangaItem {
		let fullUrl = ParserUtils.toAbsoluteUrl(manga.url, domain: domain)
		let html = try await HttpClient.shared.getString(url: fullUrl, headers: sourceID.defaultHeaders)
		let doc = try SwiftSoup.parse(html)

		let title = (try? doc.select("h1[itemprop=name]").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines))
			.flatMap { $0.isEmpty ? nil : $0 } ?? manga.title
		let desc = (try? doc.select("div[itemprop=description]").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines))
			?? manga.description
		let cover = ParserUtils.imageSrc(try? doc.select("div[itemprop=image] img").first(), domain: domain)
			?? manga.coverUrl
		let tags = (try? doc.select("a[itemprop=genre]").array().compactMap { el -> String? in
			let t = try? el.text().trimmingCharacters(in: .whitespacesAndNewlines)
			return (t?.isEmpty == false) ? t : nil
		}) ?? []

		var metaFields: [String: String] = [:]
		for row in (try? doc.select("div.space-y-2 > div:has(h4)").array()) ?? [] {
			guard let label = (try? row.select("h4").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines).lowercased()),
				  let val = (try? row.select("p").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines)),
				  !val.isEmpty, val != "-" else { continue }
			metaFields[label] = val
		}
		var authors: [String] = []
		for key in ["author", "artist"] {
			if let v = metaFields[key], !authors.contains(v) {
				authors.append(v)
			}
		}

		let rawHx = (try? doc.select("[hx-get*='manga_id=']").first()?.attr("hx-get")) ?? ""
		let wpMangaId = rawHx
			.components(separatedBy: "manga_id=").dropFirst().first?
			.components(separatedBy: "&").first?
			.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

		var chaptersDesc: [ChapterItem] = []
		var seenUrls = Set<String>()
		if !wpMangaId.isEmpty {
			for page in 1...50 {
				let chHtml = try await HttpClient.shared.getString(
					url: "https://\(domain)/wp-admin/admin-ajax.php?manga_id=\(wpMangaId)&page=\(page)&action=chapter_list",
					headers: ["Referer": fullUrl, "hx-request": "true"]
				)
				let chDoc = try SwiftSoup.parse(chHtml)
				let rows = try chDoc.select("div#chapter-list > div[data-chapter-number]").array()
				if rows.isEmpty { break }

				var addedOnPage = false
				for row in rows {
					guard let a = try row.select("a[href]").first(),
						  let rawHref = try? a.attr("href"), !rawHref.isEmpty else { continue }
					let chUrl = SourceJSON.stripHost(rawHref, domain: domain)
					guard seenUrls.insert(chUrl).inserted else { continue }
					let num = Float((try? row.attr("data-chapter-number")) ?? "") ?? 0
					let rawTitle = (try? row.select("div.font-medium span, div.font-medium").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines))
						.flatMap { $0.isEmpty ? nil : $0 }
						?? (try? a.text().trimmingCharacters(in: .whitespacesAndNewlines))
						?? "Chapter \(SourceJSON.formatNumber(num))"
					chaptersDesc.append(
						ChapterItem(
							id: KotatsuUid.generate(sourceName: sourceID.rawValue, url: chUrl),
							title: rawTitle,
							number: num,
							url: chUrl,
							sourceName: sourceID.rawValue
						)
					)
					addedOnPage = true
				}
				let hasMore = (try? chDoc.select("[hx-get*='action=chapter_list'], [hx-get*='page='], a[href*='page='], button[data-page]").first()) != nil
				if !addedOnPage || !hasMore { break }
			}
		}

		var updated = manga
		updated.title = title
		updated.coverUrl = cover
		updated.description = desc
		updated.authors = authors.isEmpty ? manga.authors : authors
		updated.tags = tags.isEmpty ? manga.tags : tags
		updated.state = Self.parseStatus(metaFields["status"]) ?? manga.state
		updated.chapters = Array(chaptersDesc.reversed())
		return updated
	}

	public func fetchChapterPayload(chapter: ChapterItem) async throws -> ChapterPayload {
		let fullUrl = ParserUtils.toAbsoluteUrl(chapter.url, domain: domain)
		let html = try await HttpClient.shared.getString(url: fullUrl, headers: sourceID.defaultHeaders)
		let doc = try SwiftSoup.parse(html)
		var imgs = try doc.select("section[data-image-data] > img").array()
		if imgs.isEmpty {
			imgs = try doc.select("main section section > img").array()
		}
		var pages: [ComicPageItem] = []
		for (idx, img) in imgs.enumerated() {
			guard let src = ParserUtils.imageSrc(img, domain: domain) else { continue }
			pages.append(ComicPageItem(id: "\(chapter.id)_\(idx)", url: src, headers: ["Referer": fullUrl]))
		}
		return .comicPages(pages)
	}

	private func postSearchForm(baseFields: [(String, String)]) async throws -> String {
		let initialNonce = (try? await NatsuNonceStore.shared.fetchNonce(domain: domain, forceRefresh: false)) ?? ""
		let send = { (nonce: String) -> [(String, String)] in
			nonce.isEmpty ? baseFields : baseFields + [("nonce", nonce)]
		}
		let url = "https://\(domain)/wp-admin/admin-ajax.php"
		let headers = ["Referer": "https://\(domain)/"]
		do {
			let body = try await HttpClient.shared.postForm(url: url, fields: send(initialNonce), headers: headers)
			let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
			if trimmed == "0" || trimmed == "-1" {
				let refreshed = try await NatsuNonceStore.shared.fetchNonce(
					domain: domain,
					forceRefresh: true,
					failedNonce: initialNonce
				)
				if !refreshed.isEmpty, refreshed != initialNonce {
					return try await HttpClient.shared.postForm(url: url, fields: send(refreshed), headers: headers)
				}
			}
			return body
		} catch HttpClientError.httpStatus(let code, _) where code == 400 || code == 403 {
			let refreshed = try await NatsuNonceStore.shared.fetchNonce(
				domain: domain,
				forceRefresh: true,
				failedNonce: initialNonce
			)
			guard !refreshed.isEmpty, refreshed != initialNonce else {
				throw HttpClientError.httpStatus(code, url)
			}
			return try await HttpClient.shared.postForm(url: url, fields: send(refreshed), headers: headers)
		}
	}

	private static func parseStatus(_ raw: String?) -> String? {
		guard let lower = raw?.lowercased(), !lower.isEmpty else { return nil }
		if lower.contains("ongoing") || lower.contains("berjalan") { return "ONGOING" }
		if lower.contains("completed") || lower.contains("tamat") { return "FINISHED" }
		if lower.contains("hiatus") { return "PAUSED" }
		if lower.contains("cancel") || lower.contains("dropped") { return "ABANDONED" }
		return nil
	}
}

public struct IkiruSource: ContentSource {
	public let sourceID: CatalogSourceID = .ikiru
	private let domain = "11.ikiru.wtf"

	public init() {}

	public func fetchList(page: Int, query: String, sort: SortMode) async throws -> [MangaItem] {
		let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
		if (1...2).contains(cleanQuery.count) {
			if page > 1 { return [] }
			let encoded = HttpClient.formEncode(cleanQuery)
			let raw = try await HttpClient.shared.getString(
				url: "https://\(domain)/api/public/quick-search?query=\(encoded)",
				headers: sourceID.defaultHeaders
			)
			guard let root = SourceJSON.object(from: raw),
				  let arr = root["data"] as? [[String: Any]] else {
				return []
			}
			return arr.compactMap { parseMangaItem($0) }
		}

		var comps = URLComponents(string: "https://\(domain)/api/public/library/search")!
		var qItems = [
			URLQueryItem(name: "page", value: "\(page)"),
			URLQueryItem(name: "sortBy", value: sort == .popular ? "popular" : "updated"),
			URLQueryItem(name: "sort", value: "desc"),
		]
		if cleanQuery.count >= 3 {
			qItems.append(URLQueryItem(name: "query", value: cleanQuery))
		}
		comps.queryItems = qItems
		let raw = try await HttpClient.shared.getString(
			url: comps.url!.absoluteString,
			headers: sourceID.defaultHeaders
		)
		guard let root = SourceJSON.object(from: raw),
			  let data = root["data"] as? [String: Any],
			  let arr = data["mangas"] as? [[String: Any]] else {
			return []
		}
		return arr.compactMap { parseMangaItem($0) }
	}

	public func fetchDetails(manga: MangaItem) async throws -> MangaItem {
		let rawPath = manga.url.components(separatedBy: "?").first ?? manga.url
		let slug = rawPath.split(separator: "/").last.map(String.init) ?? ""
		guard !slug.isEmpty else { return manga }
		let encodedSlug = HttpClient.formEncode(slug)

		let detRaw = try await HttpClient.shared.getString(
			url: "https://\(domain)/api/public/manga/\(encodedSlug)",
			headers: sourceID.defaultHeaders
		)
		var updated = manga
		if let root = SourceJSON.object(from: detRaw),
		   let data = root["data"] as? [String: Any] {
			let metadata = data["metadata"] as? [String: Any]
			updated.title = SourceJSON.string(data["title"]) ?? manga.title
			updated.coverUrl = SourceJSON.string(data["featuredImage"]) ?? manga.coverUrl
			if let descHtml = SourceJSON.string(data["description"]),
			   let parsedDesc = try? SwiftSoup.parseBodyFragment(descHtml).text().trimmingCharacters(in: .whitespacesAndNewlines),
			   !parsedDesc.isEmpty {
				updated.description = parsedDesc
			}
			if let rawState = SourceJSON.string(data["status"])?.uppercased() {
				switch rawState {
				case "ONGOING": updated.state = "ONGOING"
				case "COMPLETED": updated.state = "FINISHED"
				case "HIATUS": updated.state = "PAUSED"
				case "CANCELLED": updated.state = "ABANDONED"
				default: updated.state = rawState
				}
			}
			var authors: [String] = []
			for key in ["author", "artist"] {
				for obj in (metadata?[key] as? [[String: Any]] ?? []) {
					if let n = SourceJSON.string(obj["name"]), !authors.contains(n) {
						authors.append(n)
					}
				}
			}
			if !authors.isEmpty { updated.authors = authors }
			let genres = (metadata?["genre"] as? [[String: Any]] ?? [])
				.compactMap { SourceJSON.string($0["name"]) }
			if !genres.isEmpty { updated.tags = genres }
			if let adult = data["isAdult"] as? Bool { updated.isNsfw = adult }
		}

		let chRaw = try await HttpClient.shared.getString(
			url: "https://\(domain)/api/public/manga/\(encodedSlug)/chapter",
			headers: sourceID.defaultHeaders
		)
		if let root = SourceJSON.object(from: chRaw),
		   let data = root["data"] as? [String: Any],
		   let arr = data["chapters"] as? [[String: Any]] {
			var chapters: [ChapterItem] = []
			for ch in arr.reversed() {
				let num = SourceJSON.float(ch["number"], default: -1)
				guard num >= 0 else { continue }
				let numStr = SourceJSON.formatNumber(num)
				let chUrl = "/manga/\(slug)/chapter-\(numStr)"
				let title = SourceJSON.string(ch["title"]) ?? "Chapter \(numStr)"
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
			updated.chapters = chapters
		}
		return updated
	}

	public func fetchChapterPayload(chapter: ChapterItem) async throws -> ChapterPayload {
		let clean = (chapter.url.components(separatedBy: "?").first ?? chapter.url)
			.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		let parts = clean.split(separator: "/").map(String.init)
		guard let mangaIdx = parts.firstIndex(of: "manga"),
			  mangaIdx + 1 < parts.count,
			  let lastSeg = parts.last else {
			return .comicPages([])
		}
		let mangaSlug = parts[mangaIdx + 1]
		let numStr = lastSeg.hasPrefix("chapter-") ? String(lastSeg.dropFirst("chapter-".count)) : lastSeg
		let raw = try await HttpClient.shared.getString(
			url: "https://\(domain)/api/public/chapter/\(HttpClient.formEncode(numStr))?mangaSlug=\(HttpClient.formEncode(mangaSlug))",
			headers: sourceID.defaultHeaders
		)
		guard let root = SourceJSON.object(from: raw),
			  let data = root["data"] as? [String: Any],
			  let medias = data["medias"] as? [[String: Any]] else {
			return .comicPages([])
		}
		let pageHeaders = ["Referer": "https://\(domain)/"]
		var pages: [ComicPageItem] = []
		for (idx, media) in medias.enumerated() {
			guard let path = SourceJSON.string(media["filePath"]) else { continue }
			let pageUrl = ParserUtils.toAbsoluteUrl(path, domain: domain)
			pages.append(ComicPageItem(id: "\(chapter.id)_\(idx)", url: pageUrl, headers: pageHeaders))
		}
		return .comicPages(pages)
	}

	private func parseMangaItem(_ jo: [String: Any]) -> MangaItem? {
		guard let slug = SourceJSON.string(jo["slug"]),
			  let title = SourceJSON.string(jo["title"]) else {
			return nil
		}
		let relUrl = "/manga/\(slug)"
		return MangaItem(
			id: KotatsuUid.generate(sourceName: sourceID.rawValue, url: relUrl),
			title: title,
			url: relUrl,
			publicUrl: "https://\(domain)\(relUrl)",
			coverUrl: SourceJSON.string(jo["featuredImage"]),
			isNsfw: (jo["isAdult"] as? Bool) == true,
			sourceName: sourceID.rawValue
		)
	}
}

public struct KomikCastSource: ContentSource {
	public let sourceID: CatalogSourceID = .komikCast
	private let domain = "komikcast.gg"

	public init() {}

	public func fetchList(page: Int, query: String, sort: SortMode) async throws -> [MangaItem] {
		var comps = URLComponents(string: "https://\(domain)/explore")!
		var qItems = [
			URLQueryItem(name: "page", value: "\(page)"),
			URLQueryItem(name: "sort", value: sort == .popular ? "popular" : "latest"),
		]
		let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
		if !cleanQuery.isEmpty {
			qItems.append(URLQueryItem(name: "q", value: cleanQuery))
		}
		comps.queryItems = qItems
		let html = try await HttpClient.shared.getString(url: comps.url!.absoluteString, headers: sourceID.defaultHeaders)
		guard let props = Self.extractInertiaProps(from: html) else { return [] }

		var rawList: [[String: Any]] = []
		if let dict = props["comics"] as? [String: Any] {
			let sortedKeys = dict.keys.sorted { (Int($0) ?? Int.max, $0) < (Int($1) ?? Int.max, $1) }
			for key in sortedKeys {
				if let obj = dict[key] as? [String: Any] {
					rawList.append(obj)
				}
			}
		} else if let arr = props["comics"] as? [[String: Any]] {
			rawList = arr
		}
		return rawList.compactMap { parseComicItem($0) }
	}

	public func fetchDetails(manga: MangaItem) async throws -> MangaItem {
		let fullUrl = ParserUtils.toAbsoluteUrl(manga.url, domain: domain)
		let html = try await HttpClient.shared.getString(url: fullUrl, headers: sourceID.defaultHeaders)
		let doc = try SwiftSoup.parse(html)
		var updated = manga

		if let props = Self.extractInertiaProps(from: html),
		   let comic = props["comic"] as? [String: Any] {
			updated.title = SourceJSON.string(comic["title"]) ?? manga.title
			updated.description = SourceJSON.string(comic["description"]) ?? manga.description
			if let coverPath = SourceJSON.string(comic["cover_path"])?
				.trimmingCharacters(in: CharacterSet(charactersIn: "/")) {
				updated.coverUrl = "https://\(domain)/media/\(coverPath)"
			}
			var authors: [String] = []
			for key in ["author", "artist"] {
				if let v = SourceJSON.string(comic[key]), !authors.contains(v) {
					authors.append(v)
				}
			}
			if !authors.isEmpty { updated.authors = authors }
			let tags = (comic["genres"] as? [[String: Any]] ?? [])
				.compactMap { SourceJSON.string($0["name"]) }
			if !tags.isEmpty { updated.tags = tags }
			if let adult = comic["is_adult"] as? Bool { updated.isNsfw = adult }
			if let rawState = SourceJSON.string(comic["status"])?.lowercased() {
				if rawState.contains("berjalan") || rawState.contains("ongoing") { updated.state = "ONGOING" }
				else if rawState.contains("tamat") || rawState.contains("completed") { updated.state = "FINISHED" }
				else if rawState.contains("hiatus") { updated.state = "PAUSED" }
			}
		}

		let pills = try doc.select("a.chapter-pill").array()
		var chapters: [ChapterItem] = []
		for (idx, a) in pills.reversed().enumerated() {
			guard let rawHref = try? a.attr("href"), !rawHref.isEmpty else { continue }
			let chUrl = SourceJSON.stripHost(rawHref, domain: domain)
			let numSeg = chUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")).split(separator: "/").last.map(String.init) ?? ""
			let num = Float(numSeg) ?? Float(idx + 1)
			let title = (try? a.select("strong").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines))
				.flatMap { $0.isEmpty ? nil : $0 }
				?? (try? a.text().trimmingCharacters(in: .whitespacesAndNewlines))
				?? "Chapter \(SourceJSON.formatNumber(num))"
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
		updated.chapters = chapters
		return updated
	}

	public func fetchChapterPayload(chapter: ChapterItem) async throws -> ChapterPayload {
		let fullUrl = ParserUtils.toAbsoluteUrl(chapter.url, domain: domain)
		let html = try await HttpClient.shared.getString(url: fullUrl, headers: sourceID.defaultHeaders)
		guard let props = Self.extractInertiaProps(from: html),
			  let pages = props["pages"] as? [String] else {
			return .comicPages([])
		}
		let pageHeaders = ["Referer": fullUrl]
		return .comicPages(pages.enumerated().compactMap { idx, raw in
			let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !clean.isEmpty else { return nil }
			return ComicPageItem(
				id: "\(chapter.id)_\(idx)",
				url: ParserUtils.toAbsoluteUrl(clean, domain: domain),
				headers: pageHeaders
			)
		})
	}

	public static func extractInertiaProps(from html: String) -> [String: Any]? {
		let pattern = #"<script[^>]*data-page=["']?app["']?[^>]*>([\s\S]*?)</script>"#
		guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
			  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
			  match.numberOfRanges > 1,
			  let range = Range(match.range(at: 1), in: html) else {
			return nil
		}
		let jsonRaw = String(html[range])
		guard let root = SourceJSON.object(from: jsonRaw) else { return nil }
		return root["props"] as? [String: Any]
	}

	private func parseComicItem(_ jo: [String: Any]) -> MangaItem? {
		guard let slug = SourceJSON.string(jo["slug"]),
			  let title = SourceJSON.string(jo["title"]) else {
			return nil
		}
		let relUrl = "/series/\(slug)"
		let coverPath = SourceJSON.string(jo["cover_path"])?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		let coverUrl = coverPath.map { "https://\(domain)/media/\($0)" }
		return MangaItem(
			id: KotatsuUid.generate(sourceName: sourceID.rawValue, url: relUrl),
			title: title,
			url: relUrl,
			publicUrl: "https://\(domain)\(relUrl)",
			coverUrl: coverUrl,
			isNsfw: (jo["is_adult"] as? Bool) == true,
			sourceName: sourceID.rawValue
		)
	}
}

public struct MangaReaderSource: ContentSource {
	public let sourceID: CatalogSourceID

	public init(sourceID: CatalogSourceID) {
		self.sourceID = sourceID
	}

	private var domain: String { sourceID.defaultDomain }

	public func fetchList(page: Int, query: String, sort: SortMode) async throws -> [MangaItem] {
		let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
		let url: String
		if !cleanQuery.isEmpty {
			url = "https://\(domain)/page/\(page)/?s=\(HttpClient.formEncode(cleanQuery))"
		} else {
			let order = sort == .popular ? "popular" : "update"
			url = "https://\(domain)/manga/?order=\(order)&page=\(page)"
		}
		let html = try await HttpClient.shared.getString(url: url, headers: sourceID.defaultHeaders)
		let doc = try SwiftSoup.parse(html)
		var items: [MangaItem] = []
		var seen = Set<String>()
		for el in try doc.select(".postbody .listupd .bs .bsx").array() {
			guard let a = try el.select("a").first(),
				  let rawHref = try? a.attr("href"), !rawHref.isEmpty else { continue }
			let relUrl = SourceJSON.stripHost(rawHref, domain: domain)
			guard seen.insert(relUrl).inserted else { continue }
			let title = (try? el.select("div.tt").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines))
				.flatMap { $0.isEmpty ? nil : $0 }
				?? (try? a.attr("title").trimmingCharacters(in: .whitespacesAndNewlines))
				?? ""
			guard !title.isEmpty else { continue }
			let imgEl = (try? el.select("img.ts-post-image").first()) ?? (try? el.select("img").first())
			let cover = ParserUtils.imageSrc(imgEl, domain: domain)
			items.append(
				MangaItem(
					id: KotatsuUid.generate(sourceName: sourceID.rawValue, url: relUrl),
					title: title,
					url: relUrl,
					publicUrl: ParserUtils.toAbsoluteUrl(relUrl, domain: domain),
					coverUrl: cover,
					isNsfw: sourceID.isNsfw,
					sourceName: sourceID.rawValue
				)
			)
		}
		return items
	}

	public func fetchDetails(manga: MangaItem) async throws -> MangaItem {
		let fullUrl = ParserUtils.toAbsoluteUrl(manga.url, domain: domain)
		let html = try await HttpClient.shared.getString(url: fullUrl, headers: sourceID.defaultHeaders)
		let doc = try SwiftSoup.parse(html)

		let title = (try? doc.select("h1.entry-title, .seriestucontent h1, h1").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines))
			.flatMap { $0.isEmpty ? nil : $0 } ?? manga.title
		let desc = (try? doc.select("div.entry-content").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines))
			?? manga.description
		let tags = (try? doc.select(".seriestugenre > a, .wd-full .mgen > a").array().compactMap { el -> String? in
			let t = try? el.text().trimmingCharacters(in: .whitespacesAndNewlines)
			return (t?.isEmpty == false) ? t : nil
		}) ?? []
		let cover = ParserUtils.imageSrc(try? doc.select("div.thumb img, .seriestucontl img").first(), domain: domain)
			?? manga.coverUrl

		let rows = (try? doc.select("#chapterlist > ul > li").array()) ?? []
		var chapters: [ChapterItem] = []
		for (idx, row) in rows.reversed().enumerated() {
			guard let a = try row.select("a").first(),
				  let rawHref = try? a.attr("href"), !rawHref.isEmpty else { continue }
			let chUrl = SourceJSON.stripHost(rawHref, domain: domain)
			let chTitle = (try? row.select(".chapternum").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines))
				.flatMap { $0.isEmpty ? nil : $0 }
				?? "Chapter \(idx + 1)"
			chapters.append(
				ChapterItem(
					id: KotatsuUid.generate(sourceName: sourceID.rawValue, url: chUrl),
					title: chTitle,
					number: Float(idx + 1),
					url: chUrl,
					sourceName: sourceID.rawValue
				)
			)
		}

		var updated = manga
		updated.title = title
		updated.coverUrl = cover
		updated.description = desc
		if !tags.isEmpty { updated.tags = tags }
		updated.chapters = chapters
		return updated
	}

	public func fetchChapterPayload(chapter: ChapterItem) async throws -> ChapterPayload {
		let fullUrl = ParserUtils.toAbsoluteUrl(chapter.url, domain: domain)
		let html = try await HttpClient.shared.getString(url: fullUrl, headers: sourceID.defaultHeaders)
		let pageHeaders = ["Referer": fullUrl]
		let scriptImages = Self.extractTsReaderImages(from: html)
		if !scriptImages.isEmpty {
			return .comicPages(scriptImages.enumerated().map { idx, imgUrl in
				ComicPageItem(
					id: "\(chapter.id)_\(idx)",
					url: ParserUtils.toAbsoluteUrl(imgUrl, domain: domain),
					headers: pageHeaders
				)
			})
		}

		let doc = try SwiftSoup.parse(html)
		var pages: [ComicPageItem] = []
		for (idx, img) in (try doc.select("div#readerarea img").array()).enumerated() {
			guard let src = ParserUtils.imageSrc(img, domain: domain) else { continue }
			pages.append(ComicPageItem(id: "\(chapter.id)_\(idx)", url: src, headers: pageHeaders))
		}
		return .comicPages(pages)
	}

	public static func extractTsReaderImages(from html: String) -> [String] {
		guard let runRange = html.range(of: "ts_reader.run"),
			  let braceStart = html[runRange.upperBound...].firstIndex(of: "{") else {
			return []
		}
		var depth = 0
		var inString = false
		var escaped = false
		var idx = braceStart
		var braceEnd: String.Index?
		while idx < html.endIndex {
			let ch = html[idx]
			if inString {
				if escaped {
					escaped = false
				} else if ch == "\\" {
					escaped = true
				} else if ch == "\"" {
					inString = false
				}
			} else {
				if ch == "\"" {
					inString = true
				} else if ch == "{" {
					depth += 1
				} else if ch == "}" {
					depth -= 1
					if depth == 0 {
						braceEnd = html.index(after: idx)
						break
					}
				}
			}
			idx = html.index(after: idx)
		}
		guard let braceEnd else { return [] }
		let jsonStr = String(html[braceStart..<braceEnd])
		guard let root = SourceJSON.object(from: jsonStr),
			  let sources = root["sources"] as? [[String: Any]],
			  let images = sources.first?["images"] as? [String] else {
			return []
		}
		return images.compactMap { raw in
			let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
			return t.isEmpty ? nil : t
		}
	}
}
