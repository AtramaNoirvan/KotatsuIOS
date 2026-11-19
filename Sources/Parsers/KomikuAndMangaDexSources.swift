import Foundation
import SwiftSoup

public struct KomikuSource: ContentSource {
	public let sourceID: CatalogSourceID = .komiku
	private let domain = "komiku.org"
	private let apiDomain = "api.komiku.org"

	public init() {}

	public func fetchList(page: Int, query: String, sort: SortMode) async throws -> [MangaItem] {
		let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
		let url: String
		if !cleanQuery.isEmpty {
			let encoded = HttpClient.formEncode(cleanQuery)
			url = "https://\(apiDomain)/page/\(page)/?post_type=manga&s=\(encoded)"
		} else {
			let orderBy = sort == .popular ? "meta_value_num" : "modified"
			let pageSeg = page > 1 ? "/page/\(page)" : ""
			url = "https://\(apiDomain)/manga\(pageSeg)/?orderby=\(orderBy)"
		}
		let html = try await HttpClient.shared.getString(url: url, headers: sourceID.defaultHeaders)
		let doc = try SwiftSoup.parse(html)
		var items: [MangaItem] = []
		var seen = Set<String>()
		for el in try doc.select("div.bge").array() {
			guard let link = try el.select("a:has(h3)").first(),
				  let rawHref = try? link.attr("href").trimmingCharacters(in: .whitespacesAndNewlines),
				  !rawHref.isEmpty else { continue }
			let relUrl = ParserUtils.toRelativeUrl(rawHref, domain: domain)
			guard seen.insert(relUrl).inserted else { continue }
			guard let title = try el.select("h3").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines),
				  !title.isEmpty else { continue }
			let cover = ParserUtils.imageSrc(try el.select("img").first(), domain: domain)
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

		let title = (try? doc.select("h1 span[itemprop=name]").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines))
			.flatMap { $0.isEmpty ? nil : $0 } ?? manga.title
		let desc = try? doc.select("#Sinopsis > p").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines)
		let cover = ParserUtils.imageSrc(try? doc.select("div.ims > img").first(), domain: domain)?
			.components(separatedBy: "?").first ?? manga.coverUrl
		let tags = (try? doc.select("ul.genre li.genre a").array().compactMap { el -> String? in
			let t = try? el.text().trimmingCharacters(in: .whitespacesAndNewlines)
			return (t?.isEmpty == false) ? t : nil
		}) ?? []

		let rows = (try? doc.select("#Daftar_Chapter tr:has(td.judulseries)").array()) ?? []
		var chapters: [ChapterItem] = []
		for (idx, row) in rows.reversed().enumerated() {
			guard let a = try? row.select("td.judulseries a").first(),
				  let rawHref = try? a.attr("href"), !rawHref.isEmpty else { continue }
			let chUrl = ParserUtils.toRelativeUrl(rawHref, domain: domain)
			let chTitle = (try? a.select("span").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines))
				.flatMap { $0.isEmpty ? nil : $0 }
				?? (try? a.text().trimmingCharacters(in: .whitespacesAndNewlines))
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
		updated.tags = tags
		updated.chapters = chapters
		return updated
	}

	public func fetchChapterPayload(chapter: ChapterItem) async throws -> ChapterPayload {
		let fullUrl = ParserUtils.toAbsoluteUrl(chapter.url, domain: domain)
		let html = try await HttpClient.shared.getString(url: fullUrl, headers: sourceID.defaultHeaders)
		let doc = try SwiftSoup.parse(html)
		var imgs = try doc.select("#Baca_Komik img.ww, #Baca_Komik img.klazy").array()
		if imgs.isEmpty {
			imgs = try doc.select("#Baca_Komik img").array()
		}
		var pages: [ComicPageItem] = []
		for (idx, img) in imgs.enumerated() {
			guard let src = ParserUtils.imageSrc(img, domain: domain) else { continue }
			let lower = src.lowercased()
			if lower.contains("/asset/img/") || lower.hasSuffix("/opening.webp") {
				continue
			}
			pages.append(
				ComicPageItem(
					id: "\(chapter.id)_\(idx)",
					url: src,
					headers: ["Referer": fullUrl]
				)
			)
		}
		return .comicPages(pages)
	}
}

public struct MangaDexSource: ContentSource {
	public let sourceID: CatalogSourceID = .mangaDex
	private let apiBase = "https://api.mangadex.org"

	public init() {}

	public func fetchList(page: Int, query: String, sort: SortMode) async throws -> [MangaItem] {
		let limit = 20
		let offset = max(0, page - 1) * limit
		var comps = URLComponents(string: "\(apiBase)/manga")!
		var qItems = [
			URLQueryItem(name: "limit", value: "\(limit)"),
			URLQueryItem(name: "offset", value: "\(offset)"),
			URLQueryItem(name: "includes[]", value: "cover_art"),
			URLQueryItem(name: "contentRating[]", value: "safe"),
			URLQueryItem(name: "contentRating[]", value: "suggestive"),
		]
		let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
		if !cleanQuery.isEmpty {
			qItems.append(URLQueryItem(name: "title", value: cleanQuery))
		} else if sort == .popular {
			qItems.append(URLQueryItem(name: "order[followedCount]", value: "desc"))
		} else {
			qItems.append(URLQueryItem(name: "order[latestUploadedChapter]", value: "desc"))
		}
		comps.queryItems = qItems
		let raw = try await HttpClient.shared.getString(url: comps.url!.absoluteString)
		guard let data = raw.data(using: .utf8),
			  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
			  let list = root["data"] as? [[String: Any]] else {
			return []
		}
		return list.compactMap { parseManga($0) }
	}

