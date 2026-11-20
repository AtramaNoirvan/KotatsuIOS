import Foundation
import SwiftSoup

public enum SortMode: String, CaseIterable, Identifiable {
	case updated = "Terbaru"
	case popular = "Populer"

	public var id: String { rawValue }
}

public protocol ContentSource {
	var sourceID: CatalogSourceID { get }
	func fetchList(page: Int, query: String, sort: SortMode) async throws -> [MangaItem]
	func fetchDetails(manga: MangaItem) async throws -> MangaItem
	func fetchChapterPayload(chapter: ChapterItem) async throws -> ChapterPayload
}

public enum SourceRegistry {
	public static func source(for id: CatalogSourceID) -> ContentSource {
		switch id {
		case .komiku:
			return KomikuSource()
		case .shinigami:
			return ShinigamiSource()
		case .kiryuu:
			return NatsuWpSource(sourceID: .kiryuu)
		case .natsu:
			return NatsuWpSource(sourceID: .natsu)
		case .ikiru:
			return IkiruSource()
		case .komikCast:
			return KomikCastSource()
		case .doujinDesu:
			return DoujinDesuSource()
		case .dojing:
			return MangaReaderSource(sourceID: .dojing)
		case .sekteDoujin:
			return MangaReaderSource(sourceID: .sekteDoujin)
		case .mangaDex:
			return MangaDexSource()
		case .novelBin:
			return NovelBinSource()
		case .freeWebNovel:
			return FreeWebNovelFamilySource(
				sourceID: .freeWebNovel,
				latestPath: "/sort/latest-release",
				popularPath: "/sort/most-popular",
				useKeywordSearchGet: false,
				useQueryPageParam: false,
				popularSinglePage: true
			)
		case .libRead:
			return FreeWebNovelFamilySource(
				sourceID: .libRead,
				latestPath: "/sort/latest-release",
				popularPath: "/most-popular",
				useKeywordSearchGet: false,
				useQueryPageParam: false,
				popularSinglePage: true
			)
		case .novelFull:
			return FreeWebNovelFamilySource(
				sourceID: .novelFull,
				latestPath: "/latest-release-novel",
				popularPath: "/most-popular",
				useKeywordSearchGet: true,
				useQueryPageParam: true,
				popularSinglePage: false
			)
		case .allNovelFull:
			return FreeWebNovelFamilySource(
				sourceID: .allNovelFull,
				latestPath: "/latest-release-novel",
				popularPath: "/most-popular",
				useKeywordSearchGet: true,
				useQueryPageParam: true,
				popularSinglePage: false
			)
		case .indoWebNovel:
			return IndoWebNovelSource()
		case .novelRingan:
			return NovelRinganSource()
		}
	}

	public static func source(named name: String) -> ContentSource? {
		guard let id = CatalogSourceID(rawValue: name) else { return nil }
		return source(for: id)
	}
}

public enum ParserUtils {
	public static func toRelativeUrl(_ raw: String, domain: String) -> String {
		let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
		if trimmed.hasPrefix("/") {
			return trimmed
		}
		if let url = URL(string: trimmed) {
			var result = url.path.isEmpty ? "/" : url.path
			if let q = url.query, !q.isEmpty {
				result += "?\(q)"
			}
			return result
		}
		return trimmed
			.replacingOccurrences(of: "https://\(domain)", with: "")
			.replacingOccurrences(of: "http://\(domain)", with: "")
	}

	public static func toAbsoluteUrl(_ raw: String, domain: String) -> String {
		let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
		if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
			return trimmed
		}
		if trimmed.hasPrefix("//") {
			return "https:\(trimmed)"
		}
		if trimmed.hasPrefix("/") {
			return "https://\(domain)\(trimmed)"
		}
		return "https://\(domain)/\(trimmed)"
	}

	public static func imageSrc(_ img: Element?, domain: String) -> String? {
		guard let img else { return nil }
		let attrs = ["data-src", "data-lazy-src", "data-original", "src"]
		for attr in attrs {
			if let raw = try? img.attr(attr).trimmingCharacters(in: .whitespacesAndNewlines),
			   !raw.isEmpty,
			   !raw.hasPrefix("data:") {
				return toAbsoluteUrl(raw, domain: domain)
			}
		}
		return nil
	}

	public static func extractCleanParagraphs(from root: Element, fallbackTitle: String?) -> [String] {
		do {
			_ = try root.select("script, style, iframe, ins, noscript, .ads, .adsbygoogle, .code-block, .sharedaddy").remove()
			var paragraphs: [String] = []
			let nodes = try root.select("p, h2, h3, h4").array()
			for node in nodes {
				let text = try node.text().trimmingCharacters(in: .whitespacesAndNewlines)
				if !text.isEmpty && !isBoilerplateLine(text) {
					paragraphs.append(text)
				}
			}
			if paragraphs.isEmpty {
				let whole = try root.text()
				let fallbackLines = whole
					.components(separatedBy: .newlines)
					.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
					.filter { !$0.isEmpty && $0 != fallbackTitle && !isBoilerplateLine($0) }
				paragraphs.append(contentsOf: fallbackLines)
			}
			return paragraphs
		} catch {
			return []
		}
	}

	private static func isBoilerplateLine(_ line: String) -> Bool {
		let lower = line.lowercased()
		return lower.contains("read novel full") ||
			lower.contains("support us by") ||
			lower.contains("remove ads") ||
			lower == "advertisement"
	}
}
