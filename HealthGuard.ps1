<#
────────────────────────────────────────────
🩺  System Health Monitor – Data Informasi™ v3.0
📅  Versi: 3.0
🧩  Pemeriksaan:
     - CPU, RAM, Disk, Suhu CPU
     - Uptime, Internet, Firewall, Update
     - Proses berat
🧠  Hasil: Tiap komponen diberi status (Baik / Sedang / Buruk)
────────────────────────────────────────────
#>

$logFile = "$env:USERPROFILE\Desktop\SystemHealthReport.txt"
$date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"🩺 Laporan Kesehatan Sistem - Data Informasi™" | Out-File $logFile
"📅 Tanggal: $date" | Out-File $logFile -Append
"=========================================" | Out-File $logFile -Append

# --- CPU Usage ---
$cpu = Get-Counter '\Processor(_Total)\% Processor Time'
$cpuUsage = [math]::Round($cpu.CounterSamples.CookedValue, 1)
if ($cpuUsage -lt 70) { $cpuStatus = "Baik" }
elseif ($cpuUsage -lt 90) { $cpuStatus = "Sedang" }
else { $cpuStatus = "Buruk" }
"CPU Usage: $cpuUsage% → $cpuStatus" | Out-File $logFile -Append

# --- RAM Usage ---
$ram = Get-CimInstance Win32_OperatingSystem
$totalRAM = [math]::Round($ram.TotalVisibleMemorySize / 1MB, 1)
$usedRAM = [math]::Round(($ram.TotalVisibleMemorySize - $ram.FreePhysicalMemory) / 1MB, 1)
$ramPercent = [math]::Round(($usedRAM / $totalRAM) * 100, 1)
if ($ramPercent -lt 75) { $ramStatus = "Baik" }
elseif ($ramPercent -lt 90) { $ramStatus = "Sedang" }
else { $ramStatus = "Buruk" }
"RAM Usage: $usedRAM GB dari $totalRAM GB ($ramPercent%) → $ramStatus" | Out-File $logFile -Append

# --- Disk Usage ---
$disk = Get-PSDrive C
$diskUsedPercent = [math]::Round((($disk.Used / $disk.Maximum) * 100), 1)
if ($diskUsedPercent -lt 80) { $diskStatus = "Baik" }
elseif ($diskUsedPercent -lt 90) { $diskStatus = "Sedang" }
else { $diskStatus = "Buruk" }
"Disk C: $diskUsedPercent% digunakan → $diskStatus" | Out-File $logFile -Append

# --- Uptime ---
$uptime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
$uptimeSpan = (New-TimeSpan $uptime (Get-Date))
$uptimeText = "{0} Hari {1} Jam" -f $uptimeSpan.Days, $uptimeSpan.Hours
if ($uptimeSpan.Days -lt 7) { $uptimeStatus = "Baik" }
elseif ($uptimeSpan.Days -lt 14) { $uptimeStatus = "Sedang" }
else { $uptimeStatus = "Buruk" }
"Uptime: $uptimeText → $uptimeStatus" | Out-File $logFile -Append

# --- Suhu CPU ---
$temp = Get-WmiObject MSAcpi_ThermalZoneTemperature -Namespace "root/wmi" -ErrorAction SilentlyContinue
if ($temp) {
    $cpuTemp = [math]::Round(($temp.CurrentTemperature / 10) - 273.15, 1)
    if ($cpuTemp -lt 70) { $tempStatus = "Baik" }
    elseif ($cpuTemp -lt 85) { $tempStatus = "Sedang" }
    else { $tempStatus = "Buruk" }
    "Suhu CPU: $cpuTemp °C → $tempStatus" | Out-File $logFile -Append
} else {
    "Suhu CPU: (Sensor tidak tersedia)" | Out-File $logFile -Append
    $tempStatus = "Baik"
}

# --- Internet Connection ---
$ping = Test-Connection google.com -Count 2 -Quiet
if ($ping) { $netStatus = "Baik" } else { $netStatus = "Buruk" }
"Koneksi Internet: $($ping ? '✅ Aktif' : '❌ Tidak terhubung') → $netStatus" | Out-File $logFile -Append

# --- Firewall Status ---
$firewall = Get-NetFirewallProfile | Where-Object {$_.Enabled -eq $true}
if ($firewall) { $fwStatus = "Baik" } else { $fwStatus = "Buruk" }
"Firewall: $($firewall ? '🟢 Aktif' : '🔴 Nonaktif') → $fwStatus" | Out-File $logFile -Append

# --- Windows Update ---
$update = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1
if ($update) {
    $daysSinceUpdate = (New-TimeSpan $update.InstalledOn (Get-Date)).Days
    if ($daysSinceUpdate -lt 15) { $updStatus = "Baik" }
    elseif ($daysSinceUpdate -lt 30) { $updStatus = "Sedang" }
    else { $updStatus = "Buruk" }
    "Windows Update Terakhir: $($update.InstalledOn.ToShortDateString()) → $updStatus" | Out-File $logFile -Append
} else {
    "Windows Update: Tidak ditemukan data → Buruk" | Out-File $logFile -Append
    $updStatus = "Buruk"
}

# --- Proses Berat ---
"Proses Berat (CPU):" | Out-File $logFile -Append
Get-Process | Sort CPU -Descending | Select -First 5 | ForEach-Object {
    "  - $($_.ProcessName): $([math]::Round($_.CPU, 2)) detik CPU" | Out-File $logFile -Append
}

# --- Evaluasi Keseluruhan ---
$statuses = @($cpuStatus, $ramStatus, $diskStatus, $uptimeStatus, $tempStatus, $netStatus, $fwStatus, $updStatus)
$score = ($statuses | ForEach-Object {
    switch ($_){
        "Baik" { 2 }
        "Sedang" { 1 }
        "Buruk" { 0 }
    }
}) | Measure-Object -Sum | Select-Object -ExpandProperty Sum

$average = $score / ($statuses.Count * 2) * 100
if ($average -ge 80) { $final = "🟢 Kondisi Sistem: Baik" }
elseif ($average -ge 50) { $final = "🟡 Kondisi Sistem: Sedang" }
else { $final = "🔴 Kondisi Sistem: Buruk" }

"-----------------------------------------" | Out-File $logFile -Append
$final | Out-File $logFile -Append
"-----------------------------------------" | Out-File $logFile -Append
"© Data Informasi™ – Pemeriksaan Sistem Otomatis" | Out-File $logFile -Append

# --- Selesai ---
Write-Host "✅ Pemeriksaan selesai!"
Write-Host "📄 Laporan tersimpan di Desktop sebagai 'SystemHealthReport.txt'"
