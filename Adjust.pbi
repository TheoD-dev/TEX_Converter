; Adjust.pbi - histogramfuncties (menu Adjust): Levels en Auto levels
;
; Alles werkt met een opzoektabel ("LUT", look-up table): voor elk kanaal een lijst van 256
; waarden die zegt welke nieuwe waarde elke oude waarde krijgt. Dat is snel en het origineel
; blijft bewaard (zie EditHistory.pbi), dus alles is terug te draaien.
; Alleen R, G en B worden aangepast; transparantie (alfa) blijft altijd zoals hij is.
;
; Levels per kanaal:  zwartpunt, witpunt, gamma (in), en zwart/wit (uit).
;   waarde -> (waarde - zwart) / (wit - zwart), begrensd op 0..1
;          -> tot de macht 1/gamma          (gamma > 1 = middentonen lichter)
;          -> uitZwart + dat * (uitWit - uitZwart)
; Eerst de instelling van het kanaal zelf (R, G of B), daarna die van "RGB" (alle drie).
;
; Clipping = waarden onder het zwartpunt of boven het witpunt: die worden allemaal precies zwart
; of wit en zijn na opslaan niet meer van elkaar te onderscheiden. De app telt ze en waarschuwt.

XIncludeFile "TexInfo.pbi"

Structure LevelsChannel
  InBlack.i                     ; 0..254
  InWhite.i                     ; 1..255, groter dan InBlack
  Gamma.d                       ; 0.10 .. 9.99, 1 = geen verandering
  OutBlack.i                    ; 0..255
  OutWhite.i                    ; 0..255
EndStructure

Structure LevelsSettings
  Ch.LevelsChannel[4]           ; 0 = RGB (alle drie), 1 = rood, 2 = groen, 3 = blauw
EndStructure

Procedure ADJ_ResetChannel(*C.LevelsChannel)
  *C\InBlack = 0 : *C\InWhite = 255 : *C\Gamma = 1.0 : *C\OutBlack = 0 : *C\OutWhite = 255
EndProcedure

Procedure ADJ_ResetLevels(*L.LevelsSettings)
  Protected i.i
  For i = 0 To 3 : ADJ_ResetChannel(@*L\Ch[i]) : Next
EndProcedure

; Eén waarde door één kanaalinstelling halen.
Procedure.i ADJ_LevelValue(V.i, *C.LevelsChannel)
  Protected t.d
  t = (V - *C\InBlack) / (*C\InWhite - *C\InBlack)
  If t < 0 : t = 0 : EndIf
  If t > 1 : t = 1 : EndIf
  If *C\Gamma <> 1 : t = Pow(t, 1 / *C\Gamma) : EndIf
  ProcedureReturn Int(*C\OutBlack + t * (*C\OutWhite - *C\OutBlack) + 0.5)
EndProcedure

; Bouwt de opzoektabel lut(kanaal 0..2 = R,G,B, waarde 0..255) uit de Levels-instellingen.
Procedure ADJ_BuildLevelsLUT(*L.LevelsSettings, Array lut.a(2))
  Protected c.i, v.i
  For c = 0 To 2
    For v = 0 To 255
      lut(c, v) = ADJ_LevelValue(ADJ_LevelValue(v, @*L\Ch[c + 1]), @*L\Ch[0])
    Next
  Next
EndProcedure

; Geeft de plek van R, G en B in een pixel van het tekengeheugen (verschilt per systeem).
Procedure ADJ_ByteOrder(*R.Integer, *G.Integer, *B.Integer)
  If DrawingBufferPixelFormat() & #PB_PixelFormat_32Bits_BGR
    *B\i = 0 : *G\i = 1 : *R\i = 2
  Else
    *R\i = 0 : *G\i = 1 : *B\i = 2
  EndIf
EndProcedure

