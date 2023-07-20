#NoTrayIcon

If $CmdLine[0]==7 Then
   Child($CmdLine)
Else
   If IsAdmin() Then Sleep(100)
   If _Singleton('LibreScroll',0) Then Parent()
EndIf

Func Parent()
     Opt("TrayIconHide", 0)
     Opt('TrayAutoPause',0)
     Opt('TrayOnEventMode',1)
     Opt('TrayMenuMode',1+2)
     If Not IsAdmin() Then TrayItemSetOnEvent(TrayCreateItem('Restart as admin'),Elevate)
     TrayItemSetOnEvent(TrayCreateItem('About LibreScroll'),Info)
     TrayItemSetOnEvent(TrayCreateItem('Options'),Unhide)
     TrayItemSetOnEvent(TrayCreateItem('Quit'),Quit)
     Global $g_hWnd = GUICreate('LibreScroll options',215,185,Default,Default,0x00C80000)
     GUISetIcon('main.cpl',608)
     TraySetOnEvent(-7,Unhide)
     TraySetOnEvent(-11,UpdateTip)
     TraySetClick(8)
     TraySetIcon('main.cpl',608)
     GUICtrlCreateLabel('Friction'      ,5,  5,100,20,0x0201)
     GUICtrlCreateLabel('Y-Sensitivity' ,5, 30,100,20,0x0201)
     GUICtrlCreateLabel('X-Sensitivity' ,5, 55,100,20,0x0201)
     GUICtrlCreateLabel('Minimum Y Step',5, 80,100,20,0x0201)
     GUICtrlCreateLabel('Minimum X Step',5,105,100,20,0x0201)
     Local $decay = GUICtrlCreateInput(IniRead('options.ini','LibreScroll','decay',3) , 110 ,  5 , 100 , 20)
     Local $sensY = GUICtrlCreateInput(IniRead('options.ini','LibreScroll','sensY',9) , 110 , 30 , 100 , 20)
     Local $sensX = GUICtrlCreateInput(IniRead('options.ini','LibreScroll','sensX',0) , 110 , 55 , 100 , 20)
     Local $stepY = GUICtrlCreateInput(IniRead('options.ini','LibreScroll','stepY',1) , 110 , 80 , 100 , 20)
     Local $stepX = GUICtrlCreateInput(IniRead('options.ini','LibreScroll','stepX',1) , 110 ,105 , 100 , 20)
     Local $flick = GUICtrlCreateCheckbox('Flick mode',110,130)
                    GUICtrlSetState( $flick , 1=IniRead('options.ini','LibreScroll','flick',0) ? 1 : 4 )
     Local $pause = GUICtrlCreateButton('Pause',  5,155,100)
     Local $apply = GUICtrlCreateButton('Apply',110,155,100)
     GUICtrlSetTip($decay,'How quickly the momentum decays, by applying a drag force that is proportional to speed.')
     GUICtrlSetTip($sensY,'Vertical scrolling sensitivity. Set a negative number for reverse scrolling.')
     GUICtrlSetTip($sensX,'Horizontal scrolling sensitivity. Set a negative number for reverse scrolling.')
     GUICtrlSetTip($stepY,'How many scroll counts to accumulate before sending.' & @CRLF & 'A regular coarse scroll step is 120.')
     GUICtrlSetTip($stepX,'How many scroll counts to accumulate before sending.' & @CRLF & 'A regular coarse scroll step is 120.')
     GUICtrlSetTip($flick,'Continue scrolling even after mouse3 is released.' & @CRLF & 'The momentum can be reset by clicking any button or moving the wheel.')
     Local $str = ''
     $str &= Number(GUICtrlRead($sensX)) & ' '
     $str &= Number(GUICtrlRead($sensY)) & ' '
     $str &= Number(GUICtrlRead($decay)) & ' '
     $str &= Round(GUICtrlRead($stepX)) & ' '
     $str &= Round(GUICtrlRead($stepY)) & ' '
     $str &= Number(1=GUICtrlRead($flick)) & ' '
     StartChild($str)
     While 1
        Local $id = GUIGetMsg()
        Switch $id
          Case -3
               GUISetState(@SW_HIDE,$g_hWnd)
          Case $decay
               Local $value = Number(GUICtrlRead($id))
               If $value<1 Then $value = 1
               GUICtrlSetData($id,$value)
          Case $sensX,$sensY
               GUICtrlSetData($id,Number(GUICtrlRead($id)))
          Case $stepX,$stepY
               Local $value = Number(GUICtrlRead($id))
               If $value<1 Then
                  GUICtrlSetData($id,1)
               ElseIf $value>120 Then
                  GUICtrlSetData($id,120)
               Else
                  GUICtrlSetData($id,Round($value))
               EndIf
          Case $flick
          Case $apply,$pause 
               If $id==$pause And GUICtrlRead($pause)=='Pause' Then 
                  CloseChild()
                  GUICtrlSetData($pause,'Unpause')
               Else
                  Local $arr = [ _ 
                     Number(GUICtrlRead($sensX))   , _
                     Number(GUICtrlRead($sensY))   , _
                     Number(GUICtrlRead($decay))   , _
                     Round(GUICtrlRead($stepX))    , _
                     Round(GUICtrlRead($stepY))    , _
                     Number(1=GUICtrlRead($flick)) _
                  ]
                  Local $str = $arr[0] & ' ' & $arr[1] & ' ' & $arr[2] & ' ' & $arr[3] & ' ' & $arr[4] & ' ' & $arr[5]
                  RestartChild($str)
                  GUICtrlSetData($pause,'Pause')
                  IniWrite('options.ini','LibreScroll','sensX',$arr[0])
                  IniWrite('options.ini','LibreScroll','sensY',$arr[1])
                  IniWrite('options.ini','LibreScroll','decay',$arr[2])
                  IniWrite('options.ini','LibreScroll','stepX',$arr[3])
                  IniWrite('options.ini','LibreScroll','stepY',$arr[4])
                  IniWrite('options.ini','LibreScroll','flick',$arr[5])
               EndIf
        EndSwitch
     WEnd
