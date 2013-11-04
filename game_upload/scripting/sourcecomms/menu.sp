/* List menu */
enum PeskyPanels
{
    curTarget,
    curIndex,
    viewingMute,
    viewingGag,
    viewingList,
}
new g_iPeskyPanels[MAXPLAYERS + 1][PeskyPanels];


/* stock functions */

stock AdminMenu_Target(client, type)
{
    decl String:Title[192], String:Option[32];
    switch(type)
    {
        case TYPE_GAG:
            Format(Title, sizeof(Title), "%T", "AdminMenu_Select_Gag", client);
        case TYPE_MUTE:
            Format(Title, sizeof(Title), "%T", "AdminMenu_Select_Mute", client);
        case TYPE_SILENCE:
            Format(Title, sizeof(Title), "%T", "AdminMenu_Select_Silence", client);
        case TYPE_UNGAG:
            Format(Title, sizeof(Title), "%T", "AdminMenu_Select_Ungag", client);
        case TYPE_UNMUTE:
            Format(Title, sizeof(Title), "%T", "AdminMenu_Select_Unmute", client);
        case TYPE_UNSILENCE:
            Format(Title, sizeof(Title), "%T", "AdminMenu_Select_Unsilence", client);
    }

    new Handle:hMenu = CreateMenu(MenuHandler_MenuTarget);    // Common menu - players list. Almost full for blocking, and almost empty for unblocking
    SetMenuTitle(hMenu, Title);
    SetMenuExitBackButton(hMenu, true);

    new iClients;
    if (type <= 3)    // Mute, gag, silence
    {
        for (new i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i) && !IsFakeClient(i))
            {
                switch(type)
                {
                    case TYPE_MUTE:
                        if (g_MuteType[i] > bNot)
                            continue;
                    case TYPE_GAG:
                        if (g_GagType[i] > bNot)
                            continue;
                    case TYPE_SILENCE:
                        if (g_MuteType[i] > bNot || g_GagType[i] > bNot)
                            continue;
                }
                iClients++;
                strcopy(Title, sizeof(Title), g_sName[i]);
                AdminMenu_GetPunishPhrase(client, i, Title, sizeof(Title));
                Format(Option, sizeof(Option), "%d %d", GetClientUserId(i), type);
                AddMenuItem(hMenu, Option, Title, (CanUserTarget(client, i) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED));
            }
        }
    }
    else        // UnMute, ungag, unsilence
    {
        for (new i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i) && !IsFakeClient(i))
            {
                switch(type)
                {
                    case TYPE_UNMUTE:
                    {
                        if (g_MuteType[i] > bNot)
                        {
                            iClients++;
                            strcopy(Title, sizeof(Title), g_sName[i]);
                            Format(Option, sizeof(Option), "%d %d", GetClientUserId(i), type);
                            AddMenuItem(hMenu, Option, Title, (CanUserTarget(client, i) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED));
                        }
                    }
                    case TYPE_UNGAG:
                    {
                        if (g_GagType[i] > bNot)
                        {
                            iClients++;
                            strcopy(Title, sizeof(Title), g_sName[i]);
                            Format(Option, sizeof(Option), "%d %d", GetClientUserId(i), type);
                            AddMenuItem(hMenu, Option, Title, (CanUserTarget(client, i) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED));
                        }
                    }
                    case TYPE_UNSILENCE:
                    {
                        if (g_MuteType[i] > bNot && g_GagType[i] > bNot)
                        {
                            iClients++;
                            strcopy(Title, sizeof(Title), g_sName[i]);
                            Format(Option, sizeof(Option), "%d %d", GetClientUserId(i), type);
                            AddMenuItem(hMenu, Option, Title, (CanUserTarget(client, i) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED));
                        }
                    }
                }
            }
        }
    }
    if (!iClients)
    {
        switch(type)
        {
            case TYPE_UNMUTE:
                Format(Title, sizeof(Title), "%T", "AdminMenu_Option_Mute_Empty", client);
            case TYPE_UNGAG:
                Format(Title, sizeof(Title), "%T", "AdminMenu_Option_Gag_Empty", client);
            case TYPE_UNSILENCE:
                Format(Title, sizeof(Title), "%T", "AdminMenu_Option_Silence_Empty", client);
            default:
                Format(Title, sizeof(Title), "%T", "AdminMenu_Option_Empty", client);
        }
        AddMenuItem(hMenu, "0", Title, ITEMDRAW_DISABLED);
    }

    DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

