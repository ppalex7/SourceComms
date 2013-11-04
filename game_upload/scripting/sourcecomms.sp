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

#define PLUGIN_VERSION "1.0.167"
#define PREFIX "\x04[SourceComms]\x01 "

#define UPDATE_URL "http://z.tf2news.ru/repo/sc-updatefile.txt"

#define MAX_TIME_MULTI 30       // maximum mass-target punishment length

#define NOW 0
#define TYPE_TEMP_SHIFT 10

#define TYPE_MUTE 1
#define TYPE_GAG 2
#define TYPE_SILENCE 3
#define TYPE_UNMUTE 4
#define TYPE_UNGAG 5
#define TYPE_UNSILENCE 6
#define TYPE_TEMP_UNMUTE 14     // TYPE_TEMP_SHIFT + TYPE_UNMUTE
#define TYPE_TEMP_UNGAG 15      // TYPE_TEMP_SHIFT + TYPE_UNGAG
#define TYPE_TEMP_UNSILENCE 16  // TYPE_TEMP_SHIFT + TYPE_UNSILENCE

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
new Handle:g_hGagExpireTimer[MAXPLAYERS + 1] = {INVALID_HANDLE, ...};
new Handle:g_hMuteExpireTimer[MAXPLAYERS + 1] = {INVALID_HANDLE, ...};


/* Log Stuff */
#if defined LOG_QUERIES
    new String:logQuery[256];
#endif

new Float:RetryTime     = 15.0;
new DefaultTime         = 30;
new DisUBImCheck        = 0;
new ConsoleImmunity     = 0;
new ConfigMaxLength     = 0;
new ConfigWhiteListOnly = 0;

new g_iServerID;
new String:g_sServerIP[16];
new String:g_sServerID[5];

new bool:g_bPlayerStatus[MAXPLAYERS + 1];   // Player block check status
new String:g_sName[MAXPLAYERS + 1][MAX_NAME_LENGTH];

new bType:g_MuteType[MAXPLAYERS + 1];
new g_iMuteTime[MAXPLAYERS + 1];
new g_iMuteLength[MAXPLAYERS + 1];  // in sec
new g_iMuteLevel[MAXPLAYERS + 1];   // immunity level of admin
new g_iMuteAdminID[MAXPLAYERS + 1]; // id from sourcebans
new String:g_sMuteAdminName[MAXPLAYERS + 1][MAX_NAME_LENGTH];
new String:g_sMuteReason[MAXPLAYERS + 1][256];

new bType:g_GagType[MAXPLAYERS + 1];
new g_iGagTime[MAXPLAYERS + 1];
new g_iGagLength[MAXPLAYERS + 1];  // in sec
new g_iGagLevel[MAXPLAYERS + 1];   // immunity level of admin
new g_iGagAdminID[MAXPLAYERS + 1]; // id from sourcebans
new String:g_sGagAdminName[MAXPLAYERS + 1][MAX_NAME_LENGTH];
new String:g_sGagReason[MAXPLAYERS + 1][256];

new Handle:g_hServersWhiteList = INVALID_HANDLE;

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

    // Process queue
    SQL_TQuery(SQLiteDB, Query_ProcessQueue,
       "SELECT id, steam_account_id, name, start_time, length, reason, admin_id, admin_ip, type FROM queue3"
    );

    // Force recheck players
    ForcePlayersRecheck();
}

public SB_OnReload()
{
    // Get values from SourceBans config and store them locally
    SB_GetConfigString("ServerIP", g_sServerIP, sizeof(g_sServerIP));
}


// SQL CALLBACKS //

public Query_AddBlockInsert(Handle:owner, Handle:hndl, const String:error[], any:data)
{
    if (hndl == INVALID_HANDLE || error[0])
    {
        LogError("Query_AddBlockInsert failed: %s", error);

        new String:sReason[256];
        new String:sName[MAX_NAME_LENGTH];
        new String:sAdminIP[20];

        ResetPack(data);
        new iTargetAccountID = ReadPackCell(data);
        new iAdminID         = ReadPackCell(data);
        new iLength          = ReadPackCell(data);
        new iType            = ReadPackCell(data);
        ReadPackString(data, sName,    sizeof(sName));
        ReadPackString(data, sReason,  sizeof(sReason));
        ReadPackString(data, sAdminIP, sizeof(sAdminIP));

        InsertTempBlock(iTargetAccountID, sName, iLength, sReason, iAdminID, sAdminIP, iType);
    }
    CloseHandle(data);
}

