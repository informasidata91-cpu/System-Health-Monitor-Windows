<# 
  HealthGuard.ps1
  System Health Monitor – Data Informasi v1.0.0.0
  Output: %USERPROFILE%\Desktop\SystemHealthReport.txt
#>

# --- Setup output ---
$logFile = Join-Path $env:USERPROFILE "Desktop\SystemHealthReport.txt"
$date    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# Helper untuk tulis baris
function Write-Log([string]$text){
    $text | Out-File -FilePath $logFile -Encoding utf8 -Append
}

# Inisialisasi file
"System Health Report - Data Informasi" | Out-File -FilePath $logFile -Encoding utf8
"Date: $date" | Out-File -FilePath $logFile -Encoding utf8 -Append
"=========================================" | Out-File $logFile -Append

# --- CPU Usage ---
try {
    $cpu = Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction Stop
    $cpuUsage = [math]::Round($cpu.CounterSamples.CookedValue, 1)
} catch {
    $cpuUsage = -1
}
if ($cpuUsage -ge 0 -and $cpuUsage -lt 70) { $cpuStatus = "Baik" }
elseif ($cpuUsage -ge 70 -and $cpuUsage -lt 90) { $cpuStatus = "Sedang" }
elseif ($cpuUsage -ge 0) { $cpuStatus = "Buruk" }
else { $cpuStatus = "Tidak tersedia" }
"CPU Usage: $cpuUsage% -> $cpuStatus" | Out-File $logFile -Append

# --- RAM Usage ---
try {
    $ram = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $totalRAMGB = [math]::Round($ram.TotalVisibleMemorySize / 1MB, 1)
    $usedRAMGB  = [math]::Round(($ram.TotalVisibleMemorySize - $ram.FreePhysicalMemory) / 1MB, 1)
    $ramPercent = if ($totalRAMGB -gt 0) { [math]::Round(($usedRAMGB / $totalRAMGB) * 100, 1) } else { 0 }
    if ($ramPercent -lt 75) { $ramStatus = "Baik" }
    elseif ($ramPercent -lt 90) { $ramStatus = "Sedang" }
    else { $ramStatus = "Buruk" }
    "RAM Usage: $usedRAMGB GB dari $totalRAMGB GB ($ramPercent%) -> $ramStatus" | Out-File $logFile -Append
} catch {
    "RAM Usage: Tidak tersedia" | Out-File $logFile -Append
    $ramStatus = "Sedang"
}

# --- Disk Usage (C) ---
try {
    $disk = Get-PSDrive C -ErrorAction Stop
    $diskUsedPercent = [math]::Round((($disk.Used / $disk.Maximum) * 100), 1)
    if ($diskUsedPercent -lt 80) { $diskStatus = "Baik" }
    elseif ($diskUsedPercent -lt 90) { $diskStatus = "Sedang" }
    else { $diskStatus = "Buruk" }
    "Disk C: $diskUsedPercent% digunakan -> $diskStatus" | Out-File $logFile -Append
} catch {
    "Disk C: Tidak tersedia" | Out-File $logFile -Append
    $diskStatus = "Sedang"
}

# --- Uptime ---
try {
    $boot = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime
    $uptimeSpan = New-TimeSpan -Start $boot -End (Get-Date)
    $uptimeText = ("{0} Hari {1} Jam" -f $uptimeSpan.Days, $uptimeSpan.Hours)
    if ($uptimeSpan.Days -lt 7) { $uptimeStatus = "Baik" }
    elseif ($uptimeSpan.Days -lt 14) { $uptimeStatus = "Sedang" }
    else { $uptimeStatus = "Buruk" }
    "Uptime: $uptimeText -> $uptimeStatus" | Out-File $logFile -Append
} catch {
    "Uptime: Tidak tersedia" | Out-File $logFile -Append
    $uptimeStatus = "Sedang"
}

