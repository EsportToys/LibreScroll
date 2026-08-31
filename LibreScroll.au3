#NoTrayIcon
Const $MAGIC_WORD = 0x53534150
Const $user32dll = DllOpen("user32.dll")
Const $kernel32dll = DllOpen("kernel32.dll")
Const $qpf = DllCall($kernel32dll, "bool", "QueryPerformanceFrequency", "int64*", Null)[1]


If $CmdLine[0] == 7 Then
    WorkerMain($CmdLine)
Else
    DialogMain()
EndIf


Func DialogMain()
    DllCall($kernel32dll, "handle", "CreateMutexW", "struct*", 0, "bool", 1, "wstr", "LibreScroll")
    If 183 == DllCall($kernel32dll, "dword", "GetLastError")[0] Then Exit

    Opt("TrayIconHide", 0)
    Opt("TrayAutoPause", 0)
    Opt("TrayOnEventMode", 1)
    Opt("TrayMenuMode", 3)

    TrayItemSetOnEvent( TrayCreateItem("About LibreScroll") , DLG_Info   )
    TrayItemSetOnEvent( TrayCreateItem("Options")           , DLG_Unhide )
    TrayItemSetOnEvent( TrayCreateItem("Quit")              , DLG_Quit   )

    TraySetOnEvent( -7  , DLG_Unhide    )
    TraySetOnEvent( -11 , DLG_UpdateTip )
    TraySetIcon( "main.cpl" , 608 )
    TraySetClick(8)

    Global $dlg_hwnd = GUICreate( "LibreScroll options" , 215 , 185 , Default , Default , 0x00C80000 )
    GUISetIcon( "main.cpl" , 608 )

    GUICtrlCreateLabel( "Friction"       , 5 ,   5 , 100 , 20 , 0x0201 )
    GUICtrlCreateLabel( "Y-Sensitivity"  , 5 ,  30 , 100 , 20 , 0x0201 )
    GUICtrlCreateLabel( "X-Sensitivity"  , 5 ,  55 , 100 , 20 , 0x0201 )
    GUICtrlCreateLabel( "Minimum Y Step" , 5 ,  80 , 100 , 20 , 0x0201 )
    GUICtrlCreateLabel( "Minimum X Step" , 5 , 105 , 100 , 20 , 0x0201 )

    Local $decay = Number( IniRead("options.ini", "LibreScroll", "decay", 3)      )
    Local $sensY = Number( IniRead("options.ini", "LibreScroll", "sensY", 18)     )
    Local $sensX = Number( IniRead("options.ini", "LibreScroll", "sensX", 0)      )
    Local $stepY = Round(  IniRead("options.ini", "LibreScroll", "stepY", 1)      )
    Local $stepX = Round(  IniRead("options.ini", "LibreScroll", "stepX", 1)      )
    Local $think = Number( IniRead("options.ini", "LibreScroll", "think", 0) == 1 )

    Local $dlg_decay = GUICtrlCreateInput( $decay , 110 ,   5 , 100 , 20 )
    Local $dlg_sensY = GUICtrlCreateInput( $sensY , 110 ,  30 , 100 , 20 )
    Local $dlg_sensX = GUICtrlCreateInput( $sensX , 110 ,  55 , 100 , 20 )
    Local $dlg_stepY = GUICtrlCreateInput( $stepY , 110 ,  80 , 100 , 20 )
    Local $dlg_stepX = GUICtrlCreateInput( $stepX , 110 , 105 , 100 , 20 )
    Local $dlg_think = GUICtrlCreateCheckbox( "ThinkPad mode" , 110 , 130 )
                       GUICtrlSetState( $dlg_think , $think ? 1 : 4 )
    Local $dlg_pause = GUICtrlCreateButton( "Pause" ,   5 , 155 , 100 )
    Local $dlg_apply = GUICtrlCreateButton( "Apply" , 110 , 155 , 100 )

    Global $dlg_worker_handle = Null
    If Not DLG_SpawnWorker($sensX, $sensY, $decay, $stepX, $stepY, $think) Then
        GUICtrlSetData($dlg_pause, "Unpause")
    EndIf
    OnAutoItExitRegister(DLG_KillWorker)

    While 1
        Local $id = GUIGetMsg()
        Switch $id
            Case -3
                GUISetState(@SW_HIDE, $dlg_hwnd)
            Case $dlg_decay
                Local $value = Number(GUICtrlRead($id))
                If $value < 1 Then $value = 1
                GUICtrlSetData($id, $value)
            Case $dlg_sensX, $dlg_sensY
                GUICtrlSetData($id, Number(GUICtrlRead($id)))
            Case $dlg_stepX, $dlg_stepY
                Local $value = Number(GUICtrlRead($id))
                If $value < 1 Then
                    GUICtrlSetData($id, 1)
                ElseIf $value > 120 Then
                    GUICtrlSetData($id, 120)
                Else
                    GUICtrlSetData($id, Round($value))
                EndIf
            Case $dlg_think
            Case $dlg_apply, $dlg_pause
                DLG_KillWorker()
                If $dlg_pause == $id And "Pause" == GUICtrlRead($dlg_pause) Then
                    GUICtrlSetData($dlg_pause, "Unpause")
                Else
                    $sensX = Number( GUICtrlRead($dlg_sensX)      )
                    $sensY = Number( GUICtrlRead($dlg_sensY)      )
                    $decay = Number( GUICtrlRead($dlg_decay)      )
                    $stepX = Round(  GUICtrlRead($dlg_stepX)      )
                    $stepY = Round(  GUICtrlRead($dlg_stepY)      )
                    $think = Number( GUICtrlRead($dlg_think) == 1 )
                    IniWrite("options.ini", "LibreScroll", "sensX", $sensX)
                    IniWrite("options.ini", "LibreScroll", "sensY", $sensY)
                    IniWrite("options.ini", "LibreScroll", "decay", $decay)
                    IniWrite("options.ini", "LibreScroll", "stepX", $stepX)
                    IniWrite("options.ini", "LibreScroll", "stepY", $stepY)
                    IniWrite("options.ini", "LibreScroll", "think", $think)
                    If DLG_SpawnWorker($sensX, $sensY, $decay, $stepX, $stepY, $think) Then
                        GUICtrlSetData($dlg_pause, "Pause")
                    EndIf
                EndIf
        EndSwitch
    WEnd
