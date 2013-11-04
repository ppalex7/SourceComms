#include <sourcemod>

#define MAX_REASONS 32
#define MAX_TIMES 32

#define DISPLAY_SIZE 64
#define REASON_SIZE 192

/* Global config variables */

new Float:g_fRetryTime     = 15.0;
new g_iDefaultTime         = 30;
new g_bDisUBImCheck        = false;
new g_iConsoleImmunity     = 0;
new g_iConfigMaxLength     = 0;
new g_bConfigWhiteListOnly = false;

/* Reasons for menu */
new g_iNumReasons;
new String:g_sReasonDisplays[MAX_REASONS][DISPLAY_SIZE];
new String:g_sReasonKey[MAX_REASONS][REASON_SIZE];

/* Punishment lenghts for menu */
new g_iNumTimes;
new g_iTimeMinutes[MAX_TIMES];
new String:g_sTimeDisplays[MAX_TIMES][DISPLAY_SIZE];

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
        g_iNumReasons = 0;
        g_iNumTimes = 0;
        InternalReadConfig(ConfigFile);
        if (g_iNumReasons)
            g_iNumReasons--;
        if (g_iNumTimes)
            g_iNumTimes--;
    }
    else
    {
        SetFailState("FATAL *** ERROR *** can't find %s", ConfigFile);
    }
    #if defined DEBUG
        PrintToServer("Loaded DefaultTime value: %d", g_iDefaultTime);
        PrintToServer("Loaded DisableUnblockImmunityCheck value: %b", g_bDisUBImCheck);
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
                g_fRetryTime = StringToFloat(value);
                if (g_fRetryTime < 15.0)
                {
                    g_fRetryTime = 15.0;
                }
                else if (g_fRetryTime > 60.0)
                {
                    g_fRetryTime = 60.0;
                }
            }
            else if (strcmp("DefaultTime", key, false) == 0)
            {
                g_iDefaultTime = StringToInt(value);
                if (g_iDefaultTime < 0)
                {
                    g_iDefaultTime = -1;
                }
                if (g_iDefaultTime == 0)
                {
                    g_iDefaultTime = 30;
                }
            }
            else if (strcmp("DisableUnblockImmunityCheck", key, false) == 0)
            {
                if (StringToInt(value) == 1)
                    g_bDisUBImCheck = true;
                else
                    g_bDisUBImCheck = false;
            }
            else if (strcmp("ConsoleImmunity", key, false) == 0)
            {
                g_iConsoleImmunity = StringToInt(value);
                if (g_iConsoleImmunity < 0 || g_iConsoleImmunity > 100)
                {
                    g_iConsoleImmunity = 0;
                }
            }
            else if (strcmp("MaxLength", key, false) == 0)
            {
                g_iConfigMaxLength = StringToInt(value);
            }
            else if (strcmp("OnlyWhiteListServers", key, false) == 0)
            {
                if (StringToInt(value) == 1)
                    g_bConfigWhiteListOnly = true;
                else
                    g_bConfigWhiteListOnly = false;
            }
        }
        case ConfigStateReasons:
        {
            Format(g_sReasonKey[g_iNumReasons], REASON_SIZE, "%s", key);
            Format(g_sReasonDisplays[g_iNumReasons], DISPLAY_SIZE, "%s", value);
            #if defined DEBUG
                PrintToServer("Loaded reason. index %d, key \"%s\", display_text \"%s\"", g_iNumReasons, g_sReasonKey[g_iNumReasons], g_sReasonDisplays[g_iNumReasons]);
            #endif
            g_iNumReasons++;
        }
        case ConfigStateTimes:
        {
            Format(g_sTimeDisplays[g_iNumTimes], DISPLAY_SIZE, "%s", value);
            g_iTimeMinutes[g_iNumTimes] = StringToInt(key);
            #if defined DEBUG
                PrintToServer("Loaded time. index %d, time %d minutes, display_text \"%s\"", g_iNumTimes, g_iTimeMinutes[g_iNumTimes] , g_sTimeDisplays[g_iNumTimes]);
            #endif
            g_iNumTimes++;
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
