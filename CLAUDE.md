# Ecaps — 作業ルール

- 設計判断・AHK v2 の落とし穴は [docs/design-notes.md](docs/design-notes.md) にまとめてある。変更前に目を通す。
- **`Ecaps.ahk` を変更したら、完了報告の前に必ずゴールデンテストを実行する**（手順・制約は design-notes 7 章）。
  - `python tests/golden_test.py` で比較し、差分が意図した変化だけであることを確認してから `--update` で golden を更新し、スクリプトと一緒にコミットする。
  - 新しいキーバインドを足したら、`tests/golden_test.py` の `CASES` にもケースを足す。
  - 他の AutoHotkey が常駐しているとテストは中止される。常駐 Ecaps は UIA 版でこちらから終了できないので、ユーザーにトレイから Exit してもらう。RDP 越しの場合は RDP ウィンドウを最小化しないよう伝える。
  - テストで確かめられない挙動（Alt 等を押したままの連打、IME、RDP 前面時の無効化）は、ユーザーに実機確認を依頼する。
- 構文チェックは `"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut /validate Ecaps.ahk`。
- コミットメッセージは日本語で、理由（なぜ）を書く。
