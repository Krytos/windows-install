#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir(A_ScriptDir)
SendMode("Input")
DetectHiddenWindows(True)
SetTitleMatchMode(2)

Name := SubStr(A_ScriptName, 1, -4)
if not FileExist(A_Startup "\" Name ".lnk")
{
    if not A_IsAdmin {
        Run("*RunAs " A_ScriptFullPath)
    }
    FileCreateShortcut(A_ScriptFullPath, A_Startup "\" Name ".lnk")
}

; Detect boot entry
bootEntry := ""
RunWait("cmd /c bcdedit /enum {current} | findstr /i description", , bootEntry)

if InStr(bootEntry, "Work")
{
    ; Run Work-specific programs
    Run("C:\Program Files\Docker\Docker.exe")
    Run("C:\Program Files\JetBrains\PyCharm\bin\pycharm64.exe")
    Run("C:\Users\Kevin\AppData\Local\JetBrains\Toolbox\bin\jetbrains-toolbox.exe")
}
else if InStr(bootEntry, "Gaming")
{
    ; Run Steam and Discord
    Run("C:\Program Files (x86)\Steam\Steam.exe")
    Run("C:\Users\Kevin\AppData\Local\Discord\Update.exe --processStart Discord.exe")
}

userprofile := "C:\Users\" A_UserName
app_dir := "%appdata%"
app_running := Map("wow", false, "dota", false, "poe", false)
counter := 0
RunOnce()

SetTimer(WatchForApp, 1000)
SetTimer(Manga, 1000)

WatchForApp()
{
    global counter
    global userprofile
    global app_running
    global app_dir


    ; L-Connect
    try {
        if WinExist("ahk_exe L-Connect 3.exe")
        {
            Sleep(5000)
            ProcessClose("L-Connect 3.exe")
            return
        }
    }

    ; WoW
    if WinExist("ahk_exe Wow.exe") or WinExist("ahk_exe WowT.exe") or WinExist("ahk_exe WowB.exe") {
        app_running["wow"] := true
        try {
            if not WinExist("ahk_exe RaiderIO.exe") {
                Run("C:\Program Files\RaiderIO\RaiderIO.exe")
                Sleep(1000)
                return
            }
        }
        try {
            if not WinExist("ahk_exe lghub.exe") {
                Run("C:\Program Files\LGHUB\system_tray\lghub_system_tray.exe")
                Sleep(1000)
                return
            }
        }
        try {
            if not WinExist("ahk_exe WarcraftRecorder.exe") {
                Run("C:\Users\Kevin\AppData\Local\Programs\WarcraftRecorder\WarcraftRecorder.exe")
                Sleep(1000)
                return
            }
        }
        try {
            if not WinExist("ahk_exe flet.exe") and not WinExist("ahk_exe Parse God.exe") and not WinExist("ParseGod ahk_exe pycharm64.exe") {
                Run(userprofile "\OneDrive\Game Macro\Parse God.exe", userprofile "\OneDrive\Game Macro\")
                Sleep(15000)
                return
            }
        }
    }
    else
    {
        if WinExist("ahk_exe RaiderIO.exe") {
            ProcessClose("RaiderIO.exe")
            return
        }
        if WinExist("ahk_exe lghub.exe") {
            ProcessClose("lghub.exe")
            return
        }
        if WinExist("ahk_exe WarcraftRecorder.exe") {
            ProcessClose("WarcraftRecorder.exe")
            return
        }
        if WinExist("ahk_exe flet.exe") {
            ProcessClose("flet.exe")
            return
        }
        if app_running["wow"] {
            app_running["wow"] := false
            Run('cmd.exe /c git add -A && git commit -m "' . FormatTime(, "yyyy.MM.dd-HH.mm.ss") . '" && /c git push', "D:\Games\World of Warcraft\_retail_\WTF")
            return
        }
    }

    ; Dota 2
    try {
        if WinExist("ahk_exe dota2.exe")
        {
            if not WinExist("dota_mini.ahk") {
                Run(userprofile "\OneDrive\Desktop\Game Macro\dota_mini.ahk")
                return
            }
        }
        else
        {
            if WinExist("dota_mini.ahk") {
                WinClose(userprofile "\OneDrive\Desktop\Game Macro\dota_mini.ahk ahk_class AutoHotkey")
                return
            }
        }
    }

    ; Battle.net
    try {
        if WinExist("ahk_exe Battle.net.exe") {
            if ( not WinExist("ahk_exe CurseBreaker.exe") and counter < 1)
            {
                counter++
                Run("cmd.exe /c CurseBreaker.exe wago_update headless", "D:\Games\World of Warcraft\_retail_")
                Run('cmd.exe /c git pull', "D:\Games\World of Warcraft\_retail_\WTF", "Hide")
                Run("*RunAs C:\Users\Kevin\AppData\Local\Programs\wowup-cf\WowUp-CF.exe")
                return
            }
        }
    }

    ; Path of Exile
    try {
        if WinExist("ahk_exe PathOfExileSteam.exe")
        {
            if not WinExist("flasks.ahk") {
                Run(userprofile "\OneDrive\Desktop\Game Macro\PoE Tools\flasks.ahk")
                return
            }
            if not WinExist("ahk_exe Awakened PoE Trade.exe") and not WinExist("Awakened PoE Trade Setup") {
                Run(userprofile "\AppData\Local\Programs\Awakened PoE Trade\Awakened PoE Trade.exe")
                return
            }
            if not WinExist("ahk_exe PoeLurker.exe") {
                Run(userprofile "\AppData\Local\PoeLurker\PoeLurker.exe")
                return
            }
        }
    }
    try {
        if not WinExist("ahk_exe PathOfExileSteam.exe")
        {
            if WinExist("flasks.ahk") {
                WinClose(userprofile "\OneDrive\Desktop\Game Macro\PoE Tools\flasks.ahk ahk_class AutoHotkey")
                return
            }
            if WinExist("ahk_exe Awakened PoE Trade.exe") {
                ProcessClose("Awakened PoE Trade.exe")
                return
            }
            if WinExist("ahk_exe PoeLurker.exe") {
                ProcessClose("PoeLurker.exe")
                return
            }
        }
    }
}

Manga()
{
    try {
        if WinActive("Tower of God ahk_exe chrome.exe") or WinActive("Chapter ahk_exe chrome.exe") or WinActive("TurtleMe ahk_exe chrome.exe") or WinActive("Tapas ahk_exe chrome.exe")
        {
            if not WinExist("Manga.ahk") {
                Run(userprofile "\OneDrive\Desktop\Game Macro\Manga.ahk")
                return
            }
        }
        else
        {
            if WinExist("Manga.ahk") {
                WinClose(userprofile "\OneDrive\Desktop\Game Macro\Manga.ahk ahk_class AutoHotkey")
                return
            }
        }
    }
}

RunOnce()
{
    Run(userprofile "\OneDrive\Code\Batch\winget_update.cmd", , "Hide")
    Run("cmd.exe /c uv self update && uv python install 313 -r", , "Hide")
}