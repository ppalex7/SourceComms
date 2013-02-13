#pragma semicolon 1

#include <sourcemod>
#include <basecomm>

#undef REQUIRE_PLUGIN
#include <adminmenu>
#include <updater>

#define UNBLOCK_FLAG ADMFLAG_CUSTOM2
#define DATABASE "sourcecomms"

//#define DEBUG
//#define LOG_QUERIES

// Do not edit below this line //
//-----------------------------//

#define VERSION "0.8.82"
#define PREFIX "\x04[SourceComms]\x01 "

#define UPDATE_URL    "http://z.tf2news.ru/repo/sc-updatefile.txt"

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
	ConfigStateTimes
}

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
new Handle:Database;
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
new ProcessQueueTime = 5;
new bool:LateLoaded;

new serverID = -1;

/* List menu */
enum PeskyPanels
{
	curTarget,
	curIndex,
	viewingMute,
	viewingGag,
	viewingList
}
new g_iPeskyPanels[MAXPLAYERS + 1][PeskyPanels];

/* Blocks info storage */
enum bType{
	bNot = 0,
	bTime,
	bPerm,
	bSess
}

new String:g_sName[MAXPLAYERS + 1][MAX_NAME_LENGTH];

new bType:g_MuteType[MAXPLAYERS + 1];
new g_iMuteTime[MAXPLAYERS + 1];
new g_iMuteLength[MAXPLAYERS + 1]; // in sec
new g_iMuteLevel[MAXPLAYERS + 1]; // immunity level of admin
new String:g_sMuteAdmin[MAXPLAYERS + 1][MAX_NAME_LENGTH];
new String:g_sMuteReason[MAXPLAYERS + 1][128];

new bType:g_GagType[MAXPLAYERS + 1];
new g_iGagTime[MAXPLAYERS + 1];
new g_iGagLength[MAXPLAYERS + 1]; // in sec
new g_iGagLevel[MAXPLAYERS + 1]; // immunity level of admin
new String:g_sGagAdmin[MAXPLAYERS + 1][MAX_NAME_LENGTH];
new String:g_sGagReason[MAXPLAYERS + 1][128];

public Plugin:myinfo =
{
	name = "SourceComms",
	author = "Alex",
	description = "Advanced punishments management for the Source engine in SourceBans style.",
	version = VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=207176"
};

