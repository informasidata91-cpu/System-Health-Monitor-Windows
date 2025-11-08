<#
  HealthGuard.ps1 (with Maintenance.exe integration)
  Output: %USERPROFILE%\Desktop\SystemHealthReport.html
#>

[CmdletBinding()]
param(
  [string]$TargetHost = "8.8.8.8",
  [string]$Drive = "C",
  [int]$TopN = 5,

  # Maintenance.exe integration
  [string]$MaintenanceExePath = "C:\ProgramData\DataInformasi\Maintenance\Maintenance.exe",
  [string]$MaintenanceDownloadUrl = "https://github.com/informasidata91-cpu/Maintenance-Windows/raw/main/Maintenance.exe",
  [switch]$AutoRunMaintenance,
  [switch]$StrictMaintenance,
  [int]$MinFreeGBSystem = 2,
  [int]$TailLinesCbs = 4000,
  [int]$TailCharsDism = 600000
)

$ErrorActionPreference = 'Stop'

# ---------------- Paths ----------------
$desk = Join-Path $env:USERPROFILE "Desktop"
$outHtml = Join-Path $desk "SystemHealthReport.html"

# ---------------- Helpers ----------------
function StatusScore($s){
  switch($s){
    "Baik"   { 2 }
    "Sedang" { 1 }
    "Buruk"  { 0 }
    default  { 1 }
  }
}
function StatusClass($s){
  switch($s){
    "Baik"   { "ok" }
    "Sedang" { "warn" }
    "Buruk"  { "bad" }
    default  { "na" }
  }
}
function SafeNum($v, $fallback=0){
  if ($null -eq $v) { return $fallback } 
  try { return [double]$v } catch { return $fallback }
}
function Ensure-Folder {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    try { New-Item -ItemType Directory -Force -Path $Path | Out-Null } catch {}
  }
  return $Path
}
function Get-FileTail {
  [CmdletBinding()]
  param(
      [Parameter(Mandatory)][string]$Path,
      [int]$TailLines = 0,
      [int]$TailChars = 0
  )
  if (-not (Test-Path -LiteralPath $Path)) { return '' }
  if ($TailLines -gt 0) {
      return ((Get-Content -LiteralPath $Path -Tail $TailLines -ErrorAction Stop) -join "`r`n")
  } elseif ($TailChars -gt 0) {
      $text = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
      if ($text.Length -gt $TailChars) { return $text.Substring($text.Length - $TailChars) }
      return $text
  } else {
      return (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop)
  }
}
function Get-SystemFreeSpaceGB {
  $sysDrive = $env:SystemDrive.TrimEnd(':','\')
  $d = Get-PSDrive -Name $sysDrive -ErrorAction SilentlyContinue
  if ($null -eq $d) { return [double]::NaN }
  return [math]::Round($d.Free / 1GB, 2)
}
function Test-HealthKPIsDegraded {
  try {
    $cpu = (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue
    $memMB = (Get-Counter '\Memory\Available MBytes').CounterSamples.CookedValue
    $diskFreePct = (Get-Counter '\LogicalDisk(_Total)\% Free Space').CounterSamples.CookedValue
    if ($cpu -ge 85 -or $memMB -le 512 -or $diskFreePct -le 10) { return $true }
  } catch { }
  return $false
}

# ---------------- Maintenance.exe integration ----------------
function Test-SFCIndicatesCorruption {
  param([int]$TailLines = 4000)
  $cbsDir = Join-Path $env:WINDIR 'Logs\CBS'
  Ensure-Folder $cbsDir | Out-Null
  $candidates = @(
    Join-Path $cbsDir 'CBS.log'
    Join-Path $cbsDir 'CBS.persist.log'
  ) | Where-Object { Test-Path -LiteralPath $_ }
  if (-not $candidates) { return $false }
  foreach ($p in $candidates) {
    try {
      $tail = Get-FileTail -Path $p -TailLines $TailLines
      if ([string]::IsNullOrEmpty($tail)) { continue }
      if ($tail -match 'Windows Resource Protection found corrupt files') { return $true }
      if ($tail -match 'unable to fix') { return $true }
      if ($tail -match 'successfully repaired') { return $true }
      if ($tail -match '\[SR\].*(cannot|repair|corrupt|hash)') { return $true }
    } catch { continue }
  }
  return $false
}
function Test-DISMRecentErrors {
  param([int]$TailChars = 600000)
  $dismLog = Join-Path $env:WINDIR 'Logs\DISM\dism.log'
  if (-not (Test-Path -LiteralPath $dismLog)) { return $false }
  try {
    $tail = Get-FileTail -Path $dismLog -TailChars $TailChars
    if ([string]::IsNullOrEmpty($tail)) { return $false }
    if ($tail -match 'Error:\s+\d+' -or
        $tail -match 'FAILED' -or
        $tail -match 'RestoreHealth.*(fail|error|could not)' -or
        $tail -match 'ScanHealth.*(fail|error|could not)') {
      return $true
    }
  } catch { }
  return $false
}
function Get-MaintenanceDecision {
  param(
    [int]$MinFreeGB = 2,
    [int]$TailLines = 4000,
    [int]$TailChars = 600000,
    [switch]$Strict
  )
  $result = [ordered]@{
    SfcCorruption = $false
    DismErrors    = $false
    FreeSpaceGB   = [double]::NaN
    LowSpace      = $false
    KPIBad        = $false
    ShouldRun     = $false
    Reasons       = @()
  }
  $result.SfcCorruption = Test-SFCIndicatesCorruption -TailLines $TailLines
  if ($result.SfcCorruption) { $result.Reasons += 'SFC indicates corruption (CBS.log)' }

  $result.DismErrors = Test-DISMRecentErrors -TailChars $TailChars
  if ($result.DismErrors) { $result.Reasons += 'DISM recent errors (dism.log)' }

  $result.FreeSpaceGB = Get-SystemFreeSpaceGB
  $result.LowSpace = ($result.FreeSpaceGB -lt $MinFreeGB)
  if ($result.LowSpace) { $result.Reasons += ("Low system free space ({0} GB < {1} GB)" -f $result.FreeSpaceGB, $MinFreeGB) }

  $result.KPIBad = Test-HealthKPIsDegraded
  if ($Strict -and $result.KPIBad) { $result.Reasons += 'Degraded health KPIs (CPU/Mem/Disk)' }

  $result.ShouldRun = if ($Strict) {
    ($result.SfcCorruption -or $result.DismErrors -or $result.LowSpace -or $result.KPIBad)
  } else {
    ($result.SfcCorruption -or $result.DismErrors -or $result.LowSpace)
  }
  return $result
}
function Ensure-FileFromUrl {
  param(
    [Parameter(Mandatory)][string]$Url,
    [Parameter(Mandatory)][string]$DestPath
  )
  $destDir = Split-Path -Parent $DestPath
  Ensure-Folder $destDir | Out-Null
  if (-not (Test-Path -LiteralPath $DestPath)) {
    Write-Host "[Maintenance] Mengunduh: $Url"
    try {
      Invoke-WebRequest -Uri $Url -OutFile $DestPath -UseBasicParsing -TimeoutSec 120
    } catch {
      Write-Host "[Maintenance] Gagal unduh: $($_.Exception.Message)"
      return $false
    }
  }
  return (Test-Path -LiteralPath $DestPath)
}
function Invoke-MaintenanceIfNeeded {
  param(
    [string]$ExePath,
    [string]$DownloadUrl,
    [switch]$Strict,
    [switch]$AutoRun
  )
  $decision = Get-MaintenanceDecision -MinFreeGB $MinFreeGBSystem -TailLines $TailLinesCbs -TailChars $TailCharsDism -Strict:$Strict

  if ($AutoRun -and $decision.ShouldRun) {
    $ok = Ensure-FileFromUrl -Url $DownloadUrl -DestPath $ExePath
    if (-not $ok) {
      $decision.Reasons += "Tidak dapat menyiapkan Maintenance.exe dari $DownloadUrl"
      $decision | Add-Member -NotePropertyName ExePath -NotePropertyValue $ExePath -Force
      $decision | Add-Member -NotePropertyName DownloadUrl -NotePropertyValue $DownloadUrl -Force
      return $decision
    }
    try {
      Write-Host "[Maintenance] Menjalankan: $ExePath"
      Start-Process -FilePath $ExePath -ArgumentList "/silent" -Verb RunAs
    } catch {
      $decision.Reasons += "Gagal menjalankan Maintenance.exe: $($_.Exception.Message)"
    }
  }

  $decision | Add-Member -NotePropertyName ExePath -NotePropertyValue $ExePath -Force
  $decision | Add-Member -NotePropertyName DownloadUrl -NotePropertyValue $DownloadUrl -Force
  return $decision
}

# ---------------- Collect Metrics ----------------
$items = @()

# CPU
try{
  $cpu = Get-Counter '\Processor(_Total)\% Processor Time'
  $cpuUsage = [math]::Round($cpu.CounterSamples.CookedValue,1)
}catch{ $cpuUsage = -1 }
if ($cpuUsage -ge 0 -and $cpuUsage -lt 70){$cpuStatus="Baik"}
elseif ($cpuUsage -ge 70 -and $cpuUsage -lt 90){$cpuStatus="Sedang"}
elseif ($cpuUsage -ge 0){$cpuStatus="Buruk"}
else {$cpuStatus="N/A"}
$items += [pscustomobject]@{Komponen="CPU"; Nilai="$cpuUsage %"; Status=$cpuStatus; Keterangan="Rata-rata total"}

# RAM
try{
  $os = Get-CimInstance Win32_OperatingSystem
  $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB,1)
  $usedGB  = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory)/1MB,1)
  $ramPct  = if ($totalGB -gt 0) { [math]::Round(($usedGB/$totalGB)*100,1) } else { 0 }
  if ($ramPct -lt 75){$ramStatus="Baik"} elseif($ramPct -lt 90){$ramStatus="Sedang"} else{$ramStatus="Buruk"}
  $items += [pscustomobject]@{Komponen="RAM"; Nilai="$usedGB GB / $totalGB GB ($ramPct %)"; Status=$ramStatus; Keterangan="Pemakaian fisik"}
}catch{
  $items += [pscustomobject]@{Komponen="RAM"; Nilai="N/A"; Status="Sedang"; Keterangan="Tidak dapat membaca"}
}

