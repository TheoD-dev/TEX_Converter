; Resize.pbi - plaatjes schalen, bijv. om SS2/SS3-textures geschikt te maken voor Serious Sam 1
;
; RSZ_Scale()     maakt een geschaalde kopie van een image, in goede kwaliteit
; RSZ_FitPow2()   rekent uit welke maat (machten van 2) binnen een maximum past
; RSZ_Dialog()    venster om de nieuwe maat te kiezen
;
; Over de kwaliteit: PureBasic's ResizeImage() kijkt bij sterk verkleinen maar naar een paar pixels,
; waardoor fijne details gaan "flikkeren" (aliasing). Daarom halveren we eerst stap voor stap door
; telkens 2 x 2 pixels te middelen (zoals mipmaps gemaakt worden) en doen we pas het laatste
; stukje met ResizeImage(). Bij het middelen tellen doorzichtige pixels minder mee voor de kleur,
; zodat er geen donkere randen ontstaan rond transparante delen.

; Grootste macht van 2 die niet groter is dan Value (1000 geeft 512).
Procedure.i RSZ_Pow2Floor(Value.i)
  Protected p.i = 1
  While p * 2 <= Value
    p * 2
  Wend
  ProcedureReturn p
EndProcedure

; Dichtstbijzijnde macht van 2 (600 geeft 512, 800 geeft 1024).
Procedure.i RSZ_Pow2Nearest(Value.i)
  Protected low.i = RSZ_Pow2Floor(Value)
  If Value - low > low * 2 - Value
    ProcedureReturn low * 2
  EndIf
  ProcedureReturn low
EndProcedure

; Rekent een maat uit met machten van 2 waarbij de langste zijde hooguit Max is,
; met ongeveer dezelfde verhouding. Bijv. 2048 x 1024 met Max 1024 geeft 1024 x 512.
Procedure RSZ_FitPow2(Width.i, Height.i, Max.i, *NewWidth.Integer, *NewHeight.Integer)
  Protected scale.d = 1
  If Width > Max Or Height > Max
    If Width >= Height
      scale = Max / Width
    Else
      scale = Max / Height
    EndIf
  EndIf
  *NewWidth\i  = RSZ_Pow2Nearest(Int(Width * scale + 0.5))
  *NewHeight\i = RSZ_Pow2Nearest(Int(Height * scale + 0.5))
  If *NewWidth\i > Max  : *NewWidth\i = Max  : EndIf
  If *NewHeight\i > Max : *NewHeight\i = Max : EndIf
  If *NewWidth\i < 1    : *NewWidth\i = 1    : EndIf
  If *NewHeight\i < 1   : *NewHeight\i = 1   : EndIf
EndProcedure

