# Ecaps 設計ノート

このドキュメントは、本リポジトリで AHK v2 のスクリプトを保守・拡張する際に、過去のチャットや調査で得た知見を将来の自分（および Claude）が素早く吸収するための要約です。

- **対象スクリプト**: `Ecaps.ahk`
- **前提環境**: Windows 11 / 日本語 109 キーボード / AutoHotkey v2.0 以降
- **設計コンセプト**: 物理 CapsLock を F13 にリマップし、`F13 + key` で Emacs / Unix シェル風のキーバインドを提供。本物の Ctrl は極力使わないので Windows ネイティブの `Ctrl+S` 等もそのまま動く。

---

## 1. AHK v2 の落とし穴

### 1.1 カスタムコンボにモディファイア前置記号は付けられない

AHK のホットキー構文は **2 系統**ある:

| 構文 | 例 | 機構 |
|---|---|---|
| (A) 標準ホットキー: `<modifiers><key>::` | `!h::`, `^c::`, `+!s::` | OS のモディファイアフラグ（Alt/Shift/Ctrl/Win）を見る |
| (B) カスタムコンボ: `<key1> & <key2>::` | `F13 & t::`, `Numpad0 & 1::` | AHK の低レベルキーボードフックでキー押下順を見る |

**(A) と (B) を混ぜることはできない**。具体的には:

```ahk
+F13 & t::          ; ✗ 構文エラー（モディファイア + カスタムコンボ）
^F13 & t::          ; ✗ 同上
```

`F13` は OS から見れば普通のファンクションキーであり、Shift/Ctrl/Alt/Win のような正規のモディファイアではないため、(A) の前置記号にぶら下げられない。

**回避策**: ハンドラ内で物理キー状態を見る。

```ahk
F13 & t::{
    if GetKeyState("Shift", "P")
        Send("+{Tab}")
    else
        Send("{Tab}")
}
```

本リポジトリではこの定型を `SendAndUnmarkShifted(plain, shifted)` として括り出しており、`F13 & t::SendAndUnmarkShifted("{Tab}", "+{Tab}")` のように 1 行で書ける。

### 1.2 行頭の `+` は前行の式継続として連結される

AHK v2 は行頭が `+` `-` `*` `&` などの**二項演算子になり得る記号**で始まると、前行の続きとして解釈する。例えば:

```ahk
F13 & t::SendAndUnmark("{Tab}")
+F13 & t::SendAndUnmark("+{Tab}")
```

これは内部で 1 行に連結され、`t::` が三項演算子の `:` と誤認されて `A ":" is missing its "?"` エラーになる。

仮に上記の構文（モディファイア＋カスタムコンボ）が許されたとしても、行頭 `+` の連結問題で破綻するので、結局 `GetKeyState` 方式が唯一の正解になる。

### 1.3 JP 109 ではシフト記号文字がカスタムコンボのサフィックスで衝突する

JP 109 キーボードに「`'` 専用キー」は存在せず、`'` は **Shift+7** で入力する文字。AHK のカスタムコンボ (B) はサフィックスのスキャンコードでフックを登録し、**Shift の有無は見ない**ため:

```ahk
F13 & 7::Send("{F7}")               ; sc008 に登録
F13 & '::Send("{Blind}^'")          ; 同じ sc008 に登録 → 後勝ち
```

結果として `F13+7` を押しても後者が発火し、`F7`（IME 全角カタカナ変換等）が機能しない。同様の問題は `<` (Shift+,)、`>` (Shift+.) など**シフト記号で出る文字**全般で起こり得る。

**対策**: そのキーを使うフォールバックは消すか、本当に Shift 込みで使いたければ `GetKeyState("Shift", "P")` 分岐で実装する。

参考: 標準ホットキー (A) では `!<` のような書き方は **問題なく動く**。これはサフィックス文字の解決時に Shift も暗黙に含めて登録するため。**(B) と (A) で挙動が違う**点に注意。

### 1.4 英字キー名はケース不問

`F13 & T::` と `F13 & t::` は同じキー（`t` キー）を指す。**`T` と書いても Shift+t にはならない**。Shift で分岐したいなら 1.1 の `GetKeyState` 方式。