#if SOURCEMOD_V_MAJOR >= 1 && SOURCEMOD_V_MINOR >= 3
public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
#else
public bool:AskPluginLoad(Handle:myself, bool:late, String:error[], err_max)
#endif
{
	LateLoaded = late;

	#if SOURCEMOD_V_MAJOR >= 1 && SOURCEMOD_V_MINOR >= 3
		return APLRes_Success;
	#else
		return true;
	#endif
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

	CreateConVar("sourcecomms_version", VERSION, _, FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
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
		LogToFile(logFile, "Plugin loading. Version %s", VERSION);
	#endif

	// Catch config error
	if (!SQL_CheckConfig(DATABASE))
	{
		LogToFile(logFile, "Database failure: Could not find Database conf %s", DATABASE);
		SetFailState("Database failure: Could not find Database conf  %s", DATABASE);
		return;
	}
	SQL_TConnect(GotDatabase, DATABASE);

	InitializeBackupDB();

	ServerInfo();

	// This timer is what processes the SQLite queue when the database is unavailable
	CreateTimer(float(ProcessQueueTime * 60), ProcessQueue);

	/* Account for late loading */
	if (LateLoaded)
	{
		#if defined DEBUG
			LogToFile(logFile, "Plugin late loaded");
		#endif
		for (new i = 1; i <= GetMaxClients(); i++)
		{
			if (IsClientInGame(i) && IsClientAuthorized(i) && !IsFakeClient(i))
			{
				#if defined DEBUG
				{
					decl String:clientAuth[64];
					GetClientAuthString(i, clientAuth, sizeof(clientAuth));
					LogToFile(logFile, "Creating Recheck timer for %s", clientAuth);
				}
				#endif
				GetClientName(i, g_sName[i], sizeof(g_sName[]));
				g_hPlayerRecheck[i] = CreateTimer(RetryTime + i, ClientRecheck, GetClientUserId(i));
			}
		}
	}

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
	LogToFile(logFile, "Plugin updated. Old version was %s. Now reloading.", VERSION);

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
	if (g_hPlayerRecheck[client] != INVALID_HANDLE)
	{
		KillTimer(g_hPlayerRecheck[client]);
		g_hPlayerRecheck[client] = INVALID_HANDLE;
	}

	if (client > 0 && !IsFakeClient(client))
	{
		if (g_hMuteExpireTimer[client] != INVALID_HANDLE && CloseHandle(g_hMuteExpireTimer[client]))
		{
			g_hMuteExpireTimer[client] = INVALID_HANDLE;
			#if defined DEBUG
			{
				decl String:clientAuth[64];
				GetClientAuthString(client, clientAuth, sizeof(clientAuth));
				LogToFile(logFile, "Closed MuteExpire Timer for %s OnClientDisconnect", clientAuth);
			}
			#endif
		}

		if (g_hGagExpireTimer[client] != INVALID_HANDLE && CloseHandle(g_hGagExpireTimer[client]))
		{
			g_hGagExpireTimer[client] = INVALID_HANDLE;
			#if defined DEBUG
			{
				decl String:clientAuth[64];
				GetClientAuthString(client, clientAuth, sizeof(clientAuth));
				LogToFile(logFile, "Closed GagExpire Timer for %s OnClientDisconnect", clientAuth);
			}
			#endif
		}
	}
}

public bool:OnClientConnect(client, String:rejectmsg[], maxlen)
{
	g_bPlayerStatus[client] = false;
	return true;
}

public OnClientConnected(client)
{
	if (client > 0 && !IsFakeClient(client))
	{
		g_sName[client][0] = '\0';

		g_MuteType[client] = bNot;
		g_iMuteTime[client] = 0;
		g_iMuteLength[client] = 0;
		g_iMuteLevel[client] = -1;
		g_sMuteAdmin[client][0] = '\0';
		g_sMuteReason[client][0] = '\0';

		g_GagType[client] = bNot;
		g_iGagTime[client] = 0;
		g_iGagLength[client] = 0;
		g_iGagLevel[client] = -1;
		g_sGagAdmin[client][0] = '\0';
		g_sGagReason[client][0] = '\0';
	}
}

public OnClientPostAdminCheck(client)
{
	decl String:clientAuth[64];
	GetClientAuthString(client, clientAuth, sizeof(clientAuth));
	GetClientName(client, g_sName[client], sizeof(g_sName[]));

	/* Do not check bots nor check player with lan steamid. */
	if (clientAuth[0] == 'B' || clientAuth[9] == 'L' || Database == INVALID_HANDLE) // || Database == INVALID_HANDLE ??
	{
		g_bPlayerStatus[client] = true;
		return;
	}

	if (client > 0 && !IsFakeClient(client))
	{
		decl String:Query[512];
		FormatEx(Query, sizeof(Query), "SELECT (c.ends - UNIX_TIMESTAMP()) as remaining, c.length, c.type, c.created, c.reason, a.user, IF (a.immunity>=g.immunity, a.immunity, IFNULL(g.immunity,0)) as immunity, c.aid FROM %s_comms c LEFT JOIN %s_admins a ON a.aid=c.aid LEFT JOIN %s_srvgroups g ON g.name = a.srv_group WHERE c.authid REGEXP '^STEAM_[0-9]:%s$' AND (length = '0' OR ends > UNIX_TIMESTAMP()) AND RemoveType IS NULL",
				DatabasePrefix, DatabasePrefix, DatabasePrefix, clientAuth[8]);
		#if defined LOG_QUERIES
			LogToFile(logQuery, "Checking blocks for: %s. QUERY: %s", clientAuth, Query);
		#endif
		SQL_TQuery(Database, VerifyBlocks, Query, GetClientUserId(client), DBPrio_High);
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
				g_MuteType[client] = bSess;
				g_iMuteTime[client] = GetTime();
				g_iMuteLength[client] = -1;
				g_iMuteLevel[client] = ConsoleImmunity;
				g_sMuteAdmin[client] = "CONSOLE";
				g_sMuteReason[client] = "Muted through natives";

				decl String:adminIp[24];
				decl String:adminAuth[64];
				// setup dummy adminAuth and adminIp for server
				strcopy(adminAuth, sizeof(adminAuth), "STEAM_ID_SERVER");
				strcopy(adminIp, sizeof(adminIp), ServerIp);

				// target information
				decl String:auth[64];
				GetClientAuthString(client, auth, sizeof(auth));

				// Pack everything into a data pack so we can retain it trough sql-callback
				new Handle:dataPack = CreateDataPack();
				new Handle:reasonPack = CreateDataPack();
				WritePackString(reasonPack, g_sMuteReason[client]);
				WritePackCell(dataPack, -1);
				WritePackCell(dataPack, TYPE_MUTE);
				WritePackCell(dataPack, _:reasonPack);
				WritePackString(dataPack, g_sName[client]);
				WritePackString(dataPack, auth);
				WritePackString(dataPack, adminAuth);
				WritePackString(dataPack, adminIp);

				ResetPack(dataPack);
				ResetPack(reasonPack);
				if (Database != INVALID_HANDLE)
				{
					UTIL_InsertBlock(-1, TYPE_MUTE, g_sName[client], auth, g_sMuteReason[client], adminAuth, adminIp, dataPack); // длина блокировки, тип, имя игрока, стим игрока, причина, стим админа, ип админа
				} else {
					UTIL_InsertTempBlock(-1, TYPE_MUTE, g_sName[client], auth, g_sMuteReason[client], adminAuth, adminIp);
					LogToFile(logFile, "We need insert to queue (calling UTIL_InsertTempBlock)");
				}
			}
		}
		else
		{
			if (g_MuteType[client] > bNot)
			{
				g_MuteType[client] = bNot;
				g_iMuteTime[client] = 0;
				g_iMuteLength[client] = 0;
				g_iMuteLevel[client] = -1;
				g_sMuteAdmin[client][0] = '\0';
				g_sMuteReason[client][0] = '\0';
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
				g_GagType[client] = bSess;
				g_iGagTime[client] = GetTime();
				g_iGagLength[client] = -1;
				g_iGagLevel[client] = ConsoleImmunity;
				g_sGagAdmin[client] = "CONSOLE";
				g_sGagReason[client] = "Gagged through natives";

				decl String:adminIp[24];
				decl String:adminAuth[64];
				// setup dummy adminAuth and adminIp for server
				strcopy(adminAuth, sizeof(adminAuth), "STEAM_ID_SERVER");
				strcopy(adminIp, sizeof(adminIp), ServerIp);

				// target information
				decl String:auth[64];
				GetClientAuthString(client, auth, sizeof(auth));

				// Pack everything into a data pack so we can retain it trough sql-callback
				new Handle:dataPack = CreateDataPack();
				new Handle:reasonPack = CreateDataPack();
				WritePackString(reasonPack, g_sGagReason[client]);
				WritePackCell(dataPack, -1);
				WritePackCell(dataPack, TYPE_MUTE);
				WritePackCell(dataPack, _:reasonPack);
				WritePackString(dataPack, g_sName[client]);
				WritePackString(dataPack, auth);
				WritePackString(dataPack, adminAuth);
				WritePackString(dataPack, adminIp);

				ResetPack(dataPack);
				ResetPack(reasonPack);
				if (Database != INVALID_HANDLE)
				{
					UTIL_InsertBlock(-1, TYPE_GAG, g_sName[client], auth, g_sGagReason[client], adminAuth, adminIp, dataPack); // длина блокировки, тип, имя игрока, стим игрока, причина, стим админа, ип админа
				} else {
					UTIL_InsertTempBlock(-1, TYPE_GAG, g_sName[client], auth, g_sGagReason[client], adminAuth, adminIp);
					LogToFile(logFile, "We need insert to queue (calling UTIL_InsertTempBlock)");
				}
			}
		}
		else
		{
			if (g_GagType[client] > bNot)
			{
				g_GagType[client] = bNot;
				g_iGagTime[client] = 0;
				g_iGagLength[client] = 0;
				g_iGagLevel[client] = -1;
				g_sGagAdmin[client][0] = '\0';
				g_sGagReason[client][0] = '\0';
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

	return Plugin_Continue;
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
					g_iMuteTime[i] = GetTime();
					g_iMuteLength[i] = length / 60;
					g_iMuteLevel[i] = 99;
					g_sMuteAdmin[i] = "CONSOLE";
					g_sMuteReason[i][0] = '\0';
					PrintToChat(i, "%s%t", PREFIX, "Muted on connect");
					LogToFile(logFile, "%s is muted from web", clientAuth);

					if (length > 0)
					{
						g_MuteType[i] = bTime;
						#if defined DEBUG
							LogToFile(logFile, "Creating MuteExpire timer");
						#endif
						g_hMuteExpireTimer[i] = CreateTimer(float(length), Timer_MuteExpire, GetClientUserId(i), TIMER_FLAG_NO_MAPCHANGE);
					}
					else
						g_MuteType[i] = bPerm;

					BaseComm_SetClientMute(i, true);
				}
				if (g_GagType[i] == bNot && (type == 2 || type == 3))
				{
					g_iGagTime[i] = GetTime();
					g_iGagLength[i] = length / 60;
					g_iGagLevel[i] = 99;
					g_sGagAdmin[i] = "CONSOLE";
					g_sGagReason[i][0] = '\0';
					PrintToChat(i, "%s%t", PREFIX, "Gagged on connect");

					LogToFile(logFile, "%s is gagged from web", clientAuth);
					if (length > 0)
					{
						g_GagType[i] = bTime;
						#if defined DEBUG
							LogToFile(logFile, "Creating GagExpire timer");
						#endif
						g_hGagExpireTimer[i] = CreateTimer(float(length), Timer_GagExpire, GetClientUserId(i), TIMER_FLAG_NO_MAPCHANGE);
					}
					else
						g_GagType[i] = bPerm;

					BaseComm_SetClientGag(i, true);
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
					g_GagType[i] = bNot;
					g_iGagTime[i] = 0;
					g_iGagLength[i] = 0;
					g_iGagLevel[i] = -1;
					g_sGagAdmin[i][0] = '\0';
					g_sGagReason[i][0] = '\0';
					PrintToChat(i, "%s%t", PREFIX, "FWUngag");
					BaseComm_SetClientGag(i, false);
					LogToFile(logFile, "%s is ungagged from web", clientAuth);
					if (g_hGagExpireTimer[i] != INVALID_HANDLE && CloseHandle(g_hGagExpireTimer[i]))
						g_hGagExpireTimer[i] = INVALID_HANDLE;
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
					g_MuteType[i] = bNot;
					g_iMuteTime[i] = 0;
					g_iMuteLength[i] = 0;
					g_iMuteLevel[i] = -1;
					g_sMuteAdmin[i][0] = '\0';
					g_sMuteReason[i][0] = '\0';
					PrintToChat(i, "%s%t", PREFIX, "FWUnmute");
					BaseComm_SetClientMute(i, false);
					LogToFile(logFile, "%s is unmuted from web", clientAuth);
					if (g_hMuteExpireTimer[i] != INVALID_HANDLE && CloseHandle(g_hMuteExpireTimer[i]))
						g_hMuteExpireTimer[i] = INVALID_HANDLE;
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
	#if defined DEBUG
		LogToFile(logFile, "CommandGag()");
	#endif

	if (client && !CheckCommandAccess(client, "sm_gag", ADMFLAG_CHAT))
		return Plugin_Continue;

	if (args < 1)
	{
		ReplyToCommand(client, "%sUsage: sm_gag <#userid|name> [time|0] [reason]", PREFIX);
		ReplyToCommand(client, "%s%t", PREFIX, "Usage_time", DefaultTime);
		return Plugin_Stop;
	}

	PrepareBlock(client, TYPE_GAG, args);
	return Plugin_Stop;
}

public Action:CommandMute(client, const String:command[], args)
{
	#if defined DEBUG
		LogToFile(logFile, "CommandMute()");
	#endif

	if (client && !CheckCommandAccess(client, "sm_mute", ADMFLAG_CHAT))
		return Plugin_Continue;

	if (args < 1)
	{
		ReplyToCommand(client, "%sUsage: sm_mute <#userid|name> [time|0] [reason]", PREFIX);
		ReplyToCommand(client, "%s%t", PREFIX, "Usage_time", DefaultTime);
		return Plugin_Stop;
	}

	PrepareBlock(client, TYPE_MUTE, args);
	return Plugin_Stop;
}

public Action:CommandSilence(client, const String:command[], args)
{
	#if defined DEBUG
		LogToFile(logFile, "CommandSilence()");
	#endif

	if (client && !CheckCommandAccess(client, "sm_silence", ADMFLAG_CHAT))
		return Plugin_Continue;

	if (args < 1)
	{
		ReplyToCommand(client, "%sUsage: sm_silence <#userid|name> [time|0] [reason]", PREFIX);
		ReplyToCommand(client, "%s%t", PREFIX, "Usage_time", DefaultTime);
		return Plugin_Stop;
	}

	PrepareBlock(client, TYPE_SILENCE, args);
	return Plugin_Stop;
}

public Action:CommandUnGag(client, const String:command[], args)
{
	#if defined DEBUG
		LogToFile(logFile, "CommandUnGag()");
	#endif

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
	#if defined DEBUG
		LogToFile(logFile, "CommandUnMute()");
	#endif

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
	#if defined DEBUG
		LogToFile(logFile, "CommandUnSilence()");
	#endif

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

public Action:PrepareBlock(client, type_block, args)
{
	#if defined DEBUG
		LogToFile(logFile, "PrepareBlock(type %d)", type_block);
	#endif

	new String:sBuffer[256], String:sArg[3][192], String:sReason[256];
	GetCmdArgString(sBuffer, sizeof(sBuffer));
	ExplodeString(sBuffer, " ", sArg, 3, 192, true);

	// Get the target, find target returns a message on failure so we do not
	new target = FindTarget(client, sArg[0], true);
	if (target == -1)
	{
		#if defined DEBUG
			LogToFile(logFile, "target not found (-1)");
		#endif

		return Plugin_Stop;
	}

	// Get the ban time
	new time;
	if(!StringToIntEx(sArg[1], time))	// not valid number in second argument
	{
		time = DefaultTime;
		Format(sReason, sizeof(sReason), "%s %s", sArg[1], sArg[2]);
	}
	else
		strcopy(sReason, sizeof(sReason), sArg[2]);

	#if defined DEBUG
		LogToFile(logFile, "Calling CreateBlock cl %d, target %d, time %d, type %d, reason %s", client, target, time, type_block, sArg[2]);
	#endif

	CreateBlock(client, target, time, type_block, sReason);
	return Plugin_Stop;
}

public Action:PrepareUnBlock(client, type_block, args)
{
	#if defined DEBUG
		LogToFile(logFile, "PrepareUnBlock(type %d)", type_block);
	#endif

	new String:sBuffer[256], String:sArg[2][192];
	GetCmdArgString(sBuffer, sizeof(sBuffer));
	ExplodeString(sBuffer, " ", sArg, 2, 192, true);

	// Get the target, find target returns a message on failure so we do not
	new target = FindTarget(client, sArg[0], true);
	if (target == -1)
	{
		#if defined DEBUG
			LogToFile(logFile, "target not found (-1)");
		#endif

		return Plugin_Stop;
	}

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
	{
		return;
	}

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

	new Handle:hMenu = CreateMenu(MenuHandler_MenuTarget);	// Общая менюшка - список игроков. Почти полная для блокировок и почти пустая - для разблокировок
	SetMenuTitle(hMenu, Title);
	SetMenuExitBackButton(hMenu, true);

	if (type <= 3)	// Mute, gag, silence
	{
		for (new i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && !IsFakeClient(i))
			{
				strcopy(Title, sizeof(Title), g_sName[i]);
				AdminMenu_GetPunishPhrase(client, i, Title, sizeof(Title));
				Format(Option, sizeof(Option), "%d %d", GetClientUserId(i), type);
				AddMenuItem(hMenu, Option, Title, (CanUserTarget(client, i) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED));
			}
		}
	}
	else		// UnMute, ungag, unsilence
	{
		new iClients;
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
			}
			AddMenuItem(hMenu, "0", Title, ITEMDRAW_DISABLED);
		}
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
		Format(sTemp, sizeof(sTemp), "%d %d %d", GetClientUserId(target), type, i);	// TargetID TYPE_BLOCK index_of_Time
		AddMenuItem(hMenu, sTemp, g_sTimeDisplays[i]);
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

				if (iNumReasons) // есть что показывать (причины)
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
				if (lengthIndex >= 0 && lengthIndex <= iNumTimes)	// а вдруг погода нелетная?
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
	if (hndl == INVALID_HANDLE)
	{
		LogToFile(logFile, "Database failure: %s.", error);
		return;
	}

	Database = hndl;

	decl String:query[128];
	FormatEx(query, sizeof(query), "SET NAMES \"UTF8\"");
	#if defined LOG_QUERIES
		LogToFile(logQuery, "Set encoding. QUERY: %s", query);
	#endif
	SQL_TQuery(Database, ErrorCheckCallback, query);
}

public VerifyInsertB(Handle:owner, Handle:hndl, const String:error[], any:dataPack)
{
	if (dataPack == INVALID_HANDLE)
	{
		LogToFile(logFile, "Block Failed: %s", error);
		return;
	}

	if (hndl == INVALID_HANDLE || error[0])
	{
		LogToFile(logFile, "Verify Insert Query Failed: %s", error);

		ResetPack(dataPack);
		new time = ReadPackCell(dataPack);
		new type = ReadPackCell(dataPack);
		new Handle:reasonPack = Handle:ReadPackCell(dataPack);
		decl String:reason[128];
		ReadPackString(reasonPack, reason, sizeof(reason));
		new String:name[MAX_NAME_LENGTH];
		ReadPackString(dataPack, name, sizeof(name));
		decl String:auth[64];
		ReadPackString(dataPack, auth, sizeof(auth));
		decl String:adminAuth[32];
		ReadPackString(dataPack, adminAuth, sizeof(adminAuth));
		decl String:adminIp[20];
		ReadPackString(dataPack, adminIp, sizeof(adminIp));
		ResetPack(dataPack);
		ResetPack(reasonPack);

		UTIL_InsertTempBlock(time, type, name, auth, reason, adminAuth, adminIp);

		if (reasonPack != INVALID_HANDLE)
		{
			CloseHandle(reasonPack);
		}
		CloseHandle(dataPack);

		return;
	}
	CloseHandle(dataPack);
}

public SelectUnBlockCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	decl String:adminAuth[30], String:targetAuth[30], String:reason[128];
	new String:unbanReason[256];
	ResetPack(data);
	new adminUserID = ReadPackCell(data);
	new targetUserID = ReadPackCell(data);
	new type = ReadPackCell(data);
	ReadPackString(data, reason, sizeof(reason));
	ReadPackString(data, adminAuth, sizeof(adminAuth));
	ReadPackString(data, targetAuth, sizeof(targetAuth));
	SQL_EscapeString(Database, reason, unbanReason, sizeof(unbanReason));
	CloseHandle(data);	// Need to close datapack

	new admin = GetClientOfUserId(adminUserID);
	new target = GetClientOfUserId(targetUserID);

	new AdmImmunity, bool:AdmHasFlag = false;
	if (admin > 0)
	{
		AdmImmunity = GetAdminImmunityLevel(GetUserAdmin(admin));
		AdmHasFlag = CheckCommandAccess(admin, "", UNBLOCK_FLAG, true) ;
	}
	else
		AdmImmunity = 0;
	new bool:AdmImCheck = (DisUBImCheck == 0 && ((type == TYPE_MUTE && AdmImmunity > g_iMuteLevel[target]) || (type == TYPE_GAG && AdmImmunity > g_iGagLevel[target]) || (type == TYPE_SILENCE && AdmImmunity > g_iMuteLevel[target] && AdmImmunity > g_iGagLevel[target]) ) );

	new bool:errorCheck = false;
	// If error is not an empty string the query failed
	if (error[0] != '\0')
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
		errorCheck = true;
	}

	// If there was no results then a ban does not exist for that id
	if (hndl == INVALID_HANDLE || !SQL_GetRowCount(hndl))
	{
		if (admin && IsClientInGame(admin))
		{
			PrintToChat(admin, "%s%t", PREFIX, "No blocks found", targetAuth);
		} else {
			PrintToServer("%s%T", PREFIX, "No blocks found", LANG_SERVER, targetAuth);
		}
		errorCheck = true;
	}

	if (errorCheck)
	{
		#if defined DEBUG
			LogToFile(logFile, "we have errors in SelectUnBlockCallback");
			LogToFile(logFile, "WHO WE ARE CHECKING!");
			if (!admin)
				LogToFile(logFile, "we are console (possibly)");
			if (AdmHasFlag)
				LogToFile(logFile, "we have special flag");
		#endif

		// We have some error.... Check access for unblock without db changes (temporary unblock)
		if (!admin || AdmHasFlag || AdmImCheck)	//can, if we are console or have special flag
		{
			switch(type)
			{
				case TYPE_MUTE:
				{
					g_MuteType[target] = bNot;
					g_iMuteTime[target] = 0;
					g_iMuteLength[target] = 0;
					g_iMuteLevel[target] = -1;
					g_sMuteAdmin[target][0] = '\0';
					g_sMuteReason[target][0] = '\0';
					BaseComm_SetClientMute(target, false);
					if (g_hMuteExpireTimer[target] != INVALID_HANDLE && CloseHandle(g_hMuteExpireTimer[target]))
					{
						g_hMuteExpireTimer[target] = INVALID_HANDLE;
						#if defined DEBUG
							LogToFile(logFile, "MuteExpireTimer killed on temporary unmute (DB problems)");
						#endif
					}
					ShowActivity2(admin, PREFIX, "%t", "Temp unmuted player", g_sName[target]);
					LogAction(admin, target, "\"%L\" temporary (DB problems) unmuted \"%L\" (reason \"%s\")", admin, target, reason);
				}
				//-------------------------------------------------------------------------------------------------
				case TYPE_GAG:
				{
					g_GagType[target] = bNot;
					g_iGagTime[target] = 0;
					g_iGagLength[target] = 0;
					g_iGagLevel[target] = -1;
					g_sGagAdmin[target][0] = '\0';
					g_sGagReason[target][0] = '\0';
					BaseComm_SetClientGag(target, false);
					if (g_hGagExpireTimer[target] != INVALID_HANDLE && CloseHandle(g_hGagExpireTimer[target]))
					{
						g_hGagExpireTimer[target] = INVALID_HANDLE;
						#if defined DEBUG
							LogToFile(logFile, "GagExpireTimer killed on temporary ungag (DB problems)");
						#endif
					}
					ShowActivity2(admin, PREFIX, "%t", "Temp ungagged player", g_sName[target]);
					LogAction(admin, target, "\"%L\" temporary (DB problems) ungagged \"%L\" (reason \"%s\")", admin, target, reason);
				}
				//-------------------------------------------------------------------------------------------------
				case TYPE_SILENCE:
				{
					g_MuteType[target] = bNot;
					g_iMuteTime[target] = 0;
					g_iMuteLength[target] = 0;
					g_iMuteLevel[target] = -1;
					g_sMuteAdmin[target][0] = '\0';
					g_sMuteReason[target][0] = '\0';
					BaseComm_SetClientMute(target, false);
					g_GagType[target] = bNot;
					g_iGagTime[target] = 0;
					g_iGagLength[target] = 0;
					g_iGagLevel[target] = -1;
					g_sGagAdmin[target][0] = '\0';
					g_sGagReason[target][0] = '\0';
					BaseComm_SetClientGag(target, false);
					if (g_hMuteExpireTimer[target] != INVALID_HANDLE && CloseHandle(g_hMuteExpireTimer[target]))
					{
						g_hMuteExpireTimer[target] = INVALID_HANDLE;
						#if defined DEBUG
							LogToFile(logFile, "MuteExpireTimer killed on temporary unsilence (DB problems)");
						#endif
					}
					if (g_hGagExpireTimer[target] != INVALID_HANDLE && CloseHandle(g_hGagExpireTimer[target]))
					{
						g_hGagExpireTimer[target] = INVALID_HANDLE;
						#if defined DEBUG
							LogToFile(logFile, "GagExpireTimer killed on temporary unsilence (DB problems)");
						#endif
					}
					ShowActivity2(admin, PREFIX, "%t", "Temp unsilenced player", g_sName[target]);
					LogAction(admin, target, "\"%L\" temporary (DB problems) unsilenced \"%L\" (reason \"%s\")", admin, target, reason);
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
		return;
	}

	// There is blocks
	if (hndl != INVALID_HANDLE)
	{
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
				if (AdmHasFlag)
					LogToFile(logFile, "we have special flag");
				if (AdmImmunity > cImmunity)
					LogToFile(logFile, "we have %d immunity and block has %d. we cool", AdmImmunity, cImmunity);
				LogToFile(logFile, "Fetched from DB: bid %d, iAID: %d, cAID: %d, cImmunity: %d, cType: %d", bid, iAID, cAID, cImmunity, cType);
			#endif

			// Checking - has we acces to unblock?
			if (iAID == cAID || AdmHasFlag || !admin || (DisUBImCheck == 0 && (AdmImmunity > cImmunity)))
			{
				// Ok! we have rights to unblock

				// UnMute/UnGag, Show & log activity
				switch(cType)
				{
					case TYPE_MUTE:
					{
						g_MuteType[target] = bNot;
						g_iMuteTime[target] = 0;
						g_iMuteLength[target] = 0;
						g_iMuteLevel[target] = -1;
						g_sMuteAdmin[target][0] = '\0';
						g_sMuteReason[target][0] = '\0';
						BaseComm_SetClientMute(target, false);
						if (g_hMuteExpireTimer[target] != INVALID_HANDLE && CloseHandle(g_hMuteExpireTimer[target]))
						{
							g_hMuteExpireTimer[target] = INVALID_HANDLE;
							#if defined DEBUG
								LogToFile(logFile, "MuteExpireTimer killed on unmute");
							#endif
						}
						ShowActivity2(admin, PREFIX, "%t", "Unmuted player", g_sName[target]);
						LogAction(admin, target, "\"%L\" unmuted \"%L\" (reason \"%s\")", admin, target, reason);
					}
					//-------------------------------------------------------------------------------------------------
					case TYPE_GAG:
					{
						g_GagType[target] = bNot;
						g_iGagTime[target] = 0;
						g_iGagLength[target] = 0;
						g_iGagLevel[target] = -1;
						g_sGagAdmin[target][0] = '\0';
						g_sGagReason[target][0] = '\0';
						BaseComm_SetClientGag(target, false);
						if (g_hGagExpireTimer[target] != INVALID_HANDLE && CloseHandle(g_hGagExpireTimer[target]))
						{
							g_hGagExpireTimer[target] = INVALID_HANDLE;
							#if defined DEBUG
								LogToFile(logFile, "GagExpireTimer killed on ungag");
							#endif
						}
						ShowActivity2(admin, PREFIX, "%t", "Ungagged player", g_sName[target]);
						LogAction(admin, target, "\"%L\" ungagged \"%L\" (reason \"%s\")", admin, target, reason);
					}
				}

				// Packing data for next callback
				new Handle:dataPack = CreateDataPack();
				WritePackCell(dataPack, adminUserID);
				WritePackCell(dataPack, targetUserID);
				WritePackCell(dataPack, cType);
				WritePackString(dataPack, g_sName[target]);

				decl String:query[1024];
				Format(query, sizeof(query),
					"UPDATE %s_comms SET RemovedBy = %d, RemoveType = 'U', RemovedOn = UNIX_TIMESTAMP(), ureason = '%s' WHERE bid = %d",
					DatabasePrefix, iAID, unbanReason, bid);
				#if defined LOG_QUERIES
					LogToFile(logQuery, "in SelectUnBlockCallback: Unblocking. QUERY: %s", query);
				#endif
				SQL_TQuery(Database, InsertUnBlockCallback, query, dataPack);
			}
			else
			{
				// sorry, we don't have permission to unblock!
				switch(cType)
				{
					case TYPE_MUTE:
					{
						ShowActivity2(admin, PREFIX, "%t", "No permission unmute", g_sName[target]);
						LogAction(admin, target, "\"%L\" tried (and didn't have permission) to unmute \"%L\" (reason \"%s\")", admin, target, reason);
					}
					//-------------------------------------------------------------------------------------------------
					case TYPE_GAG:
					{
						ShowActivity2(admin, PREFIX, "%t", "No permission ungag", g_sName[target]);
						LogAction(admin, target, "\"%L\" tried (and didn't have permission) to ungag \"%L\" (reason \"%s\")", admin, target, reason);
					}
				}
			}
		}
	}
}

public InsertUnBlockCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	// if the pack is good unpack it and close the handle
	new admin, target, type;
	new String:clientName[MAX_NAME_LENGTH];
	if (data != INVALID_HANDLE)
	{
		ResetPack(data);
		admin = GetClientOfUserId(ReadPackCell(data));
		target = GetClientOfUserId(ReadPackCell(data));
		type = ReadPackCell(data);
		ReadPackString(data, clientName, sizeof(clientName));
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
			LogAction(admin, -1, "\"%L\" removed mute for \"%L\" from DB", admin, target);
			if (admin && IsClientInGame(admin))
			{
				PrintToChat(admin, "%s%t", PREFIX, "successfully unmuted", clientName);
			} else {
				PrintToServer("%s%T", PREFIX, "successfully unmuted", LANG_SERVER, clientName);
			}
		}
		//-------------------------------------------------------------------------------------------------
		case TYPE_GAG:
		{
			LogAction(admin, -1, "\"%L\" removed gag for \"%L\" from DB", admin, target);
			if (admin && IsClientInGame(admin))
			{
				PrintToChat(admin, "%s%t", PREFIX, "successfully ungagged", clientName);
			} else {
				PrintToServer("%s%T", PREFIX, "successfully ungagged", LANG_SERVER, clientName);
			}
		}
	}
}

