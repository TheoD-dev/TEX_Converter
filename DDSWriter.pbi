; DDSWriter.pbi - slaat een plaatje op als DDS ("DirectDraw Surface")
;
; DDS is het textureformaat dat bijna alle games en engines lezen. Het bestand bestaat uit:
;   "DDS "      - herkenningsteken
;   124 bytes   - kop: maten, aantal mipmaps, en het pixelformaat (DXT1, DXT5, ATI2/BC5 of 32-bit)
;   pixels      - eerst het grootste plaatje, dan elke keer half zo groot (mipmaps) tot 1 x 1
;
; Formaten:
;   DXT1  - 4 bits per pixel, geen transparantie (zoals SS3 "compressed opaque")
;   DXT5  - 8 bits per pixel, met transparantie (zoals SS3 "compressed translucent")
;   BC5   - 8 bits per pixel, alleen rood en groen: voor normal maps (in DDS heet dat "ATI2")
;   BGRA  - 32 bits per pixel, niet ingepakt: geen kwaliteitsverlies, maar 4 tot 8 keer groter

XIncludeFile "DXTEncode.pbi"    ; DXTE_WriteLevel() - de DXT-encoder
XIncludeFile "Resize.pbi"       ; RSZ_Halve() - voor de mipmaps

Enumeration DDSFormat
  #DDS_DXT1
  #DDS_DXT5
  #DDS_BC5
  #DDS_BGRA
EndEnumeration

; Maakt een 4-letterige code (zoals "DXT1") als getal, zoals hij in de DDS-kop staat.
Procedure.l DDS_FourCC(Text.s)
  ProcedureReturn Asc(Mid(Text, 1, 1)) | Asc(Mid(Text, 2, 1)) << 8 | Asc(Mid(Text, 3, 1)) << 16 | Asc(Mid(Text, 4, 1)) << 24
EndProcedure

