#pragma semicolon 1

#include <sourcemod>
#include <basecomm>
#include <sourcebans>
#include <sb_admins>
#include "include/sourcecomms.inc"

#undef REQUIRE_PLUGIN
#include <adminmenu>
#include <updater>

#define UNBLOCK_FLAG ADMFLAG_CUSTOM2

#define DEBUG
#define LOG_QUERIES

// Do not edit below this line //
//-----------------------------//

#define PLUGIN_VERSION "1.0.186"
#define PREFIX "\x04[SourceComms]\x01 "

#define UPDATE_URL "http://z.tf2news.ru/repo/sc-updatefile.txt"

#define MAX_REASONS 32
#define DISPLAY_SIZE 64
#define REASON_SIZE 192

new iNumReasons;
new String:g_sReasonDisplays[MAX_REASONS][DISPLAY_SIZE], String:g_sReasonKey[MAX_REASONS][REASON_SIZE];

#define MAX_TIMES 32
new iNumTimes, g_iTimeMinutes[MAX_TIMES];
new String:g_sTimeDisplays[MAX_TIMES][DISPLAY_SIZE];

new Handle:hTopMenu = INVALID_HANDLE;

/* Database handle */
new Handle:SQLiteDB;

/* Timer handles */
new Handle:g_hPlayerRecheck[MAXPLAYERS + 1] = {INVALID_HANDLE, ...};

/* Log Stuff */
#if defined LOG_QUERIES
    new String:logQuery[256];
#endif

new Float:RetryTime     = 15.0;
new DefaultTime         = 30;
new DisUBImCheck        = 0;
new ConsoleImmunity     = 0;    //todo - rename to g_iConsoleImmunity
new ConfigMaxLength     = 0;
new ConfigWhiteListOnly = 0;

new g_iServerID;
new String:g_sServerIP[16];
new String:g_sServerID[5];


new Handle:g_hServersWhiteList = INVALID_HANDLE;

