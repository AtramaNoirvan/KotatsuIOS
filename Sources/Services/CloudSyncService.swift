import Foundation
import Security

// MARK: - Wire-Compatible DTOs matching Kotatsu Android v9.5.3 (kotatsu-sync-v1.json)

public struct CloudSyncPayloadDTO: Codable {
	public var version: Int
	public var updatedAt: Int64
	public var history: [CloudHistoryEntryDTO]
	public var categories: [CloudCategoryEntryDTO]
	public var favourites: [CloudFavouriteEntryDTO]
	public var sources: [SourceBackupDTO]

	public enum CodingKeys: String, CodingKey {
		case version
		case updatedAt = "updated_at"
		case history
		case categories
		case favourites
		case sources
	}

	public init(
		version: Int = 1,
		updatedAt: Int64 = 0,
		history: [CloudHistoryEntryDTO] = [],
		categories: [CloudCategoryEntryDTO] = [],
		favourites: [CloudFavouriteEntryDTO] = [],
		sources: [SourceBackupDTO] = []
	) {
		self.version = version
		self.updatedAt = updatedAt
		self.history = history
		self.categories = categories
		self.favourites = favourites
		self.sources = sources
	}

	public init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		self.version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
		self.updatedAt = try c.decodeIfPresent(Int64.self, forKey: .updatedAt) ?? 0
		self.history = try c.decodeIfPresent([CloudHistoryEntryDTO].self, forKey: .history) ?? []
		self.categories = try c.decodeIfPresent([CloudCategoryEntryDTO].self, forKey: .categories) ?? []
		self.favourites = try c.decodeIfPresent([CloudFavouriteEntryDTO].self, forKey: .favourites) ?? []
		self.sources = try c.decodeIfPresent([SourceBackupDTO].self, forKey: .sources) ?? []
	}
}

public struct CloudHistoryEntryDTO: Codable {
	public var mangaId: Int64
	public var createdAt: Int64
	public var updatedAt: Int64
	public var deletedAt: Int64
	public var chapterId: Int64
	public var page: Int
	public var scroll: Float
	public var percent: Float
	public var chaptersCount: Int
	public var manga: MangaBackupDTO

	public enum CodingKeys: String, CodingKey {
		case mangaId = "manga_id"
		case createdAt = "created_at"
		case updatedAt = "updated_at"
		case deletedAt = "deleted_at"
		case chapterId = "chapter_id"
		case page
		case scroll
		case percent
		case chaptersCount = "chapters"
		case manga
	}

	public init(
		mangaId: Int64,
		createdAt: Int64,
		updatedAt: Int64,
		deletedAt: Int64,
		chapterId: Int64,
		page: Int,
		scroll: Float,
		percent: Float,
		chaptersCount: Int,
		manga: MangaBackupDTO
	) {
		self.mangaId = mangaId
		self.createdAt = createdAt
		self.updatedAt = updatedAt
		self.deletedAt = deletedAt
		self.chapterId = chapterId
		self.page = page
		self.scroll = scroll
		self.percent = percent
		self.chaptersCount = chaptersCount
		self.manga = manga
	}

	public init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		self.mangaId = try c.decode(Int64.self, forKey: .mangaId)
		self.createdAt = try c.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
		self.updatedAt = try c.decodeIfPresent(Int64.self, forKey: .updatedAt) ?? 0
		self.deletedAt = try c.decodeIfPresent(Int64.self, forKey: .deletedAt) ?? 0
		self.chapterId = try c.decodeIfPresent(Int64.self, forKey: .chapterId) ?? 0
		self.page = try c.decodeIfPresent(Int.self, forKey: .page) ?? 0
		self.scroll = try c.decodeIfPresent(Float.self, forKey: .scroll) ?? 0
		self.percent = try c.decodeIfPresent(Float.self, forKey: .percent) ?? -1
		self.chaptersCount = try c.decodeIfPresent(Int.self, forKey: .chaptersCount) ?? 0
		self.manga = try c.decode(MangaBackupDTO.self, forKey: .manga)
	}

	public var effectiveTimestamp: Int64 { max(updatedAt, deletedAt) }
}

public struct CloudCategoryEntryDTO: Codable {
	public var categoryId: Int
	public var createdAt: Int64
	public var deletedAt: Int64
	public var sortKey: Int
	public var title: String
	public var order: String
	public var track: Bool
	public var isVisibleInLibrary: Bool