; Schrijft één mipmap-niveau als 32-bit B,G,R,A.
Procedure.i DDS_WriteBGRA(File.i, Image.i)
  Protected w.i = ImageWidth(Image), h.i = ImageHeight(Image), x.i, y.i, c.i, *line
  *line = AllocateMemory(w * 4)
  If StartDrawing(ImageOutput(Image))
    DrawingMode(#PB_2DDrawing_AllChannels)
    For y = 0 To h - 1
      For x = 0 To w - 1
        c = Point(x, y)
        PokeA(*line + x * 4, Blue(c)) : PokeA(*line + x * 4 + 1, Green(c))
        PokeA(*line + x * 4 + 2, Red(c)) : PokeA(*line + x * 4 + 3, Alpha(c))
      Next
      WriteData(File, *line, w * 4)
    Next
    StopDrawing()
  EndIf
  FreeMemory(*line)
  ProcedureReturn w * h * 4
EndProcedure

; Slaat Image op als DDS. Format: #DDS_DXT1, #DDS_DXT5, #DDS_BC5 of #DDS_BGRA.
; Mipmaps = #True: ook alle kleinere versies opslaan (dat willen games meestal).
; Geeft #True terug als het gelukt is.
Procedure.i DDS_Save(Image.i, FileName.s, Format.i, Mipmaps.i = #True)
  Protected w.i, h.i, levels.i, file.i, i.i, flags.l, caps.l, linear.i, level.i, next_.i, lw.i, lh.i

  If IsImage(Image) = 0
    ProcedureReturn #False
  EndIf
  w = ImageWidth(Image) : h = ImageHeight(Image)

  ; Aantal mipmap-niveaus: tot beide zijden 1 zijn
  levels = 1
  If Mipmaps
    lw = w : lh = h
    While lw > 1 Or lh > 1
      lw = lw / 2 : If lw < 1 : lw = 1 : EndIf
      lh = lh / 2 : If lh < 1 : lh = 1 : EndIf
      levels + 1
    Wend
  EndIf

  ; Grootte van het grootste niveau (staat in de kop)
  Select Format
    Case #DDS_DXT1 : linear = ((w + 3) / 4) * ((h + 3) / 4) * 8
    Case #DDS_BGRA : linear = w * 4                    ; bij niet ingepakt: bytes per regel
    Default        : linear = ((w + 3) / 4) * ((h + 3) / 4) * 16
  EndSelect

  file = CreateFile(#PB_Any, FileName)
  If file = 0
    ProcedureReturn #False
  EndIf

  ; --- Kop ---
  WriteString(file, "DDS ", #PB_Ascii)
  flags = $1 | $2 | $4 | $1000                         ; CAPS, HEIGHT, WIDTH, PIXELFORMAT
  If Format = #DDS_BGRA : flags | $8 : Else : flags | $80000 : EndIf   ; PITCH of LINEARSIZE
  If levels > 1 : flags | $20000 : EndIf               ; MIPMAPCOUNT
  WriteLong(file, 124)                                 ; grootte van de kop
  WriteLong(file, flags)
  WriteLong(file, h)
  WriteLong(file, w)
  WriteLong(file, linear)
  WriteLong(file, 0)                                   ; diepte (alleen voor 3D-textures)
  WriteLong(file, levels)
  For i = 1 To 11 : WriteLong(file, 0) : Next          ; gereserveerd
  ; Pixelformaat (32 bytes)
  WriteLong(file, 32)
  If Format = #DDS_BGRA
    WriteLong(file, $41)                               ; RGB + ALPHAPIXELS
    WriteLong(file, 0)
    WriteLong(file, 32)                                ; bits per pixel
    WriteLong(file, $00FF0000)                         ; waar rood zit
    WriteLong(file, $0000FF00)                         ; groen
    WriteLong(file, $000000FF)                         ; blauw
    WriteLong(file, $FF000000)                         ; alfa
  Else
    WriteLong(file, $4)                                ; FOURCC: het formaat staat in de 4 letters
    Select Format
      Case #DDS_DXT1 : WriteLong(file, DDS_FourCC("DXT1"))
      Case #DDS_DXT5 : WriteLong(file, DDS_FourCC("DXT5"))
      Case #DDS_BC5  : WriteLong(file, DDS_FourCC("ATI2"))
    EndSelect
    For i = 1 To 5 : WriteLong(file, 0) : Next
  EndIf
  caps = $1000                                         ; TEXTURE
  If levels > 1 : caps | $8 | $400000 : EndIf          ; COMPLEX + MIPMAP
  WriteLong(file, caps)
  For i = 1 To 4 : WriteLong(file, 0) : Next           ; caps2..4 en gereserveerd

  ; --- Pixels: elk niveau half zo groot als het vorige ---
  level = CopyImage(Image, #PB_Any)
  For i = 1 To levels
    Select Format
      Case #DDS_DXT1 : DXTE_WriteLevel(file, level, #DXT1)
      Case #DDS_DXT5 : DXTE_WriteLevel(file, level, #DXT5)
      Case #DDS_BC5  : DXTE_WriteLevel(file, level, #BC5)
      Case #DDS_BGRA : DDS_WriteBGRA(file, level)
    EndSelect
    If i < levels
      next_ = RSZ_Halve(level, Bool(ImageWidth(level) > 1), Bool(ImageHeight(level) > 1))
      FreeImage(level)
      level = next_
    EndIf
  Next
  FreeImage(level)

  CloseFile(file)
  ProcedureReturn #True
EndProcedure

; Venster om het DDS-formaat te kiezen. Default wordt gekozen op basis van het plaatje.
; Geeft #True terug bij "OK"; de keuze staat dan in *Format en *Mipmaps.
Procedure.i DDS_Dialog(ParentWindow.i, HasAlpha.i, IsNormalMap.i, *Format.Integer, *Mipmaps.Integer)
  Protected win.i, combo.i, mips.i, ok.i, cancel.i, event.i, done.i, result.i

  win = OpenWindow(#PB_Any, 0, 0, 380, 150, "Save as DDS", #PB_Window_SystemMenu | #PB_Window_WindowCentered, WindowID(ParentWindow))
  If win = 0
    ProcedureReturn #False
  EndIf
  TextGadget(#PB_Any, 12, 16, 70, 20, "Format:")
  combo = ComboBoxGadget(#PB_Any, 80, 12, 288, 24)
  AddGadgetItem(combo, -1, "DXT1 / BC1 - compressed, no transparency")
  AddGadgetItem(combo, -1, "DXT5 / BC3 - compressed, with transparency")
  AddGadgetItem(combo, -1, "BC5 / ATI2 - compressed normal map (red + green)")
  AddGadgetItem(combo, -1, "BGRA 32-bit - uncompressed, no quality loss")
  If IsNormalMap
    SetGadgetState(combo, #DDS_BC5)
  ElseIf HasAlpha
    SetGadgetState(combo, #DDS_DXT5)
  Else
    SetGadgetState(combo, #DDS_DXT1)
  EndIf
  mips = CheckBoxGadget(#PB_Any, 80, 48, 288, 24, "Generate mipmaps (recommended for games)")
  SetGadgetState(mips, #True)
  ok = ButtonGadget(#PB_Any, 196, 110, 80, 28, "OK", #PB_Button_Default)
  cancel = ButtonGadget(#PB_Any, 288, 110, 80, 28, "Cancel")
  AddKeyboardShortcut(win, #PB_Shortcut_Escape, 2)
  AddKeyboardShortcut(win, #PB_Shortcut_Return, 1)
  DisableWindow(ParentWindow, #True)

  Repeat
    event = WaitWindowEvent()
    If EventWindow() <> win : Continue : EndIf
    Select event
      Case #PB_Event_CloseWindow
        done = #True
      Case #PB_Event_Menu
        If EventMenu() = 1 : result = #True : EndIf
        done = #True
      Case #PB_Event_Gadget
        If EventGadget() = ok : result = #True : done = #True : EndIf
        If EventGadget() = cancel : done = #True : EndIf
    EndSelect
  Until done
  If result
    *Format\i = GetGadgetState(combo)
    *Mipmaps\i = GetGadgetState(mips)
  EndIf

  DisableWindow(ParentWindow, #False)
  CloseWindow(win)
  SetActiveWindow(ParentWindow)
  ProcedureReturn result
EndProcedure