public Query_UnBlockSelect(Handle:owner, Handle:hndl, const String:error[], any:data)
{
    decl String:sReason[256];
    decl String:sTargetName[MAX_NAME_LENGTH];
    decl String:sTargetAuth[64];

    ResetPack(data);
    new iAdminUserID  = ReadPackCell(data);
    new iAdmID        = ReadPackCell(data);
    new iTargetUserID = ReadPackCell(data);
    new iType         = ReadPackCell(data); // command type
    ReadPackString(data, sReason,     sizeof(sReason));
    ReadPackString(data, sTargetName, sizeof(sTargetName));
    ReadPackString(data, sTargetAuth, sizeof(sTargetAuth));

    new admin  = GetClientOfUserId(iAdminUserID);
    new target = GetClientOfUserId(iTargetUserID);

    #if defined DEBUG
        PrintToServer("Query_UnBlockSelect(adminUID: %d/%d, adminID %d, targetUID: %d/%d, target auth/name %s / %s, type: %d, reason: %s)",
            iAdminUserID, admin, iAdmID, iTargetUserID, target, sTargetAuth, sTargetName, iType, sReason);
    #endif

    new bool:bHasErrors = false;
    // If error is not an empty string the query failed
    if (hndl == INVALID_HANDLE || error[0] != '\0')
    {
        LogError("Query_UnBlockSelect failed: %s", error);
        if (admin && IsClientInGame(admin))
        {
            PrintToChat(admin,    "%s%T", PREFIX, "Unblock Select Failed", admin, sTargetName);
            PrintToConsole(admin, "%s%T", PREFIX, "Unblock Select Failed", admin, sTargetName);
        }
        else
        {
            PrintToServer("%s%T", PREFIX, "Unblock Select Failed", LANG_SERVER, sTargetName);
        }
        bHasErrors = true;
    }

    // If there was no results then a ban does not exist for that id
    if (hndl != INVALID_HANDLE && !SQL_GetRowCount(hndl))
    {
        if (admin && IsClientInGame(admin))
        {
            PrintToChat(admin,    "%s%t", PREFIX, "No blocks found", sTargetName);
            PrintToConsole(admin, "%s%t", PREFIX, "No blocks found", sTargetName);
        }
        else
        {
            PrintToServer("%s%T", PREFIX, "No blocks found", LANG_SERVER, sTargetName);
        }
        bHasErrors = true;
    }

    if (bHasErrors)
    {
        #if defined DEBUG
            PrintToServer("Calling TempUnBlock from Query_UnBlockSelect");
        #endif

        TempUnBlock(data);    // Datapack closed inside.
        return;
    }
    else
    {
        new bool:bSuccess = false;
        // Get the values from the founded blocks.
        while(SQL_MoreRows(hndl))
        {
            // Oh noes! What happened?!
            if (!SQL_FetchRow(hndl))
                continue;

            new iId    = SQL_FetchInt(hndl, 0);
            new iCType = SQL_FetchInt(hndl, 1); // current record type (TYPE_MUTE or TYPE_GAG, NOT TYPE_SILENCE)

            #if defined DEBUG
                PrintToServer("Fetched from DB: id %d, type: %d", iId, iCType);
            #endif

            bSuccess = true;
            // UnMute/UnGag, Show & log activity
            if (target && IsClientInGame(target))
            {
                switch(iCType)
                {
                    case TYPE_MUTE:
                    {
                        PerformUnMute(target);
                        LogAction(admin, target, "\"%L\" unmuted \"%L\" (reason \"%s\")", admin, target, sReason);
                    }
                    //-------------------------------------------------------------------------------------------------
                    case TYPE_GAG:
                    {
                        PerformUnGag(target);
                        LogAction(admin, target, "\"%L\" ungagged \"%L\" (reason \"%s\")", admin, target, sReason);
                    }
                }
            }

            new Handle:hDataPack = CreateDataPack();
            WritePackCell(hDataPack, iAdminUserID);
            WritePackCell(hDataPack, iCType);
            WritePackString(hDataPack, sTargetName);
            WritePackString(hDataPack, sTargetAuth);

            new String:sReasonEscaped[sizeof(sReason) * 2 + 1];
            SB_Escape(sReason, sReasonEscaped, sizeof(sReasonEscaped));

            decl String:sQuery[2048];
            Format(sQuery, sizeof(sQuery),
               "UPDATE {{comms}} \
                   SET unban_admin_id = %d \
                     , unban_time = UNIX_TIMESTAMP() \
                     , unban_reason = '%s' \
                 WHERE id = %d",
                iAdmID, sReasonEscaped, iId
            );
            #if defined LOG_QUERIES
                LogToFile(logQuery, "Query_UnBlockSelect. QUERY: %s", sQuery);
            #endif
            SB_Query(Query_UnBlockUpdate, sQuery, hDataPack);
        }

        if (bSuccess && target && IsClientInGame(target))
        {
            #if defined DEBUG
                PrintToServer("Showing activity to server in Query_UnBlockSelect");
            #endif
            ShowActivityToServer(admin, iType, _, _, g_sName[target], _);

            if (iType == TYPE_UNSILENCE)
            {
                // check result for possible combination with temp and time punishments (temp was skipped in code above)
                SetPackPosition(data, 24);
                if (g_MuteType[target] > bNot)
                {
                    WritePackCell(data, TYPE_UNMUTE);
                    TempUnBlock(data);  // datapack closed inside
                    data = INVALID_HANDLE;
                }
                else if (g_GagType[target] > bNot)
                {
                    WritePackCell(data, TYPE_UNGAG);
                    TempUnBlock(data);  // datapack closed inside
                    data = INVALID_HANDLE;
                }
            }
        }
    }
    if (data != INVALID_HANDLE)
        CloseHandle(data);
}

public Query_UnBlockUpdate(Handle:owner, Handle:hndl, const String:error[], any:data)
{
    decl String:sTargetName[MAX_NAME_LENGTH];
    decl String:sTargetAuth[64];

    ResetPack(data);
    new admin = GetClientOfUserId(ReadPackCell(data));
    new iType =                   ReadPackCell(data);
    ReadPackString(data, sTargetName, sizeof(sTargetName));
    ReadPackString(data, sTargetAuth, sizeof(sTargetAuth));
    CloseHandle(data);

    if (hndl == INVALID_HANDLE || error[0] != '\0')
    {
        LogError("Query_UnBlockUpdate failed: %s", error);
        if (admin && IsClientInGame(admin))
        {
            PrintToChat(admin, "%s%t", PREFIX, "Unblock insert failed");
            PrintToConsole(admin, "%s%t", PREFIX, "Unblock insert failed");
        }
        return;
    }

    switch(iType)
    {
        case TYPE_MUTE:
        {
            LogAction(admin, -1, "\"%L\" removed mute for %s from DB", admin, sTargetAuth);
            if (admin && IsClientInGame(admin))
            {
                PrintToChat(admin, "%s%t", PREFIX, "successfully unmuted", sTargetName);
                PrintToConsole(admin, "%s%t", PREFIX, "successfully unmuted", sTargetName);
            }
            else
            {
                PrintToServer("%s%T", PREFIX, "successfully unmuted", LANG_SERVER, sTargetName);
            }
        }
        //-------------------------------------------------------------------------------------------------
        case TYPE_GAG:
        {
            LogAction(admin, -1, "\"%L\" removed gag for %s from DB", admin, sTargetAuth);
            if (admin && IsClientInGame(admin)){
                PrintToChat(admin, "%s%t", PREFIX, "successfully ungagged", sTargetName);
                PrintToConsole(admin, "%s%t", PREFIX, "successfully ungagged", sTargetName);
            }
            else
            {
                PrintToServer("%s%T", PREFIX, "successfully ungagged", LANG_SERVER, sTargetName);
            }
        }
    }
}

