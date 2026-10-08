; Serious Sam TEX Converter
; Opent Serious Sam 1, 2 en 3 .tex-bestanden, toont ze op het canvas en slaat ze op als
; .png of .tga (HDR-textures ook verliesvrij als .hdr).
; Gebaseerd op Voorbeeld-Mainwindow.pb.

EnableExplicit

XIncludeFile "Settings.pbi"     ; SET_Read(), SET_Write() - instellingen bewaren (o.a. laatste mappen)
XIncludeFile "Preferences.pbi"  ; PREF_Load(), PREF_Dialog() - voorkeuren (Tools > Preferences)
XIncludeFile "TexReader.pbi"    ; TEX_Load() - .tex inlezen (SE1, SE2 en SE3)
XIncludeFile "TGAWriter.pbi"    ; TGA_Save() - eigen TGA-encoder
XIncludeFile "HDRWriter.pbi"    ; HDR_Save() - verliesvrij opslaan van HDR-textures
XIncludeFile "Histogram.pbi"    ; Histogram_Open() - histogramvenster (menu Tools)
XIncludeFile "PCXWriter.pbi"    ; PCX_Save() - eigen PCX-encoder
XIncludeFile "TIFFWriter.pbi"   ; TIFF_Save() - eigen TIFF-encoder
XIncludeFile "ImageReader.pbi"  ; IMG_Load() - gewone beeldbestanden openen (png, tga, pcx, hdr, ...)
XIncludeFile "GroReader.pbi"    ; GRO_ChooseTex() - een .tex kiezen uit een .gro-archief
XIncludeFile "TexWriterSE1.pbi" ; TEXW_SaveSE1() - opslaan als Serious Sam 1-.tex
XIncludeFile "Resize.pbi"       ; RSZ_Scale(), RSZ_Dialog() - schalen (menu Tools)
XIncludeFile "DDSWriter.pbi"    ; DDS_Save() - opslaan als DDS (met eigen DXT-encoder)
XIncludeFile "Channels.pbi"     ; CH_Extract(), CH_SetAlpha() ... - kanalen splitsen en samenvoegen
XIncludeFile "NormalMap.pbi"    ; NM_FlipGreen(), NM_FromHeight() ... - normal maps omzetten
XIncludeFile "Skybox.pbi"       ; SKY_Open() - skybox-set bekijken en omzetten
XIncludeFile "Batch.pbi"        ; BAT_Open() - veel bestanden tegelijk omzetten (Tools > Batch conversion)
XIncludeFile "EditHistory.pbi"  ; EH_Push(), EH_Undo() ... - ongedaan maken en opnieuw doen (menu Edit)
XIncludeFile "Adjust.pbi"       ; ADJ_LevelsDialog(), ADJ_AutoLevels() ... - histogram-bewerkingen (menu Adjust)

UsePNGImageEncoder()            ; PNG opslaan zit wel in PureBasic
UseJPEGImageEncoder()           ; JPG ook; BMP zit standaard in PureBasic

Global AppTitle.s = "Serious Sam TEX Converter"
Global Window_0
Global ScrollArea_0, Canvas_0
Global default_X.l, default_Y.l, default_W.l, default_H.l ; eventueel later uit een .ini gehaalde waarden
default_X = 100
default_Y = 50
default_H = 448
default_W = 824
Global StartCentered.i = #PB_Window_ScreenCentered   ; 0 als de positie van de vorige keer gebruikt wordt
Global StartMaximized.i

Global CurrentImage.i           ; het geladen plaatje (0 = niets geladen)
Global CurrentInfo.TexInfo      ; gegevens uit de kop van het .tex-bestand
Global CurrentFile.s            ; pad van het geopende .tex-bestand
Global SavedFile.s              ; pad waar het laatst naartoe is opgeslagen (voor Ctrl+S)
Global LastDir.s                ; map die de bestandskiezer de volgende keer toont
Global LastDDSFormat.i = -1      ; laatst gekozen DDS-formaat (voor Ctrl+S), -1 = nog niet gekozen
Global LastDDSMips.i = #True
Global NameSuffix.s              ; achtervoegsel voor de voorgestelde naam bij Save As, bijv. "_alpha"
Global CurrentStatus.s            ; tekst in statusbalkveld 2 (maat en soort), ook nodig voor Undo
Global LastClipped.i             ; geclipte waarden van de bewerking die nu wordt vastgelegd (Levels)
Global LastSaveDir.s            ; map waar het laatst is opgeslagen (voor textures uit een .gro)

#CheckerSize = 8                ; grootte van de blokjes van het schaakbord achter transparante delen
#MinViewSize = 256              ; kleinere plaatjes worden vergroot zodat ze zichtbaar zijn

Enumeration FormMenu
  #Menu_Open
  #Menu_Save
  #Menu_SaveAs
  #Menu_Quit
  #Menu_Batch
  #Menu_Preferences
  #Menu_Help
  #Menu_About
  #Menu_ExposureUp
  #Menu_ExposureDown
  #Menu_ExposureReset
  #Menu_ToneClip
  #Menu_ToneFilmic
  #Menu_ToneToggle
  #Menu_Histogram
  #Menu_OpenGro
  #Menu_Resize
  #Menu_ChRed
  #Menu_ChGreen
  #Menu_ChBlue
  #Menu_ChAlpha
  #Menu_ChLoadAlpha
  #Menu_ChRemoveAlpha
  #Menu_ChInvertAlpha
  #Menu_NmFlipGreen
  #Menu_NmFlipRed
  #Menu_NmRebuildZ
  #Menu_NmNormalize
  #Menu_NmFromHeight
  #Menu_Skybox
  #Menu_Undo
  #Menu_Redo
  #Menu_Revert
  #Menu_Levels
  #Menu_AutoLevels
  #Statusbar
EndEnumeration


