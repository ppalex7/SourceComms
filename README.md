# SourceComms
A sourcemod plugin, which provides extended, temporary and permanent punishments with full history storing in sourcebans system.
Also includes files and instructions to integration to existing sourcebans web-pages.

***********
**Important note:** If you has installed web part before 16th March 2013, please follow the [instructions](https://github.com/d-ai/SourceComms/tree/master/web_updates/update01.md) to update it to actual version.
***********

## Requirements
* Working sourcebans system *(yes, you need MySQL server and web server with PHP)*. Currently supported versions **1.4.*** (and 1.5.0 for sourcebans plugin). Integration into sourcebans 2.0 currently in development.
* SourceMod **1.5.0-hg3761** or **newer** is required to use plugin on server.
* SourceMod **1.6** is required to **compile** the plugin. *(Compiled plugin also works on SourceMod 1.5)*

##Compatibility:
* In theory - all games on the Source 2009 engine.
* Plugin tested on TF2, CS:S, CS:GO servers.

## Features
### Server plugin
* Provides a straightforward category in the sm_admin menu where administrators can punish players as well as view current comm punishments.
	* The original BaseComm menu option still exist, and will still function.
	* SourceComms plugin support toring history of punishments from BaseComm and another plugins.
	* The category provides options for issuing new punishments, removing and viewing current punishments (categorized based on the punishment), as well as a List feature that provides information about current punishments.
	* The category also modifies the player's names in all of the options to show what their current punishment is. [ ] = None, [G] = Gagged, [M] = Muted, [S] = Silenced. *I used Twisted|Panda menu code :)*
* All punishments (temporary, extended or permanent) are saved in MySQL database and are automatically reapplied (except temporary) when the punished player connects to the server. This allows punishments to be applied across multiple servers.
	* Extended punishments will automatically expire in-game at the designated time.
	* Permanent punishments remain on the player until an administrator removes them.
	* If the server has problems with access to the database, the punishments will store in SQLite database and would be added in the main database when connection is restored. *(like in sourcebans plugin, yes)*
* Also you could apply punishments to multi-targets (such as `@all`, `@ct`, `@blue`, etc...)^
	* Multi-target punishments will **not** be saved in db.
    * Removing punishments from multi-targets will removed punishments **temporary** (not from db).
    * Allowed session (temporary) punishments and extended with length less than 30 minutes **and** less than `DefaultTime` setting.
    * Permanent multi-target punishments **is not available**.
* SourceComms has support for protecting current punishments based on immunity levels.
	* When a punishment is issued, the administrator responsible has their immunity level attached to the punishment. In order to remove that punishment, the second administrator must have **higher** immunity level or special admin flag (<i>ADMFLAG\_CUSTOM2</i> by default. You may change it in sourcecode). Also, punishment can be removed by console or his author.
	* Punishments issued by *CONSOLE* has some immunity level (which is set in config, option *"ConsoleImmunity"*).
	* Immunity checking system could be disabled by setting option *"DisableUnblockImmunityCheck"* to value **1** in config file.
	* One more **important** moment. When somebody removes punishment - plugin retrieves *"punishment issuer admin id"* from database. If the request fails - punishment could be temporary removed (on server, not in database) only by console, admin with special flag or with higher immunity.
* Plugin has *Servers White List* feature. If enabled, plugin will apply on players punishments only from current server or servers listed in *White List*.
* Punishments reasons and times stored in config. More details about config listed below.
* SourceComms supports [auto-update](https://forums.alliedmods.net/showthread.php?p=1570806).

### Web part provides the following functionality:
* Full punishments history (includes time, server, admin, reason, block length, comments, etc).
* Showing type of block as icon in first column.
* Showing count of other blocks for this player (steam-id) at the right end of *'Player Name'* column (This allows you to quickly identify regular offenders).
* Admins with necessary rights could edit, delete blocks, and also *"ungag"* or *"umnute"* (like unban) player.
* If the block is still in effect, during unblocking or deleting, web-part sends command for ungag or unmute player to all servers.
* Search field for quick punishments search on all pages and advanced search options on Comms page.
* Admin-page *'Comms'* for adding new punishments.
* Command *'Block comms'* in player context menu on servers page

**Sample of web-part you may look [there](http://z.tf2news.ru/tbans/index.php?p=commslist)** (Login/pass `test`/`test`)

##Commands:
* `sm_comms` - Shows to player their communications status. *(Also may be used in chat as `/comms`)*
* `sm_mute <player> <optional:time> <optional:reason>` - Removes a player's ability to use in-game voice.
* `sm_gag <player> <optional:time> <optional:reason>` - Removes a player's ability to use in-game chat.
* `sm_silence <player> <optional:time> <optional:reason>` - Removes a player's ability to use in-game voice and chat.
* `sm_unmute <player> <optional:reason>` - Restores a player's ability to use in-game voice.
* `sm_ungag <player> <optional:reason>` - Restores a player's ability to use in-game chat.
* `sm_unsilence <player> <optional:reason>` - Restores a player's ability to use in-game voice and chat.

The **player** parameter could be Name *(only as single word, without whitespaces)*, UserID (`#127`) or *magic* targets (like `@all` or `@red`). Look at sourcemod [wiki](http://wiki.alliedmods.net/Admin_Commands_(SourceMod) for more details about targets.<br/>
The **time** parameter controls how long the player is punished. (`< 0` == Temporary, `0` == Permanent, `#` == Minutes). If not specified it will be *"DefaultTime"* minutes (default value is **30**).

##Cvars:
* `sourcecomms_version` - plugin version

##Config settings:
* `DefaultTime`. When admin run sm_gag (mute, silence) command only with player name - player will be gagged on *"DefaultTime"* value minutes. (if *"DefaultTime"* setted in **-1** -> player will be blocked only on session (until reconnect)). Value **0** *(permanent)* **is not allowed**.
* `DisableUnblockImmunityCheck` (0, 1). Default value is **0**. If setted to **1**, player can be ungagged only by issuer admin, console or admin with special flag. Also, If **0** player maybe unblocked by Admin with higher immunity level than issuer admin had.
* `ConsoleImmunity`. Default value is **0**. Immunity Level of server console.
* `MaxLength`, which works following way: Plugin will hide (for admins without ADMFLAG_CUSTOM 2) from menu all durations more than MaxLength and restricts punishments commands with `time > MaxLength` argument (or permanent).
* `OnlyWhiteListServers`. Default value is **0**. Set this option to **1** to applying on players punishments only from this server and servers listed in WhiteList. Value **0** applies on players punishments from any server.

##Installation instructions
First of all, download this repository as a zip file.
###Installation of server part
1. Upload all the contents of `game_upload` directory from the zip file to your gameserver into `/addons/sourcemod` folder.
2. Edit `addons/sourcemod/configs/databases.cfg` on your gameserver and add an entry for SourceComms. It should have the following general format:

		"sourcecomms"
		{
			"driver"			"mysql"
			"host"				"your_mysql_host"
			"database"			"your_sourcebans_database"
			"user"				"your_mysql_login"
			"pass"				"your_mysql_password"
			//"timeout"			"0"
			"port"				"your_database_port(default_3306)"
		}
3. (Optional) Edit `/addons/sourcemod/configs/adminmenu_sorting.txt`. Find `}` at the end of file and add **before**:

		"sourcecomm_cmds"
		{
			"item" "sourcecomm_gag"
			"item" "sourcecomm_mute"
			"item" "sourcecomm_silence"
			"item" "sourcecomm_ungag"
			"item" "sourcecomm_unmute"
			"item" "sourcecomm_unsilence"
			"item" "sourcecomm_list"
		}

### Installation of database part
1. **Check your sourcebans tables prefix!** Replace in query bellow prefix `sb` to yours, if you use another. Execute the following query on your sourcebans database:

		CREATE TABLE `sb_comms` (
		`bid` int(6) NOT NULL AUTO_INCREMENT,
		`authid` varchar(64) NOT NULL,
		`name` varchar(128) NOT NULL DEFAULT 'unnamed',
		`created` int(11) NOT NULL DEFAULT '0',
  		`ends` int(11) NOT NULL DEFAULT '0',
		`length` int(10) NOT NULL DEFAULT '0',
		`reason` text NOT NULL,
		`aid` int(6) NOT NULL DEFAULT '0',
		`adminIp` varchar(32) NOT NULL DEFAULT '',
		`sid` int(6) NOT NULL DEFAULT '0',
		`RemovedBy` int(8) DEFAULT NULL,
		`RemoveType` varchar(3) DEFAULT NULL,
		`RemovedOn` int(11) DEFAULT NULL,
		`type` tinyint(4) NOT NULL DEFAULT '0' COMMENT '1 - Mute, 2 - Gag',
		`ureason` text,
		PRIMARY KEY (`bid`),
		KEY `authid` (`authid`),
		KEY `created` (`created`),
		KEY `RemoveType` (`RemoveType`),
		KEY `type` (`type`),
		KEY `sid` (`sid`),
		KEY `aid` (`aid`),
		FULLTEXT KEY `authid_2` (`authid`),
		FULLTEXT KEY `name` (`name`),
		FULLTEXT KEY `reason` (`reason`)
		) ENGINE=MyISAM  DEFAULT CHARSET=utf8;
or you could import `sb_comms.sql` file **(please check table prefix in file!)** to database instead of copying code from this manual.
2. If you want to import punishments from ExtendedComm plugin:
* Check sourcebans table prefix and extendedcomm table name.
* If you have different prefix (not `sb_`) or table_name (not `extendedcomm`) - replace their in code below (or in `import.sql` file) to your values.
* If your `extendedcomm` table is in the different database - replace in code below (or in `import.sql` file) `extendedcomm` to `'database_with_table'.'name_of_extendedcomm_table'`
* Execute folowing queries on your sourcebans database (or import `import.sql` file)

		INSERT INTO sb_comms (authid, name, created, length, ends, reason, type) SELECT steam_id, name, mute_time, mute_length, mute_time+mute_length, mute_reason, 1 FROM extendedcomm WHERE (mute_type='1' OR mute_type='2');
		INSERT INTO sb_comms (authid, name, created, length, ends, reason, type) SELECT steam_id, name, gag_time, gag_length, gag_time+gag_length, gag_reason, 2 FROM extendedcomm WHERE (gag_type='1' OR gag_type='2');

### Installation of Web part
1. Upload all the contents of `web_upload` directory from the zip file to your webserver into root sourcebans folder (which contains such files as index.php, config.php, getdemo.php).
Place files from sourcecomms-web.zip archive to your sourcebans web folder.
2. You need to edit a few files **(make backup before you doing this!!!)** Instructions for editing are placed in `files_to_edit.txt` from zip. Example from this file:
	<pre><code>\includes\page-builder.php
At line 38 --		case "servers":		--
Add BEFORE

	case "commslist":
		RewritePageTitle("Communications Block List");
		$page = TEMPLATES_PATH ."/page.commslist.php";
		break;</code></pre>
This means, that you need to open file `<sourcebans_web_folder>\includes\page-builder.php` from your webserver, find in it `case "servers":` on 38th line (or near from it) and add **before** this line next code:
<pre><code>case "commslist":
		RewritePageTitle("Communications Block List");
		$page = TEMPLATES_PATH ."/page.commslist.php";
		break;</code></pre>

## For plugin developers
**SourceComms** releases several natives to provide compatibility with other plugins and for additional functionality.

### These natives to set client status:
* `native bool:SourceComms_SetClientMute(client, bool:muteState, muteLength, bool:saveToDB, const String:reason[])` - Sets a client's mute state.
* `native bool:SourceComms_SetClientGag(client, bool:gagState, gagLength, bool:saveToDB, const String:reason[])` - Sets a client's gag state.
* Parametrs:
	* `client` - Client index. Client index must be valid (`0 < client < MaxClients`) and client must be in game (`IsClientInGame(client) == true`).
	* *bool* `muteState` | `gagState` - `true` to mute (or gag) client, `false` to unmute (ungag).
	* Next parameters applies only for muting or gagging (`muteState==true` or `gagState==true`).
		* `muteLength` | `gagLength` - length of punishment in minutes. Value `< 0` muting (gagging) client for session (until reconnect). Permanent (`0`) **is not allowed**. Default value is `-1`.
		* *bool* `saveToDB` - if `true` - punishment will be saved in DB (maybe not immediately). Default value is `false`.
		* *String* `reason` - reason of punishment which will displayed and (possibly) saved into DB. Default value is `Muted through natives` or `Gagged through natives`.
* Natives returns `true` if this caused a change in *mute* or *gag* state, `false` otherwise.
* It's recommended to use these natives instead of `BaseComm_SetClientMute` or `BaseComm_SetClientGag`.
* For example, equivalent of `BaseComm_SetClientMute(client, true)` is `SourceComms_SetClientMute(client, true, -1, false)`; also it may be `SourceComms_SetClientMute(client, true, _, _)` or simple `SourceComms_SetClientMute(client, true)`.
* Removing player's punishments from DB through natives **are not available at this moment**.

### Natives to get client status:
* `native bType:SourceComms_GetClientMuteType(client)` - Returns the client's mute type.
* `native bType:SourceComms_GetClientGagType(client)` - Returns the client's gag type.
* Parametrs:
	* `client` - Client index, it must be valid and client must be in game.
* Natives returns one of enum `bType` values, which can be:
	* `bNot` - Player chat or voice is not blocked.
	* `bSess` - Player chat or voice is blocked for player session (until reconnect) (like in *basecomm* plugin).
	* `bTime` - Player chat or voice is blocked for some time.
	* `bPerm` -  Player chat or voice is permanently blocked.

## Special thanks to
* [Twisted|Panda](https://forums.alliedmods.net/member.php?u=41467) for his [ExtendedComm](https://forums.alliedmods.net/showthread.php?p=1383953) plugin, which inspired me and was the basis for my plugin.
* [SourceBans Development Team](http://sourcebans.net/team) for their [SourceBans](https://github.com/GameConnect/SourceBans) plugin.
* [killerps](https://forums.alliedmods.net/member.php?u=145192) for Polish translation.
* [StayOx](https://forums.alliedmods.net/member.php?u=185412) for Portuguese (Brazilian) translation.
* [winter](http://steamcommunity.com/profiles/76561198012507628) for Deutsch translation.