stock AdminMenu_Duration(client, target, type)
{
    new Handle:hMenu = CreateMenu(MenuHandler_MenuDuration);
    decl String:sBuffer[192], String:sTemp[64];
    Format(sBuffer, sizeof(sBuffer), "%T", "AdminMenu_Title_Durations", client);
    SetMenuTitle(hMenu, sBuffer);
    SetMenuExitBackButton(hMenu, true);

    for (new i = 0; i <= iNumTimes; i++)
    {
        if (IsAllowedBlockLength(client, g_iTimeMinutes[i]))
        {
            Format(sTemp, sizeof(sTemp), "%d %d %d", GetClientUserId(target), type, i);    // TargetID TYPE_BLOCK index_of_Time
            AddMenuItem(hMenu, sTemp, g_sTimeDisplays[i]);
        }
    }

    DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

stock AdminMenu_Reason(client, target, type, lengthIndex)
{
    new Handle:hMenu = CreateMenu(MenuHandler_MenuReason);
    decl String:sBuffer[192], String:sTemp[64];
    Format(sBuffer, sizeof(sBuffer), "%T", "AdminMenu_Title_Reasons", client);
    SetMenuTitle(hMenu, sBuffer);
    SetMenuExitBackButton(hMenu, true);

    for (new i = 0; i <= iNumReasons; i++)
    {
        Format(sTemp, sizeof(sTemp), "%d %d %d %d", GetClientUserId(target), type, i, lengthIndex);    // TargetID TYPE_BLOCK ReasonIndex LenghtIndex
        AddMenuItem(hMenu, sTemp, g_sReasonDisplays[i]);
    }

    DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

stock AdminMenu_List(client, index)
{
    decl String:sTitle[192], String:sOption[32];
    Format(sTitle, sizeof(sTitle), "%T", "AdminMenu_Select_List", client);
    new iClients, Handle:hMenu = CreateMenu(MenuHandler_MenuList);
    SetMenuTitle(hMenu, sTitle);
    if (!g_iPeskyPanels[client][viewingList])
        SetMenuExitBackButton(hMenu, true);

    for (new i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i) && (g_MuteType[i] > bNot || g_GagType[i] > bNot))
        {
            iClients++;
            strcopy(sTitle, sizeof(sTitle), g_sName[i]);
            AdminMenu_GetPunishPhrase(client, i, sTitle, sizeof(sTitle));
            Format(sOption, sizeof(sOption), "%d", GetClientUserId(i));
            AddMenuItem(hMenu, sOption, sTitle);
        }
    }

    if (!iClients)
    {
        Format(sTitle, sizeof(sTitle), "%T", "ListMenu_Option_Empty", client);
        AddMenuItem(hMenu, "0", sTitle, ITEMDRAW_DISABLED);
    }

    DisplayMenuAtItem(hMenu, client, index, MENU_TIME_FOREVER);
}

