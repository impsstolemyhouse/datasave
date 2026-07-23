#NoEnv
#SingleInstance force
#Persistent
SetBatchLines, -1
SetWorkingDir, %A_ScriptDir%

global gProfiles := []
global gProfileMap := {}
global gSwitcherPath := A_ScriptFullPath
global gRepoRoot := A_ScriptDir
global gHiddenProfilesFile := gRepoRoot . "\.ahk-profile-switcher.ignore"
global gJdOutputFile := gRepoRoot . "\jobs\unanalyzed-jobs.txt"
global gJdMaxTabs := 100
global gJdPageLoadWaitMs := 250
global gJdClipboardWaitSec := 2

Menu, Tray, NoStandard
Menu, Tray, Click, 1

BuildTrayMenu()
SetTimer, RefreshRunningState, 3000
return

^F12::
CollectOpenTabJds()
return

SwitchProfile:
targetLabel := A_ThisMenuItem
targetPath := gProfileMap[targetLabel]

if (targetPath = "")
    return

CloseManagedProfiles(targetPath)
Sleep, 250

if !IsScriptRunning(targetPath)
    Run, "%A_AhkPath%" "%targetPath%"

Gosub, RefreshRunningState
TrayTip, AHK Profile Switcher, Active profile: %targetLabel%, 1, 1
return

RefreshProfiles:
BuildTrayMenu()
return

RefreshRunningState:
UpdateTrayChecks()
return

OpenRepoFolder:
Run, %gRepoRoot%
return

Noop:
return

ExitSwitcher:
ExitApp
return

BuildTrayMenu()
{
    global gProfiles
    global gProfileMap
    global gRepoRoot
    global gSwitcherPath
    hiddenRules := LoadHiddenProfileRules()

    gProfiles := []
    gProfileMap := {}

    Menu, Tray, DeleteAll

    Loop, Files, %gRepoRoot%\*.ahk, R
    {
        fullPath := A_LoopFileFullPath
        if (fullPath = gSwitcherPath)
            continue

        if IsProfileHidden(fullPath, hiddenRules)
            continue

        rawLabel := BuildProfileLabel(fullPath)
        label := EscapeMenuText(rawLabel)

        gProfiles.Push({ path: fullPath, label: label, rawLabel: rawLabel })
        gProfileMap[label] := fullPath
    }

    if (gProfiles.MaxIndex())
    {
        for _, profile in gProfiles
            Menu, Tray, Add, % profile.label, SwitchProfile
    }
    else
    {
        Menu, Tray, Add, No AHK Scripts Found, Noop
    }

    Menu, Tray, Add
    Menu, Tray, Add, Refresh List, RefreshProfiles
    Menu, Tray, Add, Open Repo Folder, OpenRepoFolder
    Menu, Tray, Add, Exit Switcher, ExitSwitcher

    Menu, Tray, Tip, AHK Profile Switcher
    UpdateTrayChecks()
}

