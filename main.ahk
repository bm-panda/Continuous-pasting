#Requires AutoHotkey v2.0
#SingleInstance Force

; ─── Global State ───
clipQueue := []
isPasting := false
prevText := ""
currentHotkey := ""
autoExit := true
configFile := A_ScriptDir "\config.ini"

; ─── Initialization ───
ReadConfig()
RegisterHotkey()
try prevText := A_Clipboard
SetTimer(WatchClipboard, 300)
SetupTrayMenu()

; ─── Config ───
ReadConfig() {
    global currentHotkey, autoExit
    if !FileExist(configFile) {
        currentHotkey := "^Numpad0"
        autoExit := true
        WriteConfig()
        return
    }
    currentHotkey := IniRead(configFile, "Settings", "Hotkey", "^Numpad0")
    autoExit := (IniRead(configFile, "Settings", "AutoExit", "true") = "true")
}

WriteConfig() {
    IniWrite(currentHotkey, configFile, "Settings", "Hotkey")
    IniWrite(autoExit ? "true" : "false", configFile, "Settings", "AutoExit")
}

RegisterHotkey() {
    global currentHotkey
    try Hotkey(currentHotkey, "Off")
    try {
        Hotkey(currentHotkey, PasteHandler)
    } catch {
        TrayTip("快捷键 " currentHotkey " 无效，已恢复默认。", "连续粘贴", "Iconi")
        currentHotkey := "^Numpad0"
        WriteConfig()
        Hotkey(currentHotkey, PasteHandler)
    }
}

; ─── Clipboard Monitor ───
WatchClipboard() {
    global clipQueue, isPasting, prevText
    if isPasting
        return
    curText := ""
    try curText := A_Clipboard
    if (curText != "" && curText != prevText) {
        clipQueue.Push(curText)
        prevText := curText
        UpdateTrayTip()
    }
}

; ─── Paste Handler ───
PasteHandler(*) {
    global clipQueue, isPasting, prevText, autoExit
    if clipQueue.Length = 0 {
        TrayTip("队列为空，请先复制文本。", "连续粘贴", "Iconi")
        SetTimer(() => TrayTip(), -2000)
        return
    }
    isPasting := true
    text := clipQueue.RemoveAt(1)
    A_Clipboard := text
    if !ClipWait(1) {
        isPasting := false
        TrayTip("剪贴板写入超时，请重试。", "连续粘贴", "Iconi")
        SetTimer(() => TrayTip(), -2000)
        return
    }
    SendInput("^v")
    Sleep(150)
    try prevText := A_Clipboard
    isPasting := false
    UpdateTrayTip()
    if clipQueue.Length = 0 {
        TrayTip("全部粘贴完成，队列已清空。", "连续粘贴", "Iconi")
        if autoExit
            SetTimer(() => ExitApp(), -2000)
    }
}

; ─── Tray ───
SetupTrayMenu() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add("查看队列 (&1)", ShowQueue)
    A_TrayMenu.Add("清空队列 (&2)", ClearQueue)
    A_TrayMenu.Add()
    A_TrayMenu.Add("设置 (&4)", ShowSettings)
    A_TrayMenu.Add("重新加载 (&5)", (*) => Reload())
    A_TrayMenu.Add()
    A_TrayMenu.Add("退出 (&3)", (*) => ExitApp())
    UpdateTrayTip()
}

UpdateTrayTip() {
    global clipQueue, currentHotkey
    n := clipQueue.Length
    hk := FormatHotkey(currentHotkey)
    A_IconTip := n > 0
        ? "连续粘贴 - 队列: " n " 项 (" hk ")"
        : "连续粘贴 - 就绪 (" hk ")"
}

ShowQueue(*) {
    global clipQueue
    n := clipQueue.Length
    if n = 0 {
        MsgBox("队列为空。"
            "`n`n请先复制文本，然后按快捷键按顺序粘贴。"
            "`n可在托盘菜单「设置」中自定义快捷键。",
            "队列状态")
        return
    }
    text := "队列中共 " n " 项:`n`n"
    for i, item in clipQueue {
        preview := SubStr(item, 1, 60)
        if StrLen(item) > 60
            preview .= "..."
        text .= i ": " preview "`n"
    }
    MsgBox(text, "队列状态")
}

ClearQueue(*) {
    global clipQueue
    clipQueue := []
    UpdateTrayTip()
    TrayTip("队列已清空。", "连续粘贴", "Iconi")
    SetTimer(() => TrayTip(), -1500)
}