EndFunc

Func DLG_Unhide()
    GUISetState(@SW_SHOW, $dlg_hwnd)
    GUISetState(@SW_RESTORE, $dlg_hwnd)
EndFunc

Func DLG_UpdateTip()
    TraySetToolTip("LibreScroll - " & ( ProcessExists($dlg_worker_handle) ? "Active" : "Inactive") )
EndFunc

Func DLG_Info()
    MsgBox(0, "About LibreScroll v1.4-autoit", "Visit https://github.com/EsportToys/LibreScroll for more info.")
EndFunc

Func DLG_Quit()
    Exit
EndFunc

Func DLG_KillWorker()
    If $dlg_worker_handle Then
        If ProcessExists($dlg_worker_handle) Then
            ProcessClose($dlg_worker_handle)
        EndIf
        $dlg_worker_handle = Null
    EndIf
EndFunc

Func DLG_SpawnWorker($sensX, $sensY, $decay, $stepX, $stepY, $think)
    If $dlg_worker_handle Then Return
    Const $arg = $sensX & " " & $sensY & " " & $decay & " " & $stepX & " " & $stepY & " " & $think
    $dlg_worker_handle = Run(@AutoItExe & " " & ( @Compiled ? "" : @ScriptFullPath ) & " " & @AutoItPID & " " & $arg)
    If ProcessExists($dlg_worker_handle) Then 
        ProcessSetPriority( $dlg_worker_handle, 3 )
        Return True
    Else
        Return False
    EndIf
EndFunc

Func WorkerMain($args)
    If Not ProcessExists($args[1]) Then Return

    Global Const $wkr_sens_x = Number($args[2])
    Global Const $wkr_sens_y = Number($args[3])
    Global Const $wkr_damp = ($args[4] > 0) ? $args[4] : 3
    Global Const $wkr_thresh_x = ($args[5] > 1) ? $args[5] : 1
    Global Const $wkr_thresh_y = ($args[6] > 1) ? $args[6] : 1
    Global Const $wkr_think = Number($args[7]) ? True : False

    Global Const $wkr_timer_fn = DllCallbackGetPtr(DllCallbackRegister("WKR_TimerProc", "none", "hwnd;uint;uint_ptr;dword"))

    Global $wkr_clipRect = DllStructCreate("long x1;long y1;long x2;long y2;");
    Global $wkr_scrollVel = [0, 0]
    Global $wkr_scrollAccu = [0, 0]
    Global $wkr_trigger_isDown = False
    Global $wkr_scroll_pending = False
    Global $wkr_last_send_time = 0

    DllCall($user32dll, "bool", "SetProcessDPIAware")

    Local $raw = DllStructCreate("ushort page; ushort usage; dword flags; hwnd target")
    Const $rawSize = DllStructGetSize($raw)
    $raw.page = 1
    $raw.usage = 2
    $raw.flags = 256
    $raw.target = GUICreate("")
    DllCall($user32dll, "bool", "RegisterRawInputDevices", "struct*", $raw, "uint", 1, "uint", $rawSize)
    GUIRegisterMsg(0x00FF, WKR_Rawinput)

    Const $hookdll = DllCall($kernel32dll, "handle", "LoadLibraryW", "wstr", @ScriptDir & "\hook.dll")
    If @error Then
        MsgBox(0, "LoadLibrary error", @error)
    ElseIf $hookdll[0] == Null Then
        MsgBox(0, "LoadLibrary error", "hook.dll not found")
        Exit
    EndIf

    Const $hookptr = DllCall($kernel32dll, "ptr", "GetProcAddress", "handle", $hookdll[0], "str", "hookMain")
    If @error Then 
        MsgBox(0, "GetProcAddress error", @error)
        Exit
    ElseIf $hookptr[0] == Null Then
        MsgBox(0, "GetProcAddress error", "proc not found")
        Exit
    EndIf

    Const $hookhandle = DllCall($kernel32dll, "handle", "CreateThread", _
        "struct*", Null, _
        "ulong_ptr", 0, _
        "ptr", $hookptr[0], _
        "handle", Null, _
        "dword", 0, _
        "dword*", Null _
    )
    If @error Then
        MsgBox(0, "CreateThread error", @error)
        Exit
    ElseIf $hookhandle == Null Then
        MsgBox(0, "CreateThread error", "thread not created")
        Exit
    EndIf

    DllCall($kernel32dll, "bool", "SetThreadPriority", "handle", $hookhandle[0], "int", 15)

    Do 
    Until -3 == GUIGetMsg()