LoadHiddenProfileRules()
{
    global gHiddenProfilesFile

    rules := { exact: {}, fileNames: {}, prefixes: [] }
    if !FileExist(gHiddenProfilesFile)
        return rules

    FileRead, content, %gHiddenProfilesFile%
    if (ErrorLevel)
        return rules

    Loop, Parse, content, `n, `r
    {
        rawRule := Trim(A_LoopField)
        if (rawRule = "")
            continue

        firstChar := SubStr(rawRule, 1, 1)
        if (firstChar = ";" || firstChar = "#")
            continue

        isPrefix := RegExMatch(rawRule, "[\\/]$")
        normalized := NormalizeProfileRule(rawRule)
        if (normalized = "")
            continue

        if (isPrefix)
        {
            if (SubStr(normalized, 0) != "\")
                normalized .= "\"
            rules.prefixes.Push(normalized)
            continue
        }

        if InStr(normalized, "\")
            rules.exact[normalized] := true
        else
            rules.fileNames[normalized] := true
    }

    return rules
}

IsProfileHidden(fullPath, hiddenRules)
{
    relPath := NormalizeProfileRule(GetRelativeProfilePath(fullPath))
    SplitPath, relPath, fileName
    fileName := ToLowerText(fileName)

    if (hiddenRules.exact.HasKey(relPath))
        return true

    if (hiddenRules.fileNames.HasKey(fileName))
        return true

    for _, prefix in hiddenRules.prefixes
    {
        if (SubStr(relPath, 1, StrLen(prefix)) = prefix)
            return true
    }

    return false
}

GetRelativeProfilePath(fullPath)
{
    global gRepoRoot

    rootPrefix := gRepoRoot . "\"
    relPath := fullPath
    if (SubStr(fullPath, 1, StrLen(rootPrefix)) = rootPrefix)
        relPath := SubStr(fullPath, StrLen(rootPrefix) + 1)

    return StrReplace(relPath, "/", "\")
}

NormalizeProfileRule(rule)
{
    rule := Trim(rule)
    if (rule = "")
        return ""

    rule := StrReplace(rule, "/", "\")
    rule := RegExReplace(rule, "\\+", "\")
    if (SubStr(rule, 1, 2) = ".\")
        rule := SubStr(rule, 3)

    return ToLowerText(rule)
}

ToLowerText(text)
{
    StringLower, text, text
    return text
}

BuildProfileLabel(fullPath)
{
    relPath := GetRelativeProfilePath(fullPath)

    SplitPath, relPath, fileName, dirPath
    if (dirPath = "")
        return RegExReplace(fileName, "i)\.ahk$")

    return StrReplace(dirPath, "\", " / ")
}

EscapeMenuText(text)
{
    return StrReplace(text, "&", "&&")
}

UpdateTrayChecks()
{
    global gProfiles

    runningMap := GetRunningProfiles()
    activeLabel := ""

    for _, profile in gProfiles
    {
        if (runningMap.HasKey(profile.path))
        {
            Menu, Tray, Check, % profile.label
            if (activeLabel = "")
                activeLabel := profile.rawLabel
        }
        else
        {
            Menu, Tray, UnCheck, % profile.label
        }
    }

    tip := "AHK Profile Switcher"
    if (activeLabel != "")
        tip .= "`nActive: " . activeLabel
    else
        tip .= "`nActive: none"

    Menu, Tray, Tip, %tip%
}

GetRunningProfiles()
{
    global gProfiles

    running := {}
    service := ComObjGet("winmgmts:")
    query := "Select ProcessId, CommandLine, Name from Win32_Process where Name like 'AutoHotkey%'"

    for process in service.ExecQuery(query)
    {
        cmd := process.CommandLine
        if (cmd = "")
            continue

        for _, profile in gProfiles
        {
            if InStr(cmd, profile.path, false)
            {
                running[profile.path] := process.ProcessId
                break
            }
        }
    }

    return running
}

IsScriptRunning(scriptPath)
{
    service := ComObjGet("winmgmts:")
    query := "Select ProcessId, CommandLine, Name from Win32_Process where Name like 'AutoHotkey%'"

    for process in service.ExecQuery(query)
    {
        cmd := process.CommandLine
        if (cmd = "")
            continue

        if InStr(cmd, scriptPath, false)
            return true
    }

    return false
}

CloseManagedProfiles(exceptPath := "")
{
    global gProfiles

    service := ComObjGet("winmgmts:")
    query := "Select ProcessId, CommandLine, Name from Win32_Process where Name like 'AutoHotkey%'"

    for process in service.ExecQuery(query)
    {
        cmd := process.CommandLine
        if (cmd = "")
            continue

        for _, profile in gProfiles
        {
            if !InStr(cmd, profile.path, false)
                continue

            if (profile.path = exceptPath)
                break

            pid := process.ProcessId
            Process, Close, %pid%
            break
        }
    }
}

CollectOpenTabJds()
{
    global gJdOutputFile
    global gJdMaxTabs
    global gJdPageLoadWaitMs

    originalClipboard := ClipboardAll
    collected := 0
    firstUrl := GetCurrentBrowserUrl()

    if (firstUrl = "")
    {
        TrayTip, JD Collector, Could not read the current tab URL., 4, 17
        Clipboard := originalClipboard
        return
    }

    Loop, %gJdMaxTabs%
    {
        currentUrl := GetCurrentBrowserUrl()
        if (currentUrl = "")
            break

        pageText := GetCurrentBrowserPageText()
        AppendOpenTabJobDescription(currentUrl, pageText)
        collected++

        Send, ^{Tab}
        Sleep, %gJdPageLoadWaitMs%

        nextUrl := GetCurrentBrowserUrl()
        if (nextUrl = "" || nextUrl = firstUrl)
            break
    }

    Clipboard := originalClipboard
    TrayTip, JD Collector, Saved %collected% tab(s) to %gJdOutputFile%., 4, 1
}

GetCurrentBrowserUrl()
{
    global gJdClipboardWaitSec

    Clipboard :=
    Send, ^l
    Sleep, 80
    Send, ^c
    ClipWait, %gJdClipboardWaitSec%

    url := Trim(Clipboard)
    Send, {Esc}
    Sleep, 80

    if RegExMatch(url, "i)^(https?|file)://")
        return url

    return ""
}

GetCurrentBrowserPageText()
{
    global gJdClipboardWaitSec

    Clipboard :=
    Send, {Esc}
    Sleep, 80
    Send, ^a
    Sleep, 120
    Send, ^c
    ClipWait, %gJdClipboardWaitSec%

    return Clipboard
}

AppendOpenTabJobDescription(url, pageText)
{
    global gJdOutputFile

    SplitPath, gJdOutputFile,, outputDir
    if !FileExist(outputDir)
        FileCreateDir, %outputDir%

    FormatTime, timestamp,, yyyy-MM-dd HH:mm:ss

    pageText := NormalizeJdLineEndings(pageText)

    FileAppend,
(

================================================================================
Captured: %timestamp%
URL: %url%
================================================================================

%pageText%

), %gJdOutputFile%, UTF-8
}

NormalizeJdLineEndings(text)
{
    text := StrReplace(text, "`r`n", "`n")
    text := StrReplace(text, "`r", "`n")
    text := StrReplace(text, "`n", "`r`n")
    return Trim(text)
}
