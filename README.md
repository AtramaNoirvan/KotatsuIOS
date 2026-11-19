# Kotatsu iOS (SwiftUI, v9.5.3)

Aplikasi pembaca **Komik & Light Novel** native iOS (SwiftUI, iOS 16+) yang kompatibel dengan **GitHub Gist Cloud Sync (`kotatsu-sync-v1.json`)** milik Kotatsu Android v9.5.3.

## Fitur Utama
- **Pemisahan Mode `Komik` | `Novel`**: Katalog, Riwayat, dan Favorit terpisah rapi.
- **Katalog Komik**: Komiku (ID), DoujinDesu (ID, API JSON + dekoder XOR), dan MangaDex (ID/EN).
- **Katalog Light & Web Novel**: NovelBin, FreeWebNovel, LibRead, NovelFull, AllNovelFull, IndoWebNovel, dan NovelRingan.
- **Pembaca Novel Lengkap**:
  - Terjemahan streaming 19 bahasa + Mode Bilingual (1-tap ke Bahasa Indonesia).
  - **Audiobook TTS (`AVSpeechSynthesizer`)** dengan sorotan paragraf aktif, auto-scroll, kecepatan 0.75x sampai 2.0x, dan Sleep Timer.
  - **Simpan & Unduh Offline** (chapter satuan maupun batch 10/25 chapter beserta terjemahan).
  - **Glosarium Karakter**, **Cari Kata di Chapter**, **Tanda Kutipan**, **Auto-Scroll Halus**, dan **4 Tema Baca** (Midnight Slate, Sepia, Terang, AMOLED).
- **Pembaca Komik**: Vertical Webtoon + pinch-to-zoom + **Terjemahkan Teks Komik Cepat**.
- **Reading Streak & Target Harian**: Rekor hari beruntun + bar aktivitas 7 hari.
- **GitHub Gist Cloud Sync**: Token disimpan aman di iOS Keychain, sinkron 2 arah dengan Kotatsu Android v9.5.3.

## Cara Build File `.ipa` Gratis lewat GitHub Actions (Tanpa Mac)
1. Buat repository GitHub baru (boleh **Private** atau **Public**), lalu push isi folder `KotatsuIOS` ke branch `main`:
   ```bash
   cd KotatsuIOS
   git init -b main
   git add .
   git commit -m "Initial Kotatsu iOS v9.5.3"
   git remote add origin https://github.com/<USERNAME>/<REPO_KAMU>.git
   git push -u origin main
   ```
2. Buka tab **Actions** di repository GitHub kamu, lalu tunggu workflow **Build iOS IPA** (`macos-latest`) selesai (~4-6 menit).
   Workflow akan otomatis menjalankan `xcodegen`, seluruh unit test (`KotatsuIOSTests`), lalu memaketkan **`KotatsuIOS-v9.5.3.ipa`**.
3. Unduh artifact **`KotatsuIOS-v9.5.3-ipa`** (berisi `KotatsuIOS-v9.5.3.ipa`).

## Cara Install `.ipa` ke iPhone / iPad
- **Sideloadly** (Windows/Mac): Sambungkan iPhone lewat kabel USB, drag-and-drop `KotatsuIOS-v9.5.3.ipa`, masukkan Apple ID, klik Start.
- **AltStore / SideStore**: Buka file `.ipa` di aplikasi AltStore/SideStore di iPhone (SideStore bisa refresh otomatis tanpa PC).
- **TrollStore** (iOS yang mendukung): Langsung install permanen tanpa batas 7 hari.

## Sinkronisasi dengan Kotatsu Android v9.5.3
1. Buka tab **Statistik** di Kotatsu iOS -> bagian **GitHub Gist Cloud Sync**.
2. Masukkan **Personal Access Token GitHub** (izin `gist`) yang sama dengan yang dipakai di Kotatsu Android v9.5.3.
3. Ketuk **Simpan Token**, lalu ketuk **Tarik Data dari Cloud** atau **Sinkronkan Sekarang**.
