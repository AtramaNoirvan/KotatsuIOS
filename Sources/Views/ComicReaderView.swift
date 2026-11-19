import SwiftUI
import UIKit

public struct ComicReaderView: View {
	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject private var store: LibraryStore

	let manga: MangaItem
	let startChapterIndex: Int

	@State private var chapterIndex: Int
	@State private var pages: [ComicPageItem] = []
	@State private var isLoading: Bool = false
	@State private var errorMessage: String?
	@State private var showChrome: Bool = true
	@State private var zoomScale: CGFloat = 1.0
	@State private var showQuickTranslate: Bool = false
	@State private var showChapterList: Bool = false
	@State private var sessionStart: Date = Date()

	public init(manga: MangaItem, startChapterIndex: Int) {
		self.manga = manga
		self.startChapterIndex = startChapterIndex
		self._chapterIndex = State(initialValue: startChapterIndex)
	}

	private var currentChapter: ChapterItem? {
		manga.chapters.indices.contains(chapterIndex) ? manga.chapters[chapterIndex] : nil
	}

	public var body: some View {
		ZStack {
			Color.black.ignoresSafeArea()

			if isLoading && pages.isEmpty {
				ProgressView("Memuat halaman komik...")
					.tint(.white)
					.foregroundStyle(.white)
			} else if let errorMessage, pages.isEmpty {
				VStack(spacing: 12) {
					Text("Gagal memuat chapter")
						.font(.headline)
						.foregroundStyle(.white)
					Text(errorMessage)
						.font(.caption)
						.foregroundStyle(.gray)
						.multilineTextAlignment(.center)
						.padding(.horizontal, 24)
					Button("Coba Lagi") {
						Task { await loadCurrentChapter() }
					}
					.buttonStyle(.borderedProminent)
				}
			} else {
				ScrollView {
					LazyVStack(spacing: 2) {
						ForEach(pages) { page in
							RemoteImageView(
								urlString: page.url,
								headers: page.headers,
								contentMode: .fit
							)
							.frame(maxWidth: .infinity)
						}
					}
					.scaleEffect(zoomScale)
				}
				.gesture(
					MagnificationGesture()
						.onChanged { value in
							zoomScale = min(max(1.0, value), 3.0)
						}
				)
				.onTapGesture(count: 2) {
					withAnimation(.easeInOut(duration: 0.2)) {
						zoomScale = zoomScale > 1.05 ? 1.0 : 2.0
					}
				}
				.onTapGesture {
					withAnimation(.easeInOut(duration: 0.18)) {
						showChrome.toggle()
					}
				}
			}

			if showChrome {
				VStack {
					topBar
					Spacer()
					bottomBar
				}
				.transition(.opacity)
			}
		}
		.statusBarHidden(!showChrome)
		.sheet(isPresented: $showQuickTranslate) {
			ComicQuickTranslateSheet()
		}
		.sheet(isPresented: $showChapterList) {
			NavigationStack {
				List {
					ForEach(Array(manga.chapters.enumerated()), id: \.element.id) { idx, ch in
						Button {
							showChapterList = false
							chapterIndex = idx
						} label: {
							HStack {
								Text(ch.title)
									.foregroundStyle(idx == chapterIndex ? Color.accentColor : .primary)
								Spacer()
								if idx == chapterIndex {
									Image(systemName: "checkmark")
										.foregroundStyle(Color.accentColor)
								}
							}
						}
					}
				}
				.navigationTitle("Daftar Chapter")
				.navigationBarTitleDisplayMode(.inline)
				.toolbar {
					ToolbarItem(placement: .cancellationAction) {
						Button("Tutup") { showChapterList = false }
					}
				}
			}
		}
		.task(id: chapterIndex) {
			await loadCurrentChapter()
		}
		.onAppear {
			sessionStart = Date()
		}
		.onDisappear {
			let elapsed = Int64(Date().timeIntervalSince(sessionStart))
			store.recordReadingDuration(seconds: elapsed)
		}
	}

