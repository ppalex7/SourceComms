#include <sourcemod>
#include <basecomm>
#include <sourcebans>
#include <sb_admins>

/* Constants */
// maximum mass-target punishment length
#define MAX_TIME_MULTI 30

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

/* Common variables */
new bool:g_bPlayerStatus[MAXPLAYERS + 1];                       // Is player status checked in database?
new String:g_sName[MAXPLAYERS + 1][MAX_NAME_LENGTH];            // Names of players

/* Timer handles */
new Handle:g_hGagExpireTimer[MAXPLAYERS + 1] = {INVALID_HANDLE, ...};
new Handle:g_hMuteExpireTimer[MAXPLAYERS + 1] = {INVALID_HANDLE, ...};

/* Variables for "mute" */
new bType:g_MuteType[MAXPLAYERS + 1];                           // Player voice status
new _:g_iMuteTime[MAXPLAYERS + 1];                              // Mute start time
new _:g_iMuteLength[MAXPLAYERS + 1];                            // Mute length, in minutes
new _:g_iMuteLevel[MAXPLAYERS + 1];                             // immunity level of issuer admin
new _:g_iMuteAdminID[MAXPLAYERS + 1];                           // issuer admin id from sourcebans
new String:g_sMuteAdminName[MAXPLAYERS + 1][MAX_NAME_LENGTH];   // issuer admin name
new String:g_sMuteReason[MAXPLAYERS + 1][256];                  // Mute reason

/* Variables for "gag" */
new bType:g_GagType[MAXPLAYERS + 1];                            // Player chat status
new _:g_iGagTime[MAXPLAYERS + 1];                               // Gag start time
new _:g_iGagLength[MAXPLAYERS + 1];                             // Gag length, in minutes
new _:g_iGagLevel[MAXPLAYERS + 1];                              // immunity level of issuer admin
new _:g_iGagAdminID[MAXPLAYERS + 1];                            // issuer admin id from sourcebans
new String:g_sGagAdminName[MAXPLAYERS + 1][MAX_NAME_LENGTH];    // issyer admin name
new String:g_sGagReason[MAXPLAYERS + 1][256];                   // Gag reason

// ------------------------------------------------------------------------------------------------------------------------


/* Functions to work with punishment expires timers */

stock CloseMuteExpireTimer(const _:target)
{
    if (g_hMuteExpireTimer[target] != INVALID_HANDLE && CloseHandle(g_hMuteExpireTimer[target]))
        g_hMuteExpireTimer[target] = INVALID_HANDLE;
}

stock CloseGagExpireTimer(const _:target)
{
    if (g_hGagExpireTimer[target] != INVALID_HANDLE && CloseHandle(g_hGagExpireTimer[target]))
        g_hGagExpireTimer[target] = INVALID_HANDLE;
}

stock CreateMuteExpireTimer(const _:target, const _:iRemainingTime = 0)
{
    if (g_iMuteLength[target] > 0)
    {
        if (iRemainingTime)
            g_hMuteExpireTimer[target] = CreateTimer(float(iRemainingTime),             Timer_MuteExpire, GetClientUserId(target), TIMER_FLAG_NO_MAPCHANGE);
        else
            g_hMuteExpireTimer[target] = CreateTimer(float(g_iMuteLength[target] * 60), Timer_MuteExpire, GetClientUserId(target), TIMER_FLAG_NO_MAPCHANGE);
    }
}

stock CreateGagExpireTimer(const _:target, const _:iRemainingTime = 0)
{
    if (g_iGagLength[target] > 0)
    {
        if (iRemainingTime)
            g_hGagExpireTimer[target] = CreateTimer(float(iRemainingTime),            Timer_GagExpire, GetClientUserId(target), TIMER_FLAG_NO_MAPCHANGE);
        else
            g_hGagExpireTimer[target] = CreateTimer(float(g_iGagLength[target] * 60), Timer_GagExpire, GetClientUserId(target), TIMER_FLAG_NO_MAPCHANGE);
    }
}

/* Timer callbacks */