# --- CPU Temperature (WMI fallback; optional) ---
# Catatan: Tidak semua perangkat menyediakan sensor ini.
try {
    $temp = Get-WmiObject -Namespace "root/wmi" -Class MSAcpi_ThermalZoneTemperature -ErrorAction Stop
    if ($temp -and $temp.CurrentTemperature) {
        $cpuTemp = [math]::Round(($temp.CurrentTemperature / 10) - 273.15, 1)
        if ($cpuTemp -lt 70) { $tempStatus = "Baik" }
        elseif ($cpuTemp -lt 85) { $tempStatus = "Sedang" }
        else { $tempStatus = "Buruk" }
        "Suhu CPU: $cpuTemp C -> $tempStatus" | Out-File $logFile -Append
    } else {
        "Suhu CPU: Sensor tidak tersedia" | Out-File $logFile -Append
        $tempStatus = "Baik"
    }
} catch {
    "Suhu CPU: Sensor tidak tersedia" | Out-File $logFile -Append
    $tempStatus = "Baik"
}

# --- Internet Connection ---
try {
    $pingOk = Test-Connection -ComputerName "google.com" -Count 2 -Quiet -ErrorAction Stop
} catch { $pingOk = $false }
if ($pingOk) { $netStatus = "Baik"; $pingText = "Aktif" } else { $netStatus = "Buruk"; $pingText = "Tidak terhubung" }
"Koneksi Internet: $pingText -> $netStatus" | Out-File $logFile -Append

# --- Firewall Status ---
try {
    $fwEnabled = (Get-NetFirewallProfile -ErrorAction Stop | Where-Object { $_.Enabled -eq $true }).Count -gt 0
} catch { $fwEnabled = $false }
if ($fwEnabled) { $fwStatus = "Baik"; $fwText = "Aktif" } else { $fwStatus = "Buruk"; $fwText = "Nonaktif" }
"Firewall: $fwText -> $fwStatus" | Out-File $logFile -Append

# --- Windows Update (last hotfix date) ---
try {
    $update = Get-HotFix -ErrorAction Stop | Sort-Object InstalledOn -Descending | Select-Object -First 1
    if ($update) {
        $daysSinceUpdate = (New-TimeSpan -Start $update.InstalledOn -End (Get-Date)).Days
        if ($daysSinceUpdate -lt 15) { $updStatus = "Baik" }
        elseif ($daysSinceUpdate -lt 30) { $updStatus = "Sedang" }
        else { $updStatus = "Buruk" }
        "Windows Update Terakhir: $($update.InstalledOn.ToShortDateString()) -> $updStatus" | Out-File $logFile -Append
    } else {
        "Windows Update: Tidak ditemukan data -> Buruk" | Out-File $logFile -Append
        $updStatus = "Buruk"
    }
} catch {
    "Windows Update: Tidak tersedia" | Out-File $logFile -Append
    $updStatus = "Sedang"
}

# --- Heavy Processes (Top 5 by CPU time) ---
"Proses Berat (CPU):" | Out-File $logFile -Append
try {
    Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 | ForEach-Object {
        $cpuTime = if ($_.CPU) { [math]::Round($_.CPU, 2) } else { 0 }
        "  - $($_.ProcessName): $cpuTime detik CPU" | Out-File $logFile -Append
    }
} catch {
    "  - Tidak dapat membaca proses" | Out-File $logFile -Append
}

# --- Overall Evaluation ---
$statuses = @($cpuStatus, $ramStatus, $diskStatus, $uptimeStatus, $tempStatus, $netStatus, $fwStatus, $updStatus)

# Konversi status ke skor
$score = 0
foreach($s in $statuses){
    switch ($s) {
        "Baik"  { $score += 2 }
        "Sedang"{ $score += 1 }
        "Buruk" { $score += 0 }
        default { $score += 1 } # unknown -> netral
    }
}

$average = [math]::Round(($score / ($statuses.Count * 2)) * 100, 1)

if ($average -ge 80) { $final = "Kondisi Sistem: BAIK" }
elseif ($average -ge 50) { $final = "Kondisi Sistem: SEDANG" }
else { $final = "Kondisi Sistem: BURUK" }

"-----------------------------------------" | Out-File $logFile -Append
$final | Out-File $logFile -Append
"Skor: $average %" | Out-File $logFile -Append
"-----------------------------------------" | Out-File $logFile -Append
"(c) Data Informasi - Pemeriksaan Sistem Otomatis" | Out-File $logFile -Append

# --- Selesai ---
Write-Host "Pemeriksaan selesai!"
Write-Host "Laporan tersimpan di Desktop sebagai 'SystemHealthReport.txt'"