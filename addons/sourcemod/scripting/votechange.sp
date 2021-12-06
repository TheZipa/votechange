#include <sourcemod>
#include <csgo_colors>

#pragma semicolon 1
#pragma newdecls required

#undef REQUIRE_PLUGIN

#include <adminmenu>

Database g_hDataBase;
KeyValues g_hKeyValues;
Menu g_hVotechangeMenu;
TopMenu g_hAdminMenu = null;

// ConVars
ConVar Cvar_AutoExecute,
		Cvar_AutoExecute_Time;
		
Handle g_hTimer = INVALID_HANDLE;

public Plugin myinfo = 
{
	name = "VoteChange",
	author = "TheZipa",
	description = "Command to votes on the server",
	version = "1.1.2",
}

public void OnPluginStart()
{
	Cvar_AutoExecute = CreateConVar("sm_votechange_autoexecute", "0", "Enable automatic activation of the votes for all players in the session. 1 - On, 0 - Off", _, true, 0.0, true, 1.0);
	HookConVarChange(Cvar_AutoExecute, HookAutoExecute);
	Cvar_AutoExecute_Time = CreateConVar("sm_votechange_autoexecute_time", "60", "Sets the interval between automatic votes (minutes)", _, true, 1.0, true, 1320.0);
	HookConVarChange(Cvar_AutoExecute_Time, HookAutoExecute_Time);
	
	RegConsoleCmd("sm_votechange", Cmd_Votechange);
	RegAdminCmd("sm_push_votechange", Cmd_PushVotechange, ADMFLAG_KICK);
	
	char szConfigPath[50];
	Database.Connect(ConnectionCallBack, "storage-local");
	BuildPath(Path_SM, szConfigPath, sizeof(szConfigPath), "configs/votechange.ini");
	
	g_hKeyValues = new KeyValues("Votechange");
	if(!(g_hKeyValues.ImportFromFile(szConfigPath)))
	{
		SetFailState("votechange.ini is missing");
	}
	
	if(LibraryExists("adminmenu"))
    {
		TopMenu hTopMenu;
		if((hTopMenu = GetAdminTopMenu()) != null)
		{
			OnAdminMenuReady(hTopMenu);
		}
	}
	
	char szKeyName[64], szTitleName[200];
	g_hVotechangeMenu = new Menu(VotechangeMenu_Handler);
	g_hKeyValues.Rewind();
	if(g_hKeyValues.GotoFirstSubKey())
	{
		do
		{
			g_hKeyValues.GetSectionName(szKeyName, sizeof(szKeyName));
			g_hKeyValues.GetString("title", szTitleName, sizeof(szTitleName));
				
			g_hVotechangeMenu.AddItem(szKeyName, szTitleName);
		}while(g_hKeyValues.GotoNextKey());
	}
		
	g_hVotechangeMenu.ExitButton = true;
	
	LoadTranslations("votechange.phrases");
	LoadTranslations("common.phrases");
	
	AutoExecConfig(true, "votechange");
}

public void OnPluginEnd()
{
	delete g_hVotechangeMenu;
	delete g_hKeyValues;
}