	public enum CodingKeys: String, CodingKey {
		case categoryId = "category_id"
		case createdAt = "created_at"
		case deletedAt = "deleted_at"
		case sortKey = "sort_key"
		case title
		case order
		case track
		case isVisibleInLibrary = "show_in_lib"
	}

	public init(
		categoryId: Int,
		createdAt: Int64,
		deletedAt: Int64,
		sortKey: Int,
		title: String,
		order: String,
		track: Bool,
		isVisibleInLibrary: Bool
	) {
		self.categoryId = categoryId
		self.createdAt = createdAt
		self.deletedAt = deletedAt
		self.sortKey = sortKey
		self.title = title
		self.order = order
		self.track = track
		self.isVisibleInLibrary = isVisibleInLibrary
	}

	public init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		self.categoryId = try c.decode(Int.self, forKey: .categoryId)
		self.createdAt = try c.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
		self.deletedAt = try c.decodeIfPresent(Int64.self, forKey: .deletedAt) ?? 0
		self.sortKey = try c.decodeIfPresent(Int.self, forKey: .sortKey) ?? 0
		self.title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Favorit"
		self.order = try c.decodeIfPresent(String.self, forKey: .order) ?? "NEWEST"
		self.track = try c.decodeIfPresent(Bool.self, forKey: .track) ?? true
		self.isVisibleInLibrary = try c.decodeIfPresent(Bool.self, forKey: .isVisibleInLibrary) ?? true
	}

	public var effectiveTimestamp: Int64 { max(createdAt, deletedAt) }
}

public struct CloudFavouriteEntryDTO: Codable {
	public var mangaId: Int64
	public var categoryId: Int64
	public var sortKey: Int
	public var isPinned: Bool
	public var createdAt: Int64
	public var deletedAt: Int64
	public var manga: MangaBackupDTO

	public enum CodingKeys: String, CodingKey {
		case mangaId = "manga_id"
		case categoryId = "category_id"
		case sortKey = "sort_key"
		case isPinned = "pinned"
		case createdAt = "created_at"
		case deletedAt = "deleted_at"
		case manga
	}

	public init(
		mangaId: Int64,
		categoryId: Int64,
		sortKey: Int,
		isPinned: Bool,
		createdAt: Int64,
		deletedAt: Int64,
		manga: MangaBackupDTO
	) {
		self.mangaId = mangaId
		self.categoryId = categoryId
		self.sortKey = sortKey
		self.isPinned = isPinned
		self.createdAt = createdAt
		self.deletedAt = deletedAt
		self.manga = manga
	}

	public init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		self.mangaId = try c.decode(Int64.self, forKey: .mangaId)
		self.categoryId = try c.decodeIfPresent(Int64.self, forKey: .categoryId) ?? 1
		self.sortKey = try c.decodeIfPresent(Int.self, forKey: .sortKey) ?? 0
		self.isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
		self.createdAt = try c.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
		self.deletedAt = try c.decodeIfPresent(Int64.self, forKey: .deletedAt) ?? 0
		self.manga = try c.decode(MangaBackupDTO.self, forKey: .manga)
	}

	public var effectiveTimestamp: Int64 { max(createdAt, deletedAt) }
}

public struct MangaBackupDTO: Codable {
	public var id: Int64
	public var title: String
	public var altTitles: String?
	public var url: String
	public var publicUrl: String
	public var rating: Float
	public var isNsfw: Bool
	public var contentRating: String?
	public var coverUrl: String
	public var largeCoverUrl: String?
	public var state: String?
	public var authors: String?
	public var source: String
	public var tags: [TagBackupDTO]

	public enum CodingKeys: String, CodingKey {
		case id
		case title
		case altTitles = "alt_title"
		case url
		case publicUrl = "public_url"
		case rating
		case isNsfw = "nsfw"
		case contentRating = "content_rating"
		case coverUrl = "cover_url"
		case largeCoverUrl = "large_cover_url"
		case state
		case authors = "author"
		case source
		case tags
	}

	public init(from manga: MangaItem) {
		self.id = manga.id
		self.title = manga.title
		self.altTitles = nil
		self.url = manga.url
		self.publicUrl = manga.publicUrl
		self.rating = -1
		self.isNsfw = manga.isNsfw
		self.contentRating = manga.isNsfw ? "ADULT" : "SAFE"
		self.coverUrl = manga.coverUrl ?? ""
		self.largeCoverUrl = nil
		self.state = manga.state
		self.authors = manga.authors.isEmpty ? nil : manga.authors.joined(separator: ", ")
		self.source = manga.sourceName
		self.tags = []
	}