# Disk
$diskUsedPercent = $null
try{
  $d = Get-PSDrive -Name $Drive -ErrorAction Stop
  if ($d.Maximum -gt 0){ $diskUsedPercent = [math]::Round(($d.Used/$d.Maximum)*100,1) }
}catch{}
if ($null -eq $diskUsedPercent){
  try{
    $ld = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($Drive):'"
    if ($ld -and $ld.Size -gt 0){ $diskUsedPercent = [math]::Round((($ld.Size-$ld.FreeSpace)/$ld.Size)*100,1) }
  }catch{}
}
if ($diskUsedPercent -ne $null){
  if ($diskUsedPercent -lt 80){$diskStatus="Baik"} elseif($diskUsedPercent -lt 90){$diskStatus="Sedang"} else{$diskStatus="Buruk"}
  $items += [pscustomobject]@{Komponen="Disk $Drive"; Nilai="$diskUsedPercent %"; Status=$diskStatus; Keterangan="Terpakai"}
}else{
  $items += [pscustomobject]@{Komponen="Disk $Drive"; Nilai="N/A"; Status="Sedang"; Keterangan="Tidak tersedia"}
}

# Uptime
try{
  $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
  $span = New-TimeSpan $boot (Get-Date)
  $uptText = "{0} Hari {1} Jam" -f $span.Days,$span.Hours
  if ($span.Days -lt 7){$uptStatus="Baik"} elseif($span.Days -lt 14){$uptStatus="Sedang"} else{$uptStatus="Buruk"}
  $items += [pscustomobject]@{Komponen="Uptime"; Nilai=$uptText; Status=$uptStatus; Keterangan="Sejak boot"}
}catch{
  $items += [pscustomobject]@{Komponen="Uptime"; Nilai="N/A"; Status="Sedang"; Keterangan="Tidak tersedia"}
}