// ProcessQueueCallback is called as the result of selecting all the rows from the queue table
public Query_ProcessQueue(Handle:owner, Handle:hndl, const String:error[], any:data)
{
    if (hndl == INVALID_HANDLE || error[0])
    {
        LogError("Query_ProcessQueue failed: %s", error);
        return;
    }

    while(SQL_MoreRows(hndl))
    {
        // Oh noes! What happened?!
        if (!SQL_FetchRow(hndl))
            continue;

        // if we get to here then there are rows in the queue pending processing
        new String:sName[MAX_NAME_LENGTH];
        new String:sReason[256];
        new String:sAdminIP[20];

        // id   steam_account_id    name    start_time  length  reason  admin_id    admin_ip    type
        new iId              = SQL_FetchInt(hndl, 0);
        new iTargetAccountID = SQL_FetchInt(hndl, 1);
        SQL_FetchString(hndl, 2, sName, sizeof(sName));
        new iStartTime       = SQL_FetchInt(hndl, 3);
        new iLength          = SQL_FetchInt(hndl, 4);
        SQL_FetchString(hndl, 5, sReason, sizeof(sReason));
        new iAdminID         = SQL_FetchInt(hndl, 6);
        SQL_FetchString(hndl, 7, sAdminIP, sizeof(sAdminIP));
        new iType            = SQL_FetchInt(hndl, 8);

        #if defined DEBUG
            PrintToServer(
                "Fetched from queue: AccountID %d, name %d, created %d, length %d, reason: %s, AdminID %d, AdminIP %s, type %d",
                iTargetAccountID, sName, iStartTime, iLength, sReason, iAdminID, sAdminIP, iType
            );
        #endif

        new String:sAdminID[5];
        if (iAdminID)
            IntToString(iAdminID, sAdminID, sizeof(sAdminID));
        else
            strcopy(sAdminID, sizeof(sAdminID), "NULL");

        new String:sNameEscaped[MAX_NAME_LENGTH * 2  + 1];
        new String:sReasonEscaped[sizeof(sReason) * 2 + 1];
        if (SB_Connect())
        {
            SB_Escape(sName,   sNameEscaped,   sizeof(sNameEscaped));
            SB_Escape(sReason, sReasonEscaped, sizeof(sReasonEscaped));
        }
        else
        {
            // all blocks should be entered into db!
            continue;
        }

        decl String:sQuery[4096];
        FormatEx(sQuery, sizeof(sQuery),
           "INSERT INTO {{comms}} (create_time, steam_account_id, name, reason, length, server_id, admin_id, admin_ip, type) \
                 VALUES (%d, %d, '%s', '%s', %d, %s, %s, '%s', %d)",
            iStartTime, iTargetAccountID, sNameEscaped, sReasonEscaped, iLength, g_sServerID, sAdminID, sAdminIP, iType
        );
        #if defined LOG_QUERIES
            LogToFile(logQuery, "Query_ProcessQueue. QUERY: %s", sQuery);
        #endif
        SB_Query(Query_AddBlockFromQueue, sQuery, iId);
    }
}

public Query_AddBlockFromQueue(Handle:owner, Handle:hndl, const String:error[], any:data)
{
    decl String:sQuery[512];
    if (hndl != INVALID_HANDLE && error[0] == '\0')
    {
        // The insert was successful so delete the record from the queue
        FormatEx(sQuery, sizeof(sQuery), "DELETE FROM queue3 WHERE id = %d", data);
        #if defined LOG_QUERIES
            LogToFile(logQuery, "Query_AddBlockFromQueue. QUERY: %s", sQuery);
        #endif
        SQL_TQuery(SQLiteDB, Query_ErrorCheck, sQuery);
    }
    else
    {
        LogError("Query_AddBlockFromQueue failed: %s", error);
    }
}

public Query_ErrorCheck(Handle:owner, Handle:hndl, const String:error[], any:data)
{
    if (hndl == INVALID_HANDLE || error[0])
        LogError("%T (%s)", "Failed to query database", LANG_SERVER, error);
}

