#cs ----------------------------------------------------------------------------
 Author:         Pedro Iniguez Huerta
 Description:
	Synchronize files changes between two USBs drives and update each other USB with the latest changes
#ce ----------------------------------------------------------------------------

#include <AutoItConstants.au3>
#include <MsgBoxConstants.au3>
#include <Array.au3>
#include <File.au3>
#include <FileConstants.au3>
#include <Date.au3>
#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <GuiScrollBars.au3>
#include <ColorConstants.au3>

Global $backupFile = "usbsync.log"
Global $debugMode = False
Global $filesCounter = 0
Global $log = ""
Global $title = "USB Synchronizer"
Global $hGUI
Global $closeId
Global $stopId
Global $listId
Global $aborting = False
Global $closing = False
Global $stopping = False
Global $aboutId = False


Func LogToFile($FileName, $Value)
  $FileHandle = FileOpen($FileName, 1) ; 1 = append mode

  If $FileHandle <> -1 Then
	Local $tCur = _Date_Time_GetSystemTime()
	Local $text = _Date_Time_SystemTimeToDateTimeStr($tCur)  & "> " & $Value & @CRLF
    FileWrite($FileHandle, $text)
    GUICtrlSetData(-1, $text)
	$log = $log & $text
  EndIf

  FileClose($FileHandle)
EndFunc

Func getUsbDrives(ByRef $usb_list)

	Local $aArray = DriveGetDrive($DT_ALL)
	Local $first_usb = True
	Local $count = 0

	For $i = 1 To $aArray[0]
		Local $drive = StringUpper($aArray[$i])
		Local $type = DriveGetType($drive)

		If $type = "Removable" Then
			$usb_list[$count] = $drive
			$count = $count + 1
			if $count > 2 Then
				Return $count
			EndIf
		EndIf
	Next

	Return $count
EndFunc

Func IsDir($sFilePath)
    Return StringInStr(FileGetAttrib($sFilePath), "D") > 0
EndFunc

Func FileCompare($source_file, $target_file)
    Local $iDate1 = StringRegExpReplace(FileGetTime($source_file, $FT_MODIFIED, 1), '(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})', '\1/\2/\3 \4:\5:\6')
    Local $iDate2 = StringRegExpReplace(FileGetTime($target_file, $FT_MODIFIED, 1), '(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})', '\1/\2/\3 \4:\5:\6')
    Local $iDateDiff = _DateDiff('s', $iDate2, $iDate1)
    If $iDateDiff > 0 Then Return -1
    If $iDateDiff = 0 Then Return 0
    Return 1
EndFunc

Func ByteSuffix($iBytes)
    Local $iIndex = 0, $aArray = [' bytes', ' KB', ' MB', ' GB', ' TB', ' PB', ' EB', ' ZB', ' YB']
    While $iBytes > 1023
        $iIndex += 1
        $iBytes /= 1024
    WEnd
    Return Round($iBytes) & $aArray[$iIndex]
EndFunc

Func BackupFile($sFileName,$tFileName,$mode)
	$sFileSize = FileGetSize($sFileName)
	$tFileSize = FileGetSize($tFileName)
	$filesCounter = $filesCounter + 1
	Local $msg = "[UPDATE] from " & $sFileName & "(" & ByteSuffix($sFileSize) & ")" & " to " & $tFileName & "(" & ByteSuffix($tFileSize) & ")"
	if $mode = $FC_CREATEPATH Then
		$msg = "[CREATE] from " & $sFileName & "(" & ByteSuffix($sFileSize) & ")" & " to " & $tFileName
	EndIf
	LogToFile($backupFile,$msg)
	FileCopy($sFileName,$tFileName,$mode)
	if $debugMode Then
		$iResult = MsgBox(BitOR($MB_SYSTEMMODAL, $MB_OKCANCEL), "Debug Info", $msg,1)
	EndIf
EndFunc

