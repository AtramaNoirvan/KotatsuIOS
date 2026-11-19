import Foundation
import SwiftUI

public struct DayReadingActivity: Identifiable, Hashable {
	public var id: String { dateKey }
	public let dateKey: String
	public let shortLabel: String
	public let minutes: Int
	public let reachedGoal: Bool
}

public struct StreakSnapshot {
	public let currentStreakDays: Int
	public let longestStreakDays: Int
	public let todayMinutes: Int
	public let dailyGoalMinutes: Int
	public let last7Days: [DayReadingActivity]
}

public enum ReadingStreakEngine {
	private static let formatter: DateFormatter = {
		let df = DateFormatter()
		df.calendar = Calendar(identifier: .gregorian)
		df.locale = Locale(identifier: "en_US_POSIX")
		df.dateFormat = "yyyy-MM-dd"
		return df
	}()

	public static func dateKey(for date: Date, calendar: Calendar = .current) -> String {
		formatter.timeZone = calendar.timeZone
		return formatter.string(from: date)
	}

	public static func computeCurrentStreak(activeDateKeys: Set<String>, today: Date, calendar: Calendar = .current) -> Int {
		guard !activeDateKeys.isEmpty else { return 0 }
		let todayKey = dateKey(for: today, calendar: calendar)
		let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
		let yesterdayKey = dateKey(for: yesterday, calendar: calendar)

		var cursor: Date
		if activeDateKeys.contains(todayKey) {
			cursor = today
		} else if activeDateKeys.contains(yesterdayKey) {
			cursor = yesterday
		} else {
			return 0
		}

		var streak = 0
		while activeDateKeys.contains(dateKey(for: cursor, calendar: calendar)) {
			streak += 1
			guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
			cursor = prev
		}
		return streak
	}

	public static func computeLongestStreak(activeDateKeys: Set<String>, calendar: Calendar = .current) -> Int {
		formatter.timeZone = calendar.timeZone
		let dates = activeDateKeys.compactMap { formatter.date(from: $0) }.sorted()
		guard !dates.isEmpty else { return 0 }
		var best = 1
		var run = 1
		for i in 1..<dates.count {
			let diff = calendar.dateComponents([.day], from: dates[i - 1], to: dates[i]).day ?? 0
			if diff == 1 {
				run += 1
				best = max(best, run)
			} else if diff > 1 {
				run = 1
			}
		}
		return best
	}

	public static func buildLast7Days(
		dailySeconds: [String: Int64],
		today: Date,
		goalMinutes: Int,
		calendar: Calendar = .current
	) -> [DayReadingActivity] {
		let dayNames = ["Min", "Sen", "Sel", "Rab", "Kam", "Jum", "Sab"]
		return (0...6).reversed().map { offset in
			let d = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
			let key = dateKey(for: d, calendar: calendar)
			let mins = Int((dailySeconds[key] ?? 0) / 60)
			let weekday = calendar.component(.weekday, from: d) // 1 = Sun ... 7 = Sat
			let label = dayNames[(weekday - 1) % 7]
			return DayReadingActivity(
				dateKey: key,
				shortLabel: label,
				minutes: mins,
				reachedGoal: mins >= goalMinutes
			)
		}
	}
}

private struct PersistedLibraryState: Codable {
	var history: [HistoryRecord] = []
	var favourites: [FavouriteRecord] = []
	var categories: [CloudCategoryEntryDTO] = []
	var sources: [SourceBackupDTO] = []
	var dailyReadingSeconds: [String: Int64] = [:]
	var dailyGoalMinutes: Int = 30
	var bestStreakDays: Int = 0
}

