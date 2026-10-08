; TexReaderSE2.pbi - leest Serious Sam 2 .tex-bestanden (CStaticTexture)
;
; Opbouw (zie TEX-herkenning-SE1-SE2.md):
;   offset 0   "CTSEMETA" - Croteams algemene opslagformaat
;   offset 16  LONG lengte + versietekst, bijv. "$Version: Serious Sam 2; 2.070.00:..."
;   daarna     beschrijving van alle datatypes (o.a. de klassenaam "CStaticTexture")
;   daarna     "OBJS" met de objecten. Rond de chunk "STAR" staan de texturegegevens:
;                STAR-16 breedte, STAR-12 hoogte, STAR-8 vlaggen, STAR-4 formaat (allemaal LONG)
;                "STAR" + LONG lengte + zlib-ingepakte pixeldata
;                daarna LONG U-wrapping, LONG V-wrapping, COLOR randkleur
;
; Niet-gecomprimeerde formaten bewaren het originele plaatje als B,G,R of B,G,R,A
; (alleen het grootste niveau). Gecomprimeerde formaten bewaren DXT1/DXT3/DXT5 met alle mipmaps.
;
XIncludeFile "TexInfo.pbi"   ; de structuur TexInfo
XIncludeFile "DXT.pbi"       ; DXT_Decode() voor de gecomprimeerde formaten

UseZipPacker()     ; voor UncompressMemory(): het uitpakken van de zlib-data

; Namen zoals in Serious Editor 2.0
Procedure.s TEXSE2_FormatName(Format.i)
  Select Format
    Case 0  : ProcedureReturn "opaque (32-bit)"
    Case 1  : ProcedureReturn "translucent (32-bit)"
    Case 2  : ProcedureReturn "opaque (16-bit)"
    Case 4  : ProcedureReturn "translucent (16-bit)"
    Case 5  : ProcedureReturn "grayscale translucent (16-bit)"
    Case 6  : ProcedureReturn "grayscale opaque (8-bit)"
    Case 7  : ProcedureReturn "compressed opaque (4-bit, DXT1)"
    Case 8  : ProcedureReturn "compressed translucent (8-bit, DXT3)"
    Case 9  : ProcedureReturn "compressed alpha (8-bit, DXT5)"
    Case 11 : ProcedureReturn "alpha only (8-bit)"
  EndSelect
  ProcedureReturn "unknown format " + Str(Format)
EndProcedure

Procedure.s TEXSE2_WrapName(Wrap.i)
  Select Wrap
    Case $50 : ProcedureReturn "repeat"
    Case $51 : ProcedureReturn "clamp to edge"
    Case $52 : ProcedureReturn "clamp to border"
  EndSelect
  ProcedureReturn "unknown (" + Hex(Wrap) + ")"
EndProcedure

Procedure.s TEXSE2_FlagNames(Flags.i)
  Protected text.s
  If Flags & $01 : text + ", mipmaps"  : EndIf
  If Flags & $04 : text + ", constant" : EndIf
  If Flags & $08 : text + ", resident" : EndIf
  If Flags & $40 : text + ", fastDXTc" : EndIf
  If text = ""
    ProcedureReturn "none"
  EndIf
  ProcedureReturn Mid(text, 3)        ; de eerste ", " weghalen
EndProcedure

