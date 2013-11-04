enum State /* ConfigState */
{
    ConfigStateNone = 0,
    ConfigStateConfig,
    ConfigStateReasons,
    ConfigStateTimes,
    ConfigStateServers,
}

new State:ConfigState;
new Handle:ConfigParser;

/* stock functions */

stock InitializeConfigParser()
{
    if (ConfigParser == INVALID_HANDLE)
    {
        ConfigParser = SMC_CreateParser();
        SMC_SetReaders(ConfigParser, ReadConfig_NewSection, ReadConfig_KeyValue, ReadConfig_EndSection);
    }
}

stock InternalReadConfig(const String:path[])
{
    ConfigState = ConfigStateNone;

    new SMCError:err = SMC_ParseFile(ConfigParser, path);

    if (err != SMCError_Okay)
    {
        decl String:buffer[64];
        if (SMC_GetErrorString(err, buffer, sizeof(buffer)))
        {
            PrintToServer(buffer);
        }
        else
        {
            PrintToServer("Fatal parse error");
        }
    }
}

stock ReadConfig()
{
    InitializeConfigParser();

    if (ConfigParser == INVALID_HANDLE)
    {
        return;
    }

    decl String:ConfigFile[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, ConfigFile, sizeof(ConfigFile), "configs/sourcecomms.cfg");

    if (FileExists(ConfigFile))
    {
        PrintToServer("%sLoading configs/sourcecomms.cfg config file", PREFIX);
        iNumReasons = 0;
        iNumTimes = 0;
        InternalReadConfig(ConfigFile);
        if (iNumReasons)
            iNumReasons--;
        if (iNumTimes)
            iNumTimes--;
    }
    else
    {
        SetFailState("FATAL *** ERROR *** can't find %s", ConfigFile);
    }
    #if defined DEBUG
        PrintToServer("Loaded DefaultTime value: %d", DefaultTime);
        PrintToServer("Loaded DisableUnblockImmunityCheck value: %d", DisUBImCheck);
    #endif
}

/* public callbacks */

public SMCResult:ReadConfig_NewSection(Handle:smc, const String:name[], bool:opt_quotes)
{
    if (name[0])
    {
        if (strcmp("Config", name, false) == 0)
        {
            ConfigState = ConfigStateConfig;
        }
        else if (strcmp("CommsReasons", name, false) == 0)
        {
            ConfigState = ConfigStateReasons;
        }
        else if (strcmp("CommsTimes", name, false) == 0)
        {
            ConfigState = ConfigStateTimes;
        }
        else if (strcmp("ServersWhiteList", name, false) == 0)
        {
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
            if (strcmp("RetryTime", key, false) == 0)
            {
                RetryTime = StringToFloat(value);
                if (RetryTime < 15.0)
                {
                    RetryTime = 15.0;
                }
                else if (RetryTime > 60.0)
                {
                    RetryTime = 60.0;
                }
            }
            else if (strcmp("DefaultTime", key, false) == 0)
            {
                DefaultTime = StringToInt(value);
                if (DefaultTime < 0)
                {
                    DefaultTime = -1;
                }
                if (DefaultTime == 0)
                {
                    DefaultTime = 30;
                }
            }
            else if (strcmp("DisableUnblockImmunityCheck", key, false) == 0)
            {
                DisUBImCheck = StringToInt(value);
                if (DisUBImCheck != 1)
                {
                    DisUBImCheck = 0;
                }
            }
            else if (strcmp("ConsoleImmunity", key, false) == 0)
            {
                ConsoleImmunity = StringToInt(value);
                if (ConsoleImmunity < 0 || ConsoleImmunity > 100)
                {
                    ConsoleImmunity = 0;
                }
            }
            else if (strcmp("MaxLength", key, false) == 0)
            {
                ConfigMaxLength = StringToInt(value);
            }
            else if (strcmp("OnlyWhiteListServers", key, false) == 0)
            {
                ConfigWhiteListOnly = StringToInt(value);
                if (ConfigWhiteListOnly != 1)
                {
                    ConfigWhiteListOnly = 0;
                }
            }
        }
        case ConfigStateReasons:
        {
            Format(g_sReasonKey[iNumReasons], REASON_SIZE, "%s", key);
            Format(g_sReasonDisplays[iNumReasons], DISPLAY_SIZE, "%s", value);
            #if defined DEBUG
                PrintToServer("Loaded reason. index %d, key \"%s\", display_text \"%s\"", iNumReasons, g_sReasonKey[iNumReasons], g_sReasonDisplays[iNumReasons]);
            #endif
            iNumReasons++;
        }
        case ConfigStateTimes:
        {
            Format(g_sTimeDisplays[iNumTimes], DISPLAY_SIZE, "%s", value);
            g_iTimeMinutes[iNumTimes] = StringToInt(key);
            #if defined DEBUG
                PrintToServer("Loaded time. index %d, time %d minutes, display_text \"%s\"", iNumTimes, g_iTimeMinutes[iNumTimes] , g_sTimeDisplays[iNumTimes]);
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
                        PrintToServer("Loaded white list server id %d", srvID);
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