public Query_VerifyBlock(Handle:owner, Handle:hndl, const String:error[], any:userid)
{
    decl String:clientAuth[64];
    new client = GetClientOfUserId(userid);

    #if defined DEBUG
        PrintToServer("Query_VerifyBlock(userid: %d, client: %d)", userid, client);
    #endif

    if (!client)
        return;

    /* Failure happen. Do retry with delay */
    if (hndl == INVALID_HANDLE || error[0])
    {
        LogError("Query_VerifyBlock failed: %s", error);
        if (g_hPlayerRecheck[client] == INVALID_HANDLE)
            g_hPlayerRecheck[client] = CreateTimer(RetryTime, ClientRecheck, userid);
        return;
    }

    GetClientAuthString(client, clientAuth, sizeof(clientAuth));

    // remaining, length, create_time, type, reason, server_id, admin_id, admin_name, admin_immunity
    if (SQL_GetRowCount(hndl) > 0)
    {
        while(SQL_FetchRow(hndl))
        {
            new String:sReason[256], String:sAdmName[MAX_NAME_LENGTH];
            new iRemainingTime = SQL_FetchInt(hndl, 0);
            new iLength        = SQL_FetchInt(hndl, 1);
            new iCreateTime    = SQL_FetchInt(hndl, 2);
            new iType          = SQL_FetchInt(hndl, 3);
            SQL_FetchString(hndl, 4, sReason, sizeof(sReason));
            new iServerID      = SQL_FetchInt(hndl, 5);
            new iAdmID         = SQL_FetchInt(hndl, 6);
            SQL_FetchString(hndl, 7, sAdmName, sizeof(sAdmName));
            new iAdmImmunity   = SQL_FetchInt(hndl, 8);

            // Block from CONSOLE (admin_id=0) and we have `console immunity` value in config
            if (!iAdmID && ConsoleImmunity > iAdmImmunity)
                iAdmImmunity = ConsoleImmunity;

            #if defined DEBUG
                PrintToServer("Fetched from DB: remaining %d, length %d, type %d", iRemainingTime, iLength, iType);
            #endif

            // check for server_id
            if (NotApplyToThisServer(iServerID))
            {
                #if defined DEBUG
                    PrintToServer("Skip this punishment due it comes from server's not from white list");
                #endif
                continue;
            }

            switch(iType)
            {
                case TYPE_MUTE:
                {
                    if (g_MuteType[client] < bTime)
                    {
                        PerformMute(client, iCreateTime, iLength, sAdmName, iAdmID, iAdmImmunity, sReason, iRemainingTime);
                        PrintToChat(client, "%s%t", PREFIX, "Muted on connect");
                    }
                }
                case TYPE_GAG:
                {
                    if (g_GagType[client] < bTime)
                    {
                        PerformGag(client, iCreateTime, iLength, sAdmName, iAdmID, iAdmImmunity, sReason, iRemainingTime);
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
        PrintToServer("ClientRecheck(userid: %d)", userid);
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
        PrintToServer("Mute expired for %s", clientAuth);
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
        PrintToServer("Gag expired for %s", clientAuth);
    #endif

    PrintToChat(client, "%s%t", PREFIX, "Gag expired");

    g_hGagExpireTimer[client] = INVALID_HANDLE;
    MarkClientAsUnGagged(client);
    if (IsClientInGame(client))
        BaseComm_SetClientGag(client, false);
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

stock CreateBlock(admin, const targetId = 0, _:iLength = -1, const _:iType, const String:sReasonArg[] = "", const String:sArgs[] = "")
{
    #if defined DEBUG
        PrintToServer("CreateBlock(admin: %d, target: %d, length: %d, type: %d, reason: %s, args: %s)", admin, targetId, iLength, iType, sReasonArg, sArgs);
    #endif

    decl iTargetList[MAXPLAYERS];
    decl iTargetCount;
    decl bool:bTnIsMl;
    decl String:sTargetName[MAX_NAME_LENGTH];
    decl String:sReason[256];
    new bool:bSkipped = false;

    // checking args
    if (targetId)
    {
        iTargetList[0] = targetId;
        iTargetCount= 1;
        bTnIsMl = false;
        strcopy(sTargetName, sizeof(sTargetName), g_sName[targetId]);
        strcopy(sReason,      sizeof(sReason),      sReasonArg);
    }
    else if (strlen(sArgs))
    {
        new String:sArg[3][192];

        if (ExplodeString(sArgs, "\"", sArg, 3, 192, true) == 3 && strlen(sArg[0]) == 0)    // exploding by quotes
        {
            new String:sTempArg[2][192];
            TrimString(sArg[2]);
            sArg[0] = sArg[1];        // target name
            ExplodeString(sArg[2], " ", sTempArg, 2, 192, true); // get length and reason
            sArg[1] = sTempArg[0];    // lenght
            sArg[2] = sTempArg[1];    // reason
        }
        else
        {
            ExplodeString(sArgs, " ", sArg, 3, 192, true);  // exploding by spaces
        }

        // Get the target, find target returns a message on failure so we do not
        if ((iTargetCount = ProcessTargetString(
                sArg[0],
                admin,
                iTargetList,
                MAXPLAYERS,
                COMMAND_FILTER_NO_BOTS,
                sTargetName,
                sizeof(sTargetName),
                bTnIsMl)) <= 0)
        {
            ReplyToTargetError(admin, iTargetCount);
            return;
        }

        // Get the block length
        if (!StringToIntEx(sArg[1], iLength))   // not valid number in second argument
        {
            iLength = DefaultTime;
            Format(sReason, sizeof(sReason), "%s %s", sArg[1], sArg[2]);
        }
        else
        {
            strcopy(sReason, sizeof(sReason), sArg[2]);
        }

        // Strip spaces and quotes from reason
        TrimString(sReason);
        StripQuotes(sReason);

        if (!IsAllowedBlockLength(admin, iLength, iTargetCount))
        {
            ReplyToCommand(admin, "%s%t", PREFIX, "no access");
            return;
        }
    }
    else
    {
        return;
    }

    new iAdmID = admin && IsClientInGame(admin) ? SB_GetAdminId(admin) : 0;
    new iAdmImmunity = GetAdmImmunity(admin, iAdmID);

    for (new i = 0; i < iTargetCount; i++)
    {
        new target = iTargetList[i];

        #if defined DEBUG
            decl String:sAuth[64];
            GetClientAuthString(target, sAuth, sizeof(sAuth));
            PrintToServer("Processing block for %s", sAuth);
        #endif

        if (!g_bPlayerStatus[target])
        {
            // The target has not been blocks verify. It must be completed before you can block anyone.
            ReplyToCommand(admin, "%s%t", PREFIX, "Player Comms Not Verified");
            bSkipped = true;
            continue; // skip
        }

        switch(iType)
        {
            case TYPE_MUTE:
            {
                if (!BaseComm_IsClientMuted(target))
                {
                    #if defined DEBUG
                        PrintToServer("%s not muted. Mute him, creating unmute timer and add record to DB", sAuth);
                    #endif

                    PerformMute(target, _, iLength, g_sName[admin], iAdmID, iAdmImmunity, sReason);

                    LogAction(admin, target, "\"%L\" muted \"%L\" (minutes \"%d\") (reason \"%s\")", admin, target, iLength, sReason);
                }
                else
                {
                    #if defined DEBUG
                        PrintToServer("%s already muted", sAuth);
                    #endif

                    ReplyToCommand(admin, "%s%t", PREFIX, "Player already muted", g_sName[target]);

                    bSkipped = true;
                    continue;
                }
            }
            //-------------------------------------------------------------------------------------------------
            case TYPE_GAG:
            {
                if (!BaseComm_IsClientGagged(target))
                {
                    #if defined DEBUG
                        PrintToServer("%s not gagged. Gag him, creating ungag timer and add record to DB", sAuth);
                    #endif

                    PerformGag(target, _, iLength, g_sName[admin], iAdmID, iAdmImmunity, sReason);

                    LogAction(admin, target, "\"%L\" gagged \"%L\" (minutes \"%d\") (reason \"%s\")", admin, target, iLength, sReason);
                }
                else
                {
                    #if defined DEBUG
                        PrintToServer("%s already gagged", sAuth);
                    #endif

                    ReplyToCommand(admin, "%s%t", PREFIX, "Player already gagged", g_sName[target]);

                    bSkipped = true;
                    continue;
                }
            }
            //-------------------------------------------------------------------------------------------------
            case TYPE_SILENCE:
            {
                if (!BaseComm_IsClientGagged(target) && !BaseComm_IsClientMuted(target))
                {
                    #if defined DEBUG
                        PrintToServer("%s not silenced. Silence him, creating ungag & unmute timers and add records to DB", sAuth);
                    #endif

                    PerformMute(target, _, iLength, g_sName[admin], iAdmID, iAdmImmunity, sReason);
                    PerformGag(target,  _, iLength, g_sName[admin], iAdmID, iAdmImmunity, sReason);

                    LogAction(admin, target, "\"%L\" silenced \"%L\" (minutes \"%d\") (reason \"%s\")", admin, target, iLength, sReason);
                }
                else
                {
                    #if defined DEBUG
                        PrintToServer("%s already gagged or/and muted", sAuth);
                    #endif

                    ReplyToCommand(admin, "%s%t", PREFIX, "Player already silenced", g_sName[target]);

                    bSkipped = true;
                    continue;
                }
            }
        }
    }
    if (iTargetCount == 1 && !bSkipped)
        SavePunishment(admin, iTargetList[0], iType, iLength, sReason);
    if (iTargetCount > 1 || !bSkipped)
        ShowActivityToServer(admin, iType, iLength, sReason, sTargetName, bTnIsMl);

    return;
}

stock ProcessUnBlock(admin, targetId = 0, const _:iType, String:sReasonArg[] = "", const String:sArgs[] = "")
{
    #if defined DEBUG
        PrintToServer("ProcessUnBlock(admin: %d, target: %d, type: %d, reason: %s, args: %s)", admin, targetId, iType, sReasonArg, sArgs);
    #endif

    decl iTargetList[MAXPLAYERS];
    decl iTargetCount;
    decl bool:bTnIsMl;
    decl String:sTargetName[MAX_NAME_LENGTH];
    decl String:sReason[256];

    if(targetId)
    {
        iTargetList[0] = targetId;
        iTargetCount = 1;
        bTnIsMl = false;
        strcopy(sTargetName, sizeof(sTargetName), g_sName[targetId]);
        strcopy(sReason,     sizeof(sReason),     sReasonArg);
    }
    else
    {
        new String:sBuffer[256], String:sArg[3][192];
        GetCmdArgString(sBuffer, sizeof(sBuffer));

        if (ExplodeString(sBuffer, "\"", sArg, 3, 192, true) == 3 && strlen(sArg[0]) == 0)
        {
            TrimString(sArg[2]);
            sArg[0] = sArg[1];  // target name
            sArg[1] = sArg[2];  // reason; sArg[2] - not in use
        }
        else
        {
            ExplodeString(sBuffer, " ", sArg, 2, 192, true);
        }
        strcopy(sReason, sizeof(sReason), sArg[1]);
        // Strip spaces and quotes from reason
        TrimString(sReason);
        StripQuotes(sReason);

        // Get the target, find target returns a message on failure so we do not
        if ((iTargetCount = ProcessTargetString(
                sArg[0],
                admin,
                iTargetList,
                MAXPLAYERS,
                COMMAND_FILTER_NO_BOTS,
                sTargetName,
                sizeof(sTargetName),
                bTnIsMl)) <= 0)
        {
            ReplyToTargetError(admin, iTargetCount);
            return;
        }
    }

    new iAdmID = admin && IsClientInGame(admin) ? SB_GetAdminId(admin) : 0;

    if (iTargetCount > 1)
    {
        #if defined DEBUG
            PrintToServer("ProcessUnBlock: targets_count > 1");
        #endif

        new bool:bSuccess = false;

        for (new i = 0; i < iTargetCount; i++)
        {
            new target = iTargetList[i];
            new iTargetAccountID = 0;

            if (IsClientInGame(target))
                iTargetAccountID = GetSteamAccountID(target);

            // if target left the game or Account ID is not available
            if (!iTargetAccountID)
                continue;

            // check permissions
            new bool:bHasPermission = AdminCheck(admin, target, iAdmID, iType) || ImmunityCheck(admin, target, iAdmID, iType);
            #if defined DEBUG
                PrintToServer("Permissions to temporary unblock: %b", bHasPermission);
            #endif
            if (!bHasPermission)
            {
                if (admin && IsClientInGame(admin))
                {
                    PrintToChat(admin, "%s%t", PREFIX, "No db error unlock perm");
                    PrintToConsole(admin, "%s%t", PREFIX, "No db error unlock perm");
                }
                continue;
            }

            new Handle:hDataPack = CreateDataPack();
            WritePackCell(hDataPack, GetClientUserId2(admin));
            SetPackPosition(hDataPack, 16);
            WritePackCell(hDataPack, GetClientUserId(target));
            WritePackCell(hDataPack, iType);
            WritePackString(hDataPack, sReason);

            TempUnBlock(hDataPack); // dataPack closed inside
            bSuccess = true;
        }

        if (bSuccess)
        {
            #if defined DEBUG
                PrintToServer("Showing activity to server in ProcessUnBlock for targets_count > 1");
            #endif
            ShowActivityToServer(admin, iType + TYPE_TEMP_SHIFT, _, _, sTargetName, bTnIsMl);
        }
    }
    else
    {
        decl String:sTyperWHERE[100];
        new String:sTargetAuth[64];
        new bool:bDontCheckDB = false;
        new target = iTargetList[0];
        new iTargetAccountID = 0;

        if (IsClientInGame(target))
        {
            iTargetAccountID = GetSteamAccountID(target);
            GetClientAuthString(target, sTargetAuth, sizeof(sTargetAuth));
        }

        // if target left the game or Account ID is not available
        if (!iTargetAccountID)
            return;

        // check permissions
        new bool:bHasPermission = AdminCheck(admin, target, iAdmID, iType) || ImmunityCheck(admin, target, iAdmID, iType);
        #if defined DEBUG
            PrintToServer("Permissions to unblock: %b", bHasPermission);
        #endif

        switch(iType)
        {
            case TYPE_UNMUTE:
            {
                if (!BaseComm_IsClientMuted(target))
                {
                    ReplyToCommand(admin, "%s%t", PREFIX, "Player not muted");
                    return;
                }
                else if (bHasPermission)
                {
                    FormatEx(sTyperWHERE, sizeof(sTyperWHERE), "c.type = %d", TYPE_MUTE);
                    if (g_MuteType[target] == bSess)
                        bDontCheckDB = true;
                }
                else
                {
                    if (admin && IsClientInGame(admin))
                    {
                        PrintToChat(admin, "%s%t", PREFIX, "No permission unmute", g_sName[target]);
                        PrintToConsole(admin, "%s%t", PREFIX, "No permission unmute", g_sName[target]);
                    }
                    LogAction(admin, target, "\"%L\" tried (and didn't have permission) to unmute \"%L\" (reason \"%s\")", admin, target, sReason);
                    return;
                }
            }
            //-------------------------------------------------------------------------------------------------
            case TYPE_UNGAG:
            {
                if (!BaseComm_IsClientGagged(target))
                {
                    ReplyToCommand(admin, "%s%t", PREFIX, "Player not gagged");
                    return;
                }
                else if (bHasPermission)
                {
                    FormatEx(sTyperWHERE, sizeof(sTyperWHERE), "c.type = %d", TYPE_GAG);
                    if (g_GagType[target] == bSess)
                        bDontCheckDB = true;
                }
                else
                {
                    if (admin && IsClientInGame(admin))
                    {
                        PrintToChat(admin, "%s%t", PREFIX, "No permission ungag", g_sName[target]);
                        PrintToConsole(admin, "%s%t", PREFIX, "No permission ungag", g_sName[target]);
                    }
                    LogAction(admin, target, "\"%L\" tried (and didn't have permission) to ungag \"%L\" (reason \"%s\")", admin, target, sReason);
                    return;
                }
            }
            //-------------------------------------------------------------------------------------------------
            case TYPE_UNSILENCE:
            {
                if (!BaseComm_IsClientMuted(target) || !BaseComm_IsClientGagged(target))
                {
                    ReplyToCommand(admin, "%s%t", PREFIX, "Player not silenced");
                    return;
                }
                else if (bHasPermission)
                {
                    FormatEx(sTyperWHERE, sizeof(sTyperWHERE), "(c.type = %d OR c.type = %d)", TYPE_MUTE, TYPE_GAG);
                    if (g_MuteType[target] == bSess && g_GagType[target] == bSess)
                        bDontCheckDB = true;
                }
                else
                {
                    if (admin && IsClientInGame(admin))
                    {
                        PrintToChat(admin, "%s%t", PREFIX, "No permission unsilence", g_sName[target]);
                        PrintToConsole(admin, "%s%t", PREFIX, "No permission unsilence", g_sName[target]);
                    }
                    LogAction(admin, target, "\"%L\" tried (and didn't have permission) to unsilence \"%L\" (reason \"%s\")", admin, target, sReason);
                    return;
                }
            }
        }

        // Pack everything into a data pack so we can retain it
        new Handle:hDataPack = CreateDataPack();
        WritePackCell(hDataPack, GetClientUserId2(admin));
        WritePackCell(hDataPack, iAdmID);
        WritePackCell(hDataPack, GetClientUserId(target));
        WritePackCell(hDataPack, iType);
        WritePackString(hDataPack, sReason);
        WritePackString(hDataPack, sTargetName);
        WritePackString(hDataPack, sTargetAuth);

        // Check current player status. If player has temporary punishment - don't get info from DB
        if (!bDontCheckDB && SB_Connect())
        {
            decl String:sQuery[4096];
            Format(sQuery, sizeof(sQuery),
               "SELECT c.id, c.type \
                  FROM {{comms}} AS c \
                 WHERE c.steam_account_id = %d \
                       AND c.unban_time IS NULL \
                       AND (c.length = '0' OR c.create_time + c.length * 60 > UNIX_TIMESTAMP()) \
                       AND %s",
                iTargetAccountID, sTyperWHERE
            );

            #if defined LOG_QUERIES
                LogToFile(logQuery, "ProcessUnBlock. QUERY: %s", sQuery);
            #endif
            SB_Query(Query_UnBlockSelect, sQuery, hDataPack);
        }
        else
        {
            #if defined DEBUG
                PrintToServer("Calling TempUnBlock from ProcessUnBlock");
            #endif

            TempUnBlock(hDataPack); // datapack closed inside
            ShowActivityToServer(admin, iType + TYPE_TEMP_SHIFT, _, _, g_sName[target], _);
        }
    }
}

stock TempUnBlock(Handle:data)
{
    decl String:sReason[256];

    ResetPack(data);
    new iAdminUserID  = ReadPackCell(data);
    SetPackPosition(data, 16);              // skip AdminID
    new iTargetUserID = ReadPackCell(data);
    new iType         = ReadPackCell(data); // command type
    ReadPackString(data, sReason, sizeof(sReason));
    CloseHandle(data);                      // Need to close datapack

    new admin  = GetClientOfUserId(iAdminUserID);
    new target = GetClientOfUserId(iTargetUserID);

    #if defined DEBUG
        PrintToServer("TempUnBlock(adminUID: %d/%d, targetUID: %d/%d, type: %d, reason: %s)", iAdminUserID, admin, iTargetUserID, target, iType, sReason);
    #endif

    if (!target)
        return; // target has gone away

    switch(iType)
    {
        case TYPE_UNMUTE:
        {
            PerformUnMute(target);
            LogAction(admin, target, "\"%L\" temporary unmuted \"%L\" (reason \"%s\")", admin, target, sReason);
        }
        //-------------------------------------------------------------------------------------------------
        case TYPE_UNGAG:
        {
            PerformUnGag(target);
            LogAction(admin, target, "\"%L\" temporary ungagged \"%L\" (reason \"%s\")", admin, target, sReason);
        }
        //-------------------------------------------------------------------------------------------------
        case TYPE_UNSILENCE:
        {
            PerformUnMute(target);
            PerformUnGag(target);
            LogAction(admin, target, "\"%L\" temporary unsilenced \"%L\" (reason \"%s\")", admin, target, sReason);
        }
    }
}

stock InsertTempBlock(const _:iTargetAccountID, const String:sName[], const _:iLength, const String:sReason[], const _:iAdminID, const String:sAdminIP[], const _:iType)
{
    LogMessage("Saving punishment for Steam AccountID %d into queue", iTargetAccountID);

    new String:sNameEscaped[MAX_NAME_LENGTH * 2 + 1];
    new String:sReasonEscaped[256 * 2 + 1];

    decl String:sQuery[4096], String:sQueryVal[2048];
    new String:sQueryMute[2048], String:sQueryGag[2048];

    // escaping everything
    SQL_EscapeString(SQLiteDB, sName,   sNameEscaped,   sizeof(sNameEscaped));
    SQL_EscapeString(SQLiteDB, sReason, sReasonEscaped, sizeof(sReasonEscaped));

    // table schema:
    // id   steam_account_id    name    start_time  length  reason  admin_id    admin_ip    type
    FormatEx(sQueryVal, sizeof(sQueryVal),
        "%d, '%s', %d, %d, '%s', %d, '%s'",
        iTargetAccountID, sNameEscaped, GetTime(), iLength, sReasonEscaped, iAdminID, sAdminIP
    );

    if (iType == TYPE_MUTE || iType == TYPE_SILENCE)
    {
        FormatEx(sQueryMute, sizeof(sQueryMute), "(%s, %d)", sQueryVal, TYPE_MUTE);
    }
    if (iType == TYPE_GAG || iType == TYPE_SILENCE)
    {
        FormatEx(sQueryGag, sizeof(sQueryGag), "(%s, %d)", sQueryVal, TYPE_GAG);
    }

    FormatEx(sQuery, sizeof(sQuery),
        "INSERT INTO queue3 (steam_account_id, name, start_time, length, reason, admin_id, admin_ip, type) VALUES %s%s%s",
        sQueryMute, iType == TYPE_SILENCE ? ", " : "", sQueryGag);

    #if defined LOG_QUERIES
        LogToFile(logQuery, "InsertTempBlock. QUERY: %s", sQuery);
    #endif

    SQL_TQuery(SQLiteDB, Query_ErrorCheck, sQuery);
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

stock MarkClientAsUnMuted(target)
{
    g_MuteType[target]          = bNot;
    g_iMuteTime[target]         = 0;
    g_iMuteLength[target]       = 0;
    g_iMuteLevel[target]        = -1;
    g_iMuteAdminID[target]      = -1;
    g_sMuteAdminName[target][0] = '\0';
    g_sMuteReason[target][0]    = '\0';
}

stock MarkClientAsUnGagged(target)
{
    g_GagType[target]          = bNot;
    g_iGagTime[target]         = 0;
    g_iGagLength[target]       = 0;
    g_iGagLevel[target]        = -1;
    g_iGagAdminID[target]      = -1;
    g_sGagAdminName[target][0] = '\0';
    g_sGagReason[target][0]    = '\0';
}

stock MarkClientAsMuted(target, const iCreateTime = NOW, const iLength = -1, const String:sAdmName[] = "CONSOLE", const _:iAdmID = 0, const iAdmImmunity = 0, const String:sReason[] = "")
{
    if (iCreateTime)
        g_iMuteTime[target] = iCreateTime;
    else
        g_iMuteTime[target] = GetTime();

    g_iMuteLength[target]  = iLength;
    g_iMuteLevel[target]   = iAdmID ? iAdmImmunity : ConsoleImmunity;
    g_iMuteAdminID[target] = iAdmID;
    strcopy(g_sMuteAdminName[target], sizeof(g_sMuteAdminName[]), sAdmName);
    strcopy(g_sMuteReason[target],    sizeof(g_sMuteReason[]),    sReason);

    if (iLength > 0)
        g_MuteType[target] = bTime;
    else if (iLength == 0)
        g_MuteType[target] = bPerm;
    else
        g_MuteType[target] = bSess;
}

stock MarkClientAsGagged(target, const iCreateTime = NOW, const iLength = -1, const String:sAdmName[] = "CONSOLE", const _:iAdmID = 0, const iAdmImmunity = 0, const String:sReason[] = "")
{
    if (iCreateTime)
        g_iGagTime[target] = iCreateTime;
    else
        g_iGagTime[target] = GetTime();

    g_iGagLength[target]  = iLength;
    g_iGagLevel[target]   = iAdmID ? iAdmImmunity : ConsoleImmunity;
    g_iGagAdminID[target] = iAdmID;
    strcopy(g_sGagAdminName[target], sizeof(g_sGagAdminName[]), sAdmName);
    strcopy(g_sGagReason[target],    sizeof(g_sGagReason[]),    sReason);

    if (iLength > 0)
        g_GagType[target] = bTime;
    else if (iLength == 0)
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
            g_hMuteExpireTimer[target] = CreateTimer(float(remainingTime),              Timer_MuteExpire, GetClientUserId(target), TIMER_FLAG_NO_MAPCHANGE);
        else
            g_hMuteExpireTimer[target] = CreateTimer(float(g_iMuteLength[target] * 60), Timer_MuteExpire, GetClientUserId(target), TIMER_FLAG_NO_MAPCHANGE);
    }
}

stock CreateGagExpireTimer(target, remainingTime = 0)
{
    if (g_iGagLength[target] > 0)
    {
        if (remainingTime)
            g_hGagExpireTimer[target] = CreateTimer(float(remainingTime),             Timer_GagExpire, GetClientUserId(target), TIMER_FLAG_NO_MAPCHANGE);
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

stock PerformMute(target, const iCreateTime = NOW, const iLength = -1, const String:sAdmName[] = "CONSOLE", const _:iAdmID = 0, const iAdmImmunity = 0, const String:sReason[] = "", iRemainingTime = 0)
{
    MarkClientAsMuted(target, iCreateTime, iLength, sAdmName, iAdmID, iAdmImmunity, sReason);
    BaseComm_SetClientMute(target, true);
    CreateMuteExpireTimer(target, iRemainingTime);
}

stock PerformGag(target, const iCreateTime = NOW, const iLength = -1, const String:sAdmName[] = "CONSOLE", const _:iAdmID = 0, const iAdmImmunity = 0, const String:sReason[] = "", iRemainingTime = 0)
{
    MarkClientAsGagged(target, iCreateTime, iLength, sAdmName, iAdmID, iAdmImmunity, sReason);
    BaseComm_SetClientGag(target, true);
    CreateGagExpireTimer(target, iRemainingTime);
}

stock SavePunishment(admin = 0, const target, const _:iType, const iLength = -1 , const String:sReason[] = "")
{
    if (iType < TYPE_MUTE || iType > TYPE_SILENCE)
        return;

    // target information
    new iTargetAccountID = 0;
    if (IsClientInGame(target))
        iTargetAccountID = GetSteamAccountID(target);

    // if target left the game or Account ID is not available
    if (!iTargetAccountID)
        return;

    // Admin information
    new iAdminID;
    new String:sAdminIP[24];
    if (admin && IsClientInGame(admin))
    {
        iAdminID = SB_GetAdminId(admin);
        GetClientIP(admin, sAdminIP, sizeof(sAdminIP));
    }
    else
    {
        strcopy(sAdminIP,  sizeof(sAdminIP),  g_sServerIP);
    }

    new String:sAdminID[5];
    if (iAdminID)
        IntToString(iAdminID, sAdminID, sizeof(sAdminID));
    else
        strcopy(sAdminID, sizeof(sAdminID), "NULL");


    new String:sName[MAX_NAME_LENGTH];
    strcopy(sName, sizeof(sName), g_sName[target]);

    if (SB_Connect())
    {
        // Accepts length in minutes, writes to db in minutes! In all over places in plugin - length is in minutes (except timers).
        new String:sNameEscaped[MAX_NAME_LENGTH * 2 + 1];
        new String:sReasonEscaped[256 * 2 + 1];

        // escaping everything
        SB_Escape(sName,   sNameEscaped,   sizeof(sNameEscaped));
        SB_Escape(sReason, sReasonEscaped, sizeof(sReasonEscaped));

        // table schema:
        // id   type    steam_account_id    name    reason  length  server_id   admin_id    admin_ip    unban_admin_id  unban_reason    unban_time  create_time
        decl String:sQuery[4096], String:sQueryVal[1024];
        new String:sQueryMute[1024], String:sQueryGag[1024];

        // create_time, steam_account_id, name, reason, length, server_id, admin_id, admin_ip
        FormatEx(sQueryVal, sizeof(sQueryVal),
            "UNIX_TIMESTAMP(), %d, '%s', '%s', %d, %s, %s, '%s'",
            iTargetAccountID, sNameEscaped, sReasonEscaped, iLength, g_sServerID, sAdminID, sAdminIP
        );

        if (iType == TYPE_MUTE || iType == TYPE_SILENCE)
        {
            FormatEx(sQueryMute, sizeof(sQueryMute), "(%s, %d)", sQueryVal, TYPE_MUTE);
        }
        if (iType == TYPE_GAG || iType == TYPE_SILENCE)
        {
            FormatEx(sQueryGag, sizeof(sQueryGag), "(%s, %d)", sQueryVal, TYPE_GAG);
        }

        // litle magic - one query for all actions (mute, gag or silence)
        FormatEx(sQuery, sizeof(sQuery),
            "INSERT INTO {{comms}} (create_time, steam_account_id, name, reason, length, server_id, admin_id, admin_ip, type) VALUES %s%s%s",
            sQueryMute, iType == TYPE_SILENCE ? ", " : "", sQueryGag
        );

        #if defined LOG_QUERIES
            LogToFile(logQuery, "SavePunishment. QUERY: %s", sQuery);
        #endif

        // all data cached before calling asynchronous functions
        new Handle:hDataPack = CreateDataPack();
        WritePackCell(hDataPack, iTargetAccountID);
        WritePackCell(hDataPack, iAdminID);
        WritePackCell(hDataPack, iLength);
        WritePackCell(hDataPack, iType);
        WritePackString(hDataPack, sName);
        WritePackString(hDataPack, sReason);
        WritePackString(hDataPack, sAdminIP);

        SB_Query(Query_AddBlockInsert, sQuery, hDataPack, DBPrio_High);
    }
    else
    {
        InsertTempBlock(iTargetAccountID, sName, iLength, sReason, iAdminID, sAdminIP, iType);
    }
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
