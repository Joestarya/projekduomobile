# QA Test Matrix — versi untuk project ini

File ini berisi daftar uji manual yang disesuaikan untuk proyek mobile di workspace.

| No | Fitur | Diuji | Input / Aksi | Output yang Diharapkan | Hasil yang Didapatkan | Status |
|---:|:------|:------|:-------------|:-----------------------|:----------------------|:------|
| 1 | Login | Autentikasi pengguna | Buka halaman Login → isi email & password valid → tekan Login | Pengguna diarahkan ke Dashboard / Home; sesi tersimpan | - | Belum Diuji |
| 2 | Register | Pendaftaran akun baru | Buka Register → isi data valid → submit | Akun tersimpan (Supabase/Backend); password ter-hash; user terdaftar | - | Belum Diuji |
| 3 | Mulai Game (Market Forecast) | Flow memulai ronde prediksi | Dari `Game` screen pilih asset & timeframe → pilih Higher/Lower → mulai ronde | Ronde aktif: entry price dicatat, timer berjalan, UI berubah ke state Active | - | Belum Diuji |
| 4 | Resolusi Ronde & Hasil | Menyelesaikan ronde yang sedang berjalan | Tunggu sampai timer habis → app mengambil final price → tampilkan hasil | Status ronde berubah ke Result; muncul breakdown (entry, exit, delta, points) | - | Belum Diuji |
| 5 | Batalkan Ronde | Cancel saat ronde aktif | Saat ronde aktif tekan `Cancel round` | Ronde dibatalkan, state kembali ke Idle, timer berhenti | - | Belum Diuji |
| 6 | Ganti Asset & Timeframe | UI tabs dan pemilihan aset/timeframe | Di Game screen pilih asset lain dan timeframe saat idle | Asset & timeframe tersimpan; chart dan ticker menyesuaikan | - | Belum Diuji |
| 7 | Chart Rendering | Menampilkan candlestick kecil | Buka Game screen dengan data candles tersedia | Chart muncul (CustomPaint) dan entry line tampil saat ronde aktif | - | Belum Diuji |
| 8 | Score & Accuracy | Penambahan skor setelah ronde | Setelah ronde selesai, skor bertambah sesuai hasil | `_totalScore` meningkat; akurasi (`_accuracy`) ter-update | - | Belum Diuji |
| 9 | Pencarian (Search) | Cari project/scene/task/asset | Buka Dashboard/Search → ketik kata kunci | Hasil relevan muncul sesuai data yang diindeks | - | Belum Diuji |
| 10 | Notes (Local) | Simpan catatan lokal (Hive) | Buka Notes → buat catatan baru → simpan → restart app | Catatan muncul di daftar; tetap ada setelah restart | - | Belum Diuji |
| 11 | Upload Foto Profil | Ganti foto dari galeri | Buka Profile → pilih gambar dari galeri → simpan | Foto profil berubah di UI; upload (jika ada backend) | - | Belum Diuji |
| 12 | Logout & Session Clear | Keluar dari akun | Dari Profile tekan Logout | Session dihapus (SharedPreferences); diarahkan ke Login | - | Belum Diuji |
| 13 | Biometric Opt-in | Aktifkan biometric di Profile | Toggle Biometric ON → otentikasi sistem | Preference tersimpan; pada buka berikutnya diminta auth | - | Belum Diuji |
| 14 | Biometric Failure Handling | Gagal biometrik saat app buka | Buka app dengan biometric ON → gagal autentikasi | User diarahkan ke Login; session cleared; biometric pref reset | - | Belum Diuji |
| 15 | Change Role (Profile) | Ubah role pengguna di Profile | Buka Profile → Change Role → pilih role baru → simpan | Role ter-update di UI dan di backend/local storage | - | Belum Diuji |

## Catatan pelaksanaan
- Lokasi screen utama untuk pengujian game: [lib/screens/feature/gamescreen.dart](lib/screens/feature/gamescreen.dart)
- Untuk pengujian fitur backend (register/login) sesuaikan endpoint di `backend/` atau environment Supabase.
- Isi kolom *Hasil yang Didapatkan* dan ubah *Status* ke `Lulus`/`Gagal`/`Butuh Investigasi` saat pengujian manual dijalankan.

## Saran lanjutan
- Ingin saya tambahkan checklist otomatis (integration tests / widget tests) untuk beberapa kasus (login, notes, game flow)?
