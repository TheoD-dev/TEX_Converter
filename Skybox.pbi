; Skybox.pbi - een complete skybox-set (5 vlakken) bekijken en omzetten
;
; Een SS3-skybox is een kubus rond de speler, zonder onderkant:
;   N, E, S, W - de zijkanten (noord, oost, zuid, west). Alleen de BOVENSTE helft is opgeslagen,
;                dus 1024 x 512: de onderrand is de horizon.
;   C          - de bovenkant ("ceiling"), 1024 x 1024.
; Uitgezocht met HDR_Cloudy04 door de randen te vergelijken: de bovenrand van N sluit aan op de
; onderrand van C, die van E op de rechterrand van C (van onder naar boven), die van S op de
; bovenrand van C (van rechts naar links) en die van W op de linkerrand van C (van boven naar onder).
;
; De bestanden heten bijv. HDR_Cloudy04_N.tex of HDR_Cloudy05_C--Big.tex: de letter na de laatste "_"
; is het vlak. Kies je één vlak, dan zoekt SKY_FindSet() de andere erbij (in dezelfde map of .gro).
;
; Alle vlakken krijgen dezelfde belichting (TEXSE3_ExposureEV en TEXSE3_ToneMode), zodat de randen
; op elkaar aansluiten. Exporteren kan als:
;   - losse vlakken (in elk formaat)
;   - strook: W N E S naast elkaar (rondom-beeld van de horizon)
;   - kruis: C boven N, met W N E S eronder
;   - 360-graden-panorama ("equirectangular", 2:1), zoals veel andere games en programma's gebruiken.
;     Onder de horizon is geen beeld; daar komt de gemiddelde kleur van de horizon (de onderste rij).
; Zijn alle vlakken HDR, dan kan alles ook als .hdr met behoud van alle helderheid.

XIncludeFile "TexReader.pbi"
XIncludeFile "ImageReader.pbi"
XIncludeFile "GroReader.pbi"
XIncludeFile "TGAWriter.pbi"
XIncludeFile "TIFFWriter.pbi"
XIncludeFile "HDRWriter.pbi"
XIncludeFile "TexWriterSE1.pbi"

#SKY_Faces = 6                  ; N, E, S, W, boven (C) en eventueel onder (D)
#SKY_Letters = "NESWCD"         ; volgorde van de vlakken in SKY_Face(); D (onder) is niet verplicht
#SKY_Labels = "NESWUD"          ; zo heten ze in het venster: U = up (boven), D = down (onder)

Structure SkyFace
  Letter.s
  Path.s                        ; bestand op schijf, of "archief.gro::Content/..."
  Name.s                        ; alleen de bestandsnaam (voor het opslaan)
  Loaded.i
  Width.i
  Height.i
  IsHDR.i
  *Rgbe                         ; HDR: pixels als Radiance R,G,B,E (E in hele stops)
  Image.i                       ; plaatje zoals getoond (bij HDR met de huidige belichting)
EndStructure