# Temperature
try{
  $t = Get-WmiObject -Namespace "root/wmi" -Class MSAcpi_ThermalZoneTemperature -ErrorAction Stop
  if ($t -and $t.CurrentTemperature){
    $c = [math]::Round(($t.CurrentTemperature/10)-273.15,1)
    if ($c -lt 70){$tStatus="Baik"} elseif($c -lt 85){$tStatus="Sedang"} else{$tStatus="Buruk"}
    $items += [pscustomobject]@{Komponen="CPU Temp"; Nilai="$c C"; Status=$tStatus; Keterangan="ACPI sensor"}
  } else {
    $items += [pscustomobject]@{Komponen="CPU Temp"; Nilai="N/A"; Status="Baik"; Keterangan="Sensor tidak tersedia"}
  }
}catch{
  $items += [pscustomobject]@{Komponen="CPU Temp"; Nilai="N/A"; Status="Baik"; Keterangan="Sensor tidak tersedia"}
}

# Internet
$target = $TargetHost
$pingOk = $false
$avgMs  = ""
try {
  $p = Test-Connection -ComputerName $target -Count 3 -ErrorAction Stop
  $avgMs = [math]::Round(($p | Measure-Object -Property ResponseTime -Average).Average, 1)
  $pingOk = $true
} catch {
  try { $pingOk = Test-Connection -ComputerName $target -Count 2 -Quiet } catch { $pingOk = $false }
}
$netStatus = if ($pingOk) { "Baik" } else { "Buruk" }
$netText   = if ($pingOk) { "Aktif" } else { "Tidak terhubung" }
$ket       = if ($pingOk) { "$target; rtt~$avgMs ms" } else { "$target; ping=fail" }
$items += [pscustomobject]@{Komponen="Internet"; Nilai=$netText; Status=$netStatus; Keterangan=$ket}

