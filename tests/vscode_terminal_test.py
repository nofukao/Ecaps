"""VSCode 内蔵ターミナル (Git Bash) での Ecaps の end-to-end テスト

golden_test.py が「Ecaps が送出するキー列」を見るのに対し、こちらは VSCode の
ターミナルで bash (readline) が実際にどう編集したかを確かめる。VSCode は Ctrl+K を
chord の 1 打目として横取りする等、キーが bash に届くかは VSCode 次第なので、
キー列の golden だけでは足りないため。

仕組み:
  1. 使い捨ての --user-data-dir / --extensions-dir で VSCode を別インスタンス起動
     (ユーザーの VSCode 設定には触れない。既定設定のまま、既定プロファイルだけ Git Bash)。
  2. Ecaps.ahk を起動し、VSCode のターミナルで「行を打つ → Ecaps のキー → echo で
     結果をファイルへ追記」を繰り返す。
  3. 追記された各行を期待値と比較する。

使い方:
  python tests/vscode_terminal_test.py
  python tests/vscode_terminal_test.py --keep   # 終了後も VSCode を閉じない (調査用)

注意: 実行中 (1 分程度) はキーボード・マウスに触れないこと。Git Bash が必要。
"""

import argparse
import ctypes
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import golden_test as g  # noqa: E402

user32 = g.user32
CODE_EXE = Path(os.environ.get("ECAPS_CODE_EXE", Path(os.environ["LOCALAPPDATA"]) / r"Programs\Microsoft VS Code\Code.exe"))
KEYEVENTF_UNICODE = 0x4
WORKSPACE_NAME = "ecaps-vscode-test"

# (名前, 打鍵列, 期待される echo 出力)
#   打鍵列: 文字列はそのままタイプ。("key", "Left") 等はキー、("combo", "F13", "k") は同時押し。
#   各ケースの最後に ' >> "$O"' + Enter を打ち、echo の出力を結果ファイルへ追記する。
CASES = [
    ("kill_line",  ["echo abc123", ("key", "Left", 3), ("combo", "F13", "k"), "XY"], "abcXY"),
    ("kill_bol",   ["garbage", ("combo", "F13", "u"), "echo u-ok"], "u-ok"),
    ("kill_word",  ["echo aaa bbb", ("key", "Left", 3), ("combo", "LAlt", "d")], "aaa"),
    ("bkill_word", ["echo aaa bbb", ("combo", "LAlt", "h")], "aaa"),
    ("yank",       ["echo abc123", ("key", "Left", 3), ("combo", "F13", "k"), ("combo", "F13", "y")], "abc123"),
    ("move",       ["echo 1234", ("combo", "F13", "b"), ("combo", "F13", "b"), ("combo", "F13", "h"),
                    ("combo", "F13", "e")], "134"),
]


def send_text(text):
    for ch in text:
        for flags in (KEYEVENTF_UNICODE, KEYEVENTF_UNICODE | g.KEYEVENTF_KEYUP):
            g.send_input(0, ord(ch), flags)
        time.sleep(0.01)


def run_steps(steps):
    for step in steps:
        if isinstance(step, str):
            send_text(step)
        elif step[0] == "key":
            for _ in range(step[2] if len(step) > 2 else 1):
                g.play([f"{step[1]} tap"])
        elif step[0] == "combo":
            g.play(g.combo(step[1], step[2]))
        time.sleep(0.05)


def find_window(title_part, timeout=30):
    end = time.time() + timeout
    while time.time() < end:
        found = []

        @ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)
        def cb(hwnd, _):
            buf = ctypes.create_unicode_buffer(512)
            user32.GetWindowTextW(hwnd, buf, 512)
            if title_part in buf.value and user32.IsWindowVisible(hwnd):
                found.append(hwnd)
            return True

        user32.EnumWindows(cb, 0)
        if found:
            return found[0]
        time.sleep(0.5)
    raise RuntimeError(f"ウィンドウ '{title_part}' が見つかりません")


def focus(hwnd):
    g.GUARD_HWND = hwnd  # 以後、この VSCode が前面のときだけ入力を送る
    for _ in range(20):
        g.force_foreground(hwnd)
        time.sleep(0.1)
        if user32.GetForegroundWindow() == hwnd:
            return
    raise RuntimeError("VSCode を前面にできませんでした")


def focused_class():
    r = subprocess.run([str(g.AHK_EXE), "/ErrorStdOut", str(Path(__file__).with_name("uia_focus.ahk"))],
                       capture_output=True, timeout=10)
    return r.stdout.decode("utf-8", "replace").strip()


def require_terminal_focus(hwnd, timeout=15):
    """テスト用 VSCode のターミナル入力欄にフォーカスがあるときだけ先へ進む (誤入力防止)"""
    end = time.time() + timeout
    while time.time() < end:
        focus(hwnd)
        if focused_class() == "xterm-helper-textarea":
            return
        time.sleep(0.5)
    raise RuntimeError(f"テスト用 VSCode のターミナルにフォーカスできません (focus={focused_class()!r})")