stock AdminMenu_ListTarget(client, target, index, viewMute = 0, viewGag = 0)
{
    new userid = GetClientUserId(target), Handle:hMenu = CreateMenu(MenuHandler_MenuListTarget);
    decl String:sBuffer[192], String:sOption[32];
    SetMenuTitle(hMenu, g_sName[target]);
    SetMenuPagination(hMenu, MENU_NO_PAGINATION);
    SetMenuExitButton(hMenu, true);
    SetMenuExitBackButton(hMenu, false);

    if (g_MuteType[target] > bNot)
    {
        Format(sBuffer, sizeof(sBuffer), "%T", "ListMenu_Option_Mute", client);
        Format(sOption, sizeof(sOption), "0 %d %d %b %b", userid, index, viewMute, viewGag);
        AddMenuItem(hMenu, sOption, sBuffer);

        if (viewMute)
        {
            Format(sBuffer, sizeof(sBuffer), "%T", "ListMenu_Option_Admin", client, g_sMuteAdminName[target]);
            AddMenuItem(hMenu, "", sBuffer, ITEMDRAW_DISABLED);

            decl String:sMuteTemp[192], String:_sMuteTime[192];
            Format(sMuteTemp, sizeof(sMuteTemp), "%T", "ListMenu_Option_Duration", client);
            if (g_MuteType[target] == bPerm)
                Format(sBuffer, sizeof(sBuffer), "%s%T", sMuteTemp, "ListMenu_Option_Duration_Perm", client);
            else if (g_MuteType[target] == bTime)
                Format(sBuffer, sizeof(sBuffer), "%s%T", sMuteTemp, "ListMenu_Option_Duration_Time", client, g_iMuteLength[target]);
            else if (g_MuteType[target] == bSess)
                Format(sBuffer, sizeof(sBuffer), "%s%T", sMuteTemp, "ListMenu_Option_Duration_Temp", client);
            else
                Format(sBuffer, sizeof(sBuffer), "error");
            AddMenuItem(hMenu, "", sBuffer, ITEMDRAW_DISABLED);

            FormatTime(_sMuteTime, sizeof(_sMuteTime), NULL_STRING, g_iMuteTime[target]);
            Format(sBuffer, sizeof(sBuffer), "%T", "ListMenu_Option_Issue", client, _sMuteTime);
            AddMenuItem(hMenu, "", sBuffer, ITEMDRAW_DISABLED);

            Format(sMuteTemp, sizeof(sMuteTemp), "%T", "ListMenu_Option_Expire", client);
            if (g_MuteType[target] == bPerm)
                Format(sBuffer, sizeof(sBuffer), "%s%T", sMuteTemp, "ListMenu_Option_Expire_Perm", client);
            else if (g_MuteType[target] == bTime)
            {
                FormatTime(_sMuteTime, sizeof(_sMuteTime), NULL_STRING, (g_iMuteTime[target] + g_iMuteLength[target] * 60));
                Format(sBuffer, sizeof(sBuffer), "%s%T", sMuteTemp, "ListMenu_Option_Expire_Time", client, _sMuteTime);
            }
            else if (g_MuteType[target] == bSess)
                Format(sBuffer, sizeof(sBuffer), "%s%T", sMuteTemp, "ListMenu_Option_Expire_Temp_Reconnect", client);
            else
                Format(sBuffer, sizeof(sBuffer), "error");
            AddMenuItem(hMenu, "", sBuffer, ITEMDRAW_DISABLED);

            if (strlen(g_sMuteReason[target]) > 0)
            {
                Format(sBuffer, sizeof(sBuffer), "%T", "ListMenu_Option_Reason", client);
                Format(sOption, sizeof(sOption), "1 %d %d %b %b", userid, index, viewMute, viewGag);
                AddMenuItem(hMenu, sOption, sBuffer);
            }
            else
            {
                Format(sBuffer, sizeof(sBuffer), "%T", "ListMenu_Option_Reason_None", client);
                AddMenuItem(hMenu, "", sBuffer, ITEMDRAW_DISABLED);
            }
        }
    }

    if (g_GagType[target] > bNot)
    {
        Format(sBuffer, sizeof(sBuffer), "%T", "ListMenu_Option_Gag", client);
        Format(sOption, sizeof(sOption), "2 %d %d %b %b", userid, index, viewMute, viewGag);
        AddMenuItem(hMenu, sOption, sBuffer);

        if (viewGag)
        {
            Format(sBuffer, sizeof(sBuffer), "%T", "ListMenu_Option_Admin", client, g_sGagAdminName[target]);
            AddMenuItem(hMenu, "", sBuffer, ITEMDRAW_DISABLED);

            decl String:sGagTemp[192], String:_sGagTime[192];
            Format(sGagTemp, sizeof(sGagTemp), "%T", "ListMenu_Option_Duration", client);
            if (g_GagType[target] == bPerm)
                Format(sBuffer, sizeof(sBuffer), "%s%T", sGagTemp, "ListMenu_Option_Duration_Perm", client);
            else if (g_GagType[target] == bTime)
                Format(sBuffer, sizeof(sBuffer), "%s%T", sGagTemp, "ListMenu_Option_Duration_Time", client, g_iGagLength[target]);
            else if (g_GagType[target] == bSess)
                Format(sBuffer, sizeof(sBuffer), "%s%T", sGagTemp, "ListMenu_Option_Duration_Temp", client);
            else
                Format(sBuffer, sizeof(sBuffer), "error");
            AddMenuItem(hMenu, "", sBuffer, ITEMDRAW_DISABLED);

            FormatTime(_sGagTime, sizeof(_sGagTime), NULL_STRING, g_iGagTime[target]);
            Format(sBuffer, sizeof(sBuffer), "%T", "ListMenu_Option_Issue", client, _sGagTime);
            AddMenuItem(hMenu, "", sBuffer, ITEMDRAW_DISABLED);

            Format(sGagTemp, sizeof(sGagTemp), "%T", "ListMenu_Option_Expire", client);
            if (g_GagType[target] == bPerm)
                Format(sBuffer, sizeof(sBuffer), "%s%T", sGagTemp, "ListMenu_Option_Expire_Perm", client);
            else if (g_GagType[target] == bTime)
            {
                FormatTime(_sGagTime, sizeof(_sGagTime), NULL_STRING, (g_iGagTime[target] + g_iGagLength[target] * 60));
                Format(sBuffer, sizeof(sBuffer), "%s%T", sGagTemp, "ListMenu_Option_Expire_Time", client, _sGagTime);
            }
            else if (g_GagType[target] == bSess)
                Format(sBuffer, sizeof(sBuffer), "%s%T", sGagTemp, "ListMenu_Option_Expire_Temp_Reconnect", client);
            else
                Format(sBuffer, sizeof(sBuffer), "error");
            AddMenuItem(hMenu, "", sBuffer, ITEMDRAW_DISABLED);

            if (strlen(g_sGagReason[target]) > 0)
            {
                Format(sBuffer, sizeof(sBuffer), "%T", "ListMenu_Option_Reason", client);
                Format(sOption, sizeof(sOption), "3 %d %d %b %b", userid, index, viewMute, viewGag);
                AddMenuItem(hMenu, sOption, sBuffer);
            }
            else
            {
                Format(sBuffer, sizeof(sBuffer), "%T", "ListMenu_Option_Reason_None", client);
                AddMenuItem(hMenu, "", sBuffer, ITEMDRAW_DISABLED);
            }
        }
    }

    g_iPeskyPanels[client][curIndex] = index;
    g_iPeskyPanels[client][curTarget] = target;
    g_iPeskyPanels[client][viewingGag] = viewGag;
    g_iPeskyPanels[client][viewingMute] = viewMute;
    DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
}

