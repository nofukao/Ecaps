# Ecaps

nWindows 上で Emacs / Unix シェル風のキーバインドを実現する AutoHotkey v2 スクリプト。

物理 **CapsLock** キーを **F13** に割り当てた上で、`F13 + key` の組合せに Emacs 風の操作を割り当てます。Windows 既定の Ctrl ショートカット（`Ctrl+S` / `Ctrl+C` 等）はそのまま使えるため、Windows と Emacs の操作体系を両立できます。

- **対象**: AutoHotkey **v2.0** 以降（動作確認: 2.0.24 / 2.0.29）
- **前提**: 日本語 109 キーボード
- **作者**: nofukao

---

## 目次

- [特徴](#特徴)
- [インストール](#インストール)
- [基本概念](#基本概念)
- [キーバインド一覧](#キーバインド一覧)
  - [カーソル移動](#カーソル移動)
  - [編集・削除](#編集削除)
  - [選択・コピー・カット・ペースト](#選択コピーカットペースト)
  - [ファンクションキー](#ファンクションキー)
  - [ファイル・システム操作](#ファイルシステム操作)
  - [履歴検索・再読込・置換](#履歴検索再読込置換)
  - [日本語入力 (IME) 制御](#日本語入力-ime-制御)
- [技術的補足](#技術的補足)
- [特定アプリでの無効化](#特定アプリでの無効化)

---

## 特徴

- ホームポジションを崩さず Emacs 風カーソル移動・編集
- `F13 + Space` で **Set Mark**（選択モード）— Emacs の挙動を再現
- 日本語入力の **ON / OFF を直接制御**（トグルではない確定動作）
- **ターミナル/コンソール** (Windows Terminal, PuTTY, cmd, Git Bash 等) では、削除・選択・カット/ペーストを Unix シェル (readline) 流の制御キーへ自動で切り替え
- リモートデスクトップ (mstsc.exe) 配下でも IME 制御が動作
- 未定義の `F13 + キー` は自動的に `Ctrl + キー` にフォールバック
- マウス操作も `F13 + クリック / ホイール` → `Ctrl + …` にマップ（拡大縮小等）

---

## インストール

### 1. 物理 CapsLock を F13 に割り当て

Windows のレジストリレベルで CapsLock を F13 (scancode `0x0064`) に変更します。再起動後、CapsLock を押すと OS は F13 として認識します。

代表的な方法:

- **ChangeKey** などのキー割り当て変更ツールを使う
- または `.reg` ファイルでスキャンコードマップを直接書き込む

### 2. AutoHotkey v2 をインストール

[AutoHotkey 公式サイト](https://www.autohotkey.com/) から v2 をダウンロードしてインストールします。

### 3. スクリプトを配置・自動起動

1. `Ecaps.ahk` を任意のフォルダに配置（例: `OneDrive\bin\AutoHotkey\`）
2. `Win + R` → `shell:startup` を実行してスタートアップフォルダを開く
3. `Ecaps.ahk` のショートカットをそこに配置 → Windows 起動時に自動実行されます

### 4. (任意) PowerShell を Emacs 編集モードにする

ローカル PowerShell を bash（SSH 先の readline）と同じ行編集にすると、`F13 + u`(行頭まで削除) / `F13 + k`(行末まで削除) などが PowerShell でも期待どおり動きます。PowerShell タブで以下を実行します（管理者権限は不要）。

```powershell
if (!(Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force }
Add-Content -Path $PROFILE -Value 'Set-PSReadLineOption -EditMode Emacs'
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force
```

新しい PowerShell タブを開くと反映されます。背景・補足（`RemoteSigned` の意味、PowerShell 7 の別プロファイル等）は [PowerShell を SSH 先と一致させる](#powershell-を-ssh-先と一致させるpsreadline-の-emacs-モード) を参照してください。

---

## 基本概念

### 修飾キーとしての F13 (= 物理 CapsLock)

本ドキュメントで `F13` と表記しているキーは、すべて **物理的な CapsLock キー** を指します。インストール手順 1 でリマップ済みなので、CapsLock を押しながら他のキーを押すことで、以下のキーバインドが発動します。

### Set Mark（選択モード）

`F13 + Space` で選択モードのトグルが切り替わります。アクティブな間はカーソル移動キーが `Shift + 矢印` として送出され、範囲選択を伸ばせます。コピー・カット・編集系のコマンドを実行すると自動的にリセットされます。

ターミナル/コンソールでは仕組みが異なり、`F13 + Space` は readline の set-mark（`Ctrl+Space`）を送り、移動キーは `Shift` を付けずにそのまま送出します（端末は mark〜カーソル間を region として扱うため）。詳細は [ターミナル/コンソールでの挙動](#ターミナルコンソールでの挙動) を参照。

---

## キーバインド一覧

### カーソル移動

| キー操作 | 動作 | Emacs 由来 |
|---|---|---|
| `F13 + f` | 1 文字右へ (→) | forward-char |
| `F13 + b` | 1 文字左へ (←) | backward-char |
| `F13 + n` | 1 行下へ (↓) | next-line |
| `F13 + p` | 1 行上へ (↑) | previous-line |
| `F13 + a` | 行頭へ (Home) | beginning-of-line |
| `F13 + e` | 行末へ (End) | end-of-line |
| `Alt + f` | 単語右へ (Ctrl+→) | forward-word |
| `Alt + b` | 単語左へ (Ctrl+←) | backward-word |
| `Alt + n` | ページダウン (PgDn) | scroll-up |
| `Alt + p` | ページアップ (PgUp) | scroll-down |
| `Alt + <` | 文書先頭へ (Ctrl+Home) | beginning-of-buffer |
| `Alt + >` | 文書末尾へ (Ctrl+End) | end-of-buffer |

### 編集・削除

| キー操作 | 動作 | Emacs 由来 |
|---|---|---|
| `F13 + d` | カーソル右の 1 文字を削除 (Del) | delete-char |
| `F13 + h` | カーソル左の 1 文字を削除 (BS) | backward-delete-char |
| `F13 + k` | カーソル位置から行末まで削除 | kill-line（端末: `Ctrl+K`） |
| `F13 + u` | 行頭からカーソル位置まで削除 | 端末: `Ctrl+U` |
| `Alt + d` | カーソル位置から単語末まで削除 | kill-word（端末: `Alt+d`） |
| `Alt + h` | 単語頭からカーソル位置まで削除 | backward-kill-word（端末: `Ctrl+W`） |
| `F13 + m` | 改行 (Enter) | newline |
| `F13 + t` | タブ (Tab) | — |
| `F13 + /` | 元に戻す (Ctrl+Z) | undo |

### 選択・コピー・カット・ペースト

| キー操作 | 動作 | 備考 |
|---|---|---|
| `F13 + Space` | **選択モード開始 / 終了** | 押下後、移動キーで範囲選択（端末: `Ctrl+Space` = set-mark） |
| `F13 + w` | カット (Ctrl+X) | Emacs `C-w`（端末: `Ctrl+W` = kill-region） |
| `F13 + x` | カット (Ctrl+X) | Windows 互換 |
| `Alt + w` | コピー (Ctrl+C) | Emacs `M-w`（端末: `Alt+w` = kill-ring-save。emacs 等で有効） |
| `F13 + c` | コピー (Ctrl+C) | Windows 互換（端末では `Ctrl+C` = 中断/SIGINT） |
| `F13 + y` | ペースト (Ctrl+V) | Emacs `C-y` (Yank)（端末: `Ctrl+Y` = yank） |
| `F13 + v` | ペースト (Ctrl+V) | Windows 互換 |
| `F13 + g` | キャンセル (Esc) | Emacs `C-g` |
| `F13 + [` | エスケープ (Esc) | — |

### ファンクションキー

| キー操作 | 動作 |
|---|---|
| `F13 + 1` ～ `F13 + 9` | `F1` ～ `F9` |
| `F13 + 0` | `F10` |

### ファイル・システム操作

| キー操作 | 動作 | 備考 |
|---|---|---|
| `F13 + s` | 上書き保存 (Ctrl+S) | save-buffer |
| `F13 + @` | スクリプトのサスペンド (トグル) | 動作 ON / OFF |
| `Pause` | スクリプトのサスペンド (トグル) | 同上 |
| `Ctrl + @` | スクリプトのサスペンド (トグル) | 同上 |

サスペンド中はタスクトレイのアイコンが切り替わり、状態が一目でわかります。

### 履歴検索・再読込・置換

| キー操作 | 動作 | 主な用途 |
|---|---|---|
| `F13 + r` | `Ctrl + R` | シェルでの履歴逆検索 (reverse-i-search) / ブラウザのページ再読込 / エディタの置換ダイアログ |

Emacs の `C-r` (`isearch-backward`) を Windows 環境にブリッジする位置付けです。`Ctrl + R` はアプリによって意味が変わりますが、いずれも **「巻き戻す / 再びやる」** 系統の操作で文脈横断的に整合します。

### 日本語入力 (IME) 制御

Windows の IME ステータスを **直接制御** します。「半角/全角」キーのトグル動作と異なり、現在の状態に依らず確定的に ON / OFF できます。

| キー操作 | 動作 | 詳細 |
|---|---|---|
| `F13 + j` / `Ctrl + Alt + j` | 日本語入力 **ON** | IME ON ＋ 入力モード「半角英数」で待機 |
| `F13 + i` / `Ctrl + Alt + i` | 日本語入力 **OFF** | IME OFF（直接入力） |

`F13 + j` で「IME ON だが半角英数」という状態になるのは、日本語キーボードで日本語と英語を混在入力する際に都合が良いためです。必要に応じて `F10` で全角英数 / `F9` で全角ひらがなに切り替えてください。

> **リモートデスクトップ対応**: アクティブウィンドウが `mstsc.exe` の場合、Windows メッセージは遠隔 PC へ転送されないため、内部的にキー入力シーケンス（`VK_IME_OFF` → `半角/全角` → `Shift+無変換` ×2）に切り替えて同等の状態を再現します。MS-IME の「前回モードを記憶」設定が ON だと崩れる可能性があるため、OFF を推奨します。

---

## 技術的補足

### 未定義キーのフォールバック

スクリプト後半で、Emacs キーバインドとして定義されていない `F13 + キー`（例: `F13 + z`, `F13 + l`, `F13 + q` など）は **通常の `Ctrl + キー`** として動作するように記述されています。

これにより、定義外の Windows ショートカットも CapsLock を Ctrl 代わりに使って実行できます。

### マウス操作

`F13` を押しながらのマウス操作は `Ctrl + マウス操作` として動作します:

| キー操作 | 動作 |
|---|---|
| `F13 + 左クリック` | `Ctrl + 左クリック` |
| `F13 + 右クリック` | `Ctrl + 右クリック` |
| `F13 + 中クリック` | `Ctrl + 中クリック` |
| `F13 + ホイール上 / 下` | `Ctrl + ホイール`（多くのアプリで拡大縮小） |
| `F13 + ホイール左 / 右` | `Ctrl + 横ホイール` |

### 選択モード (Mark) の挙動

`F13 + Space` で内部状態 `Mark.Active` が `true` になり、以降のカーソル移動コマンドは `Shift + 矢印` として送信されます。コピー・カット・改行・削除など編集系の操作を行うと自動でリセットされます。`Enter` キー単独でもリセットされる仕様です。

### ターミナル/コンソールでの挙動

GUI アプリの行編集は「**選択してから削除**」「**クリップボード**」で行いますが、ターミナルの行編集器（Linux の `readline`/bash、PuTTY など）には選択範囲もクリップボードも存在しません。これらは Emacs 由来の**制御文字**（`Ctrl+U` / `Ctrl+K` / `Ctrl+W` / `Ctrl+Y` / `Ctrl+Space` …）で編集します。

そのためアクティブウィンドウがターミナル/コンソールのときは、削除・選択・カット/ペーストを自動で readline 流の制御キーに切り替えます（GUI 流の「Shift+移動 → Del」「Ctrl+X/V」を送ると、端末では文字化けや誤動作になるため）。

| 判定対象 | 例 |
|---|---|
| Windows Terminal | `WindowsTerminal.exe` / `OpenConsole.exe` |
| PuTTY | ウィンドウクラス `PuTTY` |
| 旧コンソール | `cmd` / `PowerShell`（`ConsoleWindowClass`） |
| Git Bash / Cygwin / WSL | `mintty.exe` |
| Tera Term | `ttermpro.exe` |

#### 注意点：中で動くプログラムまでは判定できない

ターミナルが前面かどうかは判定できますが、**その中で動いているのが bash なのか emacs なのかローカルシェルなのかまでは AHK からは分かりません**。送る制御キーは同じでも、受け手のプログラムごとに意味が変わります。

| 中で動くもの | `F13+k`（Ctrl+K） | `F13+u`（Ctrl+U） |
|---|---|---|
| **bash（readline）** | 行末まで削除 ✅ | 行頭まで削除 ✅ |
| **emacs -nw** | `C-k` = kill-line（行の途中で有効） | `C-u` = universal-argument（数引数。emacs には「行頭まで削除」の標準キーが無い） |
| **ローカル cmd / 既定の PowerShell** | 未割当 → `^K` がそのまま表示 | 未割当 → `^U` がそのまま表示 |

- **emacs -nw** では F13 は実質 Ctrl として働き、**emacs 本来のキー**になります（これは仕様です）。`F13+k`(C-k) は行の途中にカーソルがあれば kill-line として効きます（行末では消す対象が無く無反応に見えます）。`F13+u`(C-u) は emacs の数引数（universal-argument）で、行頭まで削除する標準キーは emacs 側に存在しません。
- **ローカルの cmd / PowerShell** で `^U` `^K` がそのまま入力されてしまう場合は、下記「PowerShell を SSH 先と一致させる」を参照してください（`cmd.exe` は行編集の制御キーを持たないため非対応）。

> **Windows Terminal の制約**: 同一ウィンドウで「ローカル PowerShell」と「SSH 先 Linux」を扱うため、両者をウィンドウ属性から区別できません。端末用の制御キーは両方に送られます。SSH 先（bash）が正しく動く一方、ローカルシェルでは設定次第で `^U`/`^K` になる、というトレードオフが残ります（PuTTY は常に readline なので問題ありません）。

#### PowerShell を SSH 先と一致させる（PSReadLine の Emacs モード）

ローカル PowerShell を SSH 先（readline）と同じ挙動にするには、PSReadLine を **Emacs 編集モード**にします。これで `Ctrl+U`(行頭まで) / `Ctrl+K`(行末まで) / `Ctrl+W` / `Ctrl+Y` / `Ctrl+Space` が bash と同じ意味になります。

> この設定は **Windows ターミナルの設定画面ではなく、PowerShell のプロファイル**（起動時に毎回読み込まれる `.ps1`）に書きます。

実行する 3 行の役割:

| コマンド | 役割 |
|---|---|
| `if (!(Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force }` | プロファイル未作成なら作成（親フォルダも自動生成。`-Force` は未存在時のみ実行されるので既存ファイルは壊さない） |
| `Add-Content -Path $PROFILE -Value 'Set-PSReadLineOption -EditMode Emacs'` | 起動時に PSReadLine を Emacs 編集モードへ（`Ctrl+U`=行頭まで削除 / `Ctrl+K`=行末まで削除 等が有効化） |
| `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force` | プロファイル（`.ps1`）の実行を許可（既定の `Restricted` では読み込まれない。`-Force` で確認プロンプトを省略） |

**1. プロファイルに追記**（PowerShell タブで実行。無ければ作成して 1 行追記）

```powershell
if (!(Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force }
Add-Content -Path $PROFILE -Value 'Set-PSReadLineOption -EditMode Emacs'
```

**2. スクリプト実行を許可**（Windows PowerShell は既定でプロファイル `.ps1` の実行がブロックされ、起動時に `PSSecurityException`／「スクリプトの実行が無効」エラーになります）

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force   # 管理者権限は不要
```

> `-Force` は変更確認の `[Y/N]` プロンプトを省略します（無人で実行可能）。

`RemoteSigned` は「ローカルで自分が作った `.ps1` は実行可・ダウンロードした未署名スクリプトは不可」という安全寄りの設定です。

**3. 反映**：新しい PowerShell タブを開く（または現タブで `. $PROFILE`）。

補足:
- プロファイルの実体パスは `$PROFILE` で確認できます（通常 `…\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1`）。手で編集するなら `notepad $PROFILE`。
- 現在の実行ポリシーは `Get-ExecutionPolicy -List` で確認できます。
- **PowerShell 7 (`pwsh`)** は別プロファイル（`…\Documents\PowerShell\…`）なので、使う場合はそちらにも同じ追記が必要です。
- 会社管理 PC 等で `MachinePolicy`/`UserPolicy` により実行ポリシーがロックされている場合は変更できません。

### サスペンド時のトレイアイコン

AutoHotkey v2 のデフォルトではサスペンド時のトレイアイコンの差異が小さく状態が判別しづらいため、本スクリプトでは `TraySetIcon` で明示的に切り替えています。AutoHotkey 実行ファイル本体に埋め込まれているアイコン（index 1: 既定 / index 2: サスペンド）を利用するため、追加ファイルなしで動作します。

---

## 特定アプリでの無効化

PuTTY、Vim、GVim、Emacs 本体など **本キーバインドを適用したくないアプリ** がある場合は、スクリプト内の `GroupAdd("NoEcaps", ...)` の隣に、そのウィンドウを `NoEcaps` グループへ追加してください。

```ahk
GroupAdd("NoEcaps", "ahk_class PuTTY")
GroupAdd("NoEcaps", "ahk_class Vim")
```

ローカル PC で動作中のリモートデスクトップ (mstsc) は自動でこのグループに入ります。それ以外はデフォルトで全アプリ有効です。

> `#HotIf` に `||` や自作関数を含む式を書くのは避けてください。キーを押し続けたときにホットキーが外れて素の文字が入力される原因になります（[設計ノート 1.5](docs/design-notes.md)）。
