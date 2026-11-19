import SwiftUI

public struct TitleDetailView: View {
	@EnvironmentObject private var store: LibraryStore

	let initialManga: MangaItem

	@State private var manga: MangaItem
	@State private var isLoading: Bool = false
	@State private var errorMessage: String?
	@State private var reverseOrder: Bool = false
	@State private var cachedIds: Set<Int64> = []
	@State private var selectedChapterIndex: Int?

	public init(initialManga: MangaItem) {
		self.initialManga = initialManga
		self._manga = State(initialValue: initialManga)
	}

	private var displayedChapters: [(originalIndex: Int, chapter: ChapterItem)] {
		let indexed = manga.chapters.enumerated().map { ($0.offset, $0.element) }
		return reverseOrder ? indexed.reversed() : indexed
	}

	private var resumeChapterIndex: Int {
		if let history = store.historyRecord(for: manga.id),
		   let idx = manga.chapters.firstIndex(where: { $0.id == history.chapterId }) {
			return idx
		}
		return 0
	}

	public var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				HStack(alignment: .top, spacing: 14) {
					RemoteImageView(
						urlString: manga.coverUrl,
						headers: manga.sourceID?.defaultHeaders ?? [:]
					)
					.frame(width: 112, height: 162)
					.clipShape(RoundedRectangle(cornerRadius: 12))

					VStack(alignment: .leading, spacing: 8) {
						Text(manga.title)
							.font(.title3.bold())
							.fixedSize(horizontal: false, vertical: true)

						Text(manga.sourceID?.displayName ?? manga.sourceName)
							.font(.caption.weight(.semibold))
							.padding(.horizontal, 8)
							.padding(.vertical, 3)
							.background(Color.accentColor.opacity(0.15))
							.foregroundStyle(Color.accentColor)
							.clipShape(Capsule())

						if !manga.authors.isEmpty {
							Text(manga.authors.joined(separator: ", "))
								.font(.caption)
								.foregroundStyle(.secondary)
						}

						if let state = manga.state, !state.isEmpty {
							Text("Status: \(state)")
								.font(.caption)
								.foregroundStyle(.secondary)
						}

						Spacer(minLength: 4)

						HStack(spacing: 10) {
							Button {
								if !manga.chapters.isEmpty {
									selectedChapterIndex = resumeChapterIndex
								}
							} label: {
								Label(
									store.historyRecord(for: manga.id) != nil ? "Lanjut Baca" : "Mulai Baca",
									systemImage: "play.fill"
								)
								.font(.subheadline.bold())
								.frame(maxWidth: .infinity)
							}
							.buttonStyle(.borderedProminent)
							.disabled(manga.chapters.isEmpty)

							Button {
								store.toggleFavourite(manga: manga)
							} label: {
								Image(systemName: store.isFavourite(mangaId: manga.id) ? "heart.fill" : "heart")
									.foregroundStyle(store.isFavourite(mangaId: manga.id) ? .red : .primary)
									.frame(width: 34, height: 34)
							}
							.buttonStyle(.bordered)
						}
					}
				}

				if let desc = manga.description, !desc.isEmpty {
					Text(desc)
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}

				if !manga.tags.isEmpty {
					ScrollView(.horizontal, showsIndicators: false) {
						HStack(spacing: 6) {
							ForEach(manga.tags.prefix(12), id: \.self) { tag in
								Text(tag)
									.font(.caption2)
									.padding(.horizontal, 8)
									.padding(.vertical, 4)
									.background(Color.secondary.opacity(0.12))
									.clipShape(Capsule())
							}
						}
					}
				}

				Divider()

				HStack {
					Text("Daftar Chapter (\(manga.chapters.count))")
						.font(.headline)
					Spacer()
					Button {
						reverseOrder.toggle()
					} label: {
						Label(reverseOrder ? "Terbaru" : "Awal", systemImage: "arrow.up.arrow.down")
							.font(.caption)
					}
				}

				if isLoading && manga.chapters.isEmpty {
					ProgressView("Memuat daftar chapter...")
						.frame(maxWidth: .infinity)
						.padding()
				} else if let errorMessage, manga.chapters.isEmpty {
					VStack(spacing: 8) {
						Text(errorMessage)
							.font(.caption)
							.foregroundStyle(.red)
						Button("Coba Lagi") {
							Task { await loadDetails() }
						}
						.buttonStyle(.bordered)
					}
					.frame(maxWidth: .infinity)
					.padding()
				} else {
					LazyVStack(spacing: 0) {
						ForEach(displayedChapters, id: \.chapter.id) { entry in
							let isLastRead = store.historyRecord(for: manga.id)?.chapterId == entry.chapter.id
							Button {
								selectedChapterIndex = entry.originalIndex
							} label: {
								HStack {
									VStack(alignment: .leading, spacing: 2) {
										Text(entry.chapter.title)
											.font(.subheadline.weight(isLastRead ? .bold : .regular))
											.foregroundStyle(isLastRead ? Color.accentColor : .primary)
											.lineLimit(2)
											.multilineTextAlignment(.leading)
										if isLastRead {
											Text("Terakhir dibaca")
												.font(.caption2)
												.foregroundStyle(Color.accentColor)
										}
									}
									Spacer()
									if cachedIds.contains(entry.chapter.id) {
										Image(systemName: "arrow.down.circle.fill")
											.foregroundStyle(.green)
											.font(.caption)
									}
									Image(systemName: "chevron.right")
										.font(.caption2)
										.foregroundStyle(.tertiary)
								}
								.padding(.vertical, 10)
								.contentShape(Rectangle())
							}
							.buttonStyle(.plain)
							Divider()
						}
					}
				}
			}
			.padding()
		}
		.navigationTitle(manga.title)
		.navigationBarTitleDisplayMode(.inline)
		.fullScreenCover(
			isPresented: Binding(
				get: { selectedChapterIndex != nil },
				set: { if !$0 { selectedChapterIndex = nil; refreshOfflineBadges() } }
			)
		) {
			if let idx = selectedChapterIndex {
				if manga.isNovel {
					NovelReaderView(manga: manga, startChapterIndex: idx)
						.environmentObject(store)
				} else {
					ComicReaderView(manga: manga, startChapterIndex: idx)
						.environmentObject(store)
				}
			}
		}
		.task {
			refreshOfflineBadges()
			await loadDetails()
		}
	}

	private func refreshOfflineBadges() {
		if manga.isNovel {
			cachedIds = NovelExtrasStore.shared.cachedChapterIds(mangaId: manga.id)
		}
	}

	private func loadDetails() async {
		guard let src = SourceRegistry.source(named: manga.sourceName) else {
			errorMessage = "Sumber \(manga.sourceName) belum tersedia di Kotatsu iOS."
			return
		}
		isLoading = true
		errorMessage = nil
		defer { isLoading = false }
		do {
			let full = try await src.fetchDetails(manga: manga)
			manga = full
			refreshOfflineBadges()
		} catch {
			if !Task.isCancelled {
				errorMessage = error.localizedDescription
			}
		}
	}
}
