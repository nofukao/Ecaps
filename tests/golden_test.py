"""Ecaps.ahk のゴールデンテスト (Windows 専用, 依存ライブラリ無し)

仕組み:
  1. 本プロセスで低レベルキーボードフック (レコーダ) を先に登録する。
  2. テスト対象の Ecaps.ahk を起動する。後から登録された AHK のフックが
     先に呼ばれるので、レコーダには「Ecaps を通過したキーイベント」だけが届く
     (Ecaps が握り潰したキーは届かない)。
  3. 自前のテスト用ウィンドウを前面にし、SendInput で物理キー相当の入力
     (dwExtraInfo に DRIVER_TAG を付ける) を送る。
  4. 記録したイベント列を tests/golden/<ケース名>.txt と比較する。

  記録の各行は "<送信元> <down|up> <キー名>"。送信元 drv = 本テストが送った
  キーが Ecaps を素通りしたもの、ahk = Ecaps (AHK) が生成したもの。

使い方:
  python tests/golden_test.py            # 全ケースを実行して比較
  python tests/golden_test.py --update   # 現在の結果で golden を作り直す
  python tests/golden_test.py -k alt     # 名前に "alt" を含むケースだけ

注意:
  - 実行中 (1 分弱) はキーボード・マウスに触れないこと。RDP 越しに実行する場合は
    RDP ウィンドウを最小化しないこと (SendInput が失敗する)。
  - 入力は SendInput による注入なので、AHK からは「物理的に押されていない」キーに
    見える。修飾キー (Alt 等) を押したまま連打する挙動は実機と異なり得るので、
    それは手で確認すること。
  - 他の AutoHotkey スクリプトが動いていると、AHK の SendInput が SendEvent に
    自動で切り替わり結果が変わるので、既定では中止する。--stop-others を付けると
    それらを終了させ、テスト後にスタートアップフォルダの .ahk を起動し直す。
    ただし UIA 版 (AutoHotkey64_UIA.exe) で常駐している場合は権限上終了できない
    ので、トレイアイコンから手動で Exit しておくこと。
"""

import argparse
import ctypes
import ctypes.wintypes as wt
import difflib
import os
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "Ecaps.ahk"
GOLDEN_DIR = Path(__file__).resolve().parent / "golden"
AHK_EXE = Path(os.environ.get("ECAPS_AHK_EXE", r"C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"))

DRIVER_TAG = 0x0EC0E5  # テストが送ったイベントの目印 (dwExtraInfo)
KEY_DELAY = 0.03       # 送信キー間の待ち (秒)
SETTLE = 0.3           # ケース終了後、AHK の送出が落ち着くまでの待ち (秒)