public void OnMapStart()
{
	if(GetConVarBool(Cvar_AutoExecute))
	{
		g_hTimer = CreateTimer(GetConVarFloat(Cvar_AutoExecute_Time) * 60, Timer_VotechangeAutoExecute, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action Timer_VotechangeAutoExecute(Handle hTimer)
{
	VotechangeAll();
	return Plugin_Continue;
}

public void HookAutoExecute(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(StrEqual(newValue, "1"))
	{
		g_hTimer = CreateTimer(GetConVarFloat(Cvar_AutoExecute_Time) * 60.0, Timer_VotechangeAutoExecute, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		KillTimer(g_hTimer);
		g_hTimer = INVALID_HANDLE;
	}	
		
	LogMessage("Changed cvar \"%s\" to %s", "sm_votechange_autoexecute", newValue);
}

public void HookAutoExecute_Time(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(g_hTimer != INVALID_HANDLE)
	{
		KillTimer(g_hTimer);
		g_hTimer = INVALID_HANDLE;
		g_hTimer = CreateTimer(GetConVarFloat(Cvar_AutoExecute_Time) * 60.0, Timer_VotechangeAutoExecute, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
	
	LogMessage("Changed cvar \"%s\" to %s", "sm_votechange_autoexecute_time", newValue);
}

public void OnLibraryRemoved(const char[] szName)
{
	if(StrEqual(szName, "adminmenu"))
	{
		g_hAdminMenu = null;
	}
}

public void OnAdminMenuReady(Handle aTopMenu)
{
	TopMenu hTopMenu = TopMenu.FromHandle(aTopMenu);
	if(hTopMenu == g_hAdminMenu)
	{
		return;
	}
	g_hAdminMenu = hTopMenu;
	
	TopMenuObject hVotechangeCategory = g_hAdminMenu.AddCategory("votechange_category", Handler_VotechangeCategory, "sm_votechange_category", ADMFLAG_KICK);
	
	if(hVotechangeCategory != INVALID_TOPMENUOBJECT)
	{
		g_hAdminMenu.AddItem("votechange_clear", Handler_VotechangeClear, hVotechangeCategory, "sm_votechange_clear", ADMFLAG_ROOT);
		g_hAdminMenu.AddItem("votechange_push", Handler_VotechangePush, hVotechangeCategory, "sm_votechange_push", ADMFLAG_KICK);
		g_hAdminMenu.AddItem("votechange_results", Handler_VotechangeResults, hVotechangeCategory, "sm_votechange_results", ADMFLAG_ROOT);
		g_hAdminMenu.AddItem("votechange_list", Handler_VotechangeList, hVotechangeCategory, "sm_votechange_list", ADMFLAG_ROOT);
	}
}

public void Handler_VotechangeCategory(TopMenu hMenu, TopMenuAction action, TopMenuObject object_id, int iClient, char[] sBuffer, int maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			FormatEx(sBuffer, maxlength, "%T", "Votechange Management", iClient);
		}
		case TopMenuAction_DisplayTitle:
		{
			FormatEx(sBuffer, maxlength, "%T", "Votechange Management", iClient);
		}
	}
}

public void Handler_VotechangeClear(TopMenu hMenu, TopMenuAction action, TopMenuObject object_id, int iClient, char[] sBuffer, int maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			FormatEx(sBuffer, maxlength, "%T", "Clear List", iClient);
		}
		case TopMenuAction_SelectOption:
		{
			char szMenuTitle[100], szClearAll[50], szKeyName[50], szTitleName[200];
			Menu hSelectClearMenu = new Menu(SelectClearMenu_Handler);
			FormatEx(szClearAll, sizeof(szClearAll), "%T", "Clear All", iClient);
			FormatEx(szMenuTitle, sizeof(szMenuTitle), "%T:", "Votechange Menu", iClient);
			hSelectClearMenu.SetTitle(szMenuTitle);
				
			g_hKeyValues.Rewind();
			if(g_hKeyValues.GotoFirstSubKey())
			{
				do
				{
					g_hKeyValues.GetSectionName(szKeyName, sizeof(szKeyName));
					g_hKeyValues.GetString("title", szTitleName, sizeof(szTitleName));
					
					hSelectClearMenu.AddItem(szKeyName, szTitleName);
				}while(g_hKeyValues.GotoNextKey());
			}
			
			hSelectClearMenu.AddItem("clear_all", szClearAll);
			hSelectClearMenu.ExitButton = true;
			hSelectClearMenu.Display(iClient, 20);
		}
	}
}

public void Handler_VotechangePush(TopMenu hMenu, TopMenuAction action, TopMenuObject object_id, int iClient, char[] sBuffer, int maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			FormatEx(sBuffer, maxlength, "%T", "Send To Player", iClient);
		}
		case TopMenuAction_SelectOption:
		{
			char szTargetMenuTitle[64];
			FormatEx(szTargetMenuTitle, sizeof(szTargetMenuTitle), "%T", "Select Player", iClient);
			Menu hTargetsMenu = new Menu(TargetsMenu_Handler);
			hTargetsMenu.SetTitle(szTargetMenuTitle);
			
			AddTargetsToMenu(hTargetsMenu, 0, true, false);
			hTargetsMenu.Display(iClient, 50);
		}
	}
}

