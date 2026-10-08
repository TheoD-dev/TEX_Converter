; TexReader.pbi - leest Serious Sam .tex-bestanden
;
; TEX_Load() is de enige functie die het hoofdprogramma nodig heeft. Die kijkt naar de
; eerste bytes en kiest zelf: "TVER" = Serious Engine 1 (dit bestand),
; "CTSEMETA" (eventueel na een "SIGSTRM1"-handtekening) = Serious Engine 2 (TexReaderSE2.pbi)
; of Serious Engine 3 (TexReaderSE3.pbi), afhankelijk van de versietekst in het bestand.
;
; Serious Engine 1 (zie TEX-formaat-analyse.md):
;
; Versie 4, gewone texture:
;   offset  0  "TVER" + versie (LONG = 4)
;   offset  8  "TDAT" + vlaggen, mexBreedte, mexHoogte, mipNiveaus, firstMip, aantalFrames (allemaal LONG)
;   offset 36  "FRMS" + per frame alleen het grootste plaatje, 3 bytes (R,G,B) of 4 bytes (R,G,B,A) per pixel
;
; Versie 3 (ouder formaat):
;   offset  0  "TVER" + versie (LONG = 3)
;   offset  8  "TDAT" + vlaggen, mexBreedte, mexHoogte, mipNiveaus, mipNiveaus2, firstMip, frameGrootte, aantalFrames
;   offset 44  "FRMS" + per frame ALLE mipmaps, 2 bytes per pixel (16-bit kleur: 5 bits rood, 5 groen, 5 blauw)
;
; Versie 4, effect-texture (water, vuur, ...):
;   offset 36  "FXDT" + effecttype, bufferBreedte, bufferHoogte, gegevens van de effectbronnen
;   daarna     "FXBF" + rekenbuffers (LONG per punt), "ANIM"-blok, "BAST" + "DFNM" + naam van de basistexture
;   Het echte beeld rekent het spel tijdens het spelen uit. Wij tonen de basistexture als die
;   naast het bestand staat, en anders de buffer als grijs plaatje.
;
; Alle bestanden eindigen met een "ANIM"-blok met animatiegegevens (niet nodig voor het tonen).

XIncludeFile "TexInfo.pbi"        ; de structuur TexInfo en de vlaggen #TEX_...
XIncludeFile "TexReaderSE2.pbi"   ; Serious Engine 2 (apart bestand, makkelijker te debuggen)
XIncludeFile "TexReaderSE3.pbi"   ; Serious Engine 3 (idem)