// ProcessQueueCallback is called as the result of selecting all the rows from the queue table
public ProcessQueueCallbackB(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE || strlen(error) > 0)
	{
		LogToFile(logFile, "Failed to retrieve queued bans from sqlite database, %s", error);
		return;
	}

	decl String:auth[64];
	new String:name[MAX_NAME_LENGTH];
	decl String:reason[128];
	decl String:adminAuth[64], String:adminIp[20];
	decl String:query[1024];
	decl String:banReason[256];
	new String:banName[MAX_NAME_LENGTH * 2  + 1];
	while(SQL_MoreRows(hndl))
	{
		// Oh noes! What happened?!
		if (!SQL_FetchRow(hndl))
			continue;

		// if we get to here then there are rows in the queue pending processing
		//steam_id TEXT, time INTEGER, start_time INTEGER, reason TEXT, name TEXT, admin_id TEXT, admin_ip TEXT, type INTEGER
		SQL_FetchString(hndl, 0, auth, sizeof(auth));
		new time = SQL_FetchInt(hndl, 1);
		new startTime = SQL_FetchInt(hndl, 2);
		SQL_FetchString(hndl, 3, reason, sizeof(reason));
		SQL_FetchString(hndl, 4, name, sizeof(name));
		SQL_FetchString(hndl, 5, adminAuth, sizeof(adminAuth));
		SQL_FetchString(hndl, 6, adminIp, sizeof(adminIp));
		new type = SQL_FetchInt(hndl, 7);
		SQL_EscapeString(SQLiteDB, name, banName, sizeof(banName));
		SQL_EscapeString(SQLiteDB, reason, banReason, sizeof(banReason));
		// all blocks should be entered into db!
		if ( serverID == -1 )
		{
			FormatEx(query, sizeof(query),
					"INSERT INTO %s_comms (authid, name, created, ends, length, reason, aid, adminIp, sid, type) VALUES \
					('%s', '%s', %d, %d, %d, '%s', IFNULL((SELECT aid FROM %s_admins WHERE authid = '%s' OR authid REGEXP '^STEAM_[0-9]:%s$'), '0'), '%s', \
					(SELECT sid FROM %s_servers WHERE ip = '%s' AND port = '%s' LIMIT 0,1), %d)",
					DatabasePrefix, auth, banName, startTime, (startTime + (time*60)), (time*60), banReason, DatabasePrefix, adminAuth, adminAuth[8], adminIp, DatabasePrefix, ServerIp, ServerPort, type);
		}
		else
		{
			FormatEx(query, sizeof(query),
					"INSERT INTO %s_comms (authid, name, created, ends, length, reason, aid, adminIp, sid, type) VALUES \
					('%s', '%s', %d, %d, %d, '%s', IFNULL((SELECT aid FROM %s_admins WHERE authid = '%s' OR authid REGEXP '^STEAM_[0-9]:%s$'), '0'), '%s', \
					%d, %d)",
					DatabasePrefix, auth, banName, startTime, (startTime + (time*60)), (time*60), banReason, DatabasePrefix, adminAuth, adminAuth[8], adminIp, serverID, type);
		}
		#if defined LOG_QUERIES
			LogToFile(logQuery, "in ProcessQueueCallbackB: Insert to db. QUERY: %s", query);
		#endif
		new Handle:authPack = CreateDataPack();
		WritePackString(authPack, auth);
		WritePackCell(authPack, type);
		ResetPack(authPack);
		SQL_TQuery(Database, AddedFromSQLiteCallbackB, query, authPack);
	}
	// We have finished processing the queue but should process again in ProcessQueueTime minutes
	CreateTimer(float(ProcessQueueTime * 60), ProcessQueue);
}