public Action:Timer_MuteExpire(Handle:timer, any:userid)
{
    new target = GetClientOfUserId(userid);
    if (!target)
        return;

    #if defined DEBUG
        decl String:sTargetAuth[64];
        GetClientAuthString(target, sTargetAuth,sizeof(sTargetAuth));
        PrintToServer("Mute expired for %s", sTargetAuth);
    #endif

    PrintToChat(target, "%s%t", PREFIX, "Mute expired");

    g_hMuteExpireTimer[target] = INVALID_HANDLE;
    MarkClientAsUnMuted(target);
    if (IsClientInGame(target))
        BaseComm_SetClientMute(target, false);
}

public Action:Timer_GagExpire(Handle:timer, any:userid)
{
    new target = GetClientOfUserId(userid);
    if (!target)
        return;

    #if defined DEBUG
        decl String:sTargetAuth[64];
        GetClientAuthString(target, sTargetAuth,sizeof(sTargetAuth));
        PrintToServer("Gag expired for %s", sTargetAuth);
    #endif

    PrintToChat(target, "%s%t", PREFIX, "Gag expired");

    g_hGagExpireTimer[target] = INVALID_HANDLE;
    MarkClientAsUnGagged(target);
    if (IsClientInGame(target))
        BaseComm_SetClientGag(target, false);
}

// ------------------------------------------------------------------------------------------------------------------------


/* Functions to mark player as "clean" */

stock MarkClientAsUnMuted(const _:target)
{
    g_MuteType[target]          = bNot;
    g_iMuteTime[target]         = 0;
    g_iMuteLength[target]       = 0;
    g_iMuteLevel[target]        = -1;
    g_iMuteAdminID[target]      = -1;
    g_sMuteAdminName[target][0] = '\0';
    g_sMuteReason[target][0]    = '\0';
}

stock MarkClientAsUnGagged(const _:target)
{
    g_GagType[target]          = bNot;
    g_iGagTime[target]         = 0;
    g_iGagLength[target]       = 0;
    g_iGagLevel[target]        = -1;
    g_iGagAdminID[target]      = -1;
    g_sGagAdminName[target][0] = '\0';
    g_sGagReason[target][0]    = '\0';
}

// ------------------------------------------------------------------------------------------------------------------------


/* Functions to mark player as "punished" */