; Telt per kanaal (R, G, B) hoeveel pixels elke waarde hebben. Volledig doorzichtige pixels
; tellen niet mee (die zie je niet). Direct uit het tekengeheugen: snel, ook bij 2048 x 2048.
Procedure ADJ_Histogram(Image.i, Array hist.i(2))
  Protected *buf, pitch.i, x.i, y.i, *p.Ascii, ro.i, go.i, bo.i, w.i = ImageWidth(Image), h.i = ImageHeight(Image)
  Dim hist.i(2, 255)
  If StartDrawing(ImageOutput(Image))
    *buf = DrawingBuffer() : pitch = DrawingBufferPitch()
    ADJ_ByteOrder(@ro, @go, @bo)
    For y = 0 To h - 1
      For x = 0 To w - 1
        *p = *buf + y * pitch + x * 4
        If PeekA(*p + 3) = 0 : Continue : EndIf
        hist(0, PeekA(*p + ro)) + 1
        hist(1, PeekA(*p + go)) + 1
        hist(2, PeekA(*p + bo)) + 1
      Next
    Next
    StopDrawing()
  EndIf
EndProcedure

; Per kanaal (R, G, B) en invoerwaarde: wordt deze waarde geclipt? -1 = naar zwart, 1 = naar wit, 0 = nee.
; Geclipt betekent: de waarde valt onder het zwartpunt of boven het witpunt (van het kanaal zelf
; of daarna van RGB), en wordt dus vastgezet op zwart of wit.
Procedure ADJ_BuildClipTable(*L.LevelsSettings, Array clip.b(2))
  Protected c.i, v.i, u.i
  For c = 0 To 2
    For v = 0 To 255
      clip(c, v) = 0
      If v < *L\Ch[c + 1]\InBlack
        clip(c, v) = -1
      ElseIf v > *L\Ch[c + 1]\InWhite
        clip(c, v) = 1
      Else
        u = ADJ_LevelValue(v, @*L\Ch[c + 1])
        If u < *L\Ch[0]\InBlack
          clip(c, v) = -1
        ElseIf u > *L\Ch[0]\InWhite
          clip(c, v) = 1
        EndIf
      EndIf
    Next
  Next
EndProcedure

