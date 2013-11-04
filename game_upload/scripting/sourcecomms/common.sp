#include <sourcemod>

/* Timer handles */
new Handle:g_hPlayerRecheck[MAXPLAYERS + 1] = {INVALID_HANDLE, ...};

// ------------------------------------------------------------------------------------------------------------------------


/* Functions for create and destroy timers for checking player status */

stock CreateRecheckTimer(const _:target, const Float:fDelay)
{
    #if defined DEBUG
        decl String:sTargetAuth[64];
        GetClientAuthString(target, sTargetAuth, sizeof(sTargetAuth));
    #endif

    if (g_hPlayerRecheck[target] == INVALID_HANDLE)
    {
        #if defined DEBUG
            PrintToServer("Creating Recheck timer for %s, with delay: %f", sTargetAuth, fDelay);
        #endif
        g_hPlayerRecheck[target] = CreateTimer(fDelay, ClientRecheck, GetClientUserId(target));
    }
    #if defined DEBUG
    else
        PrintToServer("Recheck timer already exists for %s", sTargetAuth);
    #endif
}

stock CloseRecheckTimer(const _:target)
{
    if (g_hPlayerRecheck[target] != INVALID_HANDLE && CloseHandle(g_hPlayerRecheck[target]))
        g_hPlayerRecheck[target] = INVALID_HANDLE;
}

/* timer-callback */

public Action:ClientRecheck(Handle:timer, any:userid)
{
    #if defined DEBUG
        PrintToServer("ClientRecheck(userid: %d)", userid);
    #endif

    new target = GetClientOfUserId(userid);
    if (!target)
        return;

    if (IsClientConnected(target))
        OnClientPostAdminCheck(target);

    g_hPlayerRecheck[target] =  INVALID_HANDLE;
}

// ------------------------------------------------------------------------------------------------------------------------


/* Function that checking status of all players (called from OnConnect database callback) */

stock ForcePlayersRecheck()
{
    for (new i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsClientAuthorized(i) && !IsFakeClient(i))
            CreateRecheckTimer(i, float(i));
    }
}

// ------------------------------------------------------------------------------------------------------------------------


/* Drops old tables and creates new (if not exists) into local database */

