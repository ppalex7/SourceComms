#pragma semicolon 1

#include <sourcemod>
#include <basecomm>
#include "include/sourcecomms.inc"

#undef REQUIRE_PLUGIN
#include <adminmenu>
#include <updater>

#define UNBLOCK_FLAG ADMFLAG_CUSTOM2
#define DATABASE "sourcecomms"

#define DEBUG
#define LOG_QUERIES

// Do not edit below this line //
//-----------------------------//

#define PLUGIN_VERSION "0.9.135"
#define PREFIX "\x04[SourceComms]\x01 "

#define UPDATE_URL    "http://z.tf2news.ru/repo/sc-updatefile.txt"

#define MAX_TIME_MULTI 10

#define NOW 0
#define TYPE_MUTE 1
#define TYPE_GAG 2
#define TYPE_SILENCE 3
#define TYPE_UNMUTE 4
#define TYPE_UNGAG 5
#define TYPE_UNSILENCE 6

#define MAX_REASONS 32
#define DISPLAY_SIZE 64
#define REASON_SIZE 192
new iNumReasons;
new String:g_sReasonDisplays[MAX_REASONS][DISPLAY_SIZE], String:g_sReasonKey[MAX_REASONS][REASON_SIZE];

#define MAX_TIMES 32
new iNumTimes, g_iTimeMinutes[MAX_TIMES];
new String:g_sTimeDisplays[MAX_TIMES][DISPLAY_SIZE];

enum State /* ConfigState */
{
	ConfigStateNone = 0,
	ConfigStateConfig,
	ConfigStateReasons,
	ConfigStateTimes,
	ConfigStateServers,
}
enum DatabaseState /* Database connection state */
{
	DatabaseState_None = 0,
	DatabaseState_Wait,
	DatabaseState_Connecting,
	DatabaseState_Connected,
}

new DatabaseState:g_DatabaseState;
new g_iConnectLock = 0;
new g_iSequence    = 0;

new State:ConfigState;
new Handle:ConfigParser;

new Handle:hTopMenu = INVALID_HANDLE;

/* Cvar handle*/
new Handle:CvarHostIp;
new Handle:CvarPort;

new String:ServerIp[24];
new String:ServerPort[7];
new String:DatabasePrefix[10] = "sb";

/* Database handle */
new Handle:g_hDatabase;
new Handle:SQLiteDB;

/* Datapack and Timer handles */
new Handle:g_hPlayerRecheck[MAXPLAYERS + 1] = {INVALID_HANDLE, ...};
new Handle:g_hGagExpireTimer[MAXPLAYERS + 1] = {INVALID_HANDLE, ...};
new Handle:g_hMuteExpireTimer[MAXPLAYERS + 1] = {INVALID_HANDLE, ...};

/* Player ban check status */
new bool:g_bPlayerStatus[MAXPLAYERS + 1];

/* Log Stuff */
new String:logFile[256];
#if defined LOG_QUERIES
new String:logQuery[256];
#endif

new Float:RetryTime = 15.0;
new DefaultTime = 30;
new DisUBImCheck = 0;
new ConsoleImmunity = 0;
new ConfigMaxLength = 0;
new ConfigWhiteListOnly = 0;

new serverID = 0;

/* List menu */
enum PeskyPanels
{
	curTarget,
	curIndex,
	viewingMute,
	viewingGag,
	viewingList,
}
new g_iPeskyPanels[MAXPLAYERS + 1][PeskyPanels];

new String:g_sName[MAXPLAYERS + 1][MAX_NAME_LENGTH];

new bType:g_MuteType[MAXPLAYERS + 1];
new g_iMuteTime[MAXPLAYERS + 1];
new g_iMuteLength[MAXPLAYERS + 1]; // in sec
new g_iMuteLevel[MAXPLAYERS + 1]; // immunity level of admin
new String:g_sMuteAdmin[MAXPLAYERS + 1][MAX_NAME_LENGTH];
new String:g_sMuteReason[MAXPLAYERS + 1][256];

new bType:g_GagType[MAXPLAYERS + 1];
new g_iGagTime[MAXPLAYERS + 1];
new g_iGagLength[MAXPLAYERS + 1]; // in sec
new g_iGagLevel[MAXPLAYERS + 1]; // immunity level of admin
new String:g_sGagAdmin[MAXPLAYERS + 1][MAX_NAME_LENGTH];
new String:g_sGagReason[MAXPLAYERS + 1][256];

new Handle:g_hServersWhiteList = INVALID_HANDLE;

public Plugin:myinfo =
{
	name = "SourceComms",
	author = "Alex",
	description = "Advanced punishments management for the Source engine in SourceBans style",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=207176"
};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	CreateNative("SourceComms_SetClientMute", 		Native_SetClientMute);
	CreateNative("SourceComms_SetClientGag",        Native_SetClientGag);
	CreateNative("SourceComms_GetClientMuteType",	Native_GetClientMuteType);
	CreateNative("SourceComms_GetClientGagType",	Native_GetClientGagType);
	RegPluginLibrary("sourcecomms");
	return APLRes_Success;
}

public OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("sourcecomms.phrases");

	new Handle:hTemp = INVALID_HANDLE;
	if (LibraryExists("adminmenu") && ((hTemp = GetAdminTopMenu()) != INVALID_HANDLE))
		OnAdminMenuReady(hTemp);

	CvarHostIp = FindConVar("hostip");
	CvarPort = FindConVar("hostport");
	g_hServersWhiteList = CreateArray();

	CreateConVar("sourcecomms_version", PLUGIN_VERSION, _, FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	AddCommandListener(CommandGag, "sm_gag");
	AddCommandListener(CommandUnGag, "sm_ungag");
	AddCommandListener(CommandMute, "sm_mute");
	AddCommandListener(CommandUnMute, "sm_unmute");
	AddCommandListener(CommandSilence, "sm_silence");
	AddCommandListener(CommandUnSilence, "sm_unsilence");
	RegServerCmd("sc_fw_block", FWBlock, "Blocking player comms by command from sourceban web site", FCVAR_PLUGIN);
	RegServerCmd("sc_fw_ungag", FWUngag, "Ungagging player by command from sourceban web site", FCVAR_PLUGIN);
	RegServerCmd("sc_fw_unmute",FWUnmute, "Unmuting player by command from sourceban web site", FCVAR_PLUGIN);
	RegConsoleCmd("sm_comms", CommandComms, "Shows current player communications status", FCVAR_PLUGIN);

	HookEvent("player_changename", Event_OnPlayerName, EventHookMode_Post);

	BuildPath(Path_SM, logFile, sizeof(logFile), "logs/sourcecomms.log");

	#if defined LOG_QUERIES
	BuildPath(Path_SM, logQuery, sizeof(logQuery), "logs/sourcecomms-q.log");
	#endif

	#if defined DEBUG
		LogToFile(logFile, "Plugin loading. Version %s", PLUGIN_VERSION);
	#endif

	// Catch config error
	if (!SQL_CheckConfig(DATABASE))
	{
		LogToFile(logFile, "Database failure: Could not find Database conf %s", DATABASE);
		SetFailState("Database failure: Could not find Database conf  %s", DATABASE);
		return;
	}
	DB_Connect();

	InitializeBackupDB();

	ServerInfo();

	if (LibraryExists("updater"))
    {
		Updater_AddPlugin(UPDATE_URL);
	}
}

public OnLibraryAdded(const String:name[])
{
	if (StrEqual(name, "updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
}

public Updater_OnPluginUpdated()
{
	LogToFile(logFile, "Plugin updated. Old version was %s. Now reloading.", PLUGIN_VERSION);

	ReloadPlugin();
}

public OnLibraryRemoved(const String:name[])
{
	if (StrEqual(name, "adminmenu"))
		hTopMenu = INVALID_HANDLE;
}

public OnMapStart()
{
	ReadConfig();
}

// CLIENT CONNECTION FUNCTIONS //

public OnClientDisconnect(client)
{
	if (g_hPlayerRecheck[client] != INVALID_HANDLE && CloseHandle(g_hPlayerRecheck[client]))
		g_hPlayerRecheck[client] = INVALID_HANDLE;

	CloseMuteExpireTimer(client);
	CloseGagExpireTimer(client);
}

public bool:OnClientConnect(client, String:rejectmsg[], maxlen)
{
	g_bPlayerStatus[client] = false;
	return true;
}

public OnClientConnected(client)
{
	g_sName[client][0] = '\0';

	MarkClientAsUnMuted(client);
	MarkClientAsUnGagged(client);
}

public OnClientPostAdminCheck(client)
{
	decl String:clientAuth[64];
	GetClientAuthString(client, clientAuth, sizeof(clientAuth));
	GetClientName(client, g_sName[client], sizeof(g_sName[]));

	/* Do not check bots nor check player with lan steamid. */
	if (clientAuth[0] == 'B' || clientAuth[9] == 'L' || !DB_Connect())
	{
		g_bPlayerStatus[client] = true;
		return;
	}

	if (client > 0 && IsClientInGame(client) && !IsFakeClient(client))
	{
		new String:sClAuthYZEscaped[sizeof(clientAuth) * 2 + 1];
		SQL_EscapeString(g_hDatabase, clientAuth[8], sClAuthYZEscaped, sizeof(sClAuthYZEscaped));

		decl String:Query[512];
		FormatEx(Query, sizeof(Query), "SELECT (c.ends - UNIX_TIMESTAMP()) as remaining, c.length, c.type, c.created, c.reason, a.user, IF (a.immunity>=g.immunity, a.immunity, IFNULL(g.immunity,0)) as immunity, c.aid, c.sid FROM %s_comms c LEFT JOIN %s_admins a ON a.aid=c.aid LEFT JOIN %s_srvgroups g ON g.name = a.srv_group WHERE RemoveType IS NULL AND c.authid REGEXP '^STEAM_[0-9]:%s$' AND (length = '0' OR ends > UNIX_TIMESTAMP())",
				DatabasePrefix, DatabasePrefix, DatabasePrefix, sClAuthYZEscaped);
		#if defined LOG_QUERIES
			LogToFile(logQuery, "Checking blocks for: %s. QUERY: %s", clientAuth, Query);
		#endif
		SQL_TQuery(g_hDatabase, VerifyBlocks, Query, GetClientUserId(client), DBPrio_High);
	}
}

// OTHER CLIENT CODE //

public Action:Event_OnPlayerName(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (client > 0 && IsClientInGame(client))
		GetEventString(event, "newname", g_sName[client], sizeof(g_sName[]));
}

public BaseComm_OnClientMute(client, bool:muteState)
{
	if (client > 0 && client <= MaxClients)
	{
		if (muteState)
		{
			if (g_MuteType[client] == bNot)
			{
				MarkClientAsMuted(client, _, _, _, ConsoleImmunity, "Muted through BaseComm natives");
				SavePunishment(_, client, TYPE_MUTE, _, "Muted through BaseComm natives");
			}
		}
		else
		{
			if (g_MuteType[client] > bNot)
			{
				MarkClientAsUnMuted(client);
			}
		}
	}
}

public BaseComm_OnClientGag(client, bool:gagState)
{
	if (client > 0 && client <= MaxClients)
	{
		if (gagState)
		{
			if (g_GagType[client] == bNot)
			{
				MarkClientAsGagged(client, _, _, _, ConsoleImmunity, "Gagged through BaseComm natives");
				SavePunishment(_, client, TYPE_GAG, _, "Gagged through BaseComm natives");
			}
		}
		else
		{
			if (g_GagType[client] > bNot)
			{
				MarkClientAsUnGagged(client);
			}
		}
	}
}

// COMMAND CODE //

public Action:CommandComms(client, args)
{
	if (!client)
	{
		ReplyToCommand(client, "%s%t", PREFIX, "CommandComms_na");
		return Plugin_Continue;
	}

	if (g_MuteType[client] > bNot || g_GagType[client] > bNot)
		AdminMenu_ListTarget(client, client, 0);
	else
		ReplyToCommand(client,  "%s%t", PREFIX, "CommandComms_nb");

	return Plugin_Handled;
}

public Action:FWBlock(args)
{
	new String:arg_string[256], String:sArg[3][64];
	GetCmdArgString(arg_string, sizeof(arg_string));

	new type, length;
	if(ExplodeString(arg_string, " ", sArg, 3, 64) != 3 || !StringToIntEx(sArg[0], type) || type < 1 || type > 3 || !StringToIntEx(sArg[1], length))
	{
		LogToFile(logFile, "Wrong usage of sc_fw_block");
		return Plugin_Stop;
	}

	LogToFile(logFile, "Received block command from web: steam %s, type %d, length %d", sArg[2], type, length);

	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsClientAuthorized(i) && !IsFakeClient(i))
		{
			decl String:clientAuth[64];
			GetClientAuthString(i, clientAuth, sizeof(clientAuth));
			if (strcmp(clientAuth, sArg[2], false) == 0)
			{
				#if defined DEBUG
				LogToFile(logFile, "Catched %s for blocking from web", clientAuth);
				#endif

				if (g_MuteType[i] == bNot && (type == 1 || type == 3))
				{
					PerformMute(i, _, length / 60, _, ConsoleImmunity, _);
					PrintToChat(i, "%s%t", PREFIX, "Muted on connect");
					LogToFile(logFile, "%s is muted from web", clientAuth);
				}
				if (g_GagType[i] == bNot && (type == 2 || type == 3))
				{
					PerformGag(i, _, length / 60, _, ConsoleImmunity, _);
					PrintToChat(i, "%s%t", PREFIX, "Gagged on connect");
					LogToFile(logFile, "%s is gagged from web", clientAuth);
				}
				break;
			}
		}
	}

	return Plugin_Handled;
}

