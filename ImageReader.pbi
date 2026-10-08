; ImageReader.pbi - opent gewone beeldbestanden (dus geen .tex), zodat je ze ook kunt bekijken
; en omzetten: PNG, TGA, BMP, JPG, TIFF, PCX, DDS en Radiance HDR.
;
; PureBasic kan zelf PNG, TGA, BMP, JPG en TIFF lezen. Voor deze formaten hebben we toch iets eigens:
;   TGA  - PureBasic's TGA-lezer leest 32-bit TGA (met transparantie) in Linux verkeerd in.
;   PCX  - PureBasic kan geen PCX lezen. Ondersteund: 8-bit met palet, 24-bit en 32-bit.
;   HDR  - PureBasic kan geen .hdr lezen. De RGBE-data wordt bewaard (dus opnieuw opslaan als
;          .hdr is verliesvrij) en net als een SE3-HDR-texture met de belichting getoond.
;   TIFF - PureBasic's TIFF-lezer rekent transparantie om ("voorvermenigvuldigd"), waardoor
;          halfdoorzichtige pixels donkerder worden. Eenvoudige, niet-ingepakte TIFF's (zoals
;          TIFFWriter.pbi ze maakt) lezen we daarom zelf; andere TIFF's via PureBasic.

XIncludeFile "TexInfo.pbi"
XIncludeFile "TexReaderSE3.pbi"     ; TEXSE3_ToneMap() en de HDR-belichting
XIncludeFile "DXT.pbi"              ; DXT_Decode() voor DDS

UsePNGImageDecoder()
UseJPEGImageDecoder()
UseTGAImageDecoder()
UseTIFFImageDecoder()     ; als laatste: anders geeft de TIFF-lezer een foutregel bij elk TGA-bestand

