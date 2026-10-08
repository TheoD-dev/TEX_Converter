; DXT.pbi - eigen decoder voor DXT1, DXT3, DXT5 en BC5 (ook bekend als BC1, BC2, BC3 en BC5)
;
; DXT deelt een plaatje op in blokjes van 4 x 4 pixels. Per blokje worden opgeslagen:
;   - twee kleuren in 16-bit (5 bits rood, 6 bits groen, 5 bits blauw)
;   - per pixel 2 bits die zeggen welke van 4 kleuren de pixel krijgt
;     (de twee opgeslagen kleuren en twee tussenkleuren die je zelf uitrekent)
; DXT1: 8 bytes per blok, alleen kleur (eventueel 1 bit transparantie).
; DXT3: 16 bytes per blok: eerst 8 bytes alfa (4 bits per pixel), dan een kleurblok.
; DXT5: 16 bytes per blok: eerst 8 bytes alfa (2 alfawaarden + 3 bits per pixel), dan een kleurblok.
; BC5:  16 bytes per blok: twee keer zo'n DXT5-alfablok, voor X en Y van een normal map.
;       Z (blauw) staat er niet in; die reken je uit omdat de lengte van een normaal 1 is.
;
; Alleen het grootste mipmap-niveau wordt gedecodeerd; dat staat altijd vooraan.

Enumeration DXTType 1
  #DXT1
  #DXT3
  #DXT5
  #BC5
EndEnumeration

; Geeft het aantal bytes van het grootste mipmap-niveau.
Procedure.i DXT_DataSize(Width.i, Height.i, Type.i)
  Protected blocks.i = ((Width + 3) / 4) * ((Height + 3) / 4)
  If Type = #DXT1
    ProcedureReturn blocks * 8
  EndIf
  ProcedureReturn blocks * 16
EndProcedure

; Zet een 16-bit kleur (5-6-5) om in losse waarden 0..255.
Procedure DXT_Color565(Value.i, Array kleur.i(1), Index.i)
  kleur(Index * 3)     = ((Value >> 11) & 31) * 255 / 31     ; rood
  kleur(Index * 3 + 1) = ((Value >> 5) & 63) * 255 / 63      ; groen
  kleur(Index * 3 + 2) = (Value & 31) * 255 / 31             ; blauw
EndProcedure

; Decodeert een alfablok zoals in DXT5 (8 bytes) naar 16 waarden 0..255.
; Wordt ook gebruikt voor de twee kanalen van BC5.
Procedure DXT_AlphaBlock(*Src, Array waarde.i(1))
  Protected i.i, bits.q
  Dim palette.i(7)       ; de 8 mogelijke waarden

  palette(0) = PeekA(*Src)
  palette(1) = PeekA(*Src + 1)
  If palette(0) > palette(1)
    For i = 1 To 6                     ; 6 tussenwaarden
      palette(i + 1) = ((7 - i) * palette(0) + i * palette(1)) / 7
    Next
  Else
    For i = 1 To 4                     ; 4 tussenwaarden, plus 0 en 255
      palette(i + 1) = ((5 - i) * palette(0) + i * palette(1)) / 5
    Next
    palette(6) = 0
    palette(7) = 255
  EndIf
  ; 48 bits met per pixel 3 bits (welke van de 8 waarden)
  bits = PeekQ(*Src + 2) & $FFFFFFFFFFFF
  For i = 0 To 15
    waarde(i) = palette((bits >> (3 * i)) & 7)
  Next
EndProcedure

