import SwiftUI

public enum NovelThemePreset: Int, CaseIterable, Identifiable {
	case midnight = 0
	case sepia = 1
	case light = 2
	case amoled = 3

	public var id: Int { rawValue }

	public var name: String {
		switch self {
		case .midnight: return "Gelap (Midnight Slate)"
		case .sepia: return "Sepia (Kertas Klasik)"
		case .light: return "Terang (Kertas Putih)"
		case .amoled: return "Hitam Pekat (AMOLED)"
		}
	}

	public var background: Color {
		switch self {
		case .midnight: return Color(red: 0.067, green: 0.086, blue: 0.133)
		case .sepia: return Color(red: 0.957, green: 0.925, blue: 0.847)
		case .light: return Color(red: 0.973, green: 0.980, blue: 0.988)
		case .amoled: return .black
		}
	}

	public var text: Color {
		switch self {
		case .midnight: return Color(red: 0.886, green: 0.910, blue: 0.941)
		case .sepia: return Color(red: 0.176, green: 0.133, blue: 0.094)
		case .light: return Color(red: 0.059, green: 0.090, blue: 0.165)
		case .amoled: return Color(red: 0.831, green: 0.831, blue: 0.847)
		}
	}

	public var secondaryText: Color {
		switch self {
		case .midnight: return Color(red: 0.580, green: 0.639, blue: 0.722)
		case .sepia: return Color(red: 0.431, green: 0.353, blue: 0.278)
		case .light: return Color(red: 0.278, green: 0.333, blue: 0.412)
		case .amoled: return Color(red: 0.443, green: 0.443, blue: 0.478)
		}
	}

	public var ttsHighlight: Color {
		switch self {
		case .sepia: return Color.orange.opacity(0.24)
		default: return Color.blue.opacity(0.24)
		}
	}
}

public struct NovelReaderView: View {
	@Environment(\.dismiss) private var dismiss
	@EnvironmentObject private var store: LibraryStore

	let manga: MangaItem
	let startChapterIndex: Int

	@AppStorage("novel_target_lang") private var targetLang: String = NovelTranslator.langOff
	@AppStorage("novel_bilingual") private var isBilingualMode: Bool = false
	@AppStorage("novel_font_size") private var fontSize: Double = 18
	@AppStorage("novel_serif") private var isSerifFont: Bool = true
	@AppStorage("novel_theme_index") private var themeRaw: Int = 0

	@StateObject private var speech = NovelSpeechEngine()

	@State private var chapterIndex: Int
	@State private var chapterTitle: String = ""
	@State private var originalParagraphs: [String] = []
	@State private var translatedParagraphs: [String]?
	@State private var loadedFromOffline: Bool = false
	@State private var translationProgress: String?
	@State private var isLoading: Bool = false
	@State private var errorMessage: String?

	@State private var glossaryRules: [GlossaryRule] = []
	@State private var bookmarks: [NovelBookmark] = []
	@State private var cachedIds: Set<Int64> = []

	@State private var searchQuery: String = ""
	@State private var isImmersive: Bool = false
	@State private var autoScrollActive: Bool = false
	@State private var autoScrollPaused: Bool = false
	@State private var autoScrollParagraphCursor: Int = 0
	@State private var autoScrollSpeed: Int = 2
	@State private var autoScrollTask: Task<Void, Never>?
	@State private var translateTask: Task<Void, Never>?
	@State private var batchDownloadStatus: String?
	@State private var sessionStart: Date = Date()
	@State private var statusMessage: String?
	@State private var autoResumeTtsOnNextLoad: Bool = false

	@State private var activeSheet: NovelSheet?

	private enum NovelSheet: Int, Identifiable {
		case translate
		case appearance
		case chapters
		case glossary
		case bookmarks
		case search
		case offline

		var id: Int { rawValue }
	}

	public init(manga: MangaItem, startChapterIndex: Int) {
		self.manga = manga
		self.startChapterIndex = startChapterIndex
		self._chapterIndex = State(initialValue: startChapterIndex)
	}

	private var theme: NovelThemePreset {
		NovelThemePreset(rawValue: themeRaw) ?? .midnight
	}

	private var currentChapter: ChapterItem? {
		manga.chapters.indices.contains(chapterIndex) ? manga.chapters[chapterIndex] : nil
	}

	private var displayParagraphs: [String] {
		let base = (targetLang != NovelTranslator.langOff ? translatedParagraphs : nil) ?? originalParagraphs
		return NovelGlossaryEngine.apply(paragraphs: base, rules: glossaryRules)
	}

