# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

claude-code-setup導入済み。/setup で起動

## Overview

This repository contains a single PowerShell installer script (`install.ps1`) for Claude Code on Windows. It downloads the appropriate binary, verifies its SHA-256 checksum, and runs the bundled installer.

## Usage

```powershell
# Install latest version
.\install.ps1

# Install stable channel
.\install.ps1 stable

# Install a specific version
.\install.ps1 1.2.3
```

## How `install.ps1` works

1. Resolves the target version by fetching `$DOWNLOAD_BASE_URL/latest`
2. Downloads `manifest.json` for that version to get the SHA-256 checksum
3. Selects the platform binary (`win32-arm64` on ARM64, `win32-x64` otherwise)
4. Downloads `claude.exe` to `~\.claude\downloads\` and verifies the checksum
5. Runs `claude.exe install [target] --force` to set up the launcher and shell integration
6. Cleans up the temporary binary

The script requires 64-bit Windows and uses `$ErrorActionPreference = "Stop"` throughout.

## Transcription (`transcribe.ps1`)

Wrapper around local Whisper for Japanese audio/video transcription. Default model: `medium`, default language: `Japanese`.

### Usage

```powershell
# Basic (medium model, Japanese)
.\transcribe.ps1 video.mp4

# Specify language
.\transcribe.ps1 video.mp4 -Language English

# Specify output directory
.\transcribe.ps1 video.mp4 -OutputDir C:\Users\tomiy531\Desktop
```

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-File` | (required) | Audio/video file to transcribe |
| `-Model` | `medium` | Whisper model size (tiny/small/medium/large) |
| `-Language` | `Japanese` | Language of the audio |
| `-OutputDir` | `.` | Directory to save transcript files |

### Notes

- First run downloads the medium model (~1.5GB) automatically
- Requires Python 3.11 and `openai-whisper` (already installed)
- Output formats: `.txt`, `.srt`, `.vtt`, `.tsv`, `.json`

## 動画チャンネルの制作・運用

動画の制作・運用前に docs/video-channel-manual.md と当該チャンネルの設定・台帳（channels/<channel-key>/）を読み、制作は docs/video-production-rules.md に従う。上位指示と利用者の最新指定を優先する。

- 新しいチャンネルは `channels/_template/` を `channels/<channel-key>/` へ複製して作る（未確定値は「未設定」のまま）
- 制作機能の接続状況は docs/video-capabilities.md に記録する