stock AdminMenu_ListTargetReason(client, target, showMute, showGag)
{
    decl String:sTemp[192], String:sBuffer[192];
    new Handle:hPanel = CreatePanel();
    SetPanelTitle(hPanel, g_sName[target]);
    DrawPanelItem(hPanel, " ", ITEMDRAW_SPACER|ITEMDRAW_RAWLINE);

    if (showMute)
    {
        Format(sTemp, sizeof(sTemp), "%T", "ReasonPanel_Punishment_Mute", client);
        if (g_MuteType[target] == bPerm)
            Format(sBuffer, sizeof(sBuffer), "%s%T", sTemp, "ReasonPanel_Perm", client);
        else if (g_MuteType[target] == bTime)
            Format(sBuffer, sizeof(sBuffer), "%s%T", sTemp, "ReasonPanel_Time", client, g_iMuteLength[target]);
        else if (g_MuteType[target] == bSess)
            Format(sBuffer, sizeof(sBuffer), "%s%T", sTemp, "ReasonPanel_Temp", client);
        else
            Format(sBuffer, sizeof(sBuffer), "error");
        DrawPanelText(hPanel, sBuffer);

        Format(sBuffer, sizeof(sBuffer), "%T", "ReasonPanel_Reason", client, g_sMuteReason[target]);
        DrawPanelText(hPanel, sBuffer);
    }
    else if (showGag)
    {
        Format(sTemp, sizeof(sTemp), "%T", "ReasonPanel_Punishment_Gag", client);
        if (g_GagType[target] == bPerm)
            Format(sBuffer, sizeof(sBuffer), "%s%T", sTemp, "ReasonPanel_Perm", client);
        else if (g_GagType[target] == bTime)
            Format(sBuffer, sizeof(sBuffer), "%s%T", sTemp, "ReasonPanel_Time", client, g_iGagLength[target]);
        else if (g_GagType[target] == bSess)
            Format(sBuffer, sizeof(sBuffer), "%s%T", sTemp, "ReasonPanel_Temp", client);
        else
            Format(sBuffer, sizeof(sBuffer), "error");
        DrawPanelText(hPanel, sBuffer);

        Format(sBuffer, sizeof(sBuffer), "%T", "ReasonPanel_Reason", client, g_sGagReason[target]);
        DrawPanelText(hPanel, sBuffer);
    }

    DrawPanelItem(hPanel, " ", ITEMDRAW_SPACER|ITEMDRAW_RAWLINE);
    SetPanelCurrentKey(hPanel, 10);
    Format(sBuffer, sizeof(sBuffer), "%T", "ReasonPanel_Back", client);
    DrawPanelItem(hPanel, sBuffer);
    SendPanelToClient(hPanel, client, PanelHandler_ListTargetReason, MENU_TIME_FOREVER);
    CloseHandle(hPanel);
}


