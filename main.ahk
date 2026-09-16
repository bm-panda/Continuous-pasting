#Requires AutoHotkey v2.0
#SingleInstance Force

; ─── Global State ───
clipQueue := []
isPasting := false
prevText := ""
autoExit := true
injectMode := "input"
apiBase := ""
configFile := A_ScriptDir "\config.ini"

; ─── Hotkey ───
#InputLevel 1
^v:: PasteHandler
#InputLevel 0

; ─── Initialization ───
apiBase := ReadApiBase(A_Args.Length > 0 ? A_Args[1] : "")
ReadConfig()
try prevText := A_Clipboard
SetTimer(WatchClipboard, 300)
SetupTrayMenu()
DebugLog("START v1.2.4 | apiBase=" (apiBase = "" ? "(none)" : apiBase) " | mode=" injectMode)
BoxNotify("success", "连续粘贴启动成功，请先复制多段文本，再按 Ctrl+V 逐条粘贴")

; ─── Box API ───
ReadApiBase(paramPath) {
    if (paramPath = "" || !FileExist(paramPath))
        return ""
    try content := FileRead(paramPath, "UTF-8")
    catch
        return ""
    if RegExMatch(content, '"api_base"\s*:\s*"([^"]+)"', &m)
        return m[1]
    return ""
}

BoxNotify(type, message) {
    global apiBase
    if (apiBase = "") {
        TrayTip(message, "连续粘贴", "Iconi")
        SetTimer(() => TrayTip(), -3000)
        return
    }
    try {
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.SetTimeouts(1000, 1000, 1000, 1000)
        whr.Open("POST", apiBase "/api/notify", false)
        whr.SetRequestHeader("Content-Type", "application/json")
        whr.Send('{"notify_type":"' type '","message":"' JsonEscape(message) '"}')
    }
}

JsonEscape(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`r", "\r")
    s := StrReplace(s, "`t", "\t")
    return s
}

DebugLog(msg) {
    try FileAppend(FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") " | " msg "`n", A_Temp "\cp_debug.log", "UTF-8")
}

; ─── Config ───
ReadConfig() {
    global autoExit, injectMode
    if !FileExist(configFile) {
        autoExit := true
        injectMode := "input"
        WriteConfig()
        return
    }
    autoExit := (IniRead(configFile, "Settings", "AutoExit", "true") = "true")
    injectMode := IniRead(configFile, "Settings", "SendMode", "input")
    if (injectMode != "input" && injectMode != "play" && injectMode != "control")
        injectMode := "input"
}

WriteConfig() {
    global autoExit, injectMode
    IniWrite(autoExit ? "true" : "false", configFile, "Settings", "AutoExit")
    IniWrite(injectMode, configFile, "Settings", "SendMode")
}

; ─── Clipboard Monitor ───
WatchClipboard() {
    EnqueueClipboard()
}

EnqueueClipboard() {
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

; ─── Paste Handler (Ctrl+V) ───
PasteHandler(*) {
    global clipQueue, isPasting, prevText, autoExit, injectMode
    if isPasting
        return
    isPasting := true
    DebugLog("HOTKEY FIRED | queue=" clipQueue.Length " | mode=" injectMode)
    pasted := false
    if clipQueue.Length > 0 {
        text := clipQueue.RemoveAt(1)
        A_Clipboard := text
        if !ClipWait(1) {
            isPasting := false
            DebugLog("CLIPBOARD WRITE TIMEOUT")
            BoxNotify("error", "剪贴板写入超时，请重试。")
            return
        }
        pasted := true
    }
    SendLevel(0)
    InjectPaste()
    Sleep(50)
    DebugLog("INJECTED | mode=" injectMode)
    isPasting := false
    try prevText := A_Clipboard
    UpdateTrayTip()
    if pasted && clipQueue.Length = 0 {
        BoxNotify("success", "全部粘贴完成，队列已清空。")
        if autoExit
            SetTimer(() => ExitApp(), -2000)
    }
}

InjectPaste() {
    global injectMode
    switch injectMode {
        case "play":
            SendMode("Play")
            Send("^v")
            SendMode("Input")
        case "control":
            ctrl := ""
            try ctrl := ControlGetFocus("A")
            ControlSend("^v", ctrl, "A")
        default:
            SendInput("^v")
    }
}

; ─── Tray ───
SetupTrayMenu() {
    global compatMenu, autoExit
    compatMenu := Menu()
    compatMenu.Add("SendInput（默认）", (*) => SetSendMode("input"))
    compatMenu.Add("SendPlay", (*) => SetSendMode("play"))
    compatMenu.Add("ControlSend", (*) => SetSendMode("control"))
    A_TrayMenu.Delete()
    A_TrayMenu.Add("查看队列 (&1)", ShowQueue)
    A_TrayMenu.Add("清空队列 (&2)", ClearQueue)
    A_TrayMenu.Add()
    A_TrayMenu.Add("自动退出 (&3)", ToggleAutoExit)
    A_TrayMenu.Add("重新加载 (&4)", (*) => Reload())
    A_TrayMenu.Add()
    A_TrayMenu.Add("兼容模式 (&6)", compatMenu)
    A_TrayMenu.Add()
    A_TrayMenu.Add("退出 (&5)", (*) => ExitApp())
    if autoExit
        A_TrayMenu.Check("自动退出 (&3)")
    UpdateCompatChecks()
    UpdateTrayTip()
}

UpdateCompatChecks() {
    global compatMenu, injectMode
    compatMenu.Uncheck("SendInput（默认）")
    compatMenu.Uncheck("SendPlay")
    compatMenu.Uncheck("ControlSend")
    switch injectMode {
        case "play": compatMenu.Check("SendPlay")
        case "control": compatMenu.Check("ControlSend")
        default: compatMenu.Check("SendInput（默认）")
    }
}

SetSendMode(mode) {
    global injectMode
    injectMode := mode
    WriteConfig()
    UpdateCompatChecks()
    DebugLog("MODE CHANGED | " mode)
    BoxNotify("success", "注入模式已切换为 " ModeLabel(mode))
}

ModeLabel(mode) {
    switch mode {
        case "play": return "SendPlay"
        case "control": return "ControlSend"
        default: return "SendInput"
    }
}

UpdateTrayTip() {
    global clipQueue
    n := clipQueue.Length
    A_IconTip := n > 0
        ? "连续粘贴 - 队列: " n " 项"
        : "连续粘贴 - 就绪"
}

ShowQueue(*) {
    global clipQueue
    n := clipQueue.Length
    if n = 0 {
        MsgBox("队列为空。"
            "`n`n请先复制文本，然后按 Ctrl+V 按顺序粘贴。"
            "`n想恢复普通粘贴，可先在托盘菜单清空队列。",
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
    BoxNotify("success", "队列已清空。")
}

ToggleAutoExit(*) {
    global autoExit
    autoExit := !autoExit
    WriteConfig()
    if autoExit
        A_TrayMenu.Check("自动退出 (&3)")
    else
        A_TrayMenu.Uncheck("自动退出 (&3)")
}