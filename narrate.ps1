# Fish Audio narration: text script -> TTS audio -> merge into video with ffmpeg
# Requires: ffmpeg/ffprobe on PATH, Fish Audio API key in $env:FISH_AUDIO_API_KEY
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Video,
    [Parameter(Mandatory=$true, Position=1)]
    [string]$Script,
    [string]$VoiceId = $env:FISH_AUDIO_VOICE_ID,
    [string]$Model = "s1",
    [ValidateSet("replace", "mix")]
    [string]$Mode = "replace",
    [double]$BgVolume = 0.3,
    [string]$Output
)

$ErrorActionPreference = "Stop"

$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")

$apiKey = $env:FISH_AUDIO_API_KEY
if (-not $apiKey) {
    Write-Error "FISH_AUDIO_API_KEY is not set. Get a key at https://fish.audio and run: setx FISH_AUDIO_API_KEY <key>"
    exit 1
}
foreach ($cmd in "ffmpeg", "ffprobe") {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Error "$cmd not found. Install it with: winget install Gyan.FFmpeg"
        exit 1
    }
}

$videoPath = (Resolve-Path $Video).Path
$text = Get-Content -Path $Script -Raw -Encoding UTF8
if (-not $text.Trim()) {
    Write-Error "Script file is empty: $Script"
    exit 1
}
if (-not $Output) {
    $Output = Join-Path (Split-Path $videoPath) ([IO.Path]::GetFileNameWithoutExtension($videoPath) + "_narrated.mp4")
}
$narration = [IO.Path]::ChangeExtension($Output, ".narration.mp3")

# 1. Text-to-speech via Fish Audio API
$body = @{ text = $text; format = "mp3"; normalize = $true }
if ($VoiceId) { $body.reference_id = $VoiceId }
$json = $body | ConvertTo-Json -Compress

Write-Host "Generating narration (model=$Model, voice=$(if ($VoiceId) { $VoiceId } else { 'default' }))..."
Invoke-WebRequest -Uri "https://api.fish.audio/v1/tts" -Method Post -UseBasicParsing `
    -Headers @{ Authorization = "Bearer $apiKey"; model = $Model } `
    -ContentType "application/json; charset=utf-8" `
    -Body ([Text.Encoding]::UTF8.GetBytes($json)) `
    -OutFile $narration
Write-Host "Narration saved: $narration"

# 2. Merge into video (output keeps the video's length; narration is padded with silence)
$hasAudio = [bool](& ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 $videoPath)
if ($Mode -eq "mix" -and -not $hasAudio) {
    Write-Warning "Video has no audio track; using replace mode."
    $Mode = "replace"
}

$inv = [Globalization.CultureInfo]::InvariantCulture
$videoSec = [double]::Parse((& ffprobe -v error -show_entries format=duration -of csv=p=0 $videoPath), $inv)
$narrationSec = [double]::Parse((& ffprobe -v error -show_entries format=duration -of csv=p=0 $narration), $inv)
if ($narrationSec -gt $videoSec) {
    Write-Warning ("Narration ({0:N1}s) is longer than the video ({1:N1}s); it will be cut off at the end." -f $narrationSec, $videoSec)
}

if ($Mode -eq "mix") {
    $filter = "[0:a]volume=$($BgVolume.ToString($inv))[bg];[1:a]apad[nar];[bg][nar]amix=inputs=2:duration=first:normalize=0[a]"
} else {
    $filter = "[1:a]apad[a]"
}

Write-Host "Merging into video (mode=$Mode)..."
& ffmpeg -y -hide_banner -loglevel error -i $videoPath -i $narration `
    -filter_complex $filter -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 192k -shortest $Output
if ($LASTEXITCODE -ne 0) {
    Write-Error "ffmpeg failed (exit code $LASTEXITCODE)"
    exit $LASTEXITCODE
}

Write-Host "Done: $Output"
