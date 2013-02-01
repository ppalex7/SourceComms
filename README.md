# SourceComms
A sourcemod plugin, which provides extended, temporary and permanent punishments with full history storing in sourcebans system.
Also includes files and instructions to integration to existing sourcebans web-pages.

## Requirements
* Working sourcebans system *(yes, you need MySQL server and web server with PHP)*
* SourceMod 1.4.1 or newer; SourceMod **1.5.0-hg3761** or **newer** is required if you want to *store history of punishments from another plugins*

##Compatibility:
* In theory - all games on the Source 2009 engine.
* But plugin tested only on TF2 servers.

## Features
### Server plugin
* Provides a straightforward category in the sm_admin menu where administrators can punish players as well as view current comm punishments.
	* The original BaseComm menu option still exist, and will still function.
		* SourceComms plugin has optional support (not by default) storing history of punishments from BaseComm and another plugins if you are having **SM 1.5.0-hg3761** or **newer**
	* The category provides options for issuing new punishments, removing and viewing current punishments (categorized based on the punishment), as well as a List feature that provides information about current punishments.
	* The category also modifies the player's names in all of the options to show what their current punishment is. [ ] = None, [G] = Gagged, [M] = Muted, [S] = Silenced. *I used Twisted|Panda menu code :)*
* All punishments (temporary, extended or permanent) are saved in MySQL database and are automatically reapplied (except temporary) when the punished player connects to the server. This allows punishments to be applied across multiple servers.
	* Extended punishments will automatically expire in-game at the designated time.
	* Permanent punishments remain on the player until an administrator removes them.
	* If the server has problems with access to the database, the punishments will store in SQLite database and would be added in the main database when connection is restored. *(like in sourcebans plugin, yes)*
* SourceComms has support for protecting current punishments based on immunity levels.
	* When a punishment is issued, the administrator responsible has their immunity level attached to the punishment. In order to remove that punishment, the second administrator must have **higher** immunity level or special admin flag (*ADMFLAG_CUSTOM2* by default. You may change it in sourcecode). Also, punishment can be removed by console or his author.
	* Punishments issued by *CONSOLE* has some immunity level (which is set in config, option "ConsoleImmunity").
	* Immunity checking system could be disabled by setting option *"DisableUnblockImmunityCheck"* to value 1 in config file.
	* One more **important** moment. When somebody removes punishment - plugin retrieves *"punishment issuer admin id"* from database. If the request fails - punishment could be temporary removed (on server, not in database) only by console, admin with special flag or with higher immunity.
* Punishments reasons and times stored in config.
* Config has another usefull setting - *"DefaultTime"*. When admin run sm_gag (mute, silence) command only with player name - he will be gagged on "DefaultTime" value minutes. (if *"DefaultTime"* setted in -1 -> player will be blocked only on session (until reconnect)).
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

**Sample of web-part you may look [there](http://z.tf2news.ru/tbans/index.php?p=commslist)** (Login / pass *test* / *test*)

##Commands:
* `sm_mute <player> <optional:time> <optional:reason>` - Removes a player's ability to use in-game voice.
* `sm_gag <player> <optional:time> <optional:reason>` - Removes a player's ability to use in-game chat.
* `sm_silence <player> <optional:time> <optional:reason>` - Removes a player's ability to use in-game voice and chat.
* `sm_unmute <player> <optional:reason>` - Restores a player's ability to use in-game voice.
* `sm_ungag <player> <optional:reason>` - Restores a player's ability to use in-game chat.
* `sm_unsilence <player> <optional:reason>` - Restores a player's ability to use in-game voice and chat.

The **time** parameter controls how long the player is punished. (< 0 == Temporary, 0 == Permanent, # == Minutes). If not specified it will be *"DefaultTime"* minutes (30 by default).

##Cvars:
* `sourcecomms_version` - plugin version

##Installation instructions
First of all, download this repository as a zip file.
###Installation of server part
1. Upload all the contents of `game_upload` directory from the zip file to your gameserver into `/addons/sourcemod` folder.
2. Edit addons/sourcemod/configs/databases.cfg and add an entry for SourceComms. It should have the following general format:

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
3. *(Optional)* If you have **SourceMod 1.5.0-hg3761** or **newer**. Edit `game_upload/scripting/sourcecomms.sp` and uncomment line 13 `//#define BUG_FIXED` (remove `//` in the begin of the line). Then, compile plugin and upload to your server with other files as usual.

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

## Known bugs
### Server plugin
* has no known bugs.

### Web part
* Sometimes blocking/unblocking from web may work not properly. (The *search players on the servers* box "hangs" and doesn't respond.)

## Special thanks to
* [Twisted|Panda](https://forums.alliedmods.net/member.php?u=41467) for his [ExtendedComm](https://forums.alliedmods.net/showthread.php?p=1383953) plugin, which inspired me and was the basis for my plugin.
* [SourceBans Development Team](http://sourcebans.net/team) for their [SourceBans](http://sourcebans.net) plugin.