### 1.5 SendInput（v2 の既定）は送出中にフックを外す → 押し続けると素の文字が漏れる

**症状**: VSCode 等で `F13+p` を押し続けると、カーソルが上へ動き続けるが、途中で `p` が入力される（`F13+n` / `F13+f` も同様）。

**原因**: v2 の `Send` は既定で SendInput。AHK のヘルプ（SendMode）には「スクリプトが低レベルキーボードフックを持っていると、SendInput は実行前にそれを外し、実行後に付け直す」とある。押し続けるとオートリピートのたびにホットキーが走って Send → フックの付け外しが繰り返され、

- フックが外れている隙に届いたリピートは、Ecaps を素通りしてアプリに `p` として入る
- `#HotIf` が一般の式（`!ShouldYieldToRDP()` 等）だと、フック側はメインスレッドでの式評価を待つ。メインスレッドは SendInput の中でフックの付け外しを待っており、互いに待ち合う。Windows の低レベルフックのタイムアウト（既定 300 ms）を超えると素のキーが流れ、11 回目でフック自体が外される

RDP 越しのキー入力は詰まって届きやすく、リピートの間隔が実質短くなるので起きやすい。v1 は既定が SendEvent だったため、v1 からの移植時に顕在化した可能性が高い。

**対策**: スクリプト冒頭で `SendMode("Event")`。SendEvent はフックを外さない（自分の送出はフックが識別して無視する）。ゴールデンテスト（7 章）で、送出キー列が変わらないこと、長押しで漏れ・取りこぼしがないことを確認済み。副次効果として、SendInput 時に出ていた余計な Ctrl 打鍵（フック付け直しの副作用）も消えた。

**採用しなかった案**: `#HotIf` を最適化される形（`!WinActive("ahk_group ...")` のように WinActive/WinExist 1 回だけ、引数は文字列リテラル）にしてメインスレッド待ちを無くす案。単独で試したところ漏れは減ったが残り、さらに実機で Alt 系（`Alt+f` 等）が効かなくなったと報告された（ゴールデンテストでは再現せず原因未特定）。SendEvent 化で待ち合いの原因（SendInput 中のフック付け外し）自体が無くなるので見送った。

---

## 2. Mark（選択モード）ヘルパーの設計方針

`F13+Space` で `Mark.Active` をトグルする選択モードがある。Active 中、移動キーは `SendMove` 経由で Shift+矢印として送られ、選択範囲を広げられる。

### ヘルパー一覧

| 関数 | 用途 | Mark への影響 |
|---|---|---|
| `SendMove(key)` | 移動キー（Mark 状態に応じて Shift を付け足す） | **保持** |
| `SendAndUnmark(keys)` | テキスト変更 / 選択を消費する操作（Del, Enter, Tab, ^x, ^c, ^v 等） | **解除** |
| `SendAndUnmarkShifted(plain, shifted)` | Shift 押下で送出キーを切り替え（Tab / Shift+Tab 等） | **解除** |
| `DeleteRange(rangeKey)` | (Shift+移動)→Del で範囲削除（kill-line, kill-word 等） | **解除** |

### 使い分けのルール

新しいキーを追加するときは以下の問いで決める:

1. **カーソル移動だけか？** → `SendMove`
2. **テキストを変更する／選択を消費するか？** → `SendAndUnmark`
3. **範囲削除（先に選択→削除）か？** → `DeleteRange`
4. **Shift で挙動を分岐したいか？** → `SendAndUnmarkShifted`
5. **編集と無関係か？（IME 切替, F1-F10, Save, Undo, マウス等）** → ヘルパー無しの素の `Send`

### 例外として "ヘルパー無し" を選んでいる箇所

- **F13 & 1〜0 (F1-F10)**: F-キーは選択や本文に作用しないので Mark を触らない
- **F13 & j / i (IME ON/OFF)**: Mark とは独立した状態
- **F13 & s (Save)**: Emacs の `save-buffer` も Mark を非活性化しないので倣っている
- **F13 & / と F13 & z (Undo)**: Emacs の `undo` は mark を残す。なお Undo が 2 箇所ある（フォールバック群との重複）のは意図的
- **Ctrl+キーフォールバック群** ([Ecaps.ahk] L295 付近): 何が起きるかアプリ依存なので保守的に Mark に触らない
- **マウス系**: Ctrl+クリックは選択拡張の用途もあるので触らない

