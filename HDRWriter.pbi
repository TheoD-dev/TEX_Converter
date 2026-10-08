; HDRWriter.pbi - slaat HDR-pixels op als Radiance .hdr (RGBE), met behoud van alle helderheid
;
; Een .hdr-bestand bestaat uit:
;   tekstregels  "#?RADIANCE", "FORMAT=32-bit_rle_rgbe", een lege regel, en "-Y hoogte +X breedte"
;   pixels       per pixel R,G,B,E (E in hele stops; TexReaderSE3 rekent de SE3-waarden hiernaar om,
;                met een afwijking van hooguit 0,4%)
;
; De pixels schrijven we per rij in het "nieuwe" Radiance-formaat: eerst 2,2 en de breedte,
; daarna de vier kanalen (eerst alle R, dan alle G, ...) in stukjes van maximaal 128 bytes.
; Elk stukje begint met een byte die zegt hoeveel bytes er volgen. Echte compressie (herhalingen)
; gebruiken we niet; dat mag volgens het formaat en houdt de code eenvoudig.

; Slaat RGBE-data (4 bytes per pixel: R,G,B,E) op als .hdr. Geeft #True terug als het gelukt is.
Procedure.i HDR_Save(*RGBE, Width.i, Height.i, FileName.s)
  Protected file.i, header.s, x.i, y.i, c.i, count.i, *row

  If *RGBE = 0 Or Width < 1 Or Height < 1
    ProcedureReturn #False
  EndIf

  file = CreateFile(#PB_Any, FileName)
  If file = 0
    ProcedureReturn #False
  EndIf

  header = "#?RADIANCE" + #LF$ + "FORMAT=32-bit_rle_rgbe" + #LF$ + #LF$ + "-Y " + Str(Height) + " +X " + Str(Width) + #LF$
  WriteString(file, header, #PB_Ascii)

  For y = 0 To Height - 1
    *row = *RGBE + y * Width * 4
    If Width < 8 Or Width > 32767
      ; Zo smal of breed kan het rij-formaat niet: pixels gewoon achter elkaar
      WriteData(file, *row, Width * 4)
    Else
      ; Rij-kop: 2, 2, breedte (2 bytes, hoogste eerst)
      WriteByte(file, 2)
      WriteByte(file, 2)
      WriteByte(file, (Width >> 8) & 255)
      WriteByte(file, Width & 255)
      ; Elk kanaal apart, in stukjes van maximaal 128 bytes
      For c = 0 To 3
        x = 0
        While x < Width
          count = Width - x
          If count > 128
            count = 128
          EndIf
          WriteByte(file, count)
          While count > 0
            WriteByte(file, PeekA(*row + x * 4 + c))
            x + 1
            count - 1
          Wend
        Wend
      Next
    EndIf
  Next

  CloseFile(file)
  ProcedureReturn #True
EndProcedure
