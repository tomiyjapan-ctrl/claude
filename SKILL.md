---
name: video-use
description: Transcribe audio/video files to text using local Whisper. Use when the user wants to transcribe, convert speech to text, or extract text from audio/video files. Default model is medium, default language is Japanese.
tools: Bash
---

# video-use

Transcribe audio and video files using local OpenAI Whisper (offline, no API key required).

## Usage

Run transcription with default settings (medium model, Japanese):

```powershell
powershell -File "$env:USERPROFILE\.claude\skills\video-use\transcribe.ps1" -File "path\to\file.mp4"
```

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-File` | (required) | Path to audio/video file |
| `-Model` | `medium` | Whisper model (tiny/small/medium/large) |
| `-Language` | `Japanese` | Language of the audio |
| `-OutputDir` | `.` | Directory to save output files |

## Supported Formats

Audio: mp3, wav, m4a, flac, ogg
Video: mp4, mov, avi, mkv, webm

## Output

Whisper generates the following files alongside the transcript:
- `.txt` — plain text
- `.srt` — subtitles with timestamps
- `.vtt` — WebVTT subtitles
- `.tsv` — tab-separated with timestamps
- `.json` — full detail with word-level timestamps

## Notes

- First run downloads the medium model (~1.5GB) automatically
- Requires Python 3.11 and openai-whisper (already installed)
- Runs fully offline — no API key or internet connection needed after model download