	private var activeSpeechLocale: String {
		if targetLang != NovelTranslator.langOff {
			return NovelTranslator.findLanguage(targetLang).speechLocale
		}
		return manga.sourceID?.isForeignLanguage == true ? "en-US" : "id-ID"
	}

	public var body: some View {
		ZStack(alignment: .topTrailing) {
			theme.background.ignoresSafeArea()

			VStack(spacing: 0) {
				if !isImmersive {
					headerBar
				}

				if isLoading || batchDownloadStatus != nil {
					ProgressView()
						.progressViewStyle(.linear)
				}

				if let batchDownloadStatus {
					Text(batchDownloadStatus)
						.font(.caption)
						.foregroundStyle(.white)
						.frame(maxWidth: .infinity)
						.padding(.vertical, 6)
						.background(Color.blue.opacity(0.85))
				}

				if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
					HStack {
						Text("Cari: \"\(searchQuery)\" (\(searchMatchCount) cocok)")
							.font(.caption.bold())
							.foregroundStyle(.yellow)
						Spacer()
						Button("Tutup") { searchQuery = "" }
							.font(.caption.bold())
							.foregroundStyle(.white)
					}
					.padding(.horizontal, 14)
					.padding(.vertical, 6)
					.background(Color.black.opacity(0.75))
				}

				ScrollViewReader { proxy in
					ScrollView {
						VStack(alignment: .leading, spacing: 14) {
							translationBanner

							Text(chapterTitle)
								.font(.system(size: fontSize + 4, weight: .bold, design: isSerifFont ? .serif : .default))
								.foregroundStyle(theme.text)
								.padding(.bottom, 4)

							if let errorMessage, originalParagraphs.isEmpty {
								VStack(spacing: 10) {
									Text(errorMessage)
										.font(.subheadline)
										.foregroundStyle(.red)
									Button("Coba Lagi") {
										Task { await loadChapter(index: chapterIndex, autoStartTts: false) }
									}
									.buttonStyle(.borderedProminent)
								}
								.frame(maxWidth: .infinity)
								.padding(.vertical, 24)
							} else {
								LazyVStack(alignment: .leading, spacing: 14) {
									ForEach(Array(displayParagraphs.enumerated()), id: \.offset) { idx, para in
										paragraphView(index: idx, text: para)
											.id(idx)
									}
								}
							}

							Spacer(minLength: 40)
						}
						.padding(.horizontal, 20)
						.padding(.top, 16)
					}
					.onChange(of: speech.currentParagraphIndex) { newIndex in
						if speech.isActive {
							withAnimation(.easeInOut(duration: 0.25)) {
								proxy.scrollTo(newIndex, anchor: .center)
							}
						}
					}
					.onChange(of: autoScrollParagraphCursor) { newIndex in
						if autoScrollActive {
							withAnimation(.easeInOut(duration: 0.45)) {
								proxy.scrollTo(newIndex, anchor: .top)
							}
						}
					}
				}

				if speech.isActive {
					ttsMiniBar
				}

				if autoScrollActive {
					autoScrollMiniBar
				}

				if !isImmersive {
					bottomBar
				}
			}

			if isImmersive {
				Button("Tampilkan Menu") {
					withAnimation { isImmersive = false }
				}
				.font(.caption.bold())
				.buttonStyle(.borderedProminent)
				.padding(14)
			}
		}
		.statusBarHidden(isImmersive)
		.sheet(item: $activeSheet) { sheet in
			sheetContent(for: sheet)
		}
		.alert("Info", isPresented: Binding(
			get: { statusMessage != nil },
			set: { if !$0 { statusMessage = nil } }
		)) {
			Button("OK", role: .cancel) {}
		} message: {
			Text(statusMessage ?? "")
		}
		.onAppear {
			sessionStart = Date()
			glossaryRules = NovelExtrasStore.shared.loadGlossary(mangaId: manga.id)
			bookmarks = NovelExtrasStore.shared.loadBookmarks(mangaId: manga.id)
			cachedIds = NovelExtrasStore.shared.cachedChapterIds(mangaId: manga.id)
			speech.onChapterFinished = {
				if chapterIndex + 1 < manga.chapters.count {
					autoResumeTtsOnNextLoad = true
					chapterIndex += 1
				} else {
					speech.stop()
				}
			}
		}
		.onDisappear {
			speech.stop()
			stopAutoScroll()
			translateTask?.cancel()
			let elapsed = Int64(Date().timeIntervalSince(sessionStart))
			store.recordReadingDuration(seconds: elapsed)
		}
		.task(id: chapterIndex) {
			let shouldResumeTts = autoResumeTtsOnNextLoad
			autoResumeTtsOnNextLoad = false
			await loadChapter(index: chapterIndex, autoStartTts: shouldResumeTts)
		}
	}

	// MARK: - Subviews

	private var headerBar: some View {
		HStack(spacing: 8) {
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
				let est = NovelTranslator.estimateReadingMinutes(displayParagraphs)
				Text("\(currentChapter?.title ?? "") • ~\(est) mnt")
					.font(.caption2)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}

			Spacer()

			Button {
				activeSheet = .translate
			} label: {
				Text(NovelTranslator.findLanguage(targetLang).badge)
					.font(.caption.bold())
					.padding(.horizontal, 8)
					.padding(.vertical, 5)
					.background(Color.blue.opacity(0.2))
					.clipShape(Capsule())
			}

			Button {
				toggleTtsQuick()
			} label: {
				Image(systemName: speech.isActive ? "speaker.wave.3.fill" : "speaker.wave.2")
					.frame(width: 34, height: 34)
			}

			Menu {
				Button {
					if autoScrollActive { stopAutoScroll() } else { startAutoScroll() }
				} label: {
					Label(autoScrollActive ? "Hentikan Auto-Scroll" : "Auto-Scroll Halus", systemImage: "arrow.down.to.line")
				}
				Button { activeSheet = .offline } label: {
					Label("Simpan & Unduh Offline", systemImage: "arrow.down.circle")
				}
				Button { activeSheet = .glossary } label: {
					Label("Glosarium Karakter (\(glossaryRules.count))", systemImage: "character.book.closed")
				}
				Button { activeSheet = .search } label: {
					Label("Cari Kata di Chapter", systemImage: "magnifyingglass")
				}
				Button { activeSheet = .bookmarks } label: {
					Label("Tanda & Kutipan (\(bookmarks.count))", systemImage: "bookmark")
				}
				Button { activeSheet = .appearance } label: {
					Label("Tampilan, Font & Tema", systemImage: "textformat.size")
				}
				Button {
					withAnimation { isImmersive.toggle() }
				} label: {
					Label("Mode Fokus (Layar Penuh)", systemImage: "arrow.up.left.and.arrow.down.right")
				}
			} label: {
				Image(systemName: "ellipsis.circle")
					.frame(width: 34, height: 34)
			}

			Button {
				activeSheet = .chapters
			} label: {
				Image(systemName: "list.bullet")
					.frame(width: 34, height: 34)
			}
		}
		.padding(.horizontal, 10)
		.padding(.vertical, 8)
		.background(.ultraThinMaterial)
	}

	@ViewBuilder
	private var translationBanner: some View {
		let offlinePrefix = loadedFromOffline ? "Offline • " : ""
		if let translationProgress {
			Text(translationProgress)
				.font(.caption)
				.padding(.horizontal, 10)
				.padding(.vertical, 6)
				.background(Color.blue.opacity(0.18))
				.foregroundStyle(.blue)
				.clipShape(Capsule())
		} else if targetLang != NovelTranslator.langOff && translatedParagraphs != nil {
			let label = NovelTranslator.findLanguage(targetLang).label
			Button {
				isBilingualMode.toggle()
			} label: {
				Text("\(offlinePrefix)\(label) (\(isBilingualMode ? "Bilingual" : "Terjemahan")) • Ketuk ganti mode")
					.font(.caption)
					.padding(.horizontal, 10)
					.padding(.vertical, 6)
					.background(Color.blue.opacity(0.18))
					.foregroundStyle(.blue)
					.clipShape(Capsule())
			}
			.buttonStyle(.plain)
		} else if targetLang == NovelTranslator.langOff && manga.sourceID?.isForeignLanguage == true {
			Button {
				targetLang = "id"
				startTranslation()
			} label: {
				Text("\(offlinePrefix)Ketuk untuk terjemahkan cepat ke Bahasa Indonesia")
					.font(.caption.weight(.semibold))
					.padding(.horizontal, 10)
					.padding(.vertical, 6)
					.background(Color.blue.opacity(0.18))
					.foregroundStyle(.blue)
					.clipShape(Capsule())
			}
			.buttonStyle(.plain)
		} else if loadedFromOffline {
			Text("Dibuka dari penyimpanan offline")
				.font(.caption)
				.padding(.horizontal, 10)
				.padding(.vertical, 5)
				.background(Color.green.opacity(0.18))
				.foregroundStyle(.green)
				.clipShape(Capsule())
		}
	}

	@ViewBuilder
	private func paragraphView(index: Int, text: String) -> some View {
		let isSpoken = speech.isActive && speech.currentParagraphIndex == index
		let matchesSearch = !searchQuery.isEmpty && text.localizedCaseInsensitiveContains(searchQuery)

		VStack(alignment: .leading, spacing: 4) {
			if isBilingualMode,
			   targetLang != NovelTranslator.langOff,
			   translatedParagraphs != nil,
			   originalParagraphs.indices.contains(index) {
				Text(originalParagraphs[index])
					.font(.system(size: max(12, fontSize - 2), design: isSerifFont ? .serif : .default))
					.foregroundStyle(theme.secondaryText)
					.lineSpacing(4)
			}
			Text(text)
				.font(.system(size: fontSize, design: isSerifFont ? .serif : .default))
				.foregroundStyle(theme.text)
				.lineSpacing(7)
				.textSelection(.enabled)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.vertical, isSpoken || matchesSearch ? 6 : 0)
		.padding(.horizontal, isSpoken || matchesSearch ? 8 : 0)
		.background(
			RoundedRectangle(cornerRadius: 8)
				.fill(
					isSpoken
						? theme.ttsHighlight
						: (matchesSearch ? Color.orange.opacity(0.22) : Color.clear)
				)
		)
	}

	private var ttsMiniBar: some View {
		VStack(spacing: 6) {
			HStack {
				Text("Audiobook • Paragraf \(speech.currentParagraphIndex + 1)/\(max(1, displayParagraphs.count))")
					.font(.caption.bold())
					.foregroundStyle(.blue)
				Spacer()
				Button {
					speech.cycleSleepTimer()
				} label: {
					Text(speech.sleepMinutesRemaining > 0 ? "Timer \(speech.sleepMinutesRemaining)m" : "Timer Off")
						.font(.caption2.bold())
				}
				.buttonStyle(.bordered)
				Button {
					speech.stop()
				} label: {
					Image(systemName: "xmark")
						.font(.caption.bold())
				}
				.padding(.leading, 6)
			}

			HStack(spacing: 10) {
				Button { speech.skip(by: -1) } label: {
					Image(systemName: "backward.fill")
				}
				.buttonStyle(.bordered)

				Button { speech.togglePause() } label: {
					Label(speech.isPaused ? "Lanjut" : "Jeda", systemImage: speech.isPaused ? "play.fill" : "pause.fill")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.borderedProminent)

				Button { speech.skip(by: 1) } label: {
					Image(systemName: "forward.fill")
				}
				.buttonStyle(.bordered)

				Button { speech.cycleSpeed() } label: {
					Text(String(format: "%.2gx", speech.speechRateMultiplier))
						.font(.caption.bold().monospacedDigit())
				}
				.buttonStyle(.bordered)
			}
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 8)
		.background(.ultraThinMaterial)
	}

	private var autoScrollMiniBar: some View {
		HStack(spacing: 10) {
			Text("Auto-Scroll • \(autoScrollPaused ? "Dijeda" : "\(autoScrollSpeed)x")")
				.font(.caption.bold())
				.foregroundStyle(.blue)
			Spacer()
			Button("-") { autoScrollSpeed = max(1, autoScrollSpeed - 1) }
				.buttonStyle(.bordered)
			Button(autoScrollPaused ? "Lanjut" : "Jeda") {
				autoScrollPaused.toggle()
			}
			.buttonStyle(.borderedProminent)
			Button("+") { autoScrollSpeed = min(5, autoScrollSpeed + 1) }
				.buttonStyle(.bordered)
			Button {
				stopAutoScroll()
			} label: {
				Image(systemName: "xmark")
			}
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 8)
		.background(.ultraThinMaterial)
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

			Text("\(chapterIndex + 1) / \(max(1, manga.chapters.count))")
				.font(.caption.monospacedDigit())

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
		.padding(.vertical, 8)
		.background(.ultraThinMaterial)
	}

	private var searchMatchCount: Int {
		let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !q.isEmpty else { return 0 }
		return displayParagraphs.filter { $0.localizedCaseInsensitiveContains(q) }.count
	}

	// MARK: - Sheets

	@ViewBuilder
	private func sheetContent(for sheet: NovelSheet) -> some View {
		switch sheet {
		case .translate:
			NavigationStack {
				List {
					Section {
						Toggle("Mode Bilingual (Asli + Terjemahan)", isOn: $isBilingualMode)
					}
					Section("Pilih Bahasa Target (19 Bahasa)") {
						ForEach(NovelTranslator.supportedLanguages) { lang in
							Button {
								targetLang = lang.code
								activeSheet = nil
								if lang.code == NovelTranslator.langOff {
									translateTask?.cancel()
									translatedParagraphs = nil
									translationProgress = nil
								} else {
									startTranslation()
								}
							} label: {
								HStack {
									Text("\(lang.label) [\(lang.badge)]")
										.foregroundStyle(.primary)
									Spacer()
									if lang.code == targetLang {
										Image(systemName: "checkmark")
											.foregroundStyle(Color.accentColor)
									}
								}
							}
						}
					}
				}
				.navigationTitle("Terjemahan Novel")
				.navigationBarTitleDisplayMode(.inline)
				.toolbar {
					ToolbarItem(placement: .cancellationAction) {
						Button("Tutup") { activeSheet = nil }
					}
				}
			}

		case .appearance:
			NavigationStack {
				Form {
					Section("Tipografi") {
						HStack {
							Text("Ukuran Teks: \(Int(fontSize)) pt")
							Spacer()
							Stepper("", value: $fontSize, in: 14...28, step: 1)
								.labelsHidden()
						}
						Toggle("Font Serif (Gaya Buku)", isOn: $isSerifFont)
					}
					Section("Tema Baca") {
						ForEach(NovelThemePreset.allCases) { preset in
							Button {
								themeRaw = preset.rawValue
							} label: {
								HStack {
									Circle()
										.fill(preset.background)
										.overlay(Circle().stroke(Color.gray.opacity(0.4), lineWidth: 1))
										.frame(width: 22, height: 22)
									Text(preset.name)
										.foregroundStyle(.primary)
									Spacer()
									if preset.rawValue == themeRaw {
										Image(systemName: "checkmark")
											.foregroundStyle(Color.accentColor)
									}
								}
							}
						}
					}
				}
				.navigationTitle("Tampilan & Tema")
				.navigationBarTitleDisplayMode(.inline)
				.toolbar {
					ToolbarItem(placement: .confirmationAction) {
						Button("Selesai") { activeSheet = nil }
					}
				}
			}

		case .chapters:
			NavigationStack {
				List {
					ForEach(Array(manga.chapters.enumerated()), id: \.element.id) { idx, ch in
						Button {
							activeSheet = nil
							chapterIndex = idx
						} label: {
							HStack {
								Text("\(idx + 1). \(ch.title)")
									.foregroundStyle(idx == chapterIndex ? Color.accentColor : .primary)
								Spacer()
								if cachedIds.contains(ch.id) {
									Image(systemName: "arrow.down.circle.fill")
										.foregroundStyle(.green)
								}
								if idx == chapterIndex {
									Image(systemName: "checkmark")
										.foregroundStyle(Color.accentColor)
								}
							}
						}
					}
				}
				.navigationTitle("Daftar Chapter (\(manga.chapters.count))")
				.navigationBarTitleDisplayMode(.inline)
				.toolbar {
					ToolbarItem(placement: .cancellationAction) {
						Button("Tutup") { activeSheet = nil }
					}
				}
			}

		case .glossary:
			NovelGlossarySheet(mangaId: manga.id, rules: $glossaryRules)

		case .bookmarks:
			NovelBookmarksSheet(
				mangaId: manga.id,
				currentChapter: currentChapter,
				currentChapterIndex: chapterIndex,
				sampleExcerpt: displayParagraphs.first ?? "",
				bookmarks: $bookmarks,
				onSelect: { bm in
					activeSheet = nil
					if let idx = manga.chapters.firstIndex(where: { $0.id == bm.chapterId }) {
						chapterIndex = idx
					} else if manga.chapters.indices.contains(bm.chapterIndex) {
						chapterIndex = bm.chapterIndex
					}
				}
			)

		case .search:
			NavigationStack {
				Form {
					Section("Cari kata atau nama karakter di chapter ini") {
						TextField("Ketik kata kunci...", text: $searchQuery)
					}
					Section {
						Button("Terapkan Sorotan") { activeSheet = nil }
							.buttonStyle(.borderedProminent)
						if !searchQuery.isEmpty {
							Button("Hapus Pencarian", role: .destructive) {
								searchQuery = ""
								activeSheet = nil
							}
						}
					}
				}
				.navigationTitle("Cari di Chapter")
				.navigationBarTitleDisplayMode(.inline)
			}

		case .offline:
			let stats = NovelExtrasStore.shared.cacheStats(mangaId: manga.id)
			NavigationStack {
				List {
					Section("Status Penyimpanan Novel Ini") {
						Text("Tersimpan: \(stats.chapterCount) chapter (\(stats.formattedSize))")
					}
					Section("Aksi") {
						Button("Simpan Chapter Ini Offline") {
							saveCurrentOffline()
							activeSheet = nil
						}
						Button("Unduh 10 Chapter Berikutnya") {
							activeSheet = nil
							Task { await batchDownload(count: 10) }
						}
						Button("Unduh 25 Chapter Berikutnya") {
							activeSheet = nil
							Task { await batchDownload(count: 25) }
						}
						Button("Hapus Cache Offline Novel Ini", role: .destructive) {
							let removed = NovelExtrasStore.shared.deleteNovelCache(mangaId: manga.id)
							cachedIds = []
							loadedFromOffline = false
							statusMessage = "\(removed) chapter offline dihapus."
							activeSheet = nil
						}
					}
				}
				.navigationTitle("Simpan Offline")
				.navigationBarTitleDisplayMode(.inline)
				.toolbar {
					ToolbarItem(placement: .cancellationAction) {
						Button("Tutup") { activeSheet = nil }
					}
				}
			}
		}
	}

	// MARK: - Actions & Loading

	private func toggleTtsQuick() {
		if speech.isActive {
			speech.togglePause()
		} else {
			stopAutoScroll()
			speech.start(paragraphs: displayParagraphs, startIndex: 0, locale: activeSpeechLocale)
		}
	}

	private func startAutoScroll() {
		speech.stop()
		autoScrollActive = true
		autoScrollPaused = false
		autoScrollParagraphCursor = 0
		autoScrollTask?.cancel()
		autoScrollTask = Task {
			while !Task.isCancelled && autoScrollActive {
				let secondsPerParagraph = max(1.2, 5.5 - Double(autoScrollSpeed) * 0.85)
				try? await Task.sleep(nanoseconds: UInt64(secondsPerParagraph * 1_000_000_000))
				if autoScrollPaused { continue }
				if autoScrollParagraphCursor + 1 < displayParagraphs.count {
					autoScrollParagraphCursor += 1
				} else {
					autoScrollPaused = true
				}
			}
		}
	}

	private func stopAutoScroll() {
		autoScrollActive = false
		autoScrollPaused = false
		autoScrollTask?.cancel()
		autoScrollTask = nil
	}

	private func saveCurrentOffline() {
		guard let chapter = currentChapter, !originalParagraphs.isEmpty else { return }
		NovelExtrasStore.shared.saveChapter(
			mangaId: manga.id,
			chapterId: chapter.id,
			title: chapterTitle,
			paragraphs: originalParagraphs,
			translatedLang: targetLang != NovelTranslator.langOff ? targetLang : nil,
			translatedParagraphs: translatedParagraphs
		)
		cachedIds.insert(chapter.id)
		loadedFromOffline = true
		statusMessage = "Chapter berhasil disimpan untuk dibaca offline."
	}

	private func batchDownload(count: Int) async {
		guard let source = SourceRegistry.source(named: manga.sourceName) else { return }
		let endIdx = min(manga.chapters.count - 1, chapterIndex + count - 1)
		guard chapterIndex <= endIdx else { return }
		let indices = Array(chapterIndex...endIdx)
		var saved = 0
		for (step, idx) in indices.enumerated() {
			let ch = manga.chapters[idx]
			batchDownloadStatus = "Mengunduh offline (\(step + 1)/\(indices.count)): \(ch.title)"
			let existing = NovelExtrasStore.shared.loadChapter(mangaId: manga.id, chapterId: ch.id)
			var title = existing?.title ?? ch.title
			var paragraphs = existing?.paragraphs ?? []
			if paragraphs.isEmpty {
				if let payload = try? await source.fetchChapterPayload(chapter: ch),
				   case .novel(let loadedTitle, let loadedParagraphs) = payload {
					title = loadedTitle ?? ch.title
					paragraphs = loadedParagraphs
				}
			}
			guard !paragraphs.isEmpty else { continue }
			var trans: [String]? = existing?.translations[targetLang]
			if targetLang != NovelTranslator.langOff && trans == nil {
				trans = try? await NovelTranslator.shared.translateParagraphs(
					chapterKey: "\(ch.id)_\(ch.url)",
					paragraphs: paragraphs,
					targetLang: targetLang
				)
			}
			NovelExtrasStore.shared.saveChapter(
				mangaId: manga.id,
				chapterId: ch.id,
				title: title,
				paragraphs: paragraphs,
				translatedLang: targetLang != NovelTranslator.langOff ? targetLang : nil,
				translatedParagraphs: trans
			)
			cachedIds.insert(ch.id)
			saved += 1
		}
		batchDownloadStatus = nil
		statusMessage = "Selesai! \(saved) chapter siap dibaca offline."
	}

	private func loadChapter(index: Int, autoStartTts: Bool) async {
		guard manga.chapters.indices.contains(index) else { return }
		let chapter = manga.chapters[index]
		translateTask?.cancel()
		isLoading = true
		errorMessage = nil
		chapterTitle = chapter.title
		translatedParagraphs = nil
		translationProgress = nil

		defer { isLoading = false }

		if let cached = NovelExtrasStore.shared.loadChapter(mangaId: manga.id, chapterId: chapter.id),
		   !cached.paragraphs.isEmpty {
			chapterTitle = cached.title ?? chapter.title
			originalParagraphs = cached.paragraphs
			loadedFromOffline = true
			if targetLang != NovelTranslator.langOff, let offlineTrans = cached.translations[targetLang] {
				translatedParagraphs = offlineTrans
			}
		} else if let source = SourceRegistry.source(named: manga.sourceName) {
			loadedFromOffline = false
			do {
				let payload = try await source.fetchChapterPayload(chapter: chapter)
				if case .novel(let title, let paragraphs) = payload {
					chapterTitle = title ?? chapter.title
					originalParagraphs = paragraphs
				}
			} catch {
				if !Task.isCancelled {
					errorMessage = error.localizedDescription
				}
				return
			}
		}

		let pct = manga.chapters.isEmpty ? 0 : Float(index + 1) / Float(manga.chapters.count)
		store.recordProgress(
			manga: manga,
			chapterId: chapter.id,
			page: 0,
			scroll: 0,
			percent: pct,
			chaptersCount: manga.chapters.count
		)

		if targetLang != NovelTranslator.langOff && translatedParagraphs == nil {
			startTranslation(autoStartTtsAfter: autoStartTts)
		} else if autoStartTts {
			speech.start(paragraphs: displayParagraphs, startIndex: 0, locale: activeSpeechLocale)
		}
	}

	private func startTranslation(autoStartTtsAfter: Bool = false) {
		guard let chapter = currentChapter,
			  targetLang != NovelTranslator.langOff,
			  !originalParagraphs.isEmpty else { return }
		let langCode = targetLang
		let langLabel = NovelTranslator.findLanguage(langCode).label
		let paragraphsSnapshot = originalParagraphs
		let titleSnapshot = chapterTitle

		translateTask?.cancel()
		translateTask = Task {
			translationProgress = "Menerjemahkan ke \(langLabel)..."
			do {
				let result = try await NovelTranslator.shared.translateParagraphs(
					chapterKey: "\(chapter.id)_\(chapter.url)",
					paragraphs: paragraphsSnapshot,
					targetLang: langCode
				) { partial, done, total in
					await MainActor.run {
						self.translatedParagraphs = partial
						self.translationProgress = done < total
							? "Menerjemahkan ke \(langLabel) (\(done)/\(total))..."
							: nil
					}
				}
				translatedParagraphs = result
				translationProgress = nil
				NovelExtrasStore.shared.saveChapter(
					mangaId: manga.id,
					chapterId: chapter.id,
					title: titleSnapshot,
					paragraphs: paragraphsSnapshot,
					translatedLang: langCode,
					translatedParagraphs: result
				)
				cachedIds.insert(chapter.id)
				if autoStartTtsAfter {
					speech.start(paragraphs: displayParagraphs, startIndex: 0, locale: activeSpeechLocale)
				} else if speech.isActive {
					speech.updateParagraphs(displayParagraphs, locale: activeSpeechLocale)
				}
			} catch {
				if !Task.isCancelled {
					translationProgress = "Gagal menerjemahkan: \(error.localizedDescription)"
				}
			}
		}
	}
}