; Decodeert DXT-data naar een nieuw 32-bit image. Geeft het image-nummer terug, of 0.
Procedure.i DXT_Decode(*Data, DataSize.i, Width.i, Height.i, Type.i)
  Protected image.i, bx.i, by.i, x.i, y.i, i.i, px.i, py.i
  Protected *block, *color, c0.i, c1.i, indices.i, idx.i, a.i, blockSize.i
  Protected nx.d, ny.d, nz.d
  Dim kleur.i(11)        ; 4 kleuren x 3 waarden (R,G,B)
  Dim alfa.i(15)         ; alfa per pixel in het huidige blok
  Dim kanaalX.i(15)      ; BC5: X per pixel
  Dim kanaalY.i(15)      ; BC5: Y per pixel

  If Type = #DXT1
    blockSize = 8
  Else
    blockSize = 16
  EndIf
  If DataSize < DXT_DataSize(Width, Height, Type)
    ProcedureReturn 0
  EndIf

  image = CreateImage(#PB_Any, Width, Height, 32, #PB_Image_Transparent)
  If image = 0 Or StartDrawing(ImageOutput(image)) = 0
    ProcedureReturn image
  EndIf
  DrawingMode(#PB_2DDrawing_AllChannels)

  *block = *Data
  For by = 0 To (Height + 3) / 4 - 1
    For bx = 0 To (Width + 3) / 4 - 1

      If Type = #BC5
        ; --- Normal map: X en Y uit twee alfablokken, Z uitrekenen ---
        DXT_AlphaBlock(*block, kanaalX())
        DXT_AlphaBlock(*block + 8, kanaalY())
        For y = 0 To 3
          For x = 0 To 3
            px = bx * 4 + x
            py = by * 4 + y
            If px < Width And py < Height
              i = y * 4 + x
              nx = kanaalX(i) / 127.5 - 1       ; 0..255 omrekenen naar -1..1
              ny = kanaalY(i) / 127.5 - 1
              nz = 1 - nx * nx - ny * ny
              If nz < 0 : nz = 0 : EndIf
              nz = Sqr(nz)
              Plot(px, py, RGBA(kanaalX(i), kanaalY(i), Int((nz + 1) * 127.5), 255))
            EndIf
          Next
        Next
        *block + blockSize
        Continue
      EndIf

      ; --- Alfa van dit blok ---
      Select Type
        Case #DXT1
          For i = 0 To 15 : alfa(i) = 255 : Next
          *color = *block

        Case #DXT3
          ; 16 pixels x 4 bits; de lage 4 bits van een byte zijn de eerste pixel
          For i = 0 To 15
            a = PeekA(*block + i / 2)
            If i & 1
              a = a >> 4
            EndIf
            alfa(i) = (a & 15) * 17           ; 0..15 omrekenen naar 0..255
          Next
          *color = *block + 8

        Case #DXT5
          DXT_AlphaBlock(*block, alfa())
          *color = *block + 8
      EndSelect

      ; --- Kleuren van dit blok ---
      c0 = PeekU(*color)
      c1 = PeekU(*color + 2)
      indices = PeekL(*color + 4) & $FFFFFFFF
      DXT_Color565(c0, kleur(), 0)
      DXT_Color565(c1, kleur(), 1)
      If c0 > c1 Or Type <> #DXT1
        ; 4 kleuren: twee tussenkleuren op 1/3 en 2/3
        For i = 0 To 2
          kleur(6 + i) = (2 * kleur(i) + kleur(3 + i)) / 3
          kleur(9 + i) = (kleur(i) + 2 * kleur(3 + i)) / 3
        Next
      Else
        ; DXT1 met c0 <= c1: 3 kleuren, de vierde betekent "doorzichtig"
        For i = 0 To 2
          kleur(6 + i) = (kleur(i) + kleur(3 + i)) / 2
          kleur(9 + i) = 0
        Next
      EndIf

      ; --- De 16 pixels tekenen ---
      For y = 0 To 3
        For x = 0 To 3
          px = bx * 4 + x
          py = by * 4 + y
          If px < Width And py < Height       ; blokjes aan de rand kunnen buiten het plaatje vallen
            i = y * 4 + x
            idx = (indices >> (2 * i)) & 3
            a = alfa(i)
            If Type = #DXT1 And idx = 3 And c0 <= c1
              a = 0
            EndIf
            Plot(px, py, RGBA(kleur(idx * 3), kleur(idx * 3 + 1), kleur(idx * 3 + 2), a))
          EndIf
        Next
      Next

      *block + blockSize
    Next
  Next

  StopDrawing()
  ProcedureReturn image
EndProcedure
