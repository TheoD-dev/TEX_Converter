; TexWriterSE1.pbi - slaat een plaatje op als Serious Sam 1 .tex-bestand (texture-versie 4)
;
; Precies de opbouw die we in TEX-formaat-analyse.md hebben uitgezocht:
;   "TVER" + LONG 4
;   "TDAT" + vlaggen, mexBreedte, mexHoogte, mipNiveaus, firstMip, aantalFrames (LONG's)
;   "FRMS" + pixels van het grootste plaatje: R,G,B (3 bytes) of R,G,B,A (4 bytes) per pixel
;   "ANIM" + "ADAT" + 1 animatie "OnlyAnim", snelheid 0,02, 1 frame (frame 0)
;
; "mex" is de maat die SE1 gebruikt om te bepalen hoe groot de texture op een oppervlak komt.
; mexMaat = pixelMaat << firstMip (dus pixels keer 2^firstMip). Bij een SE1-bron nemen we de
; oorspronkelijke firstMip over, zodat de texture in het spel even groot blijft.

XIncludeFile "TexInfo.pbi"     ; #TEX_ALPHACHANNEL en #TEX_32BIT

; Is dit getal een macht van 2 (1, 2, 4, 8, ...)? SE1 werkt het best met zulke maten.
Procedure.i TEXW_IsPowerOf2(Value.i)
  ProcedureReturn Bool(Value > 0 And (Value & (Value - 1)) = 0)
EndProcedure

; Aantal mipmap-niveaus van de kleinste zijde, zoals in de originele bestanden (256 geeft 9).
Procedure.i TEXW_MipLevels(Width.i, Height.i)
  Protected side.i = Width, levels.i = 1
  If Height < side : side = Height : EndIf
  While side > 1
    side >> 1
    levels + 1
  Wend
  ProcedureReturn levels
EndProcedure

; Slaat een image op als SE1-.tex. WithAlpha = #True: 4 bytes per pixel met transparantie.
; FirstMip bepaalt de mex-maat (zie boven). Keep32Bit zet de vlag #TEX_32BIT (zoals in het origineel).
; Geeft #True terug als het gelukt is.
Procedure.i TEXW_SaveSE1(Image.i, FileName.s, WithAlpha.i, FirstMip.i = 0, Keep32Bit.i = #False)
  Protected width.i, height.i, bpp.i, flags.i, file.i, x.i, y.i, color.i, *line, pos.i, result.i

  If IsImage(Image) = 0 Or FirstMip < 0 Or FirstMip > 20
    ProcedureReturn #False
  EndIf
  width  = ImageWidth(Image)
  height = ImageHeight(Image)
  If WithAlpha
    bpp = 4
    flags = #TEX_ALPHACHANNEL | #TEX_32BIT
  Else
    bpp = 3
    flags = 0
  EndIf
  If Keep32Bit
    flags | #TEX_32BIT                        ; hint voor het spel uit het originele bestand overnemen
  EndIf

  file = CreateFile(#PB_Any, FileName)
  If file = 0
    ProcedureReturn #False
  EndIf

  ; --- Kop ---
  WriteString(file, "TVER", #PB_Ascii) : WriteLong(file, 4)
  WriteString(file, "TDAT", #PB_Ascii)
  WriteLong(file, flags)
  WriteLong(file, width << FirstMip)          ; mexBreedte
  WriteLong(file, height << FirstMip)         ; mexHoogte
  WriteLong(file, TEXW_MipLevels(width, height))
  WriteLong(file, FirstMip)
  WriteLong(file, 1)                          ; 1 frame
  WriteString(file, "FRMS", #PB_Ascii)

  ; --- Pixels, regel voor regel van boven naar beneden ---
  *line = AllocateMemory(width * bpp)
  If *line And StartDrawing(ImageOutput(Image))
    DrawingMode(#PB_2DDrawing_AllChannels)
    For y = 0 To height - 1
      pos = 0
      For x = 0 To width - 1
        color = Point(x, y)
        PokeA(*line + pos, Red(color))
        PokeA(*line + pos + 1, Green(color))
        PokeA(*line + pos + 2, Blue(color))
        If WithAlpha
          PokeA(*line + pos + 3, Alpha(color))
        EndIf
        pos + bpp
      Next
      WriteData(file, *line, width * bpp)
    Next
    StopDrawing()
    result = #True
  EndIf
  If *line : FreeMemory(*line) : EndIf

  ; --- Animatieblok: 1 animatie met 1 frame, zoals in alle voorbeeldbestanden ---
  WriteString(file, "ANIM", #PB_Ascii)
  WriteString(file, "ADAT", #PB_Ascii)
  WriteLong(file, 1)                          ; aantal animaties
  *line = AllocateMemory(32)                  ; naam: 32 bytes, aangevuld met nullen
  PokeS(*line, "OnlyAnim", -1, #PB_Ascii)
  WriteData(file, *line, 32)
  FreeMemory(*line)
  WriteFloat(file, 0.02)                      ; seconden per frame
  WriteLong(file, 1)                          ; aantal frames in de animatie
  WriteLong(file, 0)                          ; frame 0

  CloseFile(file)
  ProcedureReturn result
EndProcedure