public AddedFromSQLiteCallbackB(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	decl String:buffer[512];
	decl String:auth[40];
	ReadPackString(data, auth, sizeof(auth));
	new type = ReadPackCell(data);
	if (error[0] == '\0')
	{
		// The insert was successful so delete the record from the queue
		FormatEx(buffer, sizeof(buffer), "DELETE FROM queue WHERE steam_id = '%s' AND type = %d", auth, type);
		#if defined LOG_QUERIES
			LogToFile(logQuery, "in AddedFromSQLiteCallbackB: DELETE FROM QUEUE. QUERY: %s", buffer);
		#endif
		SQL_TQuery(SQLiteDB, ErrorCheckCallback, buffer);
	}
	CloseHandle(data);
}

public ErrorCheckCallback(Handle:owner, Handle:hndle, const String:error[], any:data)
{
	if (error[0])
	{
		LogToFile(logFile, "Query Failed: %s", error);
	}
}

public VerifyBlocks(Handle:owner, Handle:hndl, const String:error[], any:userid)
{
	decl String:clientAuth[64];
	new client = GetClientOfUserId(userid);

	if (!client)
		return;

	/* Failure happen. Do retry with delay */
	if (hndl == INVALID_HANDLE)
	{
		LogToFile(logFile, "Verify Blocks Query Failed: %s", error);
		g_hPlayerRecheck[client] = CreateTimer(RetryTime, ClientRecheck, userid);
		return;
	}
	GetClientAuthString(client, clientAuth, sizeof(clientAuth));

	//SELECT (c.ends - UNIX_TIMESTAMP()) as remaining, c.length, c.type, c.created, c.reason, a.user,
	//IF (a.immunity>=g.immunity, a.immunity, IFNULL(g.immunity,0)) as immunity, c.aid FROM %s_comms c LEFT JOIN %s_admins a ON a.aid=c.aid LEFT JOIN %s_srvgroups g ON g.name = a.srv_group
	//WHERE c.authid REGEXP '^STEAM_[0-9]:%s$' AND (length = '0' OR ends > UNIX_TIMESTAMP()) AND RemoveType IS NULL",
	if (SQL_GetRowCount(hndl) > 0)
	{
		while(SQL_FetchRow(hndl))
		{
			new remaining_time = SQL_FetchInt(hndl, 0);
			new length = SQL_FetchInt(hndl, 1);
			new type = SQL_FetchInt(hndl, 2);
			new aid = SQL_FetchInt(hndl, 7);
			new immunity = SQL_FetchInt(hndl, 6);

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
					g_iMuteLength[client] = length / 60;
					g_iMuteTime[client] = SQL_FetchInt(hndl, 3);
					SQL_FetchString(hndl, 4, g_sMuteReason[client], sizeof(g_sMuteReason[]));
					SQL_FetchString(hndl, 5, g_sMuteAdmin[client], sizeof(g_sMuteAdmin[]));
					g_iMuteLevel[client] = immunity;

					#if defined DEBUG
						LogToFile(logFile, "%s is muted on connect", clientAuth);
					#endif

					PrintToChat(client, "%s%t", PREFIX, "Muted on connect");

					if (length > 0)
					{
						g_MuteType[client] = bTime;
						#if defined DEBUG
							LogToFile(logFile, "Creating MuteExpire timer");
						#endif
						g_hMuteExpireTimer[client] = CreateTimer(float(remaining_time), Timer_MuteExpire, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
					}
					else
						g_MuteType[client] = bPerm;

					BaseComm_SetClientMute(client, true);
				}
				case TYPE_GAG:
				{
					g_iGagLength[client] = length / 60;
					g_iGagTime[client] = SQL_FetchInt(hndl, 3);
					SQL_FetchString(hndl, 4, g_sGagReason[client], sizeof(g_sGagReason[]));
					SQL_FetchString(hndl, 5, g_sGagAdmin[client], sizeof(g_sGagAdmin[]));
					g_iGagLevel[client] = immunity;

					#if defined DEBUG
						LogToFile(logFile, "%s is gagged on connect", clientAuth);
					#endif
					PrintToChat(client, "%s%t", PREFIX, "Gagged on connect");

					if (length > 0)
					{
						g_GagType[client] = bTime;
						#if defined DEBUG
							LogToFile(logFile, "Creating GagExpire timer");
						#endif
						g_hGagExpireTimer[client] = CreateTimer(float(remaining_time), Timer_GagExpire, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
					}
					else
						g_GagType[client] = bPerm;

					BaseComm_SetClientGag(client, true);
				}
			}
		}
	}
	else
	{
		#if defined DEBUG
			LogToFile(logFile, "%s is NOT blocked.", clientAuth);
		#endif
	}

	g_bPlayerStatus[client] = true;
}