Global Dim SKY_Face.SkyFace(#SKY_Faces - 1)
Global SKY_SetName.s
Global SKY_Dir.s                ; map voor openen en opslaan (komt van het hoofdprogramma)

Global SKY_Win.i, SKY_Canvas.i, SKY_Info.i, SKY_EV.i, SKY_Tone.i, SKY_Kind.i, SKY_Format.i, SKY_Bar.i

; Laat zien hoe ver een langzame bewerking is: tekst en voortgangsbalk in het skyboxvenster.
; Daarna even de wachtende gebeurtenissen afhandelen, zodat het venster zichzelf kan tekenen.
; (Klikken tijdens het werk worden daarbij genegeerd; dat is hier juist goed.)
Procedure SKY_Progress(Text.s, Done.i, Total.i)
  If Not IsWindow(SKY_Win)
    ProcedureReturn                     ; geen venster (bijv. in een testprogramma)
  EndIf
  If Total > 0
    SetGadgetState(SKY_Bar, Done * 100 / Total)
  Else
    SetGadgetState(SKY_Bar, 0)
  EndIf
  SetGadgetText(SKY_Info, Text)
  While WindowEvent() : Wend
EndProcedure
; Ruimt alle geladen vlakken op.
Procedure SKY_Clear()
  Protected i.i
  For i = 0 To #SKY_Faces - 1
    If SKY_Face(i)\Rgbe : FreeMemory(SKY_Face(i)\Rgbe) : EndIf
    If SKY_Face(i)\Image And IsImage(SKY_Face(i)\Image) : FreeImage(SKY_Face(i)\Image) : EndIf
    ClearStructure(@SKY_Face(i), SkyFace)
    SKY_Face(i)\Letter = Mid(#SKY_Labels, i + 1, 1)
  Next
  SKY_SetName = ""
EndProcedure

; ---------------------------------------------------------------------------------------------
; Namen van skybox-vlakken herkennen. Drie soorten komen voor:
;   letters  - HDR_Cloudy04_N.tex, ..._C--Big.tex          (SS3: N, E, S, W, C)
;   woorden  - 1_3_nightFront.tex, ...Right, Back, Left, Up (SS1), of North, East, South, West, Top/Bottom
;   nummers  - Storm1..5, Frame0001..0005, MDG01_Daylight_01..05, Mdigbo_..._0000..0004 (SS1, SS2)
; Uit de voorbeeldsets blijkt dat nummers altijd in de volgorde N, E, S, W, bovenkant staan;
; dat is gecontroleerd door de randen van de vlakken te vergelijken.
; ---------------------------------------------------------------------------------------------
; Woorden per vlak in de volgorde N, E, S, W, C (boven), D (onder); per vlak gescheiden door |
; De korte vormen ft, rt, bk, lf, (up,) dn zijn de Quake/Half-Life-namen (sky_rt.tex). Die tellen alleen
; met een _ of - ervoor, anders zou bijv. "Desert" als "rt" herkend worden (zie #SKY_ShortWords).
#SKY_Words = "front|forward|north|ft,right|east|rt,back|south|bk,left|west|lf,up|top|ceiling,down|bottom|floor|dn"
#SKY_ShortWords = ",ft,rt,bk,lf,dn,"
; Gewone "cubemap"-namen: pz = +Z (N), px = +X (E), nz = -Z (S), nx = -X (W), py = +Y (boven), ny = -Y (onder).
; Getest met een complete set: de randen passen met precies deze indeling (OpenGL-stijl).
#SKY_CubeNames = "pz,px,nz,nx,py,ny"
#SKY_CubeNamesLong = "posz,posx,negz,negx,posy,negy"   ; zelfde, voluit (bijv. Unity, three.js)

; Zoekt in een naam als "HDR_Cloudy05_C--Big.tex" de plek van de vlakletter (hier de C).
; Geeft de positie terug (1 = eerste teken), of 0 als het geen letter-naam is.
Procedure.i SKY_LetterPos(Name.s)
  Protected base.s = GetFilePart(Name, #PB_FileSystem_NoExtension), i.i, nextChar.s
  For i = Len(base) - 1 To 1 Step -1
    ; U (up) mag ook voor de bovenkant, naast C (ceiling) zoals in SS3
    If Mid(base, i, 1) = "_" And FindString(#SKY_Letters + "U", UCase(Mid(base, i + 1, 1)))
      nextChar = Mid(base, i + 2, 1)
      If nextChar = "" Or nextChar = "-"
        ProcedureReturn i + 1
      EndIf
    EndIf
  Next
  ProcedureReturn 0
EndProcedure

; Eindigt de naam (zonder extensie) op een vlakwoord? Geeft de lengte van dat woord, of 0.
Procedure.i SKY_WordLength(Name.s)
  Protected base.s = LCase(GetFilePart(Name, #PB_FileSystem_NoExtension)), i.i, j.i, words.s, word.s
  For i = 1 To 6
    words = StringField(#SKY_Words, i, ",")
    For j = 1 To CountString(words, "|") + 1
      word = StringField(words, j, "|")
      If Right(base, Len(word)) = word And Len(base) > Len(word)
        If Not FindString(#SKY_ShortWords, "," + word + ",") Or FindString("_-", Mid(base, Len(base) - Len(word), 1))
          ProcedureReturn Len(word)
        EndIf
      EndIf
    Next
  Next
  ProcedureReturn 0
EndProcedure

; Eindigt de naam op posx, negx, ... (4 tekens) of px, nx, py, ny, pz, nz (2 tekens)?
; Geeft de lengte van die naam (4 of 2), of 0.
Procedure.i SKY_IsCubeName(Name.s)
  Protected base.s = LCase(GetFilePart(Name, #PB_FileSystem_NoExtension))
  If Len(base) >= 4 And FindString("," + #SKY_CubeNamesLong + ",", "," + Right(base, 4) + ",")
    ProcedureReturn 4
  EndIf
  If Len(base) >= 2 And FindString("," + #SKY_CubeNames + ",", "," + Right(base, 2) + ",")
    ProcedureReturn 2
  EndIf
  ProcedureReturn 0
EndProcedure

; Aantal cijfers aan het eind van de naam (zonder extensie), bijv. 4 bij "Frame0003".
Procedure.i SKY_DigitCount(Name.s)
  Protected base.s = GetFilePart(Name, #PB_FileSystem_NoExtension), n.i
  While n < Len(base) And FindString("0123456789", Mid(base, Len(base) - n, 1))
    n + 1
  Wend
  ProcedureReturn n
EndProcedure

; Kan dit een skybox-vlak zijn (letter, woord of nummer)?
Procedure.i SKY_IsFaceName(Name.s)
  ProcedureReturn Bool(SKY_LetterPos(Name) Or SKY_WordLength(Name) Or SKY_IsCubeName(Name) Or SKY_DigitCount(Name))
EndProcedure
; Laadt één vlak (van schijf of uit een .gro). Bewaart de HDR-data als die er is.
Procedure.i SKY_LoadFace(Index.i, Path.s)
  Protected info.TexInfo, image.i, *mem, size.i, ext.s
  If GRO_IsGroPath(Path)
    *mem = GRO_Extract(GRO_ArchivePart(Path), GRO_EntryPart(Path), @size)
    If *mem
      image = TEX_LoadMemory(*mem, size, @info, "")
      FreeMemory(*mem)
    EndIf
    SKY_Face(Index)\Name = GRO_EntryFileName(GRO_EntryPart(Path))
  Else
    ext = LCase(GetExtensionPart(Path))
    If ext = "tex"
      image = TEX_Load(Path, @info)
    Else
      image = IMG_Load(Path, @info)
    EndIf
    SKY_Face(Index)\Name = GetFilePart(Path)
  EndIf
  If image = 0
    TEX_FreeInfo(@info)
    ProcedureReturn #False
  EndIf
  SKY_Face(Index)\Path = Path
  SKY_Face(Index)\Loaded = #True
  SKY_Face(Index)\Width = ImageWidth(image)
  SKY_Face(Index)\Height = ImageHeight(image)
  SKY_Face(Index)\IsHDR = Bool(info\IsHDR And info\HdrData)
  SKY_Face(Index)\Rgbe = info\HdrData        ; de skybox neemt het geheugen over
  info\HdrData = 0
  SKY_Face(Index)\Image = image
  ProcedureReturn #True
EndProcedure

; Bestaat dit bestand in de map (of in het .gro-archief)? Geeft het volledige pad terug, of "".
Procedure.s SKY_Exists(Archive.s, Folder.s, Candidate.s)
  If Archive <> ""
    ForEach GRO_Entries()
      If LCase(GRO_Entries()\Name) = LCase(Folder + Candidate)
        ProcedureReturn Archive + #GRO_Separator + GRO_Entries()\Name
      EndIf
    Next
    ProcedureReturn ""
  EndIf
  ProcedureReturn TEX_FindFile(Folder, Candidate)
EndProcedure

; Zoekt bij één gekozen vlak de hele set en laadt die. Geeft het aantal gevonden vlakken terug.
Procedure.i SKY_FindSet(Path.s)
  Protected name.s, folder.s, ext.s, base.s, prefix.s, pos.i, i.i, j.i, archive.s, entry.s, count.i
  Protected digits.i, number.i, first.i, ok.i, wordLen.i, word.s
  Dim found.s(#SKY_Faces - 1)

  SKY_Clear()
  If GRO_IsGroPath(Path)
    archive = GRO_ArchivePart(Path)
    entry = GRO_EntryPart(Path)
    name = GRO_EntryFileName(entry)
    folder = Left(entry, Len(entry) - Len(name))
    GRO_ReadList(archive)
  Else
    name = GetFilePart(Path)
    folder = GetPathPart(Path)
  EndIf
  ext = GetExtensionPart(name)
  base = GetFilePart(name, #PB_FileSystem_NoExtension)

  pos = SKY_LetterPos(name)
  wordLen = SKY_WordLength(name)
  digits = SKY_DigitCount(name)
  If pos
    ; --- Letters: HDR_Cloudy04_N ---
    prefix = Left(name, pos - 2)
    For i = 0 To #SKY_Faces - 1
      found(i) = SKY_Exists(archive, folder, Left(name, pos - 1) + Mid(#SKY_Letters, i + 1, 1) + Mid(name, pos + 1))
      If found(i) = "" And i = 4
        found(i) = SKY_Exists(archive, folder, Left(name, pos - 1) + "U" + Mid(name, pos + 1))   ; boven als _U
      EndIf
    Next
  ElseIf SKY_IsCubeName(name)
    ; --- Cubemap: px, nx, py, ny, pz, nz ---
    If SKY_IsCubeName(name) = 4
      prefix = Left(base, Len(base) - 4)
      For i = 0 To #SKY_Faces - 1
        found(i) = SKY_Exists(archive, folder, prefix + StringField(#SKY_CubeNamesLong, i + 1, ",") + "." + ext)
      Next
    Else
      prefix = Left(base, Len(base) - 2)
      For i = 0 To #SKY_Faces - 1
        found(i) = SKY_Exists(archive, folder, prefix + StringField(#SKY_CubeNames, i + 1, ",") + "." + ext)
      Next
    EndIf
  ElseIf wordLen
    ; --- Woorden: 1_3_nightFront ---
    prefix = Left(base, Len(base) - wordLen)
    For i = 0 To #SKY_Faces - 1
      ; Alle woorden voor dit vlak proberen (Front, Forward, North, ...)
      For j = 1 To CountString(StringField(#SKY_Words, i + 1, ","), "|") + 1
        found(i) = SKY_Exists(archive, folder, prefix + StringField(StringField(#SKY_Words, i + 1, ","), j, "|") + "." + ext)
        If found(i) <> "" : Break : EndIf
      Next
    Next
  ElseIf digits
    ; --- Nummers: Storm3, MDG01_Daylight_02, Frame0004 ---
    ; Zoek 5 opeenvolgende nummers waar het gekozen bestand bij hoort
    prefix = Left(base, Len(base) - digits)
    number = Val(Right(base, digits))
    For first = number - 4 To number
      If first < 0 : Continue : EndIf
      ok = #True
      For j = 0 To 4                       ; genummerde sets hebben 5 vlakken
        found(j) = SKY_Exists(archive, folder, prefix + RSet(Str(first + j), digits, "0") + "." + ext)
        If found(j) = "" : ok = #False : Break : EndIf
      Next
      If ok : Break : EndIf
    Next
    If Not ok
      For j = 0 To #SKY_Faces - 1 : found(j) = "" : Next
    EndIf
  Else
    ProcedureReturn 0
  EndIf

  ; Naam van de set: het gemeenschappelijke begin, zonder "_" of "-" aan het eind
  SKY_SetName = prefix
  While SKY_SetName <> "" And FindString("_-", Right(SKY_SetName, 1))
    SKY_SetName = Left(SKY_SetName, Len(SKY_SetName) - 1)
  Wend
  If SKY_SetName = ""
    ; Geen gemeenschappelijk begin (bijv. px.tex, nx.tex, ...): dan de naam van de map
    SKY_SetName = ReplaceString(Left(folder, Len(folder) - 1), "\", "/")
    SKY_SetName = StringField(SKY_SetName, CountString(SKY_SetName, "/") + 1, "/")
    If SKY_SetName = "" : SKY_SetName = "Skybox" : EndIf
  EndIf

  For i = 0 To #SKY_Faces - 1
    SKY_Progress("Loading face " + Mid(#SKY_Labels, i + 1, 1) + " (" + Str(i + 1) + " of " + Str(#SKY_Faces) + ")...", i, #SKY_Faces)
    If found(i) <> "" And SKY_LoadFace(i, found(i))
      count + 1
    EndIf
  Next
  ProcedureReturn count
EndProcedure
; ---------------------------------------------------------------------------------------------
; Controle van de indeling: passen de randen op elkaar?
; We bemonsteren van elk vlak de 4 randen op 64 punten en vergelijken die (gemiddelde kleurafstand).
; Daarmee draaien we de bovenkant zo dat hij past, en waarschuwen we als de volgorde niet lijkt
; te kloppen. Zo werkt het ook bij sets waarvan we de volgorde alleen uit de nummers kennen.
; ---------------------------------------------------------------------------------------------
#SKY_EdgeSamples = 64
Global Dim SKY_Edge.d(#SKY_Faces - 1, 3, #SKY_EdgeSamples * 3 - 1)   ; [vlak, rand, punt*3 + kanaal]

; Randen: 0 = boven (links->rechts), 1 = rechts (boven->onder), 2 = onder (links->rechts), 3 = links (boven->onder)
Procedure SKY_SampleEdges()
  Protected i.i, side.i, k.i, x.i, y.i, w.i, h.i, c.i, t.d
  For i = 0 To #SKY_Faces - 1
    If Not SKY_Face(i)\Loaded : Continue : EndIf
    w = SKY_Face(i)\Width : h = SKY_Face(i)\Height
    If StartDrawing(ImageOutput(SKY_Face(i)\Image))
      For side = 0 To 3
        For k = 0 To #SKY_EdgeSamples - 1
          t = (k + 0.5) / #SKY_EdgeSamples
          Select side
            Case 0 : x = t * w : y = 0
            Case 1 : x = w - 1 : y = t * h
            Case 2 : x = t * w : y = h - 1
            Case 3 : x = 0 : y = t * h
          EndSelect
          If x >= w : x = w - 1 : EndIf
          If y >= h : y = h - 1 : EndIf
          c = Point(x, y)
          SKY_Edge(i, side, k * 3) = Red(c) : SKY_Edge(i, side, k * 3 + 1) = Green(c) : SKY_Edge(i, side, k * 3 + 2) = Blue(c)
        Next
      Next
      StopDrawing()
    EndIf
  Next
EndProcedure

; Verschil tussen rand A van vlak I en rand B van vlak J (Rev = een van beide omgekeerd lezen).
Procedure.d SKY_EdgeErr(I.i, A.i, J.i, B.i, Rev.i)
  Protected k.i, c.i, kb.i, d.d, sum.d
  For k = 0 To #SKY_EdgeSamples - 1
    kb = k
    If Rev : kb = #SKY_EdgeSamples - 1 - k : EndIf
    For c = 0 To 2
      d = SKY_Edge(I, A, k * 3 + c) - SKY_Edge(J, B, kb * 3 + c)
      sum + d * d
    Next
  Next
  ProcedureReturn Sqr(sum / (#SKY_EdgeSamples * 3))
EndProcedure

; Welke rand (en richting) van de bovenkant komt na R keer een kwartslag rechtsom draaien op plek Side?
Procedure SKY_RotEdge(R.i, Side.i, Rev.i, *OutSide.Integer, *OutRev.Integer)
  Protected k.i
  For k = 1 To R
    Select Side
      Case 0 : Side = 3 : Rev = 1 - Rev
      Case 1 : Side = 0
      Case 2 : Side = 1 : Rev = 1 - Rev
      Case 3 : Side = 2
    EndSelect
  Next
  *OutSide\i = Side : *OutRev\i = Rev
EndProcedure

; Fout van de hele bovenrand-aansluiting als de bovenkant R kwartslagen gedraaid zou zijn.
; Verwacht (zoals bij SS3 gemeten): N-boven = C-onder, E-boven = C-rechts (omgekeerd),
; S-boven = C-boven (omgekeerd), W-boven = C-links.
Procedure.d SKY_TopErr(R.i)
  Protected sum.d, s.i, rv.i
  Dim want.i(7)
  want(0) = 2 : want(1) = 0     ; N: onder, gewoon
  want(2) = 1 : want(3) = 1     ; E: rechts, omgekeerd
  want(4) = 0 : want(5) = 1     ; S: boven, omgekeerd
  want(6) = 3 : want(7) = 0     ; W: links, gewoon
  For s = 0 To 3
    If SKY_Face(s)\Loaded And SKY_Face(4)\Loaded
      SKY_RotEdge(R, want(s * 2), want(s * 2 + 1), @want(s * 2), @rv)
      sum + SKY_EdgeErr(s, 0, 4, want(s * 2), rv)
      ; want() is overschreven; voor de volgende R opnieuw vullen
    EndIf
  Next
  ProcedureReturn sum
EndProcedure

; Zelfde voor de onderkant D (alleen bij hele zijkanten; bij SS3 is de onderrand de horizon).
; In het kruis ligt D onder N: N-onder = D-boven, E-onder = D-rechts, S-onder = D-onder (omgekeerd),
; W-onder = D-links (omgekeerd). Dat is ook de indeling die het panorama gebruikt.
Procedure.d SKY_BottomErr(R.i)
  Protected sum.d, s.i, rv.i
  Dim want.i(7)
  want(0) = 0 : want(1) = 0     ; N: boven, gewoon
  want(2) = 1 : want(3) = 0     ; E: rechts, gewoon
  want(4) = 2 : want(5) = 1     ; S: onder, omgekeerd
  want(6) = 3 : want(7) = 1     ; W: links, omgekeerd
  For s = 0 To 3
    If SKY_Face(s)\Loaded And SKY_Face(5)\Loaded
      SKY_RotEdge(R, want(s * 2), want(s * 2 + 1), @want(s * 2), @rv)
      sum + SKY_EdgeErr(s, 2, 5, want(s * 2), rv)
    EndIf
  Next
  ProcedureReturn sum
EndProcedure

; Draait een vlak een kwartslag rechtsom (plaatje en HDR-data).
Procedure SKY_RotateFace(Index.i)
  Protected w.i = SKY_Face(Index)\Width, h.i = SKY_Face(Index)\Height, x.i, y.i, new.i, *rgbe
  Dim px.l(w * h - 1)
  If StartDrawing(ImageOutput(SKY_Face(Index)\Image))
    DrawingMode(#PB_2DDrawing_AllChannels)
    For y = 0 To h - 1 : For x = 0 To w - 1 : px(y * w + x) = Point(x, y) : Next : Next
    StopDrawing()
  EndIf
  ; Nieuw plaatje is h breed en w hoog: nieuw(x', y') = oud(y', h - 1 - x')
  new = CreateImage(#PB_Any, h, w, 32)
  If new And StartDrawing(ImageOutput(new))
    DrawingMode(#PB_2DDrawing_AllChannels)
    For y = 0 To w - 1 : For x = 0 To h - 1 : Plot(x, y, px((h - 1 - x) * w + y)) : Next : Next
    StopDrawing()
    FreeImage(SKY_Face(Index)\Image)
    SKY_Face(Index)\Image = new
  EndIf
  If SKY_Face(Index)\Rgbe
    *rgbe = AllocateMemory(w * h * 4)
    For y = 0 To w - 1 : For x = 0 To h - 1
      PokeL(*rgbe + (y * h + x) * 4, PeekL(SKY_Face(Index)\Rgbe + ((h - 1 - x) * w + y) * 4))
    Next : Next
    FreeMemory(SKY_Face(Index)\Rgbe)
    SKY_Face(Index)\Rgbe = *rgbe
  EndIf
  SKY_Face(Index)\Width = h : SKY_Face(Index)\Height = w
EndProcedure

; Controleert de indeling, draait de bovenkant zo nodig en geeft een waarschuwing terug ("" = goed).
Procedure.s SKY_CheckArrangement()
  Protected r.i, best.i, bestErr.d = 1.0e30, secondErr.d = 1.0e30, e.d, fwd.d, rev.d, warning.s, i.i
  For i = 0 To 4
    If Not SKY_Face(i)\Loaded : ProcedureReturn "" : EndIf
  Next
  SKY_Progress("Checking how the faces fit together...", 0, 1)
  SKY_SampleEdges()
  ; 1. Bovenkant: welke draaiing past het best?
  If SKY_Face(4)\Width = SKY_Face(4)\Height
    For r = 0 To 3
      e = SKY_TopErr(r)
      If e < bestErr
        secondErr = bestErr : bestErr = e : best = r
      ElseIf e < secondErr
        secondErr = e
      EndIf
    Next
    If best > 0
      For r = 1 To best : SKY_RotateFace(4) : Next
      warning + "Top face turned " + Str(best * 90) + " degrees to fit. "
    EndIf
    If bestErr > secondErr * 0.7
      warning + "The top face does not clearly fit; please check the preview. "
    EndIf
  EndIf
  ; 1b. Onderkant (als die er is en de zijkanten heel zijn): welke draaiing past het best?
  If SKY_Face(5)\Loaded And SKY_Face(5)\Width = SKY_Face(5)\Height And SKY_Face(0)\Height >= SKY_Face(0)\Width
    bestErr = 1.0e30 : secondErr = 1.0e30 : best = 0
    For r = 0 To 3
      e = SKY_BottomErr(r)
      If e < bestErr
        secondErr = bestErr : bestErr = e : best = r
      ElseIf e < secondErr
        secondErr = e
      EndIf
    Next
    If best > 0
      For r = 1 To best : SKY_RotateFace(5) : Next
      warning + "Bottom face turned " + Str(best * 90) + " degrees to fit. "
    EndIf
    If bestErr > secondErr * 0.7
      warning + "The bottom face does not clearly fit; please check the preview. "
    EndIf
  EndIf
  ; 2. Volgorde rondom: N-E-S-W of juist andersom?
  fwd = SKY_EdgeErr(0, 1, 1, 3, 0) + SKY_EdgeErr(1, 1, 2, 3, 0) + SKY_EdgeErr(2, 1, 3, 3, 0) + SKY_EdgeErr(3, 1, 0, 3, 0)
  rev = SKY_EdgeErr(0, 1, 3, 3, 0) + SKY_EdgeErr(3, 1, 2, 3, 0) + SKY_EdgeErr(2, 1, 1, 3, 0) + SKY_EdgeErr(1, 1, 0, 3, 0)
  If rev < fwd * 0.7
    warning + "The side faces seem to be in reverse order (N W S E); please check the preview. "
  EndIf
  ProcedureReturn Trim(warning)
EndProcedure
; Maakt het getoonde plaatje van een HDR-vlak opnieuw met de huidige belichting.
Procedure SKY_ToneFace(Index.i)
  Protected w.i, h.i, x.i, y.i, *p, e.i, scale.d, factor.d, image.i
  Dim expFactor.d(255)
  If Not SKY_Face(Index)\IsHDR
    ProcedureReturn
  EndIf
  w = SKY_Face(Index)\Width : h = SKY_Face(Index)\Height
  scale = Pow(2, TEXSE3_ExposureEV)
  For e = 0 To 255 : expFactor(e) = Pow(2, e - 128) / 256 : Next
  image = CreateImage(#PB_Any, w, h, 32)
  If image And StartDrawing(ImageOutput(image))
    DrawingMode(#PB_2DDrawing_AllChannels)
    For y = 0 To h - 1
      For x = 0 To w - 1
        *p = SKY_Face(Index)\Rgbe + (y * w + x) * 4
        e = PeekA(*p + 3)
        If e = 0
          Plot(x, y, RGBA(0, 0, 0, 255))
        Else
          factor = expFactor(e)
          Plot(x, y, RGBA(TEXSE3_ToneMap((PeekA(*p) + 0.5) * factor, scale), TEXSE3_ToneMap((PeekA(*p + 1) + 0.5) * factor, scale), TEXSE3_ToneMap((PeekA(*p + 2) + 0.5) * factor, scale), 255))
        EndIf
      Next
    Next
    StopDrawing()
    If SKY_Face(Index)\Image : FreeImage(SKY_Face(Index)\Image) : EndIf
    SKY_Face(Index)\Image = image
  EndIf
EndProcedure

Procedure SKY_ToneAll()
  Protected i.i
  For i = 0 To #SKY_Faces - 1
    If SKY_Face(i)\Loaded
      SKY_Progress("Applying exposure to face " + SKY_Face(i)\Letter + " (" + Str(i + 1) + " of " + Str(#SKY_Faces) + ")...", i, #SKY_Faces)
      SKY_ToneFace(i)
    EndIf
  Next
EndProcedure

; Zijn alle geladen vlakken HDR?
Procedure.i SKY_AllHDR()
  Protected i.i, n.i
  For i = 0 To #SKY_Faces - 1
    If SKY_Face(i)\Loaded
      If Not SKY_Face(i)\IsHDR : ProcedureReturn #False : EndIf
      n + 1
    EndIf
  Next
  ProcedureReturn Bool(n > 0)
EndProcedure

; Rekent één belichting uit voor de hele set: het gemiddelde (logaritmisch) van alle vlakken samen
; wordt middengrijs (18%). Zo krijgt elk vlak dezelfde belichting.
Procedure.d SKY_AutoEV()
  Protected i.i, j.i, n.i, *p, e.i, lum.d, sum.d
  For i = 0 To #SKY_Faces - 1
    If SKY_Face(i)\Loaded And SKY_Face(i)\IsHDR
      For j = 0 To SKY_Face(i)\Width * SKY_Face(i)\Height - 1 Step 7    ; elke 7e pixel is genoeg
        *p = SKY_Face(i)\Rgbe + j * 4
        e = PeekA(*p + 3)
        If e
          lum = (0.2126 * (PeekA(*p) + 0.5) + 0.7152 * (PeekA(*p + 1) + 0.5) + 0.0722 * (PeekA(*p + 2) + 0.5)) / 256 * Pow(2, e - 128)
          sum + Log(lum) : n + 1
        EndIf
      Next
    EndIf
  Next
  If n = 0 : ProcedureReturn 0 : EndIf
  ProcedureReturn Log(0.18 / Exp(sum / n)) / Log(2)
EndProcedure

; ---------------------------------------------------------------------------------------------
; Samengestelde beelden
; ---------------------------------------------------------------------------------------------
Enumeration SkyLayout
  #SKY_Strip                    ; W N E S naast elkaar
  #SKY_Cross                    ; C boven N, daaronder W N E S
  #SKY_Panorama                 ; 360-graden-panorama, 2:1
EndEnumeration

; Maat van een samengesteld beeld.
Procedure SKY_LayoutSize(Layout.i, *W.Integer, *H.Integer)
  Protected s.i = SKY_Face(0)\Width, hs.i = SKY_Face(0)\Height, cs.i = SKY_Face(4)\Height
  Select Layout
    Case #SKY_Strip    : *W\i = 4 * s : *H\i = hs
    Case #SKY_Cross    : *W\i = 4 * s : *H\i = cs + hs + SKY_Face(5)\Height   ; D (onder) is 0 hoog als die er niet is
    Case #SKY_Panorama : *W\i = 4 * s : *H\i = 2 * s
  EndSelect
EndProcedure

; Zoekt voor een pixel van het samengestelde beeld welk vlak en welke pixel daar hoort.
; Geeft #False als daar geen beeld is (lege plek in het kruis).
Procedure.i SKY_Map(Layout.i, X.i, Y.i, W.i, H.i, *Face.Integer, *PX.Integer, *PY.Integer)
  Protected s.i = SKY_Face(0)\Width, hs.i = SKY_Face(0)\Height, cs.i = SKY_Face(4)\Height
  Protected lon.d, lat.d, dx.d, dy.d, dz.d, ax.d, ay.d, az.d, u.d, t.d, v.d, face.i
  Select Layout
    Case #SKY_Strip, #SKY_Cross
      If Layout = #SKY_Cross
        If Y < cs
          ; Bovenste rij: alleen C, precies boven N
          If X >= s And X < 2 * s
            *Face\i = 4 : *PX\i = (X - s) * SKY_Face(4)\Width / s : *PY\i = Y
            ProcedureReturn #True
          EndIf
          ProcedureReturn #False
        EndIf
        Y - cs
        If Y >= hs
          ; Onderste rij: alleen D (onder), precies onder N
          If X >= s And X < 2 * s And SKY_Face(5)\Loaded
            *Face\i = 5 : *PX\i = (X - s) * SKY_Face(5)\Width / s : *PY\i = Y - hs
            ProcedureReturn #True
          EndIf
          ProcedureReturn #False
        EndIf
      EndIf
      ; Strook in de volgorde W, N, E, S (zo lopen de randen in elkaar over)
      Select X / s
        Case 0 : *Face\i = 3
        Case 1 : *Face\i = 0
        Case 2 : *Face\i = 1
        Default : *Face\i = 2
      EndSelect
      *PX\i = X % s : *PY\i = Y
      ProcedureReturn #True

    Case #SKY_Panorama
      ; Richting van deze pixel: midden = noord, naar rechts = oost, boven = recht omhoog
      lon = (X + 0.5) / W * 2 * #PI - #PI
      lat = #PI / 2 - (Y + 0.5) / H * #PI
      ; Halve zijkanten (SS3) hebben onder de horizon geen beeld (wordt de horizonkleur)
      If lat < 0 And SKY_Face(0)\Height < SKY_Face(0)\Width
        ProcedureReturn #False
      EndIf
      dx = Sin(lon) * Cos(lat) : dy = Sin(lat) : dz = Cos(lon) * Cos(lat)
      ax = Abs(dx) : ay = Abs(dy) : az = Abs(dz)
      If ay >= ax And ay >= az And dy < 0
        If Not SKY_Face(5)\Loaded
          ProcedureReturn #False               ; recht naar beneden en geen ondervlak
        EndIf
        ; Onderkant D: u = (x/|y| + 1) / 2, v = (-z/|y| + 1) / 2 (gewone cubemap-indeling)
        face = 5
        u = (dx / ay + 1) / 2 : v = (1 - dz / ay) / 2
        *PX\i = Int(u * SKY_Face(5)\Width) : *PY\i = Int(v * SKY_Face(5)\Height)
      ElseIf ay >= ax And ay >= az
        ; Bovenkant C: u = (x/y + 1) / 2, v = (z/y + 1) / 2
        face = 4
        u = (dx / dy + 1) / 2 : v = (dz / dy + 1) / 2
        *PX\i = Int(u * SKY_Face(4)\Width) : *PY\i = Int(v * SKY_Face(4)\Height)
      Else
        If az >= ax
          If dz > 0
            face = 0 : u = (dx / az + 1) / 2         ; N kijkt naar +Z, rechts = +X
          Else
            face = 2 : u = (1 - dx / az) / 2         ; S kijkt naar -Z, rechts = -X
          EndIf
          t = dy / az
        Else
          If dx > 0
            face = 1 : u = (1 - dz / ax) / 2         ; E kijkt naar +X, rechts = -Z
          Else
            face = 3 : u = (dz / ax + 1) / 2         ; W kijkt naar -X, rechts = +Z
          EndIf
          t = dy / ax
        EndIf
        *PX\i = Int(u * s)
        If hs < s
          ; Halve zijkant (SS3): alleen de bovenste helft is opgeslagen; de onderste rij is de horizon
          *PY\i = Int((1 - t) / 2 * 2 * hs)
        Else
          ; Hele zijkant (SS1/SS2): de horizon zit in het midden
          *PY\i = Int((1 - t) / 2 * hs)
        EndIf
      EndIf
      *Face\i = face
      If *PX\i < 0 : *PX\i = 0 : EndIf
      If *PX\i >= SKY_Face(face)\Width : *PX\i = SKY_Face(face)\Width - 1 : EndIf
      If *PY\i < 0 : *PY\i = 0 : EndIf
      If *PY\i >= SKY_Face(face)\Height : *PY\i = SKY_Face(face)\Height - 1 : EndIf
      ProcedureReturn #True
  EndSelect
  ProcedureReturn #False
EndProcedure

; Gemiddelde kleur van de horizon (onderste rij van de zijkanten), voor onder de horizon in het panorama.
Procedure.i SKY_HorizonColor()
  Protected i.i, x.i, c.i, r.i, g.i, b.i, n.i
  For i = 0 To 3
    If SKY_Face(i)\Loaded And StartDrawing(ImageOutput(SKY_Face(i)\Image))
      For x = 0 To SKY_Face(i)\Width - 1
        c = Point(x, SKY_Face(i)\Height - 1)
        r + Red(c) : g + Green(c) : b + Blue(c) : n + 1
      Next
      StopDrawing()
    EndIf
  Next
  If n = 0 : ProcedureReturn RGBA(0, 0, 0, 255) : EndIf
  ProcedureReturn RGBA(r / n, g / n, b / n, 255)
EndProcedure

; Zelfde, maar als HDR-waarde (R,G,B,E) voor het .hdr-panorama.
Procedure.l SKY_HorizonRGBE()
  Protected i.i, x.i, *p, f.d, r.d, g.d, b.d, n.i, result.l
  For i = 0 To 3
    If SKY_Face(i)\Loaded And SKY_Face(i)\IsHDR
      For x = 0 To SKY_Face(i)\Width - 1
        *p = SKY_Face(i)\Rgbe + ((SKY_Face(i)\Height - 1) * SKY_Face(i)\Width + x) * 4
        If PeekA(*p + 3)
          f = Pow(2, PeekA(*p + 3) - 128) / 256
          r + (PeekA(*p) + 0.5) * f : g + (PeekA(*p + 1) + 0.5) * f : b + (PeekA(*p + 2) + 0.5) * f
        EndIf
        n + 1
      Next
    EndIf
  Next
  If n
    TEXSE3_EncodeRGBE(@result, r / n, g / n, b / n)
  EndIf
  ProcedureReturn result
EndProcedure

; Maakt een samengesteld plaatje (zoals getoond, met de huidige belichting).
Procedure.i SKY_Compose(Layout.i)
  Protected w.i, h.i, x.i, y.i, i.i, face.i, px.i, py.i, image.i, fw.i, horizon.i
  SKY_LayoutSize(Layout, @w, @h)
  horizon = SKY_HorizonColor()
  ; Pixels van alle vlakken in arrays (snel opzoeken)
  Dim pix.l(#SKY_Faces - 1, 0)
  fw = 0
  For i = 0 To #SKY_Faces - 1
    If SKY_Face(i)\Width * SKY_Face(i)\Height > fw : fw = SKY_Face(i)\Width * SKY_Face(i)\Height : EndIf
  Next
  Dim pix.l(#SKY_Faces - 1, fw - 1)
  For i = 0 To #SKY_Faces - 1
    If SKY_Face(i)\Loaded And StartDrawing(ImageOutput(SKY_Face(i)\Image))
      DrawingMode(#PB_2DDrawing_AllChannels)
      For y = 0 To SKY_Face(i)\Height - 1
        For x = 0 To SKY_Face(i)\Width - 1
          pix(i, y * SKY_Face(i)\Width + x) = Point(x, y)
        Next
      Next
      StopDrawing()
    EndIf
  Next
  image = CreateImage(#PB_Any, w, h, 32, #PB_Image_Transparent)
  If image And StartDrawing(ImageOutput(image))
    DrawingMode(#PB_2DDrawing_AllChannels)
    For y = 0 To h - 1
      If y % 64 = 0
        ; Voortgang tonen. Tekenen moet daarvoor even stoppen, anders kan het venster niet bijwerken.
        StopDrawing()
        SKY_Progress("Building " + StringField("strip,cross,panorama", Layout + 1, ",") + "... " + Str(y * 100 / h) + "%", y, h)
        StartDrawing(ImageOutput(image))
        DrawingMode(#PB_2DDrawing_AllChannels)
      EndIf
      For x = 0 To w - 1
        If SKY_Map(Layout, x, y, w, h, @face, @px, @py) And SKY_Face(face)\Loaded
          Plot(x, y, pix(face, py * SKY_Face(face)\Width + px))
        ElseIf Layout = #SKY_Panorama
          Plot(x, y, horizon)                  ; onder de horizon
        EndIf
      Next
    Next
    StopDrawing()
  EndIf
  ProcedureReturn image
EndProcedure

; Maakt een samengesteld beeld als HDR-data (R,G,B,E), alleen als alle vlakken HDR zijn.
Procedure.i SKY_ComposeHDR(Layout.i, *W.Integer, *H.Integer)
  Protected w.i, h.i, x.i, y.i, face.i, px.i, py.i, *out, horizon.l
  SKY_LayoutSize(Layout, @w, @h)
  horizon = SKY_HorizonRGBE()
  *out = AllocateMemory(w * h * 4)              ; lege plekken blijven 0 = zwart
  If *out = 0 : ProcedureReturn 0 : EndIf
  For y = 0 To h - 1
    If y % 64 = 0
      SKY_Progress("Building HDR " + StringField("strip,cross,panorama", Layout + 1, ",") + "... " + Str(y * 100 / h) + "%", y, h)
    EndIf
    For x = 0 To w - 1
      If SKY_Map(Layout, x, y, w, h, @face, @px, @py) And SKY_Face(face)\Loaded
        PokeL(*out + (y * w + x) * 4, PeekL(SKY_Face(face)\Rgbe + (py * SKY_Face(face)\Width + px) * 4))
      ElseIf Layout = #SKY_Panorama
        PokeL(*out + (y * w + x) * 4, horizon)
      EndIf
    Next
  Next
  *W\i = w : *H\i = h
  ProcedureReturn *out
EndProcedure

; Slaat een plaatje op in het formaat van de extensie (tga, png, tif, tex).
Procedure.i SKY_SaveImage(Image.i, FileName.s, HasAlpha.i)
  Select LCase(GetExtensionPart(FileName))
    Case "tga" : ProcedureReturn TGA_Save(Image, FileName, HasAlpha)
    Case "tif" : ProcedureReturn TIFF_Save(Image, FileName, HasAlpha)
    Case "tex" : ProcedureReturn TEXW_SaveSE1(Image, FileName, HasAlpha, 0)
    Default
      If HasAlpha
        ProcedureReturn SaveImage(Image, FileName, #PB_ImagePlugin_PNG, 0, 32)
      EndIf
      ProcedureReturn SaveImage(Image, FileName, #PB_ImagePlugin_PNG, 0, 24)
  EndSelect
EndProcedure

; ---------------------------------------------------------------------------------------------
; Venster
; ---------------------------------------------------------------------------------------------


; Tekent het voorbeeld: het kruis, geschaald naar het canvas.
Procedure SKY_DrawPreview()
  Protected cross.i, cw.i, ch.i, scale.d, dw.i, dh.i, i.i, list.s
  If Not IsWindow(SKY_Win) : ProcedureReturn : EndIf
  If StartDrawing(CanvasOutput(SKY_Canvas))
    cw = OutputWidth() : ch = OutputHeight()
    Box(0, 0, cw, ch, RGB(60, 60, 60))
    StopDrawing()
  EndIf
  If Not SKY_Face(0)\Loaded
    SetGadgetText(SKY_Info, "No skybox loaded. Use 'Open face...' or 'From .gro...' and pick one face (e.g. HDR_Cloudy04_N.tex).")
    ProcedureReturn
  EndIf
  cross = SKY_Compose(#SKY_Cross)
  If cross
    scale = cw / ImageWidth(cross)
    If ImageHeight(cross) * scale > ch : scale = ch / ImageHeight(cross) : EndIf
    dw = ImageWidth(cross) * scale : dh = ImageHeight(cross) * scale
    ResizeImage(cross, dw, dh, #PB_Image_Smooth)
    If StartDrawing(CanvasOutput(SKY_Canvas))
      DrawAlphaImage(ImageID(cross), (cw - dw) / 2, (ch - dh) / 2)
      StopDrawing()
    EndIf
    FreeImage(cross)
  EndIf
  For i = 0 To #SKY_Faces - 1
    If SKY_Face(i)\Loaded : list + " " + SKY_Face(i)\Letter : ElseIf i < 5 : list + " (" + SKY_Face(i)\Letter + " missing)" : EndIf
  Next
  SetGadgetState(SKY_Bar, 0)                 ; klaar: voortgangsbalk weer leeg
  If SKY_AllHDR()
    SetGadgetText(SKY_Info, "Set: " + SKY_SetName + "  -  faces:" + list + "  -  HDR, exposure " + StrD(TEXSE3_ExposureEV, 1) + " EV")
  Else
    SetGadgetText(SKY_Info, "Set: " + SKY_SetName + "  -  faces:" + list)
  EndIf
EndProcedure

; Laadt een set vanaf één gekozen vlak en toont hem.
Procedure SKY_OpenSet(Path.s)
  Protected n.i = SKY_FindSet(Path)
  If n = 0
    MessageRequester("Skybox", GetFilePart(Path) + " does not look like a skybox face." + #LF$ + "Expected a name ending in _N/_E/_S/_W/_U or _C/_D (HDR_Cloudy04_N.tex), Front/Right/Back/Left/Up/Down (1_3_nightFront.tex), North/East/South/West/Top/Bottom, _ft/_rt/_bk/_lf/_up/_dn, posx/negx/..., px/nx/py/ny/pz/nz (cubemap) or a number (Storm1.tex, MDG01_Daylight_01.tex).", #PB_MessageRequester_Warning)
  ElseIf Not SKY_Face(0)\Loaded Or Not SKY_Face(1)\Loaded Or Not SKY_Face(2)\Loaded Or Not SKY_Face(3)\Loaded Or Not SKY_Face(4)\Loaded   ; D (onder) is niet verplicht
    MessageRequester("Skybox", "Only " + Str(n) + " faces were found (at least N, E, S, W and top are needed). Missing faces are left empty.", #PB_MessageRequester_Warning)
  EndIf
  Protected warning.s = SKY_CheckArrangement()
  SKY_ToneAll()
  SetGadgetText(SKY_EV, StrD(TEXSE3_ExposureEV, 1))
  SKY_DrawPreview()
  If warning <> ""
    MessageRequester("Skybox", warning, #PB_MessageRequester_Info)
  EndIf
EndProcedure

; Exporteert volgens de keuzes in het venster.
Procedure SKY_Export()
  Protected kind.i, ext.s, folder.s, file.s, i.i, ok.i = #True, img.i, *rgbe, w.i, h.i, names.s
  If Not SKY_Face(0)\Loaded
    ProcedureReturn
  EndIf
  kind = GetGadgetState(SKY_Kind)
  ext = StringField("tga,png,tif,hdr,tex", GetGadgetState(SKY_Format) + 1, ",")
  If ext = "hdr" And Not SKY_AllHDR()
    MessageRequester("Skybox", "Only HDR skyboxes can be saved as .hdr.", #PB_MessageRequester_Warning)
    ProcedureReturn
  EndIf
  If ext = "tex" And kind > 0
    MessageRequester("Skybox", "Combined images are larger than 1024 pixels; Serious Sam 1 .tex is only available for separate faces.", #PB_MessageRequester_Warning)
    ProcedureReturn
  EndIf

  If kind = 0
    ; --- Losse vlakken: een map kiezen; de namen blijven gelijk, met de nieuwe extensie ---
    folder = PathRequester("Choose a folder for the " + Str(#SKY_Faces) + " faces", SKY_Dir)
    If folder = "" : ProcedureReturn : EndIf
    For i = 0 To #SKY_Faces - 1
      If Not SKY_Face(i)\Loaded : Continue : EndIf
      file = folder + GetFilePart(SKY_Face(i)\Name, #PB_FileSystem_NoExtension) + "." + ext
      SKY_Progress("Saving " + GetFilePart(file) + "...", i, #SKY_Faces)
      If ext = "hdr"
        ok & HDR_Save(SKY_Face(i)\Rgbe, SKY_Face(i)\Width, SKY_Face(i)\Height, file)
      Else
        ok & SKY_SaveImage(SKY_Face(i)\Image, file, #False)
      EndIf
      names + GetFilePart(file) + #LF$
    Next
  Else
    ; --- Samengesteld: één bestand ---
    file = SaveFileRequester("Save skybox as", SKY_Dir + SKY_SetName + StringField("_strip,_cross,_panorama", kind, ","), "Image (*." + ext + ")|*." + ext, 0)
    If file = "" : ProcedureReturn : EndIf
    If LCase(GetExtensionPart(file)) <> ext : file + "." + ext : EndIf
    SKY_Progress("Saving " + GetFilePart(file) + "...", 0, 1)
    If ext = "hdr"
      *rgbe = SKY_ComposeHDR(kind - 1, @w, @h)
      ok = Bool(*rgbe And HDR_Save(*rgbe, w, h, file))
      If *rgbe : FreeMemory(*rgbe) : EndIf
    Else
      img = SKY_Compose(kind - 1)
      ok = Bool(img And SKY_SaveImage(img, file, Bool(kind - 1 = #SKY_Cross)))   ; kruis: lege plekken doorzichtig
      If img : FreeImage(img) : EndIf
    EndIf
    names = GetFilePart(file)
  EndIf
  SKY_Progress("Done.", 1, 1)
  If ok
    SKY_Dir = GetPathPart(file)
    MessageRequester("Skybox", "Saved:" + #LF$ + names)
  Else
    MessageRequester("Skybox", "Saving failed.", #PB_MessageRequester_Error)
  EndIf
EndProcedure

; Opent het skyboxvenster. StartPath (optioneel): een vlak om meteen te laden.
Procedure SKY_Open(ParentWindow.i, StartPath.s = "", StartDir.s = "")
  Protected event.i, done.i, bOpen.i, bGro.i, bMinus.i, bPlus.i, bAuto.i, bExport.i, bClose.i, file.s, archive.s, entry.s, ev.d

  SKY_Dir = StartDir
  SKY_Win = OpenWindow(#PB_Any, 0, 0, 900, 560, "Skybox", #PB_Window_SystemMenu | #PB_Window_WindowCentered, WindowID(ParentWindow))
  If SKY_Win = 0 : ProcedureReturn : EndIf
  bOpen = ButtonGadget(#PB_Any, 8, 8, 110, 26, "Open face...")
  bGro  = ButtonGadget(#PB_Any, 124, 8, 110, 26, "From .gro...")
  TextGadget(#PB_Any, 250, 13, 70, 20, "Exposure:")
  bMinus = ButtonGadget(#PB_Any, 320, 8, 30, 26, "-")
  SKY_EV = StringGadget(#PB_Any, 352, 9, 50, 24, StrD(TEXSE3_ExposureEV, 1))
  bPlus  = ButtonGadget(#PB_Any, 404, 8, 30, 26, "+")
  bAuto  = ButtonGadget(#PB_Any, 440, 8, 110, 26, "Auto (whole set)")
  SKY_Tone = ComboBoxGadget(#PB_Any, 560, 9, 150, 24)
  AddGadgetItem(SKY_Tone, -1, "Editor (clip)")
  AddGadgetItem(SKY_Tone, -1, "Filmic")
  SetGadgetState(SKY_Tone, TEXSE3_ToneMode)
  SKY_Canvas = CanvasGadget(#PB_Any, 8, 42, 884, 420)
  SKY_Info = TextGadget(#PB_Any, 8, 468, 680, 20, "")
  SKY_Bar = ProgressBarGadget(#PB_Any, 692, 466, 200, 20, 0, 100)
  TextGadget(#PB_Any, 8, 500, 50, 20, "Export:")
  SKY_Kind = ComboBoxGadget(#PB_Any, 60, 496, 250, 24)
  AddGadgetItem(SKY_Kind, -1, "Separate faces")
  AddGadgetItem(SKY_Kind, -1, "Strip (W N E S side by side)")
  AddGadgetItem(SKY_Kind, -1, "Cross (U above N)")
  AddGadgetItem(SKY_Kind, -1, "360 degree panorama (2:1)")
  SetGadgetState(SKY_Kind, 0)
  SKY_Format = ComboBoxGadget(#PB_Any, 320, 496, 260, 24)
  AddGadgetItem(SKY_Format, -1, "Truevision Graphics Adapter (*.tga)")
  AddGadgetItem(SKY_Format, -1, "Portable Network Graphics (*.png)")
  AddGadgetItem(SKY_Format, -1, "Tagged Image File Format (*.tif)")
  AddGadgetItem(SKY_Format, -1, "Radiance HDR, keeps brightness (*.hdr)")
  AddGadgetItem(SKY_Format, -1, "Serious Sam 1 texture (*.tex)")
  SetGadgetState(SKY_Format, 0)
  bExport = ButtonGadget(#PB_Any, 590, 495, 100, 26, "Export...")
  bClose  = ButtonGadget(#PB_Any, 792, 526, 100, 26, "Close")
  DisableWindow(ParentWindow, #True)

  SKY_Clear()
  If StartPath <> ""
    SKY_OpenSet(StartPath)
  Else
    SKY_DrawPreview()
  EndIf

  Repeat
    event = WaitWindowEvent()
    If EventWindow() <> SKY_Win : Continue : EndIf
    Select event
      Case #PB_Event_CloseWindow
        done = #True
      Case #PB_Event_Gadget
        Select EventGadget()
          Case bClose : done = #True
          Case bOpen
            file = OpenFileRequester("Open one face of a skybox", SKY_Dir, "Skybox faces|*.tex;*.hdr;*.tga;*.png;*.dds|All files (*.*)|*.*", 0)
            If file <> "" : SKY_Dir = GetPathPart(file) : SKY_OpenSet(file) : EndIf
          Case bGro
            archive = OpenFileRequester("Open .gro archive", SKY_Dir, "Serious Sam archive (*.gro)|*.gro", 0)
            If archive <> ""
              entry = GRO_ChooseTex(archive, SKY_Win)
              If entry <> "" : SKY_OpenSet(archive + #GRO_Separator + entry) : EndIf
            EndIf
          Case bMinus, bPlus, bAuto
            Select EventGadget()
              Case bMinus : TEXSE3_ExposureEV - 1
              Case bPlus  : TEXSE3_ExposureEV + 1
              Case bAuto  : TEXSE3_ExposureEV = Round(SKY_AutoEV() * 10, #PB_Round_Nearest) / 10
            EndSelect
            SetGadgetText(SKY_EV, StrD(TEXSE3_ExposureEV, 1))
            SKY_ToneAll() : SKY_DrawPreview()
          Case SKY_EV
            If EventType() = #PB_EventType_LostFocus
              ev = ValD(ReplaceString(GetGadgetText(SKY_EV), ",", "."))
              If ev <> TEXSE3_ExposureEV
                TEXSE3_ExposureEV = ev
                SKY_ToneAll() : SKY_DrawPreview()
              EndIf
            EndIf
          Case SKY_Tone
            If EventType() = #PB_EventType_Change
              TEXSE3_ToneMode = GetGadgetState(SKY_Tone)
              SKY_ToneAll() : SKY_DrawPreview()
            EndIf
          Case bExport
            SKY_Export()
        EndSelect
    EndSelect
  Until done

  SKY_Clear()
  DisableWindow(ParentWindow, #False)
  CloseWindow(SKY_Win)
  SKY_Win = 0
  SetActiveWindow(ParentWindow)
EndProcedure