; ─── Settings GUI ───
ShowSettings(*) {
    global currentHotkey, autoExit
    capturedHk := ""
    sGui := Gui("+AlwaysOnTop +ToolWindow", "连续粘贴 - 设置")
    sGui.SetFont("s10")
    sGui.Add("Text", "w75 Section", "快捷键:")
    hkEdit := sGui.Add("Edit", "x+m w150 h22 ReadOnly", FormatHotkey(currentHotkey))
    hkBtn := sGui.Add("Button", "x+m w55", "录制")
    sGui.Add("Text", "x+m w200 cGray", "点击「录制」后按新组合键")
    sGui.Add("Text", "xs y+m", "自动退出:")
    exitCb := sGui.Add("CheckBox", "x+m", "队列清空后自动退出脚本")
    exitCb.Value := autoExit
    sGui.Add("Text", "xs y+m", "")
    sGui.Add("Button", "x+m w80 Default", "保存").OnEvent("Click", SaveSettings)
    sGui.Add("Button", "x+m w80", "取消").OnEvent("Click", (*) => sGui.Destroy())
    hkBtn.OnEvent("Click", (*) => StartCapture(sGui, hkEdit))
    sGui.capturedHk := ""
    sGui.exitCb := exitCb
    sGui.Show("w480 h150")
    return

    SaveSettings(*) {
        newHk := sGui.capturedHk
        newExit := sGui.exitCb.Value
        if newHk = ""
            newHk := currentHotkey
        currentHotkey := newHk
        autoExit := newExit
        WriteConfig()
        sGui.Destroy()
        Reload()
    }
}

StartCapture(parentGui, editCtrl) {
    global currentHotkey
    Hotkey(currentHotkey, "Off")
    recGui := Gui("+AlwaysOnTop +ToolWindow +Owner", "录制快捷键")
    recGui.SetFont("s10 bold")
    recGui.Add("Text", "w280", "请在键盘上按下新的快捷键组合")
    recGui.SetFont("s9 norm")
    recGui.Add("Text", "w280 cGray", "必须包含 Ctrl / Alt / Win 修饰键")
    recGui.Add("Text", "w280 cGray", "按 Esc 取消")
    status := recGui.Add("Text", "w280 cBlue", "等待输入...")
    recGui.Show("w300 h120")
    captured := ""
    while !captured {
        Sleep 50
        if !WinExist(recGui)
            break
        if GetKeyState("Escape", "P") {
            recGui.Destroy()
            break
        }
        ctrl := GetKeyState("Ctrl", "P")
        alt := GetKeyState("Alt", "P")
        shift := GetKeyState("Shift", "P")
        win := GetKeyState("LWin", "P") || GetKeyState("RWin", "P")
        if !ctrl && !alt && !win
            continue
        key := DetectPressedKey()
        if !key
            continue
        prefix := ""
        if ctrl
            prefix .= "^"
        if alt
            prefix .= "!"
        if shift
            prefix .= "+"
        if win
            prefix .= "#"
        captured := prefix key
        KeyWait(key)
        Sleep 100
    }
    recGui.Destroy()
    if captured {
        editCtrl.Text := FormatHotkey(captured)
        parentGui.capturedHk := captured
    }
    Hotkey(currentHotkey, PasteHandler)
}

DetectPressedKey() {
    Loop 12 {
        if GetKeyState("F" A_Index, "P")
            return "F" A_Index
    }
    Loop 10 {
        if GetKeyState("Numpad" (A_Index - 1), "P")
            return "Numpad" (A_Index - 1)
    }
    Loop 26 {
        key := Chr(0x60 + A_Index)
        if GetKeyState(key, "P")
            return key
    }
    for _, key in ["0","1","2","3","4","5","6","7","8","9"] {
        if GetKeyState(key, "P")
            return key
    }
    for _, key in ["Space", "Tab", "Enter", "Backspace", "Delete", "Insert", "Home", "End", "PgUp", "PgDn", "ScrollLock", "Pause", "PrintScreen", "AppsKey", "."] {
        if GetKeyState(key, "P")
            return key
    }
    return ""
}

FormatHotkey(hk) {
    display := ""
    if InStr(hk, "^")
        display .= "Ctrl+"
    if InStr(hk, "!")
        display .= "Alt+"
    if InStr(hk, "+")
        display .= "Shift+"
    if InStr(hk, "#")
        display .= "Win+"
    key := hk
    for _, m in ["^", "!", "+", "#"]
        key := StrReplace(key, m, "")
    if SubStr(key, 1, 6) = "Numpad"
        key := "小键盘" SubStr(key, 7)
    else if StrLen(key) = 1
        key := StrUpper(key)
    return display key
}
