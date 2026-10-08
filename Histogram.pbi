; Histogram.pbi - venster met een histogram van het geladen plaatje
;
; Een histogram telt hoeveel pixels elke helderheid (0..255) hebben, per kleurkanaal.
; Links in de grafiek staat donker, rechts licht; hoe hoger de staaf, hoe meer pixels.
;
; Keuzes in het venster:
;   RGB (rood, groen en blauw over elkaar), Red, Green, Blue, Luminance (helderheid zoals het oog
;   die ziet), Alpha (transparantie) en bij HDR-textures "HDR brightness (stops)": de echte
;   helderheid van de HDR-data in stops, met een lijn waar het witpunt van de huidige belichting ligt.
;
; Het venster blijft open naast het hoofdvenster en werkt zichzelf bij als je een ander plaatje opent.
; Het regelt zijn eigen gebeurtenissen met BindEvent/BindGadgetEvent, zodat de hoofdlus
; van TexConverter.pb er niets voor hoeft te doen.

XIncludeFile "TexInfo.pbi"

Enumeration HistogramMode
  #Hist_RGB
  #Hist_Red
  #Hist_Green
  #Hist_Blue
  #Hist_Luminance
  #Hist_Alpha
  #Hist_HdrStops
EndEnumeration

#Hist_StopBins = 160            ; aantal staafjes bij de HDR-weergave

