; Channels.pbi - kleurkanalen splitsen en samenvoegen
;
; Games gebruiken de kanalen van een texture verschillend. In SS3 zit bijvoorbeeld de glans in de
; alfa van de _GM-textures, terwijl een ander spel een apart grijs glansplaatje verwacht. Daarom:
;   CH_Extract()     - één kanaal (rood, groen, blauw of alfa) als grijs plaatje
;   CH_SetAlpha()    - de helderheid van een ander plaatje (bijv. een masker) als alfa gebruiken
;   CH_RemoveAlpha() - alles volledig dekkend maken
;   CH_InvertAlpha() - doorzichtig en dekkend omdraaien
; Elke functie maakt een nieuw image; het origineel blijft ongewijzigd.

XIncludeFile "Resize.pbi"       ; RSZ_Scale() als het masker een andere maat heeft

Enumeration ChannelType
  #CH_Red
  #CH_Green
  #CH_Blue
  #CH_Alpha
EndEnumeration

; Leest alle pixels van een image in een array (sneller dan steeds Point()).
Procedure CH_ReadPixels(Image.i, Array px.l(1))
  Protected x.i, y.i, w.i = ImageWidth(Image), h.i = ImageHeight(Image)
  ReDim px(w * h - 1)
  If StartDrawing(ImageOutput(Image))
    DrawingMode(#PB_2DDrawing_AllChannels)
    For y = 0 To h - 1
      For x = 0 To w - 1
        px(y * w + x) = Point(x, y)
      Next
    Next
    StopDrawing()
  EndIf
EndProcedure

; Maakt een grijs, volledig dekkend plaatje van één kanaal.
Procedure.i CH_Extract(Image.i, Channel.i)
  Protected w.i = ImageWidth(Image), h.i = ImageHeight(Image), new.i, x.i, y.i, c.i, v.i
  Dim px.l(0)
  CH_ReadPixels(Image, px())
  new = CreateImage(#PB_Any, w, h, 32)
  If new And StartDrawing(ImageOutput(new))
    DrawingMode(#PB_2DDrawing_AllChannels)
    For y = 0 To h - 1
      For x = 0 To w - 1
        c = px(y * w + x)
        Select Channel
          Case #CH_Red   : v = Red(c)
          Case #CH_Green : v = Green(c)
          Case #CH_Blue  : v = Blue(c)
          Case #CH_Alpha : v = Alpha(c)
        EndSelect
        Plot(x, y, RGBA(v, v, v, 255))
      Next
    Next
    StopDrawing()
  EndIf
  ProcedureReturn new
EndProcedure

; Gebruikt de helderheid van Mask als alfa voor Image: wit = dekkend, zwart = doorzichtig.
; Heeft Mask een andere maat, dan wordt hij eerst geschaald.
Procedure.i CH_SetAlpha(Image.i, Mask.i)
  Protected w.i = ImageWidth(Image), h.i = ImageHeight(Image), new.i, x.i, y.i, c.i, m.i, scaled.i, lum.i
  Dim px.l(0) : Dim mk.l(0)
  If ImageWidth(Mask) <> w Or ImageHeight(Mask) <> h
    scaled = RSZ_Scale(Mask, w, h)
    If scaled = 0 : ProcedureReturn 0 : EndIf
    CH_ReadPixels(scaled, mk())
    FreeImage(scaled)
  Else
    CH_ReadPixels(Mask, mk())
  EndIf
  CH_ReadPixels(Image, px())
  new = CreateImage(#PB_Any, w, h, 32, #PB_Image_Transparent)
  If new And StartDrawing(ImageOutput(new))
    DrawingMode(#PB_2DDrawing_AllChannels)
    For y = 0 To h - 1
      For x = 0 To w - 1
        c = px(y * w + x)
        m = mk(y * w + x)
        ; Helderheid van het masker (Rec. 709); bij een grijs masker is dat gewoon de grijswaarde
        lum = (2126 * Red(m) + 7152 * Green(m) + 722 * Blue(m) + 5000) / 10000
        Plot(x, y, RGBA(Red(c), Green(c), Blue(c), lum))
      Next
    Next
    StopDrawing()
  EndIf
  ProcedureReturn new
EndProcedure

; Maakt alle pixels volledig dekkend (de kleuren onder doorzichtige delen worden zichtbaar).
Procedure.i CH_RemoveAlpha(Image.i)
  Protected w.i = ImageWidth(Image), h.i = ImageHeight(Image), new.i, x.i, y.i, c.i
  Dim px.l(0)
  CH_ReadPixels(Image, px())
  new = CreateImage(#PB_Any, w, h, 32)
  If new And StartDrawing(ImageOutput(new))
    DrawingMode(#PB_2DDrawing_AllChannels)
    For y = 0 To h - 1
      For x = 0 To w - 1
        c = px(y * w + x)
        Plot(x, y, RGBA(Red(c), Green(c), Blue(c), 255))
      Next
    Next
    StopDrawing()
  EndIf
  ProcedureReturn new
EndProcedure

; Draait de alfa om: doorzichtig wordt dekkend en andersom.
Procedure.i CH_InvertAlpha(Image.i)
  Protected w.i = ImageWidth(Image), h.i = ImageHeight(Image), new.i, x.i, y.i, c.i
  Dim px.l(0)
  CH_ReadPixels(Image, px())
  new = CreateImage(#PB_Any, w, h, 32, #PB_Image_Transparent)
  If new And StartDrawing(ImageOutput(new))
    DrawingMode(#PB_2DDrawing_AllChannels)
    For y = 0 To h - 1
      For x = 0 To w - 1
        c = px(y * w + x)
        Plot(x, y, RGBA(Red(c), Green(c), Blue(c), 255 - Alpha(c)))
      Next
    Next
    StopDrawing()
  EndIf
  ProcedureReturn new
EndProcedure
