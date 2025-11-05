# System Health Monitor – Data Informasi v1.0.0.0

Monitor kesehatan Windows secara cepat: CPU, RAM, Disk, Suhu CPU, Uptime, Internet, Firewall, Windows Update, dan proses terberat. Tiap komponen diberi status Baik/Sedang/Buruk, lalu dihitung skor keseluruhan dan disimpan otomatis ke Desktop sebagai SystemHealthReport.txt.

## Fitur

- Deteksi instan: CPU, RAM, Disk C, Suhu CPU, Uptime.
- Konektivitas: ping internet, status Firewall.
- Patch hygiene: tanggal Windows Update terakhir.
- Proses berat: top 5 berdasarkan CPU time.
- Skoring agregat → indikator akhir: 🟢 Baik / 🟡 Sedang / 🔴 Buruk.
- Output rapi ke file teks dengan timestamp.


## Prasyarat

- Windows 10/11 atau Windows Server.
- PowerShell 5.1+ atau PowerShell 7+.
- Hak eksekusi skrip (ExecutionPolicy) yang mengizinkan running script.
- Sensor suhu via WMI (opsional; jika tidak ada, skrip tetap jalan).


## Instalasi

1. Salin skrip ke file: HealtGuard.ps1
2. Buka PowerShell sebagai Administrator (disarankan).
3. Opsional: set kebijakan eksekusi sementara
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

## Cara Pakai

Jalankan dari folder skrip:
```
.\HealtGuard.ps1
```

Output:

- File laporan: %USERPROFILE%\Desktop\SystemHealthReport.txt
- Konsol menampilkan status selesai dan lokasi file.


## Logika Penilaian (ringkas)

- CPU: <70% Baik, 70–<90% Sedang, ≥90% Buruk.
- RAM: <75% Baik, 75–<90% Sedang, ≥90% Buruk.
- Disk C: <80% Baik, 80–<90% Sedang, ≥90% Buruk.
- Uptime: <7 hari Baik, 7–<14 hari Sedang, ≥14 hari Buruk.
- Suhu CPU: <70°C Baik, 70–<85°C Sedang, ≥85°C Buruk (fallback “sensor tidak tersedia” → diasumsikan Baik).
- Internet: ping google.com → Baik/Buruk.
- Firewall: profil aktif → Baik/Buruk.
- Windows Update: <15 hari Baik, 15–<30 hari Sedang, ≥30 hari Buruk.

Skor akhir: rata-rata ter-normalisasi (0–100), lalu label:

- ≥80 → 🟢 Kondisi Sistem: Baik
- ≥50 → 🟡 Kondisi Sistem: Sedang
- <50 → 🔴 Kondisi Sistem: Buruk


## Cuplikan Kode Utama

```powershell
$logFile = "$env:USERPROFILE\Desktop\SystemHealthReport.txt"
$date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"🩺 Laporan Kesehatan Sistem - Data Informasi™" | Out-File $logFile
"📅 Tanggal: $date" | Out-File $logFile -Append
"=========================================" | Out-File $logFile -Append
# … (blok CPU, RAM, Disk, Uptime, Suhu, Internet, Firewall, Update, Proses)
# … Hitung skor dan tulis ringkasan akhir
```


## Keluaran Contoh

```
🩺 Laporan Kesehatan Sistem - Data Informasi™
📅 Tanggal: 2025-11-05 20:40:12
=========================================
CPU Usage: 23.4% → Baik
RAM Usage: 5.6 GB dari 16.0 GB (35.2%) → Baik
Disk C: 61.3% digunakan → Baik
Uptime: 2 Hari 4 Jam → Baik
Suhu CPU: 53.8 °C → Baik
Koneksi Internet: ✅ Aktif → Baik
Firewall: 🟢 Aktif → Baik
Windows Update Terakhir: 01/11/2025 → Baik
Proses Berat (CPU):
  - chrome: 125.73 detik CPU
  - Code: 98.54 detik CPU
  - …
-----------------------------------------
🟢 Kondisi Sistem: Baik
-----------------------------------------
© Data Informasi™ – Pemeriksaan Sistem Otomatis
```


## Troubleshooting

- Tidak bisa ping: jaringan diblokir proxy/DNS. Ganti target ping (mis. 1.1.1.1).
- Suhu tidak muncul: driver/ACPI sensor tidak tersedia; ini normal pada beberapa perangkat.
- Akses ditolak saat menulis file: jalankan PowerShell tanpa batasan izin folder Desktop atau ubah \$logFile ke lokasi lain.


## Keamanan \& Privasi

- Laporan hanya berisi metrik sistem lokal; tidak mengirim data keluar.
- Jalankan dari akun tepercaya. Tinjau skrip sebelum dieksekusi.


## Roadmap

- Threshold configurable via parameter/JSON.
- Multi-drive report (C, D, E).
- Export CSV/JSON dan mode kontinu (scheduled task).
- Notifikasi (Toast/Email/Teams/Webhook).


## Kontribusi

PR, issue, dan saran sangat diterima. Ikuti gaya kode PowerShell yang konsisten, tambahkan komentar, dan sertakan contoh hasil.

## Lisensi

MIT License — bebas digunakan, dimodifikasi, dan didistribusikan dengan atribusi.

## Kredit

Dibuat oleh Data Informasi™ untuk automasi audit kesehatan sistem Windows harian.
