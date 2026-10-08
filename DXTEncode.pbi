; DXTEncode.pbi - eigen encoder voor DXT1, DXT5 en BC5 (het omgekeerde van DXT.pbi)
;
; Per blokje van 4 x 4 pixels moeten we twee eindkleuren kiezen en per pixel aangeven welke van de
; 4 kleuren (de twee eindkleuren en twee tussenkleuren) er het dichtst bij ligt.
; Hoe we de eindkleuren kiezen ("bounding box"):
;   - per kanaal de kleinste en grootste waarde in het blokje nemen
;   - loopt rood (of blauw) tegengesteld aan groen, dan die twee omdraaien, zodat de lijn tussen
;     de eindkleuren de richting van de kleuren in het blokje volgt
;   - de eindpunten een klein stukje (1/16) naar binnen schuiven; dat geeft gemiddeld minder fout
; Dit is niet de allerbeste methode, maar wel snel en goed genoeg voor textures.

XIncludeFile "DXT.pbi"          ; #DXT1, #DXT5, #BC5 en DXT_Color565()

; Zet R,G,B (0..255) om naar een 16-bit kleur (5 bits rood, 6 groen, 5 blauw), afgerond.
Procedure.i DXTE_To565(r.i, g.i, b.i)
  ProcedureReturn ((r * 31 + 127) / 255) << 11 | ((g * 63 + 127) / 255) << 5 | ((b * 31 + 127) / 255)
EndProcedure

; Codeert één kleurblok (8 bytes) op *Out. Pixels: 16 keer R,G,B in Array px(). Altijd 4-kleurenmodus.
Procedure DXTE_ColorBlock(Array px.i(1), *Out)
  Protected i.i, c.i, lo.i, hi.i, t.i, c0.i, c1.i, best.i, bestD.i, d.i, dr.i, dg.i, db.i, indices.i
  Protected covRG.d, covBG.d, mR.d, mG.d, mB.d, inset.i
  Dim mn.i(2) : Dim mx.i(2) : Dim pal.i(11)

  ; Kleinste en grootste waarde per kanaal, en gemiddelden
  For c = 0 To 2 : mn(c) = 255 : mx(c) = 0 : Next
  For i = 0 To 15
    For c = 0 To 2
      t = px(i * 3 + c)
      If t < mn(c) : mn(c) = t : EndIf
      If t > mx(c) : mx(c) = t : EndIf
    Next
    mR + px(i * 3) : mG + px(i * 3 + 1) : mB + px(i * 3 + 2)
  Next
  mR / 16 : mG / 16 : mB / 16
  ; Loopt rood of blauw tegengesteld aan groen? Dan die as omdraaien
  For i = 0 To 15
    covRG + (px(i * 3) - mR) * (px(i * 3 + 1) - mG)
    covBG + (px(i * 3 + 2) - mB) * (px(i * 3 + 1) - mG)
  Next
  ; Een klein stukje naar binnen schuiven
  For c = 0 To 2
    inset = (mx(c) - mn(c)) / 16
    mn(c) + inset : mx(c) - inset
  Next
  If covRG < 0 : t = mn(0) : mn(0) = mx(0) : mx(0) = t : EndIf
  If covBG < 0 : t = mn(2) : mn(2) = mx(2) : mx(2) = t : EndIf

  c0 = DXTE_To565(mx(0), mx(1), mx(2))
  c1 = DXTE_To565(mn(0), mn(1), mn(2))
  If c0 < c1                              ; 4-kleurenmodus vraagt c0 > c1: omwisselen
    t = c0 : c0 = c1 : c1 = t
  EndIf
  If c0 = c1
    ; Eén kleur voor het hele blokje: alle indexen 0
    PokeU(*Out, c0) : PokeU(*Out + 2, c1) : PokeL(*Out + 4, 0)
    ProcedureReturn
  EndIf

  ; Het palet uitrekenen zoals de decoder dat doet, en per pixel de dichtstbijzijnde kleur kiezen
  DXT_Color565(c0, pal(), 0)
  DXT_Color565(c1, pal(), 1)
  For c = 0 To 2
    pal(6 + c) = (2 * pal(c) + pal(3 + c)) / 3
    pal(9 + c) = (pal(c) + 2 * pal(3 + c)) / 3
  Next
  indices = 0
  For i = 0 To 15
    bestD = $7FFFFFFF : best = 0
    For c = 0 To 3
      dr = px(i * 3) - pal(c * 3) : dg = px(i * 3 + 1) - pal(c * 3 + 1) : db = px(i * 3 + 2) - pal(c * 3 + 2)
      d = dr * dr + dg * dg + db * db
      If d < bestD : bestD = d : best = c : EndIf
    Next
    indices | (best << (2 * i))
  Next
  PokeU(*Out, c0) : PokeU(*Out + 2, c1) : PokeL(*Out + 4, indices)