public void Handler_VotechangeResults(TopMenu hMenu, TopMenuAction action, TopMenuObject object_id, int iClient, char[] sBuffer, int maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			FormatEx(sBuffer, maxlength, "%T", "Results", iClient);
		}
		case TopMenuAction_SelectOption:
		{
			char szMenuTitle[100], szKeyName[50], szTitleName[200];
			Menu hSelectResultsMenu = new Menu(SelectResultsMenu_Handler);
			FormatEx(szMenuTitle, sizeof(szMenuTitle), "%T:", "Votechange Menu", iClient);
			hSelectResultsMenu.SetTitle(szMenuTitle);
				
			g_hKeyValues.Rewind();
			if(g_hKeyValues.GotoFirstSubKey())
			{
				do
				{
					g_hKeyValues.GetSectionName(szKeyName, sizeof(szKeyName));
					g_hKeyValues.GetString("title", szTitleName, sizeof(szTitleName));
					
					hSelectResultsMenu.AddItem(szKeyName, szTitleName);
				}while(g_hKeyValues.GotoNextKey());
			}
			
			hSelectResultsMenu.ExitButton = true;
			hSelectResultsMenu.ExitBackButton = true;
			hSelectResultsMenu.Display(iClient, 20);
		}
	}
}

public void Handler_VotechangeList(TopMenu hMenu, TopMenuAction action, TopMenuObject object_id, int iClient, char[] sBuffer, int maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			FormatEx(sBuffer, maxlength, "%T", "List of Votes", iClient);
		}
		case TopMenuAction_SelectOption:
		{
			char szMenuTitle[100], szKeyName[50], szTitleName[200];
			Menu hSelectListMenu = new Menu(SelectVotechangeList_Handler);
			FormatEx(szMenuTitle, sizeof(szMenuTitle), "%T:", "Votechange Menu", iClient);
			hSelectListMenu.SetTitle(szMenuTitle);
				
			g_hKeyValues.Rewind();
			if(g_hKeyValues.GotoFirstSubKey())
			{
				do
				{
					g_hKeyValues.GetSectionName(szKeyName, sizeof(szKeyName));
					g_hKeyValues.GetString("title", szTitleName, sizeof(szTitleName));
					
					hSelectListMenu.AddItem(szKeyName, szTitleName);
				}while(g_hKeyValues.GotoNextKey());
			}
			
			hSelectListMenu.ExitButton = true;
			hSelectListMenu.ExitBackButton = true;
			hSelectListMenu.Display(iClient, 20);
		}
	}
}

public void ConnectionCallBack(Database hDB, const char[] sError, any data)
{
	if (hDB == null)
	{
		SetFailState("Database failure: %s", sError);
		return;
	}
    
	g_hDataBase = hDB;
	g_hDataBase.Query(SQL_CreateTable_CallBack, "CREATE TABLE IF NOT EXISTS `votechange` (`steamid` INTEGER, `nickname` VARCHAR(150), `question` VARCHAR(50), `choice` VARCHAR(50) )");
}

public Action Cmd_Votechange(int iClient, int args)
{
	if(IsClientInGame(iClient))
	{
		char szMenuTitle[255];
		FormatEx(szMenuTitle, sizeof(szMenuTitle), "%T:", "Votechange Menu", iClient);
		g_hVotechangeMenu.SetTitle(szMenuTitle);
		g_hVotechangeMenu.Display(iClient, 30);
	}
	
	return Plugin_Handled;
}

public Action Cmd_PushVotechange(int iClient, int args)
{
	if(IsClientInGame(iClient))
	{
		if(args < 1)
		{
			ReplyToCommand(iClient, "[SM] %t", "Push Usage");
			return Plugin_Handled;
		}
		
		char arg[32];
		GetCmdArg(1, arg, sizeof(arg));
		int iTargetClient = FindTarget(iClient, arg, true, true);
		PushVotechange(iClient, iTargetClient);
	}
	
	return Plugin_Handled;
}

