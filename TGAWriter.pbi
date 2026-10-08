; TGAWriter.pbi - eigen TGA-encoder (PureBasic heeft geen UseTGAImageEncoder)
;
; Een ongecomprimeerde TGA bestaat uit:
;   18 bytes kop  - type, breedte, hoogte, bits per pixel, oriëntatie
;   pixels        - per pixel B,G,R (24-bit) of B,G,R,A (32-bit)
;   26 bytes voet - "TRUEVISION-XFILE." zodat programma's weten dat het TGA versie 2 is

#TGA_HeaderSize = 18
#TGA_FooterSize = 26

; Slaat een image op als TGA. Met WithAlpha = #True wordt het 32-bit (met transparantie),
; anders 24-bit. Geeft #True terug als het gelukt is.
Procedure.i TGA_Save(Image.i, FileName.s, WithAlpha.i = #True)
  Protected width.i, height.i, bpp.i, *buf, pos.i, x.i, y.i, color.i, file.i, result.i

  If IsImage(Image) = 0
    ProcedureReturn #False
  EndIf

  width  = ImageWidth(Image)
  height = ImageHeight(Image)
  If width > 65535 Or height > 65535      ; de kop heeft maar 16 bits voor de maten
    ProcedureReturn #False
  EndIf

  If WithAlpha
    bpp = 4
  Else
    bpp = 3
  EndIf

  ; AllocateMemory vult alles met nullen, dus velden die 0 moeten zijn hoeven we niet te zetten
  *buf = AllocateMemory(#TGA_HeaderSize + width * height * bpp + #TGA_FooterSize)
  If *buf = 0
    ProcedureReturn #False
  EndIf

  ; --- Kop ---
  PokeA(*buf + 0, 0)            ; lengte van het ID-veld: geen ID
  PokeA(*buf + 1, 0)            ; geen kleurenpalet
  PokeA(*buf + 2, 2)            ; type 2 = ongecomprimeerd, ware kleuren
  ; bytes 3-7: paletgegevens (0), bytes 8-11: x- en y-oorsprong (0)
  PokeW(*buf + 12, width)
  PokeW(*buf + 14, height)
  PokeA(*buf + 16, bpp * 8)     ; bits per pixel: 24 of 32
  If WithAlpha
    PokeA(*buf + 17, $28)       ; $20 = eerste rij is de bovenste, + 8 bits alfa
  Else
    PokeA(*buf + 17, $20)       ; $20 = eerste rij is de bovenste
  EndIf

  ; --- Pixels ---
  pos = #TGA_HeaderSize
  If StartDrawing(ImageOutput(Image))
    DrawingMode(#PB_2DDrawing_AllChannels)   ; zodat Point() ook het alfakanaal teruggeeft
    For y = 0 To height - 1
      For x = 0 To width - 1
        color = Point(x, y)
        PokeA(*buf + pos,     Blue(color))   ; TGA slaat de kleuren op als B,G,R(,A)
        PokeA(*buf + pos + 1, Green(color))
        PokeA(*buf + pos + 2, Red(color))
        If WithAlpha
          PokeA(*buf + pos + 3, Alpha(color))
        EndIf
        pos + bpp
      Next
    Next
    StopDrawing()
  EndIf

  ; --- Voet: 4 bytes extensie-offset (0), 4 bytes developer-offset (0), daarna de handtekening ---
  PokeS(*buf + pos + 8, "TRUEVISION-XFILE.", -1, #PB_Ascii)   ; PokeS zet zelf de afsluitende 0 erachter

  ; --- Naar schijf schrijven ---
  file = CreateFile(#PB_Any, FileName)
  If file
    If WriteData(file, *buf, MemorySize(*buf)) = MemorySize(*buf)
      result = #True
    EndIf
    CloseFile(file)
  EndIf

  FreeMemory(*buf)
  ProcedureReturn result
EndProcedure