#include "sourcecomms/core.sp"              // Core plugin code
#include "sourcecomms/menu.sp"              // Menu code
#include "sourcecomms/config-parser.sp"     // Config parser code
#include "sourcecomms/natives.sp"           // plugin natives

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
    CreateNative("SourceComms_SetClientMute",     Native_SetClientMute);
    CreateNative("SourceComms_SetClientGag",      Native_SetClientGag);
    CreateNative("SourceComms_GetClientMuteType", Native_GetClientMuteType);
    CreateNative("SourceComms_GetClientGagType",  Native_GetClientGagType);
    MarkNativeAsOptional("SQL_SetCharset");
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

    g_hServersWhiteList = CreateArray();

    CreateConVar("sourcecomms_version", PLUGIN_VERSION, _, FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
    AddCommandListener(CommandCallback,       "sm_gag");
    AddCommandListener(CommandCallback,       "sm_mute");
    AddCommandListener(CommandCallback,       "sm_silence");
    AddCommandListener(CommandCallback,       "sm_ungag");
    AddCommandListener(CommandCallback,       "sm_unmute");
    AddCommandListener(CommandCallback,       "sm_unsilence");
    RegServerCmd("sc_fw_block", FWBlock,      "Blocking player comms by command from sourceban web site", FCVAR_PLUGIN);
    RegServerCmd("sc_fw_ungag", FWUngag,      "Ungagging player by command from sourceban web site", FCVAR_PLUGIN);
    RegServerCmd("sc_fw_unmute",FWUnmute,     "Unmuting player by command from sourceban web site", FCVAR_PLUGIN);
    RegConsoleCmd("sm_comms",   CommandComms, "Shows current player communications status", FCVAR_PLUGIN);

    HookEvent("player_changename", Event_OnPlayerName, EventHookMode_Post);

    #if defined LOG_QUERIES
        BuildPath(Path_SM, logQuery, sizeof(logQuery), "logs/sourcecomms-q.log");
    #endif

    #if defined DEBUG
        PrintToServer("Sourcecomms plugin loading. Version %s", PLUGIN_VERSION);
    #endif

    SB_Connect();
    InitializeBackupDB();

    // for late loading
    if (LibraryExists("updater"))
        Updater_AddPlugin(UPDATE_URL);

    // Account for late loading
    if(LibraryExists("sourcebans"))
        SB_Init();
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
    LogMessage("Plugin updated. Old version was %s. Now reloading.", PLUGIN_VERSION);

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
    decl String:sClientAuth[64];
    GetClientAuthString(client, sClientAuth, sizeof(sClientAuth));
    GetClientName(client, g_sName[client], sizeof(g_sName[]));

    /* Do not check bots or check player with lan steamid. */
    if (!SB_Connect() || StrContains("BOT STEAM_ID_LAN", sClientAuth) != -1)
    {
        g_bPlayerStatus[client] = true;
        return;
    }

    if (client > 0 && IsClientInGame(client) && !IsFakeClient(client))
    {
        // if plugin was late loaded
        if (BaseComm_IsClientMuted(client))
        {
            MarkClientAsMuted(client);
        }
        if (BaseComm_IsClientGagged(client))
        {
            MarkClientAsGagged(client);
        }

        new iClientAccountID = GetSteamAccountID(client);
        if (iClientAccountID)
        {
            decl String:sQuery[4096];
            FormatEx(sQuery, sizeof(sQuery),
               "SELECT IF(c.length, c.create_time + c.length * 60 - UNIX_TIMESTAMP(), 0) as remaining \
                     , c.length, c.create_time, c.type, c.reason, IFNULL(c.server_id,0) \
                     , IFNULL(a.id, 0), IFNULL(a.name, 'CONSOLE'), MAX(IFNULL(IF(c.server_id, sgs.immunity, sgw.immunity), 0)) AS immunity \
                  FROM {{comms}} AS c \
                       LEFT JOIN {{admins}} AS a ON a.id = c.admin_id \
                       LEFT JOIN {{admins_server_groups}} AS asg ON asg.admin_id = c.admin_id \
                       LEFT JOIN {{server_groups}} AS sgw ON sgw.id = asg.group_id \
                       LEFT JOIN {{servers_server_groups}} AS ssg ON ssg.server_id = c.server_id \
                       LEFT JOIN {{server_groups}} AS sgs ON sgs.id = asg.group_id AND sgs.id = ssg.group_id \
                 WHERE c.steam_account_id = %d \
                       AND c.unban_time IS NULL \
                       AND (c.length = '0' OR c.create_time + c.length * 60 > UNIX_TIMESTAMP()) \
              GROUP BY c.id",
                iClientAccountID);
            #if defined LOG_QUERIES
                LogToFile(logQuery, "OnClientPostAdminCheck for: %s. QUERY: %s", sClientAuth, sQuery);
            #endif
            SB_Query(Query_VerifyBlock, sQuery, GetClientUserId(client), DBPrio_High);
        }
        else
        {
            LogError("Can't determine Steam Account ID for player %s. Skip checking", sClientAuth);
            return;
        }
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
                MarkClientAsMuted(client, _, _, _, _, _, "Muted through BaseComm natives");
                SavePunishment(_, client, TYPE_MUTE,  _, "Muted through BaseComm natives");
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
                MarkClientAsGagged(client, _, _, _, _, _, "Gagged through BaseComm natives");
                SavePunishment(_,  client, TYPE_GAG,   _, "Gagged through BaseComm natives");
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
        LogError("Wrong usage of sc_fw_block");
        return Plugin_Stop;
    }

    LogMessage("Received block command from web: steam %s, type %d, length %d", sArg[2], type, length);

    for (new i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsClientAuthorized(i) && !IsFakeClient(i))
        {
            decl String:clientAuth[64];
            GetClientAuthString(i, clientAuth, sizeof(clientAuth));
            if (strcmp(clientAuth, sArg[2], false) == 0)
            {
                #if defined DEBUG
                    PrintToServer("Catched %s for blocking from web", clientAuth);
                #endif

                if (g_MuteType[i] == bNot && (type == 1 || type == 3))
                {
                    PerformMute(i, _, length / 60, _, _, _, _);
                    PrintToChat(i, "%s%t", PREFIX, "Muted on connect");
                    LogMessage("%s is muted from web", clientAuth);
                }
                if (g_GagType[i] == bNot && (type == 2 || type == 3))
                {
                    PerformGag(i, _, length / 60, _, _, _, _);
                    PrintToChat(i, "%s%t", PREFIX, "Gagged on connect");
                    LogMessage("%s is gagged from web", clientAuth);
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
        LogError("Wrong usage of sc_fw_ungag");
        return Plugin_Stop;
    }

    LogMessage("Received ungag command from web: steam %s", sArg[0]);

    for (new i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsClientAuthorized(i) && !IsFakeClient(i))
        {
            decl String:clientAuth[64];
            GetClientAuthString(i, clientAuth, sizeof(clientAuth));
            if (strcmp(clientAuth, sArg[0], false) == 0)
            {
                #if defined DEBUG
                    PrintToServer("Catched %s for ungagging from web", clientAuth);
                #endif

                if (g_GagType[i] > bNot)
                {
                    PerformUnGag(i);
                    PrintToChat(i, "%s%t", PREFIX, "FWUngag");
                    LogMessage("%s is ungagged from web", clientAuth);
                }
                else
                    LogError("Can't ungag %s from web, it isn't gagged", clientAuth);
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
        LogError("Wrong usage of sc_fw_ungag");
        return Plugin_Stop;
    }

    LogMessage("Received unmute command from web: steam %s", sArg[0]);

    for (new i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsClientAuthorized(i) && !IsFakeClient(i))
        {
            decl String:clientAuth[64];
            GetClientAuthString(i, clientAuth, sizeof(clientAuth));
            if (strcmp(clientAuth, sArg[0], false) == 0)
            {
                #if defined DEBUG
                    PrintToServer("Catched %s for unmuting from web", clientAuth);
                #endif

                if (g_MuteType[i] > bNot)
                {
                    PerformUnMute(i);
                    PrintToChat(i, "%s%t", PREFIX, "FWUnmute");
                    LogMessage("%s is unmuted from web", clientAuth);
                }
                else
                    LogError("Can't unmute %s from web, it isn't muted", clientAuth);
                break;
            }
        }
    }
    return Plugin_Handled;
}


public Action:CommandCallback(client, const String:command[], args)
{
    if (client && !CheckCommandAccess(client, command, ADMFLAG_CHAT))
        return Plugin_Continue;

    new type;
    if (StrEqual(command, "sm_gag", false))
        type = TYPE_GAG;
    else if (StrEqual(command, "sm_mute", false))
        type = TYPE_MUTE;
    else if (StrEqual(command, "sm_ungag", false))
        type = TYPE_UNGAG;
    else if (StrEqual(command, "sm_unmute", false))
        type = TYPE_UNMUTE;
    else if (StrEqual(command, "sm_silence", false))
        type = TYPE_SILENCE;
    else if (StrEqual(command, "sm_unsilence", false))
        type = TYPE_UNSILENCE;
    else
        return Plugin_Stop;

    if (args < 1)
    {
        ReplyToCommand(client, "%sUsage: %s <#userid|name> %s", PREFIX, command, type <= TYPE_SILENCE ? "[time|0] [reason]" : "[reason]");
        if (type <= TYPE_SILENCE)
            ReplyToCommand(client, "%sUsage: %s <#userid|name> [reason]", PREFIX, command);
        return Plugin_Stop;
    }

    new String:sBuffer[256];
    GetCmdArgString(sBuffer, sizeof(sBuffer));

    if (type <= TYPE_SILENCE)
        CreateBlock(client, _, _, type, _, sBuffer);
    else
        ProcessUnBlock(client, _, type, _, sBuffer);

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

    AddToTopMenu(hTopMenu, "sourcecomm_gag",       TopMenuObject_Item, Handle_MenuGag,       MenuObject, "sm_gag",       ADMFLAG_CHAT);
    AddToTopMenu(hTopMenu, "sourcecomm_ungag",     TopMenuObject_Item, Handle_MenuUnGag,     MenuObject, "sm_ungag",     ADMFLAG_CHAT);
    AddToTopMenu(hTopMenu, "sourcecomm_mute",      TopMenuObject_Item, Handle_MenuMute,      MenuObject, "sm_mute",      ADMFLAG_CHAT);
    AddToTopMenu(hTopMenu, "sourcecomm_unmute",    TopMenuObject_Item, Handle_MenuUnMute,    MenuObject, "sm_unmute",    ADMFLAG_CHAT);
    AddToTopMenu(hTopMenu, "sourcecomm_silence",   TopMenuObject_Item, Handle_MenuSilence,   MenuObject, "sm_silence",   ADMFLAG_CHAT);
    AddToTopMenu(hTopMenu, "sourcecomm_unsilence", TopMenuObject_Item, Handle_MenuUnSilence, MenuObject, "sm_unsilence", ADMFLAG_CHAT);
    AddToTopMenu(hTopMenu, "sourcecomm_list",      TopMenuObject_Item, Handle_MenuList,      MenuObject, "sm_commlist",  ADMFLAG_CHAT);
}


// Sourcebans callbacks //

public SB_OnConnect(Handle:database)
{
    g_iServerID = SB_GetConfigValue("ServerID");

    if (g_iServerID)
        IntToString(g_iServerID, g_sServerID, sizeof(g_sServerID));
    else
        strcopy(g_sServerID, sizeof(g_sServerID), "NULL");

    if (!g_iServerID && ConfigWhiteListOnly)
    {
        LogError("Unknown ServerID! ServersWhiteList feature disabled!");
        ConfigWhiteListOnly = 0;
    }

    ProcessQueue();
    ForcePlayersRecheck();
}

public SB_OnReload()
{
    // Get values from SourceBans config and store them locally
    SB_GetConfigString("ServerIP", g_sServerIP, sizeof(g_sServerIP));
}


// SQL CALLBACKS //




public Query_ErrorCheck(Handle:owner, Handle:hndl, const String:error[], any:data)
{
    if (hndl == INVALID_HANDLE || error[0])
        LogError("%T (%s)", "Failed to query database", LANG_SERVER, error);
}





// TIMER CALL BACKS //
public Action:ClientRecheck(Handle:timer, any:userid)
{
    #if defined DEBUG
        PrintToServer("ClientRecheck(userid: %d)", userid);
    #endif

    new client = GetClientOfUserId(userid);
    if (!client)
        return;

    if (IsClientConnected(client))
        OnClientPostAdminCheck(client);

    g_hPlayerRecheck[client] =  INVALID_HANDLE;
}




// STOCK FUNCTIONS //

stock InitializeBackupDB()
{
    decl String:error[255];
    SQLiteDB = SQLite_UseDatabase("sourcecomms-queue", error, sizeof(error));
    if (SQLiteDB == INVALID_HANDLE)
    {
        SetFailState(error);
    }

    // Prune old tables
    SQL_TQuery(SQLiteDB, Query_ErrorCheck, "DROP TABLE IF EXISTS queue");
    SQL_TQuery(SQLiteDB, Query_ErrorCheck, "DROP TABLE IF EXISTS queue2");

    SQL_TQuery(SQLiteDB, Query_ErrorCheck,
       "CREATE TABLE IF NOT EXISTS queue3 ( \
            id INTEGER PRIMARY KEY, \
            steam_account_id INTEGER, name TEXT, \
            start_time INTEGER, length INTEGER, reason TEXT, \
            admin_id INTEGER, admin_ip TEXT, type INTEGER )"
    );
}










// some more

stock bool:IsAllowedBlockLength(admin, length, target_count = 1)
{
    if (target_count == 1)
    {
        if (!ConfigMaxLength)
            return true;    // Restriction disabled
        if (!admin)
            return true;    // all allowed for console
        if (AdmHasFlag(admin))
            return true;    // all allowed for admins with special flag
        if (!length || length > ConfigMaxLength)
            return false;
        else
            return true;
    }
    else
    {
        if (length < 0)
            return true;    // session punishments allowed for mass-tergeting
        if (!length)
            return false;
        if (length > MAX_TIME_MULTI)
            return false;
        if (length > DefaultTime)
            return false;
        else
            return true;
    }
}

stock bool:AdmHasFlag(admin)
{
    return admin && CheckCommandAccess(admin, "", UNBLOCK_FLAG, true);
}

stock _:GetAdmImmunity(admin, const _:iAdminID)
{
    if (admin && GetUserAdmin(admin) != INVALID_ADMIN_ID)
        return GetAdminImmunityLevel(GetUserAdmin(admin));
    else if (!admin && !iAdminID)
        return ConsoleImmunity;
    else
        return 0;
}

stock _:GetClientUserId2(client)
{
    if (client)
        return GetClientUserId(client);
    else
        return 0;    // for CONSOLE
}

stock bool:ImmunityCheck(admin, target, const _:iAdminID, const _:iType)
{
    if (DisUBImCheck != 0)
        return false;

    if (!target || !IsClientInGame(target))
        return false;

    new iAdmImmunity = GetAdmImmunity(admin, iAdminID);

    decl bool:bResult;
    switch (iType)
    {
        case TYPE_MUTE:
            bResult = iAdmImmunity > g_iMuteLevel[target];
        case TYPE_GAG:
            bResult = iAdmImmunity > g_iGagLevel[target];
        case TYPE_SILENCE:
            bResult = iAdmImmunity > g_iMuteLevel[target] && iAdmImmunity > g_iGagLevel[target];
        default:
            bResult = false;
    }

    return bResult;
}

stock bool:AdminCheck(admin, target, const _:iAdminID, const _:iType)
{
    if (!target || !IsClientInGame(target))
        return false;

    decl bool:bIsIssuerAdmin;
    switch(iType)
    {
        case TYPE_UNMUTE:
            bIsIssuerAdmin = iAdminID == g_iMuteAdminID[target];
        case TYPE_UNGAG:
            bIsIssuerAdmin = iAdminID == g_iGagAdminID[target];
        case TYPE_UNSILENCE:
            bIsIssuerAdmin = iAdminID == g_iMuteAdminID[target] && iAdminID == g_iGagAdminID[target];
        default:
            bIsIssuerAdmin = false;
    }

    new bool:bIsConsole = !admin && !iAdminID;

    #if defined DEBUG
        // WHO WE ARE?
        PrintToServer("WHO WE ARE CHECKING!");
        PrintToServer("We are block author: %b", bIsIssuerAdmin);
        PrintToServer("We are console: %b", bIsConsole);
        PrintToServer("We have special flag: %b", AdmHasFlag(admin));
    #endif

    new bool:bResult = bIsIssuerAdmin || bIsConsole || AdmHasFlag(admin);
    return bResult;
}

stock ForcePlayersRecheck()
{
    for (new i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsClientAuthorized(i) && !IsFakeClient(i) && g_hPlayerRecheck[i] == INVALID_HANDLE)
        {
            #if defined DEBUG
            {
                decl String:clientAuth[64];
                GetClientAuthString(i, clientAuth, sizeof(clientAuth));
                PrintToServer("Creating Recheck timer for %s", clientAuth);
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





stock ShowActivityToServer(admin, type, length = 0, String:reason[] = "", String:targetName[], bool:ml = false)
{
    #if defined DEBUG
        PrintToServer("ShowActivityToServer(admin: %d, type: %d, length: %d, reason: %s, name: %s, ml: %b",
            admin, type, length, reason, targetName, ml);
    #endif

    new String:actionName[32], String:translationName[64];
    switch(type)
    {
        case TYPE_MUTE:
        {
            if (length > 0)
                strcopy(actionName, sizeof(actionName), "Muted");
            else if (length == 0)
                strcopy(actionName, sizeof(actionName), "Permamuted");
            else    // temp block
                strcopy(actionName, sizeof(actionName), "Temp muted");
        }
        //-------------------------------------------------------------------------------------------------
        case TYPE_GAG:
        {
            if (length > 0)
                strcopy(actionName, sizeof(actionName), "Gagged");
            else if (length == 0)
                strcopy(actionName, sizeof(actionName), "Permagagged");
            else    //temp block
                strcopy(actionName, sizeof(actionName), "Temp gagged");
        }
        //-------------------------------------------------------------------------------------------------
        case TYPE_SILENCE:
        {
            if (length > 0)
                strcopy(actionName, sizeof(actionName), "Silenced");
            else if (length == 0)
                strcopy(actionName, sizeof(actionName), "Permasilenced");
            else    //temp block
                strcopy(actionName, sizeof(actionName), "Temp silenced");
        }
        //-------------------------------------------------------------------------------------------------
        case TYPE_UNMUTE:
        {
            strcopy(actionName, sizeof(actionName), "Unmuted");
        }
        //-------------------------------------------------------------------------------------------------
        case TYPE_UNGAG:
        {
            strcopy(actionName, sizeof(actionName), "Ungagged");
        }
        //-------------------------------------------------------------------------------------------------
        case TYPE_TEMP_UNMUTE:
        {
            strcopy(actionName, sizeof(actionName), "Temp unmuted");
        }
        //-------------------------------------------------------------------------------------------------
        case TYPE_TEMP_UNGAG:
        {
            strcopy(actionName, sizeof(actionName), "Temp ungagged");
        }
        //-------------------------------------------------------------------------------------------------
        case TYPE_TEMP_UNSILENCE:
        {
            strcopy(actionName, sizeof(actionName), "Temp unsilenced");
        }
        //-------------------------------------------------------------------------------------------------
        default:
        {
            return;
        }
    }

    Format(translationName, sizeof(translationName), "%s %s", actionName, reason[0] == '\0' ? "player" : "player reason");
    #if defined DEBUG
        PrintToServer("translation name: %s", translationName);
    #endif

    if (length > 0)
    {
        if (ml)
            ShowActivity2(admin, PREFIX, "%t", translationName,       targetName, length, reason);
        else
            ShowActivity2(admin, PREFIX, "%t", translationName, "_s", targetName, length, reason);
    }
    else
    {
        if (ml)
            ShowActivity2(admin, PREFIX, "%t", translationName,       targetName,         reason);
        else
            ShowActivity2(admin, PREFIX, "%t", translationName, "_s", targetName,         reason);
    }
}

//Yarr!