// TIMER CALL BACKS //

public Action:ClientRecheck(Handle:timer, any:userid)
{
	#if defined DEBUG
		LogToFile(logFile, "ClientRecheck()");
	#endif

	new client = GetClientOfUserId(userid);
	if (!client)
		return;

	if (!g_bPlayerStatus[client] && IsClientConnected(client))
		OnClientPostAdminCheck(client);

	g_hPlayerRecheck[client] =  INVALID_HANDLE;
}

public Action:Timer_MuteExpire(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if (!client)
		return;

	decl String:clientAuth[64];
	GetClientAuthString(client, clientAuth,sizeof(clientAuth));
	#if defined DEBUG
		LogToFile(logFile, "Mute expired for %s", clientAuth);
	#endif
	PrintToChat(client, "%s%t", PREFIX, "Mute expired");

	g_hMuteExpireTimer[client] = INVALID_HANDLE;
	g_MuteType[client] = bNot;
	g_iMuteTime[client] = 0;
	g_iMuteLength[client] = 0;
	g_iMuteLevel[client] = -1;
	g_sMuteAdmin[client][0] = '\0';
	g_sMuteReason[client][0] = '\0';

	if (IsClientInGame(client))
		BaseComm_SetClientMute(client, false);
}

public Action:Timer_GagExpire(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if (!client)
		return;

	decl String:clientAuth[64];
	GetClientAuthString(client, clientAuth,sizeof(clientAuth));
	#if defined DEBUG
		LogToFile(logFile, "Gag expired for %s", clientAuth);
	#endif
	PrintToChat(client, "%s%t", PREFIX, "Gag expired");

	g_hGagExpireTimer[client] = INVALID_HANDLE;
	g_GagType[client] = bNot;
	g_iGagTime[client] = 0;
	g_iGagLength[client] = 0;
	g_iGagLevel[client] = -1;
	g_sGagAdmin[client][0] = '\0';
	g_sGagReason[client][0] = '\0';

	if (IsClientInGame(client))
		BaseComm_SetClientGag(client, false);
}

