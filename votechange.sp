#include <sourcemod>

#pragma semicolon 1
#pragma newdecls required

#undef REQUIRE_PLUGIN

#include <adminmenu>

Database g_hDataBase;
TopMenu g_hAdminMenu = null;
char g_szConfigPath[50];

public Plugin myinfo = 
{
	name = "VoteChange / Голосование за обновления на сервере",
	author = "TheZipa",
	description = "Команда для голосования за изменения или дополнений на сервере.",
	version = "1.0.0",
}

public void OnPluginStart()
{
	RegConsoleCmd("sm_votechange", Cmd_Votechange);
	Database.Connect(ConnectionCallBack, "storage-local");
	BuildPath(Path_SM, g_szConfigPath, sizeof(g_szConfigPath), "configs/votechange.ini");
	
	if(LibraryExists("adminmenu"))
    {
		TopMenu hTopMenu;
		if((hTopMenu = GetAdminTopMenu()) != null)
		{
			OnAdminMenuReady(hTopMenu);
		}
	}
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
	
	TopMenuObject hVotechangeCategory = g_hAdminMenu.AddCategory("votechange_category", Handler_VotechangeCategory, "sm_votechange_category", ADMFLAG_ROOT);
	
	if(hVotechangeCategory != INVALID_TOPMENUOBJECT)
	{
		g_hAdminMenu.AddItem("votechange_clear", Handler_VotechangeClear, hVotechangeCategory, "sm_votechange_clear", ADMFLAG_ROOT);
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
			FormatEx(sBuffer, maxlength, "Управление Votechange");
		}
		case TopMenuAction_DisplayTitle:
		{
			FormatEx(sBuffer, maxlength, "Управление Votechange");
		}
	}
}

public void Handler_VotechangeClear(TopMenu hMenu, TopMenuAction action, TopMenuObject object_id, int iClient, char[] sBuffer, int maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			FormatEx(sBuffer, maxlength, "Очистить список");
		}
		case TopMenuAction_SelectOption:
		{
			Menu hClearAgree = new Menu(ClearAgree_Handler);
			hClearAgree.SetTitle("Вы уверены, что хотитие очистить базу данных votechange?");
			hClearAgree.AddItem("agree", "Да");
			hClearAgree.AddItem("disagree", "Нет");
			hClearAgree.Display(iClient, 10);
		}
	}
}

public void Handler_VotechangeResults(TopMenu hMenu, TopMenuAction action, TopMenuObject object_id, int iClient, char[] sBuffer, int maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			FormatEx(sBuffer, maxlength, "Результаты");
		}
		case TopMenuAction_SelectOption:
		{
			if(g_hDataBase != null)
			{
				Transaction hTransaction = new Transaction();
				ArrayList hQueryData = new ArrayList(ByteCountToCells(150));
				KeyValues hKeyValues = new KeyValues("Votechange");
				
				if(hKeyValues.ImportFromFile(g_szConfigPath))
				{
					char szAnswer[255], szSQL_TransactionQuery[255];
					hQueryData.Push(iClient);
					if(hKeyValues.GotoFirstSubKey())
					{
						do
						{
							hKeyValues.GetString("description", szAnswer, sizeof(szAnswer));
							FormatEx(szSQL_TransactionQuery, sizeof(szSQL_TransactionQuery), "SELECT COUNT(choice) FROM `votechange` WHERE `choice` = '%s'", szAnswer);
							hTransaction.AddQuery(szSQL_TransactionQuery);
							hQueryData.PushString(szAnswer);
						}
						while(hKeyValues.GotoNextKey());
					}
				}
					
				g_hDataBase.Execute(hTransaction, SQL_CountTransaction_Success, SQL_CountTransaction_Failure, hQueryData);
			}
		}
	}
}

public void Handler_VotechangeList(TopMenu hMenu, TopMenuAction action, TopMenuObject object_id, int iClient, char[] sBuffer, int maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
		{
			FormatEx(sBuffer, maxlength, "Список проголосовавших");
		}
		case TopMenuAction_SelectOption:
		{
			if(g_hDataBase != null)
			{
				g_hDataBase.Query(SQL_Callback_List, "SELECT `nickname`, `choice` FROM `votechange`", iClient);
			}
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
	g_hDataBase.Query(SQL_CreateTable_CallBack, "CREATE TABLE IF NOT EXISTS `votechange` ( `id` INTEGER PRIMARY KEY AUTOINCREMENT, `steamid` VARCHAR(50), `nickname` VARCHAR(150) ,`choice` VARCHAR(100) )");
}

public Action Cmd_Votechange(int iClient, int args)
{
	KeyValues hKeyValues = new KeyValues("Votechange");
	
	if(iClient)
	{
		Menu hVotechangeMenu = new Menu(VotechangeMenu_Handler);
	
		if(hKeyValues.ImportFromFile(g_szConfigPath))
		{
			char szQuestion[100], szKeyName[50], szAnswerDesc[255];
			hKeyValues.GetString("question", szQuestion, sizeof(szQuestion));
			hVotechangeMenu.SetTitle(szQuestion);
			if(hKeyValues.GotoFirstSubKey())
			{
				do
				{
					hKeyValues.GetString("description", szAnswerDesc, sizeof(szAnswerDesc));
					hKeyValues.GetSectionName(szKeyName, sizeof(szKeyName));
					hVotechangeMenu.AddItem(szKeyName, szAnswerDesc);
				}
				while(hKeyValues.GotoNextKey());
			}
		}
		hVotechangeMenu.ExitButton = true;
		hVotechangeMenu.Display(iClient, 25);
	}
	
	return Plugin_Handled;
}

public int VotechangeMenu_Handler(Menu hMenu, MenuAction action, int iClient, int iItem)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			int iStyle;
			char szAuthId[50], szAnwer[100], szItem[50];
			hMenu.GetItem(iItem, szItem, sizeof(szItem), iStyle, szAnwer, sizeof(szAnwer));
			GetClientAuthId(iClient, AuthId_Engine, szAuthId, sizeof(szAuthId), true);
			
			if(g_hDataBase != null)
			{
				char szQuery[100];
				FormatEx(szQuery, sizeof(szQuery), "SELECT `steamid` FROM `votechange` WHERE `steamid` = '%s'", szAuthId);
				ArrayList hQueryData = new ArrayList(ByteCountToCells(150));
				hQueryData.PushString(szAuthId);
				hQueryData.PushString(szAnwer);
				hQueryData.Push(iClient);
				
				g_hDataBase.Query(SQL_Callback_CheckSteamId, szQuery, hQueryData);
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
			char szItemInfo[10];
			hMenu.GetItem(iItem, szItemInfo, sizeof(szItemInfo));
			
			if(StrEqual(szItemInfo, "agree", true))
			{
				char szClearQuery[100];
				FormatEx(szClearQuery, sizeof(szClearQuery), "DELETE FROM `votechange`");
				g_hDataBase.Query(SQL_Callback_Clear, szClearQuery, iClient);
			}
			else
			{
				RedisplayAdminMenu(g_hAdminMenu, iClient);
			}
		}
	}
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

