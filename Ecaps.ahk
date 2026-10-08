;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Ecaps.ahk  ―  Emacs風キーバインド on Windows  (AutoHotkey v2)
;                                   2022/09 - / nofukao
;   日本語109キーボードを前提に、CapsLock を物理的に F13 (scancode 0x0064)
;   に割り当てた上で、F13 + key の組合せで Unix シェル / Emacs 風の
;   キーバインドを提供する。
;
;   本物の Ctrl は極力使わないので、Windows 既定のショートカット
;   (Ctrl+S 等) は従来通り動作する。
;
;   設定方法:
;     1. ChangeKey 等で物理 CapsLock キーに F13 (scancode 0x0064) を割当て
;     2. 本スクリプトを適当なフォルダに配置 (例: OneDrive\bin\AutoHotkey)
;     3. Win+R → shell:startup でスタートアップに登録
;
;   設定方法2 (任意):
;     PowerShell(PS)をEmacs編集モードにし、bashと同じ挙動にする。
;     1. PSターミナルを開く。(管理者権限は不要)
;     2. PSプロンプトで以下の3行について、行頭"> "の次からを切り取って、順に貼り付けて実行する。
;        > if (!(Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force }
;        > Add-Content -Path $PROFILE -Value 'Set-PSReadLineOption -EditMode Emacs'
;        > Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force
;       (最初の2行はプロファイルの追記。最後の1行はスクリプトの実行を許可。)
;     3. PSターミナルを再起動する。
;        これで、Ctrl+U(行頭まで削除)、Ctrl+K(行末まで削除)等が動作するようになる。
;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook

InstallKeybdHook()

; 送出は SendEvent で行う (v2 既定の SendInput を使わない)。
;   SendInput は送出の間だけ自スクリプトのキーボードフックを外して付け直す。
;   F13+p 等を押し続けるとオートリピートのたびにこれが起き、フックが外れて
;   いる隙に届いたリピートが素の "p" として漏れる。SendEvent はフックを外さない。
;   (詳細は docs/design-notes.md 1.5)
SendMode("Event")
SetKeyDelay(0)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; 状態管理 — Set Mark (選択モード)
;
;   F13+Space で切り替わるトグル。アクティブな間、移動キーは Shift 修飾
;   付きで送出され、選択範囲を伸ばせる。編集系コマンド実行時に自動でOFF。
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

class Mark {
    static Active := false
    static Toggle() => Mark.Active := !Mark.Active
    static Reset()  => Mark.Active := false
}


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; IME 制御
;
;   アクティブウィンドウの IME ウィンドウに WM_IME_CONTROL を送出して
;   ON/OFF や入力モードを直接切り替える。
;   参考: https://namayakegadget.com/765/
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; 低レベル: IMEウィンドウに WM_IME_CONTROL メッセージを送る
;   wParam : 0x0006=IMC_SETOPENSTATUS, 0x0002=IMC_SETCONVERSIONMODE
SendIMEControl(wParam, lParam, winTitle := "A") {
    hwnd := WinExist(winTitle)
    if WinActive(winTitle) {
        ; GUITHREADINFO : cbSize(4) + flags(4) + HWND×6 + RECT(16)
        gti := Buffer(4 + 4 + A_PtrSize * 6 + 16, 0)
        NumPut("UInt", gti.Size, gti, 0)            ; cbSize
        if DllCall("GetGUIThreadInfo", "UInt", 0, "Ptr", gti)
            hwnd := NumGet(gti, 8 + A_PtrSize, "UPtr")  ; hwndFocus
    }
    return DllCall("SendMessage"
        , "Ptr",  DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", hwnd, "Ptr")
        , "UInt", 0x0283       ; WM_IME_CONTROL
        , "Int",  wParam
        , "Int",  lParam)
}

; IME ON / OFF
SetIME(open)         => SendIMEControl(0x6, open ? 1 : 0)

; 入力モード設定
;   0:半角英数, 3:全角英数, 9:全角ひらがな, 11:全角カタカナ, 27:半角カタカナ
SetIMEConvMode(mode) => SendIMEControl(0x2, mode)

; 日本語入力 ON (ただし入力モードは半角英数で待機)
;   ローカル : WM_IME_CONTROL でモードまで含めて一発設定
;   RDP 経由 : Windows メッセージは遠隔 PC へ転送されないので、キー入力で
;              4 ステップの決定論的シーケンスを送る:
;                ① VK_IME_OFF  (vk1A)  — IME を強制 OFF (既知状態に揃える)
;                ② 半角/全角   (vk19)  — IME を ON、MS-IME 既定で ひらがな
;                ③ Shift+無変換 (vk1D) — ひらがな → 全角英数
;                ④ Shift+無変換 (vk1D) — 全角英数 → 半角英数
;              ※「半角/全角 で IME が ひらがな で立ち上がる」前提が必要。
;                MS-IME 設定で「前回モードを記憶」が ON だと崩れる可能性あり。
IMEOn() {
    if IsRDPActive() {
        Send "{vk1A}"          ; ① OFF 強制
        Sleep(50)
        Send "{vk19}"          ; ② 半角/全角 で IME ON (→ ひらがな)
        Sleep(50)
        Send "+{vk1D}"         ; ③ Shift+無変換  ひらがな → 全角英数
        Sleep(30)
        Send "+{vk1D}"         ; ④ Shift+無変換  全角英数 → 半角英数
    } else {
        SetIME(true)
        Sleep(50)
        SetIMEConvMode(0)
    }
}

; 日本語入力 OFF
;   RDP 経由は VK_IME_OFF (0x1A) を Send。明示 OFF (非トグル)。
IMEOff() {
    if IsRDPActive() {
        Send "{vk1A}"
    } else {
        SetIME(false)
    }
}

; アクティブウィンドウが RDP クライアント (mstsc.exe) かどうか
IsRDPActive() => WinActive("ahk_exe mstsc.exe")


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; ターミナル / コンソール判定
;
;   GUI アプリの行編集は「選択してから削除」「クリップボード」で行うが、
;   ターミナルの行編集器 (Linux の readline/bash, PuTTY 等) には選択範囲も
;   クリップボードも存在しない。これらは Emacs 由来の制御文字
;   (Ctrl+U/K/W/Y/Space …) で編集する。よって端末が前面のときは、編集系
;   コマンドを GUI 流ではなく readline 流の制御キーで送り分ける。
;
;   注意: Windows Terminal は「ローカル PowerShell」と「SSH 先 bash」を同一
;   ウィンドウで扱うため、ウィンドウ属性からは両者を区別できない。端末用キーは
;   どちらにも送られる (詳細は docs/design-notes.md)。
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
IsConsole() =>
       WinActive("ahk_exe WindowsTerminal.exe")    ; Windows Terminal
    || WinActive("ahk_exe OpenConsole.exe")        ; Windows Terminal (旧/別ホスト)
    || WinActive("ahk_class PuTTY")                ; PuTTY
    || WinActive("ahk_class ConsoleWindowClass")   ; 旧 conhost (cmd / PowerShell)
    || WinActive("ahk_exe mintty.exe")             ; Git Bash / Cygwin / WSL
    || WinActive("ahk_exe ttermpro.exe")           ; Tera Term

; VSCode の内蔵ターミナルにフォーカスがあるか
;   VSCode はエディタもターミナルも同じ Code.exe のウィンドウなので、ウィンドウ
;   属性では区別できない。UI Automation でフォーカス中の要素を問い合わせ、
;   ターミナル (xterm.js) の入力欄 "xterm-helper-textarea" かどうかで判定する。
;   VSCode の設定は変えずに済む (複数 PC で既定設定のまま使うため)。
;   - 問い合わせは Code.exe が前面のときだけ。1 回 0〜16ms 程度。
;   - Chromium は最初の問い合わせでアクセシビリティを有効化し、その回だけ
;     ルート ("View") を返すので、少し待って取り直す。
;   - VSCode が応答しないときに Ecaps が固まらないよう、UIA のタイムアウトを短くする。
IsVSCodeTerminal() {
    static uia := 0
    if !WinActive("ahk_exe Code.exe")
        return false
    try {
        if !uia {
            ; CUIAutomation8 / IUIAutomation2 (タイムアウトを設定できる版)
            uia := ComObject("{e22ad333-b25f-460c-83d0-0581107395c9}", "{34723aff-0c9d-49d0-9896-7ab52df8cd8a}")
            ComCall(61, uia, "UInt", 200)    ; put_ConnectionTimeout (ms)
            ComCall(63, uia, "UInt", 200)    ; put_TransactionTimeout (ms)
        }
        Loop 3 {
            ComCall(8, uia, "Ptr*", &el := 0)            ; GetFocusedElement
            ComCall(30, el, "Ptr*", &bstr := 0)          ; get_CurrentClassName
            ObjRelease(el)
            cls := bstr ? StrGet(bstr, "UTF-16") : ""
            DllCall("OleAut32\SysFreeString", "Ptr", bstr)
            if cls != "View"
                return cls = "xterm-helper-textarea"
            Sleep(30)
        }
    }
    return false
}

; 端末の種類:  "" = GUI / "console" = 端末ウィンドウ / "vscode" = VSCode 内蔵ターミナル
TermKind() => IsConsole() ? "console" : IsVSCodeTerminal() ? "vscode" : ""

; readline 流の制御キー (consoleKey) を、端末の種類に応じた実際の送出キーへ変換する。
;   VSCode は一部のキーをターミナルに渡さず自分のショートカットとして使う
;   (例: Ctrl+K は chord の 1 打目)。そのため VSCode では、既定設定のまま
;   シェルに同じ制御文字が届くキーへ置き換える。
TermKey(kind, consoleKey) {
    static vscode := Map(
        "^k",       "{U+000B}",     ; kill-line: Ctrl+K は横取りされるので文字 ^K を直接送る
        "!d",       "^{Del}",       ; kill-word: VSCode 既定で Ctrl+Del → ESC d
        "^{Space}", "^+2",          ; set-mark: VSCode 既定で Ctrl+Shift+2 → NUL
    )
    return (kind = "vscode" && vscode.Has(consoleKey)) ? vscode[consoleKey] : consoleKey
}

; 端末なら consoleKey (を端末に合わせて変換したもの)、GUI なら guiKey
TermOr(consoleKey, guiKey) => (kind := TermKind()) ? TermKey(kind, consoleKey) : guiKey


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; 実行セッション判定
;
;   このスクリプトはローカル PC とリモート PC の両方で同時に動作することが
;   ある (例: ローカルに AHK をインストール済み、かつ RDP 接続先のリモート
;   PC でも同じスクリプトが起動している)。
;   その場合、ローカル AHK のキーボードフックが F13 系ホットキーを横取り
;   してしまい、キーストロークが RDP 経由でリモートに届かなくなる。
;
;   そこで「自分自身がローカル(コンソール)で動いている」かつ「アクティブ
;   ウィンドウが RDP クライアント」のときは、ローカル側のホットキーを
;   無効化してキーをリモートに素通しさせる。
;   これにより:
;     - リモート PC で動く AHK (RDP セッション内) → 常時有効
;     - ローカル PC、RDP ウィンドウ前面               → 無効 (リモートに譲る)
;     - ローカル PC、それ以外                         → 有効 (普段使い)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; この AHK プロセスがローカル PC (コンソール) で動いているか
;   SM_REMOTESESSION (0x1000) = RDP セッション内なら 0 以外
;   起動時に一度だけ判定し static でキャッシュ
IsLocalConsole() {
    static cached := !DllCall("GetSystemMetrics", "Int", 0x1000)
    return cached
}

; ローカル PC で動作中、かつ RDP クライアントが前面のとき真
;   このとき、ローカル AHK は F13 系ホットキーをリモートに譲る
ShouldYieldToRDP() => IsLocalConsole() && IsRDPActive()


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Emacs風コマンドのコアヘルパ
;
;   SendMove             : 移動キーをマーク状態に応じて Shift 修飾付き/無しで送る
;   SendAndUnmark        : 任意のキー列を送出した後にマーク状態を解除
;   SendAndUnmarkShifted : Shift 押下時のみ別キー列を送る (Tab / Shift+Tab 等)
;   DeleteRange          : (Shift+移動) → Del で範囲削除 (kill-line / kill-word 等)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; 端末では Shift+移動 は選択にならない (readline は mark で region を持つ) ので
; Mark 中でも Shift を付けず、素の移動キーを送る。
SendMove(key) => Send(((Mark.Active && !TermKind()) ? "+" : "") . key)

SendAndUnmark(keys) {
    Send(keys)
    Mark.Reset()
}

; AHK のカスタムコンボ (F13 & X) にはモディファイア前置記号 (+ ! ^ #) を
; 付けられない。Shift で分岐したい場合はハンドラ内で物理キー状態を見る
; 必要があるため、その定型をここに括り出す。
SendAndUnmarkShifted(plain, shifted) =>
    GetKeyState("Shift", "P") ? SendAndUnmark(shifted) : SendAndUnmark(plain)

; Alt 系ホットキーで、Alt を離したときにメニュー (Win11 メモ帳のアクセスキー
; 表示等) が出ないよう、Alt が押されていれば無割当キー vkE8 を挟む。
; Alt 系ホットキーの「前後」で呼ぶ (例: !f::MaskAlt(), SendMove(...), MaskAlt())。
;   前: Send は送出の最初に Alt を離す。その時点までに Alt 以外のキーが 1 つも
;       無いと「Alt 単独の押下」と見なされる。AHK は Ctrl↓ を先に送るが、WinUI は
;       修飾キーを「他のキー」と数えないので、Ctrl では抑止できない。
;   後: Send は送出後に Alt を押し直す (物理的に押されたままなので)。この Alt を
;       そのまま離したときに備える。
;   いずれも Win11 メモ帳にキー列を再現して確認済み (docs/design-notes.md 1.5)。
MaskAlt() {
    if GetKeyState("Alt")
        Send("{Blind}{vkE8}")
}

DeleteRange(rangeKey) {
    Send("+" . rangeKey)
    Sleep(50)             ; この値は環境依存
    Send("{Del}")
    Mark.Reset()
}

; 範囲削除 (kill-line / kill-word 等) を端末/GUI で送り分ける:
;   端末 → readline の制御キーを送る (例 行末まで=Ctrl+K。VSCode は TermKey で変換)
;   GUI  → 従来どおり (Shift+移動)→Del の選択削除
KillToEdge(consoleKey, guiRangeKey) =>
    (kind := TermKind()) ? SendAndUnmark(TermKey(kind, consoleKey)) : DeleteRange(guiRangeKey)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; ※ 特定アプリ (PuTTY, Vim, GVIM, Emacs 等) でこの Emacs キーバインドを
;    無効にしたい場合は、下の #HotIf に条件を追加してください。例:
;
;      #HotIf !ShouldYieldToRDP()
;            && !WinActive("ahk_class PuTTY")
;            && !WinActive("ahk_class Vim")
;
;    なお RDP については ShouldYieldToRDP() が自動で処理するので
;    個別指定は不要です。
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


; ===== ここから先のホットキーは、ローカル PC で RDP ウィンドウが前面のとき
;       無効化される。リモート PC で動作中の AHK は常に有効。 =====
#HotIf !ShouldYieldToRDP()


;==================== AutoHotkey 制御 ====================
; サスペンド (トグル) : F13+@, Pause, Ctrl+@
;
; v2 では「ホットキー本体が Suspend のみ」でも自動除外されないため、
; #SuspendExempt で明示的にサスペンド対象から外す必要がある。
; これを忘れるとサスペンド ON 後に解除用ホットキーまで停止してしまう。
;
; v2 既定のサスペンド時トレイアイコンは v1 の "S" 文字と異なり
; 「透明な H」に変わるだけで状態が判別しづらいので、ToggleSuspend() で
; 明示的に切替える。AutoHotkey 実行ファイル (A_AhkPath) に埋め込まれている
; アイコンを利用するので、複数 PC への配布も追加ファイル無しで完結する。
;   index 1 : 既定の H アイコン
;   index 2 : サスペンド時アイコン (透明な H ―― 一番見分けが付きやすい)
#SuspendExempt
F13 & @::ToggleSuspend()
Pause::ToggleSuspend()
^@::ToggleSuspend()
#SuspendExempt False

ToggleSuspend() {
    Suspend(-1)
    if A_IsSuspended
        TraySetIcon(A_AhkPath, 2, true)   ; サスペンドアイコン (Freeze=true で固定)
    else
        TraySetIcon(A_AhkPath, 1, true)   ; 既定アイコン
}


;==================== カーソル移動 ====================
; F13 + fbnp / ae : 一文字・行頭行末
F13 & f::SendMove("{Right}")
F13 & b::SendMove("{Left}")
F13 & n::SendMove("{Down}")
F13 & p::SendMove("{Up}")
F13 & a::SendMove("{Home}")
F13 & e::SendMove("{End}")

; Alt + fbnp / <> : 単語単位・半画面・文書先頭末尾
!f::MaskAlt(), SendMove("^{Right}"), MaskAlt()
!b::MaskAlt(), SendMove("^{Left}"), MaskAlt()
!n::MaskAlt(), SendMove("^{PgDn}"), MaskAlt()
!p::MaskAlt(), SendMove("^{PgUp}"), MaskAlt()
!<::MaskAlt(), SendMove("^{Home}"), MaskAlt()
!>::MaskAlt(), SendMove("^{End}"), MaskAlt()


;==================== Set Mark (選択モード) ====================
; 端末では readline の set-mark (Ctrl+Space) を送る。GUI では自前の選択トグル。
F13 & Space::(kind := TermKind()) ? Send(TermKey(kind, "^{Space}")) : Mark.Toggle()


;==================== 削除 ====================
F13 & d::SendAndUnmark("{Del}")     ; 右一文字
F13 & h::SendAndUnmark("{BS}")      ; 左一文字
F13 & k::KillToEdge("^k", "{End}")      ; 行末まで (kill-line)  端末:Ctrl+K
F13 & u::KillToEdge("^u", "{Home}")     ; 行頭まで              端末:Ctrl+U
!d::MaskAlt(), KillToEdge("!d", "^{Right}"), MaskAlt()    ; 単語末まで (kill-word) 端末:Alt+d
!h::MaskAlt(), KillToEdge("^w", "^{Left}"), MaskAlt()     ; 単語頭まで (backward-kill-word) 端末:Ctrl+W


;==================== 改行・タブ・エスケープ ====================
~Enter::Mark.Reset()                          ; Enterは素通しで Mark のみ解除
F13 & m::SendAndUnmark("{Enter}")             ; Ctrl+m 風 改行
F13 & t::SendAndUnmarkShifted("{Tab}", "+{Tab}")    ; Shift 押下時は Shift+Tab (逆方向タブ)
F13 & [::SendAndUnmark("{Esc}")
F13 & g::SendAndUnmark("{Esc}")               ; Emacs C-g (キャンセル)


;==================== カット・コピー・ペースト ====================
F13 & x::SendAndUnmark("^x")        ; カット
F13 & w::SendAndUnmark(TermOr("^w", "^x"))   ; カット / 端末:kill-region (Ctrl+W)
F13 & c::SendAndUnmark("^c")        ; コピー (端末では Ctrl+C=SIGINT で正しい)
!w::MaskAlt(), SendAndUnmark(TermOr("!w", "^c")), MaskAlt()   ; コピー (Emacs M-w) / 端末:Alt+w=kill-ring-save
F13 & v::SendAndUnmark("^v")        ; ペースト
F13 & y::SendAndUnmark(TermOr("^y", "^v"))   ; ペースト / 端末:yank (Ctrl+Y)


;==================== ファンクションキー (F13 + 数字) ====================
F13 & 1::Send("{F1}")
F13 & 2::Send("{F2}")
F13 & 3::Send("{F3}")
F13 & 4::Send("{F4}")
F13 & 5::Send("{F5}")
F13 & 6::Send("{F6}")
F13 & 7::Send("{F7}")
F13 & 8::Send("{F8}")
F13 & 9::Send("{F9}")
F13 & 0::Send("{F10}")


;==================== IME ON/OFF ====================
F13 & j::IMEOn()      ; 日本語入力 ON (半角英数モードで待機)
^!j::IMEOn()
F13 & i::IMEOff()     ; 日本語入力 OFF
^!i::IMEOff()


;==================== 上書き保存・Undo ====================
F13 & s::Send("{Blind}^s")          ; 上書き保存 (Save)
F13 & /::Send("{Blind}^z")          ; Undo


;==================== その他 — Ctrl+キー としてフォールバック ====================
; 上で定義していない F13+キー は、通常の Ctrl+キー として動作させる。
; これにより、CapsLock を Ctrl 代わりに使った汎用ショートカットも有効。
F13 & -::Send("{Blind}^-")
F13 & =::Send("{Blind}^=")
F13 & q::Send("{Blind}^q")
F13 & o::Send("{Blind}^o")
F13 & r::Send("{Blind}^r")          ; Ctrl+R: 履歴逆検索 / 再読込 / 置換 (Emacs C-r 風)
F13 & }::Send("{Blind}^{]}")
F13 & \::Send("{Blind}^{\}")
F13 & l::Send("{Blind}^l")
F13 & sc027::Send("{Blind}^{sc027}")
F13 & z::Send("{Blind}^z")
F13 & ,::Send("{Blind}^,")
F13 & .::Send("{Blind}^.")

; マウス: F13 + マウス操作 → Ctrl + マウス操作 (拡大縮小等に有用)
F13 & LButton::Send("{Blind}^{LButton}")
F13 & RButton::Send("{Blind}^{RButton}")
F13 & MButton::Send("{Blind}^{MButton}")
F13 & WheelUp::Send("{Blind}^{WheelUp}")
F13 & WheelDown::Send("{Blind}^{WheelDown}")
F13 & WheelLeft::Send("{Blind}^{WheelLeft}")
F13 & WheelRight::Send("{Blind}^{WheelRight}")


; ===== ホットキー定義領域おわり =====
#HotIf