public Action:ProcessQueue(Handle:timer, any:data)
{
	decl String:buffer[512];
	Format(buffer, sizeof(buffer), "SELECT steam_id, time, start_time, reason, name, admin_id, admin_ip, type FROM queue");
	SQL_TQuery(SQLiteDB, ProcessQueueCallbackB, buffer);
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
			else if (strcmp("ProcessQueueTime", key, false) == 0)
			{
				ProcessQueueTime = StringToInt(value);
			}
			else if (strcmp("ServerID", key, false) == 0)
			{
				serverID = StringToInt(value);
				if (serverID == 0)
					serverID = -1;
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
	}
	return SMCParse_Continue;
}

public SMCResult:ReadConfig_EndSection(Handle:smc)
{
	return SMCParse_Continue;
}

// STOCK FUNCTIONS //

public InitializeBackupDB()
{
	decl String:error[255];
	SQLiteDB = SQLite_UseDatabase("sourcecomms-queue", error, sizeof(error));
	if (SQLiteDB == INVALID_HANDLE)
		SetFailState(error);

	SQL_LockDatabase(SQLiteDB);
	SQL_FastQuery(SQLiteDB, "CREATE TABLE IF NOT EXISTS queue (steam_id TEXT PRIMARY KEY ON CONFLICT REPLACE, time INTEGER, start_time INTEGER, reason TEXT, name TEXT, admin_id TEXT, admin_ip TEXT, type INTEGER);");
	SQL_UnlockDatabase(SQLiteDB);
}

