import XCTest
@testable import KotatsuIOS

final class KotatsuIOSTests: XCTestCase {

	func testKotatsuUidMatchesAndroidAlgorithm() {
		let id1 = KotatsuUid.generate(sourceName: "KOMIKU", url: "/manga/one-piece/")
		let id2 = KotatsuUid.generate(sourceName: "KOMIKU", url: "/manga/one-piece/")
		let id3 = KotatsuUid.generate(sourceName: "DOUJINDESU", url: "/manga/one-piece/")
		XCTAssertEqual(id1, id2)
		XCTAssertNotEqual(id1, id3)

		// Verify exact manual formula matching Kotlin LONG_HASH_SEED = 1125899906842597L
		var expected: Int64 = 1_125_899_906_842_597
		for u in "KOMIKU".utf16 { expected = (31 &* expected) &+ Int64(u) }
		for u in "/manga/one-piece/".utf16 { expected = (31 &* expected) &+ Int64(u) }
		XCTAssertEqual(id1, expected)
	}

	func testDoujinDesuXorRoundTripAndPlusPreservation() {
		let slot: Int64 = 491_234
		let nowMs = slot * 3_600_000 + 10_000
		let plainJson = #"{"title":"A+B Manga","ok":true}"#
		let key = DoujinDesuDecoder.generateHourlyKey(slot: slot)
		XCTAssertEqual(key.count, 32)

		// Encode using the exact inverse of DoujinDesu frontend XOR + rolling accumulator
		let percentEncoded = Array(plainJson.utf8)
		var acc = 42
		var hex = ""
		for (i, ch) in percentEncoded.enumerated() {
			let cipher = (Int(ch) ^ Int(key[i % 32]) ^ (i * 13) ^ acc) & 0xFF
			acc = (acc + cipher) & 0xFF
			hex += String(format: "%02x", cipher)
		}
		let envelope = #"{"_enc_resp_":"\#(hex)"}"#
		let decoded = DoujinDesuDecoder.decodeResponse(raw: envelope, nowMs: nowMs)
		XCTAssertEqual(decoded, plainJson)
	}

	func testNovelTranslatorParseAndChunk() {
		let sample = """
		[[["Halo dunia, ", "Hello world, ", null, null, 10],["bab satu dimulai.", "chapter one begins.", null, null, 10]],null,"en"]
		"""
		XCTAssertEqual(NovelTranslator.parseGtxResponse(sample), "Halo dunia, bab satu dimulai.")

		let paras = (1...15).map { "Paragraph number \($0) with sample content." }
		let chunks = NovelTranslator.chunkParagraphs(paras, maxChars: 200, maxCount: 5)
		XCTAssertGreaterThanOrEqual(chunks.count, 3)
		XCTAssertEqual(chunks.flatMap { $0 }, paras)
		XCTAssertTrue(chunks.allSatisfy { $0.count <= 5 })

		let longText = Array(repeating: "word", count: 450).joined(separator: " ")
		XCTAssertEqual(NovelTranslator.estimateReadingMinutes([longText], wordsPerMinute: 200), 3)
	}

	func testGlossarySinglePassLongestTermFirst() {
		let rules = [
			GlossaryRule(sourceTerm: "Lin", replacement: "Lin Utama"),
			GlossaryRule(sourceTerm: "Senior Brother Lin", replacement: "Kakak Seperguruan Lin"),
			GlossaryRule(sourceTerm: "Qi", replacement: "Energi Dalam"),
		]
		let input = [
			"Senior Brother Lin gathered his Qi quickly.",
			"He was quite calm inside the clinic.",
		]
		let output = NovelGlossaryEngine.apply(paragraphs: input, rules: rules)
		XCTAssertEqual(output[0], "Kakak Seperguruan Lin gathered his Energi Dalam quickly.")
		XCTAssertEqual(output[1], "He was quite calm inside the clinic.")
	}

	func testNovelExtrasStorePersistence() throws {
		let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("kotatsu_test_\(UUID().uuidString)")
		defer { try? FileManager.default.removeItem(at: tmp) }
		let store = NovelExtrasStore(rootDir: tmp)

		store.saveChapter(
			mangaId: 99,
			chapterId: 1001,
			title: "Chapter 1",
			paragraphs: ["Hello world."],
			translatedLang: "id",
			translatedParagraphs: ["Halo dunia."]
		)
		let loaded = store.loadChapter(mangaId: 99, chapterId: 1001)
		XCTAssertNotNil(loaded)
		XCTAssertEqual(loaded?.paragraphs, ["Hello world."])
		XCTAssertEqual(loaded?.translations["id"], ["Halo dunia."])
		XCTAssertTrue(store.cachedChapterIds(mangaId: 99).contains(1001))

		let rules = store.upsertGlossaryRule(mangaId: 99, rule: GlossaryRule(sourceTerm: "Dao", replacement: "Jalan Langit"))
		XCTAssertEqual(rules.count, 1)

		let removed = store.deleteNovelCache(mangaId: 99)
		XCTAssertEqual(removed, 1)
		XCTAssertNil(store.loadChapter(mangaId: 99, chapterId: 1001))
		XCTAssertEqual(store.loadGlossary(mangaId: 99).count, 1)
	}

	func testCloudSyncSchemaMatchesAndroidJsonAndMergesNewerHistory() throws {
		let androidJson = """
		{
		  "version": 1,
		  "updated_at": 1700000000000,
		  "history": [
		    {
		      "manga_id": 12345,
		      "created_at": 1700000000000,
		      "updated_at": 1700000005000,
		      "deleted_at": 0,
		      "chapter_id": 888,
		      "page": 4,
		      "scroll": 0.0,
		      "percent": 0.5,
		      "chapters": 20,
		      "manga": {
		        "id": 12345,
		        "title": "Solo Leveling",
		        "url": "/manga/solo-leveling/",
		        "public_url": "https://komiku.org/manga/solo-leveling/",
		        "rating": -1.0,
		        "nsfw": false,
		        "cover_url": "https://komiku.org/cover.jpg",
		        "source": "KOMIKU",
		        "tags": []
		      }
		    }
		  ],
		  "categories": [],
		  "favourites": [],
		  "sources": []
		}
		"""
		let remote = try JSONDecoder().decode(CloudSyncPayloadDTO.self, from: Data(androidJson.utf8))
		XCTAssertEqual(remote.history.count, 1)
		XCTAssertEqual(remote.history[0].manga.title, "Solo Leveling")

		let merged = CloudSyncMerger.merge(local: CloudSyncPayloadDTO(), remote: remote, nowMillis: 1700000010000)
		XCTAssertEqual(merged.history.count, 1)
		XCTAssertEqual(merged.history[0].chapterId, 888)
	}

	func testReadingStreakGracePeriodAndLongestRun() {
		var cal = Calendar(identifier: .gregorian)
		cal.timeZone = TimeZone(secondsFromGMT: 0)!
		let today = cal.date(from: DateComponents(year: 2026, month: 11, day: 19))!
		let dMinus1 = cal.date(byAdding: .day, value: -1, to: today)!
		let dMinus2 = cal.date(byAdding: .day, value: -2, to: today)!

		let active: Set<String> = [
			ReadingStreakEngine.dateKey(for: dMinus1, calendar: cal),
			ReadingStreakEngine.dateKey(for: dMinus2, calendar: cal),
		]
		XCTAssertEqual(ReadingStreakEngine.computeCurrentStreak(activeDateKeys: active, today: today, calendar: cal), 2)
		XCTAssertEqual(ReadingStreakEngine.computeLongestStreak(activeDateKeys: active, calendar: cal), 2)
	}
}
