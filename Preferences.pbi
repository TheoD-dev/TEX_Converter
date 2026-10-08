; Preferences.pbi - voorkeuren van de gebruiker (menu Tools > Preferences)
;
; Alle voorkeuren staan in globale variabelen PREF_... zodat elk deel van het programma ze kan
; lezen. Ze worden bewaard in het instellingenbestand van Settings.pbi (sleutels "Pref...").
; Dit bestand moet dus na Settings.pbi worden ingevoegd.

; Achtergrond achter transparante delen
Enumeration
  #PREF_BgChecker
  #PREF_BgBlack
  #PREF_BgGray
  #PREF_BgWhite
EndEnumeration

; General
Global PREF_RememberWindow.i     ; positie en grootte van het hoofdvenster onthouden
Global PREF_Background.i         ; #PREF_Bg...
Global PREF_UndoSteps.i          ; hoeveel toestanden Undo bewaart (incl. het origineel)
Global PREF_NmStrength.d         ; standaardsterkte bij "Create from height map"
Global PREF_HdrFixed.i           ; #False = HDR-belichting en tone zoals de vorige keer, #True = vaste waarden
Global PREF_HdrExposure.d        ; vaste belichting bij het starten (EV)
Global PREF_HdrTone.i            ; vaste tone bij het starten: 0 = Editor (clip), 1 = Filmic
; Saving
Global PREF_SaveFormat.i         ; standaardtype bij Save As: 0 = tga, 1 = png, 2 = pcx, 3 = bmp, 4 = tif, 5 = jpg, 6 = dds, 7 = tex
Global PREF_SaveSourceFolder.i   ; #True = Save As stelt altijd de map van het bronbestand voor
; Warnings
Global PREF_WarnDataLoss.i       ; waarschuwen als er bij opslaan informatie verloren gaat
Global PREF_WarnSE1Size.i        ; Serious Sam 1: aanbieden te verkleinen boven 1024 pixels
Global PREF_WarnClipping.i       ; Levels: vragen voordat een bewerking met clipping wordt toegepast

#PREF_SaveFormats = "tga,png,pcx,bmp,tif,jpg,dds,tex"

; Zet alle voorkeuren op de standaardwaarden.
Procedure PREF_Defaults()
  PREF_RememberWindow = #True
  PREF_Background = #PREF_BgChecker
  PREF_UndoSteps = 30
  PREF_NmStrength = 2.0
  PREF_HdrFixed = #False
  PREF_HdrExposure = 0.0
  PREF_HdrTone = 0
  PREF_SaveFormat = 0
  PREF_SaveSourceFolder = #False
  PREF_WarnDataLoss = #True
  PREF_WarnSE1Size = #True
  PREF_WarnClipping = #True
EndProcedure

; Houdt een getal binnen grenzen (voor waarden uit het bestand die iemand met de hand veranderd heeft).
Procedure.i PREF_Limit(Value.i, Low.i, High.i)
  If Value < Low : ProcedureReturn Low : EndIf
  If Value > High : ProcedureReturn High : EndIf
  ProcedureReturn Value
EndProcedure

Procedure PREF_Load()
  PREF_Defaults()
  PREF_RememberWindow   = Bool(SET_ReadInt("PrefRememberWindow", PREF_RememberWindow))
  PREF_Background       = PREF_Limit(SET_ReadInt("PrefBackground", PREF_Background), 0, 3)
  PREF_UndoSteps        = PREF_Limit(SET_ReadInt("PrefUndoSteps", PREF_UndoSteps), 2, 200)
  PREF_NmStrength       = SET_ReadDouble("PrefNormalStrength", PREF_NmStrength)
  If PREF_NmStrength <= 0 : PREF_NmStrength = 2.0 : EndIf
  PREF_HdrFixed         = Bool(SET_ReadInt("PrefHdrFixed", PREF_HdrFixed))
  PREF_HdrExposure      = SET_ReadDouble("PrefHdrExposure", PREF_HdrExposure)
  PREF_HdrTone          = PREF_Limit(SET_ReadInt("PrefHdrTone", PREF_HdrTone), 0, 1)
  PREF_SaveFormat       = PREF_Limit(SET_ReadInt("PrefSaveFormat", PREF_SaveFormat), 0, 7)
  PREF_SaveSourceFolder = Bool(SET_ReadInt("PrefSaveSourceFolder", PREF_SaveSourceFolder))
  PREF_WarnDataLoss     = Bool(SET_ReadInt("PrefWarnDataLoss", PREF_WarnDataLoss))
  PREF_WarnSE1Size      = Bool(SET_ReadInt("PrefWarnSE1Size", PREF_WarnSE1Size))
  PREF_WarnClipping     = Bool(SET_ReadInt("PrefWarnClipping", PREF_WarnClipping))
