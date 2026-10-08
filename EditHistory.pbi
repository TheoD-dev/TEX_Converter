; EditHistory.pbi - ongedaan maken (Undo) en opnieuw doen (Redo) in het hoofdvenster
;
; Hoe het werkt: na elke bewerking (Resize, Channels, Normal map, en later Levels, Curves, ...)
; bewaren we een kopie van het plaatje plus de gegevens die erbij horen (maat, transparantie, ...).
; Dat noemen we een "toestand". Toestand 0 is altijd het origineel zoals het geladen is.
;
;   [Original] -> [Resize] -> [Levels] -> [Invert]
;                                ^ EH_Pos (waar we nu zijn)
;
; Undo  = één toestand terug; Redo = één toestand vooruit.
; Doe je na een Undo een nieuwe bewerking, dan vervallen de toestanden daarna (zoals in elk programma).
; Het origineel wordt dus nooit veranderd; pas bij opslaan komt een bewerking in een bestand.
;
; Geheugen: een kopie van een 2048 x 2048-plaatje is 16 MB. We bewaren hooguit EH_MaxStates
; toestanden; daarna valt de oudste bewerking weg (het origineel blijft altijd bewaard).

Global EH_MaxStates.i = 30     ; aantal toestanden; het hoofdprogramma zet dit volgens Preferences

Structure EditState
  Image.i                       ; kopie van het plaatje in deze toestand
  Name.s                        ; naam van de bewerking die tot deze toestand leidde ("Resize", ...)
  Width.i
  Height.i
  HasAlpha.i
  IsHDR.i                       ; #True alleen in de originele toestand van een HDR-texture
  FirstMip.i                    ; SE1: voor de grootte in het spel (verandert bij Resize)
  Note.s                        ; tekst voor de statusbalk
  Suffix.s                      ; achtervoegsel voor de voorgestelde naam bij Save As
  Status.s                      ; tekst voor statusbalkveld 2 (maat en soort)
  Clipped.i                     ; aantal waarden dat deze bewerking naar puur zwart/wit duwde (Levels)
EndStructure

Global NewList EH_States.EditState()
Global EH_Pos.i = -1            ; index van de huidige toestand in EH_States()
Global EH_SavedPos.i = 0        ; bij welke toestand het laatst is opgeslagen (-1 = onbekend)

; Alles weggooien (bijv. bij het sluiten of voor een nieuw bestand).
Procedure EH_Clear()
  ForEach EH_States()
    If EH_States()\Image And IsImage(EH_States()\Image) : FreeImage(EH_States()\Image) : EndIf
  Next
  ClearList(EH_States())
  EH_Pos = -1
  EH_SavedPos = 0
EndProcedure

; Voegt een toestand toe na de huidige. Image wordt gekopieerd; de aanroeper houdt zijn eigen plaatje.
Procedure EH_Push(Image.i, *State.EditState)
  Protected copy.i = CopyImage(Image, #PB_Any)
  If copy = 0
    ProcedureReturn
  EndIf
  ; Alles na de huidige toestand vervalt (de "redo"-tak)
  While ListSize(EH_States()) > EH_Pos + 1
    LastElement(EH_States())
    If EH_States()\Image : FreeImage(EH_States()\Image) : EndIf
    DeleteElement(EH_States())
  Wend
  If EH_SavedPos > EH_Pos : EH_SavedPos = -1 : EndIf
  LastElement(EH_States())
  AddElement(EH_States())
  CopyStructure(*State, @EH_States(), EditState)
  EH_States()\Image = copy
  EH_Pos = ListSize(EH_States()) - 1
  ; Te veel toestanden: de oudste bewerking (niet het origineel) laten vallen
  While ListSize(EH_States()) > EH_MaxStates And ListSize(EH_States()) > 2
    SelectElement(EH_States(), 1)
    If EH_States()\Image : FreeImage(EH_States()\Image) : EndIf
    DeleteElement(EH_States())
    EH_Pos - 1
    EH_SavedPos - 1
    If EH_SavedPos < 0 : EH_SavedPos = -1 : EndIf
  Wend
EndProcedure

; Begint opnieuw met alleen het origineel.
Procedure EH_Reset(Image.i, *State.EditState)
  EH_Clear()
  EH_Push(Image, *State)
  EH_SavedPos = 0
EndProcedure

Procedure.i EH_CanUndo()
  ProcedureReturn Bool(EH_Pos > 0)
EndProcedure

Procedure.i EH_CanRedo()
  ProcedureReturn Bool(EH_Pos >= 0 And EH_Pos < ListSize(EH_States()) - 1)
EndProcedure

; Naam van de bewerking die Undo terugdraait / die Redo opnieuw doet.
Procedure.s EH_UndoName()
  If Not EH_CanUndo() : ProcedureReturn "" : EndIf
  SelectElement(EH_States(), EH_Pos)
  ProcedureReturn EH_States()\Name
EndProcedure

Procedure.s EH_RedoName()
  If Not EH_CanRedo() : ProcedureReturn "" : EndIf
  SelectElement(EH_States(), EH_Pos + 1)
  ProcedureReturn EH_States()\Name
EndProcedure

; Gaat naar toestand Index en geeft een pointer naar die toestand terug (of 0).
; De aanroeper maakt zelf een kopie van het plaatje om mee verder te werken.
Procedure.i EH_GoTo(Index.i)
  If Index < 0 Or Index >= ListSize(EH_States())
    ProcedureReturn 0
  EndIf
  EH_Pos = Index
  ProcedureReturn SelectElement(EH_States(), Index)
EndProcedure

Procedure.i EH_Undo()
  ProcedureReturn EH_GoTo(EH_Pos - 1)
EndProcedure

Procedure.i EH_Redo()
  ProcedureReturn EH_GoTo(EH_Pos + 1)
EndProcedure

Procedure.i EH_Original()
  ProcedureReturn EH_GoTo(0)
EndProcedure

; Zijn er wijzigingen die nog niet zijn opgeslagen?
Procedure.i EH_IsDirty()
  ProcedureReturn Bool(EH_Pos > 0 And EH_Pos <> EH_SavedPos)
EndProcedure

Procedure EH_MarkSaved()
  EH_SavedPos = EH_Pos
EndProcedure

; Aantal bewerkingen tot de huidige toestand (zonder het origineel).
Procedure.i EH_EditCount()
  If EH_Pos < 0 : ProcedureReturn 0 : EndIf
  ProcedureReturn EH_Pos
EndProcedure