EndFunc

Func WKR_Rawinput($h, $m, $w, $l)
    Static $HEAD = "struct;dword Type;dword Size;handle hDevice;wparam wParam;endstruct;"
    Static $MOU = $HEAD & "ushort Flags;ushort Alignment;ushort ButtonFlags;short ButtonData;ulong RawButtons;long LastX;long LastY;ulong ExtraInformation;"
    Static $raw = DllStructCreate($MOU)
    Static $size = DllStructGetSize($raw)
    Static $headsize = DllStructGetSize(DllStructCreate($HEAD))

    Const $qpc = DllCall($kernel32dll, "bool", "QueryPerformanceCounter", "int64*", Null)[1]

    DllCall($user32dll, "uint", "GetRawInputData", "handle", $l, "uint", 0x10000003, "struct*", $raw, "uint*", $size, "uint", $headsize)

    If $raw.hDevice Then
        If $raw.ButtonFlags Then
            If BitAnd(32, $raw.ButtonFlags) Then
                If $wkr_scroll_pending Then
                    SendMB3()
                EndIf
                $wkr_trigger_isDown = False
                $wkr_scroll_pending = False
                $wkr_scrollVel[0] = 0
                $wkr_scrollVel[1] = 0
                DllCall($user32dll, "bool", "ClipCursor", "struct*", Null)
                DllCall($user32dll, "bool", "KillTimer", "hwnd", $h, "uint_ptr", 0x420)
            ElseIf BitAnd(16, $raw.ButtonFlags) Then
                $wkr_scrollAccu[0] = 0
                $wkr_scrollAccu[1] = 0
                $wkr_scrollVel[0] = 0
                $wkr_scrollVel[1] = 0
                $wkr_trigger_isDown = True
                $wkr_scroll_pending = True
                $wkr_last_send_time = $qpc
                DllCall($user32dll, "bool", "GetCursorPos", "struct*", $wkr_clipRect)
                $wkr_clipRect.x2 = $wkr_clipRect.x1 + 1
                $wkr_clipRect.y2 = $wkr_clipRect.y1 + 1
                DllCall($user32dll, "bool", "ClipCursor", "struct*", $wkr_clipRect)
                DllCall($user32dll, "uint_ptr", "SetTimer", "hwnd", $h, "uint_ptr", 0x420, "uint", 0, "ptr", $wkr_timer_fn)
            EndIf
        ElseIf $wkr_trigger_isDown Then
            $wkr_scrollAccu[0] += $raw.LastX
            $wkr_scrollAccu[1] += $raw.LastY
        EndIf
    EndIf

    If ($qpc - $wkr_last_send_time) * 1000 > $qpf * 4 Then
        WKR_TimerProc(Null, 0, 0, 0)
    EndIf

    Return 0
EndFunc