; Kijkt of een 32-bit image ergens transparantie heeft (alfa kleiner dan 255).
Procedure.i IMG_HasAlpha(Image.i)
  Protected x.i, y.i, found.i
  If ImageDepth(Image) < 32
    ProcedureReturn #False
  EndIf
  If StartDrawing(ImageOutput(Image))
    DrawingMode(#PB_2DDrawing_AllChannels)
    For y = 0 To ImageHeight(Image) - 1
      For x = 0 To ImageWidth(Image) - 1
        If Alpha(Point(x, y)) < 255
          found = #True
          Break 2
        EndIf
      Next
    Next
    StopDrawing()
  EndIf
  ProcedureReturn found
EndProcedure

; Zet een image om naar 32-bit (zoals de .tex-lezers het maken), zodat de rest van de app
; altijd hetzelfde soort image krijgt. Het oude image wordt vrijgegeven.
Procedure.i IMG_To32Bit(Image.i)
  Protected new.i
  If ImageDepth(Image) = 32
    ProcedureReturn Image
  EndIf
  new = CreateImage(#PB_Any, ImageWidth(Image), ImageHeight(Image), 32)
  If new And StartDrawing(ImageOutput(new))
    DrawImage(ImageID(Image), 0, 0)          ; zonder alfa: alles volledig dekkend
    StopDrawing()
  EndIf
  FreeImage(Image)
  ProcedureReturn new
EndProcedure

; ---------------------------------------------------------------------------------------------
; PCX
; ---------------------------------------------------------------------------------------------
Procedure.i IMG_LoadPCX(*Mem, Size.i, *Info.TexInfo)
  Protected width.i, height.i, planes.i, bpl.i, bits.i, pos.i, y.i, x.i, n.i, c.i, count.i, v.i
  Protected *line, image.i, *palette, r.i, g.i, b.i, a.i, packed.i

  If Size < 128 Or PeekA(*Mem) <> 10
    *Info\Error = "This is not a PCX file."
    ProcedureReturn 0
  EndIf
  bits   = PeekA(*Mem + 3)
  width  = PeekU(*Mem + 8) - PeekU(*Mem + 4) + 1
  height = PeekU(*Mem + 10) - PeekU(*Mem + 6) + 1
  planes = PeekA(*Mem + 65)
  bpl    = PeekU(*Mem + 66)
  If bits <> 8 Or Not (planes = 1 Or planes = 3 Or planes = 4) Or width < 1 Or height < 1 Or bpl < width
    *Info\Error = "This PCX type is not supported (only 8-bit palette, 24-bit and 32-bit)."
    ProcedureReturn 0
  EndIf
  If planes = 1
    ; Het palet (256 kleuren) staat aan het eind: een byte 12 en dan 768 bytes R,G,B
    If Size < 128 + 769 Or PeekA(*Mem + Size - 769) <> 12
      *Info\Error = "The PCX palette is missing."
      ProcedureReturn 0
    EndIf
    *palette = *Mem + Size - 768
  EndIf

  *Info\Width = width : *Info\Height = height
  *Info\BytesPerPixel = planes
  *Info\FormatName = "PiCture eXchange (" + Str(planes * 8) + "-bit)"
  *line = AllocateMemory(bpl * planes)
  image = CreateImage(#PB_Any, width, height, 32)
  If *line = 0 Or image = 0 Or StartDrawing(ImageOutput(image)) = 0
    If *line : FreeMemory(*line) : EndIf
    *Info\Error = "Not enough memory for the image."
    ProcedureReturn 0
  EndIf
  DrawingMode(#PB_2DDrawing_AllChannels)

  ; Byte 2 zegt of het bestand is ingepakt: 1 = RLE (gebruikelijk), 0 = niet ingepakt
  ; (dat maken sommige programma's, bijv. bij PAL_Wall05.pcx: dan staan de bytes er gewoon).
  packed = Bool(PeekA(*Mem + 2) = 1)

  pos = 128
  count = 0                    ; hoeveel bytes van een herhaling er nog over zijn
  For y = 0 To height - 1
    If Not packed
      ; Niet ingepakt: de regel direct kopiëren
      If pos + bpl * planes <= Size
        CopyMemory(*Mem + pos, *line, bpl * planes)
      Else
        FillMemory(*line, bpl * planes, 0)    ; bestand te kort: rest zwart
      EndIf
      pos + bpl * planes
    EndIf
    ; Eén beeldregel uitpakken (alle kleurvlakken achter elkaar), zie PCX_WriteRun in PCXWriter.pbi.
    ; Let op: veel programma's laten een herhaling doorlopen tot in de volgende regel. Wat er van
    ; een herhaling overblijft (count) nemen we daarom mee naar de volgende regel.
    n = 0
    If Not packed
      n = bpl * planes                           ; al gekopieerd: het uitpakken overslaan
    EndIf
    While n < bpl * planes
      If count > 0
        PokeA(*line + n, v) : n + 1 : count - 1
        Continue
      EndIf
      If pos >= Size
        PokeA(*line + n, 0) : n + 1             ; bestand te kort: rest zwart
        Continue
      EndIf
      c = PeekA(*Mem + pos) : pos + 1
      If c >= $C0
        count = c & 63
        v = 0
        If pos < Size : v = PeekA(*Mem + pos) : pos + 1 : EndIf
      Else
        PokeA(*line + n, c) : n + 1
      EndIf
    Wend
    For x = 0 To width - 1
      If planes = 1
        v = PeekA(*line + x)
        r = PeekA(*palette + v * 3) : g = PeekA(*palette + v * 3 + 1) : b = PeekA(*palette + v * 3 + 2) : a = 255
      Else
        r = PeekA(*line + x) : g = PeekA(*line + bpl + x) : b = PeekA(*line + 2 * bpl + x)
        a = 255
        If planes = 4 : a = PeekA(*line + 3 * bpl + x) : EndIf
      EndIf
      Plot(x, y, RGBA(r, g, b, a))
    Next
  Next
  StopDrawing()
  FreeMemory(*line)
  *Info\HasAlpha = Bool(planes = 4 And IMG_HasAlpha(image))
  ProcedureReturn image
EndProcedure

; ---------------------------------------------------------------------------------------------
; TGA - eigen lezer. PureBasic's TGA-lezer leest 32-bit TGA's (met transparantie) in Linux
; verkeerd in (kleuren door elkaar, beeld verschoven). Daarom lezen we TGA zelf, dan werkt het
; overal hetzelfde. Ondersteund: ware kleuren (16, 24, 32 bit), grijs (8 bit) en met palet (8 bit),
; ongecomprimeerd en met RLE, en beide richtingen (eerste regel boven of onder).
; ---------------------------------------------------------------------------------------------
Procedure.i IMG_LoadTGA(*Mem, Size.i, *Info.TexInfo)
  Protected idLen.i, cmapType.i, imgType.i, cmapStart.i, cmapLen.i, cmapBits.i, width.i, height.i
  Protected bits.i, desc.i, topDown.i, rightLeft.i, bpp.i, cbpp.i, pos.i, *cmap, n.i, total.i
  Protected count.i, packet.i, i.i, x.i, y.i, image.i, v.i, r.i, g.i, b.i, a.i, *pix, *src, alphaBits.i

  If Size < 18
    *Info\Error = "This is not a TGA file."
    ProcedureReturn 0
  EndIf
  idLen    = PeekA(*Mem)
  cmapType = PeekA(*Mem + 1)
  imgType  = PeekA(*Mem + 2)
  cmapStart = PeekU(*Mem + 3)
  cmapLen  = PeekU(*Mem + 5)
  cmapBits = PeekA(*Mem + 7)
  width    = PeekU(*Mem + 12)
  height   = PeekU(*Mem + 14)
  bits     = PeekA(*Mem + 16)
  desc     = PeekA(*Mem + 17)
  topDown   = Bool(desc & $20)              ; bit 5: eerste regel is de bovenste
  rightLeft = Bool(desc & $10)              ; bit 4: van rechts naar links (zelden)
  alphaBits = desc & 15
  If width < 1 Or height < 1 Or Not (imgType = 1 Or imgType = 2 Or imgType = 3 Or imgType = 9 Or imgType = 10 Or imgType = 11)
    *Info\Error = "This TGA type is not supported (type " + Str(imgType) + ")."
    ProcedureReturn 0
  EndIf
  If Not (bits = 8 Or bits = 15 Or bits = 16 Or bits = 24 Or bits = 32)
    *Info\Error = "This TGA bit depth is not supported (" + Str(bits) + " bits)."
    ProcedureReturn 0
  EndIf
  bpp = (bits + 7) / 8
  pos = 18 + idLen
  ; Palet (bij type 1 en 9)
  If cmapType = 1
    cbpp = (cmapBits + 7) / 8
    *cmap = *Mem + pos
    pos + cmapLen * cbpp
  EndIf

  ; --- Alle pixelwaarden (zoals opgeslagen) eerst achter elkaar in *pix zetten ---
  total = width * height
  *pix = AllocateMemory(total * bpp)
  If *pix = 0
    *Info\Error = "Not enough memory for the image."
    ProcedureReturn 0
  EndIf
  If imgType >= 9
    ; RLE: een pakketbyte, bit 7 = herhaling (1 pixel, (byte & 127) + 1 keer), anders zoveel losse pixels
    n = 0
    While n < total And pos < Size
      packet = PeekA(*Mem + pos) : pos + 1
      count = (packet & 127) + 1
      If packet & 128
        For i = 1 To count
          If n < total And pos + bpp <= Size : CopyMemory(*Mem + pos, *pix + n * bpp, bpp) : EndIf
          n + 1
        Next
        pos + bpp
      Else
        For i = 1 To count
          If n < total And pos + bpp <= Size : CopyMemory(*Mem + pos, *pix + n * bpp, bpp) : EndIf
          n + 1 : pos + bpp
        Next
      EndIf
    Wend
  Else
    If pos + total * bpp > Size
      FreeMemory(*pix)
      *Info\Error = "The TGA image data is incomplete."
      ProcedureReturn 0
    EndIf
    CopyMemory(*Mem + pos, *pix, total * bpp)
  EndIf

  ; Sommige programma's zetten bij 32-bit het aantal alfabits in de kop op 0, terwijl de vierde
  ; byte wel transparantie bevat (bijv. 64x128-color-transparency.tga). Daarom: is er bij 32-bit
  ; ergens een alfa groter dan 0, dan gebruiken we die. Zijn ze allemaal 0, dan is het gewoon dekkend.
  If bpp = 4 And alphaBits = 0 And imgType <> 1 And imgType <> 9
    For i = 0 To total - 1
      If PeekA(*pix + i * 4 + 3) > 0 : alphaBits = 8 : Break : EndIf
    Next
  EndIf

  ; --- Omzetten naar een 32-bit image ---
  image = CreateImage(#PB_Any, width, height, 32, #PB_Image_Transparent)
  If image And StartDrawing(ImageOutput(image))
    DrawingMode(#PB_2DDrawing_AllChannels)
    For i = 0 To total - 1
      *src = *pix + i * bpp
      a = 255
      Select imgType
        Case 3, 11                           ; grijs
          r = PeekA(*src) : g = r : b = r
        Case 1, 9                            ; palet: de waarde is een plek in het palet
          v = PeekA(*src) - cmapStart
          If *cmap And v >= 0 And v < cmapLen
            *src = *cmap + v * cbpp
            If cbpp >= 3
              b = PeekA(*src) : g = PeekA(*src + 1) : r = PeekA(*src + 2)
              If cbpp = 4 : a = PeekA(*src + 3) : EndIf
            Else
              v = PeekU(*src)
              r = ((v >> 10) & 31) * 255 / 31 : g = ((v >> 5) & 31) * 255 / 31 : b = (v & 31) * 255 / 31
            EndIf
          Else
            r = 0 : g = 0 : b = 0
          EndIf
        Default                              ; ware kleuren: B,G,R(,A) of 16-bit 5-5-5(-1)
          If bpp = 2
            v = PeekU(*src)
            r = ((v >> 10) & 31) * 255 / 31 : g = ((v >> 5) & 31) * 255 / 31 : b = (v & 31) * 255 / 31
            If alphaBits = 1 And (v & $8000) = 0 : a = 0 : EndIf
          Else
            b = PeekA(*src) : g = PeekA(*src + 1) : r = PeekA(*src + 2)
            If bpp = 4 And alphaBits > 0 : a = PeekA(*src + 3) : EndIf
          EndIf
      EndSelect
      ; Plek in het plaatje: TGA begint standaard linksonder
      x = i % width : y = i / width
      If Not topDown : y = height - 1 - y : EndIf
      If rightLeft : x = width - 1 - x : EndIf
      Plot(x, y, RGBA(r, g, b, a))
    Next
    StopDrawing()
  EndIf
  FreeMemory(*pix)
  *Info\FormatName = "Truevision Graphics Adapter"
  *Info\BytesPerPixel = bpp
  *Info\HasAlpha = IMG_HasAlpha(image)
  ProcedureReturn image
EndProcedure

; ---------------------------------------------------------------------------------------------
; DDS (alleen het grootste mipmap-niveau): DXT1, DXT3, DXT5, ATI2/BC5 en 32-bit B,G,R,A
; ---------------------------------------------------------------------------------------------
Procedure.i IMG_LoadDDS(*Mem, Size.i, *Info.TexInfo)
  Protected width.i, height.i, pfFlags.i, fourCC.s, bits.i, image.i, x.i, y.i, *p, dxt.i

  If Size < 128 Or PeekS(*Mem, 4, #PB_Ascii) <> "DDS " Or PeekL(*Mem + 4) <> 124
    *Info\Error = "This is not a DDS file."
    ProcedureReturn 0
  EndIf
  height  = PeekL(*Mem + 12)
  width   = PeekL(*Mem + 16)
  pfFlags = PeekL(*Mem + 80)
  fourCC  = PeekS(*Mem + 84, 4, #PB_Ascii)
  bits    = PeekL(*Mem + 88)
  If width < 1 Or height < 1 Or width > 16384 Or height > 16384
    *Info\Error = "Invalid DDS dimensions."
    ProcedureReturn 0
  EndIf
  *Info\Width = width : *Info\Height = height

  If pfFlags & $4                              ; het formaat staat in de 4 letters
    Select fourCC
      Case "DXT1" : dxt = #DXT1
      Case "DXT3" : dxt = #DXT3
      Case "DXT5" : dxt = #DXT5
      Case "ATI2", "BC5U" : dxt = #BC5
      Default
        *Info\Error = "DDS format " + fourCC + " is not supported (only DXT1, DXT3, DXT5, ATI2/BC5 and 32-bit)."
        ProcedureReturn 0
    EndSelect
    image = DXT_Decode(*Mem + 128, Size - 128, width, height, dxt)
    If image = 0
      *Info\Error = "The DDS image data is incomplete."
      ProcedureReturn 0
    EndIf
    *Info\FormatName = "DirectDraw Surface (" + fourCC + ")"
    *Info\HasAlpha = Bool((dxt = #DXT3 Or dxt = #DXT5 Or dxt = #DXT1) And IMG_HasAlpha(image))
  ElseIf bits = 32 And PeekL(*Mem + 92) = $00FF0000 And PeekL(*Mem + 96) = $0000FF00 And PeekL(*Mem + 100) = $000000FF
    ; Niet ingepakt, 32-bit B,G,R,A
    If 128 + width * height * 4 > Size
      *Info\Error = "The DDS image data is incomplete."
      ProcedureReturn 0
    EndIf
    image = CreateImage(#PB_Any, width, height, 32)
    If image And StartDrawing(ImageOutput(image))
      DrawingMode(#PB_2DDrawing_AllChannels)
      *p = *Mem + 128
      For y = 0 To height - 1
        For x = 0 To width - 1
          If pfFlags & $1             ; ALPHAPIXELS: de vierde byte is transparantie
            Plot(x, y, RGBA(PeekA(*p + 2), PeekA(*p + 1), PeekA(*p), PeekA(*p + 3)))
          Else
            Plot(x, y, RGBA(PeekA(*p + 2), PeekA(*p + 1), PeekA(*p), 255))
          EndIf
          *p + 4
        Next
      Next
      StopDrawing()
    EndIf
    *Info\FormatName = "DirectDraw Surface (BGRA 32-bit)"
    *Info\HasAlpha = IMG_HasAlpha(image)
  Else
    *Info\Error = "This DDS pixel format is not supported."
    ProcedureReturn 0
  EndIf
  *Info\BytesPerPixel = 4
  ProcedureReturn image
EndProcedure

; ---------------------------------------------------------------------------------------------
; Radiance HDR
; ---------------------------------------------------------------------------------------------
Procedure.i IMG_LoadHDR(*Mem, Size.i, *Info.TexInfo)
  Protected pos.i, lineStart.i, text.s, width.i, height.i, y.i, x.i, c.i, count.i, v.i, *row
  Protected image.i, scale.d, factor.d, e.i, flipY.i
  Dim expFactor.d(255)

  ; --- Tekstkop: regels tot een lege regel, dan de regel met de maten ---
  If Size < 11 Or PeekS(*Mem, 2, #PB_Ascii) <> "#?"
    *Info\Error = "This is not a Radiance HDR file."
    ProcedureReturn 0
  EndIf
  Repeat
    lineStart = pos
    While pos < Size And PeekA(*Mem + pos) <> 10
      pos + 1
    Wend
    text = PeekS(*Mem + lineStart, pos - lineStart, #PB_Ascii)
    pos + 1
    If Left(text, 7) = "FORMAT=" And text <> "FORMAT=32-bit_rle_rgbe"
      *Info\Error = "Only RGBE HDR files are supported (" + text + ")."
      ProcedureReturn 0
    EndIf
  Until text = "" Or pos >= Size
  ; Maten, bijv. "-Y 512 +X 1024" (-Y = eerste regel is de bovenste; +Y = onderste)
  lineStart = pos
  While pos < Size And PeekA(*Mem + pos) <> 10
    pos + 1
  Wend
  text = PeekS(*Mem + lineStart, pos - lineStart, #PB_Ascii)
  pos + 1
  If StringField(text, 3, " ") <> "+X" Or (StringField(text, 1, " ") <> "-Y" And StringField(text, 1, " ") <> "+Y")
    *Info\Error = "This HDR orientation is not supported (" + text + ")."
    ProcedureReturn 0
  EndIf
  flipY  = Bool(StringField(text, 1, " ") = "+Y")
  height = Val(StringField(text, 2, " "))
  width  = Val(StringField(text, 4, " "))
  If width < 1 Or height < 1 Or width > 32768 Or height > 32768
    *Info\Error = "Invalid HDR dimensions: " + text
    ProcedureReturn 0
  EndIf

  ; --- Pixels uitpakken naar R,G,B,E (4 bytes per pixel) ---
  *Info\HdrData = AllocateMemory(width * height * 4)
  If *Info\HdrData = 0
    *Info\Error = "Not enough memory for the image."
    ProcedureReturn 0
  EndIf
  For y = 0 To height - 1
    If flipY
      *row = *Info\HdrData + (height - 1 - y) * width * 4
    Else
      *row = *Info\HdrData + y * width * 4
    EndIf
    If width >= 8 And width <= 32767 And pos + 4 <= Size And PeekA(*Mem + pos) = 2 And PeekA(*Mem + pos + 1) = 2 And PeekA(*Mem + pos + 2) < 128
      ; "Nieuw" rij-formaat: per kanaal stukjes. Teller > 128: herhaling van (teller - 128) keer
      ; dezelfde byte; anders volgen er zoveel losse bytes.
      pos + 4
      For c = 0 To 3
        x = 0
        While x < width And pos < Size
          count = PeekA(*Mem + pos) : pos + 1
          If count > 128
            count - 128
            v = PeekA(*Mem + pos) : pos + 1
            While count > 0 And x < width
              PokeA(*row + x * 4 + c, v) : x + 1 : count - 1
            Wend
          Else
            While count > 0 And x < width And pos < Size
              PokeA(*row + x * 4 + c, PeekA(*Mem + pos)) : pos + 1 : x + 1 : count - 1
            Wend
          EndIf
        Wend
      Next
    Else
      ; Gewoon achter elkaar
      If pos + width * 4 > Size
        Break
      EndIf
      CopyMemory(*Mem + pos, *row, width * 4)
      pos + width * 4
    EndIf
  Next

  ; --- Tonen met de HDR-belichting (E telt hier in hele stops) ---
  *Info\Width = width : *Info\Height = height
  *Info\IsHDR = #True
  *Info\BytesPerPixel = 4
  *Info\FormatName = "Radiance High Dynamic Range"
  scale = Pow(2, TEXSE3_ExposureEV)
  For e = 0 To 255
    expFactor(e) = Pow(2, e - 128) / 256
  Next
  image = CreateImage(#PB_Any, width, height, 32)
  If image And StartDrawing(ImageOutput(image))
    DrawingMode(#PB_2DDrawing_AllChannels)
    For y = 0 To height - 1
      For x = 0 To width - 1
        *row = *Info\HdrData + (y * width + x) * 4
        e = PeekA(*row + 3)
        If e = 0
          Plot(x, y, RGBA(0, 0, 0, 255))
        Else
          factor = expFactor(e)
          Plot(x, y, RGBA(TEXSE3_ToneMap((PeekA(*row) + 0.5) * factor, scale), TEXSE3_ToneMap((PeekA(*row + 1) + 0.5) * factor, scale), TEXSE3_ToneMap((PeekA(*row + 2) + 0.5) * factor, scale), 255))
        EndIf
      Next
    Next
    StopDrawing()
  EndIf
  *Info\Note = "HDR exposure: " + StrD(TEXSE3_ExposureEV, 1) + " EV"
  If TEXSE3_ToneMode = #TEXSE3_ToneFilmic
    *Info\Note + ", filmic"
  Else
    *Info\Note + ", editor (clip)"
  EndIf
  ProcedureReturn image
EndProcedure

; ---------------------------------------------------------------------------------------------
; TIFF (alleen de eenvoudige soort; anders geeft dit 0 en gebruiken we PureBasic's lezer)
; ---------------------------------------------------------------------------------------------
Procedure.i IMG_LoadSimpleTIFF(*Mem, Size.i, *Info.TexInfo)
  Protected ifd.i, count.i, i.i, tag.i, type.i, num.i, value.i, *e
  Protected width.i, height.i, spp.i = 1, compression.i = 1, photometric.i = -1, planar.i = 1
  Protected bitsOK.i = #True, offsetsPos.i, offsetsType.i, strips.i, rowsPerStrip.i
  Protected image.i, s.i, start.i, y.i, x.i, row.i, *p

  If Size < 8 Or PeekS(*Mem, 2, #PB_Ascii) <> "II" Or PeekU(*Mem + 2) <> 42
    ProcedureReturn 0                        ; geen little-endian TIFF: laat PureBasic het doen
  EndIf
  ifd = PeekL(*Mem + 4)
  If ifd < 8 Or ifd + 2 > Size
    ProcedureReturn 0
  EndIf
  count = PeekU(*Mem + ifd)
  For i = 0 To count - 1
    *e = *Mem + ifd + 2 + i * 12
    If ifd + 2 + i * 12 + 12 > Size : ProcedureReturn 0 : EndIf
    tag = PeekU(*e) : type = PeekU(*e + 2) : num = PeekL(*e + 4)
    If type = 3 : value = PeekU(*e + 8) : Else : value = PeekL(*e + 8) : EndIf
    Select tag
      Case 256 : width = value
      Case 257 : height = value
      Case 258                               ; bits per kanaal: alles moet 8 zijn
        If num = 1
          bitsOK = Bool(value = 8)
        ElseIf num = 2 And type = 3
          bitsOK = Bool(PeekU(*e + 8) = 8 And PeekU(*e + 10) = 8)
        Else
          s = PeekL(*e + 8)
          For x = 0 To num - 1
            If s + x * 2 + 2 > Size Or PeekU(*Mem + s + x * 2) <> 8 : bitsOK = #False : EndIf
          Next
        EndIf
      Case 259 : compression = value
      Case 262 : photometric = value
      Case 273 : offsetsPos = *e + 8 - *Mem : offsetsType = type : strips = num
      Case 277 : spp = value
      Case 278 : rowsPerStrip = value
      Case 284 : planar = value
    EndSelect
  Next
  If width < 1 Or height < 1 Or compression <> 1 Or photometric <> 2 Or planar <> 1 Or Not bitsOK Or (spp <> 3 And spp <> 4) Or strips < 1
    ProcedureReturn 0                        ; ingewikkelder TIFF: laat PureBasic het doen
  EndIf
  If rowsPerStrip < 1 Or rowsPerStrip > height : rowsPerStrip = height : EndIf
  ; Staan de strip-plekken in het veld zelf of ergens anders in het bestand?
  If (offsetsType = 3 And strips > 2) Or (offsetsType = 4 And strips > 1)
    offsetsPos = PeekL(*Mem + offsetsPos)
  EndIf

  image = CreateImage(#PB_Any, width, height, 32)
  If image = 0 Or StartDrawing(ImageOutput(image)) = 0
    ProcedureReturn 0
  EndIf
  DrawingMode(#PB_2DDrawing_AllChannels)
  For y = 0 To height - 1
    s = y / rowsPerStrip                     ; in welke strip zit deze regel?
    If s >= strips : Break : EndIf
    If offsetsType = 3 : start = PeekU(*Mem + offsetsPos + s * 2) : Else : start = PeekL(*Mem + offsetsPos + s * 4) : EndIf
    row = y - s * rowsPerStrip
    *p = *Mem + start + row * width * spp
    If start + (row + 1) * width * spp > Size : Break : EndIf
    For x = 0 To width - 1
      If spp = 4
        Plot(x, y, RGBA(PeekA(*p), PeekA(*p + 1), PeekA(*p + 2), PeekA(*p + 3)))
      Else
        Plot(x, y, RGBA(PeekA(*p), PeekA(*p + 1), PeekA(*p + 2), 255))
      EndIf
      *p + spp
    Next
  Next
  StopDrawing()
  *Info\BytesPerPixel = spp
  ProcedureReturn image
EndProcedure

; ---------------------------------------------------------------------------------------------
; Opent een gewoon beeldbestand. Geeft een 32-bit image terug, of 0 (reden in *Info\Error).
; ---------------------------------------------------------------------------------------------
Procedure.i IMG_Load(FileName.s, *Info.TexInfo)
  Protected ext.s, file.i, size.i, *mem, image.i

  ResetStructure(*Info, TexInfo)
  *Info\Engine = 0                           ; 0 = geen Serious Sam-texture
  *Info\Frames = 1
  ext = LCase(GetExtensionPart(FileName))

  If ext = "pcx" Or ext = "hdr" Or ext = "dds" Or ext = "tga" Or ext = "tif" Or ext = "tiff"
    ; Deze formaten lezen we (deels) zelf: eerst het hele bestand in het geheugen
    file = ReadFile(#PB_Any, FileName)
    If file = 0
      *Info\Error = "The file cannot be opened."
      ProcedureReturn 0
    EndIf
    size = Lof(file)
    If size > 0
      *mem = AllocateMemory(size)
      If *mem : ReadData(file, *mem, size) : EndIf
    EndIf
    CloseFile(file)
    If *mem = 0
      *Info\Error = "The file is empty or too large."
      ProcedureReturn 0
    EndIf
    Select ext
      Case "pcx" : image = IMG_LoadPCX(*mem, size, *Info)
      Case "hdr" : image = IMG_LoadHDR(*mem, size, *Info)
      Case "dds" : image = IMG_LoadDDS(*mem, size, *Info)
      Case "tga" : image = IMG_LoadTGA(*mem, size, *Info)
      Default
        image = IMG_LoadSimpleTIFF(*mem, size, *Info)
        If image
          *Info\FormatName = "Tagged Image File Format"
          *Info\HasAlpha = IMG_HasAlpha(image)
        EndIf
    EndSelect
    FreeMemory(*mem)
    If image Or (ext <> "tif" And ext <> "tiff")      ; TIFF niet gelukt: hieronder via PureBasic
      If image = 0 : TEX_FreeInfo(*Info) : EndIf
      If image
        *Info\Width = ImageWidth(image) : *Info\Height = ImageHeight(image)
      EndIf
      ProcedureReturn image
    EndIf
  EndIf

  ; --- PNG, TGA, BMP, JPG en ingewikkelder TIFF: PureBasic's eigen lezers ---
  image = LoadImage(#PB_Any, FileName)
  If image = 0
    *Info\Error = "This image format is not supported, or the file is damaged."
    ProcedureReturn 0
  EndIf
  *Info\BytesPerPixel = ImageDepth(image) / 8
  image = IMG_To32Bit(image)
  *Info\Width  = ImageWidth(image)
  *Info\Height = ImageHeight(image)
  *Info\HasAlpha = IMG_HasAlpha(image)
  Select ext
    Case "png"          : *Info\FormatName = "Portable Network Graphics"
    Case "tga"          : *Info\FormatName = "Truevision Graphics Adapter"
    Case "bmp"          : *Info\FormatName = "Microsoft BMP"
    Case "jpg", "jpeg"  : *Info\FormatName = "Joint Photographic Experts Group"
    Case "tif", "tiff"  : *Info\FormatName = "Tagged Image File Format"
                          *Info\Note = "Read with PureBasic's TIFF reader (semi-transparent pixels may look darker)"
    Default             : *Info\FormatName = UCase(ext) + " image"
  EndSelect
  ProcedureReturn image
EndProcedure