	public init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		self.id = try c.decode(Int64.self, forKey: .id)
		self.title = try c.decode(String.self, forKey: .title)
		self.altTitles = try c.decodeIfPresent(String.self, forKey: .altTitles)
		self.url = try c.decode(String.self, forKey: .url)
		self.publicUrl = try c.decodeIfPresent(String.self, forKey: .publicUrl) ?? ""
		self.rating = try c.decodeIfPresent(Float.self, forKey: .rating) ?? -1
		self.isNsfw = try c.decodeIfPresent(Bool.self, forKey: .isNsfw) ?? false
		self.contentRating = try c.decodeIfPresent(String.self, forKey: .contentRating)
		self.coverUrl = try c.decodeIfPresent(String.self, forKey: .coverUrl) ?? ""
		self.largeCoverUrl = try c.decodeIfPresent(String.self, forKey: .largeCoverUrl)
		self.state = try c.decodeIfPresent(String.self, forKey: .state)
		self.authors = try c.decodeIfPresent(String.self, forKey: .authors)
		self.source = try c.decode(String.self, forKey: .source)
		self.tags = try c.decodeIfPresent([TagBackupDTO].self, forKey: .tags) ?? []
	}

	public func toMangaItem() -> MangaItem {
		MangaItem(
			id: id,
			title: title,
			url: url,
			publicUrl: publicUrl,
			coverUrl: coverUrl.isEmpty ? nil : coverUrl,
			authors: (authors ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
			tags: tags.map(\.title),
			state: state,
			isNsfw: isNsfw || contentRating == "ADULT",
			sourceName: source
		)
	}
}

public struct TagBackupDTO: Codable {
	public var id: Int64
	public var title: String
	public var key: String
	public var source: String
	public var isPinned: Bool

	public enum CodingKeys: String, CodingKey {
		case id, title, key, source
		case isPinned = "pinned"
	}

	public init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		self.id = try c.decodeIfPresent(Int64.self, forKey: .id) ?? 0
		self.title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
		self.key = try c.decodeIfPresent(String.self, forKey: .key) ?? ""
		self.source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
		self.isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
	}
}

public struct SourceBackupDTO: Codable {
	public var source: String
	public var sortKey: Int
	public var lastUsedAt: Int64
	public var addedIn: Int
	public var isPinned: Bool
	public var isEnabled: Bool

	public enum CodingKeys: String, CodingKey {
		case source
		case sortKey = "sort_key"
		case lastUsedAt = "used_at"
		case addedIn = "added_in"
		case isPinned = "pinned"
		case isEnabled = "enabled"
	}

	public init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		self.source = try c.decode(String.self, forKey: .source)
		self.sortKey = try c.decodeIfPresent(Int.self, forKey: .sortKey) ?? 0
		self.lastUsedAt = try c.decodeIfPresent(Int64.self, forKey: .lastUsedAt) ?? 0
		self.addedIn = try c.decodeIfPresent(Int.self, forKey: .addedIn) ?? 0
		self.isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
		self.isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
	}
}

public struct CloudSyncSummary {
	public let gistId: String
	public let historyCount: Int
	public let favouritesCount: Int
}