void VotechangeAll()
{
	for(int i = 1; i <= MaxClients; ++i)
	{
		if(IsClientInGame(i))
		{
			Cmd_Votechange(i, 0);
			CGOPrintToChat(i, "%t", "Votechange All");
		}
	}
}

void PushVotechange(int iClient, int iTarget)
{
	if(iTarget > 0 && IsClientInGame(iTarget))
	{
		Cmd_Votechange(iTarget, 0);
		CGOPrintToChat(iTarget, "%t", "Votechange Pushed");
		LogAction(iClient, iTarget, "%L pushed votechange to %L", iClient, iTarget);
	}
}

public int VotechangeMenu_Handler(Menu hMenu, MenuAction action, int iClient, int iItem)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			char szVoteKeyName[50], szVote[200];
			hMenu.GetItem(iItem, szVoteKeyName, sizeof(szVoteKeyName), _, szVote, sizeof(szVote));
			
			if(g_hDataBase != null)
			{
				char szQuery[255];
				FormatEx(szQuery, sizeof(szQuery), "SELECT `choice` FROM `votechange` WHERE `steamid` = '%i' AND `question` = '%s'", GetSteamAccountID(iClient), szVoteKeyName);
				ArrayList hQueryData = new ArrayList(ByteCountToCells(200));
				hQueryData.PushString(szVoteKeyName);
				hQueryData.PushString(szVote);
				hQueryData.Push(iClient);
				
				g_hDataBase.Query(SQL_Callback_CheckChoice, szQuery, hQueryData);
			}
		}
	}
	return 0;
}

public int SelectClearMenu_Handler(Menu hMenu, MenuAction action, int iClient, int iItem)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			char szVoteKeyName[50], szAgreeTitle[150], szAgree[10], szDisagree[10];
			hMenu.GetItem(iItem, szVoteKeyName, sizeof(szVoteKeyName));
			
			if(StrEqual(szVoteKeyName, "clear_all"))
			{
				FormatEx(szAgreeTitle, sizeof(szAgreeTitle), "%T?", "Clear All", iClient);
			}
			else
			{
				FormatEx(szAgreeTitle, sizeof(szAgreeTitle), "%T", "Clear Agreement", iClient);
			}
			FormatEx(szAgree, sizeof(szAgree), "%T", "Agree", iClient);
			FormatEx(szDisagree, sizeof(szDisagree), "%T", "Disagree", iClient);
			
			Menu hClearAgree = new Menu(ClearAgree_Handler);
			hClearAgree.SetTitle(szAgreeTitle);
			hClearAgree.AddItem(szVoteKeyName, szAgree);
			hClearAgree.AddItem("disagree", szDisagree);
			hClearAgree.Display(iClient, 10);
		}
		case MenuAction_Cancel:
		{
			if(iItem == MenuCancel_ExitBack)
			{
				RedisplayAdminMenu(g_hAdminMenu, iClient);
			}
		}
		case MenuAction_End:
		{
			delete hMenu;
		}
	}
	return 0;
}

public int SelectResultsMenu_Handler(Menu hMenu, MenuAction action, int iClient, int iItem)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			char szVoteKeyName[50], szQuestion[200];
			hMenu.GetItem(iItem, szVoteKeyName, sizeof(szVoteKeyName), _, szQuestion, sizeof(szQuestion));

			if(g_hDataBase != null)
			{
				char szQuery[255];
				FormatEx(szQuery, sizeof(szQuery), "SELECT COUNT(choice), `choice` FROM `votechange` WHERE `question` = '%s' GROUP BY `choice`", szVoteKeyName);
				ArrayList hQueryData = new ArrayList(ByteCountToCells(200));
				hQueryData.Push(iClient);
				hQueryData.PushString(szVoteKeyName);
				hQueryData.PushString(szQuestion);
				
				g_hDataBase.Query(SQL_Callback_Results, szQuery, hQueryData);
			}
		}
		case MenuAction_Cancel:
		{
			if(iItem == MenuCancel_ExitBack)
			{
				RedisplayAdminMenu(g_hAdminMenu, iClient);
			}
		}
		case MenuAction_End:
		{
			delete hMenu;
		}
	}
	return 0;
}