private struct NovelGlossarySheet: View {
	@Environment(\.dismiss) private var dismiss

	let mangaId: Int64
	@Binding var rules: [GlossaryRule]

	@State private var sourceTerm: String = ""
	@State private var replacement: String = ""

	var body: some View {
		NavigationStack {
			Form {
				Section("Tambah Istilah Kustom") {
					TextField("Kata asli (misal: Senior Brother / Qi)", text: $sourceTerm)
					TextField("Ganti menjadi (misal: Kakak Seperguruan)", text: $replacement)
					Button("Simpan Istilah") {
						rules = NovelExtrasStore.shared.upsertGlossaryRule(
							mangaId: mangaId,
							rule: GlossaryRule(sourceTerm: sourceTerm, replacement: replacement)
						)
						sourceTerm = ""
						replacement = ""
					}
					.disabled(
						sourceTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
						replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
					)
				}

				Section("Daftar Aturan (\(rules.count))") {
					if rules.isEmpty {
						Text("Belum ada aturan glosarium untuk novel ini.")
							.foregroundStyle(.secondary)
					} else {
						ForEach(rules) { rule in
							HStack {
								Text(rule.sourceTerm).bold()
								Image(systemName: "arrow.right")
									.font(.caption)
									.foregroundStyle(.secondary)
								Text(rule.replacement)
							}
						}
						.onDelete { offsets in
							let terms = offsets.compactMap { rules.indices.contains($0) ? rules[$0].sourceTerm : nil }
							for term in terms {
								rules = NovelExtrasStore.shared.removeGlossaryRule(mangaId: mangaId, sourceTerm: term)
							}
						}
					}
				}
			}
			.navigationTitle("Glosarium Novel")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Selesai") { dismiss() }
				}
			}
		}
	}
}