# Firewall
try{
  $fwEnabled = (Get-NetFirewallProfile | Where-Object Enabled).Count -gt 0
}catch{ $fwEnabled = $false }
$fwStatus = if ($fwEnabled) { "Baik" } else { "Buruk" }
$fwText   = if ($fwEnabled) { "Aktif" } else { "Nonaktif" }
$items += [pscustomobject]@{Komponen="Firewall"; Nilai=$fwText; Status=$fwStatus; Keterangan="Windows Firewall"}

# Update
try{
  $hf = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1
  if ($hf){
    $days = (New-TimeSpan $hf.InstalledOn (Get-Date)).Days
    if ($days -lt 15){$updStatus="Baik"} elseif($days -lt 30){$updStatus="Sedang"} else{$updStatus="Buruk"}
    $items += [pscustomobject]@{Komponen="Win Update"; Nilai=$hf.InstalledOn.ToShortDateString(); Status=$updStatus; Keterangan="$days hari lalu"}
  } else {
    $items += [pscustomobject]@{Komponen="Win Update"; Nilai="Tidak ada data"; Status="Buruk"; Keterangan="HotFix kosong"}
  }
}catch{
  $items += [pscustomobject]@{Komponen="Win Update"; Nilai="N/A"; Status="Sedang"; Keterangan="Tidak tersedia"}
}