user32 = ctypes.WinDLL("user32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

ULONG_PTR = ctypes.c_size_t
LRESULT = ctypes.c_ssize_t
WH_KEYBOARD_LL = 13
WM_KEYDOWN, WM_KEYUP, WM_SYSKEYDOWN, WM_SYSKEYUP = 0x100, 0x101, 0x104, 0x105
WM_CLOSE, WM_COMMAND, WM_USER = 0x10, 0x111, 0x400
WM_APP_FOCUS = WM_USER + 1
INPUT_KEYBOARD = 1
KEYEVENTF_EXTENDEDKEY, KEYEVENTF_KEYUP = 0x1, 0x2
AHK_ID_TRAY_EXIT = 65307


class KBDLLHOOKSTRUCT(ctypes.Structure):
    _fields_ = [("vkCode", wt.DWORD), ("scanCode", wt.DWORD), ("flags", wt.DWORD),
                ("time", wt.DWORD), ("dwExtraInfo", ULONG_PTR)]


class KEYBDINPUT(ctypes.Structure):
    _fields_ = [("wVk", wt.WORD), ("wScan", wt.WORD), ("dwFlags", wt.DWORD),
                ("time", wt.DWORD), ("dwExtraInfo", ULONG_PTR)]


class MOUSEINPUT(ctypes.Structure):
    _fields_ = [("dx", wt.LONG), ("dy", wt.LONG), ("mouseData", wt.DWORD), ("dwFlags", wt.DWORD),
                ("time", wt.DWORD), ("dwExtraInfo", ULONG_PTR)]


class _INPUTUNION(ctypes.Union):
    _fields_ = [("ki", KEYBDINPUT), ("mi", MOUSEINPUT)]


class INPUT(ctypes.Structure):
    _fields_ = [("type", wt.DWORD), ("u", _INPUTUNION)]


HOOKPROC = ctypes.WINFUNCTYPE(LRESULT, ctypes.c_int, wt.WPARAM, wt.LPARAM)
WNDPROC = ctypes.WINFUNCTYPE(LRESULT, wt.HWND, wt.UINT, wt.WPARAM, wt.LPARAM)


class WNDCLASSW(ctypes.Structure):
    _fields_ = [("style", wt.UINT), ("lpfnWndProc", WNDPROC), ("cbClsExtra", ctypes.c_int),
                ("cbWndExtra", ctypes.c_int), ("hInstance", wt.HINSTANCE), ("hIcon", wt.HICON),
                ("hCursor", wt.HANDLE), ("hbrBackground", wt.HBRUSH), ("lpszMenuName", wt.LPCWSTR),
                ("lpszClassName", wt.LPCWSTR)]


user32.SetWindowsHookExW.argtypes = [ctypes.c_int, HOOKPROC, wt.HINSTANCE, wt.DWORD]
user32.SetWindowsHookExW.restype = wt.HHOOK
user32.CallNextHookEx.argtypes = [wt.HHOOK, ctypes.c_int, wt.WPARAM, wt.LPARAM]
user32.CallNextHookEx.restype = LRESULT
user32.DefWindowProcW.argtypes = [wt.HWND, wt.UINT, wt.WPARAM, wt.LPARAM]
user32.DefWindowProcW.restype = LRESULT
user32.CreateWindowExW.argtypes = [wt.DWORD, wt.LPCWSTR, wt.LPCWSTR, wt.DWORD, ctypes.c_int, ctypes.c_int,
                                   ctypes.c_int, ctypes.c_int, wt.HWND, wt.HMENU, wt.HINSTANCE, wt.LPVOID]
user32.CreateWindowExW.restype = wt.HWND
user32.SendInput.argtypes = [wt.UINT, ctypes.POINTER(INPUT), ctypes.c_int]
user32.PostThreadMessageW.argtypes = [wt.DWORD, wt.UINT, wt.WPARAM, wt.LPARAM]
user32.PostMessageW.argtypes = [wt.HWND, wt.UINT, wt.WPARAM, wt.LPARAM]
user32.GetForegroundWindow.restype = wt.HWND
user32.GetWindowThreadProcessId.argtypes = [wt.HWND, ctypes.POINTER(wt.DWORD)]
kernel32.GetModuleHandleW.restype = wt.HMODULE

# ---------------------------------------------------------------------------
# キー名
# ---------------------------------------------------------------------------
VK_NAMES = {
    0x08: "BS", 0x09: "Tab", 0x0D: "Enter", 0x1B: "Esc", 0x20: "Space",
    0x21: "PgUp", 0x22: "PgDn", 0x23: "End", 0x24: "Home",
    0x25: "Left", 0x26: "Up", 0x27: "Right", 0x28: "Down", 0x2E: "Del",
    0xA0: "LShift", 0xA1: "RShift", 0xA2: "LCtrl", 0xA3: "RCtrl", 0xA4: "LAlt", 0xA5: "RAlt",
    0x10: "Shift", 0x11: "Ctrl", 0x12: "Alt", 0x5B: "LWin", 0x5C: "RWin",
    0xBC: "Comma", 0xBE: "Period", 0xBF: "Slash", 0xC0: "At", 0xDB: "LBracket",
}
VK_NAMES.update({0x30 + i: str(i) for i in range(10)})
VK_NAMES.update({0x41 + i: chr(0x41 + i) for i in range(26)})
VK_NAMES.update({0x70 + i: f"F{i + 1}" for i in range(24)})
NAME_VK = {v: k for k, v in VK_NAMES.items()}
EXTENDED_VKS = {0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x2D, 0x2E, 0xA3, 0xA5}


def vk_name(vk):
    return VK_NAMES.get(vk, f"vk{vk:02X}")


# ---------------------------------------------------------------------------
# レコーダ (低レベルフック) とテスト用ウィンドウ  ―  専用スレッドで動かす
# ---------------------------------------------------------------------------
class Recorder:
    def __init__(self, window_classes):
        self.events = []
        self.recording = False
        self.windows = {}
        self._window_classes = window_classes
        self._ready = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()
        self._ready.wait(5)

    def _hook(self, ncode, wparam, lparam):
        if ncode == 0 and self.recording:
            k = ctypes.cast(lparam, ctypes.POINTER(KBDLLHOOKSTRUCT)).contents
            src = "drv" if k.dwExtraInfo == DRIVER_TAG else "ahk"
            direction = "up" if wparam in (WM_KEYUP, WM_SYSKEYUP) else "down"
            self.events.append(f"{src} {direction} {vk_name(k.vkCode)}")
        return user32.CallNextHookEx(None, ncode, wparam, lparam)

    @staticmethod
    def _wndproc(hwnd, msg, wparam, lparam):
        # キー入力・Alt メニュー等は全部捨てる (テスト用ウィンドウは何もしない)
        if 0x100 <= msg <= 0x109:
            return 0
        return user32.DefWindowProcW(hwnd, msg, wparam, lparam)

    def _run(self):
        self.thread_id = kernel32.GetCurrentThreadId()
        hinst = kernel32.GetModuleHandleW(None)
        self._hookproc = HOOKPROC(self._hook)
        self._wndproc_ref = WNDPROC(self._wndproc)
        for cls in self._window_classes:
            wc = WNDCLASSW(lpfnWndProc=self._wndproc_ref, hInstance=hinst, lpszClassName=cls,
                           hbrBackground=ctypes.c_void_p(6))  # COLOR_WINDOW+1
            user32.RegisterClassW(ctypes.byref(wc))
            hwnd = user32.CreateWindowExW(0x8, cls, f"Ecaps golden test ({cls})",  # WS_EX_TOPMOST
                                          0x80000000 | 0x10000000 | 0x00800000,  # POPUP|VISIBLE|BORDER
                                          40, 40, 420, 60, None, None, hinst, None)
            self.windows[cls] = hwnd
        self.hhook = user32.SetWindowsHookExW(WH_KEYBOARD_LL, self._hookproc, hinst, 0)
        self._ready.set()
        msg = wt.MSG()
        while user32.GetMessageW(ctypes.byref(msg), None, 0, 0) > 0:
            if msg.message == WM_APP_FOCUS:
                force_foreground(msg.wParam)
                continue
            user32.TranslateMessage(ctypes.byref(msg))
            user32.DispatchMessageW(ctypes.byref(msg))
        user32.UnhookWindowsHookEx(self.hhook)

    def focus(self, cls):
        hwnd = self.windows[cls]
        for _ in range(20):
            user32.PostThreadMessageW(self.thread_id, WM_APP_FOCUS, hwnd, 0)
            time.sleep(0.05)
            if user32.GetForegroundWindow() == hwnd:
                return
        raise RuntimeError(f"テスト用ウィンドウ {cls} を前面にできませんでした")

    def stop(self):
        user32.PostThreadMessageW(self.thread_id, 0x12, 0, 0)  # WM_QUIT


def force_foreground(hwnd):
    fg = user32.GetForegroundWindow()
    fg_tid = user32.GetWindowThreadProcessId(fg, None)
    me = kernel32.GetCurrentThreadId()
    attached = fg_tid and fg_tid != me and user32.AttachThreadInput(me, fg_tid, True)
    user32.BringWindowToTop(hwnd)
    user32.SetForegroundWindow(hwnd)
    user32.SetFocus(hwnd)
    if attached:
        user32.AttachThreadInput(me, fg_tid, False)


# ---------------------------------------------------------------------------
# 入力ドライバ
# ---------------------------------------------------------------------------
def send_key(name, up=False):
    vk = NAME_VK[name]
    scan = user32.MapVirtualKeyW(vk, 0)
    if name == "F13":
        scan = 0x64
    flags = (KEYEVENTF_KEYUP if up else 0) | (KEYEVENTF_EXTENDEDKEY if vk in EXTENDED_VKS else 0)
    inp = INPUT(type=INPUT_KEYBOARD, u=_INPUTUNION(ki=KEYBDINPUT(vk, scan, flags, 0, DRIVER_TAG)))
    if user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(INPUT)) != 1:
        raise RuntimeError(f"SendInput に失敗しました (error {ctypes.get_last_error()})。"
                           "画面ロック中や、RDP ウィンドウが最小化されていると送信できません。")


