import SwiftUI
import UIKit

public struct StatsAndSettingsView: View {
	@EnvironmentObject private var store: LibraryStore

	@State private var tokenInput: String = ""
	@State private var hasSavedToken: Bool = false
	@State private var alertMessage: String?
	@State private var isTestingToken: Bool = false

	private let goalOptions = [15, 30, 45, 60, 90, 120]

	public var body: some View {
		NavigationStack {
			Form {
				Section("Reading Streak & Target Harian") {
					let snap = store.streakSnapshot
					VStack(alignment: .leading, spacing: 10) {
						HStack {
							Text(snap.currentStreakDays > 0 ? "\(snap.currentStreakDays) Hari Beruntun" : "Mulai Streak Hari Ini")
								.font(.title3.bold())
							Spacer()
							Text("Rekor \(snap.longestStreakDays) Hari")
								.font(.caption.bold())
								.foregroundStyle(.secondary)
						}

						let ratio = min(1.0, Double(snap.todayMinutes) / Double(max(1, snap.dailyGoalMinutes)))
						Text("Hari Ini: \(snap.todayMinutes) / \(snap.dailyGoalMinutes) menit")
							.font(.caption)
							.foregroundStyle(.secondary)

						ProgressView(value: ratio)
							.tint(.accentColor)

						HStack(spacing: 6) {
							ForEach(snap.last7Days) { day in
								VStack(spacing: 3) {
									Text(day.shortLabel)
										.font(.caption2.bold())
									Text(day.minutes > 0 ? "\(day.minutes)m" : "·")
										.font(.caption2)
								}
								.frame(maxWidth: .infinity)
								.padding(.vertical, 6)
								.background(
									RoundedRectangle(cornerRadius: 8)
										.fill(
											day.reachedGoal
												? Color.accentColor
												: (day.minutes > 0 ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.14))
										)
								)
								.foregroundStyle(day.reachedGoal ? .white : .primary)
							}
						}
					}
					.padding(.vertical, 4)

					Picker("Target Baca Harian", selection: Binding(
						get: { store.streakSnapshot.dailyGoalMinutes },
						set: { store.setDailyGoalMinutes($0) }
					)) {
						ForEach(goalOptions, id: \.self) { mins in
							Text("\(mins) menit / hari").tag(mins)
						}
					}
				}

				Section(
					header: Text("GitHub Gist Cloud Sync (Kompatibel Android v9.5.3)"),
					footer: Text("Gunakan Personal Access Token GitHub dengan izin 'gist' yang sama dengan Kotatsu Android untuk sinkronisasi Riwayat & Favorit otomatis.")
				) {
					HStack {
						Text("Status Token")
						Spacer()
						Text(hasSavedToken ? "Tersimpan di Keychain" : "Belum diatur")
							.foregroundStyle(hasSavedToken ? .green : .secondary)
							.font(.caption.bold())
					}

					SecureField("Masukkan GitHub PAT (ghp_...)", text: $tokenInput)
						.textInputAutocapitalization(.never)
						.autocorrectionDisabled()

					HStack {
						Button("Simpan Token") {
							KeychainTokenStore.saveToken(tokenInput)
							hasSavedToken = KeychainTokenStore.loadToken() != nil
							tokenInput = ""
							alertMessage = "Token GitHub berhasil disimpan aman di Keychain iOS."
						}
						.disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

						Spacer()

						if hasSavedToken {
							Button("Hapus Token", role: .destructive) {
								KeychainTokenStore.saveToken(nil)
								hasSavedToken = false
								alertMessage = "Token GitHub dihapus dari Keychain."
							}
						}
					}

					TextField("Gist ID (opsional, otomatis deteksi)", text: $store.gistId)
						.textInputAutocapitalization(.never)
						.autocorrectionDisabled()

					if !store.gistId.isEmpty {
						Button("Salin Gist ID") {
							UIPasteboard.general.string = store.gistId
							alertMessage = "Gist ID disalin ke clipboard."
						}
					}

					Text(store.lastSyncStatus)
						.font(.caption)
						.foregroundStyle(.secondary)

					Button {
						Task { await runSync(preferRemote: false) }
					} label: {
						if store.isSyncing {
							ProgressView()
						} else {
							Label("Sinkronkan Sekarang", systemImage: "arrow.triangle.2.circlepath")
						}
					}
					.disabled(!hasSavedToken || store.isSyncing)

					Button {
						Task { await runSync(preferRemote: true) }
					} label: {
						Label("Tarik Data dari Cloud (Prioritas Gist)", systemImage: "icloud.and.arrow.down")
					}
					.disabled(!hasSavedToken || store.isSyncing)

					Button {
						Task { await testConnection() }
					} label: {
						if isTestingToken {
							ProgressView()
						} else {
							Label("Uji Koneksi Token", systemImage: "checkmark.shield")
						}
					}
					.disabled(!hasSavedToken || isTestingToken)
				}

				Section("Preferensi Katalog") {
					Toggle("Tampilkan Katalog 18+ (DoujinDesu)", isOn: $store.showNsfwSources)
				}

				Section("Tentang") {
					HStack {
						Text("Kotatsu iOS")
						Spacer()
						Text("v9.5.3 (1037)")
							.foregroundStyle(.secondary)
					}
					HStack {
						Text("File Sinkronisasi")
						Spacer()
						Text(GitHubGistSyncClient.syncFileName)
							.font(.caption.monospaced())
							.foregroundStyle(.secondary)
					}
				}
			}
			.navigationTitle("Statistik & Sync")
			.onAppear {
				hasSavedToken = KeychainTokenStore.loadToken() != nil
				store.refreshStreak()
			}
			.alert("Cloud Sync", isPresented: Binding(
				get: { alertMessage != nil },
				set: { if !$0 { alertMessage = nil } }
			)) {
				Button("OK", role: .cancel) {}
			} message: {
				Text(alertMessage ?? "")
			}
		}
	}

	private func runSync(preferRemote: Bool) async {
		do {
			let res = try await store.syncWithCloud(preferRemote: preferRemote)
			alertMessage = "Sinkronisasi berhasil! \(res.historyCount) riwayat, \(res.favouritesCount) favorit."
		} catch {
			alertMessage = error.localizedDescription
		}
	}

	private func testConnection() async {
		guard let token = KeychainTokenStore.loadToken() else { return }
		isTestingToken = true
		defer { isTestingToken = false }
		do {
			try await GitHubGistSyncClient.shared.verifyToken(token)
			alertMessage = "Koneksi GitHub berhasil dan izin 'gist' valid!"
		} catch {
			alertMessage = error.localizedDescription
		}
	}
}
