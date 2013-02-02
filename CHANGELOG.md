#Changelog
* **0.7.122**
	* Fixed bug: punishments were recorded into the database twice.
	* Remove "select from queue" query from logging.
	* Fixed bug with wrong logging comms actions in SM logs.
	* Enable sql-queries log.
* **0.7.114**
	* Fixed some flaws in the sql queries.
	* Small code improvements.
* **0.7.111** - First release on AlliedMods.
* **0.7.97**
	* Minor bugs fixed.
	* DEBUG info now disabled by default. 
	* Now plugin is "beta".
* **0.7.60**
	* Change internal data structure.
	* Add to Menu List of Current players punishments (from original ExtendedComms plugin).
	* Adde"ConsoleImmunity" and "DisableUnblockImmunityCheck" variables to config.
* **0.6.52**
	* Now plugin will auto-reloads after update.
	* Little changes in translation.
* **0.6.51** - Added temporary punishments.
* **0.6.44** - Added "DefaultTime" variable to config.
* **0.6.42** - In debug mode, text of all sql queries will stored in separate log.
* **0.6.37** - Add console commands that provides unblocking player comms via web.
* **0.6.34** - Add Updater support.
* **0.6.20** - Fixed bug: "after restoring a database connection expired punishments were not added to main database".
* **0.6.19** - Fixed bug with displaying admin activity after restoring a database connection, but not immediately.
* **0.6.14** - Add console commands that provides blocking player comms via web.
* **0.5.30** - First public alpha.