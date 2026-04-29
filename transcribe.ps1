# Whisper transcription wrapper — default model: medium
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$File,
    [string]$Model = "medium",
    [string]$Language = "Japanese",
    [string]$OutputDir = "."
)

$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")

Write-Host "Transcribing: $File (model=$Model, language=$Language)"
whisper $File --model $Model --language $Language --output_dir $OutputDir