---

## 3. ショートカット拡張の判断基準

新規ショートカットを足すかは以下を満たすかで判断:

1. **Emacs / shell / Linux / Windows いずれかの強い慣習に乗っているか**（独自考案より既存の慣習に乗る）
2. **複数文脈で意味が揃うか**（例: `Ctrl+R` はシェル reverse-i-search / ブラウザ reload / エディタ replace と「巻き戻す・再びやる」で揃う）
3. **既存定義と衝突しないか**（特に同じスキャンコードで衝突する JP 109 のシフト文字に注意）
4. **JP 109 キーボードで自然に打てるか**

過去に検討して不採用にしたもの（理由付き）:

| 案 | 不採用理由 |
|---|---|
| `F13 & s` を Emacs `C-s` (検索) に振り直す | 既に Save で Windows 慣習に振っており、変更は重大 |
| `M-.` (`yank-last-arg`) | Bash 限定の魔法で Windows 全般に翻訳できない |
| `C-t` (`transpose-chars`) | `F13 & t = Tab` と衝突。Tab の優先度が遥かに高い |
| `M-q` (`fill-paragraph`) | Emacs 専用、汎用 Windows ショートカット無し |
| `M-u/l/c` (大文字小文字変換) | Windows 横断の標準キーが無い |

将来の候補（未採用）:

- `!x::Send("^+p")` — Emacs `M-x` を VSCode/JetBrains の Ctrl+Shift+P (コマンドパレット) にブリッジ
- `!/::Send("^{Space}")` — Emacs `M-/` (dabbrev-expand) を IDE のオートコンプリートにブリッジ

---

## 3.5 ターミナル/コンソール分岐（GUI と端末で送るキーを変える）

### 背景

本スクリプトの編集系は当初すべて **GUI 流の idiom** で実装されていた:

- 範囲削除（kill-line / kill-word）= **(Shift+移動) → Del** の「選択してから削除」
- カット/コピー/ペースト = **Ctrl+X / Ctrl+C / Ctrl+V**（クリップボード）
- Set Mark = 自前の `Mark.Active` トグル＋移動キーに Shift を付加して選択拡張

これは GUI エディタや **ローカル PowerShell の PSReadLine** では動くが、**ターミナルの行編集器（Linux の readline/bash、PuTTY 等）では破綻する**。端末には「選択範囲」も「クリップボード」も存在せず、行編集は **制御文字（readline = Emacs 由来の割当）** で行うのが唯一の方法だから。

具体的な破綻:

| 操作 | GUI 送出 | 端末での結果 |
|---|---|---|
| `F13+u` 行頭まで削除 | `Shift+Home` → `Del` | WT→SSH: `ESC[1;2H` 等が解釈できず末尾文字が漏れる / PuTTY: Shift 無視で Home へ移動し 1 文字削除 |
| `F13+k` 行末まで削除 | `Shift+End` → `Del` | WT→SSH: `ESC[1;2F` の末尾 `F` が入力される / PuTTY: End へ移動するだけ |
| `F13+Space`→`w`(C-x)→`y`(C-v) | クリップボード | Ctrl+X/V は端末でクリップボードにならず効かない（Ctrl+V は quoted-insert） |

readline は Emacs キーをエミュレートしているので、**端末では Emacs/readline の制御キーをそのまま送れば 1:1 で正しく動く**。

### 実装

- **`IsConsole()`**: アクティブウィンドウが端末/コンソールかを判定（`WindowsTerminal.exe` / `OpenConsole.exe` / `ahk_class PuTTY` / `ConsoleWindowClass`(cmd・PowerShell) / `mintty.exe` / `ttermpro.exe`）。`IsRDPActive()` と同じ要領。
- **`KillToEdge(consoleKey, guiRangeKey)`**: 端末なら `SendAndUnmark(consoleKey)`、GUI なら従来の `DeleteRange(guiRangeKey)`。
- **`SendMove`**: 端末では Mark 中でも Shift を付けない（readline は mark〜point を region として持つ）。