public Action:FWUngag(args)
{
	new String:arg_string[256], String:sArg[1][64];
	GetCmdArgString(arg_string, sizeof(arg_string));
	if(!ExplodeString(arg_string, " ", sArg, 1, 64))
	{
		LogToFile(logFile, "Wrong usage of sc_fw_ungag");
		return Plugin_Stop;
	}

	LogToFile(logFile, "Received ungag command from web: steam %s", sArg[0]);

	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsClientAuthorized(i) && !IsFakeClient(i))
		{
			decl String:clientAuth[64];
			GetClientAuthString(i, clientAuth, sizeof(clientAuth));
			if (strcmp(clientAuth, sArg[0], false) == 0)
			{
				#if defined DEBUG
				LogToFile(logFile, "Catched %s for ungagging from web", clientAuth);
				#endif

				if (g_GagType[i] > bNot)
				{
					PerformUnGag(i);
					PrintToChat(i, "%s%t", PREFIX, "FWUngag");
					LogToFile(logFile, "%s is ungagged from web", clientAuth);
				}
				else
					LogToFile(logFile, "Can't ungag %s from web, isn't gagged", clientAuth);
				break;
			}
		}
	}
	return Plugin_Handled;
}

public Action:FWUnmute(args)
{
	new String:arg_string[256], String:sArg[1][64];
	GetCmdArgString(arg_string, sizeof(arg_string));
	if(!ExplodeString(arg_string, " ", sArg, 1, 64))
	{
		LogToFile(logFile, "Wrong usage of sc_fw_ungag");
		return Plugin_Stop;
	}

	LogToFile(logFile, "Received unmute command from web: steam %s", sArg[0]);

	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsClientAuthorized(i) && !IsFakeClient(i))
		{
			decl String:clientAuth[64];
			GetClientAuthString(i, clientAuth, sizeof(clientAuth));
			if (strcmp(clientAuth, sArg[0], false) == 0)
			{
				#if defined DEBUG
				LogToFile(logFile, "Catched %s for unmuting from web", clientAuth);
				#endif

				if (g_MuteType[i] > bNot)
				{
					PerformUnMute(i);
					PrintToChat(i, "%s%t", PREFIX, "FWUnmute");
					LogToFile(logFile, "%s is unmuted from web", clientAuth);
				}
				else
					LogToFile(logFile, "Can't unmute %s from web, isn't muted", clientAuth);
				break;
			}
		}
	}
	return Plugin_Handled;
}

public Action:CommandGag(client, const String:command[], args)
{
	if (client && !CheckCommandAccess(client, "sm_gag", ADMFLAG_CHAT))
		return Plugin_Continue;

	if (args < 1)
	{
		ReplyToCommand(client, "%sUsage: sm_gag <#userid|name> [time|0] [reason]", PREFIX);
		ReplyToCommand(client, "%s%t", PREFIX, "Usage_time", DefaultTime);
		return Plugin_Stop;
	}

	new String:sBuffer[256];
	GetCmdArgString(sBuffer, sizeof(sBuffer));
	CreateBlock(client, _, _, TYPE_GAG, _, sBuffer);

	return Plugin_Stop;
}

public Action:CommandMute(client, const String:command[], args)
{
	if (client && !CheckCommandAccess(client, "sm_mute", ADMFLAG_CHAT))
		return Plugin_Continue;

	if (args < 1)
	{
		ReplyToCommand(client, "%sUsage: sm_mute <#userid|name> [time|0] [reason]", PREFIX);
		ReplyToCommand(client, "%s%t", PREFIX, "Usage_time", DefaultTime);
		return Plugin_Stop;
	}

	new String:sBuffer[256];
	GetCmdArgString(sBuffer, sizeof(sBuffer));
	CreateBlock(client, _, _, TYPE_MUTE, _, sBuffer);

	return Plugin_Stop;
}

public Action:CommandSilence(client, const String:command[], args)
{
	if (client && !CheckCommandAccess(client, "sm_silence", ADMFLAG_CHAT))
		return Plugin_Continue;

	if (args < 1)
	{
		ReplyToCommand(client, "%sUsage: sm_silence <#userid|name> [time|0] [reason]", PREFIX);
		ReplyToCommand(client, "%s%t", PREFIX, "Usage_time", DefaultTime);
		return Plugin_Stop;
	}

	new String:sBuffer[256];
	GetCmdArgString(sBuffer, sizeof(sBuffer));
	CreateBlock(client, _, _, TYPE_SILENCE, _, sBuffer);

	return Plugin_Stop;
}

public Action:CommandUnGag(client, const String:command[], args)
{
	if (client && !CheckCommandAccess(client, "sm_ungag", ADMFLAG_CHAT))
		return Plugin_Continue;

	if (args < 1)
	{
		ReplyToCommand(client, "%sUsage: sm_ungag <#userid|name> [reason]", PREFIX);
		return Plugin_Stop;
	}

	PrepareUnBlock(client, TYPE_GAG, args);
	return Plugin_Stop;
}

public Action:CommandUnMute(client, const String:command[], args)
{
	if (client && !CheckCommandAccess(client, "sm_unmute", ADMFLAG_CHAT))
		return Plugin_Continue;

	if (args < 1)
	{
		ReplyToCommand(client, "%sUsage: sm_unmute <#userid|name> [reason]", PREFIX);
		return Plugin_Stop;
	}

	PrepareUnBlock(client, TYPE_MUTE, args);
	return Plugin_Stop;
}

public Action:CommandUnSilence(client, const String:command[], args)
{
	if (client && !CheckCommandAccess(client, "sm_unsilence", ADMFLAG_CHAT))
		return Plugin_Continue;

	if (args < 1)
	{
		ReplyToCommand(client, "%sUsage: sm_unsilence <#userid|name> [reason]", PREFIX);
		return Plugin_Stop;
	}

	PrepareUnBlock(client, TYPE_SILENCE, args);
	return Plugin_Stop;
}

public Action:PrepareUnBlock(client, type_block, args)
{
	#if defined DEBUG
		LogToFile(logFile, "PrepareUnBlock(cl %L, type %d)", client, type_block);
	#endif

	new String:sBuffer[256], String:sArg[3][192];
	GetCmdArgString(sBuffer, sizeof(sBuffer));

	if (ExplodeString(sBuffer, "\"", sArg, 3, 192, true) == 3 && strlen(sArg[0]) == 0)
	{
		TrimString(sArg[2]);
		sArg[0] = sArg[1];		// target name
		sArg[1] = sArg[2]; 		// reason; sArg[2] - not in use
	}
	else
	{
		ExplodeString(sBuffer, " ", sArg, 2, 192, true);
	}

	// Get the target, find target returns a message on failure so we do not
	new target = FindTarget(client, sArg[0], true);
	if (target == -1)
		return Plugin_Stop;

	#if defined DEBUG
		LogToFile(logFile, "Calling ProcessUnBlock cl %d, target %d, type %d, reason %s", client, target, type_block, sArg[1]);
	#endif

	ProcessUnBlock(client, target, type_block, sArg[1]);
	return Plugin_Stop;
}

// MENU CODE //

public OnAdminMenuReady(Handle:topmenu)
{
	/* Block us from being called twice */
	if (topmenu == hTopMenu)
		return;

	/* Save the Handle */
	hTopMenu = topmenu;

	new TopMenuObject:MenuObject = AddToTopMenu(hTopMenu, "sourcecomm_cmds", TopMenuObject_Category, Handle_Commands, INVALID_TOPMENUOBJECT);
	if (MenuObject == INVALID_TOPMENUOBJECT)
		return;

	AddToTopMenu(hTopMenu, "sourcecomm_gag", TopMenuObject_Item, Handle_MenuGag, MenuObject, "sm_gag", ADMFLAG_CHAT);
	AddToTopMenu(hTopMenu, "sourcecomm_ungag", TopMenuObject_Item, Handle_MenuUnGag, MenuObject, "sm_ungag", ADMFLAG_CHAT);
	AddToTopMenu(hTopMenu, "sourcecomm_mute", TopMenuObject_Item, Handle_MenuMute, MenuObject, "sm_mute", ADMFLAG_CHAT);
	AddToTopMenu(hTopMenu, "sourcecomm_unmute", TopMenuObject_Item, Handle_MenuUnMute, MenuObject, "sm_unmute", ADMFLAG_CHAT);
	AddToTopMenu(hTopMenu, "sourcecomm_silence", TopMenuObject_Item, Handle_MenuSilence, MenuObject, "sm_silence", ADMFLAG_CHAT);
	AddToTopMenu(hTopMenu, "sourcecomm_unsilence", TopMenuObject_Item, Handle_MenuUnSilence, MenuObject, "sm_unsilence", ADMFLAG_CHAT);
	AddToTopMenu(hTopMenu, "sourcecomm_list", TopMenuObject_Item, Handle_MenuList, MenuObject, "sm_commlist", ADMFLAG_CHAT);
}

public Handle_Commands(Handle:menu, TopMenuAction:action, TopMenuObject:object_id, param1, String:buffer[], maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption:
			Format(buffer, maxlength, "%T", "AdminMenu_Main", param1);
		case TopMenuAction_DisplayTitle:
			Format(buffer, maxlength, "%T", "AdminMenu_Select_Main", param1);
	}
}

public Handle_MenuGag(Handle:menu, TopMenuAction:action, TopMenuObject:object_id, param1, String:buffer[], maxlength)
{
	if (action == TopMenuAction_DisplayOption)
		Format(buffer, maxlength, "%T", "AdminMenu_Gag", param1);
	else if (action == TopMenuAction_SelectOption)
		AdminMenu_Target(param1, TYPE_GAG);
}

public Handle_MenuUnGag(Handle:menu, TopMenuAction:action, TopMenuObject:object_id, param1, String:buffer[], maxlength)
{
	if (action == TopMenuAction_DisplayOption)
		Format(buffer, maxlength, "%T", "AdminMenu_UnGag", param1);
	else if (action == TopMenuAction_SelectOption)
		AdminMenu_Target(param1, TYPE_UNGAG);
}

public Handle_MenuMute(Handle:menu, TopMenuAction:action, TopMenuObject:object_id, param1, String:buffer[], maxlength)
{
	if (action == TopMenuAction_DisplayOption)
		Format(buffer, maxlength, "%T", "AdminMenu_Mute", param1);
	else if (action == TopMenuAction_SelectOption)
		AdminMenu_Target(param1, TYPE_MUTE);
}

public Handle_MenuUnMute(Handle:menu, TopMenuAction:action, TopMenuObject:object_id, param1, String:buffer[], maxlength)
{
	if (action == TopMenuAction_DisplayOption)
		Format(buffer, maxlength, "%T", "AdminMenu_UnMute", param1);
	else if (action == TopMenuAction_SelectOption)
		AdminMenu_Target(param1, TYPE_UNMUTE);
}

public Handle_MenuSilence(Handle:menu, TopMenuAction:action, TopMenuObject:object_id, param1, String:buffer[], maxlength)
{
	if (action == TopMenuAction_DisplayOption)
		Format(buffer, maxlength, "%T", "AdminMenu_Silence", param1);
	else if (action == TopMenuAction_SelectOption)
		AdminMenu_Target(param1, TYPE_SILENCE);
}

public Handle_MenuUnSilence(Handle:menu, TopMenuAction:action, TopMenuObject:object_id, param1, String:buffer[], maxlength)
{
	if (action == TopMenuAction_DisplayOption)
		Format(buffer, maxlength, "%T", "AdminMenu_UnSilence", param1);
	else if (action == TopMenuAction_SelectOption)
		AdminMenu_Target(param1, TYPE_UNSILENCE);
}

public Handle_MenuList(Handle:menu, TopMenuAction:action, TopMenuObject:object_id, param1, String:buffer[], maxlength)
{
	if (action == TopMenuAction_DisplayOption)
		Format(buffer, maxlength, "%T", "AdminMenu_List", param1);
	else if (action == TopMenuAction_SelectOption)
	{
		g_iPeskyPanels[param1][viewingList] = false;
		AdminMenu_List(param1, 0);
	}
}

