/**
 * SourceComms Include File
 */

#if defined _sourcecomms_included
  #endinput
#endif
#define _sourcecomms_included

/**
 * Sets a client's mute state.
 *
 * @param client		Client index.
 * @param gagState		True to gag client, false to ungag.
 * -------------------------------------Parameters below this line are used only for muteState=true-------------------------------------
 * ----------------------------------for muteState=false these parameters are ignored (saveToDB=false)----------------------------------
 * @param gagLength		Length of punishment in minutes. Value < 0 muting client for session. Permanent (0) is not allowed at this time.
 * @param saveToDB		If true, punishment will be saved in database.
 * @param reason		Reason for punishment.
 * @return				True if this caused a change in mute state, false otherwise.
 */
native bool:SourceComms_SetClientMute(client, bool:muteState, muteLength = -1, bool:saveToDB = true, const String:reason[] = "Muted through natives");

/**
 * Sets a client's gag state.
 *
 * @param client		Client index.
 * @param gagState		True to gag client, false to ungag.
 * --------------------------------------Parameters below this line are used only for gagState=true--------------------------------------
 * -----------------------------------for gagState=false these parameters are ignored (saveToDB=false)-----------------------------------
 * @param gagLength		Length of punishment in minutes. Value < 0 gagging client for session. Permanent (0) is not allowed at this time.
 * @param saveToDB		If true, punishment will be saved in database.
 * @param reason		Reason for punishment.
 * @return				True if this caused a change in gag state, false otherwise.
 */
native bool:SourceComms_SetClientGag(client, bool:gagState, gagLength = -1, bool:saveToDB = true, const String:reason[] = "Gagged through natives");


public SharedPlugin:__pl_sourcecomms =
{
	name = "sourcecomms",
	file = "sourcecomms.smx",
	#if defined REQUIRE_PLUGIN
		required = 1
	#else
		required = 0
	#endif
};

public __pl_sourcecomms_SetNTVOptional()
{
	MarkNativeAsOptional("SourceComms_SetClientMute");
	MarkNativeAsOptional("SourceComms_SetClientGag");
}