def play(steps, delay=KEY_DELAY):
    """steps: "F13 down", "f down", "f tap", ("sleep", 0.1) などの列"""
    for step in steps:
        if isinstance(step, tuple):
            time.sleep(step[1])
            continue
        name, action = step.split()
        name = name.upper() if len(name) == 1 else name
        if action in ("down", "tap"):
            send_key(name)
            time.sleep(delay)
        if action in ("up", "tap"):
            send_key(name, up=True)
            time.sleep(delay)


def combo(prefix, key):
    # prefix を離す前に待つ: DeleteRange の Sleep(50) 等、ホットキー側の送出が
    # 終わってから離すことで、イベント順を実行ごとに安定させる
    return [f"{prefix} down", f"{key} tap", ("sleep", 0.15), f"{prefix} up"]


def held_repeat(prefix, key, count, interval):
    """prefix を押したまま key をオートリピート相当で count 回押下"""
    return [f"{prefix} down", ("sleep", KEY_DELAY)] + \
           [s for _ in range(count) for s in (f"{key} down", ("sleep", interval))] + \
           [f"{key} up", ("sleep", KEY_DELAY), f"{prefix} up"]


# ---------------------------------------------------------------------------
# テストケース
#   (名前, ウィンドウクラス, 入力列, 要約するか)
#   要約 = イベント列ではなく (送信元, 向き, キー) ごとの回数を golden にする
# ---------------------------------------------------------------------------
GUI, CONSOLE = "EcapsTestGui", "ConsoleWindowClass"