	private var topBar: some View {
		HStack(spacing: 12) {
			Button {
				dismiss()
			} label: {
				Image(systemName: "chevron.left")
					.font(.headline)
					.frame(width: 36, height: 36)
			}

			VStack(alignment: .leading, spacing: 2) {
				Text(manga.title)
					.font(.subheadline.bold())
					.lineLimit(1)
				Text(currentChapter?.title ?? "")
					.font(.caption)
					.foregroundStyle(.white.opacity(0.75))
					.lineLimit(1)
			}

			Spacer()

			Button {
				showQuickTranslate = true
			} label: {
				Image(systemName: "globe")
					.frame(width: 36, height: 36)
			}

			Button {
				showChapterList = true
			} label: {
				Image(systemName: "list.bullet")
					.frame(width: 36, height: 36)
			}
		}
		.foregroundStyle(.white)
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
		.background(.ultraThinMaterial.opacity(0.92))
	}

	private var bottomBar: some View {
		HStack(spacing: 12) {
			Button {
				if chapterIndex > 0 { chapterIndex -= 1 }
			} label: {
				Label("Sebelumnya", systemImage: "chevron.left")
					.font(.caption.bold())
					.frame(maxWidth: .infinity)
			}
			.buttonStyle(.borderedProminent)
			.disabled(chapterIndex <= 0)

			Text("\(chapterIndex + 1)/\(max(1, manga.chapters.count))")
				.font(.caption.monospacedDigit())
				.foregroundStyle(.white)

			Button {
				if chapterIndex + 1 < manga.chapters.count { chapterIndex += 1 }
			} label: {
				Label("Berikutnya", systemImage: "chevron.right")
					.font(.caption.bold())
					.frame(maxWidth: .infinity)
			}
			.buttonStyle(.borderedProminent)
			.disabled(chapterIndex + 1 >= manga.chapters.count)
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
		.background(.ultraThinMaterial.opacity(0.92))
	}

	private func loadCurrentChapter() async {
		guard let chapter = currentChapter,
			  let source = SourceRegistry.source(named: manga.sourceName) else { return }
		isLoading = true
		errorMessage = nil
		pages = []
		zoomScale = 1.0
		defer { isLoading = false }
		do {
			let payload = try await source.fetchChapterPayload(chapter: chapter)
			if case .comicPages(let loadedPages) = payload {
				pages = loadedPages
				let pct = manga.chapters.isEmpty ? 0 : Float(chapterIndex + 1) / Float(manga.chapters.count)
				store.recordProgress(
					manga: manga,
					chapterId: chapter.id,
					page: 0,
					scroll: 0,
					percent: pct,
					chaptersCount: manga.chapters.count
				)
			}
		} catch {
			if !Task.isCancelled {
				errorMessage = error.localizedDescription
			}
		}
	}
}

private struct ComicQuickTranslateSheet: View {
	@Environment(\.dismiss) private var dismiss

	@State private var inputText: String = ""
	@State private var targetLang: String = "id"
	@State private var outputText: String = ""
	@State private var isTranslating: Bool = false

	private var selectableLanguages: [TargetLanguage] {
		NovelTranslator.supportedLanguages.filter { $0.code != NovelTranslator.langOff }
	}

	var body: some View {
		NavigationStack {
			Form {
				Section("Bahasa Tujuan") {
					Picker("Terjemahkan ke", selection: $targetLang) {
						ForEach(selectableLanguages) { lang in
							Text("\(lang.label) [\(lang.badge)]").tag(lang.code)
						}
					}
				}

				Section("Teks Dialog Komik (EN / JP / KR / CN)") {
					TextEditor(text: $inputText)
						.frame(minHeight: 90)
					Button {
						Task { await runTranslate() }
					} label: {
						if isTranslating {
							ProgressView()
								.frame(maxWidth: .infinity)
						} else {
							Label("Terjemahkan Sekarang", systemImage: "globe")
								.frame(maxWidth: .infinity)
						}
					}
					.buttonStyle(.borderedProminent)
					.disabled(isTranslating || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
				}

				if !outputText.isEmpty {
					Section("Hasil Terjemahan") {
						Text(outputText)
							.textSelection(.enabled)
						Button {
							UIPasteboard.general.string = outputText
						} label: {
							Label("Salin Hasil", systemImage: "doc.on.doc")
						}
					}
				}
			}
			.navigationTitle("Terjemahkan Komik")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Tutup") { dismiss() }
				}
			}
		}
	}

	private func runTranslate() async {
		isTranslating = true
		defer { isTranslating = false }
		do {
			outputText = try await NovelTranslator.shared.translateQuickText(inputText, targetLang: targetLang)
		} catch {
			outputText = "Gagal menerjemahkan: \(error.localizedDescription)"
		}
	}
}
