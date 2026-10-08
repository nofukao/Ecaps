# Ecaps — 作業ルール

- 設計判断・AHK v2 の落とし穴は [docs/design-notes.md](docs/design-notes.md) にまとめてある。変更前に目を通す。
- **`Ecaps.ahk` を変更したら、完了報告の前に必ずゴールデンテストを実行する**（手順・制約は design-notes 7 章）。
  - `python tests/golden_test.py` で比較し、差分が意図した変化だけであることを確認してから `--update` で golden を更新し、スクリプトと一緒にコミットする。
  - 新しいキーバインドを足したら、`tests/golden_test.py` の `CASES` にもケースを足す。
  - 端末向けの送出に関わる変更なら `python tests/vscode_terminal_test.py`（VSCode 内蔵ターミナルでの e2e）も実行する。
  - テストは画面の前面を使ってキーを送るので、実行前にユーザーへ「1 分ほどキーボード・マウスに触れない」「RDP ウィンドウを最小化しない」と伝え、了承を得てから実行する（操作中に走らせると、ユーザーのアプリに誤入力しうる）。
  - テストで確かめられない挙動（Alt 等を押したままの連打、IME、RDP 前面時の無効化）は、ユーザーに実機確認を依頼する。
- 構文チェックは `"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut /validate Ecaps.ahk`。
- コミットメッセージは日本語で、理由（なぜ）を書く。
- インストーラ `install.ps1` を変えたら、README の「インストール」節（オプション表・AI エージェント向け手順）も合わせて直す。`install.ps1` は ASCII のみで書く（PowerShell 5.1 は BOM 無しを ANSI で読み、`irm` 経由でも実行されるため）。
- リリース手順: golden / e2e テスト合格 → main を push → `git tag vX.Y.Z` → `git push origin vX.Y.Z` → GitHub でそのタグからリリースを作成（Web 画面、または gh の `gh release create vX.Y.Z --generate-notes`）。各 PC は `install.ps1` で最新リリースを取得するので、**リリースを作るまで他の PC には配布されない**。