; Kijkt of er op een bepaalde plek in het geheugen een chunk-naam van 4 letters staat.
Procedure.i TEX_IsChunk(*Mem, Size.i, Offset.i, Id.s)
  If Offset < 0 Or Offset + 4 > Size
    ProcedureReturn #False
  EndIf
  ProcedureReturn Bool(PeekS(*Mem + Offset, 4, #PB_Ascii) = Id)
EndProcedure

; Zoekt vanaf Start naar een chunk-naam. Geeft de positie terug, of -1 als hij niet gevonden is.
Procedure.i TEX_FindChunk(*Mem, Size.i, Start.i, Id.s)
  Protected i.i
  For i = Start To Size - 4
    If TEX_IsChunk(*Mem, Size, i, Id)
      ProcedureReturn i
    EndIf
  Next
  ProcedureReturn -1
EndProcedure

; Rekent de mex-maten om naar pixels en controleert ze. Geeft "" terug als alles klopt.
Procedure.s TEX_SetSize(*Info.TexInfo, MexWidth.l, MexHeight.l)
  If *Info\FirstMip < 0 Or *Info\FirstMip > 31
    ProcedureReturn "Invalid firstMip value: " + Str(*Info\FirstMip)
  EndIf
  *Info\Width  = MexWidth  >> *Info\FirstMip     ; >> schuift de bits naar rechts (delen door 2^FirstMip)
  *Info\Height = MexHeight >> *Info\FirstMip
  If *Info\Width < 1 Or *Info\Height < 1 Or *Info\Width > 16384 Or *Info\Height > 16384
    ProcedureReturn "Invalid dimensions: " + Str(*Info\Width) + " x " + Str(*Info\Height)
  EndIf
  If *Info\Frames < 1
    ProcedureReturn "The file contains no frames."
  EndIf
  ProcedureReturn ""
EndProcedure

; Leest de gegevens van een effect-texture (vanaf de FXDT-chunk op offset 36).
Procedure.s TEX_ReadEffect(*Mem, Size.i, *Info.TexInfo)
  Protected pos.i, length.i

  *Info\IsEffect     = #True
  *Info\EffectType   = PeekL(*Mem + 40)
  *Info\BufferWidth  = PeekL(*Mem + 44)
  *Info\BufferHeight = PeekL(*Mem + 48)
  If *Info\BufferWidth < 1 Or *Info\BufferHeight < 1 Or *Info\BufferWidth > 4096 Or *Info\BufferHeight > 4096
    ProcedureReturn "Invalid effect buffer dimensions."
  EndIf

  ; De buffer staat na de FXBF-chunk. Niet elk effect slaat een buffer op
  ; (bijv. WaterFall01.tex heeft er geen); DataOffset blijft dan 0.
  pos = TEX_FindChunk(*Mem, Size, 52, "FXBF")
  If pos >= 0
    *Info\DataOffset = pos + 4
    If *Info\DataOffset + *Info\BufferWidth * *Info\BufferHeight * 4 > Size
      ProcedureReturn "The effect buffer is incomplete."
    EndIf
  EndIf

  ; Naam van de basistexture: "DFNM" + lengte (LONG) + tekst. Die staat aan het eind
  ; van het bestand, dus we zoeken van achteren naar voren.
  pos = -1
  For length = Size - 4 To 52 Step -1
    If TEX_IsChunk(*Mem, Size, length, "DFNM")
      pos = length
      Break
    EndIf
  Next
  If pos >= 0 And pos + 8 <= Size
    length = PeekL(*Mem + pos + 4)
    If length > 0 And pos + 8 + length <= Size
      *Info\BaseTexture = PeekS(*Mem + pos + 8, length, #PB_Ascii)
    EndIf
  EndIf

  ProcedureReturn ""
EndProcedure

; Leest en controleert de kop van het bestand en vult *Info.
; Geeft een lege tekst terug als alles klopt, anders de foutmelding.
Procedure.s TEX_ReadHeader(*Mem, Size.i, *Info.TexInfo)
  Protected mexWidth.l, mexHeight.l, error.s, frameSize.i

  If Size < 40 Or Not TEX_IsChunk(*Mem, Size, 0, "TVER")
    ProcedureReturn "This is not a Serious Sam texture (TVER chunk missing)."
  EndIf
  *Info\Version = PeekL(*Mem + 4)
  If Not TEX_IsChunk(*Mem, Size, 8, "TDAT")
    ProcedureReturn "Unknown layout: TDAT chunk missing."
  EndIf

  *Info\Flags = PeekL(*Mem + 12)
  mexWidth    = PeekL(*Mem + 16)
  mexHeight   = PeekL(*Mem + 20)

  Select *Info\Version

    Case 3
      If Size < 48 Or Not TEX_IsChunk(*Mem, Size, 44, "FRMS")
        ProcedureReturn "Unknown version 3 layout: FRMS chunk missing."
      EndIf
      *Info\MipLevels   = PeekL(*Mem + 24)
      *Info\FirstMip    = PeekL(*Mem + 32)
      *Info\FrameStride = PeekL(*Mem + 36)     ; grootte van één frame inclusief alle mipmaps
      *Info\Frames      = PeekL(*Mem + 40)
      *Info\DataOffset  = 48
      *Info\BytesPerPixel = 2
      error = TEX_SetSize(*Info, mexWidth, mexHeight)
      If error <> ""
        ProcedureReturn error
      EndIf
      If *Info\FrameStride < *Info\Width * *Info\Height * 2
        ProcedureReturn "The stored frame size is too small."
      EndIf

    Case 4
      *Info\MipLevels = PeekL(*Mem + 24)
      *Info\FirstMip  = PeekL(*Mem + 28)
      *Info\Frames    = PeekL(*Mem + 32)
      error = TEX_SetSize(*Info, mexWidth, mexHeight)
      If error <> ""
        ProcedureReturn error
      EndIf

      If TEX_IsChunk(*Mem, Size, 36, "FXDT")
        ProcedureReturn TEX_ReadEffect(*Mem, Size, *Info)
      ElseIf Not TEX_IsChunk(*Mem, Size, 36, "FRMS")
        ProcedureReturn "Unknown layout: FRMS chunk missing."
      EndIf

      If *Info\Flags & #TEX_ALPHACHANNEL
        *Info\BytesPerPixel = 4
      Else
        *Info\BytesPerPixel = 3
      EndIf
      *Info\DataOffset  = 40
      *Info\FrameStride = *Info\Width * *Info\Height * *Info\BytesPerPixel   ; alleen het grootste plaatje

    Default
      ProcedureReturn "Texture version " + Str(*Info\Version) + " is not supported (only versions 3 and 4)."
  EndSelect

  *Info\HasAlpha = Bool(*Info\Flags & #TEX_ALPHACHANNEL)

  If *Info\DataOffset + *Info\FrameStride * *Info\Frames > Size
    ProcedureReturn "The file is too short for " + Str(*Info\Frames) + " frame(s) of " + Str(*Info\Width) + " x " + Str(*Info\Height) + "."
  EndIf
  ProcedureReturn ""
EndProcedure

; Zet de effectbuffer om in een grijs plaatje: laagste waarde = zwart, hoogste = wit.
Procedure.i TEX_EffectBufferImage(*Mem, *Info.TexInfo)
  Protected image.i, x.i, y.i, value.i, low.i, high.i, gray.i, count.i, i.i

  count = *Info\BufferWidth * *Info\BufferHeight
  low  = PeekL(*Mem + *Info\DataOffset)
  high = low
  For i = 0 To count - 1
    value = PeekL(*Mem + *Info\DataOffset + i * 4)
    If value < low  : low  = value : EndIf
    If value > high : high = value : EndIf
  Next
  If high = low
    high = low + 1                       ; voorkomt delen door nul bij een vlakke buffer
  EndIf

  image = CreateImage(#PB_Any, *Info\BufferWidth, *Info\BufferHeight, 32)
  If image And StartDrawing(ImageOutput(image))
    DrawingMode(#PB_2DDrawing_AllChannels)
    For y = 0 To *Info\BufferHeight - 1
      For x = 0 To *Info\BufferWidth - 1
        value = PeekL(*Mem + *Info\DataOffset + (y * *Info\BufferWidth + x) * 4)
        gray = (value - low) * 255 / (high - low)
        Plot(x, y, RGBA(gray, gray, gray, 255))
      Next
    Next
    StopDrawing()
  EndIf
  ProcedureReturn image
EndProcedure

; Zet de pixels van één frame (versie 3 of 4) in een 32-bit image.
Procedure.i TEX_PixelImage(*Mem, *Info.TexInfo, Frame.i)
  Protected image.i, x.i, y.i, offset.i, value.i, r.i, g.i, b.i, alpha.i

  offset = *Info\DataOffset + Frame * *Info\FrameStride

  image = CreateImage(#PB_Any, *Info\Width, *Info\Height, 32, #PB_Image_Transparent)
  If image And StartDrawing(ImageOutput(image))
    DrawingMode(#PB_2DDrawing_AllChannels)   ; zodat Plot() ook het alfakanaal schrijft
    For y = 0 To *Info\Height - 1
      For x = 0 To *Info\Width - 1
        Select *Info\BytesPerPixel
          Case 2
            ; 16-bit: bit 15 = alfa (1 bit), bits 14-10 rood, 9-5 groen, 4-0 blauw (elk 0..31)
            value = PeekU(*Mem + offset)
            r = ((value >> 10) & 31) * 255 / 31
            g = ((value >> 5) & 31) * 255 / 31
            b = (value & 31) * 255 / 31
            alpha = 255
            If *Info\Flags & #TEX_ALPHACHANNEL And (value & $8000) = 0
              alpha = 0                        ; niet getest: geen voorbeeld met transparantie in versie 3
            EndIf
          Case 3
            r = PeekA(*Mem + offset) : g = PeekA(*Mem + offset + 1) : b = PeekA(*Mem + offset + 2)
            alpha = 255                        ; geen alfakanaal: volledig ondoorzichtig
          Case 4
            r = PeekA(*Mem + offset) : g = PeekA(*Mem + offset + 1) : b = PeekA(*Mem + offset + 2)
            alpha = PeekA(*Mem + offset + 3)
        EndSelect
        Plot(x, y, RGBA(r, g, b, alpha))
        offset + *Info\BytesPerPixel
      Next
    Next
    StopDrawing()
  EndIf
  ProcedureReturn image
EndProcedure

; Zoekt een bestand in een map zonder op hoofd- en kleine letters te letten.
; Nodig voor Linux, waar "Waterfall02.tex" en "WaterFall02.tex" verschillende namen zijn.
; Geeft het volledige pad terug, of "" als het bestand er niet is.
Procedure.s TEX_FindFile(Folder.s, Name.s)
  Protected dir.i, found.s

  ; De map doorzoeken, ook als het bestand er precies zo staat: dan krijgen we de echte schrijfwijze
  ; (Windows vindt "space1_front.tex" ook als het bestand "Space1_Front.tex" heet)
  dir = ExamineDirectory(#PB_Any, Folder, "*")
  If dir
    While NextDirectoryEntry(dir)
      If DirectoryEntryType(dir) = #PB_DirectoryEntry_File And LCase(DirectoryEntryName(dir)) = LCase(Name)
        found = Folder + DirectoryEntryName(dir)
        Break
      EndIf
    Wend
    FinishDirectory(dir)
  EndIf
  ProcedureReturn found
EndProcedure

#TEX_MaxBaseDepth = 4   ; een basistexture kan zelf ook een effect zijn; zo diep zoeken we door

; Laadt één frame van een .tex-bestand als 32-bit PureBasic-image (met alfakanaal).
; Geeft het image-nummer terug, of 0 als het mislukt (de reden staat dan in *Info\Error).
; Bij een effect-texture wordt de basistexture geladen als die in dezelfde map staat
; (die kan zelf weer een effect zijn; Depth telt hoe diep we zitten),
; anders de effectbuffer als grijs plaatje.
Declare.i TEX_Load(FileName.s, *Info.TexInfo, Frame.i = 0, Depth.i = 0)

; Zelfde als TEX_Load, maar het bestand staat al in het geheugen (bijv. uitgepakt uit een .gro).
; FileName is alleen nodig om bij een SE1-effect de basistexture in dezelfde map te zoeken.
; Het geheugen blijft van de aanroeper; die geeft het zelf vrij.
Procedure.i TEX_LoadMemory(*mem, size.i, *Info.TexInfo, FileName.s, Frame.i = 0, Depth.i = 0)
  Protected image.i, baseName.s, baseFile.s, baseInfo.TexInfo
  Protected meta.i, length.i, versionText.s

  ResetStructure(*Info, TexInfo)      ; alle velden terug op 0 / ""
  If *mem = 0 Or size < 8
    *Info\Error = "The file is empty or too small."
    ProcedureReturn 0
  EndIf

  ; 2. Welke engine? Dat zie je aan de eerste bytes:
  ;    "TVER"     = Serious Engine 1
  ;    "CTSEMETA" = Serious Engine 2 of 3; de versietekst erna zegt welke
  ;    "SIGSTRM1" = een ondertekend bestand uit de editor; daarna volgt een gewoon CTSEMETA-bestand
  meta = -1
  If size >= 24 And PeekS(*mem, 8, #PB_Ascii) = "CTSEMETA"
    meta = 0
  ElseIf size >= 24 And PeekS(*mem, 8, #PB_Ascii) = "SIGSTRM1"
    meta = TEXSE2_Find(*mem, size, 8, "CTSEMETA")   ; de handtekening slaan we over
    If meta < 0
      *Info\Error = "Signed file without CTSEMETA data."
      ProcedureReturn 0
    EndIf
  EndIf
  If meta >= 0
    ; Versietekst: LONG lengte op +16, tekst op +20 (gerekend vanaf "CTSEMETA")
    length = PeekL(*mem + meta + 16)
    If length > 0 And length < 1000 And meta + 20 + length <= size
      versionText = PeekS(*mem + meta + 20, length, #PB_Ascii)
    EndIf
    If FindString(versionText, "Serious Sam 2")
      image = TEXSE2_Decode(*mem + meta, size - meta, *Info)
    Else
      image = TEXSE3_Decode(*mem + meta, size - meta, *Info)  ; SE2017 en nieuwer
    EndIf
    ProcedureReturn image
  EndIf
  *Info\Engine = 1

  ; 3. De kop van een SE1-bestand controleren
  *Info\Error = TEX_ReadHeader(*mem, size, *Info)
  If *Info\Error <> ""
    ProcedureReturn 0
  EndIf

  ; 4. Het plaatje maken
  If *Info\IsEffect
    ; De naam is opgeslagen als "Textures\...\Naam.tex"; we nemen alleen het laatste deel
    baseName = StringField(*Info\BaseTexture, CountString(*Info\BaseTexture, "\") + 1, "\")
    If Depth < #TEX_MaxBaseDepth And baseName <> ""
      baseFile = TEX_FindFile(GetPathPart(FileName), baseName)
      If baseFile <> ""
        image = TEX_Load(baseFile, @baseInfo, 0, Depth + 1)
      EndIf
    EndIf
    If image = 0 And baseFile <> "" And *Info\DataOffset = 0
      ; De basistexture bestaat wel, maar kon ook niet getoond worden (bijv. omdat die
      ; zelf een effect is waarvan de basistexture ontbreekt): geef die reden door
      *Info\Error = baseName + ": " + baseInfo\Error
      ProcedureReturn 0
    EndIf
    If image
      *Info\Width  = baseInfo\Width
      *Info\Height = baseInfo\Height
      *Info\BytesPerPixel = baseInfo\BytesPerPixel
      *Info\HasAlpha = baseInfo\HasAlpha
      If baseInfo\BaseShown <> ""
        *Info\BaseShown = baseInfo\BaseShown   ; de basistexture was zelf een effect
      Else
        *Info\BaseShown = baseName
      EndIf
      *Info\Note = "Effect texture: showing base texture " + *Info\BaseShown + " (without the effect)."
    ElseIf *Info\DataOffset = 0
      ; Geen opgeslagen buffer en geen basistexture: er is niets om te tonen
      *Info\Error = "This effect texture stores no image data. Place its base texture"
      If baseName <> ""
        *Info\Error + " (" + baseName + ")"
      EndIf
      *Info\Error + " in the same folder to view it."
      ProcedureReturn 0
    Else
      image = TEX_EffectBufferImage(*mem, *Info)
      *Info\Width  = *Info\BufferWidth
      *Info\Height = *Info\BufferHeight
      *Info\BytesPerPixel = 3
      *Info\HasAlpha = #False
      *Info\Note = "Effect texture: showing the effect buffer as a grayscale image"
      If baseName <> ""
        *Info\Note + " (base texture " + baseName + " not found in this folder)"
      EndIf
      *Info\Note + "."
    EndIf
  Else
    If Frame < 0 Or Frame >= *Info\Frames
      Frame = 0
    EndIf
    image = TEX_PixelImage(*mem, *Info, Frame)
  EndIf

  If image = 0
    *Info\Error = "Not enough memory for the image."
  EndIf

  ProcedureReturn image
EndProcedure

Procedure.i TEX_Load(FileName.s, *Info.TexInfo, Frame.i = 0, Depth.i = 0)
  Protected file.i, size.i, *mem, image.i

  ResetStructure(*Info, TexInfo)
  ; Het hele bestand in het geheugen lezen en dan TEX_LoadMemory het werk laten doen
  file = ReadFile(#PB_Any, FileName)
  If file = 0
    *Info\Error = "The file cannot be opened."
    ProcedureReturn 0
  EndIf
  size = Lof(file)
  If size > 0
    *mem = AllocateMemory(size)
    If *mem
      ReadData(file, *mem, size)
    EndIf
  EndIf
  CloseFile(file)
  If *mem = 0
    *Info\Error = "The file is empty or too large."
    ProcedureReturn 0
  EndIf
  image = TEX_LoadMemory(*mem, size, *Info, FileName, Frame, Depth)
  FreeMemory(*mem)
  ProcedureReturn image
EndProcedure
