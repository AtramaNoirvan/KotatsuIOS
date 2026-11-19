import Foundation
import SwiftSoup

public struct NovelBinSource: ContentSource {
	public let sourceID: CatalogSourceID = .novelBin
	private let domain = "novelbin.com"

	public init() {}

	public func fetchList(page: Int, query: String, sort: SortMode) async throws -> [MangaItem] {
		let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
		let url: String
		if !cleanQuery.isEmpty {
			url = "https://\(domain)/search?keyword=\(HttpClient.formEncode(cleanQuery))&page=\(page)"
		} else if sort == .popular {
			url = "https://\(domain)/sort/top-hot-novel?page=\(page)"
		} else {
			url = "https://\(domain)/sort/latest?page=\(page)"
		}
		let html: String
		do {
			html = try await HttpClient.shared.getString(url: url, headers: sourceID.defaultHeaders)
		} catch HttpClientError.httpStatus(404, _) where page > 1 {
			return []
		}
		let doc = try SwiftSoup.parse(html)
		var items: [MangaItem] = []
		var seen = Set<String>()
		for a in try doc.select("h3.novel-title > a, h3.truyen-title > a, .novel-title > a").array() {
			let rawHref = try a.attr("href")
			let relUrl = ParserUtils.toRelativeUrl(rawHref, domain: domain)
			guard relUrl.contains("/b/") || relUrl.contains("/novel-book/"), seen.insert(relUrl).inserted else { continue }
			var title = try a.text().trimmingCharacters(in: .whitespacesAndNewlines)
			if title.isEmpty { title = try a.attr("title").trimmingCharacters(in: .whitespacesAndNewlines) }
			guard !title.isEmpty else { continue }
			let row = a.parents().array().first { $0.hasClass("row") } ?? a.parent()
			let cover = ParserUtils.imageSrc(try row?.select("img").first(), domain: domain)?
				.replacingOccurrences(of: "/novel_80_113/", with: "/novel/")
				.replacingOccurrences(of: "/novel_150_212/", with: "/novel/")
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
		let title = (try? doc.select("h3.title").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines))
			.flatMap { $0.isEmpty ? nil : $0 } ?? manga.title
		let cover = ParserUtils.imageSrc(try? doc.select("div.book img, div.books img").first(), domain: domain) ?? manga.coverUrl
		let desc = try? doc.select("div.desc-text, #tab-description").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines)
		let novelId = (try? doc.select("[data-novel-id]").first()?.attr("data-novel-id").trimmingCharacters(in: .whitespacesAndNewlines))
			.flatMap { $0.isEmpty ? nil : $0 }
			?? manga.url.trimmingCharacters(in: CharacterSet(charactersIn: "/")).split(separator: "/").last.map(String.init)
			?? ""