def wait_file(path, timeout=20, min_lines=1):
    end = time.time() + timeout
    while time.time() < end:
        if path.exists() and len(path.read_text(encoding="utf-8", errors="replace").splitlines()) >= min_lines:
            return True
        time.sleep(0.2)
    return False


def clean_env():
    # VSCode 内 (Claude Code 等) から起動すると ELECTRON_RUN_AS_NODE 等が継承され、
    # Code.exe が VSCode ではなく Node として動いてしまうので取り除く
    return {k: v for k, v in os.environ.items()
            if not (k.startswith("VSCODE_") or k.startswith("ELECTRON_"))}


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser()
    ap.add_argument("--script", type=Path, default=g.SCRIPT)
    ap.add_argument("--keep", action="store_true")
    args = ap.parse_args()


    tmp = Path(tempfile.mkdtemp(prefix="ecaps-vsc-"))
    ws = tmp / WORKSPACE_NAME
    (tmp / "user" / "User").mkdir(parents=True)
    ws.mkdir()
    out = tmp / "out.txt"
    settings = {
        "terminal.integrated.defaultProfile.windows": "Git Bash",
        "security.workspace.trust.enabled": False,
        "workbench.startupEditor": "none",
        "terminal.integrated.confirmOnExit": "never",
        "terminal.integrated.confirmOnKill": "never",
        "update.mode": "none",
        "telemetry.telemetryLevel": "off",
        "workbench.tips.enabled": False,
        # 初回起動時のサインイン/オンボーディング画面を出さない (Enter 等が誤爆するため)
        "workbench.welcomePage.experimentalOnboarding": False,
        "workbench.welcomePage.walkthroughs.openOnInstall": False,
        "chat.disableAIFeatures": True,
    }
    (tmp / "user" / "User" / "settings.json").write_text(json.dumps(settings), encoding="utf-8")
    # テスト環境でターミナルを開くためだけのキー (ユーザー環境ではない)
    (tmp / "user" / "User" / "keybindings.json").write_text(json.dumps(
        [{"key": "f24", "command": "workbench.action.terminal.focus"}]), encoding="utf-8")

    print("VSCode (テスト用インスタンス) を起動します。終わるまでキーボード・マウスに触れないでください。")
    code = subprocess.Popen([str(CODE_EXE), "--user-data-dir", str(tmp / "user"), "--extensions-dir", str(tmp / "ext"),
                             "--disable-extensions", "--new-window", str(ws)], env=clean_env())
    ahk = None
    results = []
    try:
        hwnd = find_window(WORKSPACE_NAME)
        time.sleep(3)
        focus(hwnd)
        g.play(["F24 tap"])
        require_terminal_focus(hwnd)
        time.sleep(3)  # bash の起動待ち
        bash_out = "/" + str(out).replace(":", "").replace("\\", "/")
        bash_out = bash_out[0] + bash_out[1].lower() + bash_out[2:]
        require_terminal_focus(hwnd)
        send_text(f'O="{bash_out}"; echo ready > "$O"')
        g.play(["Enter tap"])
        if not wait_file(out):
            raise RuntimeError("ターミナル (Git Bash) が応答しません")

        ahk = subprocess.Popen([str(g.AHK_EXE), str(args.script)])
        time.sleep(1.5)

        for name, steps, _ in CASES:
            require_terminal_focus(hwnd)
            g.play(["LCtrl down", "C tap", "LCtrl up"])  # 入力途中の行を捨てる
            time.sleep(0.2)
            run_steps(steps)
            send_text(' >> "$O"')
            g.play(["Enter tap"])
            time.sleep(0.3)
            require_terminal_focus(hwnd)
            send_text(f'echo "--{name}" >> "$O"')  # ケースの区切り
            g.play(["Enter tap"])
            time.sleep(0.5)
        got, buf = {}, []
        for line in out.read_text(encoding="utf-8", errors="replace").splitlines()[1:]:
            if line.startswith("--"):
                got[line[2:]] = buf
                buf = []
            else:
                buf.append(line)
        failed = 0
        for name, _, expected in CASES:
            actual = got.get(name)
            ok = actual == [expected]
            failed += not ok
            print(f"  {'ok  ' if ok else 'FAIL'}  {name:12s} expected={expected!r} actual={actual!r}")
        print(f"\n{len(CASES) - failed}/{len(CASES)} passed")
        results = failed
    finally:
        g.release_all()
        if ahk:
            g.stop_ahk(ahk.pid) or ahk.kill()
        if not args.keep:
            try:
                user32.PostMessageW(find_window(WORKSPACE_NAME, timeout=1), g.WM_CLOSE, 0, 0)
            except RuntimeError:
                pass
            time.sleep(3)
            shutil.rmtree(tmp, ignore_errors=True)
    sys.exit(1 if results else 0)


if __name__ == "__main__":
    main()
