; PCXWriter.pbi - eigen PCX-encoder (PureBasic kan geen PCX opslaan)
;
; PCX is een oud formaat dat de Serious Sam-editors kunnen importeren. Wij schrijven 24-bit PCX:
;   128 bytes kop  - maten, aantal kleurvlakken (3 = rood, groen, blauw), bytes per regel
;   pixels         - per beeldregel eerst alle rode waarden, dan alle groene, dan alle blauwe,
;                    ingepakt met RLE (run-length encoding, zie PCX_WriteRun)
; PCX heeft geen alfakanaal; transparantie gaat bij dit formaat verloren.

; Schrijft één regel van één kleurvlak RLE-ingepakt in *Out. Geeft het aantal geschreven bytes.
; RLE: een reeks gelijke bytes wordt opgeslagen als ($C0 + aantal) gevolgd door de waarde
; (aantal maximaal 63). Een losse byte kleiner dan $C0 mag gewoon zo; een losse byte van $C0
; of hoger moet als reeks van 1, anders zou hij voor een teller worden aangezien.
Procedure.i PCX_WriteRun(*Line, Length.i, *Out)
  Protected i.i, value.i, count.i, written.i
  i = 0
  While i < Length
    value = PeekA(*Line + i)
    count = 1
    While i + count < Length And count < 63 And PeekA(*Line + i + count) = value
      count + 1
    Wend
    If count > 1 Or value >= $C0
      PokeA(*Out + written, $C0 | count)
      PokeA(*Out + written + 1, value)
      written + 2
    Else
      PokeA(*Out + written, value)
      written + 1
    EndIf
    i + count
  Wend
  ProcedureReturn written
EndProcedure

; Slaat een image op als 24-bit PCX. Geeft #True terug als het gelukt is.
Procedure.i PCX_Save(Image.i, FileName.s)
  Protected width.i, height.i, bytesPerLine.i, *header, *line, *packed, file.i, result.i
  Protected x.i, y.i, plane.i, color.i, size.i

  If IsImage(Image) = 0
    ProcedureReturn #False
  EndIf
  width  = ImageWidth(Image)
  height = ImageHeight(Image)
  If width > 65535 Or height > 65535
    ProcedureReturn #False
  EndIf
  bytesPerLine = width + (width & 1)       ; moet een even getal zijn

  file = CreateFile(#PB_Any, FileName)
  If file = 0
    ProcedureReturn #False
  EndIf

  ; --- Kop (128 bytes; AllocateMemory vult alles met nullen) ---
  *header = AllocateMemory(128)
  PokeA(*header + 0, 10)                   ; vaste herkenningsbyte van PCX
  PokeA(*header + 1, 5)                    ; versie 5 (ondersteunt 24-bit)
  PokeA(*header + 2, 1)                    ; 1 = RLE-inpakking
  PokeA(*header + 3, 8)                    ; 8 bits per pixel per kleurvlak
  PokeW(*header + 4, 0)                    ; xMin
  PokeW(*header + 6, 0)                    ; yMin
  PokeW(*header + 8, width - 1)            ; xMax
  PokeW(*header + 10, height - 1)          ; yMax
  PokeW(*header + 12, 72)                  ; horizontale resolutie (dpi)
  PokeW(*header + 14, 72)                  ; verticale resolutie (dpi)
  ; bytes 16-63: 16-kleurenpalet (niet gebruikt), byte 64: gereserveerd
  PokeA(*header + 65, 3)                   ; 3 kleurvlakken: R, G, B
  PokeW(*header + 66, bytesPerLine)
  PokeW(*header + 68, 1)                   ; 1 = kleur
  WriteData(file, *header, 128)
  FreeMemory(*header)

  ; --- Pixels, regel voor regel ---
  *line   = AllocateMemory(bytesPerLine)
  *packed = AllocateMemory(bytesPerLine * 2)   ; slechtste geval: elke byte wordt 2 bytes
  If *line And *packed And StartDrawing(ImageOutput(Image))
    For y = 0 To height - 1
      For plane = 0 To 2
        For x = 0 To width - 1
          color = Point(x, y)
          Select plane
            Case 0 : PokeA(*line + x, Red(color))
            Case 1 : PokeA(*line + x, Green(color))
            Case 2 : PokeA(*line + x, Blue(color))
          EndSelect
        Next
        size = PCX_WriteRun(*line, bytesPerLine, *packed)
        WriteData(file, *packed, size)
      Next
    Next
    StopDrawing()
    result = #True
  EndIf
  If *line   : FreeMemory(*line)   : EndIf
  If *packed : FreeMemory(*packed) : EndIf
  CloseFile(file)
  ProcedureReturn result
EndProcedure
