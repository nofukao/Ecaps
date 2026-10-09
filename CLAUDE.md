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
- インストーラ `install.ps1` を変えたら、README の「インストール」節（オプション表・AI エージェント向け手順）も合わせて直す。`install.ps1` は ASCII のみで書く（PowerShell 5.1 は BOM 無しを ANSI で読むため）。PowerShell のコマンドラインにコードや URL を載せない（`powershell -c "... irm <URL>"`、`irm | iex`、`-EncodedCommand`）。Microsoft Defender が Trojan:Win32/Commando として遮断する。ダウンロードはファイルへ、実行は `-File` で（design-notes 8 章）。
- リリース手順: 各 PC は、最新リリースに添付した `install.ps1` で最新リリースの Ecaps を取得するので、**install.ps1 も Ecaps.ahk も、リリースを作るまで他の PC には配布されない**（例外: 旧手順の URL で `main` の install.ps1 を使う人には、main への push で届く）。
  1. AutoHotkey の最新安定版（`winget show --id AutoHotkey.AutoHotkey`）を確認し、ポータブル版 zip を展開して `ECAPS_AHK_EXE=<その AutoHotkey64.exe>` で golden / e2e テストを流す（README の「動作確認」の版も更新）。
  2. `Ecaps.ahk` 冒頭のコメントの「バージョン」「リリース日」を、これから付けるタグとリリースする日に更新する。あわせて、冒頭コメント全体（説明、設置先・自動起動・CapsLock の記述、参照先）が現状と合っているか見直す。
  3. golden / e2e テストに合格する。
  4. main を push → `git tag vX.Y.Z` → `git push origin vX.Y.Z`。
  5. `gh release create vX.Y.Z --generate-notes install.ps1` でリリースを作る（Web 画面で作る場合も install.ps1 を添付する）。**install.ps1 を添付し忘れると、全 PC のインストール・更新が 404 で止まる。**
  6. `curl.exe -fsSIL https://github.com/nofukao/Ecaps/releases/latest/download/install.ps1` が通ることと、README の 2 行をこの PC で実行して新しい版に更新されることを確かめる。