AdminMenu_Target(client, type)
{
	decl String:Title[192], String:Option[32];
	switch(type)
	{
		case TYPE_GAG:
			Format(Title, sizeof(Title), "%T", "AdminMenu_Select_Gag", client);
		case TYPE_MUTE:
			Format(Title, sizeof(Title), "%T", "AdminMenu_Select_Mute", client);
		case TYPE_SILENCE:
			Format(Title, sizeof(Title), "%T", "AdminMenu_Select_Silence", client);
		case TYPE_UNGAG:
			Format(Title, sizeof(Title), "%T", "AdminMenu_Select_Ungag", client);
		case TYPE_UNMUTE:
			Format(Title, sizeof(Title), "%T", "AdminMenu_Select_Unmute", client);
		case TYPE_UNSILENCE:
			Format(Title, sizeof(Title), "%T", "AdminMenu_Select_Unsilence", client);
	}

	new Handle:hMenu = CreateMenu(MenuHandler_MenuTarget);	// Common menu - players list. Almost full for blocking, and almost empty for unblocking
	SetMenuTitle(hMenu, Title);
	SetMenuExitBackButton(hMenu, true);

	new iClients;
	if (type <= 3)	// Mute, gag, silence
	{
		for (new i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && !IsFakeClient(i))
			{
				switch(type)
				{
					case TYPE_MUTE:
						if (g_MuteType[i] > bNot)
							continue;
					case TYPE_GAG:
						if (g_GagType[i] > bNot)
							continue;
					case TYPE_SILENCE:
						if (g_MuteType[i] > bNot || g_GagType[i] > bNot)
							continue;
				}
				iClients++;
				strcopy(Title, sizeof(Title), g_sName[i]);
				AdminMenu_GetPunishPhrase(client, i, Title, sizeof(Title));
				Format(Option, sizeof(Option), "%d %d", GetClientUserId(i), type);
				AddMenuItem(hMenu, Option, Title, (CanUserTarget(client, i) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED));
			}
		}
	}
	else		// UnMute, ungag, unsilence
	{
		for (new i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && !IsFakeClient(i))
			{
				switch(type)
				{
					case TYPE_UNMUTE:
					{
						if (g_MuteType[i] > bNot)
						{
							iClients++;
							strcopy(Title, sizeof(Title), g_sName[i]);
							Format(Option, sizeof(Option), "%d %d", GetClientUserId(i), type);
							AddMenuItem(hMenu, Option, Title, (CanUserTarget(client, i) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED));
						}
					}
					case TYPE_UNGAG:
					{
						if (g_GagType[i] > bNot)
						{
							iClients++;
							strcopy(Title, sizeof(Title), g_sName[i]);
							Format(Option, sizeof(Option), "%d %d", GetClientUserId(i), type);
							AddMenuItem(hMenu, Option, Title, (CanUserTarget(client, i) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED));
						}
					}
					case TYPE_UNSILENCE:
					{
						if (g_MuteType[i] > bNot && g_GagType[i] > bNot)
						{
							iClients++;
							strcopy(Title, sizeof(Title), g_sName[i]);
							Format(Option, sizeof(Option), "%d %d", GetClientUserId(i), type);
							AddMenuItem(hMenu, Option, Title, (CanUserTarget(client, i) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED));
						}
					}
				}
			}
		}
	}
	if (!iClients)
	{
		switch(type)
		{
			case TYPE_UNMUTE:
				Format(Title, sizeof(Title), "%T", "AdminMenu_Option_Mute_Empty", client);
			case TYPE_UNGAG:
				Format(Title, sizeof(Title), "%T", "AdminMenu_Option_Gag_Empty", client);
			case TYPE_UNSILENCE:
				Format(Title, sizeof(Title), "%T", "AdminMenu_Option_Silence_Empty", client);
			default:
				Format(Title, sizeof(Title), "%T", "AdminMenu_Option_Empty", client);
		}
		AddMenuItem(hMenu, "0", Title, ITEMDRAW_DISABLED);
	}

	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public MenuHandler_MenuTarget(Handle:menu, MenuAction:action, param1, param2)
{
	switch(action)
	{
		case MenuAction_End:
			CloseHandle(menu);
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack && hTopMenu != INVALID_HANDLE)
				DisplayTopMenu(hTopMenu, param1, TopMenuPosition_LastCategory);
		}
		case MenuAction_Select:
		{
			decl String:Option[32], String:Temp[2][8];
			GetMenuItem(menu, param2, Option, sizeof(Option));
			ExplodeString(Option, " ", Temp, 2, 8);
			new target = GetClientOfUserId(StringToInt(Temp[0]));

			if (Bool_ValidMenuTarget(param1, target))
			{
				new type = StringToInt(Temp[1]);
				if (type <= 3)
				{
					AdminMenu_Duration(param1, target, type);
				}
				else
				{
					switch(type)
					{
						case TYPE_UNMUTE:
							ProcessUnBlock(param1, target, TYPE_MUTE, "");
						case TYPE_UNGAG:
							ProcessUnBlock(param1, target, TYPE_GAG, "");
						case TYPE_UNSILENCE:
							ProcessUnBlock(param1, target, TYPE_SILENCE, "");
					}
				}
			}
		}
	}
}

AdminMenu_Duration(client, target, type)
{
	new Handle:hMenu = CreateMenu(MenuHandler_MenuDuration);
	decl String:sBuffer[192], String:sTemp[64];
	Format(sBuffer, sizeof(sBuffer), "%T", "AdminMenu_Title_Durations", client);
	SetMenuTitle(hMenu, sBuffer);
	SetMenuExitBackButton(hMenu, true);

	for (new i = 0; i <= iNumTimes; i++)
	{
		if (IsAllowedBlockLength(client, g_iTimeMinutes[i]))
		{
			Format(sTemp, sizeof(sTemp), "%d %d %d", GetClientUserId(target), type, i);	// TargetID TYPE_BLOCK index_of_Time
			AddMenuItem(hMenu, sTemp, g_sTimeDisplays[i]);
		}
	}

	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public MenuHandler_MenuDuration(Handle:menu, MenuAction:action, param1, param2)
{
	switch(action)
	{
		case MenuAction_End:
			CloseHandle(menu);
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack && hTopMenu != INVALID_HANDLE)
				DisplayTopMenu(hTopMenu, param1, TopMenuPosition_LastCategory);
		}
		case MenuAction_Select:
		{
			decl String:sOption[32], String:sTemp[3][8];
			GetMenuItem(menu, param2, sOption, sizeof(sOption));
			ExplodeString(sOption, " ", sTemp, 3, 8);
			// TargetID TYPE_BLOCK index_of_Time
			new target = GetClientOfUserId(StringToInt(sTemp[0]));

			if (Bool_ValidMenuTarget(param1, target))
			{
				new type = StringToInt(sTemp[1]);
				new lengthIndex = StringToInt(sTemp[2]);

				if (iNumReasons) // we have reasons to show
					AdminMenu_Reason(param1, target, type, lengthIndex);
				else
					CreateBlock(param1, target, g_iTimeMinutes[lengthIndex], type, "");
			}
		}
	}
}

AdminMenu_Reason(client, target, type, lengthIndex)
{
	new Handle:hMenu = CreateMenu(MenuHandler_MenuReason);
	decl String:sBuffer[192], String:sTemp[64];
	Format(sBuffer, sizeof(sBuffer), "%T", "AdminMenu_Title_Reasons", client);
	SetMenuTitle(hMenu, sBuffer);
	SetMenuExitBackButton(hMenu, true);

	for (new i = 0; i <= iNumReasons; i++)
	{
		Format(sTemp, sizeof(sTemp), "%d %d %d %d", GetClientUserId(target), type, i, lengthIndex);	// TargetID TYPE_BLOCK ReasonIndex LenghtIndex
		AddMenuItem(hMenu, sTemp, g_sReasonDisplays[i]);
	}

	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public MenuHandler_MenuReason(Handle:menu, MenuAction:action, param1, param2)
{
	switch(action)
	{
		case MenuAction_End:
			CloseHandle(menu);
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack && hTopMenu != INVALID_HANDLE)
				DisplayTopMenu(hTopMenu, param1, TopMenuPosition_LastCategory);
		}
		case MenuAction_Select:
		{
			decl String:sOption[64], String:sTemp[4][8];
			GetMenuItem(menu, param2, sOption, sizeof(sOption));
			ExplodeString(sOption, " ", sTemp, 4, 8);
			// TargetID TYPE_BLOCK ReasonIndex LenghtIndex
			new target = GetClientOfUserId(StringToInt(sTemp[0]));

			if (Bool_ValidMenuTarget(param1, target))
			{
				new type = StringToInt(sTemp[1]);
				new reasonIndex = StringToInt(sTemp[2]);
				new lengthIndex = StringToInt(sTemp[3]);
				new length;
				if (lengthIndex >= 0 && lengthIndex <= iNumTimes)
					length = g_iTimeMinutes[lengthIndex];
				else
				{
					length = DefaultTime;
					LogToFile(logFile, "It's a magic? wrong length index. using default time");
				}

				CreateBlock(param1, target, length, type, g_sReasonKey[reasonIndex]);
			}
		}
	}
}

AdminMenu_List(client, index)
{
	decl String:sTitle[192], String:sOption[32];
	Format(sTitle, sizeof(sTitle), "%T", "AdminMenu_Select_List", client);
	new iClients, Handle:hMenu = CreateMenu(MenuHandler_MenuList);
	SetMenuTitle(hMenu, sTitle);
	if (!g_iPeskyPanels[client][viewingList])
		SetMenuExitBackButton(hMenu, true);

	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && (g_MuteType[i] > bNot || g_GagType[i] > bNot))
		{
			iClients++;
			strcopy(sTitle, sizeof(sTitle), g_sName[i]);
			AdminMenu_GetPunishPhrase(client, i, sTitle, sizeof(sTitle));
			Format(sOption, sizeof(sOption), "%d", GetClientUserId(i));
			AddMenuItem(hMenu, sOption, sTitle);
		}
	}

	if (!iClients)
	{
		Format(sTitle, sizeof(sTitle), "%T", "ListMenu_Option_Empty", client);
		AddMenuItem(hMenu, "0", sTitle, ITEMDRAW_DISABLED);
	}

	DisplayMenuAtItem(hMenu, client, index, MENU_TIME_FOREVER);
}

public MenuHandler_MenuList(Handle:menu, MenuAction:action, param1, param2)
{
	switch(action)
	{
		case MenuAction_End:
			CloseHandle(menu);
		case MenuAction_Cancel:
		{
			if (!g_iPeskyPanels[param1][viewingList])
				if (param2 == MenuCancel_ExitBack && hTopMenu != INVALID_HANDLE)
					DisplayTopMenu(hTopMenu, param1, TopMenuPosition_LastCategory);
		}
		case MenuAction_Select:
		{
			decl String:sOption[32];
			GetMenuItem(menu, param2, sOption, sizeof(sOption));
			new target = GetClientOfUserId(StringToInt(sOption));

			if (Bool_ValidMenuTarget(param1, target))
				AdminMenu_ListTarget(param1, target, GetMenuSelectionPosition());
			else
				AdminMenu_List(param1, GetMenuSelectionPosition());
		}
	}
}

AdminMenu_ListTarget(client, target, index, viewMute = 0, viewGag = 0)
{
	new userid = GetClientUserId(target), Handle:hMenu = CreateMenu(MenuHandler_MenuListTarget);
	decl String:sBuffer[192], String:sOption[32];
	SetMenuTitle(hMenu, g_sName[target]);
	SetMenuPagination(hMenu, MENU_NO_PAGINATION);
	SetMenuExitButton(hMenu, true);
	SetMenuExitBackButton(hMenu, false);

	if (g_MuteType[target] > bNot)
	{
		Format(sBuffer, sizeof(sBuffer), "%T", "ListMenu_Option_Mute", client);
		Format(sOption, sizeof(sOption), "0 %d %d %b %b", userid, index, viewMute, viewGag);
		AddMenuItem(hMenu, sOption, sBuffer);

		if (viewMute)
		{
			Format(sBuffer, sizeof(sBuffer), "%T", "ListMenu_Option_Admin", client, g_sMuteAdmin[target]);
			AddMenuItem(hMenu, "", sBuffer, ITEMDRAW_DISABLED);

			decl String:sMuteTemp[192], String:_sMuteTime[192];
			Format(sMuteTemp, sizeof(sMuteTemp), "%T", "ListMenu_Option_Duration", client);
			if (g_MuteType[target] == bPerm)
				Format(sBuffer, sizeof(sBuffer), "%s%T", sMuteTemp, "ListMenu_Option_Duration_Perm", client);
			else if (g_MuteType[target] == bTime)
				Format(sBuffer, sizeof(sBuffer), "%s%T", sMuteTemp, "ListMenu_Option_Duration_Time", client, g_iMuteLength[target]);
			else if (g_MuteType[target] == bSess)
				Format(sBuffer, sizeof(sBuffer), "%s%T", sMuteTemp, "ListMenu_Option_Duration_Temp", client);
			else
				Format(sBuffer, sizeof(sBuffer), "error");
			AddMenuItem(hMenu, "", sBuffer, ITEMDRAW_DISABLED);

			FormatTime(_sMuteTime, sizeof(_sMuteTime), NULL_STRING, g_iMuteTime[target]);
			Format(sBuffer, sizeof(sBuffer), "%T", "ListMenu_Option_Issue", client, _sMuteTime);
			AddMenuItem(hMenu, "", sBuffer, ITEMDRAW_DISABLED);

			Format(sMuteTemp, sizeof(sMuteTemp), "%T", "ListMenu_Option_Expire", client);
			if (g_MuteType[target] == bPerm)
				Format(sBuffer, sizeof(sBuffer), "%s%T", sMuteTemp, "ListMenu_Option_Expire_Perm", client);
			else if (g_MuteType[target] == bTime)
			{
				FormatTime(_sMuteTime, sizeof(_sMuteTime), NULL_STRING, (g_iMuteTime[target] + g_iMuteLength[target] * 60));
				Format(sBuffer, sizeof(sBuffer), "%s%T", sMuteTemp, "ListMenu_Option_Expire_Time", client, _sMuteTime);
			}
			else if (g_MuteType[target] == bSess)
				Format(sBuffer, sizeof(sBuffer), "%s%T", sMuteTemp, "ListMenu_Option_Expire_Temp_Reconnect", client);
			else
				Format(sBuffer, sizeof(sBuffer), "error");
			AddMenuItem(hMenu, "", sBuffer, ITEMDRAW_DISABLED);

			if (strlen(g_sMuteReason[target]) > 0)
			{
				Format(sBuffer, sizeof(sBuffer), "%T", "ListMenu_Option_Reason", client);
				Format(sOption, sizeof(sOption), "1 %d %d %b %b", userid, index, viewMute, viewGag);
				AddMenuItem(hMenu, sOption, sBuffer);
			}
			else
			{
				Format(sBuffer, sizeof(sBuffer), "%T", "ListMenu_Option_Reason_None", client);
				AddMenuItem(hMenu, "", sBuffer, ITEMDRAW_DISABLED);
			}
		}
	}

	if (g_GagType[target] > bNot)
	{
		Format(sBuffer, sizeof(sBuffer), "%T", "ListMenu_Option_Gag", client);
		Format(sOption, sizeof(sOption), "2 %d %d %b %b", userid, index, viewMute, viewGag);
		AddMenuItem(hMenu, sOption, sBuffer);

		if (viewGag)
		{
			Format(sBuffer, sizeof(sBuffer), "%T", "ListMenu_Option_Admin", client, g_sGagAdmin[target]);
			AddMenuItem(hMenu, "", sBuffer, ITEMDRAW_DISABLED);

			decl String:sGagTemp[192], String:_sGagTime[192];
			Format(sGagTemp, sizeof(sGagTemp), "%T", "ListMenu_Option_Duration", client);
			if (g_GagType[target] == bPerm)
				Format(sBuffer, sizeof(sBuffer), "%s%T", sGagTemp, "ListMenu_Option_Duration_Perm", client);
			else if (g_GagType[target] == bTime)
				Format(sBuffer, sizeof(sBuffer), "%s%T", sGagTemp, "ListMenu_Option_Duration_Time", client, g_iGagLength[target]);
			else if (g_GagType[target] == bSess)
				Format(sBuffer, sizeof(sBuffer), "%s%T", sGagTemp, "ListMenu_Option_Duration_Temp", client);
			else
				Format(sBuffer, sizeof(sBuffer), "error");
			AddMenuItem(hMenu, "", sBuffer, ITEMDRAW_DISABLED);

			FormatTime(_sGagTime, sizeof(_sGagTime), NULL_STRING, g_iGagTime[target]);
			Format(sBuffer, sizeof(sBuffer), "%T", "ListMenu_Option_Issue", client, _sGagTime);
			AddMenuItem(hMenu, "", sBuffer, ITEMDRAW_DISABLED);

			Format(sGagTemp, sizeof(sGagTemp), "%T", "ListMenu_Option_Expire", client);
			if (g_GagType[target] == bPerm)
				Format(sBuffer, sizeof(sBuffer), "%s%T", sGagTemp, "ListMenu_Option_Expire_Perm", client);
			else if (g_GagType[target] == bTime)
			{
				FormatTime(_sGagTime, sizeof(_sGagTime), NULL_STRING, (g_iGagTime[target] + g_iGagLength[target] * 60));
				Format(sBuffer, sizeof(sBuffer), "%s%T", sGagTemp, "ListMenu_Option_Expire_Time", client, _sGagTime);
			}
			else if (g_GagType[target] == bSess)
				Format(sBuffer, sizeof(sBuffer), "%s%T", sGagTemp, "ListMenu_Option_Expire_Temp_Reconnect", client);
			else
				Format(sBuffer, sizeof(sBuffer), "error");
			AddMenuItem(hMenu, "", sBuffer, ITEMDRAW_DISABLED);

			if (strlen(g_sGagReason[target]) > 0)
			{
				Format(sBuffer, sizeof(sBuffer), "%T", "ListMenu_Option_Reason", client);
				Format(sOption, sizeof(sOption), "3 %d %d %b %b", userid, index, viewMute, viewGag);
				AddMenuItem(hMenu, sOption, sBuffer);
			}
			else
			{
				Format(sBuffer, sizeof(sBuffer), "%T", "ListMenu_Option_Reason_None", client);
				AddMenuItem(hMenu, "", sBuffer, ITEMDRAW_DISABLED);
			}
		}
	}

	g_iPeskyPanels[client][curIndex] = index;
	g_iPeskyPanels[client][curTarget] = target;
	g_iPeskyPanels[client][viewingGag] = viewGag;
	g_iPeskyPanels[client][viewingMute] = viewMute;
	DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

public MenuHandler_MenuListTarget(Handle:menu, MenuAction:action, param1, param2)
{
	switch(action)
	{
		case MenuAction_End:
			CloseHandle(menu);
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
				AdminMenu_List(param1, g_iPeskyPanels[param1][curIndex]);
		}
		case MenuAction_Select:
		{
			decl String:sOption[64], String:sTemp[5][8];
			GetMenuItem(menu, param2, sOption, sizeof(sOption));
			ExplodeString(sOption, " ", sTemp, 5, 8);

			new target = GetClientOfUserId(StringToInt(sTemp[1]));
			if (param1 == target || Bool_ValidMenuTarget(param1, target))
			{
				switch(StringToInt(sTemp[0]))
				{
					case 0:
						AdminMenu_ListTarget(param1, target, StringToInt(sTemp[2]), !(StringToInt(sTemp[3])), 0);
					case 1, 3:
						AdminMenu_ListTargetReason(param1, target, g_iPeskyPanels[param1][viewingMute], g_iPeskyPanels[param1][viewingGag]);
					case 2:
						AdminMenu_ListTarget(param1, target, StringToInt(sTemp[2]), 0, !(StringToInt(sTemp[4])));
				}
			}
			else
				AdminMenu_List(param1, StringToInt(sTemp[2]));

		}
	}
}