EndFunc
Func Unhide()
     GUISetState(@SW_SHOW,$g_hWnd)
     GUISetState(@SW_RESTORE,$g_hWnd)
EndFunc
Func UpdateTip()
     TraySetToolTip('LibreScroll - ' & ( ProcessExists($g_childPID) ? 'Active' : 'Inactive') )
EndFunc
Func Info()
     MsgBox(0,'About LibreScroll v1.0.2','Visit https://github.com/EsportToys/LibreScroll for more info.')
EndFunc
Func Elevate()
     CloseChild()
     ShellExecute( @AutoItExe , @Compiled ? '' : @ScriptFullPath , '' , 'runas' )
     Exit
EndFunc
Func Quit()
     Exit
EndFunc
Func RestartChild($argStr)
     CloseChild()
     StartChild($argStr)
EndFunc
Func CloseChild()
     OnAutoItExitUnRegister ( CloseChild )
     If $g_childPID Then ProcessClose($g_childPID)
     $g_childPID = Null
EndFunc
Func StartChild($argStr)
     Global $g_childPID = Run(@AutoItExe & ' ' & (@Compiled?'':@ScriptFullPath) & ' ' & @AutoItPID & ' ' & $argStr)
     If ProcessExists($g_childPID) Then 
        OnAutoItExitRegister ( CloseChild )
     Else
        Exit
     EndIf
EndFunc

Func Child($args)
     If Not ProcessExists($args[1]) Then Return
     Global $g_sensitivity_x = Number($args[2])
     Global $g_sensitivity_y = Number($args[3])
     Global $g_damping = $args[4]>0 ? $args[4] : 3
     Global $g_threshold_x = $args[5]>1 ? $args[5] : 1
     Global $g_threshold_y = $args[6]>1 ? $args[6] : 1
     Global $g_flickMode = 1=$args[7] ? True : False

     Global Const $user32dll = DllOpen('user32.dll')
     Global Const $kernel32dll = DllOpen('kernel32.dll')
     Global $g_scrollVel = [0,0]
     Global $g_scrollAccu = [0,0]
     Global $g_trigger_isDown = False
     Local $_ = DllStructCreate('ushort page;ushort usage;dword flags;hwnd target')
     Local $size = DllStructGetSize($_)
     $_.page = 1
     $_.usage = 2
     $_.flags = 256
     $_.target = GUICreate('')
     DllCall('user32.dll','bool','SetProcessDPIAware')
     DllCall('user32.dll','bool','RegisterRawInputDevices','struct*',$_,'uint',1,'uint',$size)
     GUIRegisterMsg(0xFF,WM_INPUT)
     Local $time = Now()
     While Sleep(10)
         Local $now = Now()
         Tick($now-$time)
         $time = $now
     WEnd
EndFunc

Func Now()
     Return DllCall($kernel32dll,'bool','QueryPerformanceCounter','uint64*',Null)[1]
EndFunc