public void SQL_CountTransaction_Success(Database hDatabase, ArrayList Data, int iNumQueries, DBResultSet[] results, any[] QueryData)
{
	Menu hVotechangeResultsMenu = new Menu(VotechangeResult_Handler);
	hVotechangeResultsMenu.ExitButton = true;
	hVotechangeResultsMenu.ExitBackButton = true;
	hVotechangeResultsMenu.SetTitle("Статистика голосов:");
	char szResultString[255], szAnswer[255], szTempItem[10];
	
	for(int i = 0; i < iNumQueries; i++)
	{
		if(results[i].FetchRow())
		{
			Data.GetString(i + 1, szAnswer, sizeof(szAnswer));
			FormatEx(szResultString, sizeof(szResultString), "%s - %i человек(а)", szAnswer, results[i].FetchInt(0));
			FormatEx(szTempItem, sizeof(szTempItem), "item%i", i);
			hVotechangeResultsMenu.AddItem(szTempItem, szResultString, ITEMDRAW_DISABLED);
		}
	}
	hVotechangeResultsMenu.Display(Data.Get(0), 25);
	delete Data;
}

public void SQL_CountTransaction_Failure(Database hDatabase, ArrayList Data, int iNumQueries, const char[] szError, int iFailIndex, any[] QueryData)
{
	LogError("SQL_TxnCallback_Failure: %s", szError);
}

public void SQL_Callback_List(Database hDatabase, DBResultSet results, const char[] sError, int iClient)
{
	if(sError[0])
	{
		LogError("SQL_Callback_List: %s", sError);
		return;
	}
	else
	{
		char szTempMenuItem[255], szItemName[10], szNick[150], szChoice[100];
		Menu hVotechangeList = new Menu(VotechangeList_Handler);
		hVotechangeList.SetTitle("Список проголосовавших:");
		hVotechangeList.ExitButton = true;
		hVotechangeList.ExitBackButton = true;
		
		for(int i = 1; results.FetchRow(); i++)
		{
			results.FetchString(0, szNick, sizeof(szNick));
			results.FetchString(1, szChoice, sizeof(szChoice));
			FormatEx(szTempMenuItem, sizeof(szTempMenuItem), "%s - %s", szNick, szChoice);
			FormatEx(szItemName, sizeof(szItemName), "item%i", i);
			hVotechangeList.AddItem(szItemName, szTempMenuItem, ITEMDRAW_DISABLED);
		}
		hVotechangeList.Display(iClient, 30);
	}
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
		PrintToChat(iClient, "[VoteChange]: База данных успешно очищена.");
	}
}

public void SQL_Callback_CheckSteamId(Database hDatabase, DBResultSet results, const char[] sError, ArrayList hDataList)
{
	if(sError[0])
	{
		LogError("SQL_Callback_CheckSteamId: %s", sError);
		return;
	}
	else
	{
		char szSQL_InsertClientData[256], szSQL_UpdateClientData[256], szNickname[255], szClientAuthId[50], szChoice[255];
		hDataList.GetString(0, szClientAuthId, sizeof(szClientAuthId));
		hDataList.GetString(1, szChoice, sizeof(szChoice));
		FormatEx(szNickname, sizeof(szNickname), "%N", hDataList.Get(2));
		FormatEx(szSQL_InsertClientData, sizeof(szSQL_InsertClientData), "INSERT INTO `votechange` (steamid, nickname, choice) VALUES ('%s', '%s', '%s')", szClientAuthId, szNickname, szChoice);
		FormatEx(szSQL_UpdateClientData, sizeof(szSQL_UpdateClientData), "UPDATE `votechange` SET `nickname` = '%s', `choice` = '%s' WHERE `steamid` = '%s' ", szNickname, szChoice, szClientAuthId);
		
		if(results.RowCount == 0)
		{	
			g_hDataBase.Query(SQL_Callback_InsertClientData, szSQL_InsertClientData, hDataList.Get(2));
		}
		else
		{
			g_hDataBase.Query(SQL_Callback_UpdateClientData, szSQL_UpdateClientData, hDataList.Get(2));
		}
	}
	
	delete hDataList;
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
		PrintToChat(iClient, "[VoteChange]: Вы успешно проголосовали. Благодарим за внимание!");
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
		PrintToChat(iClient, "[VoteChange]: Ваш голос успешно обновлён. Благодарим за внимание!");
	}
}