@MainActor
public final class LibraryStore: ObservableObject {
	@Published public var contentMode: ContentMode = .comic {
		didSet { UserDefaults.standard.set(contentMode.rawValue, forKey: "content_mode") }
	}
	@Published public var showNsfwSources: Bool = false {
		didSet { UserDefaults.standard.set(showNsfwSources, forKey: "show_nsfw_sources") }
	}
	@Published public private(set) var history: [HistoryRecord] = []
	@Published public private(set) var favourites: [FavouriteRecord] = []
	@Published public private(set) var streakSnapshot: StreakSnapshot
	@Published public private(set) var isSyncing: Bool = false
	@Published public var lastSyncStatus: String = "Belum disinkronkan"
	@Published public var gistId: String {
		didSet { UserDefaults.standard.set(gistId, forKey: "cloud_sync_gist_id") }
	}

	private var persistedCategories: [CloudCategoryEntryDTO] = []
	private var persistedSources: [SourceBackupDTO] = []
	private var dailyReadingSeconds: [String: Int64] = [:]
	private var dailyGoalMinutes: Int = 30
	private var bestStreakDays: Int = 0

	private let stateURL: URL

	public init() {
		let fm = FileManager.default
		let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
		try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
		self.stateURL = dir.appendingPathComponent("kotatsu_library_v1.json")
		self.gistId = UserDefaults.standard.string(forKey: "cloud_sync_gist_id") ?? ""
		self.streakSnapshot = StreakSnapshot(
			currentStreakDays: 0,
			longestStreakDays: 0,
			todayMinutes: 0,
			dailyGoalMinutes: 30,
			last7Days: []
		)
		if let rawMode = UserDefaults.standard.string(forKey: "content_mode"),
		   let mode = ContentMode(rawValue: rawMode) {
			self.contentMode = mode
		}
		self.showNsfwSources = UserDefaults.standard.bool(forKey: "show_nsfw_sources")
		loadFromDisk()
		refreshStreak()
	}

	public var availableSourcesForCurrentMode: [CatalogSourceID] {
		CatalogSourceID.allCases.filter { src in
			let matchesMode = (contentMode == .novel) ? src.isNovel : !src.isNovel
			let matchesNsfw = showNsfwSources || !src.isNsfw
			return matchesMode && matchesNsfw
		}
	}

	public var filteredHistory: [HistoryRecord] {
		history
			.filter { $0.deletedAt == 0 && $0.manga.isNovel == (contentMode == .novel) }
			.sorted { $0.updatedAt > $1.updatedAt }
	}

	public var filteredFavourites: [FavouriteRecord] {
		favourites
			.filter { $0.deletedAt == 0 && $0.manga.isNovel == (contentMode == .novel) }
			.sorted { $0.createdAt > $1.createdAt }
	}

	public func isFavourite(mangaId: Int64) -> Bool {
		favourites.contains { $0.mangaId == mangaId && $0.deletedAt == 0 }
	}

	public func toggleFavourite(manga: MangaItem) {
		let now = Int64(Date().timeIntervalSince1970 * 1000)
		let defaultCategoryId: Int64 = Int64(persistedCategories.first(where: { $0.deletedAt == 0 })?.categoryId ?? 1)
		if let idx = favourites.firstIndex(where: { $0.mangaId == manga.id && $0.deletedAt == 0 }) {
			favourites[idx].deletedAt = now
		} else {
			if persistedCategories.isEmpty {
				persistedCategories = [
					CloudCategoryEntryDTO(
						categoryId: 1,
						createdAt: now,
						deletedAt: 0,
						sortKey: 0,
						title: "Favorit",
						order: "NEWEST",
						track: true,
						isVisibleInLibrary: true
					),
				]
			}
			favourites.removeAll { $0.mangaId == manga.id && $0.categoryId == defaultCategoryId }
			favourites.insert(
				FavouriteRecord(
					mangaId: manga.id,
					categoryId: defaultCategoryId,
					sortKey: 0,
					isPinned: false,
					createdAt: now,
					deletedAt: 0,
					manga: manga
				),
				at: 0
			)
		}
		saveToDisk()
	}

