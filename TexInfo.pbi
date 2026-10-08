; TexInfo.pbi - gedeelde gegevens voor alle texture-lezers
; Hier staat de structuur TexInfo die TexReader.pbi (SE1), TexReaderSE2.pbi (SE2) en
; TexReaderSE3.pbi (SE3) vullen. Elk bestand dat TexInfo gebruikt doet XIncludeFile "TexInfo.pbi";
; de X zorgt dat het maar één keer wordt ingevoegd, ook als meerdere bestanden het vragen.

#TEX_ALPHACHANNEL = 1   ; bit 0: de texture heeft een alfakanaal (transparantie)
#TEX_32BIT        = 2   ; bit 1: alleen een hint voor het spel, verandert de opslag niet

Structure TexInfo
  Engine.l              ; 1, 2 of 3 = Serious Engine 1, 2 of 3
  EngineVersion.s       ; versietekst uit een SE2/SE3-bestand
  FormatName.s          ; naam van het SE2/SE3-formaat, zoals in Serious Editor
  Version.l             ; texture-versie uit een SE1-bestand (3 of 4)
  Flags.l               ; vlaggen (#TEX_ALPHACHANNEL, #TEX_32BIT)
  Width.l               ; breedte in pixels
  Height.l              ; hoogte in pixels
  MipLevels.l           ; aantal mipmap-niveaus (alleen informatief)
  FirstMip.l            ; nodig om mex-maten om te rekenen naar pixels
  Frames.l              ; aantal frames (plaatjes) in het bestand
  BytesPerPixel.l       ; 2 (versie 3), 3 of 4
  HasAlpha.l            ; #True als het plaatje transparantie heeft
  DataOffset.l          ; waar de pixels van frame 0 beginnen
  FrameStride.l         ; aantal bytes van het begin van een frame tot het begin van het volgende
  IsEffect.l            ; #True voor een effect-texture
  EffectType.l          ; nummer van het effecttype
  BufferWidth.l         ; maten van de effectbuffer
  BufferHeight.l
  BaseTexture.s         ; naam van de basistexture van een effect (zoals in het spel opgeslagen)
  BaseShown.s           ; naam van de texture die uiteindelijk getoond wordt (kan dieper in de keten zitten)
  IsHDR.l               ; #True voor een HDR-texture (SE3, formaat 12)
  *HdrData              ; HDR: kopie van de pixels als R,G,B,E (4 bytes per pixel), voor opslaan als .hdr.
                        ; Wie TexInfo gebruikt, ruimt dit op met TEX_FreeInfo().
  Note.s                ; extra uitleg voor de gebruiker (bijv. wat er bij een effect getoond wordt)
  Error.s               ; foutmelding als het laden mislukt
EndStructure

; Geeft het geheugen vrij dat bij een TexInfo hoort (op dit moment alleen de HDR-data).
Procedure TEX_FreeInfo(*Info.TexInfo)
  If *Info\HdrData
    FreeMemory(*Info\HdrData)
    *Info\HdrData = 0
  EndIf
EndProcedure