public bool:CreateBlock(client, target, time, type, String:reason[])
{
	#if defined DEBUG
		LogToFile(logFile, "CreateBlock(%d, %d, %d, %d, %s)", client, target, time, type, reason);
		if (type > 3 || type < 1)
			LogToFile(logFile, "WOW! How do you do that?!");
	#endif

	if (!g_bPlayerStatus[target])
	{
		// The target has not been blocks verify. It must be completed before you can block anyone.
		ReplyToCommand(client, "%s%t", PREFIX, "Player Comms Not Verified");
		return false;
	}

	decl String:adminIp[24];
	decl String:adminAuth[64];
	new String:AdmName[MAX_NAME_LENGTH];
	//	!!	client - is Admin  !! 	//
	new AdmImmunity;

	// The server is the one calling the block
	if (!client)
	{
		// setup dummy adminAuth and adminIp for server
		strcopy(adminAuth, sizeof(adminAuth), "STEAM_ID_SERVER");
		strcopy(adminIp, sizeof(adminIp), ServerIp);
		AdmImmunity = ConsoleImmunity;
		AdmName = "CONSOLE";
	} else {
		GetClientIP(client, adminIp, sizeof(adminIp));
		GetClientAuthString(client, adminAuth, sizeof(adminAuth));
		AdmImmunity = GetAdminImmunityLevel(GetUserAdmin(client));
		AdmName = g_sName[client];
	}

	// target information
	decl String:auth[64];

	GetClientAuthString(target, auth, sizeof(auth));
	#if defined DEBUG
		LogToFile(logFile, "Processing block for %s", auth);
	#endif

	// Pack everything into a data pack so we can retain it trough sql-callback
	new Handle:dataPack = CreateDataPack();
	new Handle:reasonPack = CreateDataPack();
	WritePackString(reasonPack, reason);
	WritePackCell(dataPack, time);
	WritePackCell(dataPack, type);
	WritePackCell(dataPack, _:reasonPack);
	WritePackString(dataPack, g_sName[target]);
	WritePackString(dataPack, auth);
	WritePackString(dataPack, adminAuth);
	WritePackString(dataPack, adminIp);

	ResetPack(dataPack);
	ResetPack(reasonPack);

	switch(type)
	{
		case TYPE_MUTE:
		{
			#if defined DEBUG
				LogToFile(logFile, "TYPE_MUTE. Now check player.");
			#endif

			if (!BaseComm_IsClientMuted(target))
			{
				#if defined DEBUG
					LogToFile(logFile, "%s not muted. Mute him, creating unmute timer and add record to DB", auth);
				#endif

				g_iMuteTime[target] = GetTime();
				g_iMuteLength[target] = time;
				g_iMuteLevel[target] = AdmImmunity;
				g_sMuteAdmin[target] = AdmName;
				Format(g_sMuteReason[target], sizeof(g_sMuteReason[]), "%s", reason);

				if (time > 0)
				{
					g_MuteType[target] = bTime;
					#if defined DEBUG
						LogToFile(logFile, "Creating MuteExpire timer");
					#endif
					g_hMuteExpireTimer[target] = CreateTimer(float(time*60), Timer_MuteExpire, GetClientUserId(target), TIMER_FLAG_NO_MAPCHANGE);
					if (reason[0] == '\0')
						ShowActivity2(client, PREFIX, "%t", "Muted player", g_sName[target], time);
					else
						ShowActivity2(client, PREFIX, "%t", "Muted player reason", g_sName[target], time, reason);
				}
				else if (time == 0)
				{
					g_MuteType[target] = bPerm;
					if (reason[0] == '\0')
						ShowActivity2(client, PREFIX, "%t", "Permamuted player", g_sName[target]);
					else
						ShowActivity2(client, PREFIX, "%t", "Permamuted player reason", g_sName[target], reason);
				}
				else	// temp block
				{
					g_MuteType[target] = bSess;
					if (reason[0] == '\0')
						ShowActivity2(client, PREFIX, "%t", "Temp muted player", g_sName[target]);
					else
						ShowActivity2(client, PREFIX, "%t", "Temp muted player reason", g_sName[target], reason);
				}
				BaseComm_SetClientMute(target, true);
				LogAction(client, target, "\"%L\" muted \"%L\" (minutes \"%d\") (reason \"%s\")", client, target, time, reason);

				// pass move forward with the block
				if (Database != INVALID_HANDLE)
				{
					UTIL_InsertBlock(time, TYPE_MUTE, g_sName[target], auth, reason, adminAuth, adminIp, dataPack); // длина блокировки, тип, имя игрока, стим игрока, причина, стим админа, ип админа
				} else {
					UTIL_InsertTempBlock(time, TYPE_MUTE, g_sName[target], auth, reason, adminAuth, adminIp);
					LogToFile(logFile, "We need insert to queue (calling UTIL_InsertTempBlock)");
				}
			}
			else
			{
				#if defined DEBUG
					LogToFile(logFile, "%s already muted", auth);
				#endif
				ReplyToCommand(client, "%s%t", PREFIX, "Player already muted", g_sName[target]);
				return false;
			}
		}
		//-------------------------------------------------------------------------------------------------
		case TYPE_GAG:
		{
			#if defined DEBUG
				LogToFile(logFile, "TYPE_GAG. Now check player.");
			#endif

			if (!BaseComm_IsClientGagged(target))
			{
				#if defined DEBUG
					LogToFile(logFile, "%s not gagged. Gag him, creating ungag timer and add record to DB", auth);
				#endif

				g_iGagTime[target] = GetTime();
				g_iGagLength[target] = time;
				g_iGagLevel[target] = AdmImmunity;
				g_sGagAdmin[target] = AdmName;
				Format(g_sGagReason[target], sizeof(g_sGagReason[]), "%s", reason);

				if (time > 0)
				{
					g_GagType[target] = bTime;
					#if defined DEBUG
						LogToFile(logFile, "Creating GagExpire timer");
					#endif
					g_hGagExpireTimer[target] = CreateTimer(float(time*60), Timer_GagExpire, GetClientUserId(target), TIMER_FLAG_NO_MAPCHANGE);
					if (reason[0] == '\0')
						ShowActivity2(client, PREFIX, "%t", "Gagged player", g_sName[target], time);
					else
						ShowActivity2(client, PREFIX, "%t", "Gagged player reason", g_sName[target], time, reason);
				}
				else if (time == 0)
				{
					g_GagType[target] = bPerm;
					if (reason[0] == '\0')
						ShowActivity2(client, PREFIX, "%t", "Permagagged player", g_sName[target]);
					else
						ShowActivity2(client, PREFIX, "%t", "Permagagged player reason", g_sName[target], reason);
				}
				else	//temp block
				{
					g_GagType[target] = bSess;
					if (reason[0] == '\0')
						ShowActivity2(client, PREFIX, "%t", "Temp gagged player", g_sName[target]);
					else
						ShowActivity2(client, PREFIX, "%t", "Temp gagged player reason", g_sName[target], reason);
				}
				BaseComm_SetClientGag(target, true);
				LogAction(client, target, "\"%L\" gagged \"%L\" (minutes \"%d\") (reason \"%s\")", client, target, time, reason);

				// pass move forward with the block
				if (Database != INVALID_HANDLE)
				{
					UTIL_InsertBlock(time, TYPE_GAG, g_sName[target], auth, reason, adminAuth, adminIp, dataPack);
				} else {
					UTIL_InsertTempBlock(time, TYPE_GAG, g_sName[target], auth, reason, adminAuth, adminIp);
					LogToFile(logFile, "We need insert to queue (calling UTIL_InsertTempBlock)");
				}
			}
			else
			{
				#if defined DEBUG
					LogToFile(logFile, "%s already gagged", auth);
				#endif
				ReplyToCommand(client, "%s%t", PREFIX, "Player already gagged", g_sName[target]);
				return false;
			}
		}
		//-------------------------------------------------------------------------------------------------
		case TYPE_SILENCE:
		{
			#if defined DEBUG
				LogToFile(logFile, "TYPE_SILENCE. Now check player.");
			#endif

			if (!BaseComm_IsClientGagged(target) && !BaseComm_IsClientMuted(target))
			{
				#if defined DEBUG
					LogToFile(logFile, "%s not silenced. Silence him, creating ungag & unmute timers and add records to DB", auth);
				#endif

				g_iMuteTime[target] = GetTime();
				g_iMuteLength[target] = time;
				g_iMuteLevel[target] = AdmImmunity;
				g_sMuteAdmin[target] = AdmName;
				Format(g_sMuteReason[target], sizeof(g_sMuteReason[]), "%s", reason);

				g_iGagTime[target] = GetTime();
				g_iGagLength[target] = time;
				g_iGagLevel[target] = AdmImmunity;
				g_sGagAdmin[target] = AdmName;
				Format(g_sGagReason[target], sizeof(g_sGagReason[]), "%s", reason);

				if (time > 0)
				{
					g_MuteType[target] = bTime;
					g_GagType[target] = bTime;
					#if defined DEBUG
						LogToFile(logFile, "Creating GagExpire timer");
					#endif
					g_hGagExpireTimer[target] = CreateTimer(float(time*60), Timer_GagExpire, GetClientUserId(target), TIMER_FLAG_NO_MAPCHANGE);

					#if defined DEBUG
						LogToFile(logFile, "Creating MuteExpire timer");
					#endif
					g_hMuteExpireTimer[target] = CreateTimer(float(time*60), Timer_MuteExpire, GetClientUserId(target), TIMER_FLAG_NO_MAPCHANGE);
					if (reason[0] == '\0')
						ShowActivity2(client, PREFIX, "%t", "Silenced player", g_sName[target], time);
					else
						ShowActivity2(client, PREFIX, "%t", "Silenced player reason", g_sName[target], time, reason);
				}
				else if (time == 0)
				{
					g_MuteType[target] = bPerm;
					g_GagType[target] = bPerm;
					if (reason[0] == '\0')
						ShowActivity2(client, PREFIX, "%t", "Permasilenced player", g_sName[target]);
					else
						ShowActivity2(client, PREFIX, "%t", "Permasilenced player reason", g_sName[target], reason);
				}
				else	//temp block
				{
					g_MuteType[target] = bSess;
					g_GagType[target] = bSess;
					if (reason[0] == '\0')
						ShowActivity2(client, PREFIX, "%t", "Temp silenced player", g_sName[target]);
					else
						ShowActivity2(client, PREFIX, "%t", "Temp silenced player reason", g_sName[target], reason);
				}
				BaseComm_SetClientMute(target, true);
				BaseComm_SetClientGag(target, true);
				LogAction(client, target, "\"%L\" silenced \"%L\" (minutes \"%d\") (reason \"%s\")", client, target, time, reason);

				// pass move forward with the block
				if (Database != INVALID_HANDLE)
				{
					UTIL_InsertBlock(time, TYPE_MUTE, g_sName[target], auth, reason, adminAuth, adminIp, dataPack);
					// Oh no... Looks very bad, but we need to do it again
					// Pack everything into a data pack so we can retain it trough sql-callback
					new Handle:dataPack2 = CreateDataPack();
					new Handle:reasonPack2 = CreateDataPack();
					WritePackString(reasonPack2, reason);
					WritePackCell(dataPack2, time);
					WritePackCell(dataPack2, type);
					WritePackCell(dataPack2, _:reasonPack2);
					WritePackString(dataPack2, g_sName[target]);
					WritePackString(dataPack2, auth);
					WritePackString(dataPack2, adminAuth);
					WritePackString(dataPack2, adminIp);
					ResetPack(dataPack2);
					ResetPack(reasonPack2);

					UTIL_InsertBlock(time, TYPE_GAG, g_sName[target], auth, reason, adminAuth, adminIp, dataPack2);
				} else {
					UTIL_InsertTempBlock(time, TYPE_MUTE, g_sName[target], auth, reason, adminAuth, adminIp);
					UTIL_InsertTempBlock(time, TYPE_GAG, g_sName[target], auth, reason, adminAuth, adminIp);
					LogToFile(logFile, "We need insert to queue (calling UTIL_InsertTempBlock)");
				}
			}
			else
			{
				#if defined DEBUG
					LogToFile(logFile, "%s already gagged or/and muted", auth);
				#endif
				ReplyToCommand(client, "%s%t", PREFIX, "Player already silenced", g_sName[target]);
				return false;
			}
		}
		//-------------------------------------------------------------------------------------------------
	}
	return true;
}