; Maakt een image half zo groot door telkens 2 x 2 pixels te middelen (alfa-gewogen).
; Is een zijde al 1 pixel, dan blijft die 1. Geeft een nieuw image terug.
Procedure.i RSZ_Halve(Image.i, HalveX.i, HalveY.i)
  Protected w.i = ImageWidth(Image), h.i = ImageHeight(Image), nw.i, nh.i, x.i, y.i, dx.i, dy.i
  Protected new.i, c.i, a.i, sa.i, sr.i, sg.i, sb.i, n.i, sx.i, sy.i
  nw = w : nh = h
  If HalveX : nw = w / 2 : EndIf
  If HalveY : nh = h / 2 : EndIf
  If nw < 1 : nw = 1 : EndIf
  If nh < 1 : nh = 1 : EndIf

  ; Eerst alle pixels in een array, dan is lezen veel sneller dan steeds Point()
  Dim src.l(w * h - 1)
  If StartDrawing(ImageOutput(Image))
    DrawingMode(#PB_2DDrawing_AllChannels)
    For y = 0 To h - 1
      For x = 0 To w - 1
        src(y * w + x) = Point(x, y)
      Next
    Next
    StopDrawing()
  EndIf

  new = CreateImage(#PB_Any, nw, nh, 32, #PB_Image_Transparent)
  If new And StartDrawing(ImageOutput(new))
    DrawingMode(#PB_2DDrawing_AllChannels)
    For y = 0 To nh - 1
      For x = 0 To nw - 1
        sr = 0 : sg = 0 : sb = 0 : sa = 0 : n = 0
        For dy = 0 To Bool(HalveY)
          For dx = 0 To Bool(HalveX)
            sx = x * (1 + Bool(HalveX)) + dx : If sx >= w : sx = w - 1 : EndIf
            sy = y * (1 + Bool(HalveY)) + dy : If sy >= h : sy = h - 1 : EndIf
            c = src(sy * w + sx)
            a = Alpha(c)
            sr + Red(c) * a : sg + Green(c) * a : sb + Blue(c) * a : sa + a
            n + 1
          Next
        Next
        If sa > 0
          Plot(x, y, RGBA(sr / sa, sg / sa, sb / sa, sa / n))
        Else
          ; Alles doorzichtig: gewone gemiddelde kleur bewaren (onzichtbaar, maar netjes)
          c = src((y * (1 + Bool(HalveY))) * w + x * (1 + Bool(HalveX)))
          Plot(x, y, RGBA(Red(c), Green(c), Blue(c), 0))
        EndIf
      Next
    Next
    StopDrawing()
  EndIf
  ProcedureReturn new
EndProcedure

; Maakt een geschaalde kopie van Image met maat NewWidth x NewHeight. Het origineel blijft bestaan.
Procedure.i RSZ_Scale(Image.i, NewWidth.i, NewHeight.i)
  Protected work.i, next_.i, hx.i, hy.i

  work = CopyImage(Image, #PB_Any)
  If work = 0
    ProcedureReturn 0
  EndIf
  ; Halveren zolang we daarmee niet onder de gewenste maat komen
  Repeat
    hx = Bool(ImageWidth(work) >= NewWidth * 2)
    hy = Bool(ImageHeight(work) >= NewHeight * 2)
    If hx = 0 And hy = 0
      Break
    EndIf
    next_ = RSZ_Halve(work, hx, hy)
    FreeImage(work)
    work = next_
    If work = 0
      ProcedureReturn 0
    EndIf
  ForEver
  ; Het laatste stukje (of vergroten) met PureBasic's eigen, vloeiende schaling
  If ImageWidth(work) <> NewWidth Or ImageHeight(work) <> NewHeight
    ResizeImage(work, NewWidth, NewHeight, #PB_Image_Smooth)
  EndIf
  ProcedureReturn work
EndProcedure

; Venster om de nieuwe maat te kiezen. Geeft #True terug bij "OK", met de maat in *NewWidth/*NewHeight.
Procedure.i RSZ_Dialog(ParentWindow.i, Width.i, Height.i, *NewWidth.Integer, *NewHeight.Integer)
  Protected win.i, cW.i, cH.i, keep.i, btnSS1.i, btnOK.i, btnCancel.i, info.i, event.i, done.i, result.i
  Protected p.i, w.i, h.i, busy.i

  win = OpenWindow(#PB_Any, 0, 0, 360, 200, "Resize", #PB_Window_SystemMenu | #PB_Window_WindowCentered, WindowID(ParentWindow))
  If win = 0
    ProcedureReturn #False
  EndIf
  TextGadget(#PB_Any, 12, 14, 330, 20, "Current size: " + Str(Width) + " x " + Str(Height) + " pixels")
  TextGadget(#PB_Any, 12, 48, 60, 20, "Width:")
  cW = ComboBoxGadget(#PB_Any, 80, 44, 100, 24, #PB_ComboBox_Editable)
  TextGadget(#PB_Any, 12, 80, 60, 20, "Height:")
  cH = ComboBoxGadget(#PB_Any, 80, 76, 100, 24, #PB_ComboBox_Editable)
  ; Keuzelijst met machten van 2; je kunt ook zelf een getal typen
  p = 16
  While p <= 8192
    AddGadgetItem(cW, -1, Str(p))
    AddGadgetItem(cH, -1, Str(p))
    p * 2
  Wend
  SetGadgetText(cW, Str(Width))
  SetGadgetText(cH, Str(Height))
  keep = CheckBoxGadget(#PB_Any, 196, 60, 150, 24, "Keep aspect ratio")
  SetGadgetState(keep, #True)
  btnSS1 = ButtonGadget(#PB_Any, 12, 116, 334, 26, "Fit Serious Sam 1 (powers of 2, max 1024)")
  info = TextGadget(#PB_Any, 12, 172, 160, 20, "")
  btnOK = ButtonGadget(#PB_Any, 176, 164, 80, 28, "OK", #PB_Button_Default)
  btnCancel = ButtonGadget(#PB_Any, 266, 164, 80, 28, "Cancel")
  AddKeyboardShortcut(win, #PB_Shortcut_Escape, 2)
  DisableWindow(ParentWindow, #True)

  Repeat
    event = WaitWindowEvent()
    If EventWindow() <> win
      Continue
    EndIf
    Select event
      Case #PB_Event_CloseWindow
        done = #True
      Case #PB_Event_Menu
        If EventMenu() = 2 : done = #True : EndIf
      Case #PB_Event_Gadget
        Select EventGadget()
          Case cW
            ; Breedte veranderd: hoogte meeschalen (busy voorkomt dat de twee elkaar blijven aanpassen)
            If Not busy And GetGadgetState(keep) And (EventType() = #PB_EventType_Change)
              w = Val(GetGadgetText(cW))
              If w > 0
                busy = #True
                SetGadgetText(cH, Str(Int(w * Height / Width + 0.5)))
                busy = #False
              EndIf
            EndIf
          Case cH
            If Not busy And GetGadgetState(keep) And (EventType() = #PB_EventType_Change)
              h = Val(GetGadgetText(cH))
              If h > 0
                busy = #True
                SetGadgetText(cW, Str(Int(h * Width / Height + 0.5)))
                busy = #False
              EndIf
            EndIf
          Case btnSS1
            RSZ_FitPow2(Width, Height, 1024, @w, @h)
            busy = #True
            SetGadgetText(cW, Str(w))
            SetGadgetText(cH, Str(h))
            busy = #False
          Case btnOK
            w = Val(GetGadgetText(cW))
            h = Val(GetGadgetText(cH))
            If w < 1 Or h < 1 Or w > 16384 Or h > 16384
              SetGadgetText(info, "Invalid size")
            Else
              *NewWidth\i = w
              *NewHeight\i = h
              result = #True
              done = #True
            EndIf
          Case btnCancel
            done = #True
        EndSelect
    EndSelect
  Until done

  DisableWindow(ParentWindow, #False)
  CloseWindow(win)
  SetActiveWindow(ParentWindow)
  ProcedureReturn result
EndProcedure