public int SelectVotechangeList_Handler(Menu hMenu, MenuAction action, int iClient, int iItem)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			char szVoteKeyName[50], szQuestion[200];
			hMenu.GetItem(iItem, szVoteKeyName, sizeof(szVoteKeyName), _, szQuestion, sizeof(szQuestion));

			if(g_hDataBase != null)
			{
				char szQuery[255];
				FormatEx(szQuery, sizeof(szQuery), "SELECT `nickname`, `choice` FROM `votechange` WHERE `question` = '%s'", szVoteKeyName);
				ArrayList hQueryData = new ArrayList(ByteCountToCells(200));
				hQueryData.Push(iClient);
				hQueryData.PushString(szVoteKeyName);
				hQueryData.PushString(szQuestion);
				
				g_hDataBase.Query(SQL_Callback_List, szQuery, hQueryData);
			}
		}
		case MenuAction_Cancel:
		{
			if(iItem == MenuCancel_ExitBack)
			{
				RedisplayAdminMenu(g_hAdminMenu, iClient);
			}
		}
		case MenuAction_End:
		{
			delete hMenu;
		}
	}
	return 0;
}

public int ClearAgree_Handler(Menu hMenu, MenuAction action, int iClient, int iItem)
{
	switch(action)
	{
		case MenuAction_End:
		{
			delete hMenu;
		}
		case MenuAction_Select:
		{
			char szItemInfo[12];
			hMenu.GetItem(iItem, szItemInfo, sizeof(szItemInfo));
			
			if(StrEqual(szItemInfo, "disagree", true))
			{
				RedisplayAdminMenu(g_hAdminMenu, iClient);
			}
			else
			{
				char szClearQuery[100];
				if(StrEqual(szItemInfo, "clear_all"))
				{
					FormatEx(szClearQuery, sizeof(szClearQuery), "DELETE FROM `votechange`");
					g_hDataBase.Query(SQL_Callback_AllClear, szClearQuery, iClient);
					LogMessage("%L deleted all votechange results", iClient);
				}
				else
				{
					FormatEx(szClearQuery, sizeof(szClearQuery), "DELETE FROM `votechange` WHERE `question` = '%s'", szItemInfo);
					g_hDataBase.Query(SQL_Callback_Clear, szClearQuery, iClient);

					char szLogQuestion[200];
					g_hKeyValues.Rewind();
					g_hKeyValues.GetString(szItemInfo, szLogQuestion, sizeof(szLogQuestion));
					
					LogMessage("%L deleted votechange results from '%s'", iClient, szLogQuestion);
				}
			}
		}
	}
}

public int TargetsMenu_Handler(Menu hMenu, MenuAction action, int iClient, int iItem)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			char szClient[64];
			hMenu.GetItem(iItem, szClient, sizeof(szClient));	
			PushVotechange(iClient, GetClientOfUserId(StringToInt(szClient)));
		}
		case MenuAction_Cancel:
		{
			if(iItem == MenuCancel_ExitBack)
			{
				RedisplayAdminMenu(g_hAdminMenu, iClient);
			}
		}
		case MenuAction_End:
		{
			delete hMenu;
		}
	}
	return 0;
}

public int VotechangeResult_Handler(Menu hMenu, MenuAction action, int iClient, int iItem)
{
	switch(action)
	{
		case MenuAction_Cancel:
		{
			if(iItem == MenuCancel_ExitBack)
			{
				RedisplayAdminMenu(g_hAdminMenu, iClient);
			}
		}
		case MenuAction_End:
		{
			delete hMenu;
		}
	}
}

public int VotechangeList_Handler(Menu hMenu, MenuAction action, int iClient, int iItem)
{
	switch(action)
	{
		case MenuAction_Cancel:
		{
			if(iItem == MenuCancel_ExitBack)
			{
				RedisplayAdminMenu(g_hAdminMenu, iClient);
			}
		}
		case MenuAction_End:
		{
			delete hMenu;
		}
	}
}

