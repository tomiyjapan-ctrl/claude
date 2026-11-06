<#
.SYNOPSIS
    メモリ・CPUを多く消費しているソフトを調べる診断スクリプト（読み取り専用）

.DESCRIPTION
    何も変更・停止しません。結果を画面に表示し、デスクトップにレポートを保存します。

.EXAMPLE
    .\diagnose-memory.ps1
    .\diagnose-memory.ps1 -Top 30
#>
param(
    [int]$Top = 20,
    [string]$OutputDir = [Environment]::GetFolderPath("Desktop")
)

$ErrorActionPreference = "Continue"
$report = New-Object System.Collections.Generic.List[string]

function Write-Section($title) {
    $line = "`n===== $title ====="
    Write-Host $line -ForegroundColor Cyan
    $report.Add($line)
}

function Write-Out($obj) {
    $text = ($obj | Out-String -Width 200).TrimEnd()
    Write-Host $text
    $report.Add($text)
}

# --- 1. メモリ全体の状況 ---
Write-Section "メモリ全体"
$os = Get-CimInstance Win32_OperatingSystem
$totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
$freeGB  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
$usedPct = [math]::Round((1 - $os.FreePhysicalMemory / $os.TotalVisibleMemorySize) * 100, 0)
$commitTotalGB = [math]::Round($os.TotalVirtualMemorySize / 1MB, 1)
$commitFreeGB  = [math]::Round($os.FreeVirtualMemory / 1MB, 1)
$uptime = (Get-Date) - $os.LastBootUpTime

Write-Out ([pscustomobject]@{
    "搭載メモリ(GB)"       = $totalGB
    "空きメモリ(GB)"       = $freeGB
    "使用率(%)"            = $usedPct
    "コミット上限(GB)"     = $commitTotalGB
    "コミット空き(GB)"     = $commitFreeGB
    "起動からの経過(日)"   = [math]::Round($uptime.TotalDays, 1)
} | Format-List)

if ($usedPct -ge 85) { Write-Out "⚠ メモリ使用率が高い状態です（85%以上）。下の上位ソフトを確認してください。" }
if ($uptime.TotalDays -ge 7) { Write-Out "⚠ 7日以上再起動していません。一度再起動するだけで改善することがあります。" }

# --- 2. メモリ消費の多いソフト（同名プロセスをまとめて集計） ---
Write-Section "メモリ消費の多いソフト 上位$Top（同名プロセス合算）"
$procs = Get-Process
$grouped = $procs | Group-Object ProcessName | ForEach-Object {
    $desc = ($_.Group | Where-Object { $_.Description } | Select-Object -First 1).Description
    [pscustomobject]@{
        "名前"       = $_.Name
        "説明"       = $desc
        "数"         = $_.Count
        "メモリ(MB)" = [math]::Round(($_.Group | Measure-Object WorkingSet64 -Sum).Sum / 1MB, 0)
        "CPU時間(秒)" = [math]::Round(($_.Group | Measure-Object CPU -Sum).Sum, 0)
    }
} | Sort-Object "メモリ(MB)" -Descending | Select-Object -First $Top
Write-Out ($grouped | Format-Table -AutoSize)

# --- 3. 今まさにCPUを使っているソフト（5秒間計測） ---
Write-Section "現在CPUを多く使っているソフト（5秒間計測）"
$before = @{}
$procs | ForEach-Object { if ($_.CPU) { $before[$_.Id] = $_.CPU } }
# ディスク・メモリの計測も同じ5秒間で行う
$ioBefore = @{}
Get-CimInstance Win32_Process | ForEach-Object {
    $ioBefore[[int]$_.ProcessId] = [double]$_.ReadTransferCount + [double]$_.WriteTransferCount
}
$diskBefore = Get-CimInstance Win32_PerfRawData_PerfDisk_PhysicalDisk -Filter "Name='_Total'" -ErrorAction SilentlyContinue
$memBefore  = Get-CimInstance Win32_PerfRawData_PerfOS_Memory -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5
$ioAfter    = Get-CimInstance Win32_Process
$diskAfter  = Get-CimInstance Win32_PerfRawData_PerfDisk_PhysicalDisk -Filter "Name='_Total'" -ErrorAction SilentlyContinue
$memAfter   = Get-CimInstance Win32_PerfRawData_PerfOS_Memory -ErrorAction SilentlyContinue
$cores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
$cpuNow = Get-Process | Where-Object { $before.ContainsKey($_.Id) -and $_.CPU } | ForEach-Object {
    [pscustomobject]@{
        "名前"     = $_.ProcessName
        "PID"      = $_.Id
        "CPU(%)"   = [math]::Round((($_.CPU - $before[$_.Id]) / 5) / $cores * 100, 1)
    }
} | Where-Object { $_."CPU(%)" -gt 0.5 } | Sort-Object "CPU(%)" -Descending | Select-Object -First 10
if ($cpuNow) { Write-Out ($cpuNow | Format-Table -AutoSize) } else { Write-Out "目立ってCPUを使っているソフトはありません。" }