/* public functions */

public Handle_Commands(Handle:menu, TopMenuAction:action, TopMenuObject:object_id, param1, String:buffer[], maxlength)
{
    switch(action)
    {
        case TopMenuAction_DisplayOption:
            Format(buffer, maxlength, "%T", "AdminMenu_Main", param1);
        case TopMenuAction_DisplayTitle:
            Format(buffer, maxlength, "%T", "AdminMenu_Select_Main", param1);
    }
}

public Handle_MenuGag(Handle:menu, TopMenuAction:action, TopMenuObject:object_id, param1, String:buffer[], maxlength)
{
    if (action == TopMenuAction_DisplayOption)
        Format(buffer, maxlength, "%T", "AdminMenu_Gag", param1);
    else if (action == TopMenuAction_SelectOption)
        AdminMenu_Target(param1, TYPE_GAG);
}

public Handle_MenuUnGag(Handle:menu, TopMenuAction:action, TopMenuObject:object_id, param1, String:buffer[], maxlength)
{
    if (action == TopMenuAction_DisplayOption)
        Format(buffer, maxlength, "%T", "AdminMenu_UnGag", param1);
    else if (action == TopMenuAction_SelectOption)
        AdminMenu_Target(param1, TYPE_UNGAG);
}

public Handle_MenuMute(Handle:menu, TopMenuAction:action, TopMenuObject:object_id, param1, String:buffer[], maxlength)
{
    if (action == TopMenuAction_DisplayOption)
        Format(buffer, maxlength, "%T", "AdminMenu_Mute", param1);
    else if (action == TopMenuAction_SelectOption)
        AdminMenu_Target(param1, TYPE_MUTE);
}