public void SQL_CreateTable_CallBack(Database hDatabase, DBResultSet results, const char[] sError, any data)
{
	if(sError[0])
	{
		LogError("SQL_CreateTable_CallBack: %s", sError);
		return;
	}
}

public void SQL_Callback_Results(Database hDatabase, DBResultSet results, const char[] sError, ArrayList hDataList)
{
	if(sError[0])
	{
		LogError("SQL_Callback_Results: %s", sError);
		return;
	}
	else
	{
		if(IsClientInGame(hDataList.Get(0)))
		{
			char szVotechangeResultsTitle[100], szVoteKeyName[50], szResultString[255], szAnswer[200];
			hDataList.GetString(1, szVoteKeyName, sizeof(szVoteKeyName));
			hDataList.GetString(2, szVotechangeResultsTitle, sizeof(szVotechangeResultsTitle));
			
			Menu hVotechangeResultsMenu = new Menu(VotechangeResult_Handler);
			hVotechangeResultsMenu.SetTitle(szVotechangeResultsTitle);
			hVotechangeResultsMenu.ExitButton = true;
			hVotechangeResultsMenu.ExitBackButton = true;
			
			if(results.RowCount == 0)
			{
				char szNoResults[64];
				FormatEx(szNoResults, sizeof(szNoResults), "%T", "No Results", hDataList.Get(0));
				hVotechangeResultsMenu.AddItem("no_results", szNoResults, ITEMDRAW_DISABLED);
			}
			else
			{
				char szAnswerKeyName[32];
				while(results.FetchRow())
				{
					results.FetchString(1, szAnswerKeyName, sizeof(szAnswerKeyName));
					
					g_hKeyValues.Rewind();
					if(g_hKeyValues.JumpToKey(szVoteKeyName, false))
					{
						g_hKeyValues.GetString(szAnswerKeyName, szAnswer, sizeof(szAnswer));
						
						FormatEx(szResultString, sizeof(szResultString), "%T", "People", hDataList.Get(0), szAnswer, results.FetchInt(0));
						hVotechangeResultsMenu.AddItem(szAnswerKeyName, szResultString, ITEMDRAW_DISABLED);
					}
				}
			}
			
			hVotechangeResultsMenu.Display(hDataList.Get(0), 25);
		}
		delete hDataList;
	}
}

public void SQL_Callback_List(Database hDatabase, DBResultSet results, const char[] sError, ArrayList hDataList)
{
	if(sError[0])
	{
		LogError("SQL_Callback_List: %s", sError);
		return;
	}
	else
	{
		if(IsClientInGame(hDataList.Get(0)))
		{
			char szTempListItem[255], szTempItemName[24], szMenuTitle[200], szVoteKeyName[50], szNick[150], szChoiceKeyName[50], szChoice[200];
			Menu hVotechangeList = new Menu(VotechangeList_Handler);
			hDataList.GetString(1, szVoteKeyName, sizeof(szVoteKeyName));
			hDataList.GetString(2, szMenuTitle, sizeof(szMenuTitle));
			
			hVotechangeList.SetTitle(szMenuTitle);
			hVotechangeList.ExitButton = true;
			hVotechangeList.ExitBackButton = true;
			
			if(results.RowCount == 0)
			{	
				char szEmptyVotes[64];
				FormatEx(szEmptyVotes, sizeof(szEmptyVotes), "%T", "Votes are Empty", hDataList.Get(0));
				hVotechangeList.AddItem("empty_votes", szEmptyVotes, ITEMDRAW_DISABLED);
			}
			else
			{	
				for(int i = 1; results.FetchRow(); i++)
				{
					results.FetchString(0, szNick, sizeof(szNick));
					results.FetchString(1, szChoiceKeyName, sizeof(szChoiceKeyName));
					
					g_hKeyValues.Rewind();
					if(g_hKeyValues.JumpToKey(szVoteKeyName, false))
					{
						g_hKeyValues.GetString(szChoiceKeyName, szChoice, sizeof(szChoice));
					}
					
					FormatEx(szTempListItem, sizeof(szTempListItem), "%s - %s", szNick, szChoice);
					FormatEx(szTempItemName, sizeof(szTempItemName), "item%i", i);
					
					hVotechangeList.AddItem(szTempItemName, szTempListItem, ITEMDRAW_DISABLED);
				}
			}
			hVotechangeList.Display(hDataList.Get(0), 30);
		}
	}
	delete hDataList;
}

