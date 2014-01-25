#include <sourcemod>
#include <sourcebans>

public SharedPlugin:__pl_basecomm =
{
    name = "basecomm",
    file = "sourcecomms.smx",
    required = 0
};

// public __pl_basecomm_SetNTVOptional()
// {
//     MarkNativeAsOptional("BaseComm_IsClientGagged");
//     MarkNativeAsOptional("BaseComm_IsClientMuted");
//     MarkNativeAsOptional("BaseComm_SetClientGag");
//     MarkNativeAsOptional("BaseComm_SetClientMute");
// }

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{


    CreateNative("BaseComm_IsClientGagged", Native_SetClientMute);
    CreateNative("BaseComm_IsClientMuted",  Native_SetClientMute);
    CreateNative("BaseComm_SetClientGag",   Native_SetClientMute);
    CreateNative("BaseComm_SetClientMute",  Native_SetClientMute);
    RegPluginLibrary("basecomm");

    return APLRes_Success;
}

public Native_SetClientMute(Handle:hPlugin, numParams)
{
    new target = GetNativeCell(1);
    PrintToServer("from native %d", target);
}

public OnPluginStart()
{
    RegServerCmd("test_sb_connect", sbc, _, _);
    RegServerCmd("test_sb_execute_good", sbe1);
    RegServerCmd("test_sb_execute_bad", sbe2);
    RegServerCmd("test_sb_query_good", sbq1);
    RegServerCmd("test_sb_query_bad", sbq2);
}

public Action:sbc(args) {
    PrintToServer("SB_Connect returns: %b", SB_Connect());
    PrintToServer("done");
}

public Action:sbe1(args) {
    PrintToServer("SB_Execute('SELECT 1')");
    SB_Execute("SELECT 1");
    PrintToServer("done");
}

public Action:sbe2(args) {
    SB_Execute("SELECT blabla from unkown");
    PrintToServer("SB_Execute('SELECT blabla from unkown')");
    PrintToServer("done");
}

public Action:sbq1(args) {
    PrintToServer("SB_Query('SELECT 1')");
    SB_Query(cb, "SELECT 121");
    PrintToServer("done");
}

public Action:sbq2(args) {
    PrintToServer("SB_Query('SELECT bla from bla')");
    SB_Query(cb, "SELECT bla from bla");
    PrintToServer("done");
}

public cb(Handle:owner, Handle:hndl, const String:error[], any:data)
{
    if(error[0])
    {
        PrintToServer("Error: (%s)", error);
    }
    else
    {
        PrintToServer("no errors");
        while (SQL_FetchRow(hndl))
        {
            PrintToServer("data: %d", SQL_FetchInt(hndl, 0));
        }
    }
}