AdminMenu_ListTargetReason(client, target, showMute, showGag)
{
	decl String:sTemp[192], String:sBuffer[192];
	new Handle:hPanel = CreatePanel();
	SetPanelTitle(hPanel, g_sName[target]);
	DrawPanelItem(hPanel, " ", ITEMDRAW_SPACER|ITEMDRAW_RAWLINE);

	if (showMute)
	{
		Format(sTemp, sizeof(sTemp), "%T", "ReasonPanel_Punishment_Mute", client);
		if (g_MuteType[target] == bPerm)
			Format(sBuffer, sizeof(sBuffer), "%s%T", sTemp, "ReasonPanel_Perm", client);
		else if (g_MuteType[target] == bTime)
			Format(sBuffer, sizeof(sBuffer), "%s%T", sTemp, "ReasonPanel_Time", client, g_iMuteLength[target]);
		else if (g_MuteType[target] == bSess)
			Format(sBuffer, sizeof(sBuffer), "%s%T", sTemp, "ReasonPanel_Temp", client);
		else
			Format(sBuffer, sizeof(sBuffer), "error");
		DrawPanelText(hPanel, sBuffer);

		Format(sBuffer, sizeof(sBuffer), "%T", "ReasonPanel_Reason", client, g_sMuteReason[target]);
		DrawPanelText(hPanel, sBuffer);
	}
	else if (showGag)
	{
		Format(sTemp, sizeof(sTemp), "%T", "ReasonPanel_Punishment_Gag", client);
		if (g_GagType[target] == bPerm)
			Format(sBuffer, sizeof(sBuffer), "%s%T", sTemp, "ReasonPanel_Perm", client);
		else if (g_GagType[target] == bTime)
			Format(sBuffer, sizeof(sBuffer), "%s%T", sTemp, "ReasonPanel_Time", client, g_iGagLength[target]);
		else if (g_GagType[target] == bSess)
			Format(sBuffer, sizeof(sBuffer), "%s%T", sTemp, "ReasonPanel_Temp", client);
		else
			Format(sBuffer, sizeof(sBuffer), "error");
		DrawPanelText(hPanel, sBuffer);

		Format(sBuffer, sizeof(sBuffer), "%T", "ReasonPanel_Reason", client, g_sGagReason[target]);
		DrawPanelText(hPanel, sBuffer);
	}

	DrawPanelItem(hPanel, " ", ITEMDRAW_SPACER|ITEMDRAW_RAWLINE);
	SetPanelCurrentKey(hPanel, 10);
	Format(sBuffer, sizeof(sBuffer), "%T", "ReasonPanel_Back", client);
	DrawPanelItem(hPanel, sBuffer);
	SendPanelToClient(hPanel, client, PanelHandler_ListTargetReason, MENU_TIME_FOREVER);
	CloseHandle(hPanel);
}

public PanelHandler_ListTargetReason(Handle:menu, MenuAction:action, param1, param2)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			AdminMenu_ListTarget(param1, g_iPeskyPanels[param1][curTarget], g_iPeskyPanels[param1][curIndex], g_iPeskyPanels[param1][viewingMute], g_iPeskyPanels[param1][viewingGag]);
		}
	}
}

// QUERY CALL BACKS //

public GotDatabase(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	#if defined DEBUG
		LogToFile(logFile, "in GotDatabase: data %d, lock %d, g_h %d, hndl %d", data, g_iConnectLock, g_hDatabase, hndl);
	#endif

	// If this happens to be an old connection request, ignore it.
	if(data != g_iConnectLock || g_hDatabase)
	{
		if(hndl)
			CloseHandle(hndl);
		return;
	}

	g_iConnectLock   = 0;
	g_DatabaseState  = DatabaseState_Connected;
	g_hDatabase      = hndl;

	// See if the connection is valid.  If not, don't un-mark the caches
	// as needing rebuilding, in case the next connection request works.
	if(!g_hDatabase)
	{
		LogToFile(logFile, "Could not connect to database. Error %s", error);
		return;
	}

	// Set character set to UTF-8 in the database
	decl String:query[128];
	FormatEx(query, sizeof(query), "SET NAMES 'UTF8'");
	#if defined LOG_QUERIES
		LogToFile(logQuery, "Set encoding. QUERY: %s", query);
	#endif
	SQL_TQuery(g_hDatabase, ErrorCheckCallback, query);

	// Process queue
	SQL_TQuery(SQLiteDB, ProcessQueueCallbackB, "SELECT id, steam_id, time, start_time, reason, name, admin_id, admin_ip, type FROM queue2");

	// Force recheck players
	ForcePlayerRecheck();
}

public VerifyInsertB(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	ResetPack(data);
	new adminUserID = ReadPackCell(data);
	new length = ReadPackCell(data);
	new type = ReadPackCell(data);
	new String:reason[256], String:name[MAX_NAME_LENGTH], String:auth[64], String:adminAuth[32], String:adminIp[20];
	ReadPackString(data, reason, sizeof(reason));
	ReadPackString(data, name, sizeof(name));
	ReadPackString(data, auth, sizeof(auth));
	ReadPackString(data, adminAuth, sizeof(adminAuth));
	ReadPackString(data, adminIp, sizeof(adminIp));

	if (DB_Conn_Lost(hndl) || error[0])
	{
		LogToFile(logFile, "Inserting punishments Query Failed: %s", error);

		UTIL_InsertTempBlock(length, type, name, auth, reason, adminAuth, adminIp, data);
	}
	else
	{
		CloseHandle(data);
		ShowActivityToServer(GetClientOfUserId(adminUserID), type, length, reason, name);
	}
}

public VerifyInsertQueue(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	ResetPack(data);
	new admin = GetClientOfUserId(ReadPackCell(data));
	new length = ReadPackCell(data);
	new type = ReadPackCell(data);
	new String:reason[256], String:name[MAX_NAME_LENGTH], String:auth[64], String:adminAuth[32], String:adminIp[20];
	ReadPackString(data, reason, sizeof(reason));
	ReadPackString(data, name, sizeof(name));
	ReadPackString(data, auth, sizeof(auth));
	ReadPackString(data, adminAuth, sizeof(adminAuth));
	ReadPackString(data, adminIp, sizeof(adminIp));

	if (DB_Conn_Lost(hndl) || error[0])
	{
		LogToFile(logFile, "Inserting punishments to queue Failed: %s", error);
		ReplyToCommand(admin, "FIXME error inserting intro q");
	}
	else
	{
		ShowActivityToServer(admin, type, length, reason, name);
	}
	CloseHandle(data);
}

public SelectUnBlockCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	decl String:adminAuth[30], String:targetAuth[30], String:reason[256];

	ResetPack(data);
	new adminUserID = ReadPackCell(data);
	new targetUserID = ReadPackCell(data);

	#if defined DEBUG
		new type = ReadPackCell(data);
	#else
		ReadPackCell(data);	// Skip `type` row
	#endif

	ReadPackString(data, adminAuth, sizeof(adminAuth));
	ReadPackString(data, targetAuth, sizeof(targetAuth));
	ReadPackString(data, reason, sizeof(reason));

	new admin = GetClientOfUserId(adminUserID);
	new target = GetClientOfUserId(targetUserID);

	new String:targetName[MAX_NAME_LENGTH];
	strcopy(targetName, MAX_NAME_LENGTH, target && IsClientInGame(target) ? g_sName[target] : targetAuth);

	new bool:hasErrors = false;
	// If error is not an empty string the query failed
	if (DB_Conn_Lost(hndl) || error[0] != '\0')
	{
		LogToFile(logFile, "Unblock Select Query Failed: %s", error);
		if (admin && IsClientInGame(admin))
		{
			PrintToChat(admin, "%s%T", PREFIX, "Unblock Select Failed", admin, targetAuth);
		}
		else
		{
			PrintToServer("%s%T", PREFIX, "Unblock Select Failed", LANG_SERVER, targetAuth);
		}
		hasErrors = true;
	}

	// If there was no results then a ban does not exist for that id
	if (!DB_Conn_Lost(hndl) && !SQL_GetRowCount(hndl))
	{
		if (admin && IsClientInGame(admin))
		{
			PrintToChat(admin, "%s%t", PREFIX, "No blocks found", targetAuth);
		} else {
			PrintToServer("%s%T", PREFIX, "No blocks found", LANG_SERVER, targetAuth);
		}
		hasErrors = true;
	}

	if (hasErrors)
	{
		#if defined DEBUG
			LogToFile(logFile, "Calling TempUnBlock from SelectUnBlockCallback");
		#endif

		TempUnBlock(data);	// Datapack closed inside.
		return;
	}
	else
	{
		CloseHandle(data);	// Need to close datapack

		#if defined DEBUG
			LogToFile(logFile, "Processing unblock. Type: %d, admin %s, target %s,", type, adminAuth, targetAuth);
		#endif

		// Get the values from the founded blocks.
		while(SQL_MoreRows(hndl))
		{
			// Oh noes! What happened?!
			if (!SQL_FetchRow(hndl))
				continue;
			new bid = SQL_FetchInt(hndl, 0);
			new iAID = SQL_FetchInt(hndl, 1);
			new cAID = SQL_FetchInt(hndl, 2);
			new cImmunity = SQL_FetchInt(hndl, 3);
			new cType = SQL_FetchInt(hndl, 4);

			#if defined DEBUG
				// WHO WE ARE?
				LogToFile(logFile, "WHO WE ARE CHECKING!");
				if (iAID == cAID)
					LogToFile(logFile, "we are block author");
				if (!admin)
					LogToFile(logFile, "we are console (possibly)");
				if (AdmHasFlag(admin))
					LogToFile(logFile, "we have special flag");
				if (GetAdmImmunity(admin) > cImmunity)
					LogToFile(logFile, "we have %d immunity and block has %d. we cool", GetAdmImmunity(admin), cImmunity);
				LogToFile(logFile, "Fetched from DB: bid %d, iAID: %d, cAID: %d, cImmunity: %d, cType: %d", bid, iAID, cAID, cImmunity, cType);
			#endif

			// Checking - has we acces to unblock?
			if (iAID == cAID || (!admin && StrEqual(adminAuth, "STEAM_ID_SERVER")) || AdmHasFlag(admin) || (DisUBImCheck == 0 && (GetAdmImmunity(admin) > cImmunity)))
			{
				// Ok! we have rights to unblock
				// UnMute/UnGag, Show & log activity
				if (target && IsClientInGame(target))
				{
					switch(cType)
					{
						case TYPE_MUTE:
						{
							PerformUnMute(target);
							ShowActivity2(admin, PREFIX, "%t", "Unmuted player", g_sName[target]);
							LogAction(admin, target, "\"%L\" unmuted \"%L\" (reason \"%s\")", admin, target, reason);
						}
						//-------------------------------------------------------------------------------------------------
						case TYPE_GAG:
						{
							PerformUnGag(target);
							ShowActivity2(admin, PREFIX, "%t", "Ungagged player", g_sName[target]);
							LogAction(admin, target, "\"%L\" ungagged \"%L\" (reason \"%s\")", admin, target, reason);
						}
					}
				}

				new Handle:dataPack = CreateDataPack();
				WritePackCell(dataPack, adminUserID);
				WritePackCell(dataPack, cType);
				WritePackString(dataPack, g_sName[target]);
				WritePackString(dataPack, targetAuth);

				new String:unbanReason[sizeof(reason) * 2 + 1];
				SQL_EscapeString(g_hDatabase, reason, unbanReason, sizeof(unbanReason));

				decl String:query[1024];
				Format(query, sizeof(query),
					"UPDATE %s_comms SET RemovedBy = %d, RemoveType = 'U', RemovedOn = UNIX_TIMESTAMP(), ureason = '%s' WHERE bid = %d",
					DatabasePrefix, iAID, unbanReason, bid);
				#if defined LOG_QUERIES
					LogToFile(logQuery, "in SelectUnBlockCallback: Unblocking. QUERY: %s", query);
				#endif
				SQL_TQuery(g_hDatabase, InsertUnBlockCallback, query, dataPack);
			}
			else
			{
				// sorry, we don't have permission to unblock!
				switch(cType)
				{
					case TYPE_MUTE:
					{
						if (admin && IsClientInGame(admin))
							PrintToChat(admin, "%s%t", PREFIX, "No permission unmute", targetName);
						LogAction(admin, target, "\"%L\" tried (and didn't have permission) to unmute %s (reason \"%s\")", admin, targetAuth, reason);
					}
					//-------------------------------------------------------------------------------------------------
					case TYPE_GAG:
					{
						if (admin && IsClientInGame(admin))
							PrintToChat(admin, "%s%t", PREFIX, "No permission ungag", targetName);
						LogAction(admin, target, "\"%L\" tried (and didn't have permission) to ungag %s (reason \"%s\")", admin, targetAuth, reason);
					}
				}
			}
		}
	}
}

public InsertUnBlockCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	// if the pack is good unpack it and close the handle
	new admin, type;
	new String:targetName[MAX_NAME_LENGTH], String:targetAuth[30];
	if (data != INVALID_HANDLE)
	{
		ResetPack(data);
		admin = GetClientOfUserId(ReadPackCell(data));
		type = ReadPackCell(data);
		ReadPackString(data, targetName, sizeof(targetName));
		ReadPackString(data, targetAuth, sizeof(targetAuth));
		CloseHandle(data);
	} else {
		// Technically this should not be possible
		ThrowError("Invalid Handle in InsertUnBlockCallback");
	}

	// If error is not an empty string the query failed
	if (error[0] != '\0')
	{
		LogToFile(logFile, "UnBlock Insert Query Failed: %s", error);
		if (admin && IsClientInGame(admin))
		{
			PrintToChat(admin, "%s%t", PREFIX, "Unblock insert failed");
		}
		return;
	}

	switch(type)
	{
		case TYPE_MUTE:
		{
			LogAction(admin, -1, "\"%L\" removed mute for %s from DB", admin, targetAuth);
			if (admin && IsClientInGame(admin))
			{
				PrintToChat(admin, "%s%t", PREFIX, "successfully unmuted", targetName);
			} else {
				PrintToServer("%s%T", PREFIX, "successfully unmuted", LANG_SERVER, targetName);
			}
		}
		//-------------------------------------------------------------------------------------------------
		case TYPE_GAG:
		{
			LogAction(admin, -1, "\"%L\" removed gag for %s from DB", admin, targetAuth);
			if (admin && IsClientInGame(admin))
			{
				PrintToChat(admin, "%s%t", PREFIX, "successfully ungagged", targetName);
			} else {
				PrintToServer("%s%T", PREFIX, "successfully ungagged", LANG_SERVER, targetName);
			}
		}
	}
}

// ProcessQueueCallback is called as the result of selecting all the rows from the queue table
public ProcessQueueCallbackB(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE || strlen(error) > 0)
	{
		LogToFile(logFile, "Failed to retrieve queued blocks from sqlite database, %s", error);
		return;
	}

	decl String:auth[64];
	new String:name[MAX_NAME_LENGTH];
	decl String:reason[256];
	decl String:adminAuth[64], String:adminIp[20];
	decl String:query[1024];

	while(SQL_MoreRows(hndl))
	{
		// Oh noes! What happened?!
		if (!SQL_FetchRow(hndl))
			continue;

		new String:sAuthEscaped[sizeof(auth) * 2 + 1];
		new String:banName[MAX_NAME_LENGTH * 2  + 1];
		new String:banReason[sizeof(reason) * 2 + 1];
		new String:sAdmAuthEscaped[sizeof(adminAuth) * 2 + 1];
		new String:sAdmAuthYZEscaped[sizeof(adminAuth) * 2 + 1];

		// if we get to here then there are rows in the queue pending processing
		//steam_id TEXT, time INTEGER, start_time INTEGER, reason TEXT, name TEXT, admin_id TEXT, admin_ip TEXT, type INTEGER
		new id = SQL_FetchInt(hndl, 0);
		SQL_FetchString(hndl, 1, auth, sizeof(auth));
		new time = SQL_FetchInt(hndl, 2);
		new startTime = SQL_FetchInt(hndl, 3);
		SQL_FetchString(hndl, 4, reason, sizeof(reason));
		SQL_FetchString(hndl, 5, name, sizeof(name));
		SQL_FetchString(hndl, 6, adminAuth, sizeof(adminAuth));
		SQL_FetchString(hndl, 7, adminIp, sizeof(adminIp));
		new type = SQL_FetchInt(hndl, 8);

		if (DB_Connect()) {
			SQL_EscapeString(g_hDatabase, auth, sAuthEscaped, sizeof(sAuthEscaped));
			SQL_EscapeString(g_hDatabase, name, banName, sizeof(banName));
			SQL_EscapeString(g_hDatabase, reason, banReason, sizeof(banReason));
			SQL_EscapeString(g_hDatabase, adminAuth, sAdmAuthEscaped, sizeof(sAdmAuthEscaped));
			SQL_EscapeString(g_hDatabase, adminAuth[8], sAdmAuthYZEscaped, sizeof(sAdmAuthYZEscaped));
		}
		else
			continue;
		// all blocks should be entered into db!

		FormatEx(query, sizeof(query),
				"INSERT INTO %s_comms (authid, name, created, ends, length, reason, aid, adminIp, sid, type) VALUES \
				('%s', '%s', %d, %d, %d, '%s', IFNULL((SELECT aid FROM %s_admins WHERE authid = '%s' OR authid REGEXP '^STEAM_[0-9]:%s$'), '0'), '%s', \
				%d, %d)",
				DatabasePrefix, sAuthEscaped, banName, startTime, (startTime + (time*60)), (time*60), banReason, DatabasePrefix, sAdmAuthEscaped, sAdmAuthYZEscaped, adminIp, serverID, type);
		#if defined LOG_QUERIES
			LogToFile(logQuery, "in ProcessQueueCallbackB: Insert to db. QUERY: %s", query);
		#endif
		SQL_TQuery(g_hDatabase, AddedFromSQLiteCallbackB, query, id);
	}
}

public AddedFromSQLiteCallbackB(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	decl String:buffer[128];
	if (error[0] == '\0')
	{
		// The insert was successful so delete the record from the queue
		FormatEx(buffer, sizeof(buffer), "DELETE FROM queue2 WHERE id = %d", data);
		#if defined LOG_QUERIES
			LogToFile(logQuery, "in AddedFromSQLiteCallbackB: DELETE FROM QUEUE. QUERY: %s", buffer);
		#endif
		SQL_TQuery(SQLiteDB, ErrorCheckCallback, buffer);
	}
}

public ErrorCheckCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (error[0])
	{
		LogToFile(logFile, "%s - Query Failed: %s", data, error);
	}

	// force reconnect if needed
	DB_Conn_Lost(hndl);
}

public VerifyBlocks(Handle:owner, Handle:hndl, const String:error[], any:userid)
{
	decl String:clientAuth[64];
	new client = GetClientOfUserId(userid);

	if (!client)
		return;

	/* Failure happen. Do retry with delay */
	if (DB_Conn_Lost(hndl))
	{
		LogToFile(logFile, "Verify Blocks Query Failed: %s", error);
		if (g_hPlayerRecheck[client] == INVALID_HANDLE)
			g_hPlayerRecheck[client] = CreateTimer(RetryTime, ClientRecheck, GetClientUserId(client));
		return;
	}

	GetClientAuthString(client, clientAuth, sizeof(clientAuth));

	//SELECT (c.ends - UNIX_TIMESTAMP()) as remaining, c.length, c.type, c.created, c.reason, a.user,
	//IF (a.immunity>=g.immunity, a.immunity, IFNULL(g.immunity,0)) as immunity, c.aid, c.sid
	//FROM %s_comms c LEFT JOIN %s_admins a ON a.aid=c.aid LEFT JOIN %s_srvgroups g ON g.name = a.srv_group
	//WHERE c.authid REGEXP '^STEAM_[0-9]:%s$' AND (length = '0' OR ends > UNIX_TIMESTAMP()) AND RemoveType IS NULL",
	if (SQL_GetRowCount(hndl) > 0)
	{
		while(SQL_FetchRow(hndl))
		{
			if (NotApplyToThisServer(SQL_FetchInt(hndl, 8)))
				continue;

			new String:sReason[256], String:sAdmName[MAX_NAME_LENGTH];
			new remaining_time = SQL_FetchInt(hndl, 0);
			new length = SQL_FetchInt(hndl, 1);
			new type = SQL_FetchInt(hndl, 2);
			new time = SQL_FetchInt(hndl, 3);
			SQL_FetchString(hndl, 4, sReason, sizeof(sReason));
			SQL_FetchString(hndl, 5, sAdmName, sizeof(sAdmName));
			new immunity = SQL_FetchInt(hndl, 6);
			new aid = SQL_FetchInt(hndl, 7);

			// Block from CONSOLE (aid=0) and we have `console immunity` value in config
			if (!aid && ConsoleImmunity > immunity)
				immunity = ConsoleImmunity;

			#if defined DEBUG
				LogToFile(logFile, "Fetched from DB: remaining %d, length %d, type %d", remaining_time, length, type);
			#endif

			switch(type)
			{
				case TYPE_MUTE:
				{
					if (g_MuteType[client] < bTime)
					{
						PerformMute(client, time, length / 60, sAdmName, immunity, sReason, remaining_time);
						PrintToChat(client, "%s%t", PREFIX, "Muted on connect");
					}
				}
				case TYPE_GAG:
				{
					if (g_GagType[client] < bTime)
					{
						PerformGag(client, time, length / 60, sAdmName, immunity, sReason, remaining_time);
						PrintToChat(client, "%s%t", PREFIX, "Gagged on connect");
					}
				}
			}
		}
	}

	g_bPlayerStatus[client] = true;
}


// TIMER CALL BACKS //

public Action:ClientRecheck(Handle:timer, any:userid)
{
	#if defined DEBUG
		LogToFile(logFile, "ClientRecheck(userid: %d)", userid);
	#endif

	new client = GetClientOfUserId(userid);
	if (!client)
		return;

	if (IsClientConnected(client))
		OnClientPostAdminCheck(client);

	g_hPlayerRecheck[client] =  INVALID_HANDLE;
}

public Action:Timer_MuteExpire(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if (!client)
		return;

	#if defined DEBUG
		decl String:clientAuth[64];
		GetClientAuthString(client, clientAuth,sizeof(clientAuth));
		LogToFile(logFile, "Mute expired for %s", clientAuth);
	#endif

	PrintToChat(client, "%s%t", PREFIX, "Mute expired");

	g_hMuteExpireTimer[client] = INVALID_HANDLE;
	MarkClientAsUnMuted(client);
	if (IsClientInGame(client))
		BaseComm_SetClientMute(client, false);
}

public Action:Timer_GagExpire(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if (!client)
		return;

	#if defined DEBUG
		decl String:clientAuth[64];
		GetClientAuthString(client, clientAuth,sizeof(clientAuth));
		LogToFile(logFile, "Gag expired for %s", clientAuth);
	#endif

	PrintToChat(client, "%s%t", PREFIX, "Gag expired");

	g_hGagExpireTimer[client] = INVALID_HANDLE;
	MarkClientAsUnGagged(client);
	if (IsClientInGame(client))
		BaseComm_SetClientGag(client, false);
}

public Action:Timer_StopWait(Handle:timer, any:data)
{
	g_DatabaseState = DatabaseState_None;
	DB_Connect();
}