stock MarkClientAsMuted(const _:target, const _:iCreateTime = NOW, const _:iLength = -1, const String:sAdmName[] = "CONSOLE", const _:iAdmID = 0, const _:iAdmImmunity = 0, const String:sReason[] = "")
{
    if (iCreateTime)
        g_iMuteTime[target] = iCreateTime;
    else
        g_iMuteTime[target] = GetTime();

    g_iMuteLength[target]  = iLength;
    g_iMuteLevel[target]   = iAdmID ? iAdmImmunity : g_iConsoleImmunity;
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

stock MarkClientAsGagged(const _:target, const _:iCreateTime = NOW, const _:iLength = -1, const String:sAdmName[] = "CONSOLE", const _:iAdmID = 0, const _:iAdmImmunity = 0, const String:sReason[] = "")
{
    if (iCreateTime)
        g_iGagTime[target] = iCreateTime;
    else
        g_iGagTime[target] = GetTime();

    g_iGagLength[target]  = iLength;
    g_iGagLevel[target]   = iAdmID ? iAdmImmunity : g_iConsoleImmunity;
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

// ------------------------------------------------------------------------------------------------------------------------


/* Functions for remove punishment from player */

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

// ------------------------------------------------------------------------------------------------------------------------


/* Functions for punishing player */

stock PerformMute(const _:target, const _:iCreateTime = NOW, const _:iLength = -1, const String:sAdmName[] = "CONSOLE", const _:iAdmID = 0, const _:iAdmImmunity = 0, const String:sReason[] = "", const _:iRemainingTime = 0)
{
    MarkClientAsMuted(target, iCreateTime, iLength, sAdmName, iAdmID, iAdmImmunity, sReason);
    BaseComm_SetClientMute(target, true);
    CreateMuteExpireTimer(target, iRemainingTime);
}

stock PerformGag(const _:target, const _:iCreateTime = NOW, const _:iLength = -1, const String:sAdmName[] = "CONSOLE", const _:iAdmID = 0, const _:iAdmImmunity = 0, const String:sReason[] = "", const _:iRemainingTime = 0)
{
    MarkClientAsGagged(target, iCreateTime, iLength, sAdmName, iAdmID, iAdmImmunity, sReason);
    BaseComm_SetClientGag(target, true);
    CreateGagExpireTimer(target, iRemainingTime);
}

// ------------------------------------------------------------------------------------------------------------------------


/* Function for saving punishment info into local database (queue) */

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

// ------------------------------------------------------------------------------------------------------------------------


/* Function for saving punishment info into main database */

stock SavePunishment(const _:admin = 0, const _:target, const _:iType, const _:iLength = -1 , const String:sReason[] = "")
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
    new String:sAdminID[5];
    if (admin && IsClientInGame(admin))
    {
        iAdminID = SB_GetAdminId(admin);
        GetClientIP(admin, sAdminIP, sizeof(sAdminIP));
    }
    else
    {
        strcopy(sAdminIP,  sizeof(sAdminIP),  g_sServerIP);
    }
    if (iAdminID)
        IntToString(iAdminID, sAdminID, sizeof(sAdminID));
    else
        strcopy(sAdminID, sizeof(sAdminID), "NULL");

    if (SB_Connect())
    {
        // Accepts length in minutes, writes to db in minutes! In all over places in plugin - length is in minutes (except timers).
        new String:sNameEscaped[MAX_NAME_LENGTH * 2 + 1];
        new String:sReasonEscaped[256 * 2 + 1];

        // escaping everything
        SB_Escape(g_sName[target], sNameEscaped,   sizeof(sNameEscaped));
        SB_Escape(sReason,         sReasonEscaped, sizeof(sReasonEscaped));

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
        WritePackString(hDataPack, g_sName[target]);
        WritePackString(hDataPack, sReason);
        WritePackString(hDataPack, sAdminIP);

        SB_Query(Query_AddBlockInsert, sQuery, hDataPack, DBPrio_High);
    }
    else
    {
        InsertTempBlock(iTargetAccountID, g_sName[target], iLength, sReason, iAdminID, sAdminIP, iType);
    }
}

/* sql-callback */

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

// ------------------------------------------------------------------------------------------------------------------------


/**
 * Function that completely punishes player (or several) and saves info into database
 *
 * This function is called from CommandCallback and Menu code
 */

stock CreateBlock(const _:admin, const _:targetId = 0, _:iLength = -1, const _:iType, const String:sReasonArg[] = "", const String:sArgs[] = "")
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
        // target is passed (from Menu)
        iTargetList[0] = targetId;
        iTargetCount= 1;
        bTnIsMl = false;
        strcopy(sTargetName, sizeof(sTargetName), g_sName[targetId]);
        strcopy(sReason,      sizeof(sReason),      sReasonArg);
    }
    else if (strlen(sArgs))
    {
        // arguments string is passed (from CommandCallback)
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

        // Get the punishment length
        if (!StringToIntEx(sArg[1], iLength))   // not valid number in second argument
        {
            iLength = g_iDefaultTime;
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
        // no valid data passed
        return;
    }

    new iAdmID = admin && IsClientInGame(admin) ? SB_GetAdminId(admin) : 0;
    new iAdmImmunity = GetAdmImmunity(admin, iAdmID);

    for (new i = 0; i < iTargetCount; i++)
    {
        new target = iTargetList[i];

        #if defined DEBUG
            decl String:sTargetAuth[64];
            GetClientAuthString(target, sTargetAuth, sizeof(sTargetAuth));
            PrintToServer("Processing block for %s", sTargetAuth);
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
                        PrintToServer("%s not muted. Mute him, creating unmute timer and add record to DB", sTargetAuth);
                    #endif

                    PerformMute(target, _, iLength, g_sName[admin], iAdmID, iAdmImmunity, sReason);

                    LogAction(admin, target, "\"%L\" muted \"%L\" (minutes \"%d\") (reason \"%s\")", admin, target, iLength, sReason);
                }
                else
                {
                    #if defined DEBUG
                        PrintToServer("%s already muted", sTargetAuth);
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
                        PrintToServer("%s not gagged. Gag him, creating ungag timer and add record to DB", sTargetAuth);
                    #endif

                    PerformGag(target, _, iLength, g_sName[admin], iAdmID, iAdmImmunity, sReason);

                    LogAction(admin, target, "\"%L\" gagged \"%L\" (minutes \"%d\") (reason \"%s\")", admin, target, iLength, sReason);
                }
                else
                {
                    #if defined DEBUG
                        PrintToServer("%s already gagged", sTargetAuth);
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
                        PrintToServer("%s not silenced. Silence him, creating ungag & unmute timers and add records to DB", sTargetAuth);
                    #endif

                    PerformMute(target, _, iLength, g_sName[admin], iAdmID, iAdmImmunity, sReason);
                    PerformGag(target,  _, iLength, g_sName[admin], iAdmID, iAdmImmunity, sReason);

                    LogAction(admin, target, "\"%L\" silenced \"%L\" (minutes \"%d\") (reason \"%s\")", admin, target, iLength, sReason);
                }
                else
                {
                    #if defined DEBUG
                        PrintToServer("%s already gagged or/and muted", sTargetAuth);
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
}

// ------------------------------------------------------------------------------------------------------------------------


/* Function for temporary removing punishment from player (without changes in database) */

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

// ------------------------------------------------------------------------------------------------------------------------


/**
 * Function that completely removes punishments from player (or several) and updates info into database
 *
 * This function is called from CommandCallback and Menu code
 */

stock ProcessUnBlock(const _:admin, const _:targetId = 0, const _:iType, String:sReasonArg[] = "", const String:sArgs[] = "")
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

/* sql-callbacks */

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

// ------------------------------------------------------------------------------------------------------------------------


/* Functions to process local database (queue) */

stock ProcessQueue()
{
    SQL_TQuery(SQLiteDB, Query_ProcessQueue,
        "SELECT id, steam_account_id, name, start_time, length, reason, admin_id, admin_ip, type FROM queue3"
    );
}

/* sql-callbacks */

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

// ------------------------------------------------------------------------------------------------------------------------


/* Function for check player punishments in database. Returns false for invalid player Account ID */

stock bool:VerifyPlayer(const _:target)
{
    new iTargetAccountID = GetSteamAccountID(target);

    if (iTargetAccountID)
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
            iTargetAccountID
        );
        #if defined LOG_QUERIES
            LogToFile(logQuery, "VerifyPlayer for AccountID: %d. QUERY: %s", iTargetAccountID, sQuery);
        #endif
        SB_Query(Query_VerifyBlock, sQuery, GetClientUserId(target), DBPrio_High);

        return true;
    }
    else
    {
        return false;
    }
}

