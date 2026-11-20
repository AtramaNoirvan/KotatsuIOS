import SwiftUI

public struct CatalogListView: View {
	let sourceID: CatalogSourceID

	@State private var items: [MangaItem] = []
	@State private var query: String = ""
	@State private var submittedQuery: String = ""
	@State private var sortMode: SortMode = .updated
	@State private var page: Int = 1
	@State private var isLoading: Bool = false
	@State private var hasMore: Bool = true
	@State private var errorMessage: String?

	private let columns = [
		GridItem(.adaptive(minimum: 145), spacing: 12),
	]

	public var body: some View {
		VStack(spacing: 0) {
			Picker("Urutkan", selection: $sortMode) {
				ForEach(SortMode.allCases) { mode in
					Text(mode.rawValue).tag(mode)
				}
			}
			.pickerStyle(.segmented)
			.padding(.horizontal)
			.padding(.vertical, 8)
			.onChange(of: sortMode) { _ in
				Task { await reload() }
			}

			if let errorMessage, items.isEmpty {
				VStack(spacing: 12) {
					Spacer()
					Image(systemName: "wifi.exclamationmark")
						.font(.system(size: 38))
						.foregroundStyle(.orange)
					Text("Gagal memuat katalog")
						.font(.headline)
					Text(errorMessage)
						.font(.caption)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)
						.padding(.horizontal, 24)
					Button("Coba Lagi") {
						Task { await reload() }
					}
					.buttonStyle(.borderedProminent)
					Spacer()
				}
			} else {
				ScrollView {
					LazyVGrid(columns: columns, spacing: 14) {
						ForEach(items) { manga in
							NavigationLink {
								TitleDetailView(initialManga: manga)
							} label: {
								TitlePosterCard(manga: manga)
							}
							.buttonStyle(.plain)
							.onAppear {
								if manga.id == items.last?.id && hasMore && !isLoading {
									Task { await loadNextPage() }
								}
							}
						}
					}
					.padding()

					if isLoading {
						ProgressView("Memuat...")
							.padding()
					}
				}
				.refreshable {
					await reload()
				}
			}
		}
		.navigationTitle(sourceID.displayName)
		.navigationBarTitleDisplayMode(.inline)
		.searchable(text: $query, prompt: "Cari judul di \(sourceID.displayName)")
		.onSubmit(of: .search) {
			submittedQuery = query
			Task { await reload() }
		}
		.onChange(of: query) { newValue in
			if newValue.isEmpty && !submittedQuery.isEmpty {
				submittedQuery = ""
				Task { await reload() }
			}
		}
		.task {
			if items.isEmpty {
				await reload()
			}
		}
	}

	private func reload() async {
		page = 1
		hasMore = true
		errorMessage = nil
		isLoading = true
		defer { isLoading = false }
		do {
			let fetched = try await SourceRegistry.source(for: sourceID).fetchList(
				page: 1,
				query: submittedQuery,
				sort: sortMode
			)
			items = fetched
			hasMore = !fetched.isEmpty
		} catch {
			if !Task.isCancelled {
				errorMessage = error.localizedDescription
			}
		}
	}

	private func loadNextPage() async {
		guard hasMore, !isLoading else { return }
		isLoading = true
		defer { isLoading = false }
		let nextPage = page + 1
		do {
			let fetched = try await SourceRegistry.source(for: sourceID).fetchList(
				page: nextPage,
				query: submittedQuery,
				sort: sortMode
			)
			let existingIds = Set(items.map(\.id))
			let unique = fetched.filter { !existingIds.contains($0.id) }
			if unique.isEmpty {
				hasMore = false
			} else {
				items.append(contentsOf: unique)
				page = nextPage
			}
		} catch {
			hasMore = false
		}
	}
}