# Top Processes
$top = @()
try{
  $top = Get-Process | Sort-Object CPU -Descending | Select-Object -First $TopN |
    ForEach-Object {
      $cpuTime = if ($null -ne $_.CPU) { [double]$_.CPU } else { 0 }
      [pscustomobject]@{ Process = $_.ProcessName; CPUSeconds = [math]::Round($cpuTime,2) }
    }
}catch{}

# Score
$score = 0
foreach($i in $items){ $score += StatusScore $i.Status }
$avg = if($items.Count -gt 0){ [math]::Round(($score / ($items.Count*2))*100,1) } else { 0 }
if ($avg -ge 80){$final="BAIK"} elseif($avg -ge 50){$final="SEDANG"} else{$final="BURUK"}

# Maintenance decision & optional autorun
$maint = Invoke-MaintenanceIfNeeded -ExePath $MaintenanceExePath -DownloadUrl $MaintenanceDownloadUrl -Strict:$StrictMaintenance -AutoRun:$AutoRunMaintenance
$maintStatus = if ($maint.ShouldRun) { 'Needed' } else { 'Not Needed' }
$maintClass  = if ($maint.ShouldRun) { 'warn' } else { 'ok' }
$maintReasons = if ($maint.Reasons.Count) { ($maint.Reasons -join '; ') } else { '--' }
$downloadLink = $maint.DownloadUrl
$localExists = Test-Path -LiteralPath $maint.ExePath
$localPathEsc = ($maint.ExePath -replace '\\','/')

$maintButtons = @()
if ($downloadLink) {
  $maintButtons += "<a class='btn' href='$downloadLink'>Unduh Maintenance.exe</a>"
}
if ($localExists) {
  $maintButtons += "<a class='btn' href='file:///$localPathEsc'>Buka Maintenance.exe</a>"
} else {
  $maintButtons += "<em>Maintenance.exe belum tersedia lokal.</em>"
}
$maintButtonsHtml = ($maintButtons -join ' ')