# --- 3b. ディスクの忙しさとメモリ不足のサイン（同じ5秒間） ---
Write-Section "ディスクの忙しさ・メモリ不足のサイン（5秒間計測）"
if ($diskBefore -and $diskAfter) {
    $dt = [double]$diskAfter.Timestamp_Sys100NS - [double]$diskBefore.Timestamp_Sys100NS
    $idle = 0
    if ($dt -gt 0) { $idle = ([double]$diskAfter.PercentIdleTime - [double]$diskBefore.PercentIdleTime) / $dt * 100 }
    $busy = [math]::Round([math]::Min(100, [math]::Max(0, 100 - $idle)), 0)
    Write-Out "ディスク使用率: $busy %（いま待ち行列: $($diskAfter.CurrentDiskQueueLength) 件）"
    if ($busy -ge 80) { Write-Out "⚠ ディスクがほぼ使い切られています。エクスプローラーや画像表示が遅くなる原因になります。" }
}
if ($memBefore -and $memAfter) {
    $hardFaults = [math]::Round(([double]$memAfter.PagesInputPersec - [double]$memBefore.PagesInputPersec) / 5, 0)
    Write-Out "メモリ不足でディスクから読み戻したページ数: $hardFaults /秒"
    if ($hardFaults -ge 500) { Write-Out "⚠ メモリが足りず、ディスクで代用している状態です（動作が重くなる典型）。" }
}

Write-Section "ディスクの読み書きが多いソフト（5秒間計測）"
$ioTop = $ioAfter | Where-Object { $ioBefore.ContainsKey([int]$_.ProcessId) } | ForEach-Object {
    $delta = [double]$_.ReadTransferCount + [double]$_.WriteTransferCount - $ioBefore[[int]$_.ProcessId]
    [pscustomobject]@{
        "名前"      = $_.Name
        "PID"       = $_.ProcessId
        "MB/秒"     = [math]::Round($delta / 5 / 1MB, 2)
    }
} | Where-Object { $_."MB/秒" -ge 0.1 } | Sort-Object "MB/秒" -Descending | Select-Object -First 10
if ($ioTop) { Write-Out ($ioTop | Format-Table -AutoSize) } else { Write-Out "目立って読み書きしているソフトはありません。" }

# --- 4. スタートアップ（PC起動時に自動で立ち上がるソフト） ---
Write-Section "スタートアップ登録ソフト"
$startup = Get-CimInstance Win32_StartupCommand |
    Select-Object @{n="名前";e={$_.Name}}, @{n="場所";e={$_.Location}}, @{n="コマンド";e={$_.Command}}
Write-Out ($startup | Format-Table -AutoSize -Wrap)

# --- 5. よく重くなる原因になるソフトの検出 ---
Write-Section "よく動作を重くするソフトの検出"
$suspects = [ordered]@{
    "chrome"            = "Google Chrome（タブ・拡張機能が多いとメモリを大量消費）"
    "msedge"            = "Microsoft Edge（バックグラウンドで常駐しがち）"
    "firefox"           = "Firefox"
    "Teams"             = "Microsoft Teams"
    "ms-teams"          = "Microsoft Teams（新）"
    "OneDrive"          = "OneDrive（同期中はCPU・ディスクを使用）"
    "Dropbox"           = "Dropbox"
    "GoogleDriveFS"     = "Googleドライブ"
    "MsMpEng"           = "Windows Defender（スキャン中は一時的に重い）"
    "SearchIndexer"     = "Windows検索インデックス作成"
    "Discord"           = "Discord"
    "Zoom"              = "Zoom"
    "Steam"             = "Steam"
    "EpicGamesLauncher" = "Epic Games Launcher"
    "AdobeCollabSync"   = "Adobe（常駐）"
    "Creative Cloud"    = "Adobe Creative Cloud"
    "python"            = "Python（Whisper文字起こし等が動作中の可能性）"
    "ffmpeg"            = "ffmpeg（動画変換中）"
    "Memory Compression" = "メモリ圧縮（メモリ不足のサイン）"
    "McAfee"            = "McAfee（市販ウイルス対策ソフト）"
    "Norton"            = "Norton（市販ウイルス対策ソフト）"
    "avp"               = "Kaspersky"
    "ccSvcHst"          = "Norton"
}
$found = foreach ($key in $suspects.Keys) {
    $match = $procs | Where-Object { $_.ProcessName -like "$key*" }
    if ($match) {
        [pscustomobject]@{
            "ソフト"     = $suspects[$key]
            "メモリ(MB)" = [math]::Round(($match | Measure-Object WorkingSet64 -Sum).Sum / 1MB, 0)
            "数"         = @($match).Count
        }
    }
}
if ($found) { Write-Out ($found | Sort-Object "メモリ(MB)" -Descending | Format-Table -AutoSize) } else { Write-Out "該当なし" }