| F13/Alt 操作 | GUI | 端末（readline） |
|---|---|---|
| `F13+u` | `Shift+Home`→Del | `Ctrl+U`（backward-kill-line） |
| `F13+k` | `Shift+End`→Del | `Ctrl+K`（kill-line） |
| `F13+Space` | `Mark.Toggle()` | `Ctrl+Space`（set-mark） |
| `F13+w` | `Ctrl+X` | `Ctrl+W`（kill-region） |
| `Alt+w` | `Ctrl+C` | `Alt+w`（M-w = kill-ring-save / コピー） |
| `F13+y` | `Ctrl+V` | `Ctrl+Y`（yank） |
| `Alt+d` | `Ctrl+Shift+Right`→Del | `Alt+d`（kill-word） |
| `Alt+h` | `Ctrl+Shift+Left`→Del | `Ctrl+W`（backward-kill-word） |

### 制約・判断

- **Windows Terminal は「ローカル PowerShell」と「SSH 先 bash」を同一ウィンドウで扱い、ウィンドウ属性から区別できない**。端末用キーは両方に送られる。Ctrl+U/K/W/Y/Space は PSReadLine の Emacs 編集モード（`Set-PSReadLineOption -EditMode Emacs`）で readline と一致するので、ローカル側を Emacs モードにすると整合する。
- **`F13+c` は変更しない**: 端末では `Ctrl+C`=SIGINT で、それがむしろ正しい挙動。
- **`Alt+w`（コピー）は端末で本物の `Alt+w`(M-w) を送る**: GUI 用の `Ctrl+C` を emacs -nw に送ると `C-c`（プレフィックスキー）待ちになりコピーできない。emacs のリージョンコピーは `M-w`=kill-ring-save なので、端末ではそのまま `Alt+w` を送る（bash readline では未割当で無害）。`!w::` から `Send("!w")` しても、既定 SendLevel では自ホットキーを再発火しない（`!d` と同型）。
- **`F13+x` / `F13+v` はスコープ外（現状維持）**: 端末で `F13+v`=`Ctrl+V` は quoted-insert になり不適切だが、今回は触らない。将来、端末ペースト（WT=`Ctrl+Shift+V` / PuTTY=`Shift+Insert`）へ振る余地あり。
- **`F13+d`(Del) / `F13+h`(BS) はそのままで端末でも正しい**ので分岐不要。

### VSCode 内蔵ターミナル

VSCode はエディタもターミナルも同じ `Code.exe` のウィンドウなので、`IsConsole()`（ウィンドウ単位の判定）では区別できない。以前は VSCode を常に GUI 扱いしていたため、ターミナル（Git Bash）で `F13+k` が `Shift+End`→Del になり、xterm.js が送る `ESC[1;2F` を readline が解釈できず **`F` が入力**されていた（`F13+u` は `H`）。

**方針**: 複数 PC で使うので、VSCode の設定（`window.title` や keybindings.json）は変えず、Ecaps 側だけで解決する。

- **判定 `IsVSCodeTerminal()`**: `Code.exe` が前面のときだけ UI Automation でフォーカス中の要素を問い合わせ、クラス名が `xterm-helper-textarea`（xterm.js の入力欄）なら内蔵ターミナル。エディタは別のクラス（`RootWebArea` 等）、Claude Code の入力欄は `messageInput_*`。1 回 0〜16 ms 程度で、実機で VSCode 側の副作用（スクリーンリーダー検出の通知等）が出ないことを確認済み。
  - Chromium は最初の問い合わせでアクセシビリティを有効化し、その 1 回だけルート要素（クラス `View`）を返す。そのときは 30 ms 待って取り直す。
  - VSCode が応答しないとホットキー処理（メインスレッド）ごと止まるので、`IUIAutomation2` で接続・トランザクションのタイムアウトを 200 ms に縮めている（既定は 2 秒 / 20 秒）。タイムアウト時は GUI 扱いになる。