public Handle_MenuUnMute(Handle:menu, TopMenuAction:action, TopMenuObject:object_id, param1, String:buffer[], maxlength)
{
    if (action == TopMenuAction_DisplayOption)
        Format(buffer, maxlength, "%T", "AdminMenu_UnMute", param1);
    else if (action == TopMenuAction_SelectOption)
        AdminMenu_Target(param1, TYPE_UNMUTE);
}

public Handle_MenuSilence(Handle:menu, TopMenuAction:action, TopMenuObject:object_id, param1, String:buffer[], maxlength)
{
    if (action == TopMenuAction_DisplayOption)
        Format(buffer, maxlength, "%T", "AdminMenu_Silence", param1);
    else if (action == TopMenuAction_SelectOption)
        AdminMenu_Target(param1, TYPE_SILENCE);
}

public Handle_MenuUnSilence(Handle:menu, TopMenuAction:action, TopMenuObject:object_id, param1, String:buffer[], maxlength)
{
    if (action == TopMenuAction_DisplayOption)
        Format(buffer, maxlength, "%T", "AdminMenu_UnSilence", param1);
    else if (action == TopMenuAction_SelectOption)
        AdminMenu_Target(param1, TYPE_UNSILENCE);
}

public Handle_MenuList(Handle:menu, TopMenuAction:action, TopMenuObject:object_id, param1, String:buffer[], maxlength)
{
    if (action == TopMenuAction_DisplayOption)
        Format(buffer, maxlength, "%T", "AdminMenu_List", param1);
    else if (action == TopMenuAction_SelectOption)
    {
        g_iPeskyPanels[param1][viewingList] = false;
        AdminMenu_List(param1, 0);
    }
}

public MenuHandler_MenuTarget(Handle:menu, MenuAction:action, param1, param2)
{
    switch(action)
    {
        case MenuAction_End:
            CloseHandle(menu);
        case MenuAction_Cancel:
        {
            if (param2 == MenuCancel_ExitBack && hTopMenu != INVALID_HANDLE)
                DisplayTopMenu(hTopMenu, param1, TopMenuPosition_LastCategory);
        }
        case MenuAction_Select:
        {
            decl String:Option[32], String:Temp[2][8];
            GetMenuItem(menu, param2, Option, sizeof(Option));
            ExplodeString(Option, " ", Temp, 2, 8);
            new target = GetClientOfUserId(StringToInt(Temp[0]));

            if (Bool_ValidMenuTarget(param1, target))
            {
                new type = StringToInt(Temp[1]);
                if (type <= TYPE_SILENCE)
                    AdminMenu_Duration(param1, target, type);
                else
                    ProcessUnBlock(param1, target, type);
            }
        }
    }
}

public MenuHandler_MenuDuration(Handle:menu, MenuAction:action, param1, param2)
{
    switch(action)
    {
        case MenuAction_End:
            CloseHandle(menu);
        case MenuAction_Cancel:
        {
            if (param2 == MenuCancel_ExitBack && hTopMenu != INVALID_HANDLE)
                DisplayTopMenu(hTopMenu, param1, TopMenuPosition_LastCategory);
        }
        case MenuAction_Select:
        {
            decl String:sOption[32], String:sTemp[3][8];
            GetMenuItem(menu, param2, sOption, sizeof(sOption));
            ExplodeString(sOption, " ", sTemp, 3, 8);
            // TargetID TYPE_BLOCK index_of_Time
            new target = GetClientOfUserId(StringToInt(sTemp[0]));

            if (Bool_ValidMenuTarget(param1, target))
            {
                new type = StringToInt(sTemp[1]);
                new lengthIndex = StringToInt(sTemp[2]);

                if (iNumReasons) // we have reasons to show
                    AdminMenu_Reason(param1, target, type, lengthIndex);
                else
                    CreateBlock(param1, target, g_iTimeMinutes[lengthIndex], type);
            }
        }
    }
}