Func SyncDirectory($source_dir,$target_dir,$recursive)
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	; Get the list of files in each USB
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	Local $USB1_list = _FileListToArray($source_dir, "*")
	Local $USB2_list = _FileListToArray($target_dir, "*")

	If $USB1_list == "." or $USB1_list = ".." or $USB1_list == ""  or $USB2_list == "." or $USB2_list = ".." or $USB2_list == "" Then
		; don't log the file
	Else
		LogToFile($backupFile,"dir1 = " & $USB1_list & ". dir 2 = " & $USB2_list)
	EndIf

	For $file in $USB1_list
		Local $sFileName = $source_dir & "\" & $file
		Local $tFileName = $target_dir & "\" & $file

		If $sFileName == "." or $sFileName = ".." or $sFileName == ""  or $tFileName == "." or $tFileName = ".." or $tFileName == "" Then
			ContinueLoop
		EndIf

		; ignore special files and invalid files
		if StringInStr(FileGetAttrib($sFileName), "S") OR StringInStr(FileGetAttrib($sFileName), "H") Or FileExists($sFileName) == 0 Then
			ContinueLoop
		EndIf

		; If there is no more file matching the search.
		If @error Then ExitLoop
		; If user closing window
        Switch GUIGetMsg()
			Case $closeId
				$aborting = True
				$closing = True
			Case $GUI_EVENT_CLOSE
				$aborting = True
				$closing = True
			Case $stopId
				$aborting = True
				$stopping = True
			Case $aboutId
				MsgBox($MB_SYSTEMMODAL, "About", "USBSynchronizer.exe. Author: Pedro Iniguez Huerta",2)
		EndSwitch

		; stop copying if aborted
		if $aborting Then
			return True
		EndIf

		if IsDir($sFileName) Then
			if  $recursive  Then
				; synchronize files from usb 1 to usb 2
				SyncDirectory($sFileName,$tFileName,$recursive)

				; synchronize files from usb 2 to usb 1
				SyncDirectory($tFileName,$sFileName,$recursive)
			EndIf
		Else
			; if file doesn't exists in target directory, just copy it
			if FileExists($tFileName) == 0 Then
				BackupFile($sFileName,$tFileName,$FC_CREATEPATH)
			Else
				Local $diff = FileCompare($sFileName, $tFileName)
				; file exists in both USBs, update both files on the USBs to contain the latest modified file version
				if $diff < 0 Then
					BackupFile($sFileName,$tFileName,$FC_OVERWRITE)
				ElseIf $diff > 0 Then
					BackupFile($tFileName,$sFileName,$FC_OVERWRITE)
				EndIf
			EndIf
		EndIf
	Next

    Return False
EndFunc

Func ShowResults($log)
	GUICtrlDelete($stopId)

	if $closing Then
		GUICtrlSetBkColor($listId, $COLOR_GRAY)
		GUICtrlDelete($closeId)
		Sleep(5000)
	Else
		GUICtrlSetBkColor($listId, $COLOR_GRAY)
		; Loop until the user exits.
		While 1
			Switch GUIGetMsg()
				Case $GUI_EVENT_CLOSE
					ExitLoop
				Case $closeId
					ExitLoop
				Case $aboutId
					MsgBox($MB_SYSTEMMODAL, "About", "USBSynchronizer.exe. Author: Pedro Iniguez Huerta",2)
			EndSwitch
		WEnd
	EndIf

    ; Delete the previous GUI and all controls.
    GUIDelete($hGUI)
EndFunc

Func Done($rc, $msg)
	if $rc == 1 Then
		LogToFile($backupFile,"[error] " & $msg)
	Else
		LogToFile($backupFile,$msg)
		LogToFile($backupFile,$filesCounter & " files where synchronized")
	EndIf

	LogToFile($backupFile,"======================[ USB synchronization Finished ] ==============================")
	;MsgBox($MB_SYSTEMMODAL, "Information", "USB Synchronization done",2)
	ShowResults($log)
	exit($rc)
EndFunc

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Main
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
$hGUI = GUICreate($title,800,500)
$stopId = GUICtrlCreateButton("Stop", 1, 478)
$closeId = GUICtrlCreateButton("Close", 50, 478)
$aboutId = GUICtrlCreateButton("About", 100, 478)
$listId = GUICtrlCreateList("", 1, 1,800,480)
;GUICtrlSetLimit(-1, 3) ; to limit horizontal scrolling

GUISetState(@SW_SHOW)

Local $usb_list[30] = ["","","","","","","","","","","","","","","","","","","","","","","","","","",""]
Local $count = 0

Local $count = getUsbDrives($usb_list)

LogToFile($backupFile,"======================[ Starting USB synchronization ] ==============================")

if $count < 2  Then
	Done(1,"Please insert the two USBs to synchronize")
ElseIf $count > 2 Then
	Done(1,"More than 2 USBs detected. Please remove all other USBs")
Else
	LogToFile($backupFile,"USB Drive 1 found = " & $usb_list[0])
	LogToFile($backupFile,"USB Drive 2 found = " & $usb_list[1])
EndIf

Local $recursive = True

;Check if need to disable recursive search
if $cmdline[0] == 0 Then
	$recursive = True
Elseif $cmdline[0] >= 1 Then
	if StringCompare ($cmdline[1],"0") == 0 Then
		MsgBox($MB_SYSTEMMODAL, "", "Recursive subdirectory synchronization disabled",2)
		$recursive = False
	EndIf
EndIf

Sleep(1000)

; synchronize files from usb 1 to usb 2
SyncDirectory($usb_list[0],$usb_list[1],$recursive)

; synchronize files from usb 2 to usb 1
if $aborting == False Then
	SyncDirectory($usb_list[1],$usb_list[0],$recursive)
EndIf

if $aborting and $closing Then
	LogToFile($backupFile,"******* SYNCHRONIZATION ABORTED: (autoclosing) ******************")
Elseif $stopping Then
	LogToFile($backupFile,"*************** SYNCHRONIZATION STOPPED ************************")
EndIf


Done(0,"USB SYNCHRONIZATION COMPLETED")