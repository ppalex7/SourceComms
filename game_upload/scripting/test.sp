#include <sourcemod>


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
    AddCommandListener(CommandCallback, "sm_test4");
	AddCommandListener(CommandCallback, "sm_test3");

	// pack = ;

}

public Action:CommandCallback(client, const String:command[], args)
{
	// new String:a[1], String:big[128];

	new String:q[20*1000-1];

	new String:q5[1];
	new String:q6[1];

        PrintToServer("%s: %d, %d",command, client, args);
	return Plugin_Continue;

}

public OnClientPostAdminCheck(client){
	PrintToServer("%d",GetSteamAccountID(1));
}

stock Fu(String:val[])
{


}

/*Header size:           1976 bytes
Code size:             2132 bytes
Data size:             1244 bytes
Stack/heap size:      16384 bytes; Total requirements:   21736 bytes*/