public enum CloudSyncMerger {
	public static func merge(
		local: CloudSyncPayloadDTO,
		remote: CloudSyncPayloadDTO?,
		nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
		preferRemote: Bool = false
	) -> CloudSyncPayloadDTO {
		guard let remote else {
			var copy = local
			copy.updatedAt = nowMillis
			return copy
		}

		var historyMap: [Int64: CloudHistoryEntryDTO] = [:]
		for item in local.history { historyMap[item.mangaId] = item }
		for rem in remote.history {
			guard let loc = historyMap[rem.mangaId] else {
				historyMap[rem.mangaId] = rem
				continue
			}
			if preferRemote {
				historyMap[rem.mangaId] = rem.effectiveTimestamp >= loc.effectiveTimestamp ? rem : loc
			} else if rem.effectiveTimestamp > loc.effectiveTimestamp {
				historyMap[rem.mangaId] = rem
			} else if rem.effectiveTimestamp == loc.effectiveTimestamp {
				if rem.deletedAt == 0 && loc.deletedAt != 0 {
					historyMap[rem.mangaId] = rem
				} else if rem.percent > loc.percent {
					historyMap[rem.mangaId] = rem
				}
			}
		}

		var catMap: [Int: CloudCategoryEntryDTO] = [:]
		for item in local.categories { catMap[item.categoryId] = item }
		for rem in remote.categories {
			guard let loc = catMap[rem.categoryId] else {
				catMap[rem.categoryId] = rem
				continue
			}
			if rem.effectiveTimestamp > loc.effectiveTimestamp || preferRemote {
				catMap[rem.categoryId] = rem
			}
		}
		if catMap.isEmpty {
			catMap[1] = CloudCategoryEntryDTO(
				categoryId: 1,
				createdAt: nowMillis,
				deletedAt: 0,
				sortKey: 0,
				title: "Favorit",
				order: "NEWEST",
				track: true,
				isVisibleInLibrary: true
			)
		}

		var favMap: [String: CloudFavouriteEntryDTO] = [:]
		for item in local.favourites { favMap["\(item.mangaId)_\(item.categoryId)"] = item }
		for rem in remote.favourites {
			let key = "\(rem.mangaId)_\(rem.categoryId)"
			guard let loc = favMap[key] else {
				favMap[key] = rem
				continue
			}
			if rem.effectiveTimestamp > loc.effectiveTimestamp || (preferRemote && rem.effectiveTimestamp == loc.effectiveTimestamp) {
				favMap[key] = rem
			}
		}

		// Preserve Android sources list cleanly so iOS never wipes Android catalog states
		var sourceMap: [String: SourceBackupDTO] = [:]
		for s in local.sources { sourceMap[s.source] = s }
		for s in remote.sources {
			if let existing = sourceMap[s.source] {
				sourceMap[s.source] = s.lastUsedAt >= existing.lastUsedAt ? s : existing
			} else {
				sourceMap[s.source] = s
			}
		}

		return CloudSyncPayloadDTO(
			version: 1,
			updatedAt: nowMillis,
			history: historyMap.values.sorted { $0.mangaId < $1.mangaId },
			categories: catMap.values.sorted { $0.categoryId < $1.categoryId },
			favourites: favMap.values.sorted { ($0.mangaId, $0.categoryId) < ($1.mangaId, $1.categoryId) },
			sources: sourceMap.values.sorted { $0.source < $1.source }
		)
	}
}

public enum KeychainTokenStore {
	private static let service = "org.koitharu.kotatsu.ios.cloudsync"
	private static let account = "github_gist_token"

	public static func saveToken(_ token: String?) {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
		]
		SecItemDelete(query as CFDictionary)
		guard let clean = token?.trimmingCharacters(in: .whitespacesAndNewlines),
			  !clean.isEmpty,
			  let data = clean.data(using: .utf8) else { return }
		var addQuery = query
		addQuery[kSecValueData as String] = data
		SecItemAdd(addQuery as CFDictionary, nil)
	}

	public static func loadToken() -> String? {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecReturnData as String: true,
			kSecMatchLimit as String: kSecMatchLimitOne,
		]
		var result: AnyObject?
		let status = SecItemCopyMatching(query as CFDictionary, &result)
		guard status == errSecSuccess, let data = result as? Data else { return nil }
		return String(data: data, encoding: .utf8)
	}
}

public enum CloudSyncError: LocalizedError {
	case missingToken
	case unauthorized(Int)
	case apiError(String)

	public var errorDescription: String? {
		switch self {
		case .missingToken:
			return "Token GitHub belum diisi."
		case .unauthorized(let code):
			return "Token GitHub ditolak (HTTP \(code)). Pastikan izin 'gist' aktif."
		case .apiError(let msg):
			return msg
		}
	}
}

public final class GitHubGistSyncClient {
	public static let shared = GitHubGistSyncClient()
	public static let syncFileName = "kotatsu-sync-v1.json"
	private static let apiBase = "https://api.github.com"
	private static let gistDescription = "Kotatsu Cloud Sync (Progress, Favorites, Catalogs)"

	private init() {}

	public func verifyToken(_ token: String) async throws {
		let req = makeRequest(url: "\(Self.apiBase)/gists?per_page=1", method: "GET", token: token)
		let (_, http) = try await HttpClient.shared.perform(req)
		try ensureAuthorized(http)
		guard (200...299).contains(http.statusCode) else {
			throw CloudSyncError.apiError("GitHub API error (HTTP \(http.statusCode))")
		}
		if let scopes = http.value(forHTTPHeaderField: "X-OAuth-Scopes") {
			let parts = scopes.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
			if !parts.contains("gist") {
				throw CloudSyncError.apiError("Token GitHub tidak memiliki izin 'gist'.")
			}
		}
	}

