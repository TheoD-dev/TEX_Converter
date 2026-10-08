; TIFFWriter.pbi - eigen TIFF-encoder (PureBasic kan TIFF wel lezen, maar niet opslaan)
;
; We schrijven de eenvoudigste soort TIFF die elk programma kan lezen ("baseline", niet ingepakt):
;   8 bytes kop    - "II" (little-endian, laagste byte eerst), het getal 42, en waar de IFD staat
;   pixels         - rij voor rij R,G,B (24-bit) of R,G,B,A (32-bit, met transparantie)
;   extra waarden  - die niet in een IFD-regel passen (bits per kanaal, resolutie)
;   IFD            - "Image File Directory": een lijst met regels (tags) zoals breedte, hoogte,
;                    aantal kanalen en waar de pixels staan. De tags moeten op volgorde van nummer staan.

; Schrijft één IFD-regel: tagnummer, type (3 = SHORT 2 bytes, 4 = LONG 4 bytes, 5 = RATIONAL),
; aantal waarden, en de waarde zelf of de plek in het bestand waar de waarden staan.
Procedure TIFF_Tag(File.i, Tag.i, Type.i, Count.i, Value.i)
  WriteWord(File, Tag)
  WriteWord(File, Type)
  WriteLong(File, Count)
  If Type = 3 And Count = 1
    WriteWord(File, Value)           ; een SHORT staat links in het 4-byte veld
    WriteWord(File, 0)
  Else
    WriteLong(File, Value)
  EndIf
EndProcedure

; Slaat een image op als TIFF. Met WithAlpha = #True 32-bit (met transparantie), anders 24-bit.
; Geeft #True terug als het gelukt is.
Procedure.i TIFF_Save(Image.i, FileName.s, WithAlpha.i = #True)
  Protected width.i, height.i, spp.i, dataSize.i, *pixels, pos.i, x.i, y.i, color.i, file.i
  Protected extraPos.i, bpsPos.i, xResPos.i, yResPos.i, ifdPos.i, tagCount.i, i.i

  If IsImage(Image) = 0
    ProcedureReturn #False
  EndIf
  width  = ImageWidth(Image)
  height = ImageHeight(Image)
  If WithAlpha
    spp = 4                          ; "samples per pixel": R, G, B, A
  Else
    spp = 3
  EndIf
  dataSize = width * height * spp

  ; --- Pixels verzamelen ---
  *pixels = AllocateMemory(dataSize)
  If *pixels = 0
    ProcedureReturn #False
  EndIf
  If StartDrawing(ImageOutput(Image))
    DrawingMode(#PB_2DDrawing_AllChannels)
    For y = 0 To height - 1
      For x = 0 To width - 1
        color = Point(x, y)
        PokeA(*pixels + pos,     Red(color))
        PokeA(*pixels + pos + 1, Green(color))
        PokeA(*pixels + pos + 2, Blue(color))
        If WithAlpha
          PokeA(*pixels + pos + 3, Alpha(color))
        EndIf
        pos + spp
      Next
    Next
    StopDrawing()
  EndIf

  file = CreateFile(#PB_Any, FileName)
  If file = 0
    FreeMemory(*pixels)
    ProcedureReturn #False
  EndIf

  ; --- Plekken in het bestand uitrekenen ---
  extraPos = 8 + dataSize
  extraPos + (extraPos & 1)          ; extra waarden op een even plek
  bpsPos  = extraPos                 ; bits per kanaal: spp keer de SHORT 8
  xResPos = bpsPos + spp * 2         ; resolutie: 72/1
  yResPos = xResPos + 8
  ifdPos  = yResPos + 8

  ; --- Kop ---
  WriteAsciiCharacter(file, 'I')
  WriteAsciiCharacter(file, 'I')
  WriteWord(file, 42)
  WriteLong(file, ifdPos)

  ; --- Pixels ---
  WriteData(file, *pixels, dataSize)
  FreeMemory(*pixels)
  If (8 + dataSize) & 1
    WriteByte(file, 0)               ; opvulbyte
  EndIf

  ; --- Extra waarden ---
  For i = 1 To spp
    WriteWord(file, 8)
  Next
  WriteLong(file, 72) : WriteLong(file, 1)
  WriteLong(file, 72) : WriteLong(file, 1)

  ; --- IFD ---
  tagCount = 12
  If WithAlpha
    tagCount + 1
  EndIf
  WriteWord(file, tagCount)
  TIFF_Tag(file, 256, 4, 1, width)          ; ImageWidth
  TIFF_Tag(file, 257, 4, 1, height)         ; ImageLength (hoogte)
  TIFF_Tag(file, 258, 3, spp, bpsPos)       ; BitsPerSample: 8 per kanaal
  TIFF_Tag(file, 259, 3, 1, 1)              ; Compression: 1 = niet ingepakt
  TIFF_Tag(file, 262, 3, 1, 2)              ; PhotometricInterpretation: 2 = RGB
  TIFF_Tag(file, 273, 4, 1, 8)              ; StripOffsets: de pixels beginnen op byte 8
  TIFF_Tag(file, 277, 3, 1, spp)            ; SamplesPerPixel
  TIFF_Tag(file, 278, 4, 1, height)         ; RowsPerStrip: alles in één stuk
  TIFF_Tag(file, 279, 4, 1, dataSize)       ; StripByteCounts
  TIFF_Tag(file, 282, 5, 1, xResPos)        ; XResolution
  TIFF_Tag(file, 283, 5, 1, yResPos)        ; YResolution
  TIFF_Tag(file, 296, 3, 1, 2)              ; ResolutionUnit: 2 = inch
  If WithAlpha
    TIFF_Tag(file, 338, 3, 1, 2)            ; ExtraSamples: 2 = gewone (niet voorvermenigvuldigde) alfa
  EndIf
  WriteLong(file, 0)                        ; geen volgende IFD

  CloseFile(file)
  ProcedureReturn #True
EndProcedure
