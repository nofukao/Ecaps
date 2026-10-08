; UI Automation でフォーカス中の要素のクラス名を標準出力に書く (vscode_terminal_test.py 用)
#Requires AutoHotkey v2.0
#NoTrayIcon
uia := ComObject("{ff48dba4-60ef-4201-aa87-54103eef594e}", "{30cbe57d-d9d0-452a-ab13-7ac5ac4825ee}")
ComCall(8, uia, "Ptr*", &el := 0)          ; IUIAutomation::GetFocusedElement
ComCall(30, el, "Ptr*", &bstr := 0)        ; IUIAutomationElement::get_CurrentClassName
FileAppend(bstr ? StrGet(bstr, "UTF-16") : "", "*", "UTF-8")