Func WM_INPUT($h,$m,$w,$l)
     Local Static $HEAD = 'struct;dword Type;dword Size;handle hDevice;wparam wParam;endstruct;'
     Local Static $MOU = $HEAD & 'ushort Flags;ushort Alignment;ushort ButtonFlags;short ButtonData;ulong RawButtons;long LastX;long LastY;ulong ExtraInformation;'
     Local Static $raw = DllStructCreate($MOU)
     Local Static $size = DllStructGetSize($raw)
     Local Static $headsize = DllStructGetSize(DllStructCreate($HEAD))
     Local Static $rect = DllStructCreate('long x1;long y1;long x2;long y2;')
     DllCall ( $user32dll,'uint','GetRawInputData','handle',$l,'uint',0x10000003,'struct*',$raw,'uint*',$size,'uint',$headsize)
     If $raw.hDevice Then
        If $raw.ButtonFlags Then
           If BitAnd(32,$raw.ButtonFlags) Then
              $g_trigger_isDown = False
              If Not $g_flickMode Then
                 $g_scrollVel[0] = 0
                 $g_scrollVel[1] = 0
              EndIf
              DllCall($user32dll,'bool','ClipCursor','struct*',Null)
           ElseIf BitAnd(16,$raw.ButtonFlags) Then
              SendCancel()
              $g_scrollAccu[0] = 0
              $g_scrollAccu[1] = 0
              $g_scrollVel[0] = 0
              $g_scrollVel[1] = 0
              $g_trigger_isDown = True
              DllCall($user32dll,'bool','GetCursorPos','struct*',$rect)
              $rect.x2 = $rect.x1 + 1
              $rect.y2 = $rect.y1 + 1
              DllCall($user32dll,'bool','ClipCursor','struct*',$rect)
           ElseIf $g_flickMode And Not $g_trigger_isDown Then 
              $g_scrollVel[1] = 0 
              $g_scrollVel[0] = 0 
           EndIf
        Else 
           $g_scrollAccu[0] += $raw.LastX
           $g_scrollAccu[1] += $raw.LastY
        EndIf
     EndIf
     Return 0
EndFunc

Func SendCancel()
     Local Static $SIZE = DllStructGetSize(DllStructCreate('dword;struct;long;long;dword;dword;dword;ulong_ptr;endstruct;'))
     Local Static $arr = CancelStruct()
     DllCall( $user32dll, 'uint', 'SendInput', 'uint', 2, 'struct*', $arr, 'int', $SIZE )
EndFunc

Func CancelStruct()
     Local $SIZE = DllStructGetSize(DllStructCreate('dword;struct;long;long;dword;dword;dword;ulong_ptr;endstruct;'))
     Local $arr = DllStructCreate('byte[' & $SIZE*2 & ']')
     Local $ptr = DllStructGetPtr($arr)
     Local $struct = DllStructCreate('dword;struct;word;word;dword;dword;ulong_ptr;endstruct;byte[8]',$ptr)
     DllStructSetData($struct,1,1)
     DllStructSetData($struct,2,0x03)
     DllStructSetData($struct,3,DllCall($user32dll,'uint','MapVirtualKey','uint',0x03,'uint',0)[0])
     DllStructSetData($struct,4,0)
     Local $struct = DllStructCreate('dword;struct;word;word;dword;dword;ulong_ptr;endstruct;byte[8]',$ptr+$SIZE)
     DllStructSetData($struct,1,1)
     DllStructSetData($struct,2,0x03)
     DllStructSetData($struct,3,DllCall($user32dll,'uint','MapVirtualKey','uint',0x03,'uint',0)[0])
     DllStructSetData($struct,4,2)
     Return $arr
EndFunc

Func Tick($ticks)
     Local Static $qpf = DllCall($kernel32dll,'bool','QueryPerformanceFrequency','int64*',Null)[1]
     If $g_trigger_isDown Then 
        Local $deltaX = $g_scrollAccu[0]
        Local $deltaY = $g_scrollAccu[1]
        $g_scrollVel[0] += $deltaX*$g_sensitivity_x
        $g_scrollVel[1] += $deltaY*$g_sensitivity_y
        $g_scrollAccu[0] -= $deltaX
        $g_scrollAccu[1] -= $deltaY
     Else
        If $g_flickMode Then 
           $g_scrollAccu[0]=0
           $g_scrollAccu[1]=0
        Else 
           Return
        EndIf
     EndIf
     Local $dt = $ticks/$qpf
     Local $mu = $g_damping
     Local $f0 = Exp(-$dt * $mu)
     Local $f1 = 0=$mu ? $dt : (1-$f0) / $mu
     SendScroll($f1*$g_scrollVel[0],-$f1*$g_scrollVel[1])
     $g_scrollVel[0] *= $f0
     $g_scrollVel[1] *= $f0
     If $g_scrollVel[0]*$g_scrollVel[0]+$g_scrollVel[1]*$g_scrollVel[1] < 0.25 Then 
        $g_scrollVel[0] = 0 
        $g_scrollVel[1] = 0
     EndIf 
EndFunc