CASES = []


def case(name, window, steps, summarize=False):
    CASES.append((name, window, steps, summarize))


for k in "fbnpae":
    case(f"gui_f13_{k}", GUI, combo("F13", k))
for k in ["f", "b", "n", "p", "d", "h", "w"]:
    case(f"gui_alt_{k}", GUI, combo("LAlt", k))
for k in "dhkumtgxwcvys":
    case(f"gui_f13_{k}", GUI, combo("F13", k))
case("gui_f13_1", GUI, combo("F13", "1"))
case("gui_mark_select_then_cut", GUI,
     combo("F13", "Space") + combo("F13", "f") + combo("F13", "e") + combo("F13", "w") + combo("F13", "f"))
case("gui_plain_typing", GUI, ["a tap", "f tap", "Enter tap"])
case("gui_f13_alone", GUI, ["F13 tap"])
for k in "kuwy":
    case(f"console_f13_{k}", CONSOLE, combo("F13", k))
for k in ["d", "h", "w", "f"]:
    case(f"console_alt_{k}", CONSOLE, combo("LAlt", k))
case("console_mark", CONSOLE, combo("F13", "Space") + combo("F13", "f"))
# 押し続け (オートリピート) で素のキーが漏れないこと
for k in "fp":
    case(f"gui_hold_f13_{k}", GUI, held_repeat("F13", k, 150, 0.01), summarize=True)
case("gui_hold_f13_f_fast", GUI, held_repeat("F13", "f", 300, 0.002), summarize=True)
# ※ Alt+f の押し続けはテストしない。注入した Alt は AHK から「物理的に押されて
#    いない」と見なされ、Send 後に Alt が押し直されないため、実機と挙動が異なる。


def summarize(events):
    counts = {}
    for e in events:
        counts[e] = counts.get(e, 0) + 1
    return [f"{e} x{n}" for e, n in sorted(counts.items())]


# ---------------------------------------------------------------------------
# AHK プロセス管理
# ---------------------------------------------------------------------------
def ahk_pids():
    out = subprocess.run(["tasklist", "/FO", "CSV", "/NH"], capture_output=True, text=True,
                         encoding="mbcs", errors="replace").stdout
    pids = []
    for line in out.splitlines():
        cols = [c.strip('"') for c in line.split('","')]
        if len(cols) > 1 and cols[0].lower().startswith("autohotkey"):
            pids.append(int(cols[1]))
    return pids


def ahk_windows(pid):
    found = []

    @ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)
    def cb(hwnd, _):
        p = wt.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(p))
        buf = ctypes.create_unicode_buffer(64)
        user32.GetClassNameW(hwnd, buf, 64)
        if p.value == pid and buf.value == "AutoHotkey":
            found.append(hwnd)
        return True

    user32.EnumWindows(cb, 0)
    return found