public void SQL_Callback_Clear(Database hDatabase, DBResultSet results, const char[] sError, int iClient)
{
	if(sError[0])
	{
		LogError("SQL_Callback_Clear: %s", sError);
		return;
	}
	else
	{
		if(IsClientInGame(iClient))
			CGOPrintToChat(iClient, "%t", "Vote is Cleared");
	}
}

public void SQL_Callback_AllClear(Database hDatabase, DBResultSet results, const char[] sError, int iClient)
{
	if(sError[0])
	{
		LogError("SQL_Callback_AllClear: %s", sError);
		return;
	}
	else
	{
		if(IsClientInGame(iClient))
			CGOPrintToChat(iClient, "%t", "All Votes are Cleared");
	}
}

public void SQL_Callback_CheckChoice(Database hDatabase, DBResultSet results, const char[] sError, ArrayList hDataList)
{
	if(sError[0])
	{
		LogError("SQL_Callback_CheckChoice: %s", sError);
		return;
	}
	else
	{
		if(IsClientInGame(hDataList.Get(2)))
		{
			char szVoteKeyName[50], szPlayerChoice[50], szVote[200], szAnswer[200];
			bool bPlayerExists = results.RowCount != 0;
			hDataList.GetString(0, szVoteKeyName, sizeof(szVoteKeyName));
			hDataList.GetString(1, szVote, sizeof(szVote));
			
			if(bPlayerExists)
			{
				if(results.FetchRow())
				{
					results.FetchString(0, szPlayerChoice, sizeof(szPlayerChoice));
				}
			}
			
			Menu hCurrentVotechangeMenu = new Menu(CurrentVotechangeMenu_Handler);
			hCurrentVotechangeMenu.SetTitle(szVote);
			hCurrentVotechangeMenu.ExitBackButton = true;
			
			int i = 1;
			char szTempName[50];
			FormatEx(szTempName, sizeof(szTempName), "answer%i", i);
			do
			{
				g_hKeyValues.Rewind();
				if(g_hKeyValues.JumpToKey(szVoteKeyName, false))
				{
					g_hKeyValues.GetString(szTempName, szAnswer, sizeof(szAnswer));
					if(bPlayerExists)
					{
						if(StrEqual(szPlayerChoice, szTempName))
						{
							Format(szAnswer, sizeof(szAnswer), "%T", "Selected Answer", hDataList.Get(2), szAnswer);
							hCurrentVotechangeMenu.AddItem(szTempName, szAnswer, ITEMDRAW_DISABLED);
						}
						else
						{
							hCurrentVotechangeMenu.AddItem(szTempName, szAnswer);
						}
					}
					else
					{
						hCurrentVotechangeMenu.AddItem(szTempName, szAnswer);
					}
						
					i++;
					FormatEx(szTempName, sizeof(szTempName), "answer%i", i);
				}
			}while(g_hKeyValues.JumpToKey(szTempName, false));
			
			hCurrentVotechangeMenu.Display(hDataList.Get(2), 25);
			
		}
	}
	delete hDataList;
}

