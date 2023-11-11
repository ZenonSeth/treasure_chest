
local MOD_NAME = minetest.get_current_modname() or "treasure_chest"
local S = function(s) return s end
if minetest.get_translator then S = minetest.get_translator(MOD_NAME) end

treasure_chest = {}

dofile(minetest.get_modpath("treasure_chest") .. "/utils.lua")

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

local fieldRefresh = "refresh_interval";
local fieldI0P = "i0p";
local fieldI1P = "i1p";
local fieldI2P = "i2p";
local fieldI3P = "i3p";
local fieldI4P = "i4p";
local fieldI5P = "i5p";
local buttonExit = "exit";

local strDescription = S("A chest that gives semi-randomized rewards per player");
local strOneTime = S("This is a one-time use chest, and you already opened it!");
local strTooSoon = S("To get another reward come back in ");
local strFromRefreshLabel = S("Refresh time, in minutes, integer. E.g.: 60 = 1 hour, 1440 = 1 day, 10080 = 1 week");
local strProbabiltiesLabel = S("Item probability of being given, integer, range 0..100: 0 = never, 100 = always");

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

        if player:get_player_name() == owner or privs.give then
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
        local i0p = meta:get_int(metaInt0p);
        local i1p = meta:get_int(metaInt1p);
        local i2p = meta:get_int(metaInt2p);
        local i3p = meta:get_int(metaInt3p);
        local i4p = meta:get_int(metaInt4p);
        local i5p = meta:get_int(metaInt5p);

        -- clean up some metadata
        local tmp = meta:to_table()
        local newMetaTable = tmp
        if refresh > 0 then
            for k,v in pairs(tmp["fields"]) do
                if  k ~= metaStrOwner
                and k ~= metaStrType
                and k ~= metaIntRefresh
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

        if privs.server or owner == playerName then
            openedTreasureChestConfigs[playerName] = nodePos;
            minetest.show_formspec(playerName, "treasure_chest:setup_inventory",
                "size[8,8]" ..

                "field[0.2,0.2;7.0,0.9;"..fieldRefresh..";"..strFromRefreshLabel..";".. refresh .."]"..

                "label[0.2,0.6;"..strProbabiltiesLabel.."]"..

                "field[0.5,1.2;1,1;"..fieldI0P..";;"..i0p.."]"..
                "field[1.5,1.2;1,1;"..fieldI1P..";;"..i1p.."]"..
                "field[2.5,1.2;1,1;"..fieldI2P..";;"..i2p.."]"..
                "field[3.5,1.2;1,1;"..fieldI3P..";;"..i3p.."]"..
                "field[4.5,1.2;1,1;"..fieldI4P..";;"..i4p.."]"..
                "field[5.5,1.2;1,1;"..fieldI5P..";;"..i5p.."]"..

                "list[nodemeta:"..spos..";main;0.2,1.8;6.0,1.0;]"..
                "button_exit[1.0,2.8;3.0,1.0;"..buttonExit..";Save & Close]"..

                "list[current_player;main;0.0,4.0;8.0,4.0;]");

        else
            local lastTime = meta:get_int(playerName);
            local diff;
            if lastTime and lastTime > 0 then
                diff = gameTime - lastTime;
            else
                diff = refresh*60 + 1;
            end

            local singleUseUsed = (lastTime ~= 0) and (refresh < 0);
            local notSingleUseButUsed = (refresh > 0) and (lastTime ~= 0) and (diff <= refresh*60);

            if singleUseUsed or notSingleUseButUsed then
                local reason
                if refresh < 0 then
                    reason = strOneTime
                else
                    diff = (lastTime + refresh * 60) - gameTime
                    diff = math.floor(diff / 60 + 0.5)
                    local time = ""
                    if diff <= 1 then
                        time = S("1 minute")
                    elseif diff < 60 then
                        time = diff .. S(" minutes")
                    elseif diff < 1440 then
                        time = math.floor(diff/60 + 0.5) .. S(" hours")
                    else
                        time = math.floor(diff/1440 + 0.5) .. S(" days")
                    end
                    reason = strTooSoon .. time
                end

                minetest.chat_send_player(playerName, reason);

            else
                local nodeInv = meta:get_inventory(); --minetest.get_inventory({type="node", pos=nodePos});
                local playerInv = player:get_inventory();
                local playerWieldedItem = player:get_wielded_item();
                -- bit of hard-coding, relying we only have 6 slots. Consider that the formspec is also hardcoded, it's not a huge deal
                for index=0,5,1 do
                    local metaAccessString = index.."p";
                    local probability = meta:get_int(metaAccessString);
                    print("wield list name = "..player:get_wield_list());
                    if (treasure_chest.randomCheck(probability)) then
                        local itemStackToAdd = nodeInv:get_stack("main", index+1);  -- +1 for inventory indexing begins at 1
                        itemStackToAdd = playerInv:add_item("main", itemStackToAdd);
                        if not itemStackToAdd:is_empty() then
                            minetest.item_drop(itemStackToAdd, player, player:get_pos());
                        end
                    end
                end
                meta:set_int(playerName, gameTime);
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
        openedTreasureChestConfigs[playerName] = nil
        
        local meta = minetest.get_meta(pos)
        
        local owner = meta:get_string(metaStrOwner)
        if not minetest.check_player_privs(player, "server") or owner ~= playerName then
            return true
        end

        if meta:get_string(metaStrType) ~= metaExpectedType then
            return true
        end

        meta:set_int(metaIntRefresh, treasure_chest.clamp(treasure_chest.toNum(fields[fieldRefresh], meta:get_int(metaIntRefresh)), -1, nil) )
        meta:set_int(metaInt0p, treasure_chest.clamp(treasure_chest.toNum(fields[fieldI0P], meta:get_int(metaInt0p)), 0, 100))
        meta:set_int(metaInt1p, treasure_chest.clamp(treasure_chest.toNum(fields[fieldI1P], meta:get_int(metaInt1p)), 0, 100))
        meta:set_int(metaInt2p, treasure_chest.clamp(treasure_chest.toNum(fields[fieldI2P], meta:get_int(metaInt2p)), 0, 100))
        meta:set_int(metaInt3p, treasure_chest.clamp(treasure_chest.toNum(fields[fieldI3P], meta:get_int(metaInt3p)), 0, 100))
        meta:set_int(metaInt4p, treasure_chest.clamp(treasure_chest.toNum(fields[fieldI4P], meta:get_int(metaInt4p)), 0, 100))
        meta:set_int(metaInt5p, treasure_chest.clamp(treasure_chest.toNum(fields[fieldI5P], meta:get_int(metaInt5p)), 0, 100))
        return true
    end
    return false
end)

minetest.register_on_leaveplayer(function(player)
    local playerName = player:get_player_name()
    openedTreasureChestConfigs[playerName] = nil;
end)
