# Ecaps

Windows 上で Emacs / Unix シェル風のキーバインドを実現する AutoHotkey v2 スクリプト。

物理 **CapsLock** キーを **F13** に割り当てた上で、`F13 + key` の組合せに Emacs 風の操作を割り当てます。Windows 既定の Ctrl ショートカット（`Ctrl+S` / `Ctrl+C` 等）はそのまま使えるため、Windows と Emacs の操作体系を両立できます。

- **対象**: AutoHotkey **v2.0** 以降（動作確認: 2.0.24 / 2.0.29）
- **前提**: Windows 10 / 11、日本語 109 キーボード
- **リポジトリ**: https://github.com/nofukao/Ecaps
- **作者**: nofukao

---

## 目次

- [特徴](#特徴)
- [インストール](#インストール)
  - [(A) AI に依頼する場合](#a-ai-に依頼する場合)
  - [(B) 自分で行う場合](#b-自分で行う場合)
  - [install.ps1 が行うこと](#installps1-が行うこと)
  - [標準の構成](#標準の構成)
  - [更新・移行・アンインストール](#更新移行アンインストール)
  - [手動インストール](#手動インストール)
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
- [困ったときは](#困ったときは)
- [特定アプリでの無効化](#特定アプリでの無効化)
- [テスト](#テスト)

---

## 特徴

- ホームポジションを崩さず Emacs 風カーソル移動・編集
- `F13 + Space` で **Set Mark**（選択モード）— Emacs の挙動を再現
- 日本語入力の **ON / OFF を直接制御**（トグルではない確定動作）
- **ターミナル/コンソール**（Windows Terminal, PuTTY, cmd, Git Bash, **VSCode 内蔵ターミナル** 等）では、削除・選択・カット/ペーストを Unix シェル (readline) 流の制御キーへ自動で切り替え
- ローカル PC と リモートデスクトップ (RDP) 先の両方で動かしても、キーが二重に処理されない
- 一部の `F13 + キー` は `Ctrl + キー` として動作（CapsLock を Ctrl 代わりに使える）
- マウス操作も `F13 + クリック / ホイール` → `Ctrl + …` にマップ（拡大縮小等）
- **2 行のコマンドでインストール・更新**（AI エージェントに頼むこともできる）

---

## インストール

インストールと更新は、[リリース](https://github.com/nofukao/Ecaps/releases)に添付した **`install.ps1`** が行います。AI に頼む場合も自分で行う場合も同じ `install.ps1` が実行されるので、どの PC でも同じ構成になります。

| 方法 | あなたがすること |
|---|---|
| **(A) AI に依頼する** | AI エージェント（Claude Code など）に「https://github.com/nofukao/Ecaps を設定して」と頼む |
| **(B) 自分で行う** | PowerShell で 2 行のコマンドを実行する |

どちらの場合も、AutoHotkey の導入や CapsLock の割り当てが必要なときは **UAC（管理者権限の確認）が 1 回出る**ので「はい」を押してください。CapsLock の割り当てを新しく設定した場合は、**Windows の再起動後**に有効になります。リモートデスクトップ (RDP) で入って使う PC では、再起動の前に [RDP で接続すると英語配列になる](#rdp-で接続すると英語配列になる変換キーが効かない記号の位置が違う) の設定を行ってください（`install.ps1` が必要なときに知らせます）。

### (A) AI に依頼する場合

AI エージェント（Claude Code など）に、次のように頼みます。

```
https://github.com/nofukao/Ecaps を設定して
```

更新するときも同じ依頼（または「最新にして」）でかまいません。途中で UAC の確認が出たら「はい」を押し、最後に AI から「再起動が必要」と報告されたら再起動してください。

#### AI エージェントへの指示

> この節は、上の依頼を受けた AI エージェント向けの手順です。

1. **実行前にユーザーへ伝える**: 次の 3 点を伝えてから実行する。
   - AutoHotkey v2 の導入（winget）と、CapsLock のキー割り当て（レジストリ `HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layout` の `Scancode Map`）を、必要な場合に自動で行うこと。
   - その場合は **UAC の確認が 1 回出るので、ユーザーが「はい」を押す必要がある**こと。
   - キー割り当てを新しく設定した場合は、Windows の再起動が必要なこと。
2. **実行する**: 最新リリースに添付された `install.ps1` をファイルとしてダウンロードしてから、`powershell -File` で実行する。2 つは**別々のコマンドとして**実行する（使うシェルに合わせて書き換えてよいが、この形は崩さない）。UAC の応答を待つ間ブロックするので、タイムアウトは長め（数分）にする。

   ```
   curl.exe -fsSL -o "%TEMP%\ecaps-install.ps1" https://github.com/nofukao/Ecaps/releases/latest/download/install.ps1
   powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\ecaps-install.ps1"
   ```

   - **ダウンロード URL を PowerShell のコマンドラインに直接書かない**（`powershell -c "... irm <URL> ..."` や `irm <URL> | iex` の形）。Microsoft Defender がマルウェア（Trojan:Win32/Commando）として遮断する。
   - オプションは、ユーザーが明示した場合だけ付ける。特に `-Force`（既存のキー割り当ての上書き）と `-PowerShellEmacs`（PowerShell プロファイルの変更）は、ユーザーの指示なしに付けない。
   - `install.ps1` が行わない変更（レジストリの手動編集、他のソフトの導入・削除など）は行わない（例外は手順 4 の RDP の設定だけ）。
3. **出力を確認する**: 各行の `[OK]` / `[CHANGED]` / `[TODO]` / `[ERROR]` と、最後の `Done.` または `Action needed:` を読む。
4. **完了条件**: `Installed version:` に版（例 `v1.0.0`）が表示され、`[ERROR]` が無いこと。`Action needed:` があれば、その内容（再起動が必要、既存のキー割り当てが標準と違う、UAC が拒否された、など）をユーザーにそのまま伝える。`[ERROR]` があれば、その行を示して対応をユーザーと相談する。
   - `Remote Desktop:` の `[TODO]` が出たら、表示された 2 行のコマンドと、その理由（再起動やサインアウトの後、RDP のセッションが英語配列で始まることがある。[RDP で接続すると英語配列になる](#rdp-で接続すると英語配列になる変換キーが効かない記号の位置が違う)）をユーザーに伝える。再起動が必要な場合は、再起動の前に行うよう伝える。
   - その 2 行は、ユーザーが実行を頼んだ場合に限り、エージェントが実行してよい。コマンドを一時 `.ps1` ファイルに書き、管理者として `powershell -NoProfile -ExecutionPolicy Bypass -File <そのファイル>` で実行する（UAC の確認が出る。コードをコマンドラインに直接書かない）。
5. **更新を頼まれた場合**も、同じ 2 つのコマンドを実行する（新しいリリースがある場合だけ入れ替わる）。

### (B) 自分で行う場合

1. PowerShell を開く（`Win + X` →「ターミナル」。管理者として開く必要はありません）。
2. 次の 2 行を貼り付けて実行する。1 行目で最新リリースの `install.ps1` を一時フォルダにダウンロードし、2 行目でそれを実行します。`install.ps1` は最新リリースを取得して、`Ecaps.ahk` や README などを設置先 `%LOCALAPPDATA%\Programs\Ecaps` に置きます（これらのファイルは手元に残ります）。

   ```powershell
   curl.exe -fsSL -o "$env:TEMP\ecaps-install.ps1" https://github.com/nofukao/Ecaps/releases/latest/download/install.ps1
   powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\ecaps-install.ps1"
   ```

3. UAC の確認が出たら「はい」を押す（AutoHotkey の導入や CapsLock の割り当てが必要な場合だけ出ます）。
4. 出力を確認する。各行は `[OK]`（済み）/ `[CHANGED]`（変更した）/ `[TODO]`（要対応）/ `[ERROR]`（失敗）で、最後に `Done.`（完了）または `Action needed:`（要対応の一覧）が表示されます。
5. 「Remote Desktop: …」と表示されたら、管理者として開いた PowerShell で、表示された 2 行を実行する（[RDP で接続すると英語配列になる](#rdp-で接続すると英語配列になる変換キーが効かない記号の位置が違う) と同じ設定。再起動の前に行う）。
6. 「Restart Windows …」と表示されたら Windows を再起動する。

**更新**するときも、同じ 2 行を実行します。何度実行しても同じ状態になり、新しいリリースがあるときだけ入れ替わります。

> `powershell -c "... irm <URL> ..."` のように、ダウンロードと実行を 1 行にまとめた形は使わないでください。Microsoft Defender がマルウェアの手口（Trojan:Win32/Commando）と判定して止めます。

オプションは 2 行目の末尾に付けます。例: `powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\ecaps-install.ps1" -PowerShellEmacs`

| オプション | 内容 |
|---|---|
| `-Version v1.2.0` | 最新ではなく、指定した版を入れる |
| `-NoUIA` | UIA 版ではなく、通常版の AutoHotkey で起動する |
| `-NoAdmin` | 管理者権限の操作をせず、必要なコマンドを表示するだけにする |
| `-Force` | 既に別の内容が入っている `Scancode Map` を、標準値で上書きする |
| `-PowerShellEmacs` | PowerShell の行編集を Emacs モードにする（[下記](#任意-powershell-を-emacs-編集モードにする)） |
| `-Source <フォルダ>` | リリースではなく、手元のフォルダから設置する（開発・テスト用） |

### install.ps1 が行うこと

| # | 内容 | 既に済んでいれば |
|---|---|---|
| 1 | リモートデスクトップで接続される PC なら、RDP のセッションを日本語配列で始めるための 2 つの設定（[RDP で接続すると英語配列になる](#rdp-で接続すると英語配列になる変換キーが効かない記号の位置が違う)）を確かめる。未設定なら、設定コマンドを `[TODO]` で示す（設定は変えない） | `[OK]` を表示する。リモートデスクトップを使わない PC では何も表示しない |
| 2 | AutoHotkey v2 が無ければ winget で導入する（管理者権限） | 何もしない |
| 3 | CapsLock の割り当て（[標準値](#標準の構成)）が未設定なら書き込む（管理者権限・要再起動） | 何もしない。別の値が入っていれば上書きせず報告する |
| 4 | GitHub の**最新リリース**を設置先 `%LOCALAPPDATA%\Programs\Ecaps` に置き、版を `VERSION.txt` に記録する | 同じ版なら何もしない |
| 5 | スタートアップに `Ecaps.lnk` を作る（UIA 版 AutoHotkey で起動）。Ecaps.ahk を指す古いショートカットは、二重起動の原因になるので削除する | 何もしない |
| 6 | 別の場所から起動中の Ecaps を終了し、設置先の Ecaps を起動する（更新時は再起動する） | 何もしない |

2 と 3 の管理者権限の操作は、必要なものだけを 1 つの昇格プロセスにまとめて行うので、UAC の確認は最大 1 回です。

### 標準の構成

| 項目 | 標準値 | 理由 |
|---|---|---|
| 設置先 | `%LOCALAPPDATA%\Programs\Ecaps` | Windows のユーザー単位アプリの慣例。管理者権限が不要で、OneDrive 同期の対象外（PC ごとに独立して更新される） |
| 配布 | [GitHub Releases](https://github.com/nofukao/Ecaps/releases) の zip（`install.ps1` もリリースに添付） | Git が不要。リリースした（テスト済みの）版だけが入る |
| AutoHotkey | v2（winget の `AutoHotkey.AutoHotkey`）、全ユーザー向けに Program Files へ | UIA 版の実行ファイルが作られる |
| 自動起動 | スタートアップの `Ecaps.lnk` → `AutoHotkey64_UIA.exe "…\Ecaps.ahk"` | UIA 版は、管理者権限のウィンドウ（管理者ターミナル、タスクマネージャー等）でも効く |
| キー割り当て | CapsLock → F13、ScrollLock → CapsLock | 下記 |

**キー割り当て（Scancode Map）**: レジストリ `HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layout` の値 `Scancode Map`（REG_BINARY）を次の値にします。CapsLock を F13（scancode `0x0064`）に、ScrollLock を CapsLock にします（CapsLock の機能は ScrollLock キーで使えます）。**ChangeKey などのキー割り当てツールで同じ設定をした場合も、この値になります。**

```
00 00 00 00  00 00 00 00  03 00 00 00  64 00 3A 00  3A 00 46 00  00 00 00 00
```

### 更新・移行・アンインストール

- **更新**: (A) または (B) と同じ手順です。新しいリリースがあるときだけ入れ替わり、Ecaps も再起動されます。
- **移行**: 以前の手順で別の場所（OneDrive など）に置いて自動起動していた PC も、(A) または (B) を行うだけで移行できます。古いスタートアップのショートカットは削除され、古い場所の Ecaps は終了して、標準の設置先の Ecaps に切り替わります。古い場所のファイルは削除しないので、不要なら手で消してください。
- **カスタマイズの注意**: 設置先の `Ecaps.ahk` を直接書き換えても、更新すると上書きされます。キーバインドを変えたい場合は、リポジトリを fork するなどして変更を管理してください。
- **アンインストール**:
  1. タスクトレイの Ecaps（H アイコン）を右クリック → Exit
  2. スタートアップの `Ecaps.lnk` を削除（`Win + R` → `shell:startup`）
  3. `%LOCALAPPDATA%\Programs\Ecaps` を削除
  4. CapsLock を元に戻す場合は、管理者権限の PowerShell で `Remove-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout' -Name 'Scancode Map'` を実行して再起動（他の割り当てがあれば、それも消えるので注意）
  5. AutoHotkey も不要なら、`winget uninstall --id AutoHotkey.AutoHotkey`

### 手動インストール

`install.ps1` を使わずに設置する場合の手順です（結果は同じ構成になります）。

1. **CapsLock を F13 に**: ChangeKey などで[標準のキー割り当て](#標準の構成)を設定し、再起動する。
2. **AutoHotkey v2**: [公式サイト](https://www.autohotkey.com/) からダウンロードし、全ユーザー向け（Program Files）にインストールする（UIA 版が作られる）。
3. **配置**: [Releases](https://github.com/nofukao/Ecaps/releases) の zip（Source code）を展開し、`Ecaps.ahk` などを `%LOCALAPPDATA%\Programs\Ecaps` に置く。
4. **自動起動**: `shell:startup` に、リンク先が `"C:\Program Files\AutoHotkey\v2\AutoHotkey64_UIA.exe" "%LOCALAPPDATA%\Programs\Ecaps\Ecaps.ahk"` のショートカットを作り、ダブルクリックして起動する。

### (任意) PowerShell を Emacs 編集モードにする

ローカル PowerShell を bash（SSH 先の readline）と同じ行編集にすると、`F13 + u`(行頭まで削除) / `F13 + k`(行末まで削除) などが PowerShell でも期待どおり動きます。`install.ps1` に `-PowerShellEmacs` を付けるか、PowerShell で以下を実行します（管理者権限は不要）。

```powershell
if (!(Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force }
Add-Content -Path $PROFILE -Value 'Set-PSReadLineOption -EditMode Emacs'
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force
```

新しい PowerShell タブを開くと反映されます。背景・補足（`RemoteSigned` の意味、PowerShell 7 の別プロファイル等）は [PowerShell を SSH 先と一致させる](#powershell-を-ssh-先と一致させるpsreadline-の-emacs-モード) を参照してください。

---

## 基本概念

### 修飾キーとしての F13 (= 物理 CapsLock)

本ドキュメントで `F13` と表記しているキーは、すべて **物理的な CapsLock キー** を指します。インストール時に CapsLock を F13 に割り当てるので、CapsLock を押しながら他のキーを押すことで、以下のキーバインドが発動します。

`@` `[` `-` などの記号は、**日本語 109 キーボードの刻印どおりのキー**を指します。Windows の配列が一時的に英語になっていても、同じ物理キーで動作します（v1.0.2 以降）。

### Set Mark（選択モード）

`F13 + Space` で選択モードのトグルが切り替わります。アクティブな間はカーソル移動キーが `Shift + 矢印` として送出され、範囲選択を伸ばせます。コピー・カット・編集系のコマンドを実行すると自動的にリセットされます。

ターミナル/コンソール（VSCode 内蔵ターミナルを含む）では仕組みが異なり、`F13 + Space` は readline の set-mark を送り、移動キーは `Shift` を付けずにそのまま送出します（端末は mark〜カーソル間を region として扱うため）。詳細は [ターミナル/コンソールでの挙動](#ターミナルコンソールでの挙動) を参照。

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
| `Alt + n` | `Ctrl+PgDn` を送る（アプリにより次のページ / 次のタブ） | scroll-up |
| `Alt + p` | `Ctrl+PgUp` を送る（アプリにより前のページ / 前のタブ） | scroll-down |
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
| `F13 + t` | タブ (Tab)。`Shift` を押しながらだと `Shift+Tab` | — |
| `F13 + /` | 元に戻す (Ctrl+Z) | undo |

### 選択・コピー・カット・ペースト

| キー操作 | 動作 | 備考 |
|---|---|---|
| `F13 + Space` | **選択モード開始 / 終了** | 押下後、移動キーで範囲選択（端末: set-mark） |
| `F13 + w` | カット (Ctrl+X) | Emacs `C-w`（端末: `Ctrl+W`） |
| `F13 + x` | カット (Ctrl+X) | Windows 互換 |
| `Alt + w` | コピー (Ctrl+C) | Emacs `M-w`（端末: `Alt+w` = kill-ring-save。emacs 等で有効） |
| `F13 + c` | コピー (Ctrl+C) | Windows 互換（端末では `Ctrl+C` = 中断/SIGINT） |
| `F13 + y` | ペースト (Ctrl+V) | Emacs `C-y` (Yank)（端末: `Ctrl+Y` = yank） |
| `F13 + v` | ペースト (Ctrl+V) | Windows 互換 |
| `F13 + g` | キャンセル (Esc) | Emacs `C-g` |
| `F13 + [` | エスケープ (Esc) | — |

`Enter` キーを押したときも選択モードは解除されます（`Enter` 自体はそのまま入力されます）。

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

---

## 技術的補足

### Ctrl + キー として動くキー

次の `F13 + キー` は、そのまま `Ctrl + キー` として送られます。CapsLock を Ctrl 代わりに使って、Windows のショートカットを実行できます。

| キー操作 | 送られるキー | 例 |
|---|---|---|
| `F13 + z` | `Ctrl + Z` | 元に戻す |
| `F13 + o` | `Ctrl + O` | 開く |
| `F13 + q` | `Ctrl + Q` | 終了（アプリによる） |
| `F13 + l` | `Ctrl + L` | アドレスバー / 画面クリア |
| `F13 + r` | `Ctrl + R` | [上記](#履歴検索再読込置換) |
| `F13 + -` | `Ctrl + -`（`Shift` も押すと `Ctrl + =`） | 縮小 / 拡大 |
| `F13 + ]` / `F13 + \` / `F13 + ;` | `Ctrl + ]` / `Ctrl + \` / `Ctrl + ;` | エディタ等のショートカット |
| `F13 + ,` / `F13 + .` | `Ctrl + ,` / `Ctrl + .` | 設定 / クイックフィックス（VSCode 等） |

上の表にも[キーバインド一覧](#キーバインド一覧)にも無いキーは、F13 を押していても通常どおり入力されます。

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

| 判定対象 | 判定方法 |
|---|---|
| Windows Terminal | `WindowsTerminal.exe` / `OpenConsole.exe` |
| PuTTY | ウィンドウクラス `PuTTY` |
| 旧コンソール | `cmd` / `PowerShell`（`ConsoleWindowClass`） |
| Git Bash / Cygwin / WSL | `mintty.exe` |
| Tera Term | `ttermpro.exe` |
| **VSCode 内蔵ターミナル** | `Code.exe` が前面のとき、UI Automation でフォーカス先がターミナル（`xterm-helper-textarea`）かを判定 |

#### VSCode 内蔵ターミナル

VSCode はエディタもターミナルも同じウィンドウなので、ウィンドウ単位では区別できません。そこで、VSCode が前面のときだけ UI Automation でフォーカス先を問い合わせ、ターミナルなら端末として扱います（VSCode の設定変更は不要です）。エディタや Claude Code の入力欄などは、これまでどおり GUI として扱います。

また VSCode は、既定の状態では一部のキーをターミナルに渡さず自分で使います（例: `Ctrl+K` はショートカットの 1 打目として横取りされる）。そのため VSCode 内蔵ターミナルでは、送るキーを次のように置き換えています。いずれも VSCode の設定を変えずに、bash に同じ制御文字が届きます。

| 操作 | 端末ウィンドウ | VSCode 内蔵ターミナル |
|---|---|---|
| 行末まで削除 (`F13 + k`) | `Ctrl+K` | 制御文字 `^K` を直接送る |
| 単語末まで削除 (`Alt + d`) | `Alt+d` | `Ctrl+Del`（VSCode が `ESC d` に変換） |
| set-mark (`F13 + Space`) | `Ctrl+Space` | `Ctrl+Shift+2`（VSCode が NUL に変換） |
| その他（`Ctrl+U` / `Ctrl+W` / `Ctrl+Y` / `Alt+w`） | 同じ | 同じ |

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

ローカル PowerShell を SSH 先（readline）と同じ挙動にするには、PSReadLine を **Emacs 編集モード**にします。これで `Ctrl+U`(行頭まで) / `Ctrl+K`(行末まで) / `Ctrl+W` / `Ctrl+Y` / `Ctrl+Space` が bash と同じ意味になります。`install.ps1` に `-PowerShellEmacs` を付けると、以下の手順をまとめて行います。

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

### ローカル PC と RDP 先の両方で使う場合

手元の PC と、リモートデスクトップ (RDP) で接続する先の PC の両方に Ecaps を入れて使えます。手元の Ecaps は、**RDP のウィンドウ (`mstsc.exe`) が前面の間は自動で止まり**、キーをそのまま RDP 先へ送ります。RDP 先では、RDP 先の Ecaps がキーを処理します。これにより、キーが二重に変換されることはありません（RDP 先の Ecaps は常に有効です）。

日本語入力の ON / OFF（`F13 + j` / `F13 + i`）も、RDP 先の Ecaps が RDP 先の IME を直接制御するので、そのまま動きます。

> RDP 先からさらに別の PC へ RDP する場合など、RDP クライアントが前面のまま Ecaps がキーを処理するときは、Windows のメッセージが接続先へ届かないため、IME 制御をキー入力（`VK_IME_OFF` → `半角/全角` → `Shift+無変換` ×2）で再現します。MS-IME の「前回モードを記憶」が ON だと崩れる可能性があるため、OFF を推奨します。

### サスペンド時のトレイアイコン

AutoHotkey v2 のデフォルトではサスペンド時のトレイアイコンの差異が小さく状態が判別しづらいため、本スクリプトでは `TraySetIcon` で明示的に切り替えています。AutoHotkey 実行ファイル本体に埋め込まれているアイコン（index 1: 既定 / index 2: サスペンド）を利用するため、追加ファイルなしで動作します。

---

## 困ったときは

### RDP で接続すると英語配列になる（変換キーが効かない、記号の位置が違う）

リモートデスクトップ (RDP) で接続した先の PC で、ログオン直後のキーボードが英語配列になることがあります。Windows の既知の現象で、Ecaps とは関係ありません。キーボード配列は RDP の**ログオン時**に決まるので、再起動後など、新しくログオンしたときに起きます。

主な原因は次の 2 つです。

1. 接続元の PC が「日本語キーボード・サブタイプ 0」と申告し、接続先が英語配列（`kbd101.dll`）を割り当てる。
2. 接続先が接続元のキーボード配列を取り込み、「日本語・英語キーボード」の入力方式が既定になる。

**直し方**（**接続される側の PC** で、管理者として開いた PowerShell で実行し、サインアウトして入り直す）:

```powershell
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\KeyboardType Mapping\JPN' -Name '00000000' -Value 'kbd106.dll'
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout' -Name 'IgnoreRemoteKeyboardLayout' -PropertyType DWord -Value 1 -Force
```

- 1 行目: 日本語キーボードのサブタイプ 0 を、日本語 106/109 配列（`kbd106.dll`）に割り当てる（元の値は `kbd101.dll`）。
- 2 行目: 接続元のキーボード配列を取り込まない。
- サインアウトするまでの間は、タスクバーの入力方式を日本語 IME に切り替えれば日本語配列になります。

**前もって防ぐ**: Ecaps のインストールに伴う再起動だけでなく、Windows Update の再起動やサインアウトの後にも起きます。RDP で入って使う PC には、再起動の前に上の 2 行を設定しておくことを勧めます。どちらの設定も、日本語 106/109 キーボードで使う限り害はありません。`install.ps1` は、リモートデスクトップで接続される PC でこの設定が無いと、`[TODO]`（`Remote Desktop: …`）で知らせます。

### `F13 + @`（サスペンド）など記号のキーが効かない

v1.0.1 以前の Ecaps は、記号のキーを「Ecaps が起動した時点の配列」で覚えていました。上の英語配列の状態で起動すると、`F13 + @` などが効かなくなります。v1.0.2 以降に更新してください（[インストール](#インストール) と同じ手順）。すぐに直したい場合は、日本語 IME に切り替えてから Ecaps を起動し直します（タスクトレイの H アイコンを右クリック → Reload Script）。

### Ecaps が効かない・止まっているか分からない

- タスクトレイの H アイコンが「透明な H」なら、サスペンド中です。`Pause` キー（または `F13 + @` / `Ctrl + @`）で再開します。
- H アイコンが無ければ、Ecaps が動いていません。[インストール](#インストール) の手順をもう一度実行すると、設置の確認と起動まで行います。

---

## 特定アプリでの無効化

PuTTY、Vim、GVim、Emacs 本体など **本キーバインドを適用したくないアプリ** がある場合は、`Ecaps.ahk` の `#HotIf !ShouldYieldToRDP()` の行に条件を足します（RDP については自動で処理されるので指定は不要です）。

```ahk
#HotIf !ShouldYieldToRDP()
      && !WinActive("ahk_class PuTTY")
      && !WinActive("ahk_class Vim")
```

> 設置先（`%LOCALAPPDATA%\Programs\Ecaps`）の `Ecaps.ahk` を書き換えても、`install.ps1` で更新すると上書きされます。変更を残したい場合は、リポジトリを fork するなどして管理してください。

---

## テスト

`Ecaps.ahk` を変更したら、ゴールデンテストで送出キー列に意図しない変化がないことを確認します（Python 3 が必要。依存ライブラリなし）。

```
python tests/golden_test.py            # golden (tests/golden/*.txt) と比較
python tests/golden_test.py --update   # 意図した変化なら golden を更新
```

端末向けの挙動を変えた場合は、VSCode 内蔵ターミナル (Git Bash) で bash が実際にどう編集したかを確かめる e2e テストも実行します。テスト用の VSCode を別インスタンスで起動するので、普段の VSCode の設定には影響しません。

```
python tests/vscode_terminal_test.py
```

テストに使う AutoHotkey は、環境変数 `ECAPS_AHK_EXE` に実行ファイルのパスを入れると切り替えられます（新しい版への適合確認に使います）。どちらのテストも実行中の約 1 分間は、キーボードとマウスに触れないでください。仕組みと制約は [設計ノート 7 章](docs/design-notes.md) を参照してください。