; Maakt een nieuw image met de opzoektabel toegepast op R, G en B (alfa blijft gelijk).
; ShowClip = #True: pixels die geclipt worden rood (naar wit) of blauw (naar zwart) kleuren,
; alleen voor het voorbeeld.
Procedure.i ADJ_ApplyLUT(Image.i, Array lut.a(2), ShowClip.i, Array clip.b(2))
  Protected new.i, *buf, pitch.i, x.i, y.i, *p, ro.i, go.i, bo.i, w.i, h.i, r.i, g.i, b.i
  new = CopyImage(Image, #PB_Any)
  If new = 0 : ProcedureReturn 0 : EndIf
  w = ImageWidth(new) : h = ImageHeight(new)
  If StartDrawing(ImageOutput(new))
    *buf = DrawingBuffer() : pitch = DrawingBufferPitch()
    ADJ_ByteOrder(@ro, @go, @bo)
    For y = 0 To h - 1
      *p = *buf + y * pitch
      For x = 0 To w - 1
        r = PeekA(*p + ro) : g = PeekA(*p + go) : b = PeekA(*p + bo)
        If ShowClip And PeekA(*p + 3) > 0 And (clip(0, r) Or clip(1, g) Or clip(2, b))
          If clip(0, r) = 1 Or clip(1, g) = 1 Or clip(2, b) = 1
            PokeA(*p + ro, 255) : PokeA(*p + go, 0) : PokeA(*p + bo, 0)      ; rood: naar wit geclipt
          Else
            PokeA(*p + ro, 0) : PokeA(*p + go, 0) : PokeA(*p + bo, 255)      ; blauw: naar zwart geclipt
          EndIf
        Else
          PokeA(*p + ro, lut(0, r)) : PokeA(*p + go, lut(1, g)) : PokeA(*p + bo, lut(2, b))
        EndIf
        *p + 4
      Next
    Next
    StopDrawing()
  EndIf
  ProcedureReturn new
EndProcedure

; Telt hoeveel kanaalwaarden geclipt worden, uit het histogram.
Procedure.i ADJ_CountClipped(Array hist.i(2), Array clip.b(2))
  Protected c.i, v.i, n.i
  For c = 0 To 2
    For v = 0 To 255
      If clip(c, v) : n + hist(c, v) : EndIf
    Next
  Next
  ProcedureReturn n
EndProcedure
; Telt hoeveel verschillende tinten samenvallen (verschillende invoerwaarden die dezelfde uitvoer
; krijgen). Dat gebeurt ook zonder clipping als het bereik smaller wordt.
Procedure.i ADJ_CountMerged(Array hist.i(2), Array lut.a(2))
  Protected c.i, v.i, n.i
  Dim seen.i(255)
  For c = 0 To 2
    For v = 0 To 255 : seen(v) = 0 : Next
    For v = 0 To 255
      If hist(c, v) > 0
        If seen(lut(c, v)) : n + 1 : EndIf
        seen(lut(c, v)) = #True
      EndIf
    Next
  Next
  ProcedureReturn n
EndProcedure

; Auto levels zonder clipping: het nieuwe zwart is precies de donkerste waarde, het nieuwe wit
; precies de lichtste, voor R, G en B samen (zo verschuiven de kleuren niet).
Procedure ADJ_AutoLevels(Array hist.i(2), *L.LevelsSettings)
  Protected c.i, v.i, low.i = 255, high.i = 0
  For c = 0 To 2
    For v = 0 To 255
      If hist(c, v) > 0
        If v < low : low = v : EndIf
        If v > high : high = v : EndIf
      EndIf
    Next
  Next
  ADJ_ResetLevels(*L)
  If high > low
    *L\Ch[0]\InBlack = low
    *L\Ch[0]\InWhite = high
  EndIf
EndProcedure

; Is er iets ingesteld (anders dan de standaard)?
Procedure.i ADJ_IsIdentity(*L.LevelsSettings)
  Protected i.i
  For i = 0 To 3
    If *L\Ch[i]\InBlack <> 0 Or *L\Ch[i]\InWhite <> 255 Or *L\Ch[i]\Gamma <> 1 Or *L\Ch[i]\OutBlack <> 0 Or *L\Ch[i]\OutWhite <> 255
      ProcedureReturn #False
    EndIf
  Next
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------------------------
; Levels-venster
; ---------------------------------------------------------------------------------------------
; Het hoofdprogramma geeft een procedure mee die een voorbeeld laat zien (Image = 0: weer normaal).
Prototype ADJ_PreviewProc(Image.i)

Global ADJ_Win.i, ADJ_Canvas.i, ADJ_Chan.i, ADJ_InB.i, ADJ_Gam.i, ADJ_InW.i, ADJ_OutB.i, ADJ_OutW.i
Global ADJ_ShowClip.i, ADJ_Info.i
Global ADJ_Lev.LevelsSettings, ADJ_Base.i, ADJ_Preview.ADJ_PreviewProc, ADJ_Clipped.i, ADJ_Total.i
Global Dim ADJ_Hist.i(2, 255)
Global Dim ADJ_Lut.a(2, 255)
Global Dim ADJ_Clip.b(2, 255)

#ADJ_HistW = 512                ; breedte van het histogram in het venster (2 pixels per waarde)
#ADJ_HistH = 150
#ADJ_MarkH = 18                 ; strook met de driehoekjes onder het histogram

; Gammaschuifje: staat op de plek waar de uitvoer middengrijs wordt
Procedure.d ADJ_GammaPos(*C.LevelsChannel)
  ProcedureReturn *C\InBlack + (*C\InWhite - *C\InBlack) * Pow(0.5, *C\Gamma)
EndProcedure

; Tekent histogram en schuifjes van het gekozen kanaal.
Procedure ADJ_Draw()
  Protected ch.i = GetGadgetState(ADJ_Chan), *C.LevelsChannel = @ADJ_Lev\Ch[ch], v.i, n.i, biggest.i = 1, bar.i, x.i, ox.i, w.i, h.i
  Dim col.i(255)
  For v = 0 To 255
    If ch = 0
      n = (ADJ_Hist(0, v) + ADJ_Hist(1, v) + ADJ_Hist(2, v)) / 3
    Else
      n = ADJ_Hist(ch - 1, v)
    EndIf
    col(v) = n
    If n > biggest : biggest = n : EndIf
  Next
  If StartDrawing(CanvasOutput(ADJ_Canvas))
    w = OutputWidth() : h = OutputHeight()
    ox = (w - #ADJ_HistW) / 2
    Box(0, 0, w, h, RGB(240, 240, 240))
    Box(ox, 0, #ADJ_HistW, #ADJ_HistH, RGB(30, 30, 30))
    ; Gebieden die geclipt worden lichtrood
    Box(ox, 0, *C\InBlack * 2, #ADJ_HistH, RGB(70, 30, 30))
    Box(ox + *C\InWhite * 2 + 2, 0, #ADJ_HistW - *C\InWhite * 2 - 2, #ADJ_HistH, RGB(70, 30, 30))
    For v = 0 To 255
      bar = Sqr(col(v) / biggest) * (#ADJ_HistH - 4)        ; wortel-schaal: kleine aantallen blijven zichtbaar
      Select ch
        Case 1 : Box(ox + v * 2, #ADJ_HistH - bar, 2, bar, RGB(230, 70, 70))
        Case 2 : Box(ox + v * 2, #ADJ_HistH - bar, 2, bar, RGB(70, 200, 70))
        Case 3 : Box(ox + v * 2, #ADJ_HistH - bar, 2, bar, RGB(90, 120, 240))
        Default : Box(ox + v * 2, #ADJ_HistH - bar, 2, bar, RGB(220, 220, 220))
      EndSelect
    Next
    ; Driehoekjes: zwart, gamma (grijs), wit
    x = ox + *C\InBlack * 2
    LineXY(x, #ADJ_HistH + 2, x - 6, #ADJ_HistH + 14, RGB(0, 0, 0)) : LineXY(x, #ADJ_HistH + 2, x + 6, #ADJ_HistH + 14, RGB(0, 0, 0)) : LineXY(x - 6, #ADJ_HistH + 14, x + 6, #ADJ_HistH + 14, RGB(0, 0, 0))
    FillArea(x, #ADJ_HistH + 10, RGB(0, 0, 0), RGB(0, 0, 0))
    x = ox + ADJ_GammaPos(*C) * 2
    LineXY(x, #ADJ_HistH + 2, x - 6, #ADJ_HistH + 14, RGB(90, 90, 90)) : LineXY(x, #ADJ_HistH + 2, x + 6, #ADJ_HistH + 14, RGB(90, 90, 90)) : LineXY(x - 6, #ADJ_HistH + 14, x + 6, #ADJ_HistH + 14, RGB(90, 90, 90))
    FillArea(x, #ADJ_HistH + 10, RGB(90, 90, 90), RGB(128, 128, 128))
    x = ox + *C\InWhite * 2
    LineXY(x, #ADJ_HistH + 2, x - 6, #ADJ_HistH + 14, RGB(0, 0, 0)) : LineXY(x, #ADJ_HistH + 2, x + 6, #ADJ_HistH + 14, RGB(0, 0, 0)) : LineXY(x - 6, #ADJ_HistH + 14, x + 6, #ADJ_HistH + 14, RGB(0, 0, 0))
    FillArea(x, #ADJ_HistH + 10, RGB(0, 0, 0), RGB(255, 255, 255))
    StopDrawing()
  EndIf
EndProcedure

; Zet de getallen in de invoervelden (zonder dat dat weer een "Change" geeft dat iets uitmaakt).
Procedure ADJ_FillFields()
  Protected *C.LevelsChannel = @ADJ_Lev\Ch[GetGadgetState(ADJ_Chan)]
  SetGadgetText(ADJ_InB, Str(*C\InBlack))
  SetGadgetText(ADJ_Gam, StrD(*C\Gamma, 2))
  SetGadgetText(ADJ_InW, Str(*C\InWhite))
  SetGadgetText(ADJ_OutB, Str(*C\OutBlack))
  SetGadgetText(ADJ_OutW, Str(*C\OutWhite))
EndProcedure

; Alles opnieuw uitrekenen: opzoektabel, clipping, tekst, histogram en (eventueel) het voorbeeld.
Procedure ADJ_Update(WithPreview.i = #True)
  Protected merged.i, img.i, text.s
  ADJ_BuildLevelsLUT(@ADJ_Lev, ADJ_Lut())
  ADJ_BuildClipTable(@ADJ_Lev, ADJ_Clip())
  ADJ_Clipped = ADJ_CountClipped(ADJ_Hist(), ADJ_Clip())
  merged = ADJ_CountMerged(ADJ_Hist(), ADJ_Lut())
  If ADJ_Clipped > 0
    text = "Clipping: " + Str(ADJ_Clipped) + " values (" + StrD(ADJ_Clipped * 100 / ADJ_Total, 2) + "%) become pure black or white"
    SetGadgetColor(ADJ_Info, #PB_Gadget_FrontColor, RGB(200, 0, 0))
  Else
    text = "Clipping: none"
    SetGadgetColor(ADJ_Info, #PB_Gadget_FrontColor, RGB(0, 120, 0))
  EndIf
  If merged > 0 : text + "    Merged tones: " + Str(merged) : EndIf
  SetGadgetText(ADJ_Info, text)
  ADJ_Draw()
  If WithPreview
    img = ADJ_ApplyLUT(ADJ_Base, ADJ_Lut(), GetGadgetState(ADJ_ShowClip), ADJ_Clip())
    If img
      ADJ_Preview(img)
      FreeImage(img)
    EndIf
  EndIf
EndProcedure

; Leest een getal uit een invoerveld, begrensd tussen Low en High.
Procedure.i ADJ_ReadInt(Gadget.i, Low.i, High.i)
  Protected v.i = Val(GetGadgetText(Gadget))
  If v < Low : v = Low : EndIf
  If v > High : v = High : EndIf
  ProcedureReturn v
EndProcedure

; Opent het Levels-venster voor BaseImage. Geeft #True bij OK, met de instellingen in *Result.
; Bij OK met clipping wordt eerst om bevestiging gevraagd. *Clipped krijgt het aantal geclipte waarden.
Procedure.i ADJ_LevelsDialog(ParentWindow.i, BaseImage.i, *Result.LevelsSettings, Preview.ADJ_PreviewProc, *Clipped.Integer)
  Protected event.i, done.i, result.i, bAuto.i, bReset.i, bOK.i, bCancel.i, drag.i = -1, mx.i, ox.i, v.i, t.d
  Protected *C.LevelsChannel, lastPreview.i, i.i

  ADJ_Base = BaseImage : ADJ_Preview = Preview
  ADJ_ResetLevels(@ADJ_Lev)
  ADJ_Histogram(BaseImage, ADJ_Hist())
  ADJ_Total = 0
  For i = 0 To 255 : ADJ_Total + ADJ_Hist(0, i) + ADJ_Hist(1, i) + ADJ_Hist(2, i) : Next
  If ADJ_Total = 0 : ADJ_Total = 1 : EndIf

  ADJ_Win = OpenWindow(#PB_Any, 0, 0, 560, 380, "Levels", #PB_Window_SystemMenu | #PB_Window_WindowCentered, WindowID(ParentWindow))
  If ADJ_Win = 0 : ProcedureReturn #False : EndIf
  TextGadget(#PB_Any, 14, 14, 60, 20, "Channel:")
  ADJ_Chan = ComboBoxGadget(#PB_Any, 76, 10, 120, 24)
  AddGadgetItem(ADJ_Chan, -1, "RGB") : AddGadgetItem(ADJ_Chan, -1, "Red") : AddGadgetItem(ADJ_Chan, -1, "Green") : AddGadgetItem(ADJ_Chan, -1, "Blue")
  SetGadgetState(ADJ_Chan, 0)
  bAuto  = ButtonGadget(#PB_Any, 360, 9, 90, 26, "Auto")
  bReset = ButtonGadget(#PB_Any, 456, 9, 90, 26, "Reset")
  ADJ_Canvas = CanvasGadget(#PB_Any, 14, 44, 532, #ADJ_HistH + #ADJ_MarkH)
  TextGadget(#PB_Any, 14, 224, 60, 20, "Input:")
  TextGadget(#PB_Any, 76, 224, 40, 20, "Black")  : ADJ_InB = StringGadget(#PB_Any, 116, 220, 50, 24, "0")
  TextGadget(#PB_Any, 186, 224, 50, 20, "Gamma")  : ADJ_Gam = StringGadget(#PB_Any, 236, 220, 60, 24, "1.00")
  TextGadget(#PB_Any, 316, 224, 40, 20, "White")  : ADJ_InW = StringGadget(#PB_Any, 356, 220, 50, 24, "255")
  TextGadget(#PB_Any, 14, 256, 60, 20, "Output:")
  TextGadget(#PB_Any, 76, 256, 40, 20, "Black")  : ADJ_OutB = StringGadget(#PB_Any, 116, 252, 50, 24, "0")
  TextGadget(#PB_Any, 316, 256, 40, 20, "White")  : ADJ_OutW = StringGadget(#PB_Any, 356, 252, 50, 24, "255")
  ADJ_ShowClip = CheckBoxGadget(#PB_Any, 14, 284, 300, 22, "Show clipping (red = to white, blue = to black)")
  ADJ_Info = TextGadget(#PB_Any, 14, 312, 532, 20, "")
  bOK     = ButtonGadget(#PB_Any, 360, 342, 90, 28, "OK", #PB_Button_Default)
  bCancel = ButtonGadget(#PB_Any, 456, 342, 90, 28, "Cancel")
  AddKeyboardShortcut(ADJ_Win, #PB_Shortcut_Escape, 2)
  DisableWindow(ParentWindow, #True)
  ADJ_Update()

  Repeat
    event = WaitWindowEvent()
    If EventWindow() <> ADJ_Win : Continue : EndIf
    *C = @ADJ_Lev\Ch[GetGadgetState(ADJ_Chan)]
    Select event
      Case #PB_Event_CloseWindow
        done = #True
      Case #PB_Event_Menu
        If EventMenu() = 2 : done = #True : EndIf
      Case #PB_Event_Gadget
        Select EventGadget()
          Case ADJ_Chan
            ADJ_FillFields() : ADJ_Update(#False)
          Case bAuto
            ADJ_AutoLevels(ADJ_Hist(), @ADJ_Lev)
            SetGadgetState(ADJ_Chan, 0) : ADJ_FillFields() : ADJ_Update()
          Case bReset
            ADJ_ResetLevels(@ADJ_Lev) : ADJ_FillFields() : ADJ_Update()
          Case ADJ_ShowClip
            ADJ_Update()
          Case ADJ_InB, ADJ_InW, ADJ_Gam, ADJ_OutB, ADJ_OutW
            ; SetGadgetText (bij slepen) geeft ook een "Change": alleen reageren als er echt iets anders staat
            If EventType() = #PB_EventType_Change And (GetGadgetText(ADJ_InB) <> Str(*C\InBlack) Or GetGadgetText(ADJ_InW) <> Str(*C\InWhite) Or GetGadgetText(ADJ_OutB) <> Str(*C\OutBlack) Or GetGadgetText(ADJ_OutW) <> Str(*C\OutWhite) Or GetGadgetText(ADJ_Gam) <> StrD(*C\Gamma, 2))
              *C\InBlack = ADJ_ReadInt(ADJ_InB, 0, 253)
              *C\InWhite = ADJ_ReadInt(ADJ_InW, *C\InBlack + 2, 255)
              *C\OutBlack = ADJ_ReadInt(ADJ_OutB, 0, 255)
              *C\OutWhite = ADJ_ReadInt(ADJ_OutW, 0, 255)
              t = ValD(ReplaceString(GetGadgetText(ADJ_Gam), ",", "."))
              If t >= 0.1 And t <= 9.99 : *C\Gamma = t : EndIf
              ADJ_Update()
            EndIf
          Case ADJ_Canvas
            ; Schuifjes slepen
            ox = (DesktopScaledX(GadgetWidth(ADJ_Canvas)) - #ADJ_HistW) / 2
            mx = GetGadgetAttribute(ADJ_Canvas, #PB_Canvas_MouseX) - ox
            v = mx / 2
            If v < 0 : v = 0 : EndIf
            If v > 255 : v = 255 : EndIf
            Select EventType()
              Case #PB_EventType_LeftButtonDown
                ; Het dichtstbijzijnde schuifje pakken
                drag = 0 : t = Abs(v - *C\InBlack)
                If Abs(v - ADJ_GammaPos(*C)) < t : drag = 1 : t = Abs(v - ADJ_GammaPos(*C)) : EndIf
                If Abs(v - *C\InWhite) < t : drag = 2 : EndIf
              Case #PB_EventType_LeftButtonUp
                If drag >= 0 : drag = -1 : ADJ_Update() : EndIf
            EndSelect
            If drag >= 0 And (EventType() = #PB_EventType_MouseMove Or EventType() = #PB_EventType_LeftButtonDown)
              Select drag
                Case 0 : If v > *C\InWhite - 2 : v = *C\InWhite - 2 : EndIf : *C\InBlack = v
                Case 2 : If v < *C\InBlack + 2 : v = *C\InBlack + 2 : EndIf : *C\InWhite = v
                Case 1
                  t = (v - *C\InBlack) / (*C\InWhite - *C\InBlack)
                  If t < 0.01 : t = 0.01 : EndIf
                  If t > 0.99 : t = 0.99 : EndIf
                  *C\Gamma = Log(t) / Log(0.5)
                  If *C\Gamma < 0.1 : *C\Gamma = 0.1 : EndIf
                  If *C\Gamma > 9.99 : *C\Gamma = 9.99 : EndIf
              EndSelect
              ADJ_FillFields()
              ; Voorbeeld hooguit ongeveer 8 keer per seconde bijwerken, anders wordt slepen stroef
              If ElapsedMilliseconds() - lastPreview > 120
                ADJ_Update() : lastPreview = ElapsedMilliseconds()
              Else
                ADJ_Update(#False)
              EndIf
            EndIf
          Case bOK
            If ADJ_IsIdentity(@ADJ_Lev)
              done = #True                      ; niets ingesteld: gewoon sluiten
            ElseIf ADJ_Clipped = 0 Or Not PREF_WarnClipping Or MessageRequester("Levels", "This adjustment clips " + Str(ADJ_Clipped) + " values to pure black or white." + #LF$ + "That information is lost when you save." + #LF$ + #LF$ + "Apply anyway?", #PB_MessageRequester_YesNo | #PB_MessageRequester_Warning) = #PB_MessageRequester_Yes
              CopyStructure(@ADJ_Lev, *Result, LevelsSettings)
              *Clipped\i = ADJ_Clipped
              result = #True : done = #True
            EndIf
          Case bCancel
            done = #True
        EndSelect
    EndSelect
  Until done

  ADJ_Preview(0)                                  ; voorbeeld weg, normaal plaatje weer tonen
  DisableWindow(ParentWindow, #False)
  CloseWindow(ADJ_Win)
  ADJ_Win = 0
  SetActiveWindow(ParentWindow)
  ProcedureReturn result
EndProcedure