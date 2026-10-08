; Voorbeeld van een Gui voor de Serious Sam TEX viewer/converter voor Claude


; Schakelt de expliciete modus in of uit. 
; Wanneer deze modus is ingeschakeld, worden alle variabelen die niet expliciet zijn gedeclareerd 
; met Define, Global, Protected of Static niet geaccepteerd en geeft de compiler een foutmelding. 
; Dit kan helpen bij het opsporen van typefouten.
EnableExplicit 

Global AppTitle.s = "Serious Sam TEX Converter"
Global Window_0
Global ScrollArea_0, Canvas_0
Global default_X.l, default_Y.l, default_W.l, default_H.l ; eventueel later uit een .ini gehaalde waarden
default_X = 100
default_Y = 50
default_H = 448
default_W = 824

Enumeration FormMenu
  #Menu_Open
  #Menu_Save 
  #Menu_SaveAs
  #Menu_Quit
  #Menu_Batch
  #Menu_Preferences
  #Menu_Help
  #Menu_About
  #Statusbar
EndEnumeration


Procedure OpenWindow_0()
  Window_0 = OpenWindow(#PB_Any, default_X, default_Y, default_W, default_H, AppTitle, #PB_Window_SystemMenu | #PB_Window_MinimizeGadget | #PB_Window_MaximizeGadget | #PB_Window_SizeGadget | #PB_Window_TitleBar | #PB_Window_ScreenCentered)
  CreateStatusBar(#Statusbar, WindowID(Window_0))
  AddStatusBarField(100)
  AddStatusBarField(180)
  AddStatusBarField(#PB_Ignore)
  CreateMenu(0, WindowID(Window_0))
  MenuTitle("File")
  MenuItem(#Menu_Open, "Open"+Chr(9)+"Ctrl+O")
  MenuItem(#Menu_Save, "Save"+Chr(9)+"Ctrl+S")
  MenuItem(#Menu_SaveAs, "Save As..."+Chr(9)+"Shift+Ctrl+S")
  MenuBar()
  MenuItem(#Menu_Quit, "Quit"+Chr(9)+"Q")
  MenuTitle("Tools")
  MenuItem(#Menu_Batch, "Batch conversion"+Chr(9)+"Ctrl+B")
  MenuItem(#Menu_Preferences, "Preferences..."+Chr(9)+"Ctrl+P")
  MenuTitle("Help")  
  MenuItem(#Menu_Help, "Help"+Chr(9)+"Ctrl+H")
  MenuItem(#Menu_About, "About")

  ScrollArea_0 = ScrollAreaGadget(#PB_Any, 4, 4, 819, 400, 1034, 1034, 1, #PB_ScrollArea_Single)
  Canvas_0 = CanvasGadget(#PB_Any, 4, 4, 1024, 1024, #PB_Canvas_Border | #PB_Canvas_ClipMouse | #PB_Canvas_Keyboard | #PB_Canvas_DrawFocus)
  AddKeyboardShortcut(Window_0, #PB_Shortcut_Control | #PB_Shortcut_O, #Menu_Open)
  AddKeyboardShortcut(Window_0, #PB_Shortcut_Control | #PB_Shortcut_S, #Menu_Save)
  AddKeyboardShortcut(Window_0, #PB_Shortcut_Shift|#PB_Shortcut_Control | #PB_Shortcut_S, #Menu_SaveAs)
  AddKeyboardShortcut(Window_0, #PB_Shortcut_Control | #PB_Shortcut_Q, #Menu_Quit)
  AddKeyboardShortcut(Window_0, #PB_Shortcut_Control | #PB_Shortcut_B, #Menu_Batch)  
  AddKeyboardShortcut(Window_0, #PB_Shortcut_Control | #PB_Shortcut_P, #Menu_Preferences) 
  AddKeyboardShortcut(Window_0, #PB_Shortcut_Control | #PB_Shortcut_H, #Menu_Help)  
  CloseGadgetList()
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

OpenWindow_0()
WindowResizing()



Global Event, WindowID, GadgetID, Event_Type, Quit.i
Repeat
  Event = WaitWindowEvent() 
  WindowID = EventWindow() 
  GadgetID = EventGadget() 
  Event_Type = EventType() 
  
    Select event
      Case #PB_Event_CloseWindow
        If EventWindow() = Window_0
          Quit = 1
        EndIf
    Case #PB_Event_Menu
      Select EventMenu()
        Case #Menu_Quit
          Quit = 1
      EndSelect
    Case #PB_Event_SizeWindow
      WindowResizing()  
  EndSelect
  
Until Quit = 1
; IDE Options = PureBasic 6.41 (Linux - x64)
; CursorPosition = 43
; FirstLine = 31
; Folding = -
; EnableXP
; DPIAware