private struct NovelBookmarksSheet: View {
	@Environment(\.dismiss) private var dismiss

	let mangaId: Int64
	let currentChapter: ChapterItem?
	let currentChapterIndex: Int
	let sampleExcerpt: String
	@Binding var bookmarks: [NovelBookmark]
	let onSelect: (NovelBookmark) -> Void

	@State private var noteText: String = ""

	var body: some View {
		NavigationStack {
			Form {
				if let chapter = currentChapter {
					Section("Tandai Chapter Ini") {
						Text(chapter.title)
							.font(.subheadline.bold())
						TextField("Catatan opsional...", text: $noteText)
						Button("Simpan Tanda Kutipan") {
							let bm = NovelBookmark(
								id: Int64(Date().timeIntervalSince1970 * 1000),
								chapterId: chapter.id,
								chapterIndex: currentChapterIndex,
								chapterTitle: chapter.title,
								paragraphIndex: 0,
								excerpt: String(sampleExcerpt.prefix(120)),
								note: noteText.trimmingCharacters(in: .whitespacesAndNewlines),
								createdAt: Int64(Date().timeIntervalSince1970 * 1000)
							)
							bookmarks = NovelExtrasStore.shared.addBookmark(mangaId: mangaId, bookmark: bm)
							noteText = ""
						}
					}
				}

				Section("Tanda Tersimpan (\(bookmarks.count))") {
					if bookmarks.isEmpty {
						Text("Belum ada tanda kutipan.")
							.foregroundStyle(.secondary)
					} else {
						ForEach(bookmarks) { bm in
							Button {
								onSelect(bm)
							} label: {
								VStack(alignment: .leading, spacing: 4) {
									Text(bm.chapterTitle)
										.font(.subheadline.bold())
										.foregroundStyle(.primary)
									if !bm.note.isEmpty {
										Text(bm.note)
											.font(.caption)
											.foregroundStyle(Color.accentColor)
									}
									Text("\"\(bm.excerpt)...\"")
										.font(.caption2)
										.foregroundStyle(.secondary)
										.lineLimit(2)
								}
							}
						}
						.onDelete { offsets in
							let ids = offsets.compactMap { bookmarks.indices.contains($0) ? bookmarks[$0].id : nil }
							for id in ids {
								bookmarks = NovelExtrasStore.shared.removeBookmark(mangaId: mangaId, bookmarkId: id)
							}
						}
					}
				}
			}
			.navigationTitle("Tanda & Kutipan")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Tutup") { dismiss() }
				}
			}
		}
	}
}