	public func historyRecord(for mangaId: Int64) -> HistoryRecord? {
		history.first { $0.mangaId == mangaId && $0.deletedAt == 0 }
	}

	public func recordProgress(
		manga: MangaItem,
		chapterId: Int64,
		page: Int,
		scroll: Float,
		percent: Float,
		chaptersCount: Int
	) {
		let now = Int64(Date().timeIntervalSince1970 * 1000)
		if let idx = history.firstIndex(where: { $0.mangaId == manga.id }) {
			history[idx].updatedAt = now
			history[idx].deletedAt = 0
			history[idx].chapterId = chapterId
			history[idx].page = page
			history[idx].scroll = scroll
			history[idx].percent = percent
			history[idx].chaptersCount = chaptersCount
			history[idx].manga = manga
		} else {
			history.insert(
				HistoryRecord(
					mangaId: manga.id,
					createdAt: now,
					updatedAt: now,
					deletedAt: 0,
					chapterId: chapterId,
					page: page,
					scroll: scroll,
					percent: percent,
					chaptersCount: chaptersCount,
					manga: manga
				),
				at: 0
			)
		}
		saveToDisk()
	}

	public func removeHistory(mangaId: Int64) {
		let now = Int64(Date().timeIntervalSince1970 * 1000)
		if let idx = history.firstIndex(where: { $0.mangaId == mangaId }) {
			history[idx].deletedAt = now
			history[idx].updatedAt = now
			saveToDisk()
		}
	}

	public func recordReadingDuration(seconds: Int64) {
		guard seconds >= 5 else { return }
		let todayKey = ReadingStreakEngine.dateKey(for: Date())
		dailyReadingSeconds[todayKey, default: 0] += seconds
		let activeKeys = Set(dailyReadingSeconds.filter { $0.value >= 5 }.keys)
		bestStreakDays = max(bestStreakDays, ReadingStreakEngine.computeLongestStreak(activeDateKeys: activeKeys))
		refreshStreak()
		saveToDisk()
	}

	public func setDailyGoalMinutes(_ minutes: Int) {
		dailyGoalMinutes = min(max(5, minutes), 300)
		refreshStreak()
		saveToDisk()
	}

	public func refreshStreak() {
		let now = Date()
		let activeKeys = Set(dailyReadingSeconds.filter { $0.value >= 5 }.keys)
		let current = ReadingStreakEngine.computeCurrentStreak(activeDateKeys: activeKeys, today: now)
		let longest = max(bestStreakDays, ReadingStreakEngine.computeLongestStreak(activeDateKeys: activeKeys), current)
		let todayKey = ReadingStreakEngine.dateKey(for: now)
		let todayMins = Int((dailyReadingSeconds[todayKey] ?? 0) / 60)
		streakSnapshot = StreakSnapshot(
			currentStreakDays: current,
			longestStreakDays: longest,
			todayMinutes: todayMins,
			dailyGoalMinutes: dailyGoalMinutes,
			last7Days: ReadingStreakEngine.buildLast7Days(
				dailySeconds: dailyReadingSeconds,
				today: now,
				goalMinutes: dailyGoalMinutes
			)
		)
	}

	// MARK: - GitHub Gist Cloud Sync (100% compatible with Kotatsu Android v9.5.3)