- **送出キー `TermKey()`**: 判定が「端末」になっても、VSCode は一部のキーをシェルに渡さず自分で使う。`Ctrl+K` は chord（`Ctrl+K Ctrl+C` 等）の 1 打目として横取りされる（`terminal.integrated.allowChords` 既定 true）。そこで VSCode では、**既定設定のまま同じ制御文字がシェルに届くキー**に置き換える:

| readline | 端末ウィンドウ | VSCode 内蔵ターミナル | 理由 |
|---|---|---|---|
| kill-line | `Ctrl+K` | 文字 `U+000B` を直接送る | Ctrl+K は chord として横取りされる |
| kill-word | `Alt+d` | `Ctrl+Del` | VSCode 既定で `ESC d` をシェルへ送る |
| set-mark | `Ctrl+Space` | `Ctrl+Shift+2` | VSCode 既定で NUL をシェルへ送る（Ctrl+Space は補完に取られ得る） |
| その他 (`Ctrl+U/W/Y`, `Alt+w`) | 同じ | 同じ | そのまま届く |

  VSCode が既定でシェルへ送るキーは `workbench.desktop.main.js` の `workbench.action.terminal.sendSequence` 登録（`Ctrl+Backspace`→`^W`、`Ctrl+Del`→`ESC d`、`Ctrl+Shift+2`→NUL 等）で確かめられる。
- 実際に bash まで届くかは `tests/vscode_terminal_test.py`（7 章）で確認する。


## 4. RDP セッション周りの注意

`Ecaps.ahk` はローカル PC / RDP 接続先 PC の双方で同時起動されることを想定:

- **`IsLocalConsole()`**: SM_REMOTESESSION で「自分はローカルか」を起動時に一度だけ判定し static でキャッシュ
- **`IsRDPActive()`**: アクティブウィンドウが mstsc.exe か
- **`ShouldYieldToRDP()`**: ローカル AHK が RDP ウィンドウ前面のとき、ホットキーを丸ごと無効化してリモートに譲る
- **IME 制御**: ローカルでは `WM_IME_CONTROL` を直接送るが、RDP 経由では Windows メッセージが転送されないので 4 ステップのキーシーケンス（VK_IME_OFF → 半角/全角 → Shift+無変換 ×2）にフォールバック

新規ホットキーを足す際、IME や IME 風の状態切替を含むものは **RDP 配下でも動くか**を別途検討する必要がある。

---

## 5. トラブルシュート時のチェックリスト

ホットキーが期待通りに動かないとき、以下を順に疑う:

1. **同じスキャンコードに別ホットキーが重複登録されていないか？**（特に JP 109 のシフト文字: `'`=Shift+7, `<`=Shift+, など）
2. **行頭が `+` `-` `*` `&` などで始まり、前行と連結されていないか？**
3. **`+F13 & X::` のようにモディファイアをカスタムコンボに付けていないか？**
4. **F13 が物理 CapsLock として ChangeKey 等で正しくリマップされているか？**
5. **RDP 配下なら `ShouldYieldToRDP()` で無効化されている可能性**
6. **`Send("{Blind}...")` の有無**（モディファイア状態を維持したいか/しないかで使い分け）
7. **押し続けると途中から素の文字が入る → `SendMode("Event")` が外れていないか？**（1.5）
8. **ゴールデンテスト（7 章）を流し、送出キー列の変化を確認する**

---

## 6. コミット・運用メモ

- コミットメッセージは日本語で、**理由（なぜ）** を明示する
- 単純な機能追加でも「Emacs 由来か」「Windows 慣習か」「JP 109 制約か」など背景を 1 行入れる
- README.md には「ユーザが見る」キーバインドを表で並べ、技術的な制約や設計判断はコードコメントか本ドキュメントに置く
- `Ecaps.ahk` を変更したら、コミット前に必ずゴールデンテスト（7 章）を実行する

---

## 7. ゴールデンテスト

`tests/golden_test.py`（Python 3、依存ライブラリ無し）で、キー入力に対して Ecaps が**実際に送出するキーイベント列**を記録し、`tests/golden/<ケース名>.txt` と比較する。

```
python tests/golden_test.py            # 比較 (全ケース合格で exit 0)
python tests/golden_test.py --update   # golden を現在の結果で作り直す
python tests/golden_test.py -k alt     # 名前に alt を含むケースだけ
```