public int CurrentVotechangeMenu_Handler(Menu hMenu, MenuAction action, int iClient, int iItem)
{
	switch(action)
	{
		case MenuAction_End:
		{
			delete hMenu;
		}
		case MenuAction_Cancel:
		{
			if(iItem == MenuCancel_ExitBack)
			{
				g_hVotechangeMenu.Display(iClient, 25);
			}
		}
		case MenuAction_Select:
		{
			if(iClient)
			{	
				if(g_hDataBase != null)
				{
					char szQuestion[50], szChoice[50], szVote[200], szTempVote[200], szSQL_UpdateOrInsert[255];
					hMenu.GetItem(iItem, szChoice, sizeof(szChoice));
					hMenu.GetTitle(szVote, sizeof(szVote));
					
					g_hKeyValues.Rewind();
					if(g_hKeyValues.GotoFirstSubKey())
					{
						do
						{
							g_hKeyValues.GetString("title", szTempVote, sizeof(szTempVote));
							if(StrEqual(szVote, szTempVote))
							{
								g_hKeyValues.GetSectionName(szQuestion, sizeof(szQuestion));
								break;
							}
						}while(g_hKeyValues.GotoNextKey());
					}
					
					ArrayList hDataList = new ArrayList(ByteCountToCells(100));
					hDataList.Push(iClient);
					hDataList.PushString(szQuestion);
					hDataList.PushString(szChoice);
					
					FormatEx(szSQL_UpdateOrInsert, sizeof(szSQL_UpdateOrInsert), "SELECT `steamid` FROM `votechange` WHERE `steamid` = %i AND `question` = '%s'", GetSteamAccountID(iClient), szQuestion);
					g_hDataBase.Query(SQL_Callback_UpdateOrInsertData, szSQL_UpdateOrInsert, hDataList);
				}
			}
		}
	}
	return 0;
}

public void SQL_Callback_UpdateOrInsertData(Database hDatabase, DBResultSet results, const char[] sError, ArrayList hData)
{
	if(sError[0])
	{
		LogError("SQL_Callback_UpdateOrInsertData: %s", sError);
		return;
	}
	else
	{
		int iClient = hData.Get(0);
		if(IsClientInGame(iClient))
		{
			char szQuestion[50], szChoice[50], szSQL_ClientData[255];
			hData.GetString(1, szQuestion, sizeof(szQuestion));
			hData.GetString(2, szChoice, sizeof(szChoice));
			
			if(results.RowCount == 0)
			{	
				FormatEx(szSQL_ClientData, sizeof(szSQL_ClientData), "INSERT INTO `votechange` (steamid, nickname, question, choice) VALUES (%i, '%N', '%s', '%s')", GetSteamAccountID(iClient), iClient, szQuestion, szChoice);
				g_hDataBase.Query(SQL_Callback_InsertClientData, szSQL_ClientData, iClient);
			}
			else
			{
				FormatEx(szSQL_ClientData, sizeof(szSQL_ClientData), "UPDATE `votechange` SET `nickname` = '%N', `choice` = '%s' WHERE `steamid` = %i AND `question` = '%s'", iClient, szChoice, GetSteamAccountID(iClient), szQuestion);
				g_hDataBase.Query(SQL_Callback_UpdateClientData, szSQL_ClientData, iClient);
			}
			
			char szLogQuestion[200], szLogChoice[150];
			g_hKeyValues.Rewind();
			if(g_hKeyValues.JumpToKey(szQuestion))
			{
				g_hKeyValues.GetString("title", szLogQuestion, sizeof(szLogQuestion));
				g_hKeyValues.GetString(szChoice, szLogChoice, sizeof(szLogChoice));
			}
			LogMessage("%L selected '%s' in the vote '%s'", iClient, szLogChoice, szLogQuestion);
		}
	}
}

public void SQL_Callback_InsertClientData(Database hDatabase, DBResultSet results, const char[] sError, int iClient)
{
	if(sError[0])
	{
		LogError("SQL_Callback_InsertClientData: %s", sError);
		return;
	}
	else
	{
		if(IsClientInGame(iClient))
		{
			CGOPrintToChat(iClient, "%t", "Successfully Voted");
			DisplayMenu(g_hVotechangeMenu, iClient, 30);
		}
	}
}

public void SQL_Callback_UpdateClientData(Database hDatabase, DBResultSet results, const char[] sError, int iClient)
{
	if(sError[0])
	{
		LogError("SQL_Callback_UpdateClientData: %s", sError);
		return;
	}
	else
	{
		if(IsClientInGame(iClient))
		{
			CGOPrintToChat(iClient, "%t", "Vote is Updated");
			DisplayMenu(g_hVotechangeMenu, iClient, 30);
		}
	}
}