	public func syncWithCloud(preferRemote: Bool = false) async throws -> CloudSyncSummary {
		guard let token = KeychainTokenStore.loadToken(), !token.isEmpty else {
			throw CloudSyncError.missingToken
		}
		isSyncing = true
		defer { isSyncing = false }

		let localPayload = buildLocalPayload()
		let remotePair = try await GitHubGistSyncClient.shared.fetchGist(token: token, savedGistId: gistId)
		let merged = CloudSyncMerger.merge(
			local: localPayload,
			remote: remotePair?.payload,
			preferRemote: preferRemote
		)
		let finalGistId = try await GitHubGistSyncClient.shared.uploadGist(
			token: token,
			gistId: remotePair?.gistId ?? (gistId.isEmpty ? nil : gistId),
			payload: merged
		)
		applyMergedPayload(merged)
		gistId = finalGistId
		let activeHistory = merged.history.filter { $0.deletedAt == 0 }.count
		let activeFavs = merged.favourites.filter { $0.deletedAt == 0 }.count
		let df = DateFormatter()
		df.timeStyle = .short
		lastSyncStatus = "Tersinkron \(df.string(from: Date())) (\(activeHistory) riwayat, \(activeFavs) favorit)"
		return CloudSyncSummary(gistId: finalGistId, historyCount: activeHistory, favouritesCount: activeFavs)
	}

	private func buildLocalPayload() -> CloudSyncPayloadDTO {
		let historyDTOs = history.map { h in
			CloudHistoryEntryDTO(
				mangaId: h.mangaId,
				createdAt: h.createdAt,
				updatedAt: h.updatedAt,
				deletedAt: h.deletedAt,
				chapterId: h.chapterId,
				page: h.page,
				scroll: h.scroll,
				percent: h.percent,
				chaptersCount: h.chaptersCount,
				manga: MangaBackupDTO(from: h.manga)
			)
		}
		let favDTOs = favourites.map { f in
			CloudFavouriteEntryDTO(
				mangaId: f.mangaId,
				categoryId: f.categoryId,
				sortKey: f.sortKey,
				isPinned: f.isPinned,
				createdAt: f.createdAt,
				deletedAt: f.deletedAt,
				manga: MangaBackupDTO(from: f.manga)
			)
		}
		return CloudSyncPayloadDTO(
			version: 1,
			updatedAt: Int64(Date().timeIntervalSince1970 * 1000),
			history: historyDTOs,
			categories: persistedCategories,
			favourites: favDTOs,
			sources: persistedSources
		)
	}

	private func applyMergedPayload(_ payload: CloudSyncPayloadDTO) {
		self.history = payload.history.map { h in
			HistoryRecord(
				mangaId: h.mangaId,
				createdAt: h.createdAt,
				updatedAt: h.updatedAt,
				deletedAt: h.deletedAt,
				chapterId: h.chapterId,
				page: h.page,
				scroll: h.scroll,
				percent: h.percent,
				chaptersCount: h.chaptersCount,
				manga: h.manga.toMangaItem()
			)
		}
		self.favourites = payload.favourites.map { f in
			FavouriteRecord(
				mangaId: f.mangaId,
				categoryId: f.categoryId,
				sortKey: f.sortKey,
				isPinned: f.isPinned,
				createdAt: f.createdAt,
				deletedAt: f.deletedAt,
				manga: f.manga.toMangaItem()
			)
		}
		self.persistedCategories = payload.categories
		self.persistedSources = payload.sources
		saveToDisk()
	}

	private func loadFromDisk() {
		guard let data = try? Data(contentsOf: stateURL),
			  let state = try? JSONDecoder().decode(PersistedLibraryState.self, from: data) else { return }
		self.history = state.history
		self.favourites = state.favourites
		self.persistedCategories = state.categories
		self.persistedSources = state.sources
		self.dailyReadingSeconds = state.dailyReadingSeconds
		self.dailyGoalMinutes = state.dailyGoalMinutes
		self.bestStreakDays = state.bestStreakDays
	}

	private func saveToDisk() {
		let state = PersistedLibraryState(
			history: history,
			favourites: favourites,
			categories: persistedCategories,
			sources: persistedSources,
			dailyReadingSeconds: dailyReadingSeconds,
			dailyGoalMinutes: dailyGoalMinutes,
			bestStreakDays: bestStreakDays
		)
		if let data = try? JSONEncoder().encode(state) {
			try? data.write(to: stateURL, options: .atomic)
		}
	}
}