EndProcedure

; Codeert één alfablok zoals in DXT5 (8 bytes) op *Out; waarden: 16 getallen 0..255 in Array v().
; Ook gebruikt voor de twee kanalen van BC5.
Procedure DXTE_AlphaBlock(Array v.i(1), *Out)
  Protected i.i, j.i, lo.i = 255, hi.i = 0, best.i, bestD.i, d.i, bits.q
  Dim pal.i(7)
  For i = 0 To 15
    If v(i) < lo : lo = v(i) : EndIf
    If v(i) > hi : hi = v(i) : EndIf
  Next
  PokeA(*Out, hi) : PokeA(*Out + 1, lo)
  If hi = lo
    For i = 2 To 7 : PokeA(*Out + i, 0) : Next   ; overal index 0 = hi
    ProcedureReturn
  EndIf
  ; hi > lo: 8 waarden (de twee eindwaarden en 6 tussenwaarden), zoals DXT_AlphaBlock in DXT.pbi
  pal(0) = hi : pal(1) = lo
  For i = 1 To 6
    pal(i + 1) = ((7 - i) * hi + i * lo) / 7
  Next
  For i = 0 To 15
    bestD = 1000 : best = 0
    For j = 0 To 7
      d = Abs(v(i) - pal(j))
      If d < bestD : bestD = d : best = j : EndIf
    Next
    bits | (best << (3 * i))
  Next
  For i = 0 To 5
    PokeA(*Out + 2 + i, (bits >> (8 * i)) & 255)
  Next
EndProcedure

; Codeert een heel image (één mipmap-niveau) en schrijft het naar het geopende bestand File.
; Type: #DXT1, #DXT5 of #BC5. Geeft het aantal geschreven bytes terug.
Procedure.i DXTE_WriteLevel(File.i, Image.i, Type.i)
  Protected w.i = ImageWidth(Image), h.i = ImageHeight(Image), bx.i, by.i, x.i, y.i, i.i, sx.i, sy.i
  Protected c.i, blockSize.i, written.i, *block
  Dim all.l(w * h - 1)
  Dim px.i(47) : Dim av.i(15) : Dim gv.i(15)

  If StartDrawing(ImageOutput(Image))
    DrawingMode(#PB_2DDrawing_AllChannels)
    For y = 0 To h - 1
      For x = 0 To w - 1
        all(y * w + x) = Point(x, y)
      Next
    Next
    StopDrawing()
  EndIf

  If Type = #DXT1 : blockSize = 8 : Else : blockSize = 16 : EndIf
  *block = AllocateMemory(16)
  For by = 0 To (h + 3) / 4 - 1
    For bx = 0 To (w + 3) / 4 - 1
      ; De 16 pixels van dit blokje; buiten het plaatje herhalen we de randpixel
      For i = 0 To 15
        sx = bx * 4 + (i % 4) : If sx >= w : sx = w - 1 : EndIf
        sy = by * 4 + (i / 4) : If sy >= h : sy = h - 1 : EndIf
        c = all(sy * w + sx)
        px(i * 3) = Red(c) : px(i * 3 + 1) = Green(c) : px(i * 3 + 2) = Blue(c)
        av(i) = Alpha(c)
        gv(i) = Green(c)
      Next
      Select Type
        Case #DXT1
          DXTE_ColorBlock(px(), *block)
        Case #DXT5
          DXTE_AlphaBlock(av(), *block)
          DXTE_ColorBlock(px(), *block + 8)
        Case #BC5
          ; Normal map: eerste helft = rood (X), tweede helft = groen (Y)
          For i = 0 To 15 : av(i) = px(i * 3) : Next
          DXTE_AlphaBlock(av(), *block)
          DXTE_AlphaBlock(gv(), *block + 8)
      EndSelect
      WriteData(File, *block, blockSize)
      written + blockSize
    Next
  Next
  FreeMemory(*block)
  ProcedureReturn written
EndProcedure
