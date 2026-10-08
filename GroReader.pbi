; GroReader.pbi - .tex-bestanden kiezen en uitpakken uit een Serious Sam .gro-archief
;
; Een .gro is gewoon een zip-bestand met een andere extensie. PureBasic kan zip lezen met
; UseZipPacker() en de Pack-functies, dus dat werkt op Windows en Linux.
;
; GRO_ChooseTex() opent een venster met alle .tex-bestanden in het archief, met een zoekveld.
; GRO_Extract() pakt één bestand uit naar het geheugen; TEX_LoadMemory() maakt er een plaatje van.
;
; Een textuur uit een .gro wordt in de app aangeduid als "pad\naar\archief.gro::Content/.../naam.tex".

UseZipPacker()

#GRO_Separator = "::"          ; scheidt het archief van het bestand erin

Structure GroEntry
  Name.s                       ; volledige naam in het archief, bijv. Content/SeriousSam3/Textures/x.tex
  Size.i                       ; uitgepakte grootte in bytes
EndStructure

Global NewList GRO_Entries.GroEntry()
Global NewList GRO_Chosen.s()      ; bij meerdere tegelijk kiezen: alle gekozen namen

; Is dit een verwijzing naar een bestand in een .gro?
Procedure.i GRO_IsGroPath(Path.s)
  ProcedureReturn Bool(FindString(Path, #GRO_Separator) > 0)
EndProcedure

Procedure.s GRO_ArchivePart(Path.s)
  ProcedureReturn StringField(Path, 1, #GRO_Separator)
EndProcedure

Procedure.s GRO_EntryPart(Path.s)
  ProcedureReturn Mid(Path, FindString(Path, #GRO_Separator) + Len(#GRO_Separator))
EndProcedure

; Alleen de bestandsnaam van een naam in het archief (na de laatste /)
Procedure.s GRO_EntryFileName(Entry.s)
  Entry = ReplaceString(Entry, "\", "/")
  ProcedureReturn StringField(Entry, CountString(Entry, "/") + 1, "/")
EndProcedure

; Leest de lijst met .tex-bestanden uit een archief. Geeft het aantal terug, of -1 bij een fout.
Procedure.i GRO_ReadList(Archive.s)
  Protected pack.i
  ClearList(GRO_Entries())
  pack = OpenPack(#PB_Any, Archive, #PB_PackerPlugin_Zip)
  If pack = 0
    ProcedureReturn -1
  EndIf
  If ExaminePack(pack)
    While NextPackEntry(pack)
      If PackEntryType(pack) = #PB_Packer_File And LCase(GetExtensionPart(PackEntryName(pack))) = "tex"
        AddElement(GRO_Entries())
        GRO_Entries()\Name = PackEntryName(pack)
        GRO_Entries()\Size = PackEntrySize(pack)
      EndIf
    Wend
  EndIf
  ClosePack(pack)
  SortStructuredList(GRO_Entries(), #PB_Sort_Ascending | #PB_Sort_NoCase, OffsetOf(GroEntry\Name), TypeOf(GroEntry\Name))
  ProcedureReturn ListSize(GRO_Entries())
EndProcedure

; Pakt één bestand uit het archief uit naar nieuw geheugen. *Size krijgt de grootte.
; Geeft het geheugen terug (de aanroeper geeft het vrij met FreeMemory), of 0 bij een fout.
Procedure.i GRO_Extract(Archive.s, Entry.s, *Size.Integer)
  Protected pack.i, size.i, *mem
  pack = OpenPack(#PB_Any, Archive, #PB_PackerPlugin_Zip)
  If pack = 0
    ProcedureReturn 0
  EndIf
  ; Eerst de grootte opzoeken
  If ExaminePack(pack)
    While NextPackEntry(pack)
      If PackEntryName(pack) = Entry
        size = PackEntrySize(pack)
        Break
      EndIf
    Wend
  EndIf
  If size > 0
    *mem = AllocateMemory(size)
    If *mem And UncompressPackMemory(pack, *mem, size, Entry) <> size
      FreeMemory(*mem)
      *mem = 0
    EndIf
  EndIf
  ClosePack(pack)
  *Size\i = size
  ProcedureReturn *mem
EndProcedure

; Vult de lijst in het kiesvenster, alleen met namen waar Filter in voorkomt.
Procedure GRO_FillList(ListGadget.i, CountGadget.i, Filter.s)
  Protected shown.i, name.s, folder.s
  Filter = LCase(Trim(Filter))
  HideGadget(ListGadget, #True)            ; sneller vullen als hij even onzichtbaar is
  ClearGadgetItems(ListGadget)
  ForEach GRO_Entries()
    If Filter = "" Or FindString(LCase(GRO_Entries()\Name), Filter)
      name = GRO_EntryFileName(GRO_Entries()\Name)
      folder = Left(GRO_Entries()\Name, Len(GRO_Entries()\Name) - Len(name))
      AddGadgetItem(ListGadget, -1, name + #LF$ + Str((GRO_Entries()\Size + 1023) / 1024) + " KB" + #LF$ + folder)
      SetGadgetItemData(ListGadget, shown, ListIndex(GRO_Entries()))
      shown + 1
    EndIf
  Next
  HideGadget(ListGadget, #False)
  SetGadgetText(CountGadget, Str(shown) + " of " + Str(ListSize(GRO_Entries())) + " textures")
EndProcedure

; Zet alle geselecteerde regels van de lijst in GRO_Chosen() en geeft de eerste terug.
Procedure.s GRO_CollectSelected(ListGadget.i)
  Protected i.i, first.s
  ClearList(GRO_Chosen())
  For i = 0 To CountGadgetItems(ListGadget) - 1
    If GetGadgetItemState(ListGadget, i) & #PB_ListIcon_Selected
      SelectElement(GRO_Entries(), GetGadgetItemData(ListGadget, i))
      AddElement(GRO_Chosen())
      GRO_Chosen() = GRO_Entries()\Name
      If first = "" : first = GRO_Entries()\Name : EndIf
    EndIf
  Next
  ProcedureReturn first
EndProcedure
; Opent een venster om een .tex uit het archief te kiezen. Geeft de volledige naam in het
; archief terug, of "" als er niets gekozen is. ParentWindow wordt zolang uitgeschakeld.
; Multi = #True: meerdere tegelijk kiezen (Ctrl/Shift + klik); alle keuzes staan dan in GRO_Chosen().
Procedure.s GRO_ChooseTex(Archive.s, ParentWindow.i, Multi.i = #False)
  Protected win.i, filter.i, list.i, count.i, ok.i, cancel.i, event.i, done.i, chosen.s, row.i
  Protected label.i

  ClearList(GRO_Chosen())
  If GRO_ReadList(Archive) <= 0
    MessageRequester("Open from .gro", "No .tex files found in" + #LF$ + Archive, #PB_MessageRequester_Warning)
    ProcedureReturn ""
  EndIf

  win = OpenWindow(#PB_Any, 0, 0, 760, 520, "Choose a texture - " + GetFilePart(Archive), #PB_Window_SystemMenu | #PB_Window_WindowCentered | #PB_Window_SizeGadget, WindowID(ParentWindow))
  If win = 0
    ProcedureReturn ""
  EndIf
  label  = TextGadget(#PB_Any, 8, 12, 40, 20, "Filter:")
  filter = StringGadget(#PB_Any, 52, 8, 300, 24, "")
  count  = TextGadget(#PB_Any, 364, 12, 300, 20, "")
  If Multi
    list = ListIconGadget(#PB_Any, 8, 40, 744, 436, "Name", 260, #PB_ListIcon_FullRowSelect | #PB_ListIcon_GridLines | #PB_ListIcon_MultiSelect)
    SetWindowTitle(win, "Choose textures (Ctrl/Shift + click for more) - " + GetFilePart(Archive))
  Else
    list = ListIconGadget(#PB_Any, 8, 40, 744, 436, "Name", 260, #PB_ListIcon_FullRowSelect | #PB_ListIcon_GridLines)
  EndIf
  AddGadgetColumn(list, 1, "Size", 70)
  AddGadgetColumn(list, 2, "Folder", 400)
  ok     = ButtonGadget(#PB_Any, 560, 484, 92, 28, "Open", #PB_Button_Default)
  cancel = ButtonGadget(#PB_Any, 660, 484, 92, 28, "Cancel")
  AddKeyboardShortcut(win, #PB_Shortcut_Return, 1)
  AddKeyboardShortcut(win, #PB_Shortcut_Escape, 2)
  GRO_FillList(list, count, "")
  SetActiveGadget(filter)
  DisableWindow(ParentWindow, #True)

  ; Eigen gebeurtenissenlus zolang dit venster open is
  Repeat
    event = WaitWindowEvent()
    If EventWindow() <> win
      Continue
    EndIf
    Select event
      Case #PB_Event_CloseWindow
        done = #True
      Case #PB_Event_SizeWindow
        ResizeGadget(list, #PB_Ignore, #PB_Ignore, WindowWidth(win) - 16, WindowHeight(win) - 84)
        ResizeGadget(ok, WindowWidth(win) - 200, WindowHeight(win) - 36, #PB_Ignore, #PB_Ignore)
        ResizeGadget(cancel, WindowWidth(win) - 100, WindowHeight(win) - 36, #PB_Ignore, #PB_Ignore)
      Case #PB_Event_Menu                   ; sneltoetsen
        Select EventMenu()
          Case 1 : row = GetGadgetState(list) : If row < 0 And CountGadgetItems(list) > 0 : row = 0 : SetGadgetItemState(list, 0, #PB_ListIcon_Selected) : EndIf
                   If row >= 0 : chosen = GRO_CollectSelected(list) : done = #True : EndIf
          Case 2 : done = #True
        EndSelect
      Case #PB_Event_Gadget
        Select EventGadget()
          Case filter
            If EventType() = #PB_EventType_Change
              GRO_FillList(list, count, GetGadgetText(filter))
            EndIf
          Case list
            If EventType() = #PB_EventType_LeftDoubleClick And GetGadgetState(list) >= 0
              chosen = GRO_CollectSelected(list)
              done = #True
            EndIf
          Case ok
            If GetGadgetState(list) >= 0
              chosen = GRO_CollectSelected(list)
              done = #True
            EndIf
          Case cancel
            done = #True
        EndSelect
    EndSelect
  Until done

  DisableWindow(ParentWindow, #False)
  CloseWindow(win)
  SetActiveWindow(ParentWindow)
  ProcedureReturn chosen
EndProcedure
