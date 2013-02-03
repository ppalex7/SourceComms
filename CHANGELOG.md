#Changelog
* **0.8.23** - Bots are now removed from menu targets list.
* **0.8.1**
	* Fixed bug with *player's name in the database sometimes was a part of another "sql-query"*
	* Code improvements to avoid similar bugs in the future.
	* Disabled sql-queries log.
* **0.7.122**
	* Fixed bug: punishments were recorded into the database twice.
	* Removed "select from queue" query from logging.
	* Fixed bug with wrong logging comms actions in SM logs.
	* Enabled sql-queries log.
* **0.7.114**
	* Fixed some flaws in the sql queries.
	* Small code improvements.
* **0.7.111** - First release on AlliedMods.
* **0.7.97**
	* Minor bugs fixed.
	* DEBUG info now disabled by default. 
	* Now plugin is "beta".
* **0.7.60**
	* Changed internal data structure.
	* Added to Menu List of Current players punishments (from original ExtendedComms plugin).
	* Added "ConsoleImmunity" and "DisableUnblockImmunityCheck" variables to config.
* **0.6.52**
	* Now plugin will auto-reloads after update.
	* Little changes in translation.
* **0.6.51** - Added temporary punishments.
* **0.6.44** - Added "DefaultTime" variable to config.
* **0.6.42** - In debug mode, text of all sql queries will stored in separate log.
* **0.6.37** - Added console commands that provides unblocking player comms via web.
* **0.6.34** - Added Updater support.
* **0.6.20** - Fixed bug: "after restoring a database connection expired punishments were not added to main database".
* **0.6.19** - Fixed bug with displaying admin activity after restoring a database connection, but not immediately.
* **0.6.14** - Added console commands that provides blocking player comms via web.
* **0.5.30** - First public alpha.