Func WKR_TimerProc($hWnd, $uMsg, $idEvent, $sysTick)
    If Not $wkr_trigger_isDown Then Return

    Static $rect = DllStructCreate("long x1; long y1; long x2; long y2;");
    Const $qpc = DllCall($kernel32dll, "bool", "QueryPerformanceCounter", "int64*", Null)[1]

    If Not $uMsg == 0x0113 Then
        DllCall($user32dll, "bool", "GetClipCursor", "struct*", $rect)
        If $rect.x1 <> $wkr_clipRect.x1 or $rect.x2 <> $wkr_clipRect.x2 or $rect.y1 <> $wkr_clipRect.y1 or $rect.y2 <> $wkr_clipRect.y2 Then
            DllCall($user32dll, "bool", "ClipCursor", "struct*", $wkr_clipRect)
        EndIf
    EndIf

    Const $dx = $wkr_scrollAccu[0]
    Const $dy = $wkr_scrollAccu[1]
    $wkr_scrollVel[0] += $dx * $wkr_sens_x
    $wkr_scrollVel[1] += $dy * $wkr_sens_y
    $wkr_scrollAccu[0] -= $dx
    $wkr_scrollAccu[1] -= $dy

    Const $dt = ($qpc - $wkr_last_send_time) / $qpf
    Const $mu = $wkr_damp
    Const $f0 = 0 == $mu ? 1.0 : Exp(-$dt * $mu)
    Const $f1 = 0 == $mu ? $dt : (1 - $f0) / $mu

    WKR_FlushScroll( $f1 * $wkr_scrollVel[0] , -$f1 * $wkr_scrollVel[1] )

    $wkr_scrollVel[0] *= $f0
    $wkr_scrollVel[1] *= $f0

    If $wkr_scrollVel[0]*$wkr_scrollVel[0] + $wkr_scrollVel[1]*$wkr_scrollVel[1] < 0.25 Then 
        $wkr_scrollVel[0] = 0 
        $wkr_scrollVel[1] = 0
    EndIf

    $wkr_last_send_time = $qpc
EndFunc

Func WKR_FlushScroll($dx, $dy)
    Static $residue = [0, 0]

    $residue[0] += $dx
    $residue[1] += $dy

    Const $multipleX = Int($residue[0] / $wkr_thresh_x) 
    Const $multipleY = Int($residue[1] / $wkr_thresh_y)

    Local $sendX = 0 
    If $multipleX <> 0 Then
        $sendX = $multipleX * $wkr_thresh_x
        $residue[0] -= $sendX
    EndIf

    Local $sendY = 0
    If $multipleY <> 0 Then
        $sendY = $multipleY * $wkr_thresh_y
        $residue[1] -= $sendY
    EndIf

    If $wkr_think Then 
        If Abs($sendX) > Abs($sendY) Then 
            $sendY = 0
            $residue[1] = 0
        Else 
            $sendX = 0
            $residue[0] = 0
        EndIf
    EndIf

    If $sendX <> 0 or $sendY <> 0 Then 
        If $wkr_scroll_pending Then 
            $wkr_scroll_pending = False
        EndIf
        ScrollMouseXY($sendX, $sendY)
    EndIf
EndFunc

Func ScrollMouseXY($dx, $dy)
    Static $size, $ptr, $x, $y
    Static $buf = NewScrollXY($size, $ptr, $x, $y)

    Const $count = ( $dx ? 1 : 0 ) + ( $dy ? 1 : 0 )
    Const $addr = $dy ? $ptr : $ptr + $size

    $y.data = $dy
    $x.data = $dx

    DllCall($user32dll, "uint", "SendInput", "uint", $count, "ptr", $addr, "int", $size)
EndFunc

Func NewScrollXY(ByRef $size, ByRef $ptr, ByRef $x, ByRef $y)
    Const $tag = "dword type;struct;long;long;dword data;dword flag;dword;ulong_ptr info;endstruct;"
    $size = DllStructGetSize(DllStructCreate($tag))

    Const $buf = DllStructCreate("byte[" & $size * 2 & "]")
    $ptr = DllStructGetPtr($buf)

    $y = DllStructCreate($tag, $ptr)
    $y.type = 0
    $y.flag = 0x0800

    $x = DllStructCreate($tag, $ptr + $size)
    $x.type = 0
    $x.flag = 0x1000

    Return $buf
EndFunc

Func SendMB3()
    Static $size, $ptr
    Static $buf = NewMB3($size, $ptr)
    DllCall($user32dll, "uint", "SendInput", "uint", 2, "ptr", $ptr, "int", $size)
EndFunc

Func NewMB3(ByRef $size, ByRef $ptr)
    Const $tag = "dword type;struct;long;long;dword data;dword flag;dword;ulong_ptr info;endstruct;"
    $size = DllStructGetSize(DllStructCreate($tag))

    Const $buf = DllStructCreate("byte[" & $size * 2 & "]")
    $ptr = DllStructGetPtr($buf)

    Local $buttonDn = DllStructCreate($tag, $ptr)
    $buttonDn.type = 0
    $buttonDn.flag = 0x0020
    $buttonDn.info = $MAGIC_WORD

    Local $buttonUp = DllStructCreate($tag, $ptr + $size)
    $buttonUp.type = 0
    $buttonUp.flag = 0x0040
    $buttonUp.info = $MAGIC_WORD

    Return $buf
EndFunc