// PARSER //

static InitializeConfigParser()
{
	if (ConfigParser == INVALID_HANDLE)
	{
		ConfigParser = SMC_CreateParser();
		SMC_SetReaders(ConfigParser, ReadConfig_NewSection, ReadConfig_KeyValue, ReadConfig_EndSection);
	}
}

static InternalReadConfig(const String:path[])
{
	ConfigState = ConfigStateNone;

	new SMCError:err = SMC_ParseFile(ConfigParser, path);

	if (err != SMCError_Okay)
	{
		decl String:buffer[64];
		if (SMC_GetErrorString(err, buffer, sizeof(buffer)))
		{
			PrintToServer(buffer);
		} else {
			PrintToServer("Fatal parse error");
		}
	}
}

public SMCResult:ReadConfig_NewSection(Handle:smc, const String:name[], bool:opt_quotes)
{
	if (name[0])
	{
		if (strcmp("Config", name, false) == 0)
		{
			ConfigState = ConfigStateConfig;
		} else if (strcmp("CommsReasons", name, false) == 0) {
			ConfigState = ConfigStateReasons;
		} else if (strcmp("CommsTimes", name, false) == 0) {
			ConfigState = ConfigStateTimes;
		} else if (strcmp("ServersWhiteList", name, false) == 0) {
			ConfigState = ConfigStateServers;
		}
	}
	return SMCParse_Continue;
}

public SMCResult:ReadConfig_KeyValue(Handle:smc, const String:key[], const String:value[], bool:key_quotes, bool:value_quotes)
{
	if (!key[0])
		return SMCParse_Continue;

	switch(ConfigState)
	{
		case ConfigStateConfig:
		{
			if (strcmp("DatabasePrefix", key, false) == 0)
			{
				strcopy(DatabasePrefix, sizeof(DatabasePrefix), value);

				if (DatabasePrefix[0] == '\0')
				{
					DatabasePrefix = "sb";
				}
			}
			else if (strcmp("RetryTime", key, false) == 0)
			{
				RetryTime	= StringToFloat(value);
				if (RetryTime < 15.0)
				{
					RetryTime = 15.0;
				} else if (RetryTime > 60.0) {
					RetryTime = 60.0;
				}
			}
			else if (strcmp("ServerID", key, false) == 0)
			{
				if (!StringToIntEx(value, serverID) || serverID < 1)
					serverID = 0;
			}
			else if (strcmp("DefaultTime", key, false) == 0)
			{
				DefaultTime	= StringToInt(value);
				if (DefaultTime < 0)
					DefaultTime = -1;
				if (DefaultTime == 0)
					DefaultTime = 30;
			}
			else if (strcmp("DisableUnblockImmunityCheck", key, false) == 0)
			{
				DisUBImCheck = StringToInt(value);
				if (DisUBImCheck != 1)
					DisUBImCheck = 0;
			}
			else if (strcmp("ConsoleImmunity", key, false) == 0)
			{
				ConsoleImmunity = StringToInt(value);
			}
			else if (strcmp("MaxLength", key, false) == 0)
			{
				ConfigMaxLength = StringToInt(value);
			}
			else if (strcmp("OnlyWhiteListServers", key, false) == 0)
			{
				ConfigWhiteListOnly = StringToInt(value);
				if (ConfigWhiteListOnly != 1)
					ConfigWhiteListOnly = 0;
			}
		}
		case ConfigStateReasons:
		{
			Format(g_sReasonKey[iNumReasons], REASON_SIZE, "%s", key);
			Format(g_sReasonDisplays[iNumReasons], DISPLAY_SIZE, "%s", value);
			#if defined DEBUG
				LogToFile(logFile, "Loaded reason. index %d, key \"%s\", display_text \"%s\"", iNumReasons, g_sReasonKey[iNumReasons], g_sReasonDisplays[iNumReasons]);
			#endif
			iNumReasons++;
		}
		case ConfigStateTimes:
		{
			Format(g_sTimeDisplays[iNumTimes], DISPLAY_SIZE, "%s", value);
			g_iTimeMinutes[iNumTimes] = StringToInt(key);
			#if defined DEBUG
				LogToFile(logFile, "Loaded time. index %d, time %d minutes, display_text \"%s\"", iNumTimes, g_iTimeMinutes[iNumTimes] , g_sTimeDisplays[iNumTimes]);
			#endif
			iNumTimes++;
		}
		case ConfigStateServers:
		{
			if (strcmp("id", key, false) == 0)
			{
				new srvID = StringToInt(value);
				if (srvID >= 0)
				{
					PushArrayCell(g_hServersWhiteList, srvID);
					#if defined DEBUG
						LogToFile(logFile, "Loaded white list server id %d", srvID);
					#endif
				}
			}
		}
	}
	return SMCParse_Continue;
}

public SMCResult:ReadConfig_EndSection(Handle:smc)
{
	return SMCParse_Continue;
}

// STOCK FUNCTIONS //

stock bool:DB_Connect()
{
	#if defined DEBUG
		LogToFile(logFile, "in DB_Connect, handle %d, state %d, lock %d", g_hDatabase, g_DatabaseState, g_iConnectLock);
	#endif

	if (g_hDatabase)
		return true;

	if (g_DatabaseState == DatabaseState_Wait) // 100500 connections in a minute is bad idea..
		return false;

	if(g_DatabaseState != DatabaseState_Connecting)
	{
		g_DatabaseState = DatabaseState_Connecting;
		g_iConnectLock   = ++g_iSequence;
		// Connect using the "sourcebans" section, or the "default" section if "sourcebans" does not exist
		SQL_TConnect(GotDatabase, DATABASE, g_iConnectLock);
	}

	return false;
}

stock bool:DB_Conn_Lost(Handle:hndl)
{
	if (hndl == INVALID_HANDLE)
	{
		if (g_hDatabase != INVALID_HANDLE)
		{
			LogToFile(logFile, "Lost connection to DB. Reconnect after delay.");
			CloseHandle(g_hDatabase);
			g_hDatabase = INVALID_HANDLE;
		}
		if (g_DatabaseState != DatabaseState_Wait)
		{
			g_DatabaseState = DatabaseState_Wait;
			CreateTimer(RetryTime, Timer_StopWait, _, TIMER_FLAG_NO_MAPCHANGE);
		}
		return true;
	}
	else
		return false;
}

stock InitializeBackupDB()
{
	decl String:error[255];
	SQLiteDB = SQLite_UseDatabase("sourcecomms-queue", error, sizeof(error));
	if (SQLiteDB == INVALID_HANDLE)
		SetFailState(error);

	SQL_TQuery(SQLiteDB, ErrorCheckCallback, "CREATE TABLE IF NOT EXISTS queue2 (id INTEGER PRIMARY KEY, steam_id TEXT, time INTEGER, start_time INTEGER, reason TEXT, name TEXT, admin_id TEXT, admin_ip TEXT, type INTEGER);");
}

stock CreateBlock(client, targetId = 0, length = -1, type, const String:sReason[] = "", const String:sArgs[] = "")
{
	#if defined DEBUG
		LogToFile(logFile, "CreateBlock(%d, %d, %d, %d, %s, %s)", client, targetId, length, type, sReason, sArgs);
	#endif

	decl String:reason[256], target_list[MAXPLAYERS], target_count;
	new bool:tn_is_ml = false;

	// checking args
	if (targetId)
	{
		target_list[0] = targetId;
		target_count = 1;
		strcopy(reason, sizeof(reason), sReason);
	}
	else if (strlen(sArgs))
	{
		new String:sArg[3][192];

		if (ExplodeString(sArgs, "\"", sArg, 3, 192, true) == 3 && strlen(sArg[0]) == 0)	// exploding by quotes
		{
			TrimString(sArg[2]);
			sArg[0] = sArg[1];		// target name
			new String:sTempArg[2][192];
			ExplodeString(sArg[2], " ", sTempArg, 2, 192, true); // get time and reason
			sArg[1] = sTempArg[0];	// time
			sArg[2] = sTempArg[1];	// reason
		}
		else
		{
			ExplodeString(sArgs, " ", sArg, 3, 192, true);	// exploding by spaces
		}

		// TODO -> replace to ProcessTargetString
		// Get the target, find target returns a message on failure so we do not
		targetId = FindTarget(client, sArg[0], true);
		if (targetId == -1)
			return;

		/* TODO */
		target_list[0] = targetId;
		target_count = 1;

		// Get the ban time
		if(!StringToIntEx(sArg[1], length))	// not valid number in second argument
		{
			length = DefaultTime;
			Format(reason, sizeof(reason), "%s %s", sArg[1], sArg[2]);
		}
		else
			strcopy(reason, sizeof(reason), sArg[2]);

		if(!IsAllowedBlockLength(client, length, target_count))
		{
			ReplyToCommand(client, "%s%t", PREFIX, "no access");
			return;
		}
	}
	else
	{
		return;
	}

	new admImmunity = GetAdmImmunity(client);

	for (new i = 0; i < target_count; i++)
	{
		new target = target_list[i];

		#if defined DEBUG
			decl String:auth[64];
			GetClientAuthString(target, auth, sizeof(auth));
			LogToFile(logFile, "Processing block for %s", auth);
		#endif

		if (!g_bPlayerStatus[target])
		{
			// The target has not been blocks verify. It must be completed before you can block anyone.
			ReplyToCommand(client, "%s%t", PREFIX, "Player Comms Not Verified");
			continue;
		}

		switch(type)
		{
			case TYPE_MUTE:
			{
				if (!BaseComm_IsClientMuted(target))
				{
					#if defined DEBUG
						LogToFile(logFile, "%s not muted. Mute him, creating unmute timer and add record to DB", auth);
					#endif

					PerformMute(target, _, length, g_sName[client], admImmunity, reason);

					LogAction(client, target, "\"%L\" muted \"%L\" (minutes \"%d\") (reason \"%s\")", client, target, length, reason);
				}
				else
				{
					#if defined DEBUG
						LogToFile(logFile, "%s already muted", auth);
					#endif
					ReplyToCommand(client, "%s%t", PREFIX, "Player already muted", g_sName[target]);
					continue;
				}
			}
			//-------------------------------------------------------------------------------------------------
			case TYPE_GAG:
			{
				if (!BaseComm_IsClientGagged(target))
				{
					#if defined DEBUG
						LogToFile(logFile, "%s not gagged. Gag him, creating ungag timer and add record to DB", auth);
					#endif

					PerformGag(target, _, length, g_sName[client], admImmunity, reason);

					LogAction(client, target, "\"%L\" gagged \"%L\" (minutes \"%d\") (reason \"%s\")", client, target, length, reason);
				}
				else
				{
					#if defined DEBUG
						LogToFile(logFile, "%s already gagged", auth);
					#endif
					ReplyToCommand(client, "%s%t", PREFIX, "Player already gagged", g_sName[target]);
					continue;
				}
			}
			//-------------------------------------------------------------------------------------------------
			case TYPE_SILENCE:
			{
				if (!BaseComm_IsClientGagged(target) && !BaseComm_IsClientMuted(target))
				{
					#if defined DEBUG
						LogToFile(logFile, "%s not silenced. Silence him, creating ungag & unmute timers and add records to DB", auth);
					#endif

					PerformMute(target, _, length, g_sName[client], admImmunity, reason);
					PerformGag(target, _, length, g_sName[client], admImmunity, reason);

					LogAction(client, target, "\"%L\" silenced \"%L\" (minutes \"%d\") (reason \"%s\")", client, target, length, reason);
				}
				else
				{
					#if defined DEBUG
						LogToFile(logFile, "%s already gagged or/and muted", auth);
					#endif
					ReplyToCommand(client, "%s%t", PREFIX, "Player already silenced", g_sName[target]);
					continue;
				}
			}
		}
		if (target_count == 1)
			SavePunishment(client, target_list[0], type, length, reason);
	}


	return;
}

