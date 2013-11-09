#pragma semicolon 1

#include <sourcemod>
#include <sourcebans>
#include <sourcecomms>

#define UNBLOCK_FLAG ADMFLAG_CUSTOM2

#define DEBUG
#define LOG_QUERIES
// #define REPLACE_BASECOMM

#if !defined REPLACE_BASECOMM
#include <basecomm>
#endif

#undef REQUIRE_PLUGIN
#include <adminmenu>

#if !defined DEBUG
#include <updater>
#endif


// Do not edit below this line //
//-----------------------------//

#define PLUGIN_VERSION "1.0.225"
#define PREFIX "\x04[SourceComms]\x01 "

#define UPDATE_URL "http://z.tf2news.ru/repo/sc-updatefile.txt"


/* Database handle */
new Handle:SQLiteDB;

/* Log Stuff */
#if defined LOG_QUERIES
    new String:logQuery[256];
#endif

/* Server info */

new g_iServerID;
new String:g_sServerIP[16];
new String:g_sServerID[5];

/* Servers white-list array */

new Handle:g_hServersWhiteList = INVALID_HANDLE;

// ---------------------------------------------------------------
#include "sourcecomms/config-parser.sp"     // Config parser code
#include "sourcecomms/core.sp"              // Core plugin code
#include "sourcecomms/common.sp"            // Common code
#include "sourcecomms/menu.sp"              // Menu code
#include "sourcecomms/natives.sp"           // plugin natives
// ---------------------------------------------------------------

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

    // Account for late loading
#if !defined DEBUG
    if (LibraryExists("updater"))
        Updater_AddPlugin(UPDATE_URL);
#endif

    if(LibraryExists("sourcebans"))
        SB_Init();
}

#if !defined DEBUG
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
#endif

public OnLibraryRemoved(const String:name[])
{
    if (StrEqual(name, "adminmenu"))
        g_hTopMenu = INVALID_HANDLE;
}

public OnMapStart()
{
    ReadConfig();
}


// CLIENT CONNECTION FUNCTIONS //

public OnClientDisconnect(client)
{
    CloseRecheckTimer(client);
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
            MarkClientAsMuted(client);
        if (BaseComm_IsClientGagged(client))
            MarkClientAsGagged(client);

        if (!VerifyPlayer(client))
            LogError("Can't determine Steam Account ID for player %s. Skip checking", sClientAuth);
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
    new String:sArgs[256];
    new String:sArg[3][64];
    GetCmdArgString(sArgs, sizeof(sArgs));

    new iType;
    new iLength;
    if(ExplodeString(sArgs, " ", sArg, 3, 64) != 3 || !StringToIntEx(sArg[0], iType) || iType < TYPE_MUTE || iType > TYPE_SILENCE || !StringToIntEx(sArg[1], iLength))
    {
        LogError("Wrong usage of sc_fw_block");
        return Plugin_Stop;
    }

    LogMessage("Received block command from web: steam %s, type %d, length %d", sArg[2], iType, iLength);

    for (new i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsClientAuthorized(i) && !IsFakeClient(i))
        {
            decl String:sClientAuth[64];
            GetClientAuthString(i, sClientAuth, sizeof(sClientAuth));
            if (strcmp(sClientAuth, sArg[2], false) == 0)
            {
                #if defined DEBUG
                    PrintToServer("Catched %s for blocking from web", sClientAuth);
                #endif

                if (g_MuteType[i] == bNot && (iType == TYPE_MUTE || iType == TYPE_SILENCE))
                {
                    PerformMute(i, _, iLength, _, _, _, _);
                    PrintToChat(i, "%s%t", PREFIX, "Muted on connect");
                    LogMessage("%s is muted from web", sClientAuth);
                }
                if (g_GagType[i] == bNot && (iType == TYPE_GAG || iType == TYPE_SILENCE))
                {
                    PerformGag(i, _, iLength, _, _, _, _);
                    PrintToChat(i, "%s%t", PREFIX, "Gagged on connect");
                    LogMessage("%s is gagged from web", sClientAuth);
                }
                break;
            }
        }
    }

    return Plugin_Handled;
}

public Action:FWUngag(args)
{
    new String:sArgs[256];
    new String:sArg[1][64];
    GetCmdArgString(sArgs, sizeof(sArgs));
    if(!ExplodeString(sArgs, " ", sArg, 1, 64))
    {
        LogError("Wrong usage of sc_fw_ungag");
        return Plugin_Stop;
    }

    LogMessage("Received ungag command from web: steam %s", sArg[0]);

    for (new i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsClientAuthorized(i) && !IsFakeClient(i))
        {
            decl String:sClientAuth[64];
            GetClientAuthString(i, sClientAuth, sizeof(sClientAuth));
            if (strcmp(sClientAuth, sArg[0], false) == 0)
            {
                #if defined DEBUG
                    PrintToServer("Catched %s for ungagging from web", sClientAuth);
                #endif

                if (g_GagType[i] > bNot)
                {
                    PerformUnGag(i);
                    PrintToChat(i, "%s%t", PREFIX, "FWUngag");
                    LogMessage("%s is ungagged from web", sClientAuth);
                }
                else
                    LogError("Can't ungag %s from web, it isn't gagged", sClientAuth);
                break;
            }
        }
    }
    return Plugin_Handled;
}

