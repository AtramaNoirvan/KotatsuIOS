import SwiftUI

@main
public struct KotatsuIOSApp: App {
	@StateObject private var store = LibraryStore()

	public init() {}

	public var body: some Scene {
		WindowGroup {
			RootTabView()
				.environmentObject(store)
		}
	}
}

public struct RootTabView: View {
	@EnvironmentObject private var store: LibraryStore

	public var body: some View {
		TabView {
			ExploreTabView()
				.tabItem {
					Label("Jelajah", systemImage: "safari")
				}

			HistoryTabView()
				.tabItem {
					Label("Riwayat", systemImage: "clock.arrow.circlepath")
				}

			FavouritesTabView()
				.tabItem {
					Label("Favorit", systemImage: "heart")
				}

			StatsAndSettingsView()
				.tabItem {
					Label("Statistik", systemImage: "chart.bar.xaxis")
				}
		}
	}
}

private struct ContentModeHeaderPicker: View {
	@EnvironmentObject private var store: LibraryStore

	var body: some View {
		Picker("Mode Konten", selection: $store.contentMode) {
			ForEach(ContentMode.allCases) { mode in
				Label(mode.title, systemImage: mode.systemImage)
					.tag(mode)
			}
		}
		.pickerStyle(.segmented)
		.padding(.horizontal)
		.padding(.vertical, 8)
	}
}

private struct ExploreTabView: View {
	@EnvironmentObject private var store: LibraryStore

	var body: some View {
		NavigationStack {
			VStack(spacing: 0) {
				ContentModeHeaderPicker()
				List {
					Section(header: Text(store.contentMode == .novel ? "Katalog Light & Web Novel" : "Katalog Komik")) {
						ForEach(store.availableSourcesForCurrentMode) { src in
							NavigationLink {
								CatalogListView(sourceID: src)
							} label: {
								HStack(spacing: 12) {
									ZStack {
										RoundedRectangle(cornerRadius: 10)
											.fill(src.isNovel ? Color.indigo.opacity(0.18) : Color.blue.opacity(0.18))
											.frame(width: 42, height: 42)
										Image(systemName: src.isNovel ? "book.closed.fill" : "books.vertical.fill")
											.foregroundStyle(src.isNovel ? .indigo : .blue)
									}
									VStack(alignment: .leading, spacing: 2) {
										HStack(spacing: 6) {
											Text(src.displayName)
												.font(.headline)
											if src.isNsfw {
												Text("18+")
													.font(.caption2.bold())
													.padding(.horizontal, 5)
													.padding(.vertical, 1)
													.background(Color.red.opacity(0.2))
													.foregroundStyle(.red)
													.clipShape(Capsule())
											}
										}
										Text(src.defaultDomain)
											.font(.caption)
											.foregroundStyle(.secondary)
									}
									Spacer()
									Text(src.languageBadge)
										.font(.caption.bold())
										.padding(.horizontal, 8)
										.padding(.vertical, 4)
										.background(Color.secondary.opacity(0.15))
										.clipShape(Capsule())
								}
								.padding(.vertical, 4)
							}
						}
					}
				}
				.listStyle(.insetGrouped)
			}
			.navigationTitle("Kotatsu")
		}
	}
}

private struct HistoryTabView: View {
	@EnvironmentObject private var store: LibraryStore

	var body: some View {
		NavigationStack {
			VStack(spacing: 0) {
				ContentModeHeaderPicker()
				if store.filteredHistory.isEmpty {
					VStack(spacing: 12) {
						Spacer()
						Image(systemName: store.contentMode == .novel ? "text.book.closed" : "clock")
							.font(.system(size: 42))
							.foregroundStyle(.secondary)
						Text("Belum ada riwayat \(store.contentMode.title.lowercased())")
							.font(.headline)
						Text("Mulai membaca dari tab Jelajah atau tarik data dari GitHub Gist Cloud Sync.")
							.font(.subheadline)
							.foregroundStyle(.secondary)
							.multilineTextAlignment(.center)
							.padding(.horizontal, 32)
						Spacer()
					}
				} else {
					List {
						ForEach(store.filteredHistory) { item in
							NavigationLink {
								TitleDetailView(initialManga: item.manga)
							} label: {
								HStack(spacing: 12) {
									RemoteImageView(
										urlString: item.manga.coverUrl,
										headers: item.manga.sourceID?.defaultHeaders ?? [:]
									)
									.frame(width: 54, height: 76)
									.clipShape(RoundedRectangle(cornerRadius: 8))

									VStack(alignment: .leading, spacing: 4) {
										Text(item.manga.title)
											.font(.headline)
											.lineLimit(2)
										Text(item.manga.sourceID?.displayName ?? item.manga.sourceName)
											.font(.caption)
											.foregroundStyle(.secondary)
										if item.percent >= 0 {
											ProgressView(value: Double(min(max(item.percent, 0), 1)))
												.tint(.accentColor)
										}
									}
								}
								.padding(.vertical, 2)
							}
							.swipeActions(edge: .trailing) {
								Button(role: .destructive) {
									store.removeHistory(mangaId: item.mangaId)
								} label: {
									Label("Hapus", systemImage: "trash")
								}
							}
						}
					}
					.listStyle(.plain)
				}
			}
			.navigationTitle("Riwayat")
		}
	}
}

private struct FavouritesTabView: View {
	@EnvironmentObject private var store: LibraryStore

	private let columns = [
		GridItem(.adaptive(minimum: 112), spacing: 12),
	]

	var body: some View {
		NavigationStack {
			VStack(spacing: 0) {
				ContentModeHeaderPicker()
				if store.filteredFavourites.isEmpty {
					VStack(spacing: 12) {
						Spacer()
						Image(systemName: "heart")
							.font(.system(size: 42))
							.foregroundStyle(.secondary)
						Text("Belum ada favorit \(store.contentMode.title.lowercased())")
							.font(.headline)
						Text("Ketuk ikon hati di halaman detail judul untuk menyimpannya di sini.")
							.font(.subheadline)
							.foregroundStyle(.secondary)
							.multilineTextAlignment(.center)
							.padding(.horizontal, 32)
						Spacer()
					}
				} else {
					ScrollView {
						LazyVGrid(columns: columns, spacing: 14) {
							ForEach(store.filteredFavourites) { fav in
								NavigationLink {
									TitleDetailView(initialManga: fav.manga)
								} label: {
									TitlePosterCard(manga: fav.manga)
								}
								.buttonStyle(.plain)
							}
						}
						.padding()
					}
				}
			}
			.navigationTitle("Favorit")
		}
	}
}

public struct TitlePosterCard: View {
	let manga: MangaItem

	public var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			RemoteImageView(
				urlString: manga.coverUrl,
				headers: manga.sourceID?.defaultHeaders ?? [:]
			)
			.frame(height: 168)
			.frame(maxWidth: .infinity)
			.clipShape(RoundedRectangle(cornerRadius: 10))

			Text(manga.title)
				.font(.caption.weight(.semibold))
				.foregroundStyle(.primary)
				.lineLimit(2)
				.multilineTextAlignment(.leading)
		}
	}
}