public MenuHandler_MenuReason(Handle:menu, MenuAction:action, param1, param2)
{
    switch(action)
    {
        case MenuAction_End:
            CloseHandle(menu);
        case MenuAction_Cancel:
        {
            if (param2 == MenuCancel_ExitBack && hTopMenu != INVALID_HANDLE)
                DisplayTopMenu(hTopMenu, param1, TopMenuPosition_LastCategory);
        }
        case MenuAction_Select:
        {
            decl String:sOption[64], String:sTemp[4][8];
            GetMenuItem(menu, param2, sOption, sizeof(sOption));
            ExplodeString(sOption, " ", sTemp, 4, 8);
            // TargetID TYPE_BLOCK ReasonIndex LenghtIndex
            new target = GetClientOfUserId(StringToInt(sTemp[0]));

            if (Bool_ValidMenuTarget(param1, target))
            {
                new type = StringToInt(sTemp[1]);
                new reasonIndex = StringToInt(sTemp[2]);
                new lengthIndex = StringToInt(sTemp[3]);
                new length;
                if (lengthIndex >= 0 && lengthIndex <= iNumTimes)
                    length = g_iTimeMinutes[lengthIndex];
                else
                {
                    length = DefaultTime;
                    LogError("Wrong length index in menu - using default time");
                }

                CreateBlock(param1, target, length, type, g_sReasonKey[reasonIndex]);
            }
        }
    }
}

public MenuHandler_MenuList(Handle:menu, MenuAction:action, param1, param2)
{
    switch(action)
    {
        case MenuAction_End:
            CloseHandle(menu);
        case MenuAction_Cancel:
        {
            if (!g_iPeskyPanels[param1][viewingList])
                if (param2 == MenuCancel_ExitBack && hTopMenu != INVALID_HANDLE)
                    DisplayTopMenu(hTopMenu, param1, TopMenuPosition_LastCategory);
        }
        case MenuAction_Select:
        {
            decl String:sOption[32];
            GetMenuItem(menu, param2, sOption, sizeof(sOption));
            new target = GetClientOfUserId(StringToInt(sOption));

            if (Bool_ValidMenuTarget(param1, target))
                AdminMenu_ListTarget(param1, target, GetMenuSelectionPosition());
            else
                AdminMenu_List(param1, GetMenuSelectionPosition());
        }
    }
}

public MenuHandler_MenuListTarget(Handle:menu, MenuAction:action, param1, param2)
{
    switch(action)
    {
        case MenuAction_End:
            CloseHandle(menu);
        case MenuAction_Cancel:
        {
            if (param2 == MenuCancel_ExitBack)
                AdminMenu_List(param1, g_iPeskyPanels[param1][curIndex]);
        }
        case MenuAction_Select:
        {
            decl String:sOption[64], String:sTemp[5][8];
            GetMenuItem(menu, param2, sOption, sizeof(sOption));
            ExplodeString(sOption, " ", sTemp, 5, 8);

            new target = GetClientOfUserId(StringToInt(sTemp[1]));
            if (param1 == target || Bool_ValidMenuTarget(param1, target))
            {
                switch(StringToInt(sTemp[0]))
                {
                    case 0:
                        AdminMenu_ListTarget(param1, target, StringToInt(sTemp[2]), !(StringToInt(sTemp[3])), 0);
                    case 1, 3:
                        AdminMenu_ListTargetReason(param1, target, g_iPeskyPanels[param1][viewingMute], g_iPeskyPanels[param1][viewingGag]);
                    case 2:
                        AdminMenu_ListTarget(param1, target, StringToInt(sTemp[2]), 0, !(StringToInt(sTemp[4])));
                }
            }
            else
                AdminMenu_List(param1, StringToInt(sTemp[2]));

        }
    }
}

public PanelHandler_ListTargetReason(Handle:menu, MenuAction:action, param1, param2)
{
    switch(action)
    {
        case MenuAction_Select:
        {
            AdminMenu_ListTarget(param1, g_iPeskyPanels[param1][curTarget], g_iPeskyPanels[param1][curIndex], g_iPeskyPanels[param1][viewingMute], g_iPeskyPanels[param1][viewingGag]);
        }
    }
}