stock bool:ProcessUnBlock(client, target, type, String:reason[])
{
	#if defined DEBUG
		LogToFile(logFile, "ProcessUnBlock(%d, %s)", type, reason);
	#endif

	decl String:adminAuth[64];
	decl String:targetAuth[64];

	if (!client)
	{
		// setup dummy adminAuth and adminIp for server
		strcopy(adminAuth, sizeof(adminAuth), "STEAM_ID_SERVER");
	} else {
		GetClientAuthString(client, adminAuth, sizeof(adminAuth));
	}

	if (IsClientInGame(target))
		GetClientAuthString(target, targetAuth, sizeof(targetAuth));

	decl String:typeWHERE[100];

	// Check current player status
	switch(type)
	{
		case TYPE_MUTE:
		{
			if (!BaseComm_IsClientMuted(target))
			{
				ReplyToCommand(client, "%s%t", PREFIX, "Player not muted");
				return false;
			}
			else
			{
				FormatEx(typeWHERE, sizeof(typeWHERE), "c.type = '%d'", TYPE_MUTE);
			}
		}
		//-------------------------------------------------------------------------------------------------
		case TYPE_GAG:
		{
			if (!BaseComm_IsClientGagged(target))
			{
				ReplyToCommand(client, "%s%t", PREFIX, "Player not gagged");
				return false;
			}
			else
			{
				FormatEx(typeWHERE, sizeof(typeWHERE), "c.type = '%d'", TYPE_GAG);
			}
		}
		//-------------------------------------------------------------------------------------------------
		case TYPE_SILENCE:
		{
			if (!BaseComm_IsClientMuted(target) || !BaseComm_IsClientGagged(target))
			{
				ReplyToCommand(client, "%s%t", PREFIX, "Player not silenced");
				return false;
			}
			else
			{
				FormatEx(typeWHERE, sizeof(typeWHERE), "(c.type = '%d' OR c.type = '%d')", TYPE_MUTE, TYPE_GAG);
			}
		}
	}

	// Pack everything into a data pack so we can retain it
	new Handle:dataPack = CreateDataPack();
	WritePackCell(dataPack, GetClientUserId2(client));
	WritePackCell(dataPack, GetClientUserId(target));
	WritePackCell(dataPack, type);
	WritePackString(dataPack, adminAuth);
	WritePackString(dataPack, targetAuth);
	WritePackString(dataPack, reason);
	ResetPack(dataPack);

	if (DB_Connect())
	{
		new String:sAdminAuthEscaped[sizeof(adminAuth) * 2 + 1];
		new String:sAdminAuthYZEscaped[sizeof(adminAuth) * 2 + 1];
		new String:sTargetAuthEscaped[sizeof(targetAuth) * 2 + 1];
		new String:sTargetAuthYZEscaped[sizeof(targetAuth) * 2 + 1];

		SQL_EscapeString(g_hDatabase, adminAuth, sAdminAuthEscaped, sizeof(sAdminAuthEscaped));
		SQL_EscapeString(g_hDatabase, adminAuth[8], sAdminAuthYZEscaped, sizeof(sAdminAuthYZEscaped));
		SQL_EscapeString(g_hDatabase, targetAuth, sTargetAuthEscaped, sizeof(sTargetAuthEscaped));
		SQL_EscapeString(g_hDatabase, targetAuth[8], sTargetAuthYZEscaped, sizeof(sTargetAuthYZEscaped));

		decl String:query[1024];
		Format(query, sizeof(query),
			"SELECT c.bid, IFNULL((SELECT aid FROM %s_admins WHERE authid = '%s' OR authid REGEXP '^STEAM_[0-9]:%s$'), '0') as iaid, c.aid, IF (a.immunity>=g.immunity, a.immunity, IFNULL(g.immunity,0)) as immunity, c.type FROM %s_comms c \
			LEFT JOIN %s_admins a ON a.aid=c.aid LEFT JOIN %s_srvgroups g ON g.name = a.srv_group WHERE RemoveType IS NULL AND (c.authid = '%s' OR c.authid REGEXP '^STEAM_[0-9]:%s$') AND (length = '0' OR ends > UNIX_TIMESTAMP()) AND %s",
			DatabasePrefix, sAdminAuthEscaped, sAdminAuthYZEscaped, DatabasePrefix, DatabasePrefix, DatabasePrefix, sTargetAuthEscaped, sTargetAuthYZEscaped, typeWHERE);

		#if defined LOG_QUERIES
			LogToFile(logQuery, "Unblocking select. QUERY: %s", query);
		#endif

		SQL_TQuery(g_hDatabase, SelectUnBlockCallback, query, dataPack);
	}
	else
	{
		#if defined DEBUG
			LogToFile(logFile, "Calling TempUnBlock from ProcessUnBlock");
		#endif
		TempUnBlock(dataPack);
	}

	return true;
}

stock TempUnBlock(&Handle:data)
{
	#if defined DEBUG
		LogToFile(logFile, "TemporaryUnblock");
	#endif

	decl String:adminAuth[30], String:targetAuth[30], String:reason[256];
	ResetPack(data);
	new adminUserID = ReadPackCell(data);
	new targetUserID = ReadPackCell(data);
	new type = ReadPackCell(data);
	ReadPackString(data, adminAuth, sizeof(adminAuth));
	ReadPackString(data, targetAuth, sizeof(targetAuth));
	ReadPackString(data, reason, sizeof(reason));
	CloseHandle(data);	// Need to close datapack

	new admin = GetClientOfUserId(adminUserID);
	new target = GetClientOfUserId(targetUserID);

	new AdmImmunity = GetAdmImmunity(admin);
	new bool:AdmImCheck = (DisUBImCheck == 0 && ((type == TYPE_MUTE && AdmImmunity > g_iMuteLevel[target]) || (type == TYPE_GAG && AdmImmunity > g_iGagLevel[target]) || (type == TYPE_SILENCE && AdmImmunity > g_iMuteLevel[target] && AdmImmunity > g_iGagLevel[target]) ) );

	#if defined DEBUG
		LogToFile(logFile, "WHO WE ARE CHECKING!");
		if (!admin)
			LogToFile(logFile, "we are console (possibly)");
		if (AdmHasFlag(admin))
			LogToFile(logFile, "we have special flag");
	#endif

	// Check access for unblock without db changes (temporary unblock)
	if ((!admin && StrEqual(adminAuth, "STEAM_ID_SERVER")) || AdmHasFlag(admin) || AdmImCheck)	// can, if we are console or have special flag
	{
		switch(type)
		{
			case TYPE_MUTE:
			{
				PerformUnMute(target);
				ShowActivity2(admin, PREFIX, "%t", "Temp unmuted player", g_sName[target]);
				LogAction(admin, target, "\"%L\" temporary unmuted \"%L\" (reason \"%s\")", admin, target, reason);
			}
			//-------------------------------------------------------------------------------------------------
			case TYPE_GAG:
			{
				PerformUnGag(target);
				ShowActivity2(admin, PREFIX, "%t", "Temp ungagged player", g_sName[target]);
				LogAction(admin, target, "\"%L\" temporary ungagged \"%L\" (reason \"%s\")", admin, target, reason);
			}
			//-------------------------------------------------------------------------------------------------
			case TYPE_SILENCE:
			{
				PerformUnMute(target);
				PerformUnGag(target);
				ShowActivity2(admin, PREFIX, "%t", "Temp unsilenced player", g_sName[target]);
				LogAction(admin, target, "\"%L\" temporary unsilenced \"%L\" (reason \"%s\")", admin, target, reason);
			}
		}
	}
	else
	{
		if (admin && IsClientInGame(admin))
		{
			PrintToChat(admin, "%s%t", PREFIX, "No db error unlock perm");
		} else {
			PrintToServer("%s%T", PREFIX, "No db error unlock perm", LANG_SERVER); //seriously? is it possible?
		}
	}
}

stock UTIL_InsertTempBlock(length, type, const String:name[], const String:auth[], const String:reason[], const String:adminAuth[], const String:adminIp[], Handle:pack)
{
	LogToFile(logFile, "Inserting punishment for %s into queue", auth);

	new String:banName[MAX_NAME_LENGTH * 2 + 1];
	new String:banReason[256 * 2 + 1];
	new String:sAuthEscaped[64 * 2 + 1];
	new String:sAdminAuthEscaped[64 * 2 + 1];
	decl String:sQuery[4096], String:sQueryVal[2048];
	new String:sQueryMute[2048], String:sQueryGag[2048];

	// escaping everything
	SQL_EscapeString(SQLiteDB, name, banName, sizeof(banName));
	SQL_EscapeString(SQLiteDB, reason, banReason, sizeof(banReason));
	SQL_EscapeString(SQLiteDB, auth, sAuthEscaped, sizeof(sAuthEscaped));
	SQL_EscapeString(SQLiteDB, adminAuth, sAdminAuthEscaped, sizeof(sAdminAuthEscaped));

	// steam_id time start_time reason name admin_id admin_ip
	FormatEx(sQueryVal, sizeof(sQueryVal),
		"'%s', %d, %d, '%s', '%s', '%s', '%s'",
		sAuthEscaped, length, GetTime(), banReason, banName, sAdminAuthEscaped, adminIp);

	if (type == TYPE_MUTE || type == TYPE_SILENCE)
	{
		FormatEx(sQueryMute, sizeof(sQueryMute), "(%s, %d)", sQueryVal, TYPE_MUTE);
	}
	if (type == TYPE_GAG || type == TYPE_SILENCE)
	{
		FormatEx(sQueryGag, sizeof(sQueryGag), "(%s, %d)", sQueryVal, TYPE_GAG);
	}

	FormatEx(sQuery, sizeof(sQuery),
		"INSERT INTO queue2 (steam_id, time, start_time, reason, name, admin_id, admin_ip, type) VALUES %s%s%s",
		sQueryMute, type == TYPE_SILENCE ? ", " : "", sQueryGag);

	#if defined LOG_QUERIES
		LogToFile(logQuery, "Insert into queue. QUERY: %s", sQuery);
	#endif

	SQL_TQuery(SQLiteDB, VerifyInsertQueue, sQuery, pack);
}

stock ServerInfo()
{
	decl pieces[4];
	new longip = GetConVarInt(CvarHostIp);
	pieces[0] = (longip >> 24) & 0x000000FF;
	pieces[1] = (longip >> 16) & 0x000000FF;
	pieces[2] = (longip >> 8) & 0x000000FF;
	pieces[3] = longip & 0x000000FF;
	FormatEx(ServerIp, sizeof(ServerIp), "%d.%d.%d.%d", pieces[0], pieces[1], pieces[2], pieces[3]);
	GetConVarString(CvarPort, ServerPort, sizeof(ServerPort));
}

stock ReadConfig()
{
	InitializeConfigParser();

	if (ConfigParser == INVALID_HANDLE)
	{
		return;
	}

	decl String:ConfigFile1[PLATFORM_MAX_PATH], String:ConfigFile2[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, ConfigFile1, sizeof(ConfigFile1), "configs/sourcebans/sourcebans.cfg");
	BuildPath(Path_SM, ConfigFile2, sizeof(ConfigFile2), "configs/sourcebans/sourcecomms.cfg");

	if (FileExists(ConfigFile1))
	{
		PrintToServer("%sLoading configs/sourcebans/sourcebans.cfg config file", PREFIX);
		InternalReadConfig(ConfigFile1);
	} else {
		decl String:Error[PLATFORM_MAX_PATH + 64];
		FormatEx(Error, sizeof(Error), "%sFATAL *** ERROR *** can not find %s", PREFIX, ConfigFile1);
		LogToFile(logFile, "FATAL *** ERROR *** can not find %s", ConfigFile1);
		SetFailState(Error);
	}
	if (FileExists(ConfigFile2))
	{
		PrintToServer("%sLoading configs/sourcebans/sourcecomms.cfg config file", PREFIX);
		iNumReasons = 0;
		iNumTimes = 0;
		InternalReadConfig(ConfigFile2);
		if (iNumReasons)
			iNumReasons--;
		if (iNumTimes)
			iNumTimes--;
		if (serverID == 0)
		{
			LogError("You must set valid `ServerID` value in sourcebans.cfg!");
			if (ConfigWhiteListOnly)
			{
				LogError("ServersWhiteList feature disabled!");
				ConfigWhiteListOnly = 0;
			}
		}
	} else {
		decl String:Error[PLATFORM_MAX_PATH + 64];
		FormatEx(Error, sizeof(Error), "%sFATAL *** ERROR *** can not find %s", PREFIX, ConfigFile2);
		LogToFile(logFile, "FATAL *** ERROR *** can not find %s", ConfigFile2);
		SetFailState(Error);
	}
	#if defined DEBUG
		LogToFile(logFile, "Loaded DefaultTime value: %d", DefaultTime);
		LogToFile(logFile, "Loaded DisableUnblockImmunityCheck value: %d", DisUBImCheck);
	#endif
}

// some more

AdminMenu_GetPunishPhrase(client, target, String:name[], length)
{
	decl String:Buffer[192];
	if (g_MuteType[target] > bNot && g_GagType[target] > bNot)
		Format(Buffer, sizeof(Buffer), "%T", "AdminMenu_Display_Silenced", client, name);
	else if (g_MuteType[target] > bNot)
		Format(Buffer, sizeof(Buffer), "%T", "AdminMenu_Display_Muted", client, name);
	else if (g_GagType[target] > bNot)
		Format(Buffer, sizeof(Buffer), "%T", "AdminMenu_Display_Gagged", client, name);
	else
		Format(Buffer, sizeof(Buffer), "%T", "AdminMenu_Display_None", client, name);

	strcopy(name, length, Buffer);
}

bool:Bool_ValidMenuTarget(client, target)
{
	if (target <= 0)
	{
		if (client)
			PrintToChat(client, "%s%t", PREFIX, "AdminMenu_Not_Available");
		else
			ReplyToCommand(client, "%s%t", PREFIX, "AdminMenu_Not_Available");

		return false;
	}
	else if (!CanUserTarget(client, target))
	{
		if (client)
			PrintToChat(client, "%s%t", PREFIX, "Command_Target_Not_Targetable");
		else
			ReplyToCommand(client, "%s%t", PREFIX, "Command_Target_Not_Targetable");

		return false;
	}

	return true;
}

stock bool:IsAllowedBlockLength(admin, length, target_count = 1)
{
	if (target_count == 1) {
		if (!ConfigMaxLength)
			return true;	// Restriction disabled
		if (!admin)
			return true;	// all allowed for console
		if (AdmHasFlag(admin))
			return true;	// all allowed for admins with special flag
		if (!length || length > ConfigMaxLength)
			return false;
		else
			return true;
	}
	else
	{
		if (length < 0)
			return true;
		if (!length)
			return false;
		if (length > MAX_TIME_MULTI)
			return false;
		else
			return true;
	}
}

stock bool:AdmHasFlag(admin)
{
	return admin && CheckCommandAccess(admin, "", UNBLOCK_FLAG, true);
}

stock _:GetAdmImmunity(admin)
{
	if (admin > 0 && GetUserAdmin(admin) != INVALID_ADMIN_ID)
		return GetAdminImmunityLevel(GetUserAdmin(admin));
	else
		return 0;
}

stock _:GetClientUserId2(client)
{
	if (client)
		return GetClientUserId(client);
	else
		return 0;	// for CONSOLE
}

stock ForcePlayerRecheck()
{
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsClientAuthorized(i) && !IsFakeClient(i) && g_hPlayerRecheck[i] == INVALID_HANDLE)
		{
			#if defined DEBUG
			{
				decl String:clientAuth[64];
				GetClientAuthString(i, clientAuth, sizeof(clientAuth));
				LogToFile(logFile, "Creating Recheck timer for %s", clientAuth);
			}
			#endif
			g_hPlayerRecheck[i] = CreateTimer(float(i), ClientRecheck, GetClientUserId(i));
		}
	}
}