	public func fetchGist(token: String, savedGistId: String?) async throws -> (gistId: String, payload: CloudSyncPayloadDTO)? {
		if let saved = savedGistId?.trimmingCharacters(in: .whitespacesAndNewlines), !saved.isEmpty {
			if let fetched = try await fetchGistById(token: token, gistId: saved) {
				return fetched
			}
		}
		guard let discovered = try await discoverSyncGistId(token: token) else { return nil }
		return try await fetchGistById(token: token, gistId: discovered)
	}

	public func uploadGist(token: String, gistId: String?, payload: CloudSyncPayloadDTO) async throws -> String {
		let encoder = JSONEncoder()
		let contentData = try encoder.encode(payload)
		let contentStr = String(data: contentData, encoding: .utf8) ?? "{}"

		var bodyDict: [String: Any] = [
			"files": [
				Self.syncFileName: [
					"content": contentStr,
				],
			],
		]
		let cleanId = gistId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		let method: String
		let url: String
		if cleanId.isEmpty {
			bodyDict["description"] = Self.gistDescription
			bodyDict["public"] = false
			method = "POST"
			url = "\(Self.apiBase)/gists"
		} else {
			method = "PATCH"
			url = "\(Self.apiBase)/gists/\(cleanId)"
		}

		var req = makeRequest(url: url, method: method, token: token)
		req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
		req.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)

		let (data, http) = try await HttpClient.shared.perform(req)
		try ensureAuthorized(http)
		guard (200...299).contains(http.statusCode) else {
			throw CloudSyncError.apiError("Gagal menyimpan Gist (HTTP \(http.statusCode))")
		}
		if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		   let id = root["id"] as? String, !id.isEmpty {
			return id
		}
		if !cleanId.isEmpty { return cleanId }
		throw CloudSyncError.apiError("Respon Gist tidak menyertakan ID.")
	}

	private func discoverSyncGistId(token: String) async throws -> String? {
		for page in 1...3 {
			let req = makeRequest(url: "\(Self.apiBase)/gists?per_page=100&page=\(page)", method: "GET", token: token)
			let (data, http) = try await HttpClient.shared.perform(req)
			try ensureAuthorized(http)
			guard (200...299).contains(http.statusCode),
				  let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
				throw CloudSyncError.apiError("Gagal membaca daftar Gist (HTTP \(http.statusCode))")
			}
			for obj in list {
				let isPublic = (obj["public"] as? Bool) ?? true
				let files = obj["files"] as? [String: Any]
				if !isPublic, files?[Self.syncFileName] != nil, let id = obj["id"] as? String, !id.isEmpty {
					return id
				}
			}
			if list.count < 100 { break }
		}
		return nil
	}

	private func fetchGistById(token: String, gistId: String) async throws -> (String, CloudSyncPayloadDTO)? {
		let req = makeRequest(url: "\(Self.apiBase)/gists/\(gistId)", method: "GET", token: token)
		let (data, http) = try await HttpClient.shared.perform(req)
		if http.statusCode == 404 { return nil }
		try ensureAuthorized(http)
		guard (200...299).contains(http.statusCode),
			  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
			  let files = root["files"] as? [String: Any],
			  let fileObj = files[Self.syncFileName] as? [String: Any] else {
			return nil
		}

		let contentStr: String
		if (fileObj["truncated"] as? Bool) == true, let rawUrl = fileObj["raw_url"] as? String {
			let rawReq = makeRequest(url: rawUrl, method: "GET", token: token)
			let (rawData, rawHttp) = try await HttpClient.shared.perform(rawReq)
			try ensureAuthorized(rawHttp)
			contentStr = String(data: rawData, encoding: .utf8) ?? ""
		} else {
			contentStr = (fileObj["content"] as? String) ?? ""
		}

		guard let payloadData = contentStr.data(using: .utf8) else { return nil }
		let decoded = try JSONDecoder().decode(CloudSyncPayloadDTO.self, from: payloadData)
		return (gistId, decoded)
	}

	private func makeRequest(url: String, method: String, token: String) -> URLRequest {
		var req = URLRequest(url: URL(string: url)!)
		req.httpMethod = method
		req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
		req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
		req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
		req.setValue("Kotatsu-iOS-CloudSync", forHTTPHeaderField: "User-Agent")
		return req
	}

	private func ensureAuthorized(_ http: HTTPURLResponse) throws {
		if http.statusCode == 401 || http.statusCode == 403 {
			throw CloudSyncError.unauthorized(http.statusCode)
		}
	}
}