/* SQL-callback */

public Query_VerifyBlock(Handle:owner, Handle:hndl, const String:error[], any:userid)
{
    new target = GetClientOfUserId(userid);

    #if defined DEBUG
        PrintToServer("Query_VerifyBlock(userid: %d, client: %d)", userid, target);
    #endif

    if (!target)
        return;

    /* Failure happen. Do retry with delay */
    if (hndl == INVALID_HANDLE || error[0])
    {
        LogError("Query_VerifyBlock failed: %s", error);
        CreateRecheckTimer(target, g_fRetryTime);
        return;
    }

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
            if (!iAdmID && g_iConsoleImmunity > iAdmImmunity)
                iAdmImmunity = g_iConsoleImmunity;

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
                    if (g_MuteType[target] < bTime)
                    {
                        PerformMute(target, iCreateTime, iLength, sAdmName, iAdmID, iAdmImmunity, sReason, iRemainingTime);
                        PrintToChat(target, "%s%t", PREFIX, "Muted on connect");
                    }
                }
                case TYPE_GAG:
                {
                    if (g_GagType[target] < bTime)
                    {
                        PerformGag(target, iCreateTime, iLength, sAdmName, iAdmID, iAdmImmunity, sReason, iRemainingTime);
                        PrintToChat(target, "%s%t", PREFIX, "Gagged on connect");
                    }
                }
            }
        }
    }

    g_bPlayerStatus[target] = true;
}