	public func fetchDetails(manga: MangaItem) async throws -> MangaItem {
		let mangaUuid = manga.url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		var comps = URLComponents(string: "\(apiBase)/manga/\(mangaUuid)/feed")!
		comps.queryItems = [
			URLQueryItem(name: "limit", value: "250"),
			URLQueryItem(name: "translatedLanguage[]", value: "id"),
			URLQueryItem(name: "translatedLanguage[]", value: "en"),
			URLQueryItem(name: "order[chapter]", value: "asc"),
		]
		let raw = try await HttpClient.shared.getString(url: comps.url!.absoluteString)
		var chapters: [ChapterItem] = []
		if let data = raw.data(using: .utf8),
		   let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
		   let feed = root["data"] as? [[String: Any]] {
			for (idx, item) in feed.enumerated() {
				guard let chId = item["id"] as? String,
					  let attrs = item["attributes"] as? [String: Any] else { continue }
				let external = (attrs["externalUrl"] as? String) ?? ""
				if !external.isEmpty { continue }
				let chNumStr = (attrs["chapter"] as? String) ?? "\(idx + 1)"
				let chTitleRaw = (attrs["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
				let lang = (attrs["translatedLanguage"] as? String)?.uppercased() ?? ""
				let title = chTitleRaw.isEmpty
					? "Ch. \(chNumStr) [\(lang)]"
					: "Ch. \(chNumStr): \(chTitleRaw) [\(lang)]"
				chapters.append(
					ChapterItem(
						id: KotatsuUid.generate(sourceName: sourceID.rawValue, url: chId),
						title: title,
						number: Float(chNumStr) ?? Float(idx + 1),
						url: chId,
						sourceName: sourceID.rawValue
					)
				)
			}
		}
		var updated = manga
		updated.chapters = chapters
		return updated
	}

	public func fetchChapterPayload(chapter: ChapterItem) async throws -> ChapterPayload {
		let raw = try await HttpClient.shared.getString(url: "\(apiBase)/at-home/server/\(chapter.url)")
		guard let data = raw.data(using: .utf8),
			  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
			  let baseUrl = root["baseUrl"] as? String,
			  let chObj = root["chapter"] as? [String: Any],
			  let hash = chObj["hash"] as? String else {
			return .comicPages([])
		}
		let files = (chObj["dataSaver"] as? [String])?.isEmpty == false
			? (chObj["dataSaver"] as! [String])
			: ((chObj["data"] as? [String]) ?? [])
		let qualityPath = (chObj["dataSaver"] as? [String])?.isEmpty == false ? "data-saver" : "data"
		let pages = files.enumerated().map { idx, filename in
			ComicPageItem(
				id: "\(chapter.id)_\(idx)",
				url: "\(baseUrl)/\(qualityPath)/\(hash)/\(filename)",
				headers: sourceID.defaultHeaders
			)
		}
		return .comicPages(pages)
	}

	private func parseManga(_ obj: [String: Any]) -> MangaItem? {
		guard let idStr = obj["id"] as? String,
			  let attrs = obj["attributes"] as? [String: Any] else { return nil }
		let titles = (attrs["title"] as? [String: String]) ?? [:]
		let title = titles["id"] ?? titles["en"] ?? titles.values.first ?? ""
		guard !title.isEmpty else { return nil }
		let descs = (attrs["description"] as? [String: String]) ?? [:]
		let desc = descs["id"] ?? descs["en"] ?? descs.values.first

		var coverUrl: String?
		if let rels = obj["relationships"] as? [[String: Any]] {
			for rel in rels where (rel["type"] as? String) == "cover_art" {
				if let relAttrs = rel["attributes"] as? [String: Any],
				   let filename = relAttrs["fileName"] as? String {
					coverUrl = "https://uploads.mangadex.org/covers/\(idStr)/\(filename).512.jpg"
					break
				}
			}
		}

		let tags = (attrs["tags"] as? [[String: Any]])?.compactMap { tagObj -> String? in
			let tAttrs = tagObj["attributes"] as? [String: Any]
			let nameMap = tAttrs?["name"] as? [String: String]
			return nameMap?["en"] ?? nameMap?.values.first
		} ?? []

		return MangaItem(
			id: KotatsuUid.generate(sourceName: sourceID.rawValue, url: idStr),
			title: title,
			url: idStr,
			publicUrl: "https://mangadex.org/title/\(idStr)",
			coverUrl: coverUrl,
			description: desc,
			tags: tags,
			state: attrs["status"] as? String,
			isNsfw: false,
			sourceName: sourceID.rawValue
		)
	}
}