stock InitializeBackupDB()
{
    decl String:error[255];
    SQLiteDB = SQLite_UseDatabase("sourcecomms-queue", error, sizeof(error));
    if (SQLiteDB == INVALID_HANDLE)
    {
        SetFailState(error);
    }

    // Drop old tables
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

// ------------------------------------------------------------------------------------------------------------------------


/* Common SQL-callback */

public Query_ErrorCheck(Handle:owner, Handle:hndl, const String:error[], any:data)
{
    if (hndl == INVALID_HANDLE || error[0])
        LogError("%T (%s)", "Failed to query database", LANG_SERVER, error);
}

// ------------------------------------------------------------------------------------------------------------------------


/* Magic function that independently chooses translation name */

stock ShowActivityToServer(const _:admin, const _:iType, const _:iLength = 0, const String:sReason[] = "", const String:sTargetName[], bool:bTnIsMl = false)
{
    #if defined DEBUG
        PrintToServer("ShowActivityToServer(admin: %d, type: %d, length: %d, reason: %s, name: %s, ml: %b",
            admin, iType, iLength, sReason, sTargetName, bTnIsMl);
    #endif

    new String:sActionName[32];
    new String:sTranslationName[64];
    switch(iType)
    {
        case TYPE_MUTE:
        {
            if (iLength > 0)
                strcopy(sActionName, sizeof(sActionName), "Muted");
            else if (iLength == 0)
                strcopy(sActionName, sizeof(sActionName), "Permamuted");
            else    // temp block
                strcopy(sActionName, sizeof(sActionName), "Temp muted");
        }
        //-------------------------------------------------------------------------------------------------
        case TYPE_GAG:
        {
            if (iLength > 0)
                strcopy(sActionName, sizeof(sActionName), "Gagged");
            else if (iLength == 0)
                strcopy(sActionName, sizeof(sActionName), "Permagagged");
            else    //temp block
                strcopy(sActionName, sizeof(sActionName), "Temp gagged");
        }
        //-------------------------------------------------------------------------------------------------
        case TYPE_SILENCE:
        {
            if (iLength > 0)
                strcopy(sActionName, sizeof(sActionName), "Silenced");
            else if (iLength == 0)
                strcopy(sActionName, sizeof(sActionName), "Permasilenced");
            else    //temp block
                strcopy(sActionName, sizeof(sActionName), "Temp silenced");
        }
        //-------------------------------------------------------------------------------------------------
        case TYPE_UNMUTE:
        {
            strcopy(sActionName, sizeof(sActionName), "Unmuted");
        }
        //-------------------------------------------------------------------------------------------------
        case TYPE_UNGAG:
        {
            strcopy(sActionName, sizeof(sActionName), "Ungagged");
        }
        //-------------------------------------------------------------------------------------------------
        case TYPE_TEMP_UNMUTE:
        {
            strcopy(sActionName, sizeof(sActionName), "Temp unmuted");
        }
        //-------------------------------------------------------------------------------------------------
        case TYPE_TEMP_UNGAG:
        {
            strcopy(sActionName, sizeof(sActionName), "Temp ungagged");
        }
        //-------------------------------------------------------------------------------------------------
        case TYPE_TEMP_UNSILENCE:
        {
            strcopy(sActionName, sizeof(sActionName), "Temp unsilenced");
        }
        //-------------------------------------------------------------------------------------------------
        default:
        {
            return;
        }
    }

    Format(sTranslationName, sizeof(sTranslationName), "%s %s", sActionName, sReason[0] == '\0' ? "player" : "player reason");
    #if defined DEBUG
        PrintToServer("translation name: %s", sTranslationName);
    #endif

    if (iLength > 0)
    {
        if (bTnIsMl)
            ShowActivity2(admin, PREFIX, "%t", sTranslationName,       sTargetName, iLength, sReason);
        else
            ShowActivity2(admin, PREFIX, "%t", sTranslationName, "_s", sTargetName, iLength, sReason);
    }
    else
    {
        if (bTnIsMl)
            ShowActivity2(admin, PREFIX, "%t", sTranslationName,       sTargetName,         sReason);
        else
            ShowActivity2(admin, PREFIX, "%t", sTranslationName, "_s", sTargetName,         sReason);
    }
}

// ------------------------------------------------------------------------------------------------------------------------


/* Function to check that specified punishment length is allowed for this admin */

stock bool:IsAllowedBlockLength(const _:admin, const _:iLength, const _:iTargetCount = 1)
{
    if (iTargetCount == 1)
    {
        if (!g_iConfigMaxLength)
            return true;    // Restriction disabled
        if (!admin)
            return true;    // all allowed for console
        if (AdmHasFlag(admin))
            return true;    // all allowed for admins with special flag
        if (!iLength || iLength > g_iConfigMaxLength)
            return false;
        else
            return true;
    }
    else
    {
        if (iLength < 0)
            return true;    // session punishments allowed for mass-tergeting
        if (!iLength)
            return false;
        if (iLength > MAX_TIME_MULTI)
            return false;
        if (iLength > g_iDefaultTime)
            return false;
        else
            return true;
    }
}

// ------------------------------------------------------------------------------------------------------------------------


/* Function checks that admin has special admin flag */

stock bool:AdmHasFlag(const _:admin)
{
    return admin && CheckCommandAccess(admin, "", UNBLOCK_FLAG, true);
}

// ------------------------------------------------------------------------------------------------------------------------


/* Returns admin immunity level (and for CONSOLE too) */

stock _:GetAdmImmunity(const _:admin, const _:iAdminID)
{
    if (admin && GetUserAdmin(admin) != INVALID_ADMIN_ID)
        return GetAdminImmunityLevel(GetUserAdmin(admin));
    else if (!admin && !iAdminID)
        return g_iConsoleImmunity;
    else
        return 0;
}

// ------------------------------------------------------------------------------------------------------------------------


/* ALternative version of GetClientUserId, which returns 0 for CONSOLE */

stock _:GetClientUserId2(const _:admin)
{
    if (admin)
        return GetClientUserId(admin);
    else
        return 0;
}

// ------------------------------------------------------------------------------------------------------------------------


/* The function checks the ability to remove the punishment on the basis of admin immunity */

stock bool:ImmunityCheck(const _:admin, const _:target, const _:iAdminID, const _:iType)
{
    if (g_bDisUBImCheck != 0)
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

// ------------------------------------------------------------------------------------------------------------------------


/* The function checks the ability to remove the punishment on the basis of admin rights */

stock bool:AdminCheck(const _:admin, const _:target, const _:iAdminID, const _:iType)
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

// ------------------------------------------------------------------------------------------------------------------------


/* The function checks whether the punishment to be applied on the server */

stock bool:NotApplyToThisServer(const _:srvID)
{
    if (g_bConfigWhiteListOnly && FindValueInArray(g_hServersWhiteList, srvID) == -1)
        return true;
    else
        return false;
}