EndProcedure

Procedure PREF_Save()
  SET_WriteInt("PrefRememberWindow", PREF_RememberWindow)
  SET_WriteInt("PrefBackground", PREF_Background)
  SET_WriteInt("PrefUndoSteps", PREF_UndoSteps)
  SET_WriteDouble("PrefNormalStrength", PREF_NmStrength)
  SET_WriteInt("PrefHdrFixed", PREF_HdrFixed)
  SET_WriteDouble("PrefHdrExposure", PREF_HdrExposure)
  SET_WriteInt("PrefHdrTone", PREF_HdrTone)
  SET_WriteInt("PrefSaveFormat", PREF_SaveFormat)
  SET_WriteInt("PrefSaveSourceFolder", PREF_SaveSourceFolder)
  SET_WriteInt("PrefWarnDataLoss", PREF_WarnDataLoss)
  SET_WriteInt("PrefWarnSE1Size", PREF_WarnSE1Size)
  SET_WriteInt("PrefWarnClipping", PREF_WarnClipping)
EndProcedure

; ---------------------------------------------------------------------------------------------
; Het venster Preferences
; ---------------------------------------------------------------------------------------------
Global PREF_gRemember.i, PREF_gBackground.i, PREF_gUndo.i, PREF_gStrength.i
Global PREF_gHdrLast.i, PREF_gHdrFixed.i, PREF_gHdrExp.i, PREF_gHdrTone.i
Global PREF_gFormat.i, PREF_gFolderLast.i, PREF_gFolderSource.i
Global PREF_gWarnLoss.i, PREF_gWarnSE1.i, PREF_gWarnClip.i

; Zet de waarden van de globale variabelen in de gadgets.
Procedure PREF_ToGadgets()
  SetGadgetState(PREF_gRemember, PREF_RememberWindow)
  SetGadgetState(PREF_gBackground, PREF_Background)
  SetGadgetState(PREF_gUndo, PREF_UndoSteps) : SetGadgetText(PREF_gUndo, Str(PREF_UndoSteps))
  SetGadgetText(PREF_gStrength, StrD(PREF_NmStrength, 1))
  SetGadgetState(PREF_gHdrLast, Bool(Not PREF_HdrFixed))
  SetGadgetState(PREF_gHdrFixed, PREF_HdrFixed)
  SetGadgetText(PREF_gHdrExp, StrD(PREF_HdrExposure, 1))
  SetGadgetState(PREF_gHdrTone, PREF_HdrTone)
  DisableGadget(PREF_gHdrExp, Bool(Not PREF_HdrFixed))
  DisableGadget(PREF_gHdrTone, Bool(Not PREF_HdrFixed))
  SetGadgetState(PREF_gFormat, PREF_SaveFormat)
  SetGadgetState(PREF_gFolderLast, Bool(Not PREF_SaveSourceFolder))
  SetGadgetState(PREF_gFolderSource, PREF_SaveSourceFolder)
  SetGadgetState(PREF_gWarnLoss, PREF_WarnDataLoss)
  SetGadgetState(PREF_gWarnSE1, PREF_WarnSE1Size)
  SetGadgetState(PREF_gWarnClip, PREF_WarnClipping)
