/* Magic file that includes all sub-files. It needed for properly syntax highlighting and auto-completions. */

// we should not really include this file
#endinput

#include <sourcemod>
#include <adminmenu>
#include <sourcebans>
#include <sb_admins>
#include <basecomm>

#include "../include/sourcecomms.inc"
#include "../sourcecomms.sp"

#include "config-parser.sp"     // Config parser code
#include "core.sp"              // Core plugin code
#include "common.sp"            // Common code
#include "menu.sp"              // Menu code
#include "natives.sp"           // plugin natives
