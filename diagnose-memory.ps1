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
Start-Sleep -Seconds 5
$cores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
$cpuNow = Get-Process | Where-Object { $before.ContainsKey($_.Id) -and $_.CPU } | ForEach-Object {
    [pscustomobject]@{
        "名前"     = $_.ProcessName
        "PID"      = $_.Id
        "CPU(%)"   = [math]::Round((($_.CPU - $before[$_.Id]) / 5) / $cores * 100, 1)
    }
} | Where-Object { $_."CPU(%)" -gt 0.5 } | Sort-Object "CPU(%)" -Descending | Select-Object -First 10
if ($cpuNow) { Write-Out ($cpuNow | Format-Table -AutoSize) } else { Write-Out "目立ってCPUを使っているソフトはありません。" }

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

# --- レポート保存 ---
$path = Join-Path $OutputDir ("memory-report_{0:yyyyMMdd_HHmm}.txt" -f (Get-Date))
$report | Out-File -FilePath $path -Encoding UTF8
Write-Host "`nレポートを保存しました: $path" -ForegroundColor Green
