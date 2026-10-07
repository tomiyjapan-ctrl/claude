# 制作機能の接続状況

> マニュアル「導入5」に基づく。区分は 利用可能／要接続／未導入／手動。実証結果のないものを利用可能としない。
> 確認日: 2026-10-07。確認環境: Claude Code クラウドセッション（Linux コンテナ）。利用者のWindows PCでの状況は別途確認が必要。

| 機能 | 区分 | 実証結果・備考 |
|------|------|----------------|
| 調査（Web検索） | 利用可能（未試験） | WebSearch/WebFetch ツールあり。本番調査では未試験 |
| 文字起こし | 手動（Windows PC） | このリポジトリの transcribe.ps1（Whisper medium）は利用者のWindows PC用。クラウドコンテナには whisper 未導入 |
| 音声生成 | 要接続（試験未実施） | Higgsfield MCP に generate_audio / create_voice あり。有料の可能性があり、予算合意前のため未試験 |
| 画像作成 | 要接続（試験未実施） | Higgsfield MCP に generate_image あり。同上 |
| 編集と書き出し | 利用可能 | ffmpeg 6.1.1（libass/drawtext あり）。1280x720・3秒・日本語字幕（白字黒縁）付き mp4 の書き出しとffprobeでの読み取りに成功 |
| 品質検査 | 利用可能（限定） | ffprobe・フレーム抽出で実ファイル確認可。独立担当によるQAは別セッション/サブエージェントで実施可能か都度明記 |
| YouTube操作 | 未導入 | YouTube の接続なし（Higgsfield は TikTok 投稿のみ）。投稿・予約は手動 |
| 分析 | 未導入 | YouTube Analytics の接続なし。利用者からの数値提供で手動記録 |
| 通知 | 未設定 | 通知先未確定 |
| 定期実行 | 要接続（未設定） | クラウドの Routine（スケジュール実行）は作成可能だが、利用者の依頼がないため未登録 |
