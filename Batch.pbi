; Batch.pbi - veel bestanden tegelijk omzetten (menu Tools > Batch conversion)
;
; Het venster:
;   links   - de lijst met bestanden (meerdere tegelijk te selecteren), met knoppen om toe te voegen:
;             bladeren, een hele map (met submappen), uit een .gro kiezen, alles uit een .gro,
;             en slepen ("drag & drop") vanuit de verkenner. Plus "Remove selected" en "Remove all".
;   rechts  - een voorbeeld van het (laatst) geselecteerde bestand, met de eigenschappen eronder.
;   onder   - Source format (welke bestanden in de lijst mogen), Output format, de uitvoermap,
;             "Force overwriting", en de knoppen Convert Selected en Convert All.
;
; Controles op onmogelijke keuzes:
;   - .gro-knoppen alleen als het Source format .tex is (een .gro bevat alleen .tex-bestanden)
;   - bestanden uit een .gro kunnen niet "naast het bronbestand" worden opgeslagen: dan een eigen map
;   - .hdr als uitvoer kan alleen voor HDR-bronnen (de rest wordt overgeslagen en gemeld)
;   - uitvoer = invoer (zelfde map, naam en formaat) wordt nooit overschreven
;   - dezelfde bestandsnaam uit verschillende mappen naar één uitvoermap: vragen wat te doen
;   - SE1-.tex groter dan 1024: automatisch verkleinen (keuze) of overslaan

XIncludeFile "TexReader.pbi"
XIncludeFile "ImageReader.pbi"
XIncludeFile "GroReader.pbi"
XIncludeFile "TGAWriter.pbi"
XIncludeFile "TIFFWriter.pbi"
XIncludeFile "PCXWriter.pbi"
XIncludeFile "HDRWriter.pbi"
XIncludeFile "TexWriterSE1.pbi"
XIncludeFile "DDSWriter.pbi"
XIncludeFile "Resize.pbi"

UsePNGImageEncoder()
UseJPEGImageEncoder()

Structure BatchItem
  Path.s                        ; bestand op schijf, of "archief.gro::Content/.../naam.tex"
EndStructure

Global NewList BAT_Items.BatchItem()
Global BAT_Win.i, BAT_List.i, BAT_Canvas.i, BAT_Props.i, BAT_Source.i, BAT_Output.i
Global BAT_UseSource.i, BAT_Folder.i, BAT_FolderLabel.i, BAT_BrowseFolder.i, BAT_Force.i, BAT_Fit1024.i
Global BAT_AddFiles.i, BAT_AddFolder.i, BAT_AddGro.i, BAT_AddGroAll.i, BAT_RemoveSel.i, BAT_RemoveAll.i
Global BAT_ConvSel.i, BAT_ConvAll.i, BAT_Close.i, BAT_Bar.i, BAT_Status.i, BAT_Count.i
Global BAT_OutDir.s, BAT_Dir.s, BAT_Cancel.i, BAT_Busy.i

; Bronformaten (extensies) en uitvoerformaten, in de volgorde van de keuzelijsten
#BAT_SourceExts = "tex,tga,png,pcx,bmp,tif,jpg,dds,hdr"
#BAT_OutputExts = "tga,png,pcx,bmp,tif,jpg,dds,tex,hdr"