; Zoekt een tekst van 4 of meer letters in het geheugen. Geeft de positie terug of -1.
Procedure.i TEXSE2_Find(*Mem, Size.i, Start.i, Text.s)
  Protected i.i, length.i = Len(Text)
  For i = Start To Size - length
    If PeekS(*Mem + i, length, #PB_Ascii) = Text
      ProcedureReturn i
    EndIf
  Next
  ProcedureReturn -1
EndProcedure

; Maakt van een SE2-bestand (al in het geheugen) een 32-bit image en vult *Info.
; Geeft het image-nummer terug, of 0 als het mislukt (de reden staat dan in *Info\Error).
Procedure.i TEXSE2_Decode(*Mem, Size.i, *Info.TexInfo)
  Protected length.i, objs.i, star.i, packedSize.i, flags.i, format.i, wrapU.i, wrapV.i
  Protected *raw, rawSize.i, rawMax.i, image.i, x.i, y.i, offset.i, bpp.i, dxtType.i

  *Info\Engine = 2

  ; --- Versietekst ---
  length = PeekL(*Mem + 16)
  If length > 0 And length < 1000 And 20 + length <= Size
    *Info\EngineVersion = RemoveString(PeekS(*Mem + 20, length, #PB_Ascii), "$Version: ")
  EndIf

  ; --- Soort texture: voorlopig alleen CStaticTexture ---
  If TEXSE2_Find(*Mem, Size, 0, "CStaticTexture") < 0
    *Info\Error = "This Serious Sam 2 file is not a CStaticTexture (other kinds are not supported yet)."
    ProcedureReturn 0
  EndIf

  ; --- De texturegegevens staan rond de chunk STAR (na OBJS, het begin van de objecten) ---
  objs = TEXSE2_Find(*Mem, Size, 0, "OBJS")
  If objs < 0
    *Info\Error = "Unknown Serious Sam 2 layout: OBJS chunk missing."
    ProcedureReturn 0
  EndIf
  star = TEXSE2_Find(*Mem, Size, objs, "STAR")
  If star < 16 Or star + 8 > Size
    *Info\Error = "Unknown Serious Sam 2 layout: STAR chunk missing."
    ProcedureReturn 0
  EndIf

  *Info\Width  = PeekL(*Mem + star - 16)
  *Info\Height = PeekL(*Mem + star - 12)
  flags        = PeekL(*Mem + star - 8)
  format       = PeekL(*Mem + star - 4)
  packedSize   = PeekL(*Mem + star + 4)
  *Info\Flags  = flags
  *Info\Frames = 1
  *Info\FormatName = TEXSE2_FormatName(format)

  If *Info\Width < 1 Or *Info\Height < 1 Or *Info\Width > 16384 Or *Info\Height > 16384
    *Info\Error = "Invalid dimensions: " + Str(*Info\Width) + " x " + Str(*Info\Height)
    ProcedureReturn 0
  EndIf
  If packedSize < 1 Or star + 8 + packedSize > Size
    *Info\Error = "The packed image data is incomplete."
    ProcedureReturn 0
  EndIf

  ; Na de pixeldata: wrapping en randkleur
  If star + 8 + packedSize + 8 <= Size
    wrapU = PeekL(*Mem + star + 8 + packedSize)
    wrapV = PeekL(*Mem + star + 8 + packedSize + 4)
  EndIf
  *Info\Note = "Flags: " + TEXSE2_FlagNames(flags) + "   U: " + TEXSE2_WrapName(wrapU) + "   V: " + TEXSE2_WrapName(wrapV)

  ; --- Pixeldata uitpakken (zlib) ---
  ; Het grootste mogelijke resultaat: 4 bytes per pixel plus ruimte voor mipmaps
  rawMax = *Info\Width * *Info\Height * 4 * 2 + 1024
  *raw = AllocateMemory(rawMax)
  If *raw = 0
    *Info\Error = "Not enough memory for the image."
    ProcedureReturn 0
  EndIf
  rawSize = UncompressMemory(*Mem + star + 8, packedSize, *raw, rawMax, #PB_PackerPlugin_Zip)
  If rawSize <= 0
    FreeMemory(*raw)
    *Info\Error = "The packed image data could not be unpacked."
    ProcedureReturn 0
  EndIf

  ; --- Pixels omzetten naar een image ---
  Select format
    Case 7, 8, 9
      ; Gecomprimeerd: DXT
      Select format
        Case 7 : dxtType = #DXT1
        Case 8 : dxtType = #DXT3
        Case 9 : dxtType = #DXT5
      EndSelect
      *Info\HasAlpha = Bool(format <> 7)
      *Info\BytesPerPixel = 4
      image = DXT_Decode(*raw, rawSize, *Info\Width, *Info\Height, dxtType)
      If image = 0
        *Info\Error = "The DXT data is incomplete."
      EndIf

    Default
      ; Niet gecomprimeerd: aan de grootte zien we of het B,G,R of B,G,R,A is
      If rawSize >= *Info\Width * *Info\Height * 4
        bpp = 4
      ElseIf rawSize >= *Info\Width * *Info\Height * 3
        bpp = 3
      Else
        FreeMemory(*raw)
        *Info\Error = "The image data is smaller than expected for " + *Info\FormatName + "."
        ProcedureReturn 0
      EndIf
      *Info\BytesPerPixel = bpp
      *Info\HasAlpha = Bool(bpp = 4)

      image = CreateImage(#PB_Any, *Info\Width, *Info\Height, 32, #PB_Image_Transparent)
      If image And StartDrawing(ImageOutput(image))
        DrawingMode(#PB_2DDrawing_AllChannels)
        offset = 0
        For y = 0 To *Info\Height - 1
          For x = 0 To *Info\Width - 1
            ; Let op: SE2 slaat de kleuren op als B,G,R(,A), dus andersom dan SE1
            If bpp = 4
              Plot(x, y, RGBA(PeekA(*raw + offset + 2), PeekA(*raw + offset + 1), PeekA(*raw + offset), PeekA(*raw + offset + 3)))
            Else
              Plot(x, y, RGBA(PeekA(*raw + offset + 2), PeekA(*raw + offset + 1), PeekA(*raw + offset), 255))
            EndIf
            offset + bpp
          Next
        Next
        StopDrawing()
      ElseIf image = 0
        *Info\Error = "Not enough memory for the image."
      EndIf
  EndSelect

  FreeMemory(*raw)
  ProcedureReturn image
EndProcedure
