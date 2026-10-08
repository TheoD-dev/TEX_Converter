; Settings.pbi - instellingen bewaren tussen twee keer starten van het programma
;
; De instellingen staan in een tekstbestand (zoals een .ini) in de map voor programmagegevens:
;   Windows: C:\Users\<naam>\AppData\Roaming\TexConverter\TexConverter.prefs
;   Linux:   /home/<naam>/.TexConverter/TexConverter.prefs   (of ~/.config, afhankelijk van PureBasic)
; We gebruiken de Preferences-bibliotheek van PureBasic, die op Windows en Linux hetzelfde werkt.

; Volledige naam van het instellingenbestand (de map wordt zo nodig gemaakt).
Procedure.s SET_File()
  Protected dir.s = GetUserDirectory(#PB_Directory_ProgramData) + "TexConverter"
  If FileSize(dir) <> -2
    CreateDirectory(dir)
  EndIf
  ProcedureReturn dir + #PS$ + "TexConverter.prefs"
EndProcedure

; Leest een tekst-instelling. Bestaat het bestand of de sleutel niet, dan DefaultValue.
Procedure.s SET_Read(Key.s, DefaultValue.s = "")
  Protected value.s = DefaultValue
  If OpenPreferences(SET_File())
    value = ReadPreferenceString(Key, DefaultValue)
    ClosePreferences()
  EndIf
  ProcedureReturn value
EndProcedure

; Schrijft een tekst-instelling (de andere instellingen in het bestand blijven staan).
Procedure SET_Write(Key.s, Value.s)
  If OpenPreferences(SET_File()) = 0
    If CreatePreferences(SET_File()) = 0
      ProcedureReturn
    EndIf
  EndIf
  WritePreferenceString(Key, Value)
  ClosePreferences()
EndProcedure

; Leest een map; bestaat die map niet meer, dan "".
Procedure.s SET_ReadFolder(Key.s)
  Protected dir.s = SET_Read(Key)
  If dir <> "" And FileSize(dir) = -2
    ProcedureReturn dir
  EndIf
  ProcedureReturn ""
EndProcedure

; Getallen lezen en schrijven (bewaard als tekst). Bij een ontbrekende of lege waarde: DefaultValue.
Procedure.i SET_ReadInt(Key.s, DefaultValue.i)
  Protected s.s = SET_Read(Key)
  If s = "" : ProcedureReturn DefaultValue : EndIf
  ProcedureReturn Val(s)
EndProcedure

Procedure.d SET_ReadDouble(Key.s, DefaultValue.d)
  Protected s.s = SET_Read(Key)
  If s = "" : ProcedureReturn DefaultValue : EndIf
  ProcedureReturn ValD(s)
EndProcedure

Procedure SET_WriteInt(Key.s, Value.i)
  SET_Write(Key, Str(Value))
EndProcedure

Procedure SET_WriteDouble(Key.s, Value.d)
  SET_Write(Key, StrD(Value, 3))
EndProcedure