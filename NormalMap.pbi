; NormalMap.pbi - normal maps omzetten tussen spellen en engines
;
; Een normal map slaat per pixel een richting op (X, Y, Z) als kleur:
;   rood = X (links/rechts), groen = Y (boven/onder), blauw = Z (naar je toe)
;   0..255 betekent -1..+1, dus "recht naar voren" is (128, 128, 255): het bekende lichtblauw.
;
; NM_FlipGreen()    - Y omdraaien. Spellen verschillen hierin: "DirectX-stijl" (groen naar beneden)
;                     tegenover "OpenGL-stijl" (groen naar boven). Verkeerd = bulten lijken deuken.
; NM_FlipRed()      - X omdraaien (zelden nodig)
; NM_RebuildZ()     - blauw opnieuw uitrekenen uit rood en groen. Nodig als een programma alleen
;                     X en Y heeft opgeslagen (zoals BC5; GIMP toont die olijfgroen).
; NM_Normalize()    - elke richting weer lengte 1 geven (na schalen worden ze iets te kort)
; NM_FromHeight()   - van een grijs hoogteplaatje (licht = hoog) een normal map maken.
;                     Handig voor SS1-textures: die hebben geen normal maps, SS3 wel.

XIncludeFile "Channels.pbi"     ; CH_ReadPixels()

; Maakt van X, Y, Z (-1..1) een kleur (0..255).
Procedure.i NM_ToColor(x.d, y.d, z.d, Alpha.i = 255)
  ProcedureReturn RGBA(Int((x + 1) * 127.5 + 0.5), Int((y + 1) * 127.5 + 0.5), Int((z + 1) * 127.5 + 0.5), Alpha)
EndProcedure

; Basis voor de bewerkingen per pixel. Mode: 1 = groen om, 2 = rood om, 3 = Z uitrekenen, 4 = normaliseren.
Procedure.i NM_PerPixel(Image.i, Mode.i)
  Protected w.i = ImageWidth(Image), h.i = ImageHeight(Image), new.i, i.i, c.i, x.d, y.d, z.d, length.d
  Dim px.l(0)
  CH_ReadPixels(Image, px())
  new = CreateImage(#PB_Any, w, h, 32, #PB_Image_Transparent)
  If new And StartDrawing(ImageOutput(new))
    DrawingMode(#PB_2DDrawing_AllChannels)
    For i = 0 To w * h - 1
      c = px(i)
      Select Mode
        Case 1                                   ; groen omdraaien: 255 - groen
          Plot(i % w, i / w, RGBA(Red(c), 255 - Green(c), Blue(c), Alpha(c)))
        Case 2                                   ; rood omdraaien
          Plot(i % w, i / w, RGBA(255 - Red(c), Green(c), Blue(c), Alpha(c)))
        Case 3, 4
          x = Red(c) / 127.5 - 1
          y = Green(c) / 127.5 - 1
          If Mode = 3
            ; Z uitrekenen: de lengte van de richting is 1, dus z = wortel(1 - x² - y²)
            z = 1 - x * x - y * y
            If z < 0 : z = 0 : EndIf
            z = Sqr(z)
          Else
            z = Blue(c) / 127.5 - 1
            length = Sqr(x * x + y * y + z * z)
            If length > 0.0001
              x / length : y / length : z / length
            Else
              x = 0 : y = 0 : z = 1               ; geen richting: recht naar voren
            EndIf
          EndIf
          Plot(i % w, i / w, NM_ToColor(x, y, z, Alpha(c)))
      EndSelect
    Next
    StopDrawing()
  EndIf
  ProcedureReturn new
EndProcedure

Procedure.i NM_FlipGreen(Image.i)
  ProcedureReturn NM_PerPixel(Image, 1)
EndProcedure

Procedure.i NM_FlipRed(Image.i)
  ProcedureReturn NM_PerPixel(Image, 2)
EndProcedure

Procedure.i NM_RebuildZ(Image.i)
  ProcedureReturn NM_PerPixel(Image, 3)
EndProcedure

Procedure.i NM_Normalize(Image.i)
  ProcedureReturn NM_PerPixel(Image, 4)
EndProcedure

; Maakt een normal map van de helderheid van Image (licht = hoog, donker = laag).
; Strength: hoe sterk de bulten worden (1 = normaal, 2 = twee keer zo diep, ...).
; De randen lopen door ("tiling"), omdat textures meestal herhaald worden.
; De groene richting volgt de OpenGL-stijl (groen = omhoog); met NM_FlipGreen() wordt het DirectX-stijl.
Procedure.i NM_FromHeight(Image.i, Strength.d)
  Protected w.i = ImageWidth(Image), h.i = ImageHeight(Image), new.i, x.i, y.i, c.i
  Protected dx.d, dy.d, nx.d, ny.d, nz.d, length.d
  Dim px.l(0)
  CH_ReadPixels(Image, px())
  ; Hoogte per pixel (0..1) uit de helderheid
  Dim hgt.d(w * h - 1)
  For x = 0 To w * h - 1
    c = px(x)
    hgt(x) = (0.2126 * Red(c) + 0.7152 * Green(c) + 0.0722 * Blue(c)) / 255
  Next
  new = CreateImage(#PB_Any, w, h, 32)
  If new And StartDrawing(ImageOutput(new))
    DrawingMode(#PB_2DDrawing_AllChannels)
    For y = 0 To h - 1
      For x = 0 To w - 1
        ; Helling: verschil tussen de buren links/rechts en boven/onder (Sobel-filter)
        dx = (hgt(((y + h - 1) % h) * w + (x + 1) % w) + 2 * hgt(y * w + (x + 1) % w) + hgt(((y + 1) % h) * w + (x + 1) % w)) - (hgt(((y + h - 1) % h) * w + (x + w - 1) % w) + 2 * hgt(y * w + (x + w - 1) % w) + hgt(((y + 1) % h) * w + (x + w - 1) % w))
        dy = (hgt(((y + 1) % h) * w + (x + w - 1) % w) + 2 * hgt(((y + 1) % h) * w + x) + hgt(((y + 1) % h) * w + (x + 1) % w)) - (hgt(((y + h - 1) % h) * w + (x + w - 1) % w) + 2 * hgt(((y + h - 1) % h) * w + x) + hgt(((y + h - 1) % h) * w + (x + 1) % w))
        nx = -dx * Strength
        ny = dy * Strength                       ; groen omhoog (OpenGL-stijl)
        nz = 1
        length = Sqr(nx * nx + ny * ny + nz * nz)
        Plot(x, y, NM_ToColor(nx / length, ny / length, nz / length))
      Next
    Next
    StopDrawing()
  EndIf
  ProcedureReturn new
EndProcedure