public bool:ProcessUnBlock(client, target, type, String:reason[])
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
	WritePackCell(dataPack, GetClientUserId(client));
	WritePackCell(dataPack, GetClientUserId(target));
	WritePackCell(dataPack, type);
	WritePackString(dataPack, reason);
	WritePackString(dataPack, adminAuth);
	WritePackString(dataPack, targetAuth);
	ResetPack(dataPack);

	decl String:query[1024];
	Format(query, sizeof(query),
		"SELECT c.bid, IFNULL((SELECT aid FROM %s_admins WHERE authid = '%s' OR authid REGEXP '^STEAM_[0-9]:%s$'), '0') as iaid, c.aid, IF (a.immunity>=g.immunity, a.immunity, IFNULL(g.immunity,0)) as immunity, c.type FROM %s_comms c \
		LEFT JOIN %s_admins a ON a.aid=c.aid LEFT JOIN %s_srvgroups g ON g.name = a.srv_group WHERE (length = '0' OR ends > UNIX_TIMESTAMP()) AND RemoveType IS NULL AND (c.authid = '%s' OR c.authid REGEXP '^STEAM_[0-9]:%s$') AND %s",
		DatabasePrefix, adminAuth, adminAuth[8], DatabasePrefix, DatabasePrefix, DatabasePrefix, targetAuth, targetAuth[8], typeWHERE);

	#if defined LOG_QUERIES
		LogToFile(logQuery, "Unblocking select. QUERY: %s", query);
	#endif

	SQL_TQuery(Database, SelectUnBlockCallback, query, dataPack);

	return true;
}

stock UTIL_InsertBlock(time, type, const String:Name[], const String:Authid[], const String:Reason[], const String:AdminAuthid[], const String:AdminIp[], Handle:Pack)
{
	// Принимает время - в минутах, а в базу пишет уже в секундах! Во всех остальных местах время - в минутах.
	new String:banName[MAX_NAME_LENGTH * 2 + 1];
	new String:banReason[512];
	decl String:Query[1024];

	SQL_EscapeString(Database, Name, banName, sizeof(banName));
	SQL_EscapeString(Database, Reason, banReason, sizeof(banReason));

	//bid	authid	name	created ends lenght reason aid adminip	sid	removedBy removedType removedon type ureason
	if ( serverID == -1 )
	{
		FormatEx(Query, sizeof(Query), "INSERT INTO %s_comms (authid, name, created, ends, length, reason, aid, adminIp, sid, type) VALUES \
						('%s', '%s', UNIX_TIMESTAMP(), UNIX_TIMESTAMP() + %d, %d, '%s', IFNULL((SELECT aid FROM %s_admins WHERE authid = '%s' OR authid REGEXP '^STEAM_[0-9]:%s$'),'0'), '%s', \
						(SELECT sid FROM %s_servers WHERE ip = '%s' AND port = '%s' LIMIT 0,1), %d)",
						DatabasePrefix, Authid, banName, (time*60), (time*60), banReason, DatabasePrefix, AdminAuthid, AdminAuthid[8], AdminIp, DatabasePrefix, ServerIp, ServerPort, type);
	}else{
		FormatEx(Query, sizeof(Query), "INSERT INTO %s_comms (authid, name, created, ends, length, reason, aid, adminIp, sid, type) VALUES \
						('%s', '%s', UNIX_TIMESTAMP(), UNIX_TIMESTAMP() + %d, %d, '%s', IFNULL((SELECT aid FROM %s_admins WHERE authid = '%s' OR authid REGEXP '^STEAM_[0-9]:%s$'),'0'), '%s', \
						%d, %d)",
						DatabasePrefix, Authid, banName, (time*60), (time*60), banReason, DatabasePrefix, AdminAuthid, AdminAuthid[8], AdminIp, serverID, type);
	}

	#if defined LOG_QUERIES
		LogToFile(logQuery, "UTIL_InsertBlock. QUERY: %s", Query);
	#endif

	SQL_TQuery(Database, VerifyInsertB, Query, Pack, DBPrio_High);
}

stock UTIL_InsertTempBlock(time, type, const String:name[], const String:auth[], const String:reason[], const String:adminAuth[], const String:adminIp[])
{
	new String:banName[MAX_NAME_LENGTH * 2 + 1];
	new String:banReason[512];
	decl String:query[512];
	SQL_EscapeString(SQLiteDB, name, banName, sizeof(banName));
	SQL_EscapeString(SQLiteDB, reason, banReason, sizeof(banReason));
	FormatEx(	query, sizeof(query), "INSERT INTO queue VALUES ('%s', %i, %i, '%s', '%s', '%s', '%s', %i)",
				auth, time, GetTime(), banReason, banName, adminAuth, adminIp, type);
	#if defined LOG_QUERIES
		LogToFile(logQuery, "Insert into queue. QUERY: %s", query);
	#endif
	//steam_id TEXT, time INTEGER, start_time INTEGER, reason TEXT, name TEXT, admin_id TEXT, admin_ip TEXT, type INTEGER
	SQL_TQuery(SQLiteDB, ErrorCheckCallback, query);
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
		InternalReadConfig(ConfigFile1);
		PrintToServer("%sLoading configs/sourcebans/sourcebans.cfg config file", PREFIX);
	} else {
		decl String:Error[PLATFORM_MAX_PATH + 64];
		FormatEx(Error, sizeof(Error), "%sFATAL *** ERROR *** can not find %s", PREFIX, ConfigFile1);
		LogToFile(logFile, "FATAL *** ERROR *** can not find %s", ConfigFile1);
		SetFailState(Error);
	}
	if (FileExists(ConfigFile2))
	{
		iNumReasons = 0;
		iNumTimes = 0;
		InternalReadConfig(ConfigFile2);
		if (iNumReasons)
			iNumReasons--;
		if (iNumTimes)
			iNumTimes--;
		PrintToServer("%sLoading configs/sourcebans/sourcecomms.cfg config file", PREFIX);
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

Bool_ValidMenuTarget(client, target)
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

//Yarr!