EndProcedure

; Leest de gadgets. Geeft een foutmelding (en #False) bij een ongeldig getal.
Procedure.i PREF_FromGadgets()
  Protected strength.d = ValD(ReplaceString(GetGadgetText(PREF_gStrength), ",", "."))
  If strength <= 0 Or strength > 50
    MessageRequester("Preferences", "The normal map strength must be a number between 0 and 50.", #PB_MessageRequester_Error)
    ProcedureReturn #False
  EndIf
  PREF_RememberWindow = GetGadgetState(PREF_gRemember)
  PREF_Background = GetGadgetState(PREF_gBackground)
  PREF_UndoSteps = PREF_Limit(Val(GetGadgetText(PREF_gUndo)), 2, 200)
  PREF_NmStrength = strength
  PREF_HdrFixed = GetGadgetState(PREF_gHdrFixed)
  PREF_HdrExposure = ValD(ReplaceString(GetGadgetText(PREF_gHdrExp), ",", "."))
  PREF_HdrTone = GetGadgetState(PREF_gHdrTone)
  PREF_SaveFormat = GetGadgetState(PREF_gFormat)
  PREF_SaveSourceFolder = GetGadgetState(PREF_gFolderSource)
  PREF_WarnDataLoss = GetGadgetState(PREF_gWarnLoss)
  PREF_WarnSE1Size = GetGadgetState(PREF_gWarnSE1)
  PREF_WarnClipping = GetGadgetState(PREF_gWarnClip)
  ProcedureReturn #True
EndProcedure

; Opent het venster. Bij OK worden de voorkeuren bewaard en is het resultaat #True.
Procedure.i PREF_Dialog(ParentWindow.i)
  Protected win.i, panel.i, bOK.i, bCancel.i, bDefaults.i, event.i, done.i, result.i

  win = OpenWindow(#PB_Any, 0, 0, 500, 360, "Preferences", #PB_Window_SystemMenu | #PB_Window_WindowCentered, WindowID(ParentWindow))
  If win = 0 : ProcedureReturn #False : EndIf
  panel = PanelGadget(#PB_Any, 8, 8, 484, 300)

  AddGadgetItem(panel, -1, "General")
  PREF_gRemember = CheckBoxGadget(#PB_Any, 10, 12, 450, 22, "Remember the window position and size")
  TextGadget(#PB_Any, 10, 48, 230, 20, "Background behind transparent areas:")
  PREF_gBackground = ComboBoxGadget(#PB_Any, 250, 44, 160, 24)
  AddGadgetItem(PREF_gBackground, -1, "Checkerboard")
  AddGadgetItem(PREF_gBackground, -1, "Black")
  AddGadgetItem(PREF_gBackground, -1, "Gray")
  AddGadgetItem(PREF_gBackground, -1, "White")
  TextGadget(#PB_Any, 10, 82, 230, 20, "Undo steps (more uses more memory):")
  PREF_gUndo = SpinGadget(#PB_Any, 250, 78, 80, 24, 2, 200, #PB_Spin_Numeric)
  TextGadget(#PB_Any, 10, 116, 230, 20, "Normal map from height map, strength:")
  PREF_gStrength = StringGadget(#PB_Any, 250, 112, 80, 24, "")
  FrameGadget(#PB_Any, 10, 150, 456, 106, "HDR textures when the program starts")
  PREF_gHdrLast  = OptionGadget(#PB_Any, 22, 172, 430, 22, "Same exposure and tone as last time")
  PREF_gHdrFixed = OptionGadget(#PB_Any, 22, 198, 100, 22, "Always:")
  TextGadget(#PB_Any, 130, 202, 70, 20, "Exposure (EV)")
  PREF_gHdrExp = StringGadget(#PB_Any, 210, 198, 60, 24, "")
  TextGadget(#PB_Any, 290, 202, 40, 20, "Tone")
  PREF_gHdrTone = ComboBoxGadget(#PB_Any, 330, 198, 126, 24)
  AddGadgetItem(PREF_gHdrTone, -1, "Editor (clip)")
  AddGadgetItem(PREF_gHdrTone, -1, "Filmic")

  AddGadgetItem(panel, -1, "Saving")
  TextGadget(#PB_Any, 10, 16, 180, 20, "Default format for Save As:")
  PREF_gFormat = ComboBoxGadget(#PB_Any, 190, 12, 270, 24)
  AddGadgetItem(PREF_gFormat, -1, "Truevision Graphics Adapter (*.tga)")
  AddGadgetItem(PREF_gFormat, -1, "Portable Network Graphics (*.png)")
  AddGadgetItem(PREF_gFormat, -1, "PiCture eXchange (*.pcx)")
  AddGadgetItem(PREF_gFormat, -1, "Microsoft BMP (*.bmp)")
  AddGadgetItem(PREF_gFormat, -1, "Tagged Image File Format (*.tif)")
  AddGadgetItem(PREF_gFormat, -1, "Joint Photographic Experts Group (*.jpg)")
  AddGadgetItem(PREF_gFormat, -1, "DirectDraw Surface (*.dds)")
  AddGadgetItem(PREF_gFormat, -1, "Serious Sam 1 texture (*.tex)")
  FrameGadget(#PB_Any, 10, 52, 456, 80, "Save As suggests")
  PREF_gFolderLast   = OptionGadget(#PB_Any, 22, 74, 430, 22, "The folder where you last saved")
  PREF_gFolderSource = OptionGadget(#PB_Any, 22, 100, 430, 22, "The folder of the source file")

  AddGadgetItem(panel, -1, "Warnings")
  PREF_gWarnLoss = CheckBoxGadget(#PB_Any, 10, 12, 450, 22, "Warn when saving loses information (HDR, transparency, clipping, JPG)")
  PREF_gWarnSE1  = CheckBoxGadget(#PB_Any, 10, 40, 450, 22, "Serious Sam 1 .tex: offer to resize textures larger than 1024 pixels")
  PREF_gWarnClip = CheckBoxGadget(#PB_Any, 10, 68, 450, 22, "Levels: ask before applying an adjustment that clips")
  CloseGadgetList()

  bDefaults = ButtonGadget(#PB_Any, 8, 320, 100, 28, "Defaults")
  bOK       = ButtonGadget(#PB_Any, 296, 320, 94, 28, "OK", #PB_Button_Default)
  bCancel   = ButtonGadget(#PB_Any, 398, 320, 94, 28, "Cancel")
  AddKeyboardShortcut(win, #PB_Shortcut_Escape, 1)
  PREF_ToGadgets()
  DisableWindow(ParentWindow, #True)

  Repeat
    event = WaitWindowEvent()
    If EventWindow() <> win : Continue : EndIf
    Select event
      Case #PB_Event_CloseWindow
        done = #True
      Case #PB_Event_Menu
        If EventMenu() = 1 : done = #True : EndIf
      Case #PB_Event_Gadget
        Select EventGadget()
          Case PREF_gHdrLast, PREF_gHdrFixed
            DisableGadget(PREF_gHdrExp, Bool(Not GetGadgetState(PREF_gHdrFixed)))
            DisableGadget(PREF_gHdrTone, Bool(Not GetGadgetState(PREF_gHdrFixed)))
          Case bDefaults
            ; Alleen de gadgets terugzetten; pas bij OK wordt het echt bewaard
            PREF_Defaults() : PREF_ToGadgets()
            PREF_Load()                         ; variabelen terug zoals ze waren (voor Cancel)
          Case bOK
            If PREF_FromGadgets()
              PREF_Save()
              result = #True : done = #True
            EndIf
          Case bCancel
            done = #True
        EndSelect
    EndSelect
  Until done

  DisableWindow(ParentWindow, #False)
  CloseWindow(win)
  SetActiveWindow(ParentWindow)
  ProcedureReturn result
EndProcedure