		var chapterNodes: [Element] = []
		if !novelId.isEmpty {
			let ajaxUrl = "https://\(domain)/ajax/chapter-archive?novelId=\(HttpClient.formEncode(novelId))"
			if let ajaxHtml = try? await HttpClient.shared.getString(
				url: ajaxUrl,
				headers: ["X-Requested-With": "XMLHttpRequest", "Referer": fullUrl]
			), let ajaxDoc = try? SwiftSoup.parse(ajaxHtml) {
				chapterNodes = (try? ajaxDoc.select("ul.list-chapter li a, a[href*='/chapter']").array()) ?? []
			}
		}
		if chapterNodes.isEmpty {
			chapterNodes = (try? doc.select("ul.list-chapter li a").array()) ?? []
		}
		let chapters = chapterNodes.enumerated().compactMap { idx, a -> ChapterItem? in
			guard let rawHref = try? a.attr("href"), !rawHref.isEmpty else { return nil }
			let chUrl = ParserUtils.toRelativeUrl(rawHref, domain: domain)
			let rawTitle = (try? a.attr("title").trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
			let textTitle = (try? a.text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
			let chTitle = !rawTitle.isEmpty ? rawTitle : (!textTitle.isEmpty ? textTitle : "Chapter \(idx + 1)")
			return ChapterItem(
				id: KotatsuUid.generate(sourceName: sourceID.rawValue, url: chUrl),
				title: chTitle,
				number: Float(idx + 1),
				url: chUrl,
				sourceName: sourceID.rawValue
			)
		}

		var updated = manga
		updated.title = title
		updated.coverUrl = cover
		updated.description = desc
		updated.chapters = chapters
		return updated
	}

	public func fetchChapterPayload(chapter: ChapterItem) async throws -> ChapterPayload {
		let fullUrl = ParserUtils.toAbsoluteUrl(chapter.url, domain: domain)
		let html = try await HttpClient.shared.getString(url: fullUrl, headers: sourceID.defaultHeaders)
		let doc = try SwiftSoup.parse(html)
		guard let content = try doc.select("#chr-content, #chapter-content, .chr-c, .chapter-c").first() else {
			throw HttpClientError.emptyBody
		}
		let chTitle = (try? doc.select(".chr-title, h2, h4").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? chapter.title
		let paragraphs = ParserUtils.extractCleanParagraphs(from: content, fallbackTitle: chTitle)
		return .novel(title: chTitle, paragraphs: paragraphs)
	}
}

public struct FreeWebNovelFamilySource: ContentSource {
	public let sourceID: CatalogSourceID
	private let latestPath: String
	private let popularPath: String
	private let useKeywordSearchGet: Bool
	private let useQueryPageParam: Bool
	private let popularSinglePage: Bool

	private var domain: String { sourceID.defaultDomain }

	public init(
		sourceID: CatalogSourceID,
		latestPath: String,
		popularPath: String,
		useKeywordSearchGet: Bool,
		useQueryPageParam: Bool,
		popularSinglePage: Bool
	) {
		self.sourceID = sourceID
		self.latestPath = latestPath
		self.popularPath = popularPath
		self.useKeywordSearchGet = useKeywordSearchGet
		self.useQueryPageParam = useQueryPageParam
		self.popularSinglePage = popularSinglePage
	}

	public func fetchList(page: Int, query: String, sort: SortMode) async throws -> [MangaItem] {
		let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
		let html: String
		do {
			if !cleanQuery.isEmpty {
				if useKeywordSearchGet {
					let url = "https://\(domain)/search?keyword=\(HttpClient.formEncode(cleanQuery))&page=\(page)"
					html = try await HttpClient.shared.getString(url: url, headers: sourceID.defaultHeaders)
				} else {
					if page > 1 { return [] }
					html = try await HttpClient.shared.postForm(
						url: "https://\(domain)/search",
						fields: [("searchkey", cleanQuery)],
						headers: sourceID.defaultHeaders
					)
				}
			} else {
				if sort == .popular && popularSinglePage && page > 1 { return [] }
				let basePath = sort == .popular ? popularPath : latestPath
				let url: String
				if page <= 1 {
					url = "https://\(domain)\(basePath)"
				} else if useQueryPageParam {
					url = "https://\(domain)\(basePath)?page=\(page)"
				} else {
					url = "https://\(domain)\(basePath)/\(page)"
				}
				html = try await HttpClient.shared.getString(url: url, headers: sourceID.defaultHeaders)
			}
		} catch HttpClientError.httpStatus(404, _) where page > 1 {
			return []
		}

		let doc = try SwiftSoup.parse(html)
		var items: [MangaItem] = []
		var seen = Set<String>()
		for row in try doc.select("div.li-row, div.ul-list1 div.li").array() {
			guard let a = try row.select("h3.tit > a, .tit > a").first(),
				  let rawHref = try? a.attr("href"), !rawHref.isEmpty else { continue }
			let relUrl = ParserUtils.toRelativeUrl(rawHref, domain: domain)
			guard seen.insert(relUrl).inserted else { continue }
			let rawTitle = (try? a.attr("title").trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
			let textTitle = (try? a.text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
			let title = !rawTitle.isEmpty ? rawTitle : textTitle
			guard !title.isEmpty else { continue }
			let cover = ParserUtils.imageSrc(try row.select(".pic img").first(), domain: domain)
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
		let title = (try? doc.select("h1.tit, .m-desc h1").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines))
			.flatMap { $0.isEmpty ? nil : $0 } ?? manga.title
		let cover = ParserUtils.imageSrc(try? doc.select(".m-imgtxt .pic img").first(), domain: domain) ?? manga.coverUrl
		let desc = try? doc.select(".m-desc .txt .inner, .m-desc .txt").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines)

		var seen = Set<String>()
		var chapters: [ChapterItem] = []

		func collectLinks(_ elements: [Element]) {
			for a in elements {
				guard let rawHref = try? a.attr("href"), !rawHref.isEmpty else { continue }
				let chUrl = ParserUtils.toRelativeUrl(rawHref, domain: domain)
				guard seen.insert(chUrl).inserted else { continue }
				let t1 = (try? a.attr("title").trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
				let t2 = (try? a.text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
				let chTitle = !t1.isEmpty ? t1 : (!t2.isEmpty ? t2 : "Chapter \(chapters.count + 1)")
				chapters.append(
					ChapterItem(
						id: KotatsuUid.generate(sourceName: sourceID.rawValue, url: chUrl),
						title: chTitle,
						number: Float(chapters.count + 1),
						url: chUrl,
						sourceName: sourceID.rawValue
					)
				)
			}
		}

		if !useQueryPageParam {
			if let rawAjax = try? await HttpClient.shared.getString(
				url: "\(fullUrl)?ajax=chapters&page=1&pageSize=200",
				headers: ["X-Requested-With": "XMLHttpRequest", "Referer": fullUrl]
			),
			   let data = rawAjax.data(using: .utf8),
			   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			   let fragHtml = obj["html"] as? String,
			   let fragDoc = try? SwiftSoup.parseBodyFragment(fragHtml, fullUrl) {
				collectLinks((try? fragDoc.select("a[href]").array()) ?? [])
			}
		}
		collectLinks((try? doc.select("#idData li a").array()) ?? [])
		collectLinks((try? doc.select("ul.ul-list5 li a").array()) ?? [])

		var updated = manga
		updated.title = title
		updated.coverUrl = cover
		updated.description = desc
		updated.chapters = chapters
		return updated
	}

	public func fetchChapterPayload(chapter: ChapterItem) async throws -> ChapterPayload {
		let fullUrl = ParserUtils.toAbsoluteUrl(chapter.url, domain: domain)
		let html = try await HttpClient.shared.getString(url: fullUrl, headers: sourceID.defaultHeaders)
		let doc = try SwiftSoup.parse(html)
		guard let content = try doc.select("#article, #chapter-content, .chapter-c, .txt").first() else {
			throw HttpClientError.emptyBody
		}
		let chTitle = (try? doc.select(".top span.chapter, h1, h4").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? chapter.title
		let paragraphs = ParserUtils.extractCleanParagraphs(from: content, fallbackTitle: chTitle)
		return .novel(title: chTitle, paragraphs: paragraphs)
	}
}

public struct IndoWebNovelSource: ContentSource {
	public let sourceID: CatalogSourceID = .indoWebNovel
	private let domain = "indowebnovel.id"

	public init() {}

	public func fetchList(page: Int, query: String, sort: SortMode) async throws -> [MangaItem] {
		let q = HttpClient.formEncode(query.trimmingCharacters(in: .whitespacesAndNewlines))
		let url = page > 1 ? "https://\(domain)/page/\(page)/?s=\(q)" : "https://\(domain)/?s=\(q)"
		let html: String
		do {
			html = try await HttpClient.shared.getString(url: url, headers: sourceID.defaultHeaders)
		} catch HttpClientError.httpStatus(404, _) where page > 1 {
			return []
		}
		let doc = try SwiftSoup.parse(html)
		var items: [MangaItem] = []
		var seen = Set<String>()
		for item in try doc.select("div.flexbox2-item, div.flexbox-item").array() {
			guard let a = try item.select("a[href*='/series/']").first(),
				  let rawHref = try? a.attr("href") else { continue }
			let relUrl = ParserUtils.toRelativeUrl(rawHref, domain: domain)
			guard !relUrl.hasSuffix("/feed/"), seen.insert(relUrl).inserted else { continue }
			let title = (try? item.select(".flexbox2-title > span, .flexbox-title").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines))
				.flatMap { $0.isEmpty ? nil : $0 }
				?? (try? a.attr("title").trimmingCharacters(in: .whitespacesAndNewlines))
				?? ""
			guard !title.isEmpty else { continue }
			let cover = ParserUtils.imageSrc(try item.select("img").first(), domain: domain)
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
		let title = (try? doc.select(".series-titlex h2").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines))
			.flatMap { $0.isEmpty ? nil : $0 } ?? manga.title
		let cover = ParserUtils.imageSrc(try? doc.select(".series-thumb img").first(), domain: domain) ?? manga.coverUrl
		let desc = try? doc.select(".series-synops").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines)

		let nodes = (try? doc.select("ul.series-chapterlists li, .flexch-infoz").array()) ?? []
		var chapters: [ChapterItem] = []
		for (idx, el) in nodes.reversed().enumerated() {
			guard let a = try? el.select("a[href]").first(),
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
		updated.chapters = chapters
		return updated
	}

	public func fetchChapterPayload(chapter: ChapterItem) async throws -> ChapterPayload {
		let fullUrl = ParserUtils.toAbsoluteUrl(chapter.url, domain: domain)
		let html = try await HttpClient.shared.getString(url: fullUrl, headers: sourceID.defaultHeaders)
		let doc = try SwiftSoup.parse(html)
		guard let content = try doc.select("div#content, div.reader-area, div.entry-content").first() else {
			throw HttpClientError.emptyBody
		}
		let chTitle = (try? doc.select("h2.title-chapter, h1").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? chapter.title
		let paragraphs = ParserUtils.extractCleanParagraphs(from: content, fallbackTitle: chTitle)
		return .novel(title: chTitle, paragraphs: paragraphs)
	}
}

public struct NovelRinganSource: ContentSource {
	public let sourceID: CatalogSourceID = .novelRingan
	private let domain = "novelringan.com"

	public init() {}

	public func fetchList(page: Int, query: String, sort: SortMode) async throws -> [MangaItem] {
		let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
		let url: String
		if !cleanQuery.isEmpty {
			let q = HttpClient.formEncode(cleanQuery)
			url = page > 1 ? "https://\(domain)/page/\(page)/?s=\(q)" : "https://\(domain)/?s=\(q)"
		} else {
			url = page > 1 ? "https://\(domain)/series/page/\(page)/" : "https://\(domain)/series/"
		}
		let html: String
		do {
			html = try await HttpClient.shared.getString(url: url, headers: sourceID.defaultHeaders)
		} catch HttpClientError.httpStatus(404, _) where page > 1 {
			return []
		}
		let doc = try SwiftSoup.parse(html)
		var items: [MangaItem] = []
		var seen = Set<String>()
		for article in try doc.select("article.infoseries, article.post").array() {
			guard let a = try article.select("h2.entry-title a[href*='/series/'], a[href*='/series/']").first(),
				  let rawHref = try? a.attr("href") else { continue }
			let cleanHref = rawHref.components(separatedBy: "#").first ?? rawHref
			let relUrl = ParserUtils.toRelativeUrl(cleanHref, domain: domain)
			guard relUrl.contains("/series/"), seen.insert(relUrl).inserted else { continue }
			let rawTitle = (try? article.select("h2.entry-title").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines))
				?? (try? a.text().trimmingCharacters(in: .whitespacesAndNewlines))
				?? ""
			let title = rawTitle.replacingOccurrences(of: "Bahasa Indonesia", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
			guard !title.isEmpty else { continue }
			let cover = extractCover(try article.select("img").first())
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
		let rawTitle = (try? doc.select("h1.entry-title").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? manga.title
		let title = rawTitle.replacingOccurrences(of: "Bahasa Indonesia", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
		let cover = extractCover(try? doc.select(".imgprop img, .maininfo img").first()) ?? manga.coverUrl
		let desc = (try? doc.select(".maininfo p").array().map { try $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n\n"))

		let links = (try? doc.select(".bxcl ul li a").array()) ?? []
		var chapters: [ChapterItem] = []
		for (idx, a) in links.reversed().enumerated() {
			guard let rawHref = try? a.attr("href"), !rawHref.isEmpty else { continue }
			let chUrl = ParserUtils.toRelativeUrl(rawHref, domain: domain)
			let chTitle = (try? a.text().trimmingCharacters(in: .whitespacesAndNewlines))
				.flatMap { $0.isEmpty ? nil : $0 } ?? "Chapter \(idx + 1)"
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
		updated.title = title.isEmpty ? manga.title : title
		updated.coverUrl = cover
		updated.description = desc
		updated.chapters = chapters
		return updated
	}

	public func fetchChapterPayload(chapter: ChapterItem) async throws -> ChapterPayload {
		let fullUrl = ParserUtils.toAbsoluteUrl(chapter.url, domain: domain)
		let html = try await HttpClient.shared.getString(url: fullUrl, headers: sourceID.defaultHeaders)
		let doc = try SwiftSoup.parse(html)
		guard let content = try doc.select("div.entry-content, article .entry-content").first() else {
			throw HttpClientError.emptyBody
		}
		let chTitle = (try? doc.select("h1.entry-title").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? chapter.title
		let paragraphs = ParserUtils.extractCleanParagraphs(from: content, fallbackTitle: chTitle)
		return .novel(title: chTitle, paragraphs: paragraphs)
	}

	private func extractCover(_ img: Element?) -> String? {
		guard let img else { return nil }
		if let sxrx = try? img.attr("data-sxrx").trimmingCharacters(in: .whitespacesAndNewlines), !sxrx.isEmpty {
			let clean = sxrx.hasPrefix("/") ? String(sxrx.dropFirst()) : sxrx
			return "https://i0.wp.com/\(domain)/wp-content/uploads/\(clean)"
		}
		if let src = ParserUtils.imageSrc(img, domain: domain), !src.contains("image-placeholder") {
			return src
		}
		return nil
	}
}