Func SendScroll($deltaX,$deltaY)
     Local Static $residue = [0,0]
     $residue[0] += $deltaX
     $residue[1] += $deltaY
     Local $multipleX = Int($residue[0]/$g_threshold_x) , $multipleY = Int($residue[1]/$g_threshold_y)
     Local $sendX = 0 , $sendY = 0
     If $multipleX<>0 Then
        $sendX = $multipleX*$g_threshold_x
        $residue[0] -= $sendX
     EndIf
     If $multipleY<>0 Then
        $sendY = $multipleY*$g_threshold_y
        $residue[1] -= $sendY
     EndIf
     If $sendX<>0 or $sendY<>0 Then ScrollMouseXY($sendX,$sendY)
EndFunc

Func ScrollMouseXY($dx,$dy)
     Local Static $SIZE = DllStructGetSize(DllStructCreate('dword;struct;long;long;dword;dword;dword;ulong_ptr;endstruct;'))
     Local Static $arr = DllStructCreate('byte[' & $SIZE*2 & ']')
     Local Static $ptr = DllStructGetPtr($arr)
     Local Static $yData = DllStructCreate('dword type;struct;long;long;dword data;dword flag;dword;ulong_ptr;endstruct;', $ptr)
     Local Static $xData = DllStructCreate('dword type;struct;long;long;dword data;dword flag;dword;ulong_ptr;endstruct;', $ptr+$SIZE)
     Local Static $_ = SetupScrollData($xData,$yData)
     Local $count = ($dx?1:0)+($dy?1:0)
     Local $addr = $dy ? $ptr : $ptr+$SIZE
     DllStructSetData($yData,'data',$dy)
     DllStructSetData($xData,'data',$dx)
     DllCall( $user32dll, 'uint', 'SendInput', 'uint', $count, 'struct*', $addr, 'int', $SIZE )
EndFunc

Func SetupScrollData($xData,$yData)
     DllStructSetData($xData,'type',0)
     DllStructSetData($xData,'flag',0x1000)
     DllStructSetData($yData,'type',0)
     DllStructSetData($yData,'flag',0x0800)
EndFunc




; #FUNCTION# ====================================================================================================================
; Author ........: Valik
; Modified.......:
; ===============================================================================================================================
Func _Singleton($sOccurrenceName, $iFlag = 0)
	Local Const $ERROR_ALREADY_EXISTS = 183
	Local Const $SECURITY_DESCRIPTOR_REVISION = 1
	Local $tSecurityAttributes = 0

	If BitAND($iFlag, 2) Then
		; The size of SECURITY_DESCRIPTOR is 20 bytes.  We just
		; need a block of memory the right size, we aren't going to
		; access any members directly so it's not important what
		; the members are, just that the total size is correct.
		Local $tSecurityDescriptor = DllStructCreate("byte;byte;word;ptr[4]")
		; Initialize the security descriptor.
		Local $aCall = DllCall("advapi32.dll", "bool", "InitializeSecurityDescriptor", _
				"struct*", $tSecurityDescriptor, "dword", $SECURITY_DESCRIPTOR_REVISION)
		If @error Then Return SetError(@error, @extended, 0)
		If $aCall[0] Then
			; Add the NULL DACL specifying access to everybody.
			$aCall = DllCall("advapi32.dll", "bool", "SetSecurityDescriptorDacl", _
					"struct*", $tSecurityDescriptor, "bool", 1, "ptr", 0, "bool", 0)
			If @error Then Return SetError(@error, @extended, 0)
			If $aCall[0] Then
				; Create a SECURITY_ATTRIBUTES structure.
				$tSecurityAttributes = DllStructCreate($tagSECURITY_ATTRIBUTES)
				; Assign the members.
				DllStructSetData($tSecurityAttributes, 1, DllStructGetSize($tSecurityAttributes))
				DllStructSetData($tSecurityAttributes, 2, DllStructGetPtr($tSecurityDescriptor))
				DllStructSetData($tSecurityAttributes, 3, 0)
			EndIf
		EndIf
	EndIf

	Local $aHandle = DllCall("kernel32.dll", "handle", "CreateMutexW", "struct*", $tSecurityAttributes, "bool", 1, "wstr", $sOccurrenceName)
	If @error Then Return SetError(@error, @extended, 0)
	Local $aLastError = DllCall("kernel32.dll", "dword", "GetLastError")
	If @error Then Return SetError(@error, @extended, 0)
	If $aLastError[0] = $ERROR_ALREADY_EXISTS Then
		If BitAND($iFlag, 1) Then
			DllCall("kernel32.dll", "bool", "CloseHandle", "handle", $aHandle[0])
			If @error Then Return SetError(@error, @extended, 0)
			Return SetError($aLastError[0], $aLastError[0], 0)
		Else
			Exit -1
		EndIf
	EndIf
	Return $aHandle[0]
EndFunc   ;==>_Singleton