public Action:FWUnmute(args)
{
    new String:sArgs[256];
    new String:sArg[1][64];
    GetCmdArgString(sArgs, sizeof(sArgs));
    if(!ExplodeString(sArgs, " ", sArg, 1, 64))
    {
        LogError("Wrong usage of sc_fw_ungag");
        return Plugin_Stop;
    }

    LogMessage("Received unmute command from web: steam %s", sArg[0]);

    for (new i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsClientAuthorized(i) && !IsFakeClient(i))
        {
            decl String:sClientAuth[64];
            GetClientAuthString(i, sClientAuth, sizeof(sClientAuth));
            if (strcmp(sClientAuth, sArg[0], false) == 0)
            {
                #if defined DEBUG
                    PrintToServer("Catched %s for unmuting from web", sClientAuth);
                #endif

                if (g_MuteType[i] > bNot)
                {
                    PerformUnMute(i);
                    PrintToChat(i, "%s%t", PREFIX, "FWUnmute");
                    LogMessage("%s is unmuted from web", sClientAuth);
                }
                else
                    LogError("Can't unmute %s from web, it isn't muted", sClientAuth);
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

    new iType;
    if (StrEqual(command, "sm_gag", false))
        iType = TYPE_GAG;
    else if (StrEqual(command, "sm_mute", false))
        iType = TYPE_MUTE;
    else if (StrEqual(command, "sm_ungag", false))
        iType = TYPE_UNGAG;
    else if (StrEqual(command, "sm_unmute", false))
        iType = TYPE_UNMUTE;
    else if (StrEqual(command, "sm_silence", false))
        iType = TYPE_SILENCE;
    else if (StrEqual(command, "sm_unsilence", false))
        iType = TYPE_UNSILENCE;
    else
        return Plugin_Stop;

    if (args < 1)
    {
        ReplyToCommand(client, "%sUsage: %s <#userid|name> %s", PREFIX, command, iType <= TYPE_SILENCE ? "[time|0] [reason]" : "[reason]");
        if (iType <= TYPE_SILENCE)
            ReplyToCommand(client, "%sUsage: %s <#userid|name> [reason]", PREFIX, command);
        return Plugin_Stop;
    }

    new String:sBuffer[256];
    GetCmdArgString(sBuffer, sizeof(sBuffer));

    if (iType <= TYPE_SILENCE)
        CreateBlock(client, _, _, iType, _, sBuffer);
    else
        ProcessUnBlock(client, _, iType, _, sBuffer);

    return Plugin_Stop;
}


// MENU CODE //

public OnAdminMenuReady(Handle:topmenu)
{
    /* Block us from being called twice */
    if (topmenu == g_hTopMenu)
        return;

    /* Save the Handle */
    g_hTopMenu = topmenu;

    new TopMenuObject:MenuObject = AddToTopMenu(g_hTopMenu, "sourcecomm_cmds", TopMenuObject_Category, Handle_Commands, INVALID_TOPMENUOBJECT);
    if (MenuObject == INVALID_TOPMENUOBJECT)
        return;

    AddToTopMenu(g_hTopMenu, "sourcecomm_gag",       TopMenuObject_Item, Handle_MenuGag,       MenuObject, "sm_gag",       ADMFLAG_CHAT);
    AddToTopMenu(g_hTopMenu, "sourcecomm_ungag",     TopMenuObject_Item, Handle_MenuUnGag,     MenuObject, "sm_ungag",     ADMFLAG_CHAT);
    AddToTopMenu(g_hTopMenu, "sourcecomm_mute",      TopMenuObject_Item, Handle_MenuMute,      MenuObject, "sm_mute",      ADMFLAG_CHAT);
    AddToTopMenu(g_hTopMenu, "sourcecomm_unmute",    TopMenuObject_Item, Handle_MenuUnMute,    MenuObject, "sm_unmute",    ADMFLAG_CHAT);
    AddToTopMenu(g_hTopMenu, "sourcecomm_silence",   TopMenuObject_Item, Handle_MenuSilence,   MenuObject, "sm_silence",   ADMFLAG_CHAT);
    AddToTopMenu(g_hTopMenu, "sourcecomm_unsilence", TopMenuObject_Item, Handle_MenuUnSilence, MenuObject, "sm_unsilence", ADMFLAG_CHAT);
    AddToTopMenu(g_hTopMenu, "sourcecomm_list",      TopMenuObject_Item, Handle_MenuList,      MenuObject, "sm_commlist",  ADMFLAG_CHAT);
}


// Sourcebans callbacks //

public SB_OnConnect(Handle:database)
{
    g_iServerID = SB_GetConfigValue("ServerID");

    if (g_iServerID)
        IntToString(g_iServerID, g_sServerID, sizeof(g_sServerID));
    else
        strcopy(g_sServerID, sizeof(g_sServerID), "NULL");

    if (!g_iServerID && g_bConfigWhiteListOnly)
    {
        LogError("Unknown ServerID! ServersWhiteList feature disabled!");
        g_bConfigWhiteListOnly = 0;
    }

    ProcessQueue();
    ForcePlayersRecheck();
}

public SB_OnReload()
{
    // Get values from SourceBans config and store them locally
    SB_GetConfigString("ServerIP", g_sServerIP, sizeof(g_sServerIP));
}

//Yarr!
