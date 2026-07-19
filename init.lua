
local MOD_NAME = minetest.get_current_modname() or "treasure_chest"
local S = function(s) return s end
if minetest.get_translator then S = minetest.get_translator(MOD_NAME) end

treasure_chest = {}

dofile(minetest.get_modpath("treasure_chest") .. "/utils.lua")

minetest.register_privilege("treasurechest_admin", {
    description = S("Can configure and dig up treasure chests placed by other players"),
    give_to_singleplayer = false,
})

local openedTreasureChestConfigs = {};

local metaStrType = "type";
local metaExpectedType = "traesurechest";
local metaStrOwner = "owner";
local metaIntRefresh = "refresh";
local metaInt0p = "0p";
local metaInt1p = "1p";
local metaInt2p = "2p";
local metaInt3p = "3p";
local metaInt4p = "4p";
local metaInt5p = "5p";
local metaIntPeriodMode = "periodMode";
local metaStrInfotext = "infotext";

local fieldRefresh = "refresh_interval";
local fieldPeriodMode = "period_mode";
local fieldI0P = "i0p";
local fieldI1P = "i1p";
local fieldI2P = "i2p";
local fieldI3P = "i3p";
local fieldI4P = "i4p";
local fieldI5P = "i5p";
local fieldInfotext = "infotext_field";
local buttonExit = "exit";
local buttonUpdateSchedule = "update_schedule";
local buttonSimulate = "simulate";

local strDescription = S("A chest that gives semi-randomized rewards per player");
local strOneTime = S("This is a one-time use chest, and you already opened it!");
local strTooSoon = S("To get another reward come back in ");
local strChestHeader = S("Treasure Chest:");
local strYouGot = S(" - You got ");
local strYouGotNothing = S("nothing this time");
local strTimeUntilNext = S("Time until you can get again: ");
local strOneTimeReward = S("this was a one-time reward");
local strAlwaysAvailable = S("always available");
local strFromRefreshLabel = S("Refresh time, in minutes.");
local strExamples = S("E.g.: 60 = 1 hour, 1440 = 1 day")
local strUpdateButton = S("Update");
local strPeriodModeLabel = S("Fixed schedule: everyone shares the same reset boundary\n(refresh time above), instead of a per-player cooldown");
local strGlobalResetLabel = S("Time until global reset: ");
local strProbabiltiesLabel = S("Item probability of being given, integer, range 0..100: 0 = never, 100 = always");
local strInfotextLabel = S("Infotext");
local strSimulateButton = S("Simulate Use");
local strPreviewLabel = S("Preview (what a user would receive):\n");
local strPreviewNone = S("nothing");

-- shared by the player-facing cooldown message and the admin's global reset countdown
local function formatDuration(diffMinutes)
    if diffMinutes <= 1 then
        return S("1 minute")
    elseif diffMinutes < 60 then
        return diffMinutes .. S(" minutes")
    elseif diffMinutes < 1440 then
        return math.floor(diffMinutes/60 + 0.5) .. S(" hours")
    else
        return math.floor(diffMinutes/1440 + 0.5) .. S(" days")
    end
end

-- like formatDuration, but keeps a second, smaller unit instead of rounding it away,
-- e.g. "8 hours 20 minutes" instead of just "8 hours"
local function formatDurationDetailed(diffMinutes)
    if diffMinutes <= 1 then
        return S("1 minute")
    elseif diffMinutes < 60 then
        return diffMinutes .. S(" minutes")
    elseif diffMinutes < 1440 then
        local hours = math.floor(diffMinutes / 60)
        local minutes = diffMinutes % 60
        local text = hours .. (hours == 1 and S(" hour") or S(" hours"))
        if minutes > 0 then
            text = text .. " " .. minutes .. (minutes == 1 and S(" minute") or S(" minutes"))
        end
        return text
    else
        local days = math.floor(diffMinutes / 1440)
        local hours = math.floor((diffMinutes % 1440) / 60)
        local text = days .. (days == 1 and S(" day") or S(" days"))
        if hours > 0 then
            text = text .. " " .. hours .. (hours == 1 and S(" hour") or S(" hours"))
        end
        return text
    end
