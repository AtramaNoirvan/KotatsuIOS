import Foundation

public enum KotatsuUid {
	public static let seed: Int64 = 1_125_899_906_842_597

	/// Bit-for-bit compatible with Android kotatsu-parsers MangaParser.generateUid(url).
	public static func generate(sourceName: String, url: String) -> Int64 {
		var h = seed
		for unit in sourceName.utf16 {
			h = (31 &* h) &+ Int64(unit)
		}
		for unit in url.utf16 {
			h = (31 &* h) &+ Int64(unit)
		}
		return h
	}
}

public enum ContentMode: String, CaseIterable, Identifiable, Codable {
	case comic
	case novel

	public var id: String { rawValue }

	public var title: String {
		switch self {
		case .comic: return "Komik"
		case .novel: return "Novel"
		}
	}

	public var systemImage: String {
		switch self {
		case .comic: return "book.pages"
		case .novel: return "text.book.closed"
		}
	}
}

public enum CatalogSourceID: String, CaseIterable, Identifiable, Codable {
	// Comic sources
	case komiku = "KOMIKU"
	case doujinDesu = "DOUJINDESU"
	case mangaDex = "MANGADEX"

	// Novel sources (matching Android v9.5.3)
	case novelBin = "NOVELBIN"
	case freeWebNovel = "FREEWEBNOVEL"
	case libRead = "LIBREAD"
	case novelFull = "NOVELFULL"
	case allNovelFull = "ALLNOVELFULL"
	case indoWebNovel = "INDOWEBNOVEL"
	case novelRingan = "NOVELRINGAN"

	public var id: String { rawValue }

	public var displayName: String {
		switch self {
		case .komiku: return "Komiku"
		case .doujinDesu: return "DoujinDesu"
		case .mangaDex: return "MangaDex"
		case .novelBin: return "NovelBin"
		case .freeWebNovel: return "FreeWebNovel"
		case .libRead: return "LibRead"
		case .novelFull: return "NovelFull"
		case .allNovelFull: return "AllNovelFull"
		case .indoWebNovel: return "IndoWebNovel"
		case .novelRingan: return "NovelRingan"
		}
	}

	public var languageBadge: String {
		switch self {
		case .komiku, .doujinDesu, .indoWebNovel, .novelRingan:
			return "ID"
		case .mangaDex:
			return "ID/EN"
		case .novelBin, .freeWebNovel, .libRead, .novelFull, .allNovelFull:
			return "EN"
		}
	}

	public var isNovel: Bool {
		switch self {
		case .komiku, .doujinDesu, .mangaDex:
			return false
		case .novelBin, .freeWebNovel, .libRead, .novelFull, .allNovelFull, .indoWebNovel, .novelRingan:
			return true
		}
	}

	public var isNsfw: Bool {
		self == .doujinDesu
	}

	public var isForeignLanguage: Bool {
		languageBadge == "EN"
	}

	public var defaultDomain: String {
		switch self {
		case .komiku: return "komiku.org"
		case .doujinDesu: return "doujin.desu.xxx"
		case .mangaDex: return "api.mangadex.org"
		case .novelBin: return "novelbin.com"
		case .freeWebNovel: return "freewebnovel.com"
		case .libRead: return "libread.com"
		case .novelFull: return "novelfull.net"
		case .allNovelFull: return "novgo.net"
		case .indoWebNovel: return "indowebnovel.id"
		case .novelRingan: return "novelringan.com"
		}
	}

	public var defaultHeaders: [String: String] {
		switch self {
		case .doujinDesu:
			return ["Referer": "https://\(defaultDomain)/"]
		case .komiku:
			return ["Referer": "https://\(defaultDomain)/"]
		case .mangaDex:
			return ["Referer": "https://mangadex.org/"]
		default:
			return ["Referer": "https://\(defaultDomain)/"]
		}
	}