Procedure OpenWindow_0()
  Window_0 = OpenWindow(#PB_Any, default_X, default_Y, default_W, default_H, AppTitle, #PB_Window_SystemMenu | #PB_Window_MinimizeGadget | #PB_Window_MaximizeGadget | #PB_Window_SizeGadget | #PB_Window_TitleBar | StartCentered)
  CreateStatusBar(#Statusbar, WindowID(Window_0))
  AddStatusBarField(220)
  AddStatusBarField(380)
  AddStatusBarField(#PB_Ignore)
  CreateMenu(0, WindowID(Window_0))
  MenuTitle("File")
  MenuItem(#Menu_Open, "Open"+Chr(9)+"Ctrl+O")
  MenuItem(#Menu_OpenGro, "Open from .gro archive..."+Chr(9)+"Ctrl+G")
  MenuItem(#Menu_Save, "Save"+Chr(9)+"Ctrl+S")
  MenuItem(#Menu_SaveAs, "Save As..."+Chr(9)+"Shift+Ctrl+S")
  MenuBar()
  MenuItem(#Menu_Quit, "Quit"+Chr(9)+"Ctrl+Q")
  MenuTitle("Edit")
  MenuItem(#Menu_Undo, "Undo"+Chr(9)+"Ctrl+Z")
  MenuItem(#Menu_Redo, "Redo"+Chr(9)+"Ctrl+Y")
  MenuBar()
  MenuItem(#Menu_Revert, "Revert to original")
  MenuTitle("Adjust")
  MenuItem(#Menu_Levels, "Levels..."+Chr(9)+"Ctrl+L")
  MenuItem(#Menu_AutoLevels, "Auto levels")
  MenuTitle("HDR")
  ; Belichting van HDR-textures: één waarde voor alle bestanden, zodat skybox-vlakken op elkaar aansluiten
  MenuItem(#Menu_ExposureUp, "Exposure +1 EV"+Chr(9)+"Ctrl+Up")
  MenuItem(#Menu_ExposureDown, "Exposure -1 EV"+Chr(9)+"Ctrl+Down")
  MenuItem(#Menu_ExposureReset, "Reset exposure"+Chr(9)+"Ctrl+0")
  MenuBar()
  ; Hoe heldere HDR-delen worden weergegeven; het vinkje laat de huidige keuze zien
  MenuItem(#Menu_ToneClip, "Tone: Editor (clip)")
  MenuItem(#Menu_ToneFilmic, "Tone: Filmic")
  MenuItem(#Menu_ToneToggle, "Switch tone"+Chr(9)+"Ctrl+T")
  SetMenuItemState(0, #Menu_ToneClip, #True)
  MenuTitle("Tools")
  MenuItem(#Menu_Histogram, "Histogram"+Chr(9)+"Ctrl+I")
  OpenSubMenu("Channels")
    MenuItem(#Menu_ChRed, "Extract red as grayscale")
    MenuItem(#Menu_ChGreen, "Extract green as grayscale")
    MenuItem(#Menu_ChBlue, "Extract blue as grayscale")
    MenuItem(#Menu_ChAlpha, "Extract alpha as grayscale")
    MenuBar()
    MenuItem(#Menu_ChLoadAlpha, "Load alpha from image...")
    MenuItem(#Menu_ChInvertAlpha, "Invert alpha")
    MenuItem(#Menu_ChRemoveAlpha, "Remove alpha (make opaque)")
  CloseSubMenu()
  OpenSubMenu("Normal map")
    MenuItem(#Menu_NmFlipGreen, "Flip green (DirectX <-> OpenGL)")
    MenuItem(#Menu_NmFlipRed, "Flip red")
    MenuItem(#Menu_NmRebuildZ, "Rebuild blue (Z) from red and green")
    MenuItem(#Menu_NmNormalize, "Normalize")
    MenuBar()
    MenuItem(#Menu_NmFromHeight, "Create from height map...")
  CloseSubMenu()
  MenuBar()
  MenuItem(#Menu_Resize, "Resize..."+Chr(9)+"Ctrl+R")
  MenuItem(#Menu_Skybox, "Skybox..."+Chr(9)+"Ctrl+K")
  MenuItem(#Menu_Batch, "Batch conversion"+Chr(9)+"Ctrl+B")
  MenuBar()
  MenuItem(#Menu_Preferences, "Preferences..."+Chr(9)+"Ctrl+P")
  MenuTitle("Help")
  MenuItem(#Menu_Help, "Help"+Chr(9)+"Ctrl+H")
  MenuItem(#Menu_About, "About")

  ScrollArea_0 = ScrollAreaGadget(#PB_Any, 4, 4, 819, 400, 1034, 1034, 1, #PB_ScrollArea_Single)
  ; Geen #PB_Canvas_Border: een rand maakt het canvas groter dan het plaatje
  Canvas_0 = CanvasGadget(#PB_Any, 4, 4, 1024, 1024, #PB_Canvas_ClipMouse | #PB_Canvas_Keyboard | #PB_Canvas_DrawFocus)
  AddKeyboardShortcut(Window_0, #PB_Shortcut_Control | #PB_Shortcut_O, #Menu_Open)
  AddKeyboardShortcut(Window_0, #PB_Shortcut_Control | #PB_Shortcut_S, #Menu_Save)
  AddKeyboardShortcut(Window_0, #PB_Shortcut_Shift|#PB_Shortcut_Control | #PB_Shortcut_S, #Menu_SaveAs)
  AddKeyboardShortcut(Window_0, #PB_Shortcut_Control | #PB_Shortcut_Q, #Menu_Quit)
  AddKeyboardShortcut(Window_0, #PB_Shortcut_Control | #PB_Shortcut_B, #Menu_Batch)
  AddKeyboardShortcut(Window_0, #PB_Shortcut_Control | #PB_Shortcut_P, #Menu_Preferences)
  AddKeyboardShortcut(Window_0, #PB_Shortcut_Control | #PB_Shortcut_H, #Menu_Help)
  AddKeyboardShortcut(Window_0, #PB_Shortcut_Control | #PB_Shortcut_Up, #Menu_ExposureUp)
  AddKeyboardShortcut(Window_0, #PB_Shortcut_Control | #PB_Shortcut_Down, #Menu_ExposureDown)
  AddKeyboardShortcut(Window_0, #PB_Shortcut_Control | #PB_Shortcut_0, #Menu_ExposureReset)
  AddKeyboardShortcut(Window_0, #PB_Shortcut_Control | #PB_Shortcut_T, #Menu_ToneToggle)
  AddKeyboardShortcut(Window_0, #PB_Shortcut_Control | #PB_Shortcut_I, #Menu_Histogram)
  AddKeyboardShortcut(Window_0, #PB_Shortcut_Control | #PB_Shortcut_G, #Menu_OpenGro)
  AddKeyboardShortcut(Window_0, #PB_Shortcut_Control | #PB_Shortcut_R, #Menu_Resize)
  AddKeyboardShortcut(Window_0, #PB_Shortcut_Control | #PB_Shortcut_K, #Menu_Skybox)
  AddKeyboardShortcut(Window_0, #PB_Shortcut_Control | #PB_Shortcut_Z, #Menu_Undo)
  AddKeyboardShortcut(Window_0, #PB_Shortcut_Control | #PB_Shortcut_Y, #Menu_Redo)
  AddKeyboardShortcut(Window_0, #PB_Shortcut_Control | #PB_Shortcut_L, #Menu_Levels)
  CloseGadgetList()

  ; Nog niets geladen: maak het canvas grijs
  If StartDrawing(CanvasOutput(Canvas_0))
    Box(0, 0, OutputWidth(), OutputHeight(), RGB(160, 160, 160))
    StopDrawing()
  EndIf
  StatusBarText(#Statusbar, 0, "No file opened")
EndProcedure

Procedure WindowResizing()
  Protected w_Width.i, w_Height.i
  w_Width =  WindowWidth(Window_0,#PB_Window_InnerCoordinate)
  w_Height = WindowHeight(Window_0,#PB_Window_InnerCoordinate)

  Protected m_Height.l = MenuHeight()
  Protected s_Height.l = StatusBarHeight(#StatusBar)

  ; -10 en -60 is empirisch vastgesteld in linux-mint en windows, menu en statusbar hoogte?
  ; krijg dit niet kloppend met MenuHeight() + StatusBarHeight(#StatusBar) = 43
  ResizeGadget(ScrollArea_0, 4, 4, w_Width-10, w_Height-60)
EndProcedure

; Tekent CurrentImage op het canvas, met een schaakbord achter de transparante delen.
Procedure ShowImage()
  Protected width.i, height.i, zoom.i, viewW.i, viewH.i, shown.i, x.i, y.i, color.i

  If CurrentImage = 0
    ProcedureReturn
  EndIf

  width  = ImageWidth(CurrentImage)
  height = ImageHeight(CurrentImage)

  ; Heel kleine plaatjes (bijv. 1 x 8) vergroten met een heel getal, zodat de pixels scherp blijven
  zoom = 1
  If width < #MinViewSize And height < #MinViewSize
    If width > height
      zoom = #MinViewSize / width
    Else
      zoom = #MinViewSize / height
    EndIf
  EndIf
  viewW = width * zoom
  viewH = height * zoom

  ; Kopie maken om op te tekenen; het origineel blijft onveranderd voor het opslaan
  shown = CopyImage(CurrentImage, #PB_Any)
  If shown = 0
    ProcedureReturn
  EndIf
  If zoom > 1
    ResizeImage(shown, viewW, viewH, #PB_Image_Raw)   ; Raw = niet vervagen
  EndIf

  ; Canvas en scrollgebied even groot maken als het plaatje.
  ; Gadgets werken met schermschaal (bijv. 150% in Windows), plaatjes met echte pixels.
  ; DesktopUnscaledX/Y rekent pixels om naar gadget-eenheden, zodat het canvas precies past.
  ResizeGadget(Canvas_0, #PB_Ignore, #PB_Ignore, DesktopUnscaledX(viewW), DesktopUnscaledY(viewH))
  SetGadgetAttribute(ScrollArea_0, #PB_ScrollArea_InnerWidth, DesktopUnscaledX(viewW) + 8)
  SetGadgetAttribute(ScrollArea_0, #PB_ScrollArea_InnerHeight, DesktopUnscaledY(viewH) + 8)

  If StartDrawing(CanvasOutput(Canvas_0))
    ; Eerst het hele canvas wissen, zodat er niets van het vorige plaatje overblijft
    ; (door afronding kan het canvas een pixel groter zijn dan het plaatje)
    Box(0, 0, OutputWidth(), OutputHeight(), RGB(160, 160, 160))
    ; Achtergrond achter transparante delen (keuze in Preferences)
    Select PREF_Background
      Case #PREF_BgBlack : Box(0, 0, viewW, viewH, RGB(0, 0, 0))
      Case #PREF_BgGray  : Box(0, 0, viewW, viewH, RGB(128, 128, 128))
      Case #PREF_BgWhite : Box(0, 0, viewW, viewH, RGB(255, 255, 255))
      Default
        For y = 0 To viewH - 1 Step #CheckerSize
          For x = 0 To viewW - 1 Step #CheckerSize
            If (x / #CheckerSize + y / #CheckerSize) & 1
              color = RGB(204, 204, 204)
            Else
              color = RGB(255, 255, 255)
            EndIf
            Box(x, y, #CheckerSize, #CheckerSize, color)
          Next
        Next
    EndSelect
    DrawAlphaImage(ImageID(shown), 0, 0)   ; tekent het plaatje mét transparantie
    StopDrawing()
  EndIf
  FreeImage(shown)

  If CurrentInfo\Note <> ""
    StatusBarText(#Statusbar, 2, CurrentInfo\Note)
  ElseIf zoom > 1
    StatusBarText(#Statusbar, 2, "Enlarged " + Str(zoom) + "x for visibility")
  Else
    StatusBarText(#Statusbar, 2, "")
  EndIf
EndProcedure

; Laadt een .tex-bestand en toont het. KeepSaved = #True bij opnieuw laden (bijv. na een
; andere HDR-belichting), zodat Ctrl+S nog naar hetzelfde bestand opslaat.
; Naam om te tonen: bij een texture uit een .gro alleen de bestandsnaam binnen het archief
Procedure.s DisplayName(file.s)
  If GRO_IsGroPath(file)
    ProcedureReturn GRO_EntryFileName(GRO_EntryPart(file))
  EndIf
  ProcedureReturn GetFilePart(file)
EndProcedure

; ---------------------------------------------------------------------------------------------
; Undo / Redo (zie EditHistory.pbi)
; ---------------------------------------------------------------------------------------------

; Zet de tekst in statusbalkveld 2 en onthoudt hem (zodat Undo hem terug kan zetten).
Procedure SetStatusInfo(Text.s)
  CurrentStatus = Text
  StatusBarText(#Statusbar, 1, Text)
EndProcedure

; Titelbalk (met * bij niet-opgeslagen bewerkingen) en de menu-items van Edit bijwerken.
Procedure UpdateEditUI()
  Protected title.s = AppTitle
  If CurrentImage
    title + " - " + DisplayName(CurrentFile)
    If EH_IsDirty() : title + " *" : EndIf
  EndIf
  SetWindowTitle(Window_0, title)
  If EH_CanUndo()
    SetMenuItemText(0, #Menu_Undo, "Undo " + EH_UndoName() + Chr(9) + "Ctrl+Z")
  Else
    SetMenuItemText(0, #Menu_Undo, "Undo" + Chr(9) + "Ctrl+Z")
  EndIf
  If EH_CanRedo()
    SetMenuItemText(0, #Menu_Redo, "Redo " + EH_RedoName() + Chr(9) + "Ctrl+Y")
  Else
    SetMenuItemText(0, #Menu_Redo, "Redo" + Chr(9) + "Ctrl+Y")
  EndIf
  DisableMenuItem(0, #Menu_Undo, Bool(Not EH_CanUndo()))
  DisableMenuItem(0, #Menu_Redo, Bool(Not EH_CanRedo()))
  DisableMenuItem(0, #Menu_Revert, Bool(Not EH_CanUndo()))
EndProcedure

; Legt de huidige toestand vast na een bewerking met naam Name.
Procedure PushEdit(Name.s)
  Protected s.EditState
  s\Name = Name
  s\Width = CurrentInfo\Width : s\Height = CurrentInfo\Height
  s\HasAlpha = CurrentInfo\HasAlpha : s\IsHDR = CurrentInfo\IsHDR
  s\FirstMip = CurrentInfo\FirstMip
  s\Note = CurrentInfo\Note : s\Suffix = NameSuffix : s\Status = CurrentStatus
  s\Clipped = LastClipped : LastClipped = 0
  EH_Push(CurrentImage, @s)
  UpdateEditUI()
EndProcedure

; Zet een bewaarde toestand terug als het geladen plaatje.
Procedure ApplyState(*s.EditState)
  Protected copy.i
  If *s = 0 : ProcedureReturn : EndIf
  copy = CopyImage(*s\Image, #PB_Any)
  If copy = 0
    MessageRequester(AppTitle, "Not enough memory for this operation.", #PB_MessageRequester_Error)
    ProcedureReturn
  EndIf
  If CurrentImage : FreeImage(CurrentImage) : EndIf
  CurrentImage = copy
  CurrentInfo\Width = *s\Width : CurrentInfo\Height = *s\Height
  CurrentInfo\HasAlpha = *s\HasAlpha
  ; HDR alleen als de HDR-data er nog is (die bewaren we tot een ander bestand wordt geopend)
  CurrentInfo\IsHDR = Bool(*s\IsHDR And CurrentInfo\HdrData)
  CurrentInfo\FirstMip = *s\FirstMip
  CurrentInfo\Note = *s\Note
  NameSuffix = *s\Suffix
  SetStatusInfo(*s\Status)
  ShowImage()
  Histogram_Update(CurrentImage, @CurrentInfo, TEXSE3_ExposureEV)
  UpdateEditUI()
EndProcedure

; Vraagt of niet-opgeslagen bewerkingen weg mogen. Geeft #True als we verder mogen.
Procedure.i ConfirmDiscard()
  If Not EH_IsDirty()
    ProcedureReturn #True
  EndIf
  ProcedureReturn Bool(MessageRequester(AppTitle, DisplayName(CurrentFile) + " has edits that have not been saved (" + Str(EH_EditCount()) + " edit(s))." + #LF$ + "Discard them?", #PB_MessageRequester_YesNo | #PB_MessageRequester_Warning) = #PB_MessageRequester_Yes)
EndProcedure
Procedure LoadFile(file.s, KeepSaved.i = #False)
  Protected image.i, info.TexInfo, kind.s, *mem, size.i, s.EditState

  ; Niet-opgeslagen bewerkingen? Eerst vragen (niet bij opnieuw laden voor de HDR-belichting)
  If Not KeepSaved And Not ConfirmDiscard()
    ProcedureReturn
  EndIf

  ; Uit een .gro-archief: eerst uitpakken naar het geheugen
  If GRO_IsGroPath(file)
    *mem = GRO_Extract(GRO_ArchivePart(file), GRO_EntryPart(file), @size)
    If *mem
      image = TEX_LoadMemory(*mem, size, @info, "")
      FreeMemory(*mem)
    Else
      info\Error = "Could not extract it from the archive."
    EndIf
  ; Gewone beeldbestanden via ImageReader.pbi, al het andere als Serious Sam-texture
  ElseIf FindString(",png,tga,bmp,jpg,jpeg,tif,tiff,pcx,hdr,dds,", "," + LCase(GetExtensionPart(file)) + ",")
    image = IMG_Load(file, @info)
  Else
    image = TEX_Load(file, @info)
  EndIf
  If image = 0
    MessageRequester(AppTitle, DisplayName(file) + " could not be loaded:" + #LF$ + info\Error, #PB_MessageRequester_Error)
    ProcedureReturn
  EndIf

  ; Het oude plaatje (en eventuele HDR-data) opruimen en het nieuwe onthouden
  If CurrentImage
    FreeImage(CurrentImage)
  EndIf
  TEX_FreeInfo(@CurrentInfo)
  CurrentImage = image
  CopyStructure(@info, @CurrentInfo, TexInfo)   ; CurrentInfo is nu eigenaar van info\HdrData
  CurrentFile = file
  If Not KeepSaved
    SavedFile = ""
    NameSuffix = ""
  EndIf
  If GRO_IsGroPath(file)
    LastDir = GetPathPart(GRO_ArchivePart(file))
  Else
    LastDir = GetPathPart(file)
  EndIf
  SET_Write("LastOpenFolder", LastDir)        ; onthouden voor de volgende keer dat het programma start

  If info\Engine = 0
    ; Gewoon beeldbestand (geen .tex)
    kind = info\FormatName
    If info\HasAlpha
      kind + ", with transparency"
    EndIf
  ElseIf info\Engine = 3
    kind = "SS3, " + info\FormatName
  ElseIf info\Engine = 2
    ; Serious Sam 2: de formaatnaam uit Serious Editor 2.0 zegt het meest
    kind = "SS2, " + info\FormatName
  Else
    If info\HasAlpha
      kind = "RGBA (with transparency)"
    Else
      kind = "RGB"
    EndIf
    kind + ", SS1 version " + Str(info\Version)
    If info\BytesPerPixel = 2
      kind + " (16-bit)"
    EndIf
  EndIf
  StatusBarText(#Statusbar, 0, DisplayName(file))
  SetStatusInfo(Str(info\Width) + " x " + Str(info\Height) + "  " + kind)
  ShowImage()
  Histogram_Update(CurrentImage, @CurrentInfo, TEXSE3_ExposureEV)   ; alleen als het histogramvenster open is

  ; Undo opnieuw beginnen, met dit plaatje als origineel
  s\Name = "Original"
  s\Width = CurrentInfo\Width : s\Height = CurrentInfo\Height
  s\HasAlpha = CurrentInfo\HasAlpha : s\IsHDR = CurrentInfo\IsHDR
  s\FirstMip = CurrentInfo\FirstMip
  s\Note = CurrentInfo\Note : s\Suffix = NameSuffix : s\Status = CurrentStatus
  s\Clipped = LastClipped : LastClipped = 0
  EH_Reset(CurrentImage, @s)
  UpdateEditUI()
EndProcedure

Procedure OpenTex()
  Protected file.s

  Protected pattern.s
  pattern = "Serious Sam texture (*.tex)|*.tex|"
  pattern + "All supported images|*.tex;*.tga;*.png;*.pcx;*.bmp;*.tif;*.tiff;*.jpg;*.jpeg;*.dds;*.hdr|"
  pattern + "All files (*.*)|*.*"
  file = OpenFileRequester("Open file", LastDir, pattern, 0)
  If file <> ""                        ; leeg = gebruiker heeft op Annuleren geklikt
    LoadFile(file)
  EndIf
EndProcedure

; Kiest eerst een .gro-archief en daarna een .tex daarin
Procedure OpenFromGro()
  Protected archive.s, entry.s
  archive = OpenFileRequester("Open .gro archive", LastDir, "Serious Sam archive (*.gro)|*.gro|All files (*.*)|*.*", 0)
  If archive = ""
    ProcedureReturn
  EndIf
  entry = GRO_ChooseTex(archive, Window_0)
  If entry <> ""
    LoadFile(archive + #GRO_Separator + entry)
  EndIf
EndProcedure

; Geeft #True als er een HDR-texture geladen is. Zo niet, dan een melding en verandert er niets:
; de instellingen in het HDR-menu blijven zoals ze waren.
Procedure.i HdrLoaded()
  Protected reason.s
  If CurrentImage And CurrentInfo\IsHDR
    ProcedureReturn #True
  EndIf
  If CurrentImage = 0
    reason = "No texture is loaded."
  ElseIf CurrentInfo\HdrData
    reason = DisplayName(CurrentFile) + " has been edited and is no longer an HDR image (Undo brings the HDR original back)."
  Else
    reason = DisplayName(CurrentFile) + " is not an HDR texture."
  EndIf
  MessageRequester(AppTitle, reason + #LF$ + "The settings in the HDR menu only apply to HDR textures; nothing was changed.", #PB_MessageRequester_Info)
  ProcedureReturn #False
EndProcedure

; Verandert de HDR-belichting (geldt voor alle HDR-bestanden) en laadt een HDR-texture opnieuw.
Procedure ChangeExposure(Delta.d, Reset.i = #False)
  If Not HdrLoaded()
    ProcedureReturn
  EndIf
  If Reset
    TEXSE3_ExposureEV = #TEXSE3_DefaultExposureEV
  Else
    TEXSE3_ExposureEV + Delta
  EndIf
  LoadFile(CurrentFile, #True)
EndProcedure

; Kiest hoe heldere HDR-delen worden weergegeven (geldt voor alle HDR-bestanden).
Procedure SetToneMode(Mode.i)
  If HdrLoaded()
    TEXSE3_ToneMode = Mode
    LoadFile(CurrentFile, #True)
  EndIf
  ; Vinkjes altijd volgens de echte instelling (een klik op het menu zet anders zelf een vinkje)
  SetMenuItemState(0, #Menu_ToneClip, Bool(TEXSE3_ToneMode = #TEXSE3_ToneClip))
  SetMenuItemState(0, #Menu_ToneFilmic, Bool(TEXSE3_ToneMode = #TEXSE3_ToneFilmic))
EndProcedure

; Schaalt het geladen plaatje naar NewWidth x NewHeight (alleen in het geheugen; het bestand blijft
; zoals het was). Opnieuw openen haalt het origineel terug.
Procedure ResizeCurrent(NewWidth.i, NewHeight.i)
  Protected new.i, oldW.i, oldH.i, ratio.i, steps.i

  If CurrentImage = 0
    ProcedureReturn
  EndIf
  oldW = ImageWidth(CurrentImage)
  oldH = ImageHeight(CurrentImage)
  If NewWidth = oldW And NewHeight = oldH
    ProcedureReturn
  EndIf
  new = RSZ_Scale(CurrentImage, NewWidth, NewHeight)
  If new = 0
    MessageRequester(AppTitle, "Not enough memory to resize the image.", #PB_MessageRequester_Error)
    ProcedureReturn
  EndIf
  FreeImage(CurrentImage)
  CurrentImage = new
  CurrentInfo\Width = NewWidth
  CurrentInfo\Height = NewHeight

  ; SE1-texture precies 2, 4, 8... keer kleiner: firstMip evenveel ophogen, dan blijft de
  ; mex-maat (de grootte in het spel) gelijk als je hem weer als .tex opslaat
  If CurrentInfo\Engine = 1 And oldW % NewWidth = 0 And TEXW_IsPowerOf2(oldW / NewWidth) And oldW / NewWidth = oldH / NewHeight
    ratio = oldW / NewWidth
    While ratio > 1 : ratio >> 1 : steps + 1 : Wend
    CurrentInfo\FirstMip + steps
  EndIf

  ; Een HDR-texture wordt met de huidige belichting geschaald; de HDR-data past dan niet meer
  ; (De HDR-data zelf blijft bewaard, zodat Undo terug kan naar het HDR-origineel.)
  If CurrentInfo\IsHDR
    CurrentInfo\IsHDR = #False
    CurrentInfo\Note = "HDR texture resized: the current exposure is now part of the image"
  Else
    CurrentInfo\Note = ""
  EndIf
  CurrentInfo\Note = "Resized from " + Str(oldW) + " x " + Str(oldH) + "   " + CurrentInfo\Note

  SetStatusInfo(Str(NewWidth) + " x " + Str(NewHeight) + "  (resized)")
  ShowImage()
  Histogram_Update(CurrentImage, @CurrentInfo, TEXSE3_ExposureEV)
  PushEdit("Resize")
EndProcedure

Procedure ResizeDialog()
  Protected w.i, h.i
  If CurrentImage = 0
    MessageRequester(AppTitle, "Please open a .tex file first.")
    ProcedureReturn
  EndIf
  If RSZ_Dialog(Window_0, ImageWidth(CurrentImage), ImageHeight(CurrentImage), @w, @h)
    ResizeCurrent(w, h)
  EndIf
EndProcedure

; Serious Sam 1 kan textures tot 1024 x 1024 pixels aan. Is het plaatje groter, dan aanbieden om
; het eerst te verkleinen. Geeft #False terug als er niet opgeslagen moet worden.
Procedure.i CheckSE1Size()
  Protected w.i, h.i
  If (CurrentInfo\Width <= 1024 And CurrentInfo\Height <= 1024) Or Not PREF_WarnSE1Size
    ProcedureReturn #True
  EndIf
  RSZ_FitPow2(CurrentInfo\Width, CurrentInfo\Height, 1024, @w, @h)
  If MessageRequester(AppTitle, "Serious Sam 1 textures can be at most 1024 x 1024 pixels; this image is " + Str(CurrentInfo\Width) + " x " + Str(CurrentInfo\Height) + "." + #LF$ + #LF$ + "Resize to " + Str(w) + " x " + Str(h) + " now and save?" + #LF$ + "(Choose No to cancel; you can also use Tools > Resize.)", #PB_MessageRequester_YesNo | #PB_MessageRequester_Warning) <> #PB_MessageRequester_Yes
    ProcedureReturn #False
  EndIf
  ResizeCurrent(w, h)
  ProcedureReturn #True
EndProcedure
; Vervangt het geladen plaatje door een bewerkte versie (kanalen). Note komt in de statusbalk,
; Suffix achter de voorgestelde naam bij Save As. Opnieuw openen haalt het origineel terug.
Procedure ReplaceCurrentImage(New.i, Note.s, Suffix.s)
  If New = 0
    MessageRequester(AppTitle, "Not enough memory for this operation.", #PB_MessageRequester_Error)
    ProcedureReturn
  EndIf
  FreeImage(CurrentImage)
  CurrentImage = New
  ; Een HDR-texture is na zo'n bewerking een gewoon plaatje (met de huidige belichting).
  ; De HDR-data zelf blijft bewaard, zodat Undo terug kan naar het HDR-origineel.
  If CurrentInfo\IsHDR
    CurrentInfo\IsHDR = #False
  EndIf
  CurrentInfo\HasAlpha = IMG_HasAlpha(CurrentImage)
  CurrentInfo\Note = Note
  NameSuffix + Suffix
  SetStatusInfo(Str(ImageWidth(CurrentImage)) + " x " + Str(ImageHeight(CurrentImage)) + "  (edited)")
  ShowImage()
  Histogram_Update(CurrentImage, @CurrentInfo, TEXSE3_ExposureEV)
  PushEdit(Note)
EndProcedure

; Voert een van de kanaal-bewerkingen uit het menu Tools > Channels uit.
Procedure ChannelCommand(Menu.i)
  Protected file.s, mask.i, maskInfo.TexInfo, pattern.s

  If CurrentImage = 0
    MessageRequester(AppTitle, "Please open a .tex file first.")
    ProcedureReturn
  EndIf
  Select Menu
    Case #Menu_ChRed   : ReplaceCurrentImage(CH_Extract(CurrentImage, #CH_Red), "Red channel as grayscale", "_red")
    Case #Menu_ChGreen : ReplaceCurrentImage(CH_Extract(CurrentImage, #CH_Green), "Green channel as grayscale", "_green")
    Case #Menu_ChBlue  : ReplaceCurrentImage(CH_Extract(CurrentImage, #CH_Blue), "Blue channel as grayscale", "_blue")
    Case #Menu_ChAlpha
      If Not CurrentInfo\HasAlpha
        If MessageRequester(AppTitle, "This image has no transparency; the alpha channel is completely white." + #LF$ + "Extract it anyway?", #PB_MessageRequester_YesNo) <> #PB_MessageRequester_Yes
          ProcedureReturn
        EndIf
      EndIf
      ReplaceCurrentImage(CH_Extract(CurrentImage, #CH_Alpha), "Alpha channel as grayscale", "_alpha")
    Case #Menu_ChRemoveAlpha
      ReplaceCurrentImage(CH_RemoveAlpha(CurrentImage), "Alpha removed (fully opaque)", "_opaque")
    Case #Menu_ChInvertAlpha
      ReplaceCurrentImage(CH_InvertAlpha(CurrentImage), "Alpha inverted", "_invalpha")
    Case #Menu_ChLoadAlpha
      ; Een masker kiezen: wit = dekkend, zwart = doorzichtig
      pattern = "All supported images|*.tex;*.tga;*.png;*.pcx;*.bmp;*.tif;*.tiff;*.jpg;*.jpeg;*.dds|All files (*.*)|*.*"
      file = OpenFileRequester("Choose a mask (white = opaque, black = transparent)", LastDir, pattern, 0)
      If file = ""
        ProcedureReturn
      EndIf
      If LCase(GetExtensionPart(file)) = "tex"
        mask = TEX_Load(file, @maskInfo)
      Else
        mask = IMG_Load(file, @maskInfo)
      EndIf
      If mask = 0
        MessageRequester(AppTitle, GetFilePart(file) + " could not be loaded:" + #LF$ + maskInfo\Error, #PB_MessageRequester_Error)
        ProcedureReturn
      EndIf
      ReplaceCurrentImage(CH_SetAlpha(CurrentImage, mask), "Alpha loaded from " + GetFilePart(file), "_withalpha")
      FreeImage(mask)
      TEX_FreeInfo(@maskInfo)
  EndSelect
EndProcedure
; Voert een van de bewerkingen uit het menu Tools > Normal map uit.
Procedure NormalMapCommand(Menu.i)
  Protected answer.s, strength.d

  If CurrentImage = 0
    MessageRequester(AppTitle, "Please open a .tex file first.")
    ProcedureReturn
  EndIf
  Select Menu
    Case #Menu_NmFlipGreen : ReplaceCurrentImage(NM_FlipGreen(CurrentImage), "Normal map: green flipped", "_flipg")
    Case #Menu_NmFlipRed   : ReplaceCurrentImage(NM_FlipRed(CurrentImage), "Normal map: red flipped", "_flipr")
    Case #Menu_NmRebuildZ  : ReplaceCurrentImage(NM_RebuildZ(CurrentImage), "Normal map: blue (Z) rebuilt from red and green", "_z")
    Case #Menu_NmNormalize : ReplaceCurrentImage(NM_Normalize(CurrentImage), "Normal map: normalized", "_norm")
    Case #Menu_NmFromHeight
      ; Sterkte vragen: hoe diep de bulten worden
      answer = InputRequester(AppTitle, "Create a normal map from this image (light = high, dark = low)." + #LF$ + "Strength (1 = subtle, 2 = normal, 5 = strong):", StrD(PREF_NmStrength, 1))
      If answer = ""
        ProcedureReturn
      EndIf
      strength = ValD(ReplaceString(answer, ",", "."))
      If strength <= 0
        MessageRequester(AppTitle, "Please enter a number larger than 0.", #PB_MessageRequester_Error)
        ProcedureReturn
      EndIf
      ReplaceCurrentImage(NM_FromHeight(CurrentImage, strength), "Normal map from height map (strength " + StrD(strength, 1) + ", OpenGL style: green up)", "_NM")
  EndSelect
EndProcedure
; Opent het skyboxvenster. Is het geladen plaatje een skybox-vlak, dan wordt die set meteen geladen.
Procedure SkyboxWindow()
  Protected start.s
  If CurrentImage And SKY_IsFaceName(DisplayName(CurrentFile))
    start = CurrentFile
  EndIf
  SKY_Open(Window_0, start, LastDir)
  ; Het venster kan de belichting en weergave veranderd hebben: menu en plaatje bijwerken
  SetMenuItemState(0, #Menu_ToneClip, Bool(TEXSE3_ToneMode = #TEXSE3_ToneClip))
  SetMenuItemState(0, #Menu_ToneFilmic, Bool(TEXSE3_ToneMode = #TEXSE3_ToneFilmic))
  If CurrentInfo\IsHDR
    LoadFile(CurrentFile, #True)
  EndIf
EndProcedure
; ---------------------------------------------------------------------------------------------
; Adjust-menu (zie Adjust.pbi)
; ---------------------------------------------------------------------------------------------

; Hoeveel waarden zijn er geclipt in de bewerkingen tot nu toe (voor de waarschuwing bij opslaan)?
Procedure.i ClippedInEdits()
  Protected i.i, n.i
  For i = 1 To EH_Pos
    If SelectElement(EH_States(), i) : n + EH_States()\Clipped : EndIf
  Next
  ProcedureReturn n
EndProcedure

; Voorbeeld tonen tijdens het Levels-venster. Image = 0: weer het gewone plaatje.
; ShowImage() tekent CurrentImage; daarom ruilen we die heel even om.
Procedure LevelsPreview(Image.i)
  Protected keep.i = CurrentImage
  If Image
    CurrentImage = Image
    ShowImage()
    CurrentImage = keep
  Else
    ShowImage()
  EndIf
EndProcedure

Procedure LevelsCommand()
  Protected lev.LevelsSettings, clipped.Integer, new.i
  Dim lut.a(2, 255)
  Dim clip.b(2, 255)
  If CurrentImage = 0
    MessageRequester(AppTitle, "Please open a .tex file first.")
    ProcedureReturn
  EndIf
  If ADJ_LevelsDialog(Window_0, CurrentImage, @lev, @LevelsPreview(), @clipped)
    ADJ_BuildLevelsLUT(@lev, lut())
    new = ADJ_ApplyLUT(CurrentImage, lut(), #False, clip())
    LastClipped = clipped\i
    ReplaceCurrentImage(new, "Levels", "_levels")
  EndIf
EndProcedure

; Auto levels: rekt het bereik op van de donkerste tot de lichtste waarde. Nooit clipping.
Procedure AutoLevelsCommand()
  Protected lev.LevelsSettings, new.i
  Dim hist.i(2, 255)
  Dim lut.a(2, 255)
  Dim clip.b(2, 255)
  If CurrentImage = 0
    MessageRequester(AppTitle, "Please open a .tex file first.")
    ProcedureReturn
  EndIf
  ADJ_Histogram(CurrentImage, hist())
  ADJ_AutoLevels(hist(), @lev)
  If ADJ_IsIdentity(@lev)
    MessageRequester(AppTitle, "This image already uses the full range from black to white." + #LF$ + "Auto levels has nothing to change.")
    ProcedureReturn
  EndIf
  ADJ_BuildLevelsLUT(@lev, lut())
  new = ADJ_ApplyLUT(CurrentImage, lut(), #False, clip())
  ReplaceCurrentImage(new, "Auto levels (" + Str(lev\Ch[0]\InBlack) + " - " + Str(lev\Ch[0]\InWhite) + " stretched to 0 - 255)", "_autolevels")
EndProcedure

; ---------------------------------------------------------------------------------------------
; Help-menu
; ---------------------------------------------------------------------------------------------

; Opent het helpbestand (HTML) in de webbrowser. Het staat in de map "Help" naast het programma;
; tijdens het testen vanuit de IDE staat het programma in een tijdelijke map, dan zoeken we
; naast de broncode.
Procedure OpenHelpFile()
  Protected file.s = GetPathPart(ProgramFilename()) + "Help" + #PS$ + "TexConverter-Help.html"
  If FileSize(file) < 0
    file = #PB_Compiler_FilePath + "Help" + #PS$ + "TexConverter-Help.html"
  EndIf
  If FileSize(file) < 0
    MessageRequester(AppTitle, "The help file was not found. It should be here:" + #LF$ + GetPathPart(ProgramFilename()) + "Help" + #PS$ + "TexConverter-Help.html", #PB_MessageRequester_Warning)
    ProcedureReturn
  EndIf
  ; Elk besturingssysteem heeft een eigen opdracht om een bestand met het standaardprogramma te openen
  CompilerSelect #PB_Compiler_OS
    CompilerCase #PB_OS_Windows
      RunProgram(file)
    CompilerCase #PB_OS_Linux
      RunProgram("xdg-open", #DQUOTE$ + file + #DQUOTE$, "")
    CompilerCase #PB_OS_MacOS
      RunProgram("open", #DQUOTE$ + file + #DQUOTE$, "")
  CompilerEndSelect
EndProcedure

; Het About-venster. Het plaatje zit IN het programma (IncludeBinary, zie de DataSection onderaan),
; zodat het .exe-bestand geen los TexConverter.png nodig heeft. CatchImage() maakt er een image van.
Procedure ShowAbout()
  Protected win.i, logo.i, font.i, title.i, bClose.i, event.i, done.i, os.s, cpu.s, fontName.s

  UsePNGImageDecoder()
  logo = CatchImage(#PB_Any, ?AboutLogo, ?AboutLogoEnd - ?AboutLogo)

  ; Voor welk systeem is dit programma gemaakt? (Komt uit de compiler, dus klopt ook op Linux.)
  CompilerSelect #PB_Compiler_OS
    CompilerCase #PB_OS_Windows : os = "Windows" : fontName = "Segoe UI"
    CompilerCase #PB_OS_Linux   : os = "Linux"   : fontName = "Sans"
    CompilerDefault             : os = "macOS"   : fontName = "Helvetica"
  CompilerEndSelect
  CompilerSelect #PB_Compiler_Processor
    CompilerCase #PB_Processor_x64 : cpu = "-x64"
    CompilerCase #PB_Processor_x86 : cpu = "-x86"
    CompilerDefault                : cpu = ""
  CompilerEndSelect

  win = OpenWindow(#PB_Any, 0, 0, 600, 300, "About", #PB_Window_SystemMenu | #PB_Window_WindowCentered, WindowID(Window_0))
  If win = 0 : ProcedureReturn : EndIf
  If logo
    ImageGadget(#PB_Any, 16, 16, 256, 256, ImageID(logo))
  EndIf
  title = TextGadget(#PB_Any, 290, 24, 300, 46, "Serious Sam Engine 1 texture converter 1.00")
  font = LoadFont(#PB_Any, fontName, 12, #PB_Font_Bold)
  If font : SetGadgetFont(title, FontID(font)) : EndIf
  TextGadget(#PB_Any, 290, 80, 300, 20, "TheySoft 2026")
  TextGadget(#PB_Any, 290, 120, 300, 20, "Lead Concept & Design: Thei van Duin")
  TextGadget(#PB_Any, 290, 142, 300, 20, "Lead Programmer & Debugger: Claude Opus")
  TextGadget(#PB_Any, 290, 182, 300, 20, "Created using:")
  ; #PB_Compiler_Version is bijv. 641; dat wordt "6.41"
  TextGadget(#PB_Any, 290, 204, 300, 20, "PureBasic " + Str(#PB_Compiler_Version / 100) + "." + RSet(Str(#PB_Compiler_Version % 100), 2, "0") + " (" + os + cpu + ")")
  bClose = ButtonGadget(#PB_Any, 490, 256, 94, 28, "Close", #PB_Button_Default)
  AddKeyboardShortcut(win, #PB_Shortcut_Escape, 1)
  AddKeyboardShortcut(win, #PB_Shortcut_Return, 1)
  DisableWindow(Window_0, #True)

  Repeat
    event = WaitWindowEvent()
    If EventWindow() <> win : Continue : EndIf
    Select event
      Case #PB_Event_CloseWindow : done = #True
      Case #PB_Event_Menu        : done = #True
      Case #PB_Event_Gadget
        If EventGadget() = bClose : done = #True : EndIf
    EndSelect
  Until done

  DisableWindow(Window_0, #False)
  CloseWindow(win)
  If logo : FreeImage(logo) : EndIf
  If font : FreeFont(font) : EndIf
  SetActiveWindow(Window_0)
EndProcedure

; Kijkt of er bij het opslaan in dit formaat iets verloren gaat, en vraagt dan of je wilt doorgaan.
; Geeft #True terug als er niets verloren gaat of als je "Yes" kiest.
Procedure.i ConfirmDataLoss(Ext.s)
  Protected loss.s, formatName.s

  If Not PREF_WarnDataLoss            ; uitgezet in Preferences > Warnings
    ProcedureReturn #True
  EndIf

  Select Ext
    Case "jpg", "jpeg" : formatName = "JPG"
    Case "pcx"         : formatName = "PCX"
    Case "tex"         : formatName = "Serious Sam 1 .tex"
    Default            : formatName = UCase(Ext)
  EndSelect

  ; 1. HDR: alleen .hdr bewaart alle helderheid; andere formaten krijgen het plaatje zoals op het scherm
  If CurrentInfo\IsHDR And Ext <> "hdr"
    loss + "- HDR brightness: " + formatName + " stores the image as shown (exposure " + StrD(TEXSE3_ExposureEV, 1) + " EV"
    If TEXSE3_ToneMode = #TEXSE3_ToneFilmic
      loss + ", filmic"
    Else
      loss + ", editor clip"
    EndIf
    loss + "). Brightness beyond white is lost; use .hdr to keep it." + #LF$
  EndIf

  ; 2. Transparantie: PCX, JPG en BMP (zoals wij die opslaan) hebben geen alfakanaal
  If CurrentInfo\HasAlpha And (formatName = "PCX" Or formatName = "JPG" Or formatName = "BMP")
    loss + "- Transparency: " + formatName + " has no alpha channel." + #LF$
  EndIf

  ; 3. SE1 werkt met maten die een macht van 2 zijn (64, 128, 256, ...)
  If Ext = "tex" And (Not TEXW_IsPowerOf2(CurrentInfo\Width) Or Not TEXW_IsPowerOf2(CurrentInfo\Height))
    loss + "- Size: " + Str(CurrentInfo\Width) + " x " + Str(CurrentInfo\Height) + " is not a power of 2; Serious Sam 1 may not show it correctly." + #LF$
  EndIf

  ; 4. Levels met clipping: waarden die naar puur zwart of wit zijn geduwd, komen niet meer terug
  If ClippedInEdits() > 0
    loss + "- Clipping: your adjustments pushed " + Str(ClippedInEdits()) + " values to pure black or white." + #LF$
  EndIf

  ; 5. JPG pakt in met verlies: kleine details en scherpe randen veranderen een beetje
  If formatName = "JPG"
    loss + "- Image detail: JPG compression slightly changes the image (lossy)." + #LF$
  EndIf

  If loss = ""
    ProcedureReturn #True
  EndIf
  ProcedureReturn Bool(MessageRequester(AppTitle, "Saving as " + formatName + " loses information:" + #LF$ + #LF$ + loss + #LF$ + "Save anyway?", #PB_MessageRequester_YesNo | #PB_MessageRequester_Warning) = #PB_MessageRequester_Yes)
EndProcedure

; Slaat CurrentImage op; het formaat volgt uit de extensie.
; Ask = #True: eerst waarschuwen als er informatie verloren gaat (Save As). Bij opnieuw opslaan
; naar hetzelfde bestand (Ctrl+S) is dat al eens gevraagd, dan Ask = #False.
Procedure SaveCurrent(file.s, Ask.i = #True)
  Protected ok.i, withAlpha.i, flat.i

  withAlpha = CurrentInfo\HasAlpha

  ; Eerst de maat controleren bij Serious Sam 1 (kan het plaatje verkleinen)
  If LCase(GetExtensionPart(file)) = "tex" And Not CheckSE1Size()
    ProcedureReturn
  EndIf

  If Ask And Not ConfirmDataLoss(LCase(GetExtensionPart(file)))
    ProcedureReturn
  EndIf

  Select LCase(GetExtensionPart(file))
    Case "bmp"
      ; Een gewone BMP heeft geen transparantie. 32-bit BMP met alfa bestaat wel, maar de meeste
      ; programma's (ook editors) negeren die vierde byte. Daarom altijd 24-bit, met waarschuwing.
      ok = SaveImage(CurrentImage, file, #PB_ImagePlugin_BMP, 0, 24)
    Case "tif", "tiff"
      ok = TIFF_Save(CurrentImage, file, withAlpha)
    Case "jpg", "jpeg"
      ; JPG heeft geen alfa: eerst een kopie zonder alfa maken (de kleuren onder doorzichtige
      ; delen blijven zichtbaar, net als bij PCX). Kwaliteit 9 van 10: weinig zichtbaar verlies.
      flat = CreateImage(#PB_Any, ImageWidth(CurrentImage), ImageHeight(CurrentImage), 24)
      If flat And StartDrawing(ImageOutput(flat))
        DrawImage(ImageID(CurrentImage), 0, 0)
        StopDrawing()
        ok = SaveImage(flat, file, #PB_ImagePlugin_JPEG, 9)
      EndIf
      If flat : FreeImage(flat) : EndIf
    Case "hdr"
      ; De originele HDR-waarden, dus zonder de belichting van het scherm
      If CurrentInfo\IsHDR
        ok = HDR_Save(CurrentInfo\HdrData, CurrentInfo\Width, CurrentInfo\Height, file)
      Else
        MessageRequester(AppTitle, "Only HDR textures can be saved as .hdr.", #PB_MessageRequester_Error)
        ProcedureReturn
      EndIf
    Case "tga"
      ok = TGA_Save(CurrentImage, file, withAlpha)
    Case "pcx"
      ok = PCX_Save(CurrentImage, file)       ; 24-bit, zonder transparantie
    Case "dds"
      ; Formaat kiezen (bij Ctrl+S het vorige formaat opnieuw gebruiken)
      If Ask Or LastDDSFormat < 0
        If Not DDS_Dialog(Window_0, withAlpha, Bool(FindString(LCase(CurrentInfo\FormatName), "normal")), @LastDDSFormat, @LastDDSMips)
          ProcedureReturn
        EndIf
        If Ask And PREF_WarnDataLoss And withAlpha And (LastDDSFormat = #DDS_DXT1 Or LastDDSFormat = #DDS_BC5)
          If MessageRequester(AppTitle, "This DDS format has no alpha channel; the transparency will be lost." + #LF$ + "Save anyway?", #PB_MessageRequester_YesNo | #PB_MessageRequester_Warning) <> #PB_MessageRequester_Yes
            ProcedureReturn
          EndIf
        EndIf
      EndIf
      ok = DDS_Save(CurrentImage, file, LastDDSFormat, LastDDSMips)
    Case "tex"
      ; Serious Sam 1-texture. Komt het plaatje zelf uit SE1, dan dezelfde firstMip (en dus
      ; dezelfde grootte in het spel); anders 0, dan is de mex-maat gelijk aan de pixelmaat.
      If CurrentInfo\Engine = 1 And CurrentInfo\Version = 4 And Not CurrentInfo\IsEffect
        ok = TEXW_SaveSE1(CurrentImage, file, withAlpha, CurrentInfo\FirstMip, Bool(CurrentInfo\Flags & #TEX_32BIT))
      Else
        ok = TEXW_SaveSE1(CurrentImage, file, withAlpha, 0)
      EndIf
    Default
      If withAlpha
        ok = SaveImage(CurrentImage, file, #PB_ImagePlugin_PNG, 0, 32)
      Else
        ok = SaveImage(CurrentImage, file, #PB_ImagePlugin_PNG, 0, 24)
      EndIf
  EndSelect

  If ok
    SavedFile = file
    StatusBarText(#Statusbar, 2, "Saved: " + GetFilePart(file))
    EH_MarkSaved()
    UpdateEditUI()
    LastSaveDir = GetPathPart(file)
    SET_Write("LastSaveFolder", LastSaveDir)
  Else
    MessageRequester(AppTitle, "Saving failed:" + #LF$ + file, #PB_MessageRequester_Error)
  EndIf
EndProcedure

Procedure SaveAs()
  Protected file.s, suggestion.s, ext.s, pattern.s, i.i

  If CurrentImage = 0
    MessageRequester(AppTitle, "Please open a .tex file first.")
    ProcedureReturn
  EndIf

  ; Voorstel: zelfde naam als het bestand, zonder extensie, in de laatste opslagmap. De extensie komt
  ; hieronder van het gekozen type, zodat bijv. "Microsoft BMP" ook echt een .bmp oplevert.
  ; De opslagmap wordt apart van de openmap onthouden. Nog nooit opgeslagen: naast het bronbestand
  ; (maar niet naast een .gro-archief, dat staat vaak in Program Files).
  If PREF_SaveSourceFolder And Not GRO_IsGroPath(CurrentFile)
    suggestion = GetPathPart(CurrentFile)          ; Preferences: altijd de map van het bronbestand
  ElseIf LastSaveDir <> ""
    suggestion = LastSaveDir
  ElseIf Not GRO_IsGroPath(CurrentFile)
    suggestion = GetPathPart(CurrentFile)
  EndIf
  suggestion + GetFilePart(DisplayName(CurrentFile), #PB_FileSystem_NoExtension) + NameSuffix
  ; De volgorde hier moet gelijk zijn aan de lijst met extensies hieronder
  pattern = "Truevision Graphics Adapter (*.tga)|*.tga|"
  pattern = pattern + "Portable Network Graphics (*.png)|*.png|"
  pattern = pattern + "PiCture eXchange (*.pcx)|*.pcx|"
  pattern = pattern + "Microsoft BMP (*.bmp)|*.bmp|"
  pattern = pattern + "Tagged Image File Format (*.tif)|*.tif;*.tiff|"
  pattern = pattern + "Joint Photographic Experts Group (*.jpg)|*.jpg;*.jpeg|"
  pattern = pattern + "DirectDraw Surface (*.dds)|*.dds|"
  pattern = pattern + "Serious Sam 1 texture (*.tex)|*.tex"
  If CurrentInfo\IsHDR
    pattern = pattern + "|Radiance High Dynamic Range (*.hdr)|*.hdr"
  EndIf
  ; Laatste getal = welk type vooraf gekozen is (Preferences; standaard 0 = TGA, dat leest Serious Editor)
  file = SaveFileRequester("Save As", suggestion, pattern, PREF_SaveFormat)
  If file = ""
    ProcedureReturn
  EndIf

  ; Extensie toevoegen als de gebruiker die niet zelf heeft getypt
  ext = LCase(GetExtensionPart(file))
  If FindString(",png,tga,bmp,tif,tiff,jpg,jpeg,pcx,dds,tex,hdr,", "," + ext + ",") = 0 Or ext = ""
    ; Extensie van het gekozen type in de lijst (0 = png, 1 = tga, ...)
    i = SelectedFilePattern()
    If i < 0 : i = PREF_SaveFormat : EndIf   ; onbekend: dan het standaardtype uit Preferences
    file + "." + StringField("tga,png,pcx,bmp,tif,jpg,dds,tex,hdr", i + 1, ",")
  EndIf

  If FileSize(file) >= 0
    If MessageRequester(AppTitle, GetFilePart(file) + " already exists. Overwrite?", #PB_MessageRequester_YesNo) <> #PB_MessageRequester_Yes
      ProcedureReturn
    EndIf
  EndIf

  SaveCurrent(file)
EndProcedure

Procedure Save()
  If SavedFile <> ""
    SaveCurrent(SavedFile, #False)   ; al eerder opgeslagen (en gewaarschuwd): opnieuw naar hetzelfde bestand
  Else
    SaveAs()
  EndIf
EndProcedure

; ---------------------------------------------------------------------------------------------
; Instellingen van de vorige keer (Settings.pbi) en de voorkeuren (Preferences.pbi)
; ---------------------------------------------------------------------------------------------

; Ligt het punt (x, y) op een van de schermen? (Een tweede scherm kan inmiddels weg zijn.)
Procedure.i OnDesktop(x.i, y.i)
  Protected i.i, n.i = ExamineDesktops()
  For i = 0 To n - 1
    If x >= DesktopUnscaledX(DesktopX(i)) And x < DesktopUnscaledX(DesktopX(i) + DesktopWidth(i)) And y >= DesktopUnscaledY(DesktopY(i)) And y < DesktopUnscaledY(DesktopY(i) + DesktopHeight(i))
      ProcedureReturn #True
    EndIf
  Next
  ProcedureReturn #False
EndProcedure

Procedure LoadStartSettings()
  Protected x.i, y.i, w.i, h.i
  PREF_Load()
  EH_MaxStates = PREF_UndoSteps
  ; Laatste mappen (bestaat een map niet meer, dan blijft het leeg)
  LastDir = SET_ReadFolder("LastOpenFolder")
  LastSaveDir = SET_ReadFolder("LastSaveFolder")
  ; HDR: vaste waarden uit Preferences, of zoals de vorige keer
  If PREF_HdrFixed
    TEXSE3_ExposureEV = PREF_HdrExposure
    TEXSE3_ToneMode = PREF_HdrTone
  Else
    TEXSE3_ExposureEV = SET_ReadDouble("LastHdrExposure", #TEXSE3_DefaultExposureEV)
    TEXSE3_ToneMode = PREF_Limit(SET_ReadInt("LastHdrTone", #TEXSE3_ToneClip), 0, 1)
  EndIf
  ; DDS-keuze van de vorige keer (geldt voor Ctrl+S; Save As vraagt het opnieuw)
  LastDDSFormat = SET_ReadInt("LastDDSFormat", -1)
  LastDDSMips = Bool(SET_ReadInt("LastDDSMips", #True))
  ; Positie en grootte van het venster
  If PREF_RememberWindow
    x = SET_ReadInt("WindowX", -100000) : y = SET_ReadInt("WindowY", -100000)
    w = SET_ReadInt("WindowWidth", 0) : h = SET_ReadInt("WindowHeight", 0)
    If w >= 300 And h >= 200 And OnDesktop(x + 40, y + 20)
      default_X = x : default_Y = y : default_W = w : default_H = h
      StartCentered = 0
    EndIf
    StartMaximized = Bool(SET_ReadInt("WindowMaximized", 0))
  EndIf
EndProcedure

; Bij het afsluiten: bewaren wat de volgende keer weer zo moet zijn.
Procedure SaveEndSettings()
  SET_WriteDouble("LastHdrExposure", TEXSE3_ExposureEV)
  SET_WriteInt("LastHdrTone", TEXSE3_ToneMode)
  SET_WriteInt("LastDDSFormat", LastDDSFormat)
  SET_WriteInt("LastDDSMips", LastDDSMips)
  If PREF_RememberWindow
    SET_WriteInt("WindowMaximized", Bool(GetWindowState(Window_0) = #PB_Window_Maximize))
    ; Positie alleen bewaren als het venster normaal is (niet gemaximaliseerd of geminimaliseerd)
    If GetWindowState(Window_0) = #PB_Window_Normal
      SET_WriteInt("WindowX", WindowX(Window_0)) : SET_WriteInt("WindowY", WindowY(Window_0))
      SET_WriteInt("WindowWidth", WindowWidth(Window_0)) : SET_WriteInt("WindowHeight", WindowHeight(Window_0))
    EndIf
  EndIf
EndProcedure

LoadStartSettings()
OpenWindow_0()
If StartMaximized : SetWindowState(Window_0, #PB_Window_Maximize) : EndIf
SetMenuItemState(0, #Menu_ToneClip, Bool(TEXSE3_ToneMode = #TEXSE3_ToneClip))
SetMenuItemState(0, #Menu_ToneFilmic, Bool(TEXSE3_ToneMode = #TEXSE3_ToneFilmic))
WindowResizing()
UpdateEditUI()                  ; Undo/Redo staan uit zolang er niets geladen is



Global Event, WindowID, GadgetID, Event_Type, Quit.i
Repeat
  Event = WaitWindowEvent()
  WindowID = EventWindow()
  GadgetID = EventGadget()
  Event_Type = EventType()

  Select Event
    Case #PB_Event_CloseWindow
      If EventWindow() = Window_0 And ConfirmDiscard()   ; niet-opgeslagen bewerkingen? eerst vragen
        Quit = 1
      EndIf
    Case #PB_Event_Menu
      Select EventMenu()
        Case #Menu_Open
          OpenTex()
        Case #Menu_Save
          Save()
        Case #Menu_SaveAs
          SaveAs()
        Case #Menu_Quit
          If ConfirmDiscard() : Quit = 1 : EndIf
        Case #Menu_ExposureUp
          ChangeExposure(1)
        Case #Menu_ExposureDown
          ChangeExposure(-1)
        Case #Menu_ExposureReset
          ChangeExposure(0, #True)
        Case #Menu_ToneClip
          SetToneMode(#TEXSE3_ToneClip)
        Case #Menu_ToneFilmic
          SetToneMode(#TEXSE3_ToneFilmic)
        Case #Menu_NmFlipGreen To #Menu_NmFromHeight
          NormalMapCommand(EventMenu())
        Case #Menu_ChRed To #Menu_ChInvertAlpha
          ChannelCommand(EventMenu())
        Case #Menu_Undo
          If EH_CanUndo() : ApplyState(EH_Undo()) : EndIf
        Case #Menu_Redo
          If EH_CanRedo() : ApplyState(EH_Redo()) : EndIf
        Case #Menu_Levels
          LevelsCommand()
        Case #Menu_AutoLevels
          AutoLevelsCommand()
        Case #Menu_Revert
          If EH_CanUndo() : ApplyState(EH_Original()) : EndIf
        Case #Menu_Help
          OpenHelpFile()
        Case #Menu_About
          ShowAbout()
        Case #Menu_Preferences
          If PREF_Dialog(Window_0)
            EH_MaxStates = PREF_UndoSteps
            ShowImage()                 ; achtergrond kan veranderd zijn
          EndIf
        Case #Menu_Batch
          BAT_Open(Window_0, LastDir)
        Case #Menu_Skybox
          SkyboxWindow()
        Case #Menu_Resize
          ResizeDialog()
        Case #Menu_OpenGro
          OpenFromGro()
        Case #Menu_Histogram
          If CurrentImage
            Histogram_Open(CurrentImage, @CurrentInfo, TEXSE3_ExposureEV, WindowID(Window_0))
          Else
            MessageRequester(AppTitle, "Please open a .tex file first.")
          EndIf
        Case #Menu_ToneToggle
          SetToneMode(1 - TEXSE3_ToneMode)   ; wisselen tussen 0 (clip) en 1 (filmic)
      EndSelect
    Case #PB_Event_SizeWindow
      WindowResizing()
  EndSelect

Until Quit = 1
SaveEndSettings()

; Bestanden die in het programma zelf worden meegenomen
DataSection
  AboutLogo:
  IncludeBinary "TexConverter.png"   ; logo voor het About-venster
  AboutLogoEnd:
EndDataSection

; IDE Options = PureBasic 6.41 (Windows - x64)
; CursorPosition = 392
; FirstLine = 383
; Folding = ------
; EnableXP
; DPIAware
; UseIcon = converter.ico
; Executable = SS1TexConverter.exe
; IncludeVersionInfo
; VersionField0 = 1.0.0.0
; VersionField1 = 1.0.0.0
; VersionField2 = TheySoft
; VersionField3 = SS1TexConverter
; VersionField4 = 1.00
; VersionField5 = 1.00
; VersionField6 = Serious Sam Engine 1 texture converter
; VersionField7 = SS1TexConverter.exe
; VersionField8 = SS1TexConverter.exe