def stop_ahk(pid, timeout=5):
    for hwnd in ahk_windows(pid):
        user32.PostMessageW(hwnd, WM_COMMAND, AHK_ID_TRAY_EXIT, 0)
    end = time.time() + timeout
    while time.time() < end and pid in ahk_pids():
        time.sleep(0.1)
    return pid not in ahk_pids()


def startup_ahk_entries():
    startup = Path(os.environ["APPDATA"]) / r"Microsoft\Windows\Start Menu\Programs\Startup"
    return [p for p in startup.iterdir() if p.suffix.lower() in (".lnk", ".ahk")]


def release_all():
    for name in ["F13", "LAlt", "LShift", "LCtrl"]:
        try:
            send_key(name, up=True)
        except RuntimeError:
            pass


# ---------------------------------------------------------------------------
def main():
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser()
    ap.add_argument("--update", action="store_true", help="golden を現在の結果で上書き")
    ap.add_argument("-k", default="", help="名前にこの文字列を含むケースだけ実行")
    ap.add_argument("--script", type=Path, default=SCRIPT, help="テスト対象の .ahk (既定 Ecaps.ahk)")
    ap.add_argument("--golden-dir", type=Path, default=GOLDEN_DIR, help="golden の置き場 (既定 tests/golden)")
    ap.add_argument("--stop-others", action="store_true",
                    help="他の AutoHotkey を終了し、テスト後にスタートアップから再起動する")
    ap.add_argument("--allow-others", action="store_true",
                    help="他の AutoHotkey が動いていてもそのまま実行する (結果が実運用と異なり得る)")
    args = ap.parse_args()
    golden_dir = args.golden_dir

    others = ahk_pids()
    restart = []
    if others and args.allow_others:
        print(f"警告: 他の AutoHotkey が動作中 (PID {others})。SendInput が SendEvent に切り替わった状態でテストします。")
    elif others:
        if not args.stop_others:
            sys.exit(f"他の AutoHotkey が動作中です (PID {others})。終了させるか --stop-others を付けて再実行してください。")
        restart = startup_ahk_entries()
        for pid in others:
            if not stop_ahk(pid):
                sys.exit(f"AutoHotkey (PID {pid}) を終了できませんでした。手動で終了してから再実行してください。")

    cases = [c for c in CASES if args.k in c[0]]
    print("3 秒後に開始します。終わるまでキーボード・マウスに触れないでください。")
    time.sleep(3)

    rec = Recorder([GUI, CONSOLE])
    if not args.script.exists():
        sys.exit(f"スクリプトが見つかりません: {args.script}")
    ahk = subprocess.Popen([str(AHK_EXE), str(args.script)])
    try:
        for _ in range(50):
            if ahk_windows(ahk.pid):
                break
            time.sleep(0.1)
        else:
            raise RuntimeError("テスト対象の AutoHotkey が起動しませんでした")
        time.sleep(0.5)

        golden_dir.mkdir(parents=True, exist_ok=True)
        failed, written = [], []
        for name, window, steps, summ in cases:
            rec.focus(window)
            time.sleep(0.1)
            rec.events = []
            rec.recording = True
            play(steps)
            time.sleep(SETTLE)
            rec.recording = False
            release_all()
            lines = summarize(rec.events) if summ else list(rec.events)
            actual = "\n".join(lines) + "\n"
            path = golden_dir / f"{name}.txt"
            if args.update or not path.exists():
                path.write_text(actual, encoding="utf-8", newline="\n")
                written.append(name)
                print(f"  WROTE {name}")
                continue
            expected = path.read_text(encoding="utf-8")
            if expected == actual:
                print(f"  ok    {name}")
            else:
                failed.append(name)
                print(f"  FAIL  {name}")
                sys.stdout.writelines("        " + l + "\n" for l in difflib.unified_diff(
                    expected.splitlines(), actual.splitlines(), "golden", "actual", lineterm=""))
    finally:
        release_all()
        stop_ahk(ahk.pid) or ahk.kill()
        rec.stop()
        for entry in restart:
            os.startfile(entry)
            print(f"再起動: {entry.name}")

    checked = len(cases) - len(written)
    print(f"\n{checked - len(failed)}/{checked} passed" + (f", {len(written)} golden written" if written else ""))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