	public static func isNovelSourceName(_ sourceName: String) -> Bool {
		if let known = CatalogSourceID(rawValue: sourceName) {
			return known.isNovel
		}
		return sourceName.localizedCaseInsensitiveContains("NOVEL") || sourceName == "LIBREAD"
	}
}

public struct ChapterItem: Identifiable, Hashable, Codable {
	public let id: Int64
	public let title: String
	public let number: Float
	public let url: String
	public let sourceName: String

	public init(id: Int64, title: String, number: Float, url: String, sourceName: String) {
		self.id = id
		self.title = title
		self.number = number
		self.url = url
		self.sourceName = sourceName
	}
}

public struct MangaItem: Identifiable, Hashable, Codable {
	public let id: Int64
	public var title: String
	public var url: String
	public var publicUrl: String
	public var coverUrl: String?
	public var description: String?
	public var authors: [String]
	public var tags: [String]
	public var state: String?
	public var isNsfw: Bool
	public var sourceName: String
	public var chapters: [ChapterItem]

	public init(
		id: Int64,
		title: String,
		url: String,
		publicUrl: String,
		coverUrl: String? = nil,
		description: String? = nil,
		authors: [String] = [],
		tags: [String] = [],
		state: String? = nil,
		isNsfw: Bool = false,
		sourceName: String,
		chapters: [ChapterItem] = []
	) {
		self.id = id
		self.title = title
		self.url = url
		self.publicUrl = publicUrl
		self.coverUrl = coverUrl
		self.description = description
		self.authors = authors
		self.tags = tags
		self.state = state
		self.isNsfw = isNsfw
		self.sourceName = sourceName
		self.chapters = chapters
	}

	public var isNovel: Bool {
		CatalogSourceID.isNovelSourceName(sourceName)
	}

	public var sourceID: CatalogSourceID? {
		CatalogSourceID(rawValue: sourceName)
	}
}

public enum ChapterPayload {
	case comicPages([ComicPageItem])
	case novel(title: String?, paragraphs: [String])
}

public struct ComicPageItem: Identifiable, Hashable {
	public let id: String
	public let url: String
	public let headers: [String: String]

	public init(id: String, url: String, headers: [String: String]) {
		self.id = id
		self.url = url
		self.headers = headers
	}
}

public struct HistoryRecord: Identifiable, Codable, Hashable {
	public var id: Int64 { mangaId }
	public let mangaId: Int64
	public var createdAt: Int64
	public var updatedAt: Int64
	public var deletedAt: Int64
	public var chapterId: Int64
	public var page: Int
	public var scroll: Float
	public var percent: Float
	public var chaptersCount: Int
	public var manga: MangaItem

	public var effectiveTimestamp: Int64 {
		max(updatedAt, deletedAt)
	}
}

public struct FavouriteRecord: Identifiable, Codable, Hashable {
	public var id: String { "\(mangaId)_\(categoryId)" }
	public let mangaId: Int64
	public var categoryId: Int64
	public var sortKey: Int
	public var isPinned: Bool
	public var createdAt: Int64
	public var deletedAt: Int64
	public var manga: MangaItem

	public var effectiveTimestamp: Int64 {
		max(createdAt, deletedAt)
	}
}

public struct GlossaryRule: Identifiable, Codable, Hashable {
	public var id: String { sourceTerm.lowercased() }
	public var sourceTerm: String
	public var replacement: String
	public var ignoreCase: Bool

	public init(sourceTerm: String, replacement: String, ignoreCase: Bool = true) {
		self.sourceTerm = sourceTerm
		self.replacement = replacement
		self.ignoreCase = ignoreCase
	}
}

public struct NovelBookmark: Identifiable, Codable, Hashable {
	public let id: Int64
	public let chapterId: Int64
	public let chapterIndex: Int
	public let chapterTitle: String
	public let paragraphIndex: Int
	public let excerpt: String
	public let note: String
	public let createdAt: Int64
}
