# Whisper transcription wrapper — default model: medium
# -Engine whisper : openai-whisper (default)
# -Engine faster  : faster-whisper via whisper-ctranslate2 (pip install whisper-ctranslate2)
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$File,
    [string]$Model = "medium",
    [string]$Language = "Japanese",
    [string]$OutputDir = ".",
    [ValidateSet("whisper", "faster")]
    [string]$Engine = "whisper"
)

$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")

$command = if ($Engine -eq "faster") { "whisper-ctranslate2" } else { "whisper" }
if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
    $package = if ($Engine -eq "faster") { "whisper-ctranslate2" } else { "openai-whisper" }
    Write-Error "$command not found. Install it with: pip install $package"
    exit 1
}

Write-Host "Transcribing: $File (engine=$Engine, model=$Model, language=$Language)"
if ($Engine -eq "faster") {
    whisper-ctranslate2 $File --model $Model --language $Language --output_dir $OutputDir --vad_filter True
} else {
    whisper $File --model $Model --language $Language --output_dir $OutputDir
}
exit $LASTEXITCODE