Global Hist_Window.i, Hist_Canvas.i, Hist_Combo.i, Hist_Text.i, Hist_LogBox.i
Global Hist_IsHDR.i, Hist_Pixels.i, Hist_Transparent.i, Hist_Log.i
Global Hist_StopMin.d, Hist_StopMax.d       ; bereik van de HDR-weergave in stops
Global Hist_WhitePoint.d                    ; log2 van de waarde die bij de huidige belichting wit wordt
Global Dim Hist_Count.i(4, 255)             ; [kanaal 0=R 1=G 2=B 3=A 4=helderheid, waarde]
Global Dim Hist_Stops.i(#Hist_StopBins - 1)

; Telt alle pixels van het plaatje (en bij HDR ook de echte helderheid uit de HDR-data).
Procedure Hist_Compute(Image.i, *Info.TexInfo)
  Protected x.i, y.i, c.i, w.i, h.i, lum.i, i.i, *p, e.i, v.d, lv.d, bin.i, n.i

  For c = 0 To 4
    For i = 0 To 255 : Hist_Count(c, i) = 0 : Next
  Next
  w = ImageWidth(Image)
  h = ImageHeight(Image)
  Hist_Pixels = w * h
  Hist_Transparent = 0

  If StartDrawing(ImageOutput(Image))
    DrawingMode(#PB_2DDrawing_AllChannels)    ; zodat Point() ook de alfa teruggeeft
    For y = 0 To h - 1
      For x = 0 To w - 1
        c = Point(x, y)
        Hist_Count(3, Alpha(c)) + 1
        If Alpha(c) = 0
          ; Volledig doorzichtige pixels tellen niet mee voor de kleuren: hun kleur zie je niet,
          ; en een grote doorzichtige achtergrond zou anders één enorme piek geven.
          Hist_Transparent + 1
          Continue
        EndIf
        Hist_Count(0, Red(c)) + 1
        Hist_Count(1, Green(c)) + 1
        Hist_Count(2, Blue(c)) + 1
        ; Helderheid volgens Rec. 709 (groen telt het zwaarst, blauw het minst)
        lum = (2126 * Red(c) + 7152 * Green(c) + 722 * Blue(c)) / 10000
        Hist_Count(4, lum) + 1
      Next
    Next
    StopDrawing()
  EndIf

  ; --- HDR: echte helderheid in stops (log2), uit de RGBE-data ---
  Hist_IsHDR = Bool(*Info\IsHDR And *Info\HdrData)
  If Hist_IsHDR
    n = *Info\Width * *Info\Height
    Dim lumLog.d(n - 1)
    Hist_StopMin = 1000 : Hist_StopMax = -1000
    For i = 0 To n - 1
      *p = *Info\HdrData + i * 4
      e = PeekA(*p + 3)
      If e = 0
        lv = -1000                              ; zwart
      Else
        v = (0.2126 * (PeekA(*p) + 0.5) + 0.7152 * (PeekA(*p + 1) + 0.5) + 0.0722 * (PeekA(*p + 2) + 0.5)) / 256 * Pow(2, e - 128)
        lv = Log(v) / Log(2)
        If lv < Hist_StopMin : Hist_StopMin = lv : EndIf
        If lv > Hist_StopMax : Hist_StopMax = lv : EndIf
      EndIf
      lumLog(i) = lv
    Next
    ; Bereik afronden op hele stops, minimaal 4 stops breed
    Hist_StopMin = Round(Hist_StopMin, #PB_Round_Down)
    Hist_StopMax = Round(Hist_StopMax, #PB_Round_Up)
    If Hist_StopMax - Hist_StopMin < 4 : Hist_StopMax = Hist_StopMin + 4 : EndIf
    For i = 0 To #Hist_StopBins - 1 : Hist_Stops(i) = 0 : Next
    For i = 0 To n - 1
      If lumLog(i) > -1000
        bin = Int((lumLog(i) - Hist_StopMin) / (Hist_StopMax - Hist_StopMin) * #Hist_StopBins)
        If bin < 0 : bin = 0 : EndIf
        If bin >= #Hist_StopBins : bin = #Hist_StopBins - 1 : EndIf
        Hist_Stops(bin) + 1
      EndIf
    Next
  EndIf
EndProcedure

; Tekent de staafjes van één kanaal. Kleur met een beetje doorzichtigheid, zodat RGB over elkaar past.
Procedure Hist_DrawChannel(Channel.i, Color.i, Biggest.i, Left.i, Top.i, Width.i, Height.i)
  Protected i.i, x1.i, x2.i, bar.i
  For i = 0 To 255
    x1 = Left + i * Width / 256
    x2 = Left + (i + 1) * Width / 256
    If Hist_Log
      ; Logaritmisch: kleine aantallen worden ook zichtbaar naast een grote piek
      bar = Log(1 + Hist_Count(Channel, i)) / Log(1 + Biggest) * Height
    Else
      bar = Hist_Count(Channel, i) * Height / Biggest
    EndIf
    If bar > 0
      Box(x1, Top + Height - bar, x2 - x1, bar, Color)
    EndIf
  Next
EndProcedure

; Tekent de grafiek opnieuw volgens de keuze in de lijst.
Procedure Hist_Draw()
  Protected mode.i, biggest.i, i.i, c.i, left.i, top.i, width.i, height.i, x.i, bar.i
  Protected total.d, sum.d, lowest.i, highest.i, text.s, stop.i, wp.i, median.d, acc.i

  If Not IsWindow(Hist_Window)
    ProcedureReturn
  EndIf
  mode = GetGadgetItemData(Hist_Combo, GetGadgetState(Hist_Combo))

  If StartDrawing(CanvasOutput(Hist_Canvas))
    left = 8 : top = 8
    width = OutputWidth() - 16
    height = OutputHeight() - 30
    Box(0, 0, OutputWidth(), OutputHeight(), RGB(40, 40, 40))
    Box(left, top, width, height, RGB(25, 25, 25))
    DrawingMode(#PB_2DDrawing_AlphaBlend)

    If mode = #Hist_HdrStops
      ; --- HDR: staafjes per stukje stop ---
      biggest = 1
      For i = 0 To #Hist_StopBins - 1
        If Hist_Stops(i) > biggest : biggest = Hist_Stops(i) : EndIf
      Next
      For i = 0 To #Hist_StopBins - 1
        If Hist_Log
          bar = Log(1 + Hist_Stops(i)) / Log(1 + biggest) * height
        Else
          bar = Hist_Stops(i) * height / biggest
        EndIf
        Box(left + i * width / #Hist_StopBins, top + height - bar, width / #Hist_StopBins + 1, bar, RGBA(230, 230, 230, 255))
      Next
      ; Lijnen per hele stop met het getal eronder
      DrawingMode(#PB_2DDrawing_Transparent)
      For stop = Int(Hist_StopMin) To Int(Hist_StopMax)
        x = left + (stop - Hist_StopMin) / (Hist_StopMax - Hist_StopMin) * width
        LineXY(x, top + height, x, top + height + 4, RGB(150, 150, 150))
        DrawText(x - 6, top + height + 6, Str(stop), RGB(180, 180, 180))
      Next
      ; Witpunt van de huidige belichting: alles rechts hiervan wordt (bij Editor clip) wit
      wp = left + (Hist_WhitePoint - Hist_StopMin) / (Hist_StopMax - Hist_StopMin) * width
      If wp >= left And wp <= left + width
        Box(wp - 1, top, 2, height, RGB(255, 200, 0))
        DrawText(wp + 3, top + 2, "white point", RGB(255, 200, 0))
      EndIf
      ; Mediaan: de helft van de pixels is donkerder dan dit
      total = 0
      For i = 0 To #Hist_StopBins - 1 : total + Hist_Stops(i) : Next
      acc = 0
      For i = 0 To #Hist_StopBins - 1
        acc + Hist_Stops(i)
        If acc >= total / 2
          median = Hist_StopMin + (i + 0.5) / #Hist_StopBins * (Hist_StopMax - Hist_StopMin)
          Break
        EndIf
      Next
      text = "Range: " + StrD(Hist_StopMin, 0) + " to " + StrD(Hist_StopMax, 0) + " stops   median: " + StrD(median, 1) + "   white point: " + StrD(Hist_WhitePoint, 1) + " (exposure " + StrD(-Hist_WhitePoint, 1) + " EV)"

    Else
      ; --- Gewone histogrammen (0..255) ---
      ; Hoogste staaf zoeken in de kanalen die getekend worden (bepaalt de schaal)
      biggest = 1
      For c = 0 To 4
        Select mode
          Case #Hist_RGB       : If c > 2 : Continue : EndIf
          Case #Hist_Red       : If c <> 0 : Continue : EndIf
          Case #Hist_Green     : If c <> 1 : Continue : EndIf
          Case #Hist_Blue      : If c <> 2 : Continue : EndIf
          Case #Hist_Alpha     : If c <> 3 : Continue : EndIf
          Case #Hist_Luminance : If c <> 4 : Continue : EndIf
        EndSelect
        For i = 0 To 255
          If Hist_Count(c, i) > biggest : biggest = Hist_Count(c, i) : EndIf
        Next
      Next
      Select mode
        Case #Hist_RGB
          Hist_DrawChannel(0, RGBA(255, 60, 60, 140), biggest, left, top, width, height)
          Hist_DrawChannel(1, RGBA(60, 255, 60, 140), biggest, left, top, width, height)
          Hist_DrawChannel(2, RGBA(80, 120, 255, 140), biggest, left, top, width, height)
          c = 4                                     ; statistiek over de helderheid
        Case #Hist_Red       : Hist_DrawChannel(0, RGBA(255, 60, 60, 255), biggest, left, top, width, height) : c = 0
        Case #Hist_Green     : Hist_DrawChannel(1, RGBA(60, 255, 60, 255), biggest, left, top, width, height) : c = 1
        Case #Hist_Blue      : Hist_DrawChannel(2, RGBA(80, 120, 255, 255), biggest, left, top, width, height) : c = 2
        Case #Hist_Luminance : Hist_DrawChannel(4, RGBA(230, 230, 230, 255), biggest, left, top, width, height) : c = 4
        Case #Hist_Alpha     : Hist_DrawChannel(3, RGBA(200, 200, 200, 255), biggest, left, top, width, height) : c = 3
      EndSelect
      DrawingMode(#PB_2DDrawing_Transparent)
      For i = 0 To 4                                ; schaalverdeling 0, 64, 128, 192, 255
        x = left + i * 64 * width / 256
        LineXY(x, top + height, x, top + height + 4, RGB(150, 150, 150))
        DrawText(x - 8 - 14 * Bool(i = 4), top + height + 6, Str(i * 64 - Bool(i = 4)), RGB(180, 180, 180))
      Next
      ; Statistiek van het gekozen kanaal
      total = 0 : sum = 0 : lowest = -1 : highest = 0
      For i = 0 To 255
        If Hist_Count(c, i) > 0
          If lowest < 0 : lowest = i : EndIf
          highest = i
        EndIf
        total + Hist_Count(c, i)
        sum + Hist_Count(c, i) * i
      Next
      If total > 0
        text = "Mean: " + StrD(sum / total, 1) + "   Min: " + Str(lowest) + "   Max: " + Str(highest) + "   Pixels: " + Str(Hist_Pixels)
        If mode = #Hist_RGB
          text = "(luminance) " + text
        EndIf
        If Hist_Transparent > 0 And mode <> #Hist_Alpha
          text + "   (" + Str(Hist_Transparent) + " transparent pixels not counted)"
        EndIf
      EndIf
    EndIf
    StopDrawing()
  EndIf
  SetGadgetText(Hist_Text, text)
EndProcedure

Procedure Hist_ComboChanged()
  Hist_Draw()
EndProcedure

Procedure Hist_LogChanged()
  Hist_Log = GetGadgetState(Hist_LogBox)
  Hist_Draw()
EndProcedure

Procedure Hist_Closed()
  UnbindEvent(#PB_Event_CloseWindow, @Hist_Closed(), Hist_Window)
  CloseWindow(Hist_Window)
  Hist_Window = 0
EndProcedure

; Vult de keuzelijst; de HDR-keuze staat er alleen bij een HDR-texture in.
Procedure Hist_FillCombo()
  Protected old.i = -1
  If GetGadgetState(Hist_Combo) >= 0
    old = GetGadgetItemData(Hist_Combo, GetGadgetState(Hist_Combo))
  EndIf
  ClearGadgetItems(Hist_Combo)
  AddGadgetItem(Hist_Combo, -1, "RGB")       : SetGadgetItemData(Hist_Combo, 0, #Hist_RGB)
  AddGadgetItem(Hist_Combo, -1, "Red")       : SetGadgetItemData(Hist_Combo, 1, #Hist_Red)
  AddGadgetItem(Hist_Combo, -1, "Green")     : SetGadgetItemData(Hist_Combo, 2, #Hist_Green)
  AddGadgetItem(Hist_Combo, -1, "Blue")      : SetGadgetItemData(Hist_Combo, 3, #Hist_Blue)
  AddGadgetItem(Hist_Combo, -1, "Luminance") : SetGadgetItemData(Hist_Combo, 4, #Hist_Luminance)
  AddGadgetItem(Hist_Combo, -1, "Alpha")     : SetGadgetItemData(Hist_Combo, 5, #Hist_Alpha)
  If Hist_IsHDR
    AddGadgetItem(Hist_Combo, -1, "HDR brightness (stops)") : SetGadgetItemData(Hist_Combo, 6, #Hist_HdrStops)
  EndIf
  ; Vorige keuze terugzetten als die nog bestaat
  If old >= 0 And old < CountGadgetItems(Hist_Combo)
    SetGadgetState(Hist_Combo, old)
  Else
    SetGadgetState(Hist_Combo, 0)
  EndIf
EndProcedure

; Werkt het histogram bij voor een (nieuw) plaatje, als het venster open is.
; ExposureEV is de huidige HDR-belichting; daaruit volgt het witpunt.
Procedure Histogram_Update(Image.i, *Info.TexInfo, ExposureEV.d)
  If Not IsWindow(Hist_Window) Or Image = 0
    ProcedureReturn
  EndIf
  Hist_WhitePoint = -ExposureEV
  Hist_Compute(Image, *Info)
  Hist_FillCombo()
  SetWindowTitle(Hist_Window, "Histogram - " + *Info\FormatName)
  Hist_Draw()
EndProcedure

; Opent het histogramvenster (of brengt het naar voren als het al open is).
Procedure Histogram_Open(Image.i, *Info.TexInfo, ExposureEV.d, ParentID.i)
  If Not IsWindow(Hist_Window)
    Hist_Window = OpenWindow(#PB_Any, 0, 0, 680, 330, "Histogram", #PB_Window_SystemMenu | #PB_Window_WindowCentered, ParentID)
    If Hist_Window = 0
      ProcedureReturn
    EndIf
    Hist_Combo  = ComboBoxGadget(#PB_Any, 8, 8, 220, 24)
    Hist_LogBox = CheckBoxGadget(#PB_Any, 240, 8, 200, 24, "Logarithmic scale")
    SetGadgetState(Hist_LogBox, Hist_Log)
    BindGadgetEvent(Hist_LogBox, @Hist_LogChanged())
    Hist_Canvas = CanvasGadget(#PB_Any, 8, 40, 664, 250)
    Hist_Text   = TextGadget(#PB_Any, 8, 298, 664, 24, "")
    BindGadgetEvent(Hist_Combo, @Hist_ComboChanged(), #PB_EventType_Change)
    BindEvent(#PB_Event_CloseWindow, @Hist_Closed(), Hist_Window)
  EndIf
  Histogram_Update(Image, *Info, ExposureEV)
  SetActiveWindow(Hist_Window)
EndProcedure
