# Disk usage report — shows what is taking up space in a folder (default: Documents)
param(
    [Parameter(Position=0)]
    [string]$Path = [Environment]::GetFolderPath("MyDocuments"),
    [int]$Top = 20
)

$ErrorActionPreference = "Stop"

function Format-Size([long]$Bytes) {
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N0} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

$root = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\')
Write-Host "Scanning: $root ..."

# Walk the tree once; skip junctions/symlinks (e.g. "My Music") to avoid double counting
$files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
$stack = [System.Collections.Generic.Stack[System.IO.DirectoryInfo]]::new()
$stack.Push([System.IO.DirectoryInfo]::new($root))
$skipped = 0
while ($stack.Count -gt 0) {
    $dir = $stack.Pop()
    try {
        foreach ($f in $dir.EnumerateFiles()) { $files.Add($f) }
        foreach ($d in $dir.EnumerateDirectories()) {
            if (-not ($d.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $stack.Push($d) }
        }
    } catch { $skipped++ }
}

# OneDrive "online-only" files report a size but use no local disk
$cloudOnly = [IO.FileAttributes]::Offline -bor [IO.FileAttributes]0x400000
$total = ($files | Measure-Object Length -Sum).Sum
$cloud = ($files | Where-Object { $_.Attributes -band $cloudOnly } | Measure-Object Length -Sum).Sum

Write-Host ""
Write-Host "Total: $(Format-Size $total) in $($files.Count) files"
if ($cloud) { Write-Host "  of which online-only (OneDrive, not on local disk): $(Format-Size $cloud)" }
if ($skipped) { Write-Host "  $skipped folder(s) could not be read (access denied)" }

Write-Host ""
Write-Host "=== Top-level folders ==="
$files | Group-Object {
    $rel = $_.FullName.Substring($root.Length + 1)
    if ($rel.Contains('\')) { $rel.Split('\')[0] + '\' } else { '(files in root)' }
} | ForEach-Object {
    $sum = ($_.Group | Measure-Object Length -Sum).Sum
    [pscustomobject]@{ Bytes = $sum; Size = Format-Size $sum; Files = $_.Count; Name = $_.Name }
} | Sort-Object Bytes -Descending | Select-Object -First $Top Size, Files, Name | Format-Table -AutoSize

Write-Host "=== Largest files ==="
$files | Sort-Object Length -Descending | Select-Object -First $Top `
    @{ n = 'Size'; e = { Format-Size $_.Length } },
    @{ n = 'Modified'; e = { $_.LastWriteTime.ToString('yyyy-MM-dd') } },
    @{ n = 'Path'; e = { $_.FullName.Substring($root.Length + 1) } } | Format-Table -AutoSize

Write-Host "=== By file type ==="
$files | Group-Object { if ($_.Extension) { $_.Extension.ToLower() } else { '(none)' } } | ForEach-Object {
    $sum = ($_.Group | Measure-Object Length -Sum).Sum
    [pscustomobject]@{ Bytes = $sum; Size = Format-Size $sum; Files = $_.Count; Type = $_.Name }
} | Sort-Object Bytes -Descending | Select-Object -First $Top Size, Files, Type | Format-Table -AutoSize

Write-Host "Tip: drill down with  .\folder-size.ps1 `"$root\<folder>`""
