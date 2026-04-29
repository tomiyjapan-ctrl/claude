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