end

-- gametime is just a seconds counter since world creation, with no link to the real calendar,
-- so fixed-schedule periods are anchored to real-world wall-clock midnight via a fixed offset
-- between gametime and os.time(). get_gametime() returns nil while mods are still loading, so
-- this offset is captured lazily on first use instead of at file-load time.
local worldStartRealTime = nil;
local worldStartGameTime = nil;
local referenceMidnightRealTime = nil;

local function getPreviousMidnight(realTime)
    local t = os.date("*t", realTime);
    return os.time({year = t.year, month = t.month, day = t.day, hour = 0, min = 0, sec = 0});
end

local function ensureTimeAnchor()
    if worldStartGameTime == nil then
        worldStartRealTime = os.time();
        worldStartGameTime = minetest.get_gametime();
        referenceMidnightRealTime = getPreviousMidnight(worldStartRealTime);
    end
end

local function gameTimeToRealTime(gameTime)
    ensureTimeAnchor();
    return worldStartRealTime + (gameTime - worldStartGameTime);
end

-- returns the index of the periodSeconds-sized window (since real-world midnight) that gameTime
-- falls in, plus how many seconds remain until that window ends
local function getPeriodInfo(gameTime, periodSeconds)
    local realTime = gameTimeToRealTime(gameTime);
    local periodIndex = math.floor((realTime - referenceMidnightRealTime) / periodSeconds);
    local secondsUntilNext = (referenceMidnightRealTime + (periodIndex + 1) * periodSeconds) - realTime;
    return periodIndex, secondsUntilNext;
end

local function getGlobalResetCountdownText(refresh, periodMode)
    if not periodMode or refresh <= 0 then
        return "";
    end
    local periodSeconds = refresh * 60;
    local _, secondsUntilNext = getPeriodInfo(minetest.get_gametime(), periodSeconds);
    local remainingMinutes = math.floor(secondsUntilNext / 60 + 0.5);
    return strGlobalResetLabel .. formatDurationDetailed(remainingMinutes);
end

local function getSetupFormspec(spos, refresh, periodMode, i0p, i1p, i2p, i3p, i4p, i5p, infotext, previewText)
    local formspec = "size[8,12.6]" ..

        "field[0.7,0.7;3.4,0.8;"..fieldRefresh..";"..strFromRefreshLabel..";".. refresh .."]"..
        "label[3.9,0.0;"..strExamples.."]"..
        "button[4.2,0.4;1.6,0.8;"..buttonUpdateSchedule..";"..strUpdateButton.."]"..
        "checkbox[0.2,1.35;"..fieldPeriodMode..";"..strPeriodModeLabel..";"..tostring(periodMode).."]"..
        "label[0.2,2.15;"..minetest.formspec_escape(getGlobalResetCountdownText(refresh, periodMode)).."]"..

        "label[0.2,2.6;"..strProbabiltiesLabel.."]"..

        "field[0.5,3.2;1,1;"..fieldI0P..";;"..i0p.."]"..
        "field[1.5,3.2;1,1;"..fieldI1P..";;"..i1p.."]"..
        "field[2.5,3.2;1,1;"..fieldI2P..";;"..i2p.."]"..
        "field[3.5,3.2;1,1;"..fieldI3P..";;"..i3p.."]"..
        "field[4.5,3.2;1,1;"..fieldI4P..";;"..i4p.."]"..
        "field[5.5,3.2;1,1;"..fieldI5P..";;"..i5p.."]"..

        "list[nodemeta:"..spos..";main;0.2,3.8;6.0,1.0;]"..

        "field[0.2,5.3;7.6,0.8;"..fieldInfotext..";"..strInfotextLabel..";"..minetest.formspec_escape(infotext or "").."]"..

        "button[1.0,5.9;3.0,1.0;"..buttonSimulate..";"..strSimulateButton.."]"..
        "button_exit[4.0,5.9;3.0,1.0;"..buttonExit..";Save & Close]"..

        "label[0.2,7.0;"..minetest.formspec_escape(previewText or "").."]"..

        "list[current_player;main;0.0,8.6;8.0,4.0;]";

    return formspec;
