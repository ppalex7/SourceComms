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

        PerformMute(target, _, muteLength, _, _, _, sReason);

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

        PerformGag(target, _, gagLength, _, _, _, sReason);

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