Procedure.s BAT_SourceExt()
  ProcedureReturn StringField(#BAT_SourceExts, GetGadgetState(BAT_Source) + 1, ",")
EndProcedure

Procedure.s BAT_OutputExt()
  ProcedureReturn StringField(#BAT_OutputExts, GetGadgetState(BAT_Output) + 1, ",")
EndProcedure

; Hoort dit bestand bij het gekozen Source format? (.tif/.tiff en .jpg/.jpeg tellen als gelijk)
Procedure.i BAT_MatchesSource(Path.s)
  Protected ext.s
  If GRO_IsGroPath(Path)
    ext = LCase(GetExtensionPart(GRO_EntryPart(Path)))
  Else
    ext = LCase(GetExtensionPart(Path))
  EndIf
  If ext = "tiff" : ext = "tif" : EndIf
  If ext = "jpeg" : ext = "jpg" : EndIf
  ProcedureReturn Bool(ext = BAT_SourceExt())
EndProcedure

; Naam en map van een item, voor de lijst en voor de uitvoernaam
Procedure.s BAT_ItemName(Path.s)
  If GRO_IsGroPath(Path)
    ProcedureReturn GRO_EntryFileName(GRO_EntryPart(Path))
  EndIf
  ProcedureReturn GetFilePart(Path)
EndProcedure

Procedure.s BAT_ItemLocation(Path.s)
  Protected entry.s
  If GRO_IsGroPath(Path)
    entry = GRO_EntryPart(Path)
    ProcedureReturn GetFilePart(GRO_ArchivePart(Path)) + " : " + Left(entry, Len(entry) - Len(GRO_EntryFileName(entry)))
  EndIf
  ProcedureReturn GetPathPart(Path)
EndProcedure

; Laadt een item (van schijf of uit een .gro) als 32-bit image. Geeft 0 bij een fout.
Procedure.i BAT_Load(Path.s, *Info.TexInfo)
  Protected *mem, size.i, image.i, ext.s
  If GRO_IsGroPath(Path)
    *mem = GRO_Extract(GRO_ArchivePart(Path), GRO_EntryPart(Path), @size)
    If *mem
      image = TEX_LoadMemory(*mem, size, *Info, "")
      FreeMemory(*mem)
    Else
      *Info\Error = "Could not extract it from the archive."
    EndIf
    ProcedureReturn image
  EndIf
  ext = LCase(GetExtensionPart(Path))
  If ext = "tex"
    ProcedureReturn TEX_Load(Path, *Info)
  EndIf
  ProcedureReturn IMG_Load(Path, *Info)
EndProcedure

; ---------------------------------------------------------------------------------------------
; Lijst
; ---------------------------------------------------------------------------------------------

; Voegt een bestand toe als het bij het Source format hoort en nog niet in de lijst staat.
; Geeft 1 terug als het is toegevoegd, anders 0.
Procedure.i BAT_AddPath(Path.s)
  If Not BAT_MatchesSource(Path)
    ProcedureReturn 0
  EndIf
  ForEach BAT_Items()
    If LCase(BAT_Items()\Path) = LCase(Path)
      ProcedureReturn 0                      ; staat er al in
    EndIf
  Next
  AddElement(BAT_Items())
  BAT_Items()\Path = Path
  AddGadgetItem(BAT_List, -1, BAT_ItemName(Path) + #LF$ + BAT_ItemLocation(Path))
  ProcedureReturn 1
EndProcedure

; Voegt alle bestanden van het Source format uit een map toe, ook uit alle submappen.
Procedure.i BAT_AddFolder(Folder.s)
  Protected dir.i, name.s, added.i
  If Right(Folder, 1) <> #PS$ : Folder + #PS$ : EndIf
  dir = ExamineDirectory(#PB_Any, Folder, "*")
  If dir
    While NextDirectoryEntry(dir)
      name = DirectoryEntryName(dir)
      If DirectoryEntryType(dir) = #PB_DirectoryEntry_Directory
        If name <> "." And name <> ".."
          added + BAT_AddFolder(Folder + name)
        EndIf
      Else
        added + BAT_AddPath(Folder + name)
      EndIf
    Wend
    FinishDirectory(dir)
  EndIf
  ProcedureReturn added
EndProcedure

Procedure BAT_UpdateCount()
  Protected sel.i, i.i
  For i = 0 To CountGadgetItems(BAT_List) - 1
    If GetGadgetItemState(BAT_List, i) & #PB_ListIcon_Selected : sel + 1 : EndIf
  Next
  SetGadgetText(BAT_Count, Str(ListSize(BAT_Items())) + " files, " + Str(sel) + " selected")
EndProcedure

; Zet knoppen aan of uit, afhankelijk van de keuzes (voorkomt onmogelijke combinaties).
Procedure BAT_UpdateControls()
  Protected isTex.i = Bool(BAT_SourceExt() = "tex"), hasGro.i, n.i = ListSize(BAT_Items())
  ForEach BAT_Items()
    If GRO_IsGroPath(BAT_Items()\Path) : hasGro = #True : Break : EndIf
  Next
  DisableGadget(BAT_AddGro, Bool(Not isTex))
  DisableGadget(BAT_AddGroAll, Bool(Not isTex))
  DisableGadget(BAT_RemoveSel, Bool(n = 0))
  DisableGadget(BAT_RemoveAll, Bool(n = 0))
  DisableGadget(BAT_ConvSel, Bool(n = 0))
  DisableGadget(BAT_ConvAll, Bool(n = 0))
  ; Uit een .gro kun je niet "naast het bronbestand" opslaan
  If hasGro And GetGadgetState(BAT_UseSource)
    SetGadgetState(BAT_UseSource, #False)
  EndIf
  DisableGadget(BAT_UseSource, hasGro)
  DisableGadget(BAT_BrowseFolder, GetGadgetState(BAT_UseSource))
  If GetGadgetState(BAT_UseSource)
    SetGadgetText(BAT_FolderLabel, "(next to each source file)")
  ElseIf BAT_OutDir = ""
    SetGadgetText(BAT_FolderLabel, "(no folder chosen)")
  Else
    SetGadgetText(BAT_FolderLabel, BAT_OutDir)
  EndIf
  DisableGadget(BAT_Fit1024, Bool(BAT_OutputExt() <> "tex"))
  BAT_UpdateCount()
EndProcedure

; ---------------------------------------------------------------------------------------------
; Voorbeeld
; ---------------------------------------------------------------------------------------------
Procedure BAT_ShowPreview()
  Protected row.i, image.i, info.TexInfo, cw.i, ch.i, scale.d, dw.i, dh.i, x.i, y.i, text.s
  row = GetGadgetState(BAT_List)              ; bij meerdere: de laatst aangeklikte
  If StartDrawing(CanvasOutput(BAT_Canvas))
    cw = OutputWidth() : ch = OutputHeight()
    Box(0, 0, cw, ch, RGB(60, 60, 60))
    StopDrawing()
  EndIf
  If row < 0 Or row >= ListSize(BAT_Items())
    SetGadgetText(BAT_Props, "")
    ProcedureReturn
  EndIf
  SelectElement(BAT_Items(), row)
  image = BAT_Load(BAT_Items()\Path, @info)
  If image = 0
    SetGadgetText(BAT_Props, BAT_ItemName(BAT_Items()\Path) + ": " + info\Error)
    TEX_FreeInfo(@info)
    ProcedureReturn
  EndIf
  ; Passend in het canvas (niet groter dan 1:1), met schaakbord achter transparantie
  scale = cw / ImageWidth(image)
  If ImageHeight(image) * scale > ch : scale = ch / ImageHeight(image) : EndIf
  If scale > 1 : scale = 1 : EndIf
  dw = ImageWidth(image) * scale : dh = ImageHeight(image) * scale
  If dw < 1 : dw = 1 : EndIf
  If dh < 1 : dh = 1 : EndIf
  If dw <> ImageWidth(image) : ResizeImage(image, dw, dh, #PB_Image_Smooth) : EndIf
  If StartDrawing(CanvasOutput(BAT_Canvas))
    For y = 0 To dh - 1 Step 8
      For x = 0 To dw - 1 Step 8
        If (x / 8 + y / 8) & 1
          Box((cw - dw) / 2 + x, (ch - dh) / 2 + y, 8, 8, RGB(204, 204, 204))
        Else
          Box((cw - dw) / 2 + x, (ch - dh) / 2 + y, 8, 8, RGB(255, 255, 255))
        EndIf
      Next
    Next
    DrawAlphaImage(ImageID(image), (cw - dw) / 2, (ch - dh) / 2)
    StopDrawing()
  EndIf
  ; Eigenschappen
  text = BAT_ItemName(BAT_Items()\Path) + "   " + Str(info\Width) + " x " + Str(info\Height)
  Select info\Engine
    Case 1 : text + "   SS1 version " + Str(info\Version)
    Case 2 : text + "   SS2, " + info\FormatName
    Case 3 : text + "   SS3, " + info\FormatName
    Default : text + "   " + info\FormatName
  EndSelect
  If info\HasAlpha : text + ", with transparency" : EndIf
  If info\IsHDR : text + ", HDR" : EndIf
  SetGadgetText(BAT_Props, text)
  FreeImage(image)
  TEX_FreeInfo(@info)
EndProcedure

; ---------------------------------------------------------------------------------------------
; Omzetten
; ---------------------------------------------------------------------------------------------

; Laat het venster bijwerken en kijkt of er op Cancel is gedrukt.
Procedure BAT_Pump()
  Protected event.i
  Repeat
    event = WindowEvent()
    If event = #PB_Event_Gadget And EventWindow() = BAT_Win And EventGadget() = BAT_Close
      BAT_Cancel = #True                     ; tijdens het omzetten is "Close" de stopknop
    EndIf
  Until event = 0
EndProcedure

; Slaat een image op in het gekozen formaat. Geeft "" terug als het gelukt is, anders de reden.
Procedure.s BAT_Save(Image.i, *Info.TexInfo, File.s, Ext.s)
  Protected ok.i, flat.i, format.i
  Select Ext
    Case "tga" : ok = TGA_Save(Image, File, *Info\HasAlpha)
    Case "png"
      If *Info\HasAlpha
        ok = SaveImage(Image, File, #PB_ImagePlugin_PNG, 0, 32)
      Else
        ok = SaveImage(Image, File, #PB_ImagePlugin_PNG, 0, 24)
      EndIf
    Case "pcx" : ok = PCX_Save(Image, File)
    Case "bmp" : ok = SaveImage(Image, File, #PB_ImagePlugin_BMP, 0, 24)
    Case "tif" : ok = TIFF_Save(Image, File, *Info\HasAlpha)
    Case "jpg"
      flat = CreateImage(#PB_Any, ImageWidth(Image), ImageHeight(Image), 24)
      If flat And StartDrawing(ImageOutput(flat))
        DrawImage(ImageID(Image), 0, 0)
        StopDrawing()
        ok = SaveImage(flat, File, #PB_ImagePlugin_JPEG, 9)
      EndIf
      If flat : FreeImage(flat) : EndIf
    Case "dds"
      ; Formaat automatisch: normal map -> BC5, transparantie -> DXT5, anders DXT1; altijd met mipmaps
      If FindString(LCase(*Info\FormatName), "normal")
        format = #DDS_BC5
      ElseIf *Info\HasAlpha
        format = #DDS_DXT5
      Else
        format = #DDS_DXT1
      EndIf
      ok = DDS_Save(Image, File, format, #True)
    Case "tex"
      If *Info\Engine = 1 And *Info\Version = 4 And Not *Info\IsEffect And ImageWidth(Image) = *Info\Width
        ok = TEXW_SaveSE1(Image, File, *Info\HasAlpha, *Info\FirstMip, Bool(*Info\Flags & #TEX_32BIT))
      Else
        ok = TEXW_SaveSE1(Image, File, *Info\HasAlpha, 0)
      EndIf
    Case "hdr"
      If Not *Info\IsHDR Or *Info\HdrData = 0
        ProcedureReturn "not an HDR texture"
      EndIf
      ok = HDR_Save(*Info\HdrData, *Info\Width, *Info\Height, File)
  EndSelect
  If ok
    ProcedureReturn ""
  EndIf
  ProcedureReturn "could not write the file"
EndProcedure

; Zet de items om. OnlySelected = #True: alleen de geselecteerde regels.
Procedure BAT_Convert(OnlySelected.i)
  Protected outExt.s = BAT_OutputExt(), useSource.i = GetGadgetState(BAT_UseSource), force.i = GetGadgetState(BAT_Force)
  Protected fit.i = GetGadgetState(BAT_Fit1024), i.i, n.i, done.i, okCount.i, skipped.i, failed.i, resized.i, lostAlpha.i
  Protected file.s, folder.s, base.s, report.s, reason.s, image.i, info.TexInfo, w.i, h.i, new.i, answer.i, k.i
  Protected dupMode.i                       ; 0 = geen dubbele namen, 1 = nummeren, 2 = overslaan
  NewList todo.s()
  NewList target.s()
  NewMap used.i()

  ; --- Welke items? ---
  ForEach BAT_Items()
    If Not OnlySelected Or GetGadgetItemState(BAT_List, ListIndex(BAT_Items())) & #PB_ListIcon_Selected
      AddElement(todo()) : todo() = BAT_Items()\Path
    EndIf
  Next
  If ListSize(todo()) = 0
    MessageRequester("Batch conversion", "Nothing selected.", #PB_MessageRequester_Info)
    ProcedureReturn
  EndIf

  ; --- Onmogelijke keuzes ---
  If Not useSource And BAT_OutDir = ""
    MessageRequester("Batch conversion", "Please choose an output folder first (or tick 'Use source folder as output folder').", #PB_MessageRequester_Warning)
    ProcedureReturn
  EndIf
  If Not useSource And FileSize(BAT_OutDir) <> -2
    MessageRequester("Batch conversion", "The output folder does not exist:" + #LF$ + BAT_OutDir, #PB_MessageRequester_Warning)
    ProcedureReturn
  EndIf
  If outExt = "jpg" Or outExt = "pcx" Or outExt = "bmp"
    ; Alleen een opmerking vooraf; welke bestanden transparantie hebben weten we pas bij het laden
    If MessageRequester("Batch conversion", UCase(outExt) + " has no transparency: any transparency in the files will be lost." + #LF$ + "Continue?", #PB_MessageRequester_YesNo | #PB_MessageRequester_Warning) <> #PB_MessageRequester_Yes
      ProcedureReturn
    EndIf
  EndIf

  ; --- Uitvoernamen bepalen en dubbele namen opsporen ---
  ForEach todo()
    base = GetFilePart(BAT_ItemName(todo()), #PB_FileSystem_NoExtension)
    If useSource
      folder = GetPathPart(todo())
    Else
      folder = BAT_OutDir
    EndIf
    AddElement(target()) : target() = folder + base + "." + outExt
    used(LCase(target())) + 1
  Next
  ForEach used()
    If used() > 1 : dupMode = 1 : Break : EndIf
  Next
  If dupMode
    answer = MessageRequester("Batch conversion", "Some files have the same name (for example from different subfolders or archives) and would end up as the same output file." + #LF$ + #LF$ + "Yes = add a number to the names (name_2, name_3, ...)" + #LF$ + "No = convert only the first one of each name" + #LF$ + "Cancel = stop", #PB_MessageRequester_YesNoCancel | #PB_MessageRequester_Warning)
    Select answer
      Case #PB_MessageRequester_Yes : dupMode = 1
      Case #PB_MessageRequester_No  : dupMode = 2
      Default : ProcedureReturn
    EndSelect
  EndIf

  ; --- Omzetten ---
  BAT_Busy = #True : BAT_Cancel = #False
  SetGadgetText(BAT_Close, "Stop")
  ClearMap(used())
  n = ListSize(todo())
  ResetList(target())
  ForEach todo()
    NextElement(target())
    done + 1
    If BAT_Cancel : Break : EndIf
    SetGadgetState(BAT_Bar, done * 100 / n)
    SetGadgetText(BAT_Status, "Converting " + Str(done) + " of " + Str(n) + ": " + BAT_ItemName(todo()))
    BAT_Pump()

    ; Dubbele namen: nummeren of overslaan
    file = target()
    k = used(LCase(file)) + 1
    used(LCase(file)) = k
    If k > 1
      If dupMode = 2
        skipped + 1 : report + BAT_ItemName(todo()) + ": skipped (same name as an earlier file)" + #LF$
        Continue
      EndIf
      file = GetPathPart(file) + GetFilePart(file, #PB_FileSystem_NoExtension) + "_" + Str(k) + "." + outExt
    EndIf
    ; Nooit het bronbestand zelf overschrijven
    If LCase(file) = LCase(todo())
      skipped + 1 : report + BAT_ItemName(todo()) + ": skipped (output would overwrite the source file)" + #LF$
      Continue
    EndIf
    If FileSize(file) >= 0 And Not force
      skipped + 1 : report + GetFilePart(file) + ": skipped (already exists)" + #LF$
      Continue
    EndIf

    image = BAT_Load(todo(), @info)
    If image = 0
      failed + 1 : report + BAT_ItemName(todo()) + ": " + info\Error + #LF$
      TEX_FreeInfo(@info)
      Continue
    EndIf
    ; SE1-.tex mag hooguit 1024 zijn
    If outExt = "tex" And (info\Width > 1024 Or info\Height > 1024)
      If fit
        RSZ_FitPow2(info\Width, info\Height, 1024, @w, @h)
        new = RSZ_Scale(image, w, h)
        If new
          FreeImage(image) : image = new
          resized + 1
        EndIf
      Else
        failed + 1 : report + BAT_ItemName(todo()) + ": larger than 1024 pixels (not allowed for Serious Sam 1)" + #LF$
        FreeImage(image) : TEX_FreeInfo(@info)
        Continue
      EndIf
    EndIf
    If info\HasAlpha And (outExt = "jpg" Or outExt = "pcx" Or outExt = "bmp") : lostAlpha + 1 : EndIf

    reason = BAT_Save(image, @info, file, outExt)
    If reason = ""
      okCount + 1
    ElseIf reason = "not an HDR texture"
      skipped + 1 : report + BAT_ItemName(todo()) + ": skipped (not an HDR texture, cannot be saved as .hdr)" + #LF$
    Else
      failed + 1 : report + BAT_ItemName(todo()) + ": " + reason + #LF$
    EndIf
    FreeImage(image)
    TEX_FreeInfo(@info)
  Next

  BAT_Busy = #False
  SetGadgetText(BAT_Close, "Close")
  SetGadgetState(BAT_Bar, 0)

  ; --- Overzicht ---
  If BAT_Cancel
    SetGadgetText(BAT_Status, "Stopped.")
  Else
    SetGadgetText(BAT_Status, "Done.")
  EndIf
  report = "Converted: " + Str(okCount) + "   Skipped: " + Str(skipped) + "   Failed: " + Str(failed) + #LF$ + #LF$ + report
  If BAT_Cancel : report = "Stopped by the user." + #LF$ + report : EndIf
  If resized : report + Str(resized) + " file(s) were resized to fit 1024 pixels for Serious Sam 1." + #LF$ : EndIf
  If lostAlpha : report + Str(lostAlpha) + " file(s) lost their transparency (" + UCase(outExt) + ")." + #LF$ : EndIf
  If Len(report) > 3000 : report = Left(report, 3000) + #LF$ + "..." : EndIf
  MessageRequester("Batch conversion", report)
EndProcedure

; Haalt de geselecteerde regels uit de lijst.
Procedure BAT_RemoveSelected()
  Protected i.i
  For i = CountGadgetItems(BAT_List) - 1 To 0 Step -1
    If GetGadgetItemState(BAT_List, i) & #PB_ListIcon_Selected
      SelectElement(BAT_Items(), i)
      DeleteElement(BAT_Items())
      RemoveGadgetItem(BAT_List, i)
    EndIf
  Next
EndProcedure

; Het Source format is veranderd: bestanden van een ander formaat kunnen niet blijven staan.
Procedure BAT_SourceChanged()
  Protected i.i, wrong.i
  ForEach BAT_Items()
    If Not BAT_MatchesSource(BAT_Items()\Path) : wrong + 1 : EndIf
  Next
  If wrong
    MessageRequester("Batch conversion", Str(wrong) + " file(s) in the list do not match the new source format and were removed.", #PB_MessageRequester_Info)
    For i = ListSize(BAT_Items()) - 1 To 0 Step -1
      SelectElement(BAT_Items(), i)
      If Not BAT_MatchesSource(BAT_Items()\Path)
        DeleteElement(BAT_Items())
        RemoveGadgetItem(BAT_List, i)
      EndIf
    Next
  EndIf
EndProcedure

; ---------------------------------------------------------------------------------------------
; Venster
; ---------------------------------------------------------------------------------------------
Procedure BAT_Open(ParentWindow.i, StartDir.s = "")
  Protected event.i, done.i, file.s, archive.s, added.i, files.s, i.i, n.i, pattern.s, ext.s, lastRow.i = -2

  BAT_Dir = StartDir
  BAT_Win = OpenWindow(#PB_Any, 0, 0, 1000, 640, "Batch conversion", #PB_Window_SystemMenu | #PB_Window_WindowCentered, WindowID(ParentWindow))
  If BAT_Win = 0 : ProcedureReturn : EndIf

  ; Links: lijst en knoppen
  BAT_AddFiles  = ButtonGadget(#PB_Any, 8, 8, 110, 26, "Add files...")
  BAT_AddFolder = ButtonGadget(#PB_Any, 122, 8, 110, 26, "Add folder...")
  BAT_AddGro    = ButtonGadget(#PB_Any, 236, 8, 120, 26, "Add from .gro...")
  BAT_AddGroAll = ButtonGadget(#PB_Any, 360, 8, 130, 26, "Add all from .gro...")
  BAT_List = ListIconGadget(#PB_Any, 8, 40, 482, 512, "File", 190, #PB_ListIcon_MultiSelect | #PB_ListIcon_FullRowSelect | #PB_ListIcon_GridLines)
  AddGadgetColumn(BAT_List, 1, "Location", 400)
  EnableGadgetDrop(BAT_List, #PB_Drop_Files, #PB_Drag_Copy)
  BAT_RemoveSel = ButtonGadget(#PB_Any, 8, 558, 120, 26, "Remove selected")
  BAT_RemoveAll = ButtonGadget(#PB_Any, 132, 558, 100, 26, "Remove all")
  BAT_Count = TextGadget(#PB_Any, 240, 563, 250, 20, "")

  ; Rechts: voorbeeld en eigenschappen
  BAT_Canvas = CanvasGadget(#PB_Any, 500, 8, 492, 300)
  BAT_Props = TextGadget(#PB_Any, 500, 312, 492, 20, "", #PB_Text_Border)

  ; Rechts onder: formaten en uitvoer
  TextGadget(#PB_Any, 500, 344, 100, 20, "Source format:")
  BAT_Source = ComboBoxGadget(#PB_Any, 610, 340, 382, 24)
  AddGadgetItem(BAT_Source, -1, "Serious Sam texture (*.tex)")
  AddGadgetItem(BAT_Source, -1, "Truevision Graphics Adapter (*.tga)")
  AddGadgetItem(BAT_Source, -1, "Portable Network Graphics (*.png)")
  AddGadgetItem(BAT_Source, -1, "PiCture eXchange (*.pcx)")
  AddGadgetItem(BAT_Source, -1, "Microsoft BMP (*.bmp)")
  AddGadgetItem(BAT_Source, -1, "Tagged Image File Format (*.tif)")
  AddGadgetItem(BAT_Source, -1, "Joint Photographic Experts Group (*.jpg)")
  AddGadgetItem(BAT_Source, -1, "DirectDraw Surface (*.dds)")
  AddGadgetItem(BAT_Source, -1, "Radiance High Dynamic Range (*.hdr)")
  SetGadgetState(BAT_Source, 0)
  TextGadget(#PB_Any, 500, 376, 100, 20, "Output format:")
  BAT_Output = ComboBoxGadget(#PB_Any, 610, 372, 382, 24)
  AddGadgetItem(BAT_Output, -1, "Truevision Graphics Adapter (*.tga)")
  AddGadgetItem(BAT_Output, -1, "Portable Network Graphics (*.png)")
  AddGadgetItem(BAT_Output, -1, "PiCture eXchange (*.pcx)")
  AddGadgetItem(BAT_Output, -1, "Microsoft BMP (*.bmp)")
  AddGadgetItem(BAT_Output, -1, "Tagged Image File Format (*.tif)")
  AddGadgetItem(BAT_Output, -1, "Joint Photographic Experts Group (*.jpg)")
  AddGadgetItem(BAT_Output, -1, "DirectDraw Surface (*.dds), format chosen automatically")
  AddGadgetItem(BAT_Output, -1, "Serious Sam 1 texture (*.tex)")
  AddGadgetItem(BAT_Output, -1, "Radiance High Dynamic Range (*.hdr), HDR sources only")
  SetGadgetState(BAT_Output, 0)
  BAT_UseSource = CheckBoxGadget(#PB_Any, 500, 406, 492, 22, "Use source folder as output folder")
  SetGadgetState(BAT_UseSource, #True)
  BAT_BrowseFolder = ButtonGadget(#PB_Any, 500, 432, 120, 26, "Output folder...")
  BAT_FolderLabel = TextGadget(#PB_Any, 626, 437, 366, 20, "")
  BAT_Force = CheckBoxGadget(#PB_Any, 500, 464, 492, 22, "Force overwriting existing files")
  BAT_Fit1024 = CheckBoxGadget(#PB_Any, 500, 488, 492, 22, "Serious Sam 1 .tex: resize textures larger than 1024 pixels")
  SetGadgetState(BAT_Fit1024, #True)
  BAT_ConvSel = ButtonGadget(#PB_Any, 500, 520, 160, 30, "Convert Selected")
  BAT_ConvAll = ButtonGadget(#PB_Any, 666, 520, 160, 30, "Convert All")
  BAT_Close   = ButtonGadget(#PB_Any, 892, 520, 100, 30, "Close")

  ; Onder: voortgang
  BAT_Bar = ProgressBarGadget(#PB_Any, 8, 596, 984, 16, 0, 100)
  BAT_Status = TextGadget(#PB_Any, 8, 616, 984, 20, "Add files with the buttons above the list, or drag them onto the list.")

  ; Instellingen van de vorige keer (Settings.pbi)
  SetGadgetState(BAT_Source, PREF_Limit(SET_ReadInt("BatchSource", 0), 0, CountGadgetItems(BAT_Source) - 1))
  SetGadgetState(BAT_Output, PREF_Limit(SET_ReadInt("BatchOutput", 0), 0, CountGadgetItems(BAT_Output) - 1))
  SetGadgetState(BAT_UseSource, Bool(SET_ReadInt("BatchUseSource", #True)))
  SetGadgetState(BAT_Force, Bool(SET_ReadInt("BatchForce", #False)))
  SetGadgetState(BAT_Fit1024, Bool(SET_ReadInt("BatchFit1024", #True)))
  If BAT_OutDir = "" : BAT_OutDir = SET_ReadFolder("BatchOutputFolder") : EndIf

  ClearList(BAT_Items())
  BAT_UpdateControls()
  BAT_ShowPreview()
  DisableWindow(ParentWindow, #True)

  Repeat
    event = WaitWindowEvent()
    If EventWindow() <> BAT_Win : Continue : EndIf
    Select event
      Case #PB_Event_CloseWindow
        done = #True

      Case #PB_Event_GadgetDrop
        ; Bestanden of mappen gesleept vanuit de verkenner
        If EventGadget() = BAT_List
          files = EventDropFiles()
          n = CountString(files, Chr(10)) + 1
          added = 0
          For i = 1 To n
            file = StringField(files, i, Chr(10))
            If FileSize(file) = -2
              added + BAT_AddFolder(file)
            ElseIf file <> ""
              added + BAT_AddPath(file)
            EndIf
          Next
          SetGadgetText(BAT_Status, Str(added) + " file(s) added (only ." + BAT_SourceExt() + " files are accepted with this source format).")
          BAT_UpdateControls()
        EndIf

      Case #PB_Event_Gadget
        Select EventGadget()
          Case BAT_Close
            done = #True

          Case BAT_AddFiles
            ext = BAT_SourceExt()
            pattern = "Source format (*." + ext + ")|*." + ext
            If ext = "tif" : pattern = "Source format (*.tif)|*.tif;*.tiff" : EndIf
            If ext = "jpg" : pattern = "Source format (*.jpg)|*.jpg;*.jpeg" : EndIf
            file = OpenFileRequester("Add files", BAT_Dir, pattern, 0, #PB_Requester_MultiSelection)
            added = 0
            While file <> ""
              BAT_Dir = GetPathPart(file)
              added + BAT_AddPath(file)
              file = NextSelectedFileName()
            Wend
            SetGadgetText(BAT_Status, Str(added) + " file(s) added.")
            BAT_UpdateControls()

          Case BAT_AddFolder
            file = PathRequester("Add all ." + BAT_SourceExt() + " files from a folder (including subfolders)", BAT_Dir)
            If file <> ""
              BAT_Dir = file
              SetGadgetText(BAT_Status, "Searching " + file + " ...")
              BAT_Pump()
              added = BAT_AddFolder(file)
              SetGadgetText(BAT_Status, Str(added) + " file(s) added from " + file)
              BAT_UpdateControls()
            EndIf

          Case BAT_AddGro, BAT_AddGroAll
            archive = OpenFileRequester("Open .gro archive", BAT_Dir, "Serious Sam archive (*.gro)|*.gro", 0)
            If archive <> ""
              BAT_Dir = GetPathPart(archive)
              added = 0
              If EventGadget() = BAT_AddGroAll
                SetGadgetText(BAT_Status, "Reading " + GetFilePart(archive) + " ...")
                BAT_Pump()
                GRO_ReadList(archive)
                ForEach GRO_Entries()
                  added + BAT_AddPath(archive + #GRO_Separator + GRO_Entries()\Name)
                Next
              ElseIf GRO_ChooseTex(archive, BAT_Win, #True) <> ""
                ForEach GRO_Chosen()
                  added + BAT_AddPath(archive + #GRO_Separator + GRO_Chosen())
                Next
              EndIf
              SetGadgetText(BAT_Status, Str(added) + " texture(s) added from " + GetFilePart(archive))
              BAT_UpdateControls()
            EndIf

          Case BAT_RemoveSel
            BAT_RemoveSelected() : BAT_UpdateControls() : BAT_ShowPreview()

          Case BAT_RemoveAll
            ClearList(BAT_Items()) : ClearGadgetItems(BAT_List) : BAT_UpdateControls() : BAT_ShowPreview()

          Case BAT_List
            ; Selectie veranderd: voorbeeld van de laatst aangeklikte regel
            If GetGadgetState(BAT_List) <> lastRow
              lastRow = GetGadgetState(BAT_List)
              BAT_ShowPreview()
            EndIf
            BAT_UpdateCount()

          Case BAT_Source
            If EventType() = #PB_EventType_Change
              BAT_SourceChanged() : BAT_UpdateControls() : BAT_ShowPreview()
            EndIf

          Case BAT_Output, BAT_UseSource
            BAT_UpdateControls()

          Case BAT_BrowseFolder
            file = PathRequester("Choose the output folder", BAT_OutDir)
            If file <> ""
              BAT_OutDir = file
              BAT_UpdateControls()
            EndIf

          Case BAT_ConvSel
            BAT_Convert(#True)

          Case BAT_ConvAll
            BAT_Convert(#False)
        EndSelect
    EndSelect
  Until done

  ; Instellingen bewaren voor de volgende keer
  SET_WriteInt("BatchSource", GetGadgetState(BAT_Source))
  SET_WriteInt("BatchOutput", GetGadgetState(BAT_Output))
  SET_WriteInt("BatchUseSource", GetGadgetState(BAT_UseSource))
  SET_WriteInt("BatchForce", GetGadgetState(BAT_Force))
  SET_WriteInt("BatchFit1024", GetGadgetState(BAT_Fit1024))
  SET_Write("BatchOutputFolder", BAT_OutDir)

  DisableWindow(ParentWindow, #False)
  CloseWindow(BAT_Win)
  BAT_Win = 0
  SetActiveWindow(ParentWindow)
EndProcedure
