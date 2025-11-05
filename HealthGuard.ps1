<# 
  HealthGuard.ps1
  Output: %USERPROFILE%\Desktop\SystemHealthReport.html
#>

[CmdletBinding()]
param(
  [string]$TargetHost = "google.com",
  [string]$Drive = "C",
  [int]$TopN = 5
)

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
try{
  $pingOk = Test-Connection -ComputerName $TargetHost -Count 2 -Quiet -ErrorAction Stop
}catch{ $pingOk = $false }
$netStatus = if ($pingOk) { "Baik" } else { "Buruk" }
$netText   = if ($pingOk) { "Aktif" } else { "Tidak terhubung" }
$items += [pscustomobject]@{Komponen="Internet"; Nilai=$netText; Status=$netStatus; Keterangan=$TargetHost}

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

# Top Processes (PS 5.1 safe)
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
$avg = [math]::Round(($score / ($items.Count*2))*100,1)
if ($avg -ge 80){$final="BAIK"} elseif($avg -ge 50){$final="SEDANG"} else{$final="BURUK"}

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
<meta charset="utf-8">
<title>System Health Report Data Informasi™</title>
$style
<body>
<div class="wrap">
  <div class="header">
    <h1>System Health Report Data Informasi™</h1>
    <div class="muted">Tanggal: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</div>
    <div class="kpi-wrap">
      <div class="kpi"><div>Overall Score</div><strong>$avg %</strong></div>
      <div class="kpi"><div>Kondisi</div><strong>$final</strong></div>
    </div>
  </div>
  <div style="padding:0 24px 16px">
    <table class="table">
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

    <h3>Top Proses (CPU time)</h3>
    <table class="table">
      <thead><tr><th>Proses</th><th style='text-align:right'>Detik</th></tr></thead>
      <tbody>$procHtml</tbody>
    </table>
  </div>
  <div class="footer">
    (c) Data Informasi™. Pemeriksaan Sistem Otomatis. Target host: $TargetHost. Drive: $Drive
  </div>
</div>
</body>
</html>
"@

# ---------------- Save ----------------
$htmlDoc | Out-File -FilePath $outHtml -Encoding utf8

Write-Host "Selesai. HTML report:"
Write-Host " - $outHtml"