end

minetest.register_node("treasure_chest:treasure_chest", {
    description = strDescription,

    tiles = {
        "treasurechest_u.png",
        "treasurechest_d.png",
        "treasurechest_r.png",
        "treasurechest_l.png",
        "treasurechest_b.png",
        "treasurechest_f.png"
    },

    groups = {cracky = 3},
    drop = "",
    paramtype2 = "facedir",
    can_dig = function(pos, player)
        local playerName = player:get_player_name();
        local meta = minetest.get_meta(pos);
        local privs = minetest.get_player_privs(playerName);
        local owner = meta:get_string(metaStrOwner);

        if player:get_player_name() == owner or privs.treasurechest_admin then
            return true;
        else
            return false;
        end
    end,

    after_place_node =
    function(pos, placer, itemstack, pointed_thing)
        local meta = minetest.get_meta(pos);

        meta:set_string(metaStrOwner, placer:get_player_name());
        meta:set_int(metaIntRefresh, 1);
        meta:set_int(metaIntPeriodMode, 0);
        meta:set_string(metaStrType, metaExpectedType);
        meta:set_int(metaInt0p, 100);
        meta:set_int(metaInt1p, 100);
        meta:set_int(metaInt2p, 100);
        meta:set_int(metaInt3p, 100);
        meta:set_int(metaInt4p, 100);
        meta:set_int(metaInt5p, 100);

        local inv = meta:get_inventory();
        inv:set_size("main", 6);
    end,

    on_rightclick =
    function(nodePos, node, player, itemstack, pointed_thing)
        local playerName = player:get_player_name();
        local spos = nodePos.x..","..nodePos.y..","..nodePos.z;
        local gameTime = minetest.get_gametime();
        local privs = minetest.get_player_privs(playerName);

        local meta = minetest.get_meta(nodePos);
        local owner = meta:get_string(metaStrOwner);
        local refresh = meta:get_int(metaIntRefresh);
        local periodMode = meta:get_int(metaIntPeriodMode) == 1;
        local i0p = meta:get_int(metaInt0p);
        local i1p = meta:get_int(metaInt1p);
        local i2p = meta:get_int(metaInt2p);
        local i3p = meta:get_int(metaInt3p);
        local i4p = meta:get_int(metaInt4p);
        local i5p = meta:get_int(metaInt5p);
        local infotext = meta:get_string(metaStrInfotext);

        -- clean up some metadata
        local tmp = meta:to_table()
        local newMetaTable = tmp
        if refresh > 0 then
            for k,v in pairs(tmp["fields"]) do
                if  k ~= metaStrOwner
                and k ~= metaStrType
                and k ~= metaStrInfotext
                and k ~= metaIntRefresh
                and k ~= metaIntPeriodMode
                and k ~= metaInt0p
                and k ~= metaInt1p
                and k ~= metaInt2p
                and k ~= metaInt3p
                and k ~= metaInt4p
                and k ~= metaInt5p then
                    local tv = tonumber(v)
                    if tv then
                        local diff = gameTime - tv
                        if diff > refresh * 60 then
                            newMetaTable["fields"] = treasure_chest.removeKey(newMetaTable["fields"], k)
                        end
                    end
                end
            end
            meta:from_table(newMetaTable)
        end
        -- end clean-up

        if privs.treasurechest_admin or owner == playerName then
            openedTreasureChestConfigs[playerName] = nodePos;
            minetest.show_formspec(playerName, "treasure_chest:setup_inventory",
                getSetupFormspec(spos, refresh, periodMode, i0p, i1p, i2p, i3p, i4p, i5p, infotext, nil));

        else
            local lastTime = meta:get_int(playerName);
            local periodSeconds = refresh * 60;
            local currentPeriod, secondsUntilNextBoundary;
            if periodMode and refresh > 0 then
                currentPeriod, secondsUntilNextBoundary = getPeriodInfo(gameTime, periodSeconds);
            end

            local singleUseUsed = (lastTime ~= 0) and (refresh < 0);
            local notSingleUseButUsed;
            if periodMode then
                local lastPeriod = (refresh > 0) and getPeriodInfo(lastTime, periodSeconds) or nil;
                notSingleUseButUsed = (refresh > 0) and (lastTime ~= 0) and (lastPeriod == currentPeriod);
            else
                local diff = (lastTime and lastTime > 0) and (gameTime - lastTime) or (periodSeconds + 1);
                notSingleUseButUsed = (refresh > 0) and (lastTime ~= 0) and (diff <= periodSeconds);
            end

            if singleUseUsed or notSingleUseButUsed then
                local reason
                if refresh < 0 then
                    reason = strOneTime
                else
                    local diff;
                    if periodMode then
                        diff = secondsUntilNextBoundary
                    else
                        diff = (lastTime + periodSeconds) - gameTime
                    end
                    diff = math.floor(diff / 60 + 0.5)
                    reason = strTooSoon .. formatDuration(diff)
                end

                minetest.chat_send_player(playerName, reason);

            else
                local nodeInv = meta:get_inventory(); --minetest.get_inventory({type="node", pos=nodePos});
                local playerInv = player:get_inventory();
                local given = {};
                -- bit of hard-coding, relying we only have 6 slots. Consider that the formspec is also hardcoded, it's not a huge deal
                for index=0,5,1 do
                    local metaAccessString = index.."p";
                    local probability = meta:get_int(metaAccessString);
                    if (treasure_chest.randomCheck(probability)) then
                        local itemStackToAdd = nodeInv:get_stack("main", index+1);  -- +1 for inventory indexing begins at 1
                        if not itemStackToAdd:is_empty() then
                            table.insert(given, itemStackToAdd:get_short_description().." x"..itemStackToAdd:get_count());
                            local leftover = playerInv:add_item("main", itemStackToAdd);
                            if not leftover:is_empty() then
                                minetest.item_drop(leftover, player, player:get_pos());
                            end
                        end
                    end
                end
                meta:set_int(playerName, gameTime);

                local timeUntilNext;
                if refresh < 0 then
                    timeUntilNext = strOneTimeReward;
                elseif refresh == 0 then
                    timeUntilNext = strAlwaysAvailable;
                else
                    local waitSeconds;
                    if periodMode then
                        local _, secondsUntilNext = getPeriodInfo(gameTime, periodSeconds);
                        waitSeconds = secondsUntilNext;
                    else
                        waitSeconds = periodSeconds;
                    end
                    timeUntilNext = formatDuration(math.floor(waitSeconds / 60 + 0.5));
                end

                local itemsText = (#given > 0) and table.concat(given, ", ") or strYouGotNothing;
                minetest.chat_send_player(playerName,
                    strChestHeader .. "\n" .. strYouGot .. itemsText .. "\n" .. strTimeUntilNext .. timeUntilNext);

                return playerInv:get_stack(player:get_wield_list(), player:get_wield_index());   -- the itemstack we have as input may no longer be valid due to the add_item call above
            end
        end
    end
 })


minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname == "treasure_chest:setup_inventory" then
        local playerName = player:get_player_name()

        if (not fields[fieldRefresh]) then
            -- User cancelled, quit now
            openedTreasureChestConfigs[playerName] = nil
            return true
        end

        local pos = openedTreasureChestConfigs[playerName]
        if pos == nil then
            return
        end

        local meta = minetest.get_meta(pos)

        local owner = meta:get_string(metaStrOwner)
        if not (minetest.check_player_privs(player, "treasurechest_admin") or owner == playerName) then
            openedTreasureChestConfigs[playerName] = nil
            return true
        end

        if meta:get_string(metaStrType) ~= metaExpectedType then
            openedTreasureChestConfigs[playerName] = nil
            return true
        end

        local refresh = treasure_chest.clamp(treasure_chest.toNum(fields[fieldRefresh], meta:get_int(metaIntRefresh)), -1, nil)
        -- checkboxes only appear in `fields` when the player actually toggled them this submit,
        -- so an absent field means "unchanged", not "false" - fall back to the saved value
        local periodMode
        if fields[fieldPeriodMode] ~= nil then
            periodMode = fields[fieldPeriodMode] == "true"
        else
            periodMode = meta:get_int(metaIntPeriodMode) == 1
        end
        local i0p = treasure_chest.clamp(treasure_chest.toNum(fields[fieldI0P], meta:get_int(metaInt0p)), 0, 100)
        local i1p = treasure_chest.clamp(treasure_chest.toNum(fields[fieldI1P], meta:get_int(metaInt1p)), 0, 100)
        local i2p = treasure_chest.clamp(treasure_chest.toNum(fields[fieldI2P], meta:get_int(metaInt2p)), 0, 100)
        local i3p = treasure_chest.clamp(treasure_chest.toNum(fields[fieldI3P], meta:get_int(metaInt3p)), 0, 100)
        local i4p = treasure_chest.clamp(treasure_chest.toNum(fields[fieldI4P], meta:get_int(metaInt4p)), 0, 100)
        local i5p = treasure_chest.clamp(treasure_chest.toNum(fields[fieldI5P], meta:get_int(metaInt5p)), 0, 100)
        local infotext = fields[fieldInfotext] or meta:get_string(metaStrInfotext)

        -- the period-mode checkbox submits immediately on click (unlike text fields, which need
        -- a button press), so treat that the same as the Update button: save and reshow, don't close
        if fields[buttonUpdateSchedule] or fields[fieldPeriodMode] ~= nil then
            meta:set_int(metaIntRefresh, refresh)
            meta:set_int(metaIntPeriodMode, periodMode and 1 or 0)

            local spos = pos.x..","..pos.y..","..pos.z
            minetest.show_formspec(playerName, "treasure_chest:setup_inventory",
                getSetupFormspec(spos, refresh, periodMode, i0p, i1p, i2p, i3p, i4p, i5p, infotext, nil))
            return true
        end

        if fields[buttonSimulate] then
            meta:set_int(metaIntRefresh, refresh)
            meta:set_int(metaIntPeriodMode, periodMode and 1 or 0)
            meta:set_string(metaStrInfotext, infotext)
            meta:set_int(metaInt0p, i0p)
            meta:set_int(metaInt1p, i1p)
            meta:set_int(metaInt2p, i2p)
            meta:set_int(metaInt3p, i3p)
            meta:set_int(metaInt4p, i4p)
            meta:set_int(metaInt5p, i5p)

            local inv = meta:get_inventory()
            local probs = {i0p, i1p, i2p, i3p, i4p, i5p}
            local given = {}
            for index=0,5,1 do
                if treasure_chest.randomCheck(probs[index+1]) then
                    local stack = inv:get_stack("main", index+1)
                    if not stack:is_empty() then
                        table.insert(given, stack:get_short_description().." x"..stack:get_count())
                    end
                end
            end
            local previewText = strPreviewLabel .. (#given > 0 and table.concat(given, ", ") or strPreviewNone)

            local spos = pos.x..","..pos.y..","..pos.z
            minetest.show_formspec(playerName, "treasure_chest:setup_inventory",
                getSetupFormspec(spos, refresh, periodMode, i0p, i1p, i2p, i3p, i4p, i5p, infotext, previewText))
            return true
        end

        openedTreasureChestConfigs[playerName] = nil

        meta:set_int(metaIntRefresh, refresh)
        meta:set_int(metaIntPeriodMode, periodMode and 1 or 0)
        meta:set_string(metaStrInfotext, infotext)
        meta:set_int(metaInt0p, i0p)
        meta:set_int(metaInt1p, i1p)
        meta:set_int(metaInt2p, i2p)
        meta:set_int(metaInt3p, i3p)
        meta:set_int(metaInt4p, i4p)
        meta:set_int(metaInt5p, i5p)
        return true
    end
    return false
end)

minetest.register_on_leaveplayer(function(player)
    local playerName = player:get_player_name()
    openedTreasureChestConfigs[playerName] = nil;
end)