# --- 6. ディスクの状況（HDDかSSDか） ---
Write-Section "ディスク"
try {
    Write-Out (Get-PhysicalDisk | Select-Object @{n="名前";e={$_.FriendlyName}}, @{n="種類";e={$_.MediaType}},
        @{n="容量(GB)";e={[math]::Round($_.Size/1GB,0)}}, @{n="状態";e={$_.HealthStatus}} | Format-Table -AutoSize)
} catch { Write-Out "物理ディスク情報を取得できませんでした。" }
Write-Out (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null } |
    Select-Object @{n="ドライブ";e={$_.Name}}, @{n="使用(GB)";e={[math]::Round($_.Used/1GB,1)}},
        @{n="空き(GB)";e={[math]::Round($_.Free/1GB,1)}} | Format-Table -AutoSize)

# --- 7. エクスプローラー・画像表示が遅いときの確認 ---
Write-Section "ネットワークドライブの接続状態"
# 切断されたドライブがあると、エクスプローラーが応答を待って固まりやすい
$net = Get-CimInstance Win32_NetworkConnection -ErrorAction SilentlyContinue |
    Select-Object @{n="ドライブ";e={$_.LocalName}}, @{n="接続先";e={$_.RemoteName}}, @{n="状態";e={$_.ConnectionState}}, @{n="詳細";e={$_.Status}}
if ($net) { Write-Out ($net | Format-Table -AutoSize) } else { Write-Out "ネットワークドライブはありません。" }
$mapped = Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 4 } |
    Select-Object @{n="ドライブ";e={$_.DeviceID}}, @{n="接続先";e={$_.ProviderName}}, @{n="名前";e={$_.VolumeName}}
if ($mapped) { Write-Out ($mapped | Format-Table -AutoSize) }

Write-Section "サムネイルキャッシュ"
$thumbDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Explorer"
$thumbs = Get-ChildItem $thumbDir -Filter "thumbcache_*.db" -ErrorAction SilentlyContinue
$thumbMB = [math]::Round(($thumbs | Measure-Object Length -Sum).Sum / 1MB, 0)
Write-Out "サムネイルキャッシュの合計: $thumbMB MB（$(@($thumbs).Count) ファイル）"
if ($thumbMB -ge 1000) { Write-Out "⚠ サムネイルキャッシュが大きくなっています。ディスククリーンアップで「縮小表示」を削除すると改善することがあります。" }

Write-Section "エクスプローラー・画像ビューアの状態"
$viewerNames = "explorer", "Photos", "Microsoft.Photos", "PhotosApp", "dllhost", "ImageGlass", "IrfanView", "i_view64", "Honeyview", "PhotoViewer"
$viewers = Get-Process -ErrorAction SilentlyContinue | Where-Object { $viewerNames -contains $_.ProcessName } |
    Select-Object @{n="名前";e={$_.ProcessName}}, @{n="PID";e={$_.Id}},
        @{n="メモリ(MB)";e={[math]::Round($_.WorkingSet64/1MB,0)}}, @{n="ハンドル数";e={$_.HandleCount}},
        @{n="応答";e={ if ($_.Responding) { "OK" } else { "応答なし" } }}
Write-Out ($viewers | Sort-Object "メモリ(MB)" -Descending | Format-Table -AutoSize)

Write-Section "Windows Update・保守作業の実行状況"
$maint = "TiWorker", "TrustedInstaller", "MoUsoCoreWorker", "wuauclt", "CompatTelRunner", "SearchProtocolHost", "SearchFilterHost", "MsMpEng", "NortonSvc", "defrag", "cleanmgr"
$running = Get-Process -ErrorAction SilentlyContinue | Where-Object { $maint -contains $_.ProcessName } |
    Select-Object @{n="名前";e={$_.ProcessName}}, @{n="メモリ(MB)";e={[math]::Round($_.WorkingSet64/1MB,0)}}, @{n="CPU時間(秒)";e={[math]::Round($_.CPU,0)}}
Write-Out ($running | Format-Table -AutoSize)
$pendingReboot = (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") -or
                 (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired")
if ($pendingReboot) { Write-Out "⚠ Windows Update が再起動待ちです。再起動すると改善することがあります。" } else { Write-Out "再起動待ちの更新はありません。" }

# --- レポート保存 ---
$path = Join-Path $OutputDir ("memory-report_{0:yyyyMMdd_HHmm}.txt" -f (Get-Date))
$report | Out-File -FilePath $path -Encoding UTF8
Write-Host "`nレポートを保存しました: $path" -ForegroundColor Green