stock bool:NotApplyToThisServer(srvID)
{
	if (ConfigWhiteListOnly && FindValueInArray(g_hServersWhiteList, srvID) == -1)
		return true;
	else
		return false;
}

stock MarkClientAsUnMuted(target)
{
	g_MuteType[target] = bNot;
	g_iMuteTime[target] = 0;
	g_iMuteLength[target] = 0;
	g_iMuteLevel[target] = -1;
	g_sMuteAdmin[target][0] = '\0';
	g_sMuteReason[target][0] = '\0';
}

stock MarkClientAsUnGagged(target)
{
	g_GagType[target] = bNot;
	g_iGagTime[target] = 0;
	g_iGagLength[target] = 0;
	g_iGagLevel[target] = -1;
	g_sGagAdmin[target][0] = '\0';
	g_sGagReason[target][0] = '\0';
}

stock MarkClientAsMuted(target, time = NOW, length = -1, const String:adminName[] = "CONSOLE", adminImmunity = 0, const String:reason[] = "")
{
	if (time)
		g_iMuteTime[target] = time;
	else
		g_iMuteTime[target] = GetTime();

	g_iMuteLength[target] = length;
	g_iMuteLevel[target] = adminImmunity;
	strcopy(g_sMuteAdmin[target], sizeof(g_sMuteAdmin[]), adminName);
	strcopy(g_sMuteReason[target], sizeof(g_sMuteReason[]), reason);

	if (length > 0)
		g_MuteType[target] = bTime;
	else if (length == 0)
		g_MuteType[target] = bPerm;
	else
		g_MuteType[target] = bSess;
}

stock MarkClientAsGagged(target, time = NOW, length = -1, const String:adminName[] = "CONSOLE", adminImmunity = 0, const String:reason[] = "")
{
	if (time)
		g_iGagTime[target] = time;
	else
		g_iGagTime[target] = GetTime();

	g_iGagLength[target] = length;
	g_iGagLevel[target] = adminImmunity;
	strcopy(g_sGagAdmin[target], sizeof(g_sGagAdmin[]), adminName);
	strcopy(g_sGagReason[target], sizeof(g_sGagReason[]), reason);

	if (length > 0)
		g_GagType[target] = bTime;
	else if (length == 0)
		g_GagType[target] = bPerm;
	else
		g_GagType[target] = bSess;
}

stock CloseMuteExpireTimer(target)
{
	if (g_hMuteExpireTimer[target] != INVALID_HANDLE && CloseHandle(g_hMuteExpireTimer[target]))
		g_hMuteExpireTimer[target] = INVALID_HANDLE;
}

stock CloseGagExpireTimer(target)
{
	if (g_hGagExpireTimer[target] != INVALID_HANDLE && CloseHandle(g_hGagExpireTimer[target]))
		g_hGagExpireTimer[target] = INVALID_HANDLE;
}

stock CreateMuteExpireTimer(target, remainingTime = 0)
{
	if (g_iMuteLength[target] > 0)
	{
		if (remainingTime)
			g_hMuteExpireTimer[target] = CreateTimer(float(remainingTime), Timer_MuteExpire, GetClientUserId(target), TIMER_FLAG_NO_MAPCHANGE);
		else
			g_hMuteExpireTimer[target] = CreateTimer(float(g_iMuteLength[target] * 60), Timer_MuteExpire, GetClientUserId(target), TIMER_FLAG_NO_MAPCHANGE);
	}
}

stock CreateGagExpireTimer(target, remainingTime = 0)
{
	if (g_iGagLength[target] > 0)
	{
		if (remainingTime)
			g_hGagExpireTimer[target] = CreateTimer(float(remainingTime), Timer_GagExpire, GetClientUserId(target), TIMER_FLAG_NO_MAPCHANGE);
		else
			g_hGagExpireTimer[target] = CreateTimer(float(g_iGagLength[target] * 60), Timer_GagExpire, GetClientUserId(target), TIMER_FLAG_NO_MAPCHANGE);
	}
}

stock PerformUnMute(target)
{
	MarkClientAsUnMuted(target);
	BaseComm_SetClientMute(target, false);
	CloseMuteExpireTimer(target);
}

stock PerformUnGag(target)
{
	MarkClientAsUnGagged(target);
	BaseComm_SetClientGag(target, false);
	CloseGagExpireTimer(target);
}

stock PerformMute(target, time = NOW, length = -1, const String:adminName[] = "CONSOLE", adminImmunity = 0, const String:reason[] = "", remaining_time = 0)
{
	MarkClientAsMuted(target, time, length, adminName, adminImmunity, reason);
	BaseComm_SetClientMute(target, true);
	CreateMuteExpireTimer(target, remaining_time);
}

stock PerformGag(target, time = NOW, length = -1, const String:adminName[] = "CONSOLE", adminImmunity = 0, const String:reason[] = "", remaining_time = 0)
{
	MarkClientAsGagged(target, time, length, adminName, adminImmunity, reason);
	BaseComm_SetClientGag(target, true);
	CreateGagExpireTimer(target, remaining_time);
}

stock SavePunishment(admin = 0, target, type, length = -1 , const String:reason[] = "")
{
	if (type < TYPE_MUTE || type > TYPE_SILENCE)
		return;

	// target information
	new String:targetAuth[64];
	GetClientAuthString(target, targetAuth, sizeof(targetAuth));

	new String:adminIp[24];
	new String:adminAuth[64];
	if (admin)
	{
		GetClientIP(admin, adminIp, sizeof(adminIp));
		GetClientAuthString(admin, adminAuth, sizeof(adminAuth));
	}
	else
	{
		// setup dummy adminAuth and adminIp for server
		strcopy(adminAuth, sizeof(adminAuth), "STEAM_ID_SERVER");
		strcopy(adminIp, sizeof(adminIp), ServerIp);
	}

	new String:sName[MAX_NAME_LENGTH];
	strcopy(sName, sizeof(sName), g_sName[target]);

	// all data cached before calling asynchronous functions
	new Handle:dataPack = CreateDataPack();
	WritePackCell(dataPack, GetClientUserId2(admin));
	WritePackCell(dataPack, length);
	WritePackCell(dataPack, type);
	WritePackString(dataPack, reason);
	WritePackString(dataPack, sName);
	WritePackString(dataPack, targetAuth);
	WritePackString(dataPack, adminAuth);
	WritePackString(dataPack, adminIp);

	if (DB_Connect())
	{
		// Accepts time in minutes, writes to db in seconds! In all over places in plugin - length is in minutes.
		new String:banName[MAX_NAME_LENGTH * 2 + 1];
		new String:banReason[256 * 2 + 1];
		new String:sAuthidEscaped[64 * 2 + 1];
		new String:sAdminAuthIdEscaped[64 * 2 + 1];
		new String:sAdminAuthIdYZEscaped[64 * 2 + 1];
		decl String:sQuery[4096], String:sQueryAdm[512], String:sQueryVal[1024];
		new String:sQueryMute[1024], String:sQueryGag[1024];

		// escaping everything
		SQL_EscapeString(g_hDatabase, sName, banName, sizeof(banName));
		SQL_EscapeString(g_hDatabase, reason, banReason, sizeof(banReason));
		SQL_EscapeString(g_hDatabase, targetAuth, sAuthidEscaped, sizeof(sAuthidEscaped));
		SQL_EscapeString(g_hDatabase, adminAuth, sAdminAuthIdEscaped, sizeof(sAdminAuthIdEscaped));
		SQL_EscapeString(g_hDatabase, adminAuth[8], sAdminAuthIdYZEscaped, sizeof(sAdminAuthIdYZEscaped));

		// bid	authid	name	created ends lenght reason aid adminip	sid	removedBy removedType removedon type ureason
		FormatEx(sQueryAdm, sizeof(sQueryAdm),
			"IFNULL((SELECT aid FROM %s_admins WHERE authid = '%s' OR authid REGEXP '^STEAM_[0-9]:%s$'), 0)",
			DatabasePrefix, sAdminAuthIdEscaped, sAdminAuthIdYZEscaped);

		// authid name, created, ends, length, reason, aid, adminIp, sid
		FormatEx(sQueryVal, sizeof(sQueryVal),
			"'%s', '%s', UNIX_TIMESTAMP(), UNIX_TIMESTAMP() + %d, %d, '%s', %s, '%s', %d",
			sAuthidEscaped, banName, length*60, length*60, banReason, sQueryAdm, adminIp, serverID);

		if (type == TYPE_MUTE || type == TYPE_SILENCE)
		{
			FormatEx(sQueryMute, sizeof(sQueryMute), "(%s, %d)", sQueryVal, TYPE_MUTE);
		}
		if (type == TYPE_GAG || type == TYPE_SILENCE)
		{
			FormatEx(sQueryGag, sizeof(sQueryGag), "(%s, %d)", sQueryVal, TYPE_GAG);
		}

		// litle fucking magic - one query for all actions
		FormatEx(sQuery, sizeof(sQuery),
			"INSERT INTO %s_comms (authid, name, created, ends, length, reason, aid, adminIp, sid, type) VALUES %s%s%s",
			DatabasePrefix, sQueryMute, type == TYPE_SILENCE ? ", " : "", sQueryGag);

		#if defined LOG_QUERIES
			LogToFile(logQuery, "UTIL_InsertBlock. QUERY: %s", sQuery);
		#endif

		SQL_TQuery(g_hDatabase, VerifyInsertB, sQuery, dataPack, DBPrio_High);
	}
	else
		UTIL_InsertTempBlock(length, type, sName, targetAuth, reason, adminAuth, adminIp, dataPack);
}

stock ShowActivityToServer(admin, type, length, String:reason[], String:targetName[])
{
	new String:actionName[32], String:translationName[64];
	switch(type)
	{
		case TYPE_MUTE:
		{
			if (length > 0)
				strcopy(actionName, sizeof(actionName), "Muted");
			else if (length == 0)
				strcopy(actionName, sizeof(actionName), "Permamuted");
			else	// temp block
				strcopy(actionName, sizeof(actionName), "Temp muted");
		}
		//-------------------------------------------------------------------------------------------------
		case TYPE_GAG:
		{
			if (length > 0)
				strcopy(actionName, sizeof(actionName), "Gagged");
			else if (length == 0)
				strcopy(actionName, sizeof(actionName), "Permagagged");
			else	//temp block
				strcopy(actionName, sizeof(actionName), "Temp gagged");
		}
		//-------------------------------------------------------------------------------------------------
		case TYPE_SILENCE:
		{
			if (length > 0)
				strcopy(actionName, sizeof(actionName), "Silenced");
			else if (length == 0)
				strcopy(actionName, sizeof(actionName), "Permasilenced");
			else	//temp block
				strcopy(actionName, sizeof(actionName), "Temp silenced");
		}
		default:
		{
			return;
		}
	}
	Format(translationName, sizeof(translationName), "%s %s", actionName, reason[0] == '\0' ? "player" : "player reason");
	if (length > 0)
		ShowActivity2(admin, PREFIX, "%t", translationName, targetName, length, reason);
	else
		ShowActivity2(admin, PREFIX, "%t", translationName, targetName, reason);
}

// Natives //
public Native_SetClientMute(Handle:hPlugin, numParams)
{
	new target = GetNativeCell(1);
	if (target < 1 || target > MaxClients)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", target);
	}

	if (!IsClientInGame(target))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not in game", target);
	}

	new bool:muteState = GetNativeCell(2);
	new muteLength = GetNativeCell(3);
	if (muteState && muteLength == 0)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Permanent mute is not allowed!");
	}

	new bool:bSaveToDB = GetNativeCell(4);
	if (!muteState && bSaveToDB)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Removing punishments from DB is not allowed!");
	}

	decl String:sReason[256];
	GetNativeString(5, sReason, sizeof(sReason));

	if (muteState)
	{
		if (g_MuteType[target] > bNot)
		{
			return false;
		}

		PerformMute(target, _, muteLength, _, ConsoleImmunity, sReason);

		if (bSaveToDB)
			SavePunishment(_, target, TYPE_MUTE, muteLength, sReason);
	}
	else
	{
		if (g_MuteType[target] == bNot)
		{
			return false;
		}

		PerformUnMute(target);
	}

	return true;
}

public Native_SetClientGag(Handle:hPlugin, numParams)
{
	new target = GetNativeCell(1);
	if (target < 1 || target > MaxClients)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", target);
	}

	if (!IsClientInGame(target))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not in game", target);
	}

	new bool:gagState = GetNativeCell(2);
	new gagLength = GetNativeCell(3);
	if (gagState && gagLength == 0)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Permanent gag is not allowed!");
	}

	new bool:bSaveToDB = GetNativeCell(4);
	if (!gagState && bSaveToDB)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Removing punishments from DB is not allowed!");
	}

	decl String:sReason[256];
	GetNativeString(5, sReason, sizeof(sReason));

	if (gagState)
	{
		if (g_GagType[target] > bNot)
		{
			return false;
		}

		PerformGag(target, _, gagLength, _, ConsoleImmunity, sReason);

		if (bSaveToDB)
			SavePunishment(_, target, TYPE_GAG, gagLength, sReason);
	}
	else
	{
		if (g_GagType[target] == bNot)
		{
			return false;
		}

		PerformUnGag(target);
	}

	return true;
}

public Native_GetClientMuteType(Handle:hPlugin, numParams)
{
	new target = GetNativeCell(1);
	if (target < 1 || target > MaxClients)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", target);
	}

	if (!IsClientInGame(target))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not in game", target);
	}

	return bType:g_MuteType[target];
}

public Native_GetClientGagType(Handle:hPlugin, numParams)
{
	new target = GetNativeCell(1);
	if (target < 1 || target > MaxClients)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", target);
	}

	if (!IsClientInGame(target))
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not in game", target);
	}

	return bType:g_GagType[target];
}
//Yarr!