; TexReaderSE3.pbi - leest Serious Sam 3 .tex-bestanden (CStaticTexture, engine-versie SE2017)
;
; Opbouw (zie TEX-formaat-SE3.md): hetzelfde CTSEMETA-formaat als SE2, maar
;   - de pixels zijn NIET ingepakt
;   - alle mipmaps staan erin (het grootste niveau eerst; alleen dat lezen we)
;   - de formaatnummers zijn anders dan in SE2
; Rond de chunk "STAR":
;   STAR-16 breedte, STAR-12 hoogte, STAR-8 vlaggen, STAR-4 formaat (allemaal LONG)
;   "STAR" + LONG lengte + pixeldata
;   daarna LONG U-wrapping, LONG V-wrapping, COLOR randkleur, LONG filtering, ...
;
; HDR (formaat 12): per pixel B,G,R en een gedeelde exponent E, maar E telt in stapjes van
; 1/8 stop (anders dan in Radiance .hdr, waar E in hele stops telt):
;   echte waarde = (kanaal + 0,5) / 256 * 2^((E - 127,5) / 8)
; Dit is afgeleid door te vergelijken met .tga-exports uit Serious Editor: die maakt er
;   255 * min(1, waarde) ^ (1 / 2.2)
; van, en met belichting 0 EV doen wij precies hetzelfde (verschil hooguit 3 van 255).
; We gebruiken één belichting voor ALLE HDR-bestanden (TEXSE3_ExposureEV), zodat de vlakken
; van een skybox op elkaar aansluiten.

XIncludeFile "TexInfo.pbi"     ; de structuur TexInfo
XIncludeFile "DXT.pbi"         ; DXT_Decode() voor de gecomprimeerde formaten
XIncludeFile "TexReaderSE2.pbi"; TEXSE2_Find() en TEXSE2_WrapName() gebruiken we ook hier

; Belichting voor HDR in "stops": elke +1 maakt het plaatje twee keer zo licht.
; Eén waarde voor alle bestanden, dus geen automatische belichting per plaatje.
; 0 EV geeft hetzelfde resultaat als de .tga-export van Serious Editor.
#TEXSE3_DefaultExposureEV = 0.0
Global TEXSE3_ExposureEV.d = #TEXSE3_DefaultExposureEV

; Namen zoals in de editor van Serious Sam 3 / Fusion. De originele BFE (2011) nummert anders.
Procedure.s TEXSE3_FormatName(Format.i, IsBFE.i = #False)
  If IsBFE
    Select Format
      Case 2  : ProcedureReturn "opaque (24-bit)"
      Case 3  : ProcedureReturn "translucent (32-bit)"
      Case 4  : ProcedureReturn "format 4 (24-bit)"         ; betekenis nog onbekend
      Case 5  : ProcedureReturn "format 5 (32-bit)"         ; betekenis nog onbekend
      Case 6  : ProcedureReturn "normal-map (16-bit, X/Y)"
      Case 7  : ProcedureReturn "grayscale (8-bit)"
      Case 8  : ProcedureReturn "alpha only (8-bit)"
      Case 9  : ProcedureReturn "compressed opaque (4-bit, DXT1)"
      Case 10 : ProcedureReturn "compressed translucent (8-bit, DXT5)"
      Case 11 : ProcedureReturn "compressed (DXT3)"
      Case 12 : ProcedureReturn "HDR opaque (32-bit, RGBE)"
    EndSelect
    ProcedureReturn "unknown format " + Str(Format)
  EndIf
  Select Format
    Case 2  : ProcedureReturn "opaque (32-bit)"
    Case 3  : ProcedureReturn "translucent (32-bit)"
    Case 6  : ProcedureReturn "grayscale translucent (16-bit)"
    Case 7  : ProcedureReturn "grayscale opaque (8-bit)"
    Case 8  : ProcedureReturn "alpha only (8-bit)"
    Case 9  : ProcedureReturn "compressed opaque (4-bit, DXT1)"
    Case 10 : ProcedureReturn "compressed translucent (8-bit, DXT5)"
    Case 11 : ProcedureReturn "compressed (DXT3)"
    Case 12 : ProcedureReturn "HDR opaque (32-bit, RGBE)"
    Case 15 : ProcedureReturn "compressed normal-map (8-bit, BC5)"
  EndSelect
  ProcedureReturn "unknown format " + Str(Format)
EndProcedure

Procedure.s TEXSE3_FlagNames(Flags.i)
  Protected text.s
  If Flags & $0001 : text + ", mipmaps"   : EndIf
  If Flags & $0004 : text + ", constant"  : EndIf
  If Flags & $0008 : text + ", resident"  : EndIf
  If Flags & $0080 : text + ", normalmap" : EndIf
  If Flags & $0100 : text + ", atlas"     : EndIf
  If Flags & $0400 : text + ", no streaming?" : EndIf    ; vermoedelijk
  If text = ""
    ProcedureReturn "none"
  EndIf
  ProcedureReturn Mid(text, 3)          ; de eerste ", " weghalen
EndProcedure

; Hoe HDR-waarden naar een gewoon plaatje (0..255) gaan:
Enumeration TEXSE3_ToneMode
  #TEXSE3_ToneClip      ; zoals Serious Editor: alles boven wit afkappen
  #TEXSE3_ToneFilmic    ; heldere delen zacht afvlakken, zoals in games (ACES-filmcurve)
EndEnumeration
Global TEXSE3_ToneMode.i = #TEXSE3_ToneClip

; Zet een HDR-waarde om naar 0..255: belichting toepassen, dan afkappen of filmisch afvlakken,
; en tot slot gamma 2.2 voor het scherm.
Procedure.i TEXSE3_ToneMap(Value.d, Scale.d)
  Value * Scale
  If TEXSE3_ToneMode = #TEXSE3_ToneFilmic
    ; Benadering van de ACES-filmcurve (Krzysztof Narkowicz). Lage waarden blijven bijna gelijk,
    ; hoge waarden lopen geleidelijk naar 1 in plaats van hard af te kappen.
    Value = (Value * (2.51 * Value + 0.03)) / (Value * (2.43 * Value + 0.59) + 0.14)
  EndIf
  If Value > 1
    Value = 1
  EndIf
  Value = Pow(Value, 1 / 2.2)
  ProcedureReturn Int(Value * 255 + 0.5)
EndProcedure

; Zet drie HDR-waarden om naar Radiance-RGBE (4 bytes: R,G,B,E met E in hele stops)
; en schrijft ze op *Dest. Zo kan HDR_Save() er een echt .hdr-bestand van maken.
Procedure TEXSE3_EncodeRGBE(*Dest, r.d, g.d, b.d)
  Protected biggest.d = r, e.i, scale.d
  If g > biggest : biggest = g : EndIf
  If b > biggest : biggest = b : EndIf
  If biggest < 1.0e-32
    PokeL(*Dest, 0)                         ; zwart
    ProcedureReturn
  EndIf
  ; Zoek e zodat biggest = m * 2^e met m tussen 0.5 en 1
  e = Int(Round(Log(biggest) / Log(2), #PB_Round_Down)) + 1
  If biggest / Pow(2, e) >= 1     : e + 1 : EndIf   ; afrondingsfoutjes opvangen
  If biggest / Pow(2, e) < 0.5    : e - 1 : EndIf
  scale = 256 / Pow(2, e)
  PokeA(*Dest,     Int(r * scale))
  PokeA(*Dest + 1, Int(g * scale))
  PokeA(*Dest + 2, Int(b * scale))
  PokeA(*Dest + 3, e + 128)
EndProcedure

; Telt alle pixels van alle mipmap-niveaus samen (bijv. 64x128 + 32x64 + ... + 1x1).
Procedure.i TEXSE3_ChainPixels(Width.i, Height.i)
  Protected total.i
  Repeat
    total + Width * Height
    If Width = 1 And Height = 1
      Break
    EndIf
    Width  = Width / 2  : If Width < 1  : Width = 1  : EndIf
    Height = Height / 2 : If Height < 1 : Height = 1 : EndIf
  ForEver
  ProcedureReturn total
EndProcedure

; Zet niet-gecomprimeerde pixeldata om naar nieuw geheugen met 4 bytes per pixel: B,G,R,A
; (bij HDR B,G,R,E). Alleen het grootste mipmap-niveau. Geeft 0 terug als het niet lukt.
; In *Bpp komt het aantal bytes per pixel zoals het in het bestand stond.
;
; Twee manieren van opslaan:
;   Fusion (2017): per pixel B,G,R,A achter elkaar.
;   BFE (2011), vlag $200: elk kanaal apart ("plane"): eerst alle R-waarden van alle mipmaps,
;     dan alle G, dan B, dan A/E. Elke byte is het VERSCHIL met de vorige waarde in dat kanaal
;     (delta-codering; dat pakt beter in in de .gro). Optellen geeft de echte waarde terug.
;     Bij 1 kanaal is het grijs (of alleen alfa), bij 2 kanalen X en Y van een normal map.
Procedure.i TEXSE3_Unpack(*Src, DataSize.i, Width.i, Height.i, Flags.i, Format.i, *Bpp.Integer)
  Protected n.i = Width * Height, chain.i, bpp.i, *dst, k.i, i.i, sum.i, target.i, *plane
  Protected nx.d, ny.d, nz.d

  ; Bytes per pixel volgt uit de grootte: met of zonder mipmaps
  chain = TEXSE3_ChainPixels(Width, Height)
  If DataSize % chain = 0
    bpp = DataSize / chain
  ElseIf DataSize % n = 0
    bpp = DataSize / n
    chain = n
  Else
    ProcedureReturn 0
  EndIf
  If bpp < 1 Or bpp > 4
    ProcedureReturn 0
  EndIf
  If Not (Flags & $200) And bpp <> 4
    ProcedureReturn 0                       ; zo'n combinatie hebben we nog niet gezien
  EndIf
  *Bpp\i = bpp

  *dst = AllocateMemory(n * 4)
  If *dst = 0
    ProcedureReturn 0
  EndIf

  If Not (Flags & $200)
    CopyMemory(*Src, *dst, n * 4)          ; Fusion: staat al goed
    ProcedureReturn *dst
  EndIf

  ; BFE: kanalen apart en delta-gecodeerd
  For k = 0 To bpp - 1
    ; In welke byte (B=0, G=1, R=2, A=3) komt dit kanaal terecht?
    Select k
      Case 0 : target = 2                  ; R (of grijs / X)
      Case 1 : target = 1                  ; G (of Y)
      Case 2 : target = 0                  ; B
      Case 3 : target = 3                  ; A of HDR-exponent
    EndSelect
    If bpp = 1 And Format = 8
      target = 3                           ; alpha only: het ene kanaal is de alfa
    EndIf
    *plane = *Src + k * chain
    sum = 0
    For i = 0 To n - 1
      sum = (sum + PeekA(*plane + i)) & 255
      PokeA(*dst + i * 4 + target, sum)
    Next
  Next

  ; Ontbrekende kanalen aanvullen
  For i = 0 To n - 1
    Select bpp
      Case 1
        If Format = 8
          PokeA(*dst + i * 4, 0) : PokeA(*dst + i * 4 + 1, 0) : PokeA(*dst + i * 4 + 2, 0)
        Else
          PokeA(*dst + i * 4, PeekA(*dst + i * 4 + 2))      ; grijs: B = G = R
          PokeA(*dst + i * 4 + 1, PeekA(*dst + i * 4 + 2))
          PokeA(*dst + i * 4 + 3, 255)
        EndIf
      Case 2
        ; Normal map: Z uitrekenen uit X en Y (lengte van een normaal is 1)
        nx = PeekA(*dst + i * 4 + 2) / 127.5 - 1
        ny = PeekA(*dst + i * 4 + 1) / 127.5 - 1
        nz = 1 - nx * nx - ny * ny
        If nz < 0 : nz = 0 : EndIf
        PokeA(*dst + i * 4, Int((Sqr(nz) + 1) * 127.5))
        PokeA(*dst + i * 4 + 3, 255)
      Case 3
        PokeA(*dst + i * 4 + 3, 255)
    EndSelect
  Next
  ProcedureReturn *dst
EndProcedure

; Maakt van een SE3-bestand (al in het geheugen, beginnend bij "CTSEMETA") een 32-bit image.
; Geeft het image-nummer terug, of 0 als het mislukt (de reden staat dan in *Info\Error).
Procedure.i TEXSE3_Decode(*Mem, Size.i, *Info.TexInfo)
  Protected length.i, objs.i, star.i, dataSize.i, flags.i, format.i, wrapU.i, wrapV.i
  Protected image.i, x.i, y.i, offset.i, *pixels, needed.i, dxtType.i
  Protected scale.d, factor.d, e.i, r.i, g.i, b.i, *conv, bpp.i, isBFE.i, className.s
  Dim expFactor.d(255)       ; 2^((E-127,5)/8)/256 vooraf uitgerekend: scheelt veel rekenwerk

  *Info\Engine = 3

  ; --- Versietekst ---
  length = PeekL(*Mem + 16)
  If length > 0 And length < 1000 And 20 + length <= Size
    *Info\EngineVersion = RemoveString(PeekS(*Mem + 20, length, #PB_Ascii), "$Version: ")
  EndIf

  ; Originele Serious Sam 3: BFE (2011) of de Fusion/2017-versie? De formaatnummers verschillen.
  isBFE = Bool(FindString(*Info\EngineVersion, "SE2017") = 0)

  ; --- Soort texture ---
  ; Meestal CStaticTexture. In BFE komen ook CAnimTexture (we tonen het eerste plaatje),
  ; CColorTexture en losse CBaseTexture voor; die hebben dezelfde opbouw rond STAR.
  If TEXSE2_Find(*Mem, Size, 0, "CAnimTexture") >= 0
    className = "CAnimTexture"
  ElseIf TEXSE2_Find(*Mem, Size, 0, "CColorTexture") >= 0
    className = "CColorTexture"
  ElseIf TEXSE2_Find(*Mem, Size, 0, "CStaticTexture") >= 0
    className = "CStaticTexture"
  ElseIf TEXSE2_Find(*Mem, Size, 0, "CBaseTexture") >= 0
    className = "CBaseTexture"
  Else
    *Info\Error = "This Serious Sam 3 file does not contain a texture."
    ProcedureReturn 0
  EndIf

  ; --- De texturegegevens staan rond de chunk STAR (na OBJS, het begin van de objecten) ---
  objs = TEXSE2_Find(*Mem, Size, 0, "OBJS")
  If objs < 0
    *Info\Error = "Unknown Serious Sam 3 layout: OBJS chunk missing."
    ProcedureReturn 0
  EndIf
  star = TEXSE2_Find(*Mem, Size, objs, "STAR")
  If star < 16 Or star + 8 > Size
    *Info\Error = "Unknown Serious Sam 3 layout: STAR chunk missing."
    ProcedureReturn 0
  EndIf

  *Info\Width  = PeekL(*Mem + star - 16)
  *Info\Height = PeekL(*Mem + star - 12)
  flags        = PeekL(*Mem + star - 8)
  format       = PeekL(*Mem + star - 4)
  dataSize     = PeekL(*Mem + star + 4)
  *pixels      = *Mem + star + 8
  *Info\Flags  = flags
  *Info\Frames = 1
  *Info\FormatName = TEXSE3_FormatName(format, isBFE)
  If isBFE
    *Info\FormatName = "BFE, " + *Info\FormatName
  EndIf

  If *Info\Width < 1 Or *Info\Height < 1 Or *Info\Width > 16384 Or *Info\Height > 16384
    *Info\Error = "Invalid dimensions: " + Str(*Info\Width) + " x " + Str(*Info\Height)
    ProcedureReturn 0
  EndIf
  If dataSize = 0
    ; Komt in BFE een paar keer voor (bijv. Hud\DPadDownRight.tex): de texture-gegevens staan
    ; erin, maar de pixels niet. Die haalt het spel vermoedelijk ergens anders vandaan.
    *Info\Error = "This texture file contains no image data (" + Str(*Info\Width) + " x " + Str(*Info\Height) + ", " + *Info\FormatName + ")."
    ProcedureReturn 0
  EndIf
  If dataSize < 1 Or star + 8 + dataSize > Size
    *Info\Error = "The image data is incomplete."
    ProcedureReturn 0
  EndIf

  ; Na de pixeldata: wrapping
  If star + 8 + dataSize + 8 <= Size
    wrapU = PeekL(*Mem + star + 8 + dataSize)
    wrapV = PeekL(*Mem + star + 8 + dataSize + 4)
  EndIf
  *Info\Note = "Flags: " + TEXSE3_FlagNames(flags) + "   U: " + TEXSE2_WrapName(wrapU) + "   V: " + TEXSE2_WrapName(wrapV)
  If className = "CAnimTexture"
    *Info\Note + "   Animated texture: first frame shown"
  ElseIf className <> "CStaticTexture"
    *Info\Note + "   " + className
  EndIf

  Select format

    Case 9, 10, 11, 15
      ; --- Gecomprimeerd ---
      Select format
        Case 9  : dxtType = #DXT1
        Case 10 : dxtType = #DXT5
        Case 11 : dxtType = #DXT3
        Case 15 : dxtType = #BC5
      EndSelect
      *Info\HasAlpha = Bool(format = 10 Or format = 11)
      *Info\BytesPerPixel = 4
      image = DXT_Decode(*pixels, dataSize, *Info\Width, *Info\Height, dxtType)
      If image = 0
        *Info\Error = "The compressed image data is incomplete."
      EndIf

    Default
      ; --- Niet gecomprimeerd ---
      ; Eerst alles omzetten naar 4 bytes per pixel in de volgorde B,G,R,A (bij HDR B,G,R,E),
      ; zoals Fusion het al opslaat. Daarna is de rest voor beide versies hetzelfde.
      *conv = TEXSE3_Unpack(*pixels, dataSize, *Info\Width, *Info\Height, flags, format, @bpp)
      If *conv = 0
        *Info\Error = "The image data of " + *Info\FormatName + " could not be read (" + Str(dataSize) + " bytes)."
        ProcedureReturn 0
      EndIf
      *pixels = *conv
      needed = *Info\Width * *Info\Height * 4
      *Info\BytesPerPixel = bpp
      *Info\IsHDR = Bool(format = 12 And bpp = 4)
      ; Transparantie: alleen als er echt een pixel niet volledig dekkend is
      *Info\HasAlpha = #False
      If Not *Info\IsHDR
        For offset = 3 To needed - 1 Step 4
          If PeekA(*pixels + offset) < 255
            *Info\HasAlpha = #True
            Break
          EndIf
        Next
      EndIf

      If *Info\IsHDR
        scale = Pow(2, TEXSE3_ExposureEV)
        For e = 0 To 255
          ; E telt in stapjes van 1/8 stop. Net als de editor nemen we het midden van elk
          ; stapje (E + 0,5 en kanaal + 0,5); dat geeft de kleinste afwijking.
          expFactor(e) = Pow(2, (e - 127.5) / 8) / 256

        Next
        ; Kopie omrekenen naar Radiance-RGBE (E in hele stops) voor opslaan als .hdr.
        ; De helderheid blijft gelijk; alleen de schrijfwijze verandert.
        *Info\HdrData = AllocateMemory(needed)
        If *Info\HdrData
          For offset = 0 To needed - 4 Step 4
            factor = expFactor(PeekA(*pixels + offset + 3))
            TEXSE3_EncodeRGBE(*Info\HdrData + offset, (PeekA(*pixels + offset + 2) + 0.5) * factor, (PeekA(*pixels + offset + 1) + 0.5) * factor, (PeekA(*pixels + offset) + 0.5) * factor)
          Next
        EndIf
        *Info\Note + "   HDR exposure: " + StrD(TEXSE3_ExposureEV, 1) + " EV"
        If TEXSE3_ToneMode = #TEXSE3_ToneFilmic
          *Info\Note + ", filmic"
        Else
          *Info\Note + ", editor (clip)"
        EndIf
      EndIf

      image = CreateImage(#PB_Any, *Info\Width, *Info\Height, 32, #PB_Image_Transparent)
      If image And StartDrawing(ImageOutput(image))
        DrawingMode(#PB_2DDrawing_AllChannels)
        offset = 0
        For y = 0 To *Info\Height - 1
          For x = 0 To *Info\Width - 1
            b = PeekA(*pixels + offset)          ; let op: volgorde B,G,R
            g = PeekA(*pixels + offset + 1)
            r = PeekA(*pixels + offset + 2)
            e = PeekA(*pixels + offset + 3)
            If *Info\IsHDR
              ; De vierde byte is de exponent, geen transparantie
              factor = expFactor(e)
              Plot(x, y, RGBA(TEXSE3_ToneMap((r + 0.5) * factor, scale), TEXSE3_ToneMap((g + 0.5) * factor, scale), TEXSE3_ToneMap((b + 0.5) * factor, scale), 255))
            ElseIf *Info\HasAlpha
              Plot(x, y, RGBA(r, g, b, e))
            Else
              Plot(x, y, RGBA(r, g, b, 255))
            EndIf
            offset + 4
          Next
        Next
        StopDrawing()
      ElseIf image = 0
        *Info\Error = "Not enough memory for the image."
      EndIf
      FreeMemory(*conv)
  EndSelect

  If image = 0
    TEX_FreeInfo(*Info)
  EndIf
  ProcedureReturn image
EndProcedure