# ---------------- Build HTML ----------------
$style = @"
<style>
body{font-family:Segoe UI,Arial,Helvetica,sans-serif;margin:24px;background:#fafafa;color:#222}
.wrap{max-width:1000px;margin:auto;background:#fff;border:1px solid #e5e5e5;border-radius:8px;box-shadow:0 2px 8px rgba(0,0,0,.05)}
.header{padding:20px 24px;border-bottom:1px solid #eee}
.muted{color:#666}
.kpi-wrap{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:12px}
.kpi{padding:12px 16px;border:1px solid #e5e7eb;border-radius:6px;background:#f6f8fa}
.kpi strong{font-size:20px}
.table{width:100%;border-collapse:collapse;margin-top:16px}
.table th,.table td{padding:10px 12px;border-bottom:1px solid #eee;text-align:left;font-variant-numeric:tabular-nums}
.badge{display:inline-block;padding:2px 10px;border-radius:999px;color:#fff;font-size:12px}
.badge.ok{background:#16a34a} .badge.warn{background:#f59e0b} .badge.bad{background:#dc2626} .badge.na{background:#64748b}
.footer{padding:16px 24px;border-top:1px solid #eee;color:#666;font-size:12px}
.summary{padding:16px 24px;border-top:1px dashed #ddd}
.maint{padding:12px 16px;border:1px dashed #cbd5e1;border-radius:6px;background:#f8fafc;margin-top:16px}
.maint a.btn{display:inline-block;margin-top:8px;padding:6px 12px;border-radius:6px;background:#0ea5e9;color:#fff;text-decoration:none}
</style>
"@

$rowsHtml = ($items | ForEach-Object {
  "<tr><td>$($_.Komponen)</td><td>$($_.Nilai)</td><td><span class='badge $(StatusClass $_.Status)'>$($_.Status)</span></td><td>$($_.Keterangan)</td></tr>"
}) -join "`n"

$procHtml = if($top.Count -gt 0){
  ($top | ForEach-Object { "<tr><td>$($_.Process)</td><td style='text-align:right'>$($_.CPUSeconds)</td></tr>" }) -join "`n"
} else { "<tr><td colspan='2'>Tidak dapat membaca proses</td></tr>" }

$htmlDoc = @"
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<title>System Health Report - Data Informasi&trade;</title>
$style
</head>
<body>
<div class="wrap">
  <div class="header">
    <h1>System Health Report - Data Informasi&trade;</h1>
    <div class="muted">Tanggal: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</div>
    <div class="kpi-wrap">
      <div class="kpi"><div>Skor Keseluruhan</div><strong>$avg %</strong></div>
      <div class="kpi"><div>Kondisi</div><strong>$final</strong></div>
    </div>
  </div>
  <div style="padding:0 24px 16px">
    <div class="maint">
      <strong>Kesiapan Pemeliharaan:</strong>
      <div>Status: <span class="badge $maintClass">$maintStatus</span></div>
      <div>Alasan: $maintReasons</div>
      <div>Lokasi Lokal: $($maint.ExePath)</div>
      <div>$maintButtonsHtml</div>
    </div>

    <table class="table" style="margin-top:16px">
      <thead><tr><th>Komponen</th><th>Nilai</th><th>Status</th><th>Keterangan</th></tr></thead>
      <tbody>
        $rowsHtml
      </tbody>
    </table>

    <div class="summary">
      <strong>Rekomendasi:</strong>
      <ul>
        $(if(($items|Where-Object {$_.Komponen -like 'Disk*'}).Status -eq 'Buruk'){"<li>Bersihkan drive: hapus file sementara, uninstall aplikasi tidak perlu.</li>"}else{""})
        $(if(($items|Where-Object {$_.Komponen -eq 'RAM'}).Status -eq 'Buruk'){"<li>Tutup aplikasi berat atau tingkatkan RAM.</li>"}else{""})
        $(if(($items|Where-Object {$_.Komponen -eq 'CPU'}).Status -eq 'Buruk'){"<li>Identifikasi proses konsumtif dan kelola startup.</li>"}else{""})
        $(if(($items|Where-Object {$_.Komponen -eq 'CPU Temp'}).Status -eq 'Buruk'){"<li>Periksa pendingin, bersihkan debu, ganti thermal paste.</li>"}else{""})
        $(if(($items|Where-Object {$_.Komponen -eq 'Win Update'}).Status -eq 'Buruk'){"<li>Segera jalankan Windows Update.</li>"}else{""})
        $(if(($items|Where-Object {$_.Komponen -eq 'Internet'}).Status -eq 'Buruk'){"<li>Periksa koneksi/driver jaringan atau DNS.</li>"}else{""})
        $(if(($items|Where-Object {$_.Komponen -eq 'Firewall'}).Status -eq 'Buruk'){"<li>Aktifkan Windows Firewall atau kebijakan keamanan setempat.</li>"}else{""})
      </ul>
    </div>

    <h3>Proses Teratas (Waktu CPU)</h3>
    <table class="table">
      <thead><tr><th>Proses</th><th style='text-align:right'>Detik</th></tr></thead>
      <tbody>$procHtml</tbody>
    </table>
  </div>
  <div class="footer">
    (c) Data Informasi&trade; - Pemeriksaan Sistem Otomatis - Target host: $TargetHost - Drive: $Drive
  </div>
</div>
</body>
</html>
"@

# ---------------- Save ----------------
Ensure-Folder (Split-Path -Parent $outHtml) | Out-Null
$htmlDoc | Out-File -FilePath $outHtml -Encoding utf8

Write-Host "Selesai. HTML report:"
Write-Host " - $outHtml"
if ($AutoRunMaintenance) {
  Write-Host "AutoRunMaintenance: Maintenance.exe akan diunduh (jika belum ada) dan dijalankan saat trigger terpenuhi."
}