### 仕組み

1. テスト自身が低レベルキーボードフック（レコーダ）を**先に**登録し、その後で `Ecaps.ahk` を起動する。低レベルフックは後から登録したものが先に呼ばれるので、レコーダには **Ecaps を通過したイベントだけ**が届く（Ecaps が握り潰したキーは届かない）。
2. テスト用の空ウィンドウ（GUI 用クラス / `ConsoleWindowClass`）を前面にし、SendInput で `F13+f` 等を入力する。`ConsoleWindowClass` のウィンドウは `IsConsole()` が真になるので、端末向けの分岐も確かめられる。
3. 記録の各行は `<送信元> <down|up> <キー名>`。`drv` はテストが送ったキーが素通りしたもの、`ahk` は Ecaps が生成したもの。押し続けケース（`*_hold_*`）は回数の要約を golden にする。**`drv down F` のような行が出たら、素の文字が漏れている**。

### 手順（変更時）

1. 変更前に `python tests/golden_test.py` が全合格することを確認
2. `Ecaps.ahk` を変更
3. 再実行し、差分が**意図した変化だけ**であることを確認（新しいキーを足したら `CASES` にケースも足す）
4. 意図どおりなら `--update` で golden を更新し、スクリプトと一緒にコミット
5. 端末向けの送出（`TermKind` / `TermKey` / `KillToEdge` 等）に関わる変更なら、`python tests/vscode_terminal_test.py` も全合格することを確認（下記）

### 制約

- 実行中（1 分弱）はキーボード・マウスに触れない。RDP 越しなら RDP ウィンドウを最小化しない（SendInput がアクセス拒否で失敗する）。
- 入力は送る直前に毎回、前面がテスト用ウィンドウか確かめ、違えば中止する（ユーザーのアプリへの誤入力防止）。
- 常駐中の Ecaps など他の AutoHotkey が動いていても実行できる。テスト対象のフックが最後に登録されて最初に呼ばれ、レコーダはその直後なので記録は影響を受けない。Ecaps は `SendMode("Event")` 固定なので、他スクリプトの存在で送出方式が変わることもない。テスト対象は非 UIA の `AutoHotkey64.exe` で起動する（UIA 版は CreateProcess で起動できない）。
- 入力は SendInput による注入なので、AHK からは「物理的には押されていない」キーに見える。そのため **Alt 等の修飾キーを押したまま連打する挙動は実機と異なる**（Send 後に Alt が押し直されない）。この種の変更は実機でも手で確認する。
- IME 切替（`F13+j/i`）、サスペンド、マウス、RDP 前面時の無効化はテスト対象外。

### VSCode 内蔵ターミナルの e2e テスト

`golden_test.py` は「Ecaps が何を送ったか」しか見ないが、VSCode のターミナルではキーが bash に届くかが VSCode 次第なので、`tests/vscode_terminal_test.py` で **bash が実際にどう編集したか**を確かめる。

```
python tests/vscode_terminal_test.py          # 全ケース合格で exit 0
python tests/vscode_terminal_test.py --keep   # 終了後も VSCode を閉じない (調査用)
```

- 使い捨ての `--user-data-dir` / `--extensions-dir` で VSCode を別インスタンス起動する。**ユーザーの VSCode 設定には触れない**（既定設定のまま、既定プロファイルを Git Bash にし、初回のサインイン案内等を切るだけ）。
- ターミナルで「行を打つ → Ecaps のキー → `>> "$O"` で echo の結果をファイルへ追記」を繰り返し、期待値と比べる。
- 文字やキーを送る前に、`tests/uia_focus.ahk` でフォーカスがテスト用 VSCode のターミナル入力欄（`xterm-helper-textarea`）にあることを確かめ、無ければ中止する。初回起動時のダイアログ等に Enter が誤爆するのを防ぐため。
- VSCode の中（Claude Code 等）から起動すると `ELECTRON_RUN_AS_NODE=1` が継承され、Code.exe が Node として動いてしまうので、`VSCODE_*` / `ELECTRON_*` を除いた環境で起動している。
