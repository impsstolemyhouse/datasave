#NoEnv
#SingleInstance force
#Persistent
SetBatchLines, -1
SetWorkingDir, %A_ScriptDir%

; Ctrl+F1 sends the currently selected job URL(s) to the Good Jobs server.
; Config file:
;   manual-job-ingest.ini
;   [server]
;   endpoint=https://reviewbrothers.com/jobs/api/manual-jobs/ingest
;   public_key=mjk_...
;   private_key=mjs_...

gEndpoint := "https://reviewbrothers.com/jobs/api/manual-jobs/ingest"
gPublicKey := ""
gPrivateKey := ""

LoadConfig()
return

^F1::
SubmitSelectedJobLinks()
return

SubmitSelectedJobLinks()
{
    global gEndpoint, gPublicKey, gPrivateKey

    LoadConfig()
    selectedText := GetSelectedText()
    if (Trim(selectedText) = "")
    {
        ShowInfo("Select one or more job links first.")
        return
    }

    urlCount := CountHttpUrls(selectedText)
    if (urlCount < 1)
    {
        ShowInfo("The selection does not contain any http/https URL.")
        return
    }

    if (Trim(gPublicKey) = "" || Trim(gPrivateKey) = "")
    {
        message := "Missing manual job key pair."
        message .= "`n`nCreate a key in the Good Jobs admin page."
        message .= "`nThen add public_key=... and private_key=... to manual-job-ingest.ini."
        ShowWarning(message)
        return
    }

    escapedText := JsonEscape(selectedText)
    payload := "{""text"":""" . escapedText . """,""run_external"":true,""run_score"":true}"

    http := ComObjCreate("WinHttp.WinHttpRequest.5.1")
    try
    {
        http.Open("POST", gEndpoint, false)
        http.SetRequestHeader("Content-Type", "application/json")
        http.SetRequestHeader("X-Manual-Public-Key", gPublicKey)
        http.SetRequestHeader("X-Manual-Private-Key", gPrivateKey)
        http.Send(payload)
        status := http.Status
        response := http.ResponseText
    }
    catch e
    {
        errMsg := e.Message
        ShowError("Request failed:`n" . errMsg)
        return
    }

    if (status < 200 || status >= 300)
    {
        message := "Server returned HTTP " . status . ":"
        message .= "`n" . response
        ShowError(message)
        return
    }

    inserted := JsonNumber(response, "inserted_count")
    existing := JsonNumber(response, "existing_count")
    invalid := JsonNumber(response, "invalid_count")
    queued := JsonNumber(response, "queued_external_count")
    message := "Sent " . urlCount . " link(s)."
    message .= "`nNew: " . inserted
    message .= "`nExisting: " . existing
    message .= "`nInvalid: " . invalid
    message .= "`nQueued: " . queued
    ShowInfo(message)
}

LoadConfig()
{
    global gEndpoint, gPublicKey, gPrivateKey

    iniPath := A_ScriptDir . "\manual-job-ingest.ini"
    if FileExist(iniPath)
    {
        IniRead, endpoint, %iniPath%, server, endpoint,
        if (endpoint != "ERROR" && Trim(endpoint) != "")
            gEndpoint := Trim(endpoint)

        IniRead, publicKey, %iniPath%, server, public_key,
        if (publicKey != "ERROR" && Trim(publicKey) != "")
            gPublicKey := Trim(publicKey)

        IniRead, privateKey, %iniPath%, server, private_key,
        if (privateKey != "ERROR" && Trim(privateKey) != "")
            gPrivateKey := Trim(privateKey)
    }
}

GetSelectedText()
{
    savedClipboard := ClipboardAll
    Clipboard =
    Send, ^c
    ClipWait, 1
    selectedText := Clipboard
    Clipboard := savedClipboard
    VarSetCapacity(savedClipboard, 0)
    return selectedText
}

CountHttpUrls(text)
{
    count := 0
    pos := 1
    while (pos := RegExMatch(text, "i)https?://\S+", match, pos))
    {
        count += 1
        pos += StrLen(match)
    }
    return count
}

JsonEscape(value)
{
    value := StrReplace(value, Chr(92), Chr(92) . Chr(92))
    value := StrReplace(value, Chr(34), Chr(92) . Chr(34))
    value := StrReplace(value, "`r", "\r")
    value := StrReplace(value, "`n", "\n")
    value := StrReplace(value, "`t", "\t")
    return value
}

JsonNumber(text, key)
{
    pattern := """" . key . """:\s*(\d+)"
    if RegExMatch(text, pattern, match)
        return match1
    return 0
}

ShowInfo(message)
{
    TrayTip, Manual Job Ingest, %message%, 4, 1
}

ShowWarning(message)
{
    MsgBox, 48, Manual Job Ingest, %message%
}

ShowError(message)
{
    MsgBox, 16, Manual Job Ingest, %message%
}
