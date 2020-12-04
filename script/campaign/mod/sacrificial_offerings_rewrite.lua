sacrificial_offerings_manager = {}

sacrificial_offerings_manager.__tostring = "SACRIFICIAL OFFERINGS MANAGER"
sacrificial_offerings_manager.__index = sacrificial_offerings_manager

sacrificial_offerings_manager.default_settings = {
    max_clamp = 200,    -- highest value for the offerings
    min_clamp = 20,      -- lowest value for the offerings
    result_mod = 1      -- multiplier for the end result
}

function sacrificial_offerings_manager:change_default_setting(setting_key, value)
    if not self.default_settings[setting_key] then
        -- setting doesn't exist, cancel
        return
    end

    self.default_settings[setting_key] = value
end

-- allows this mod to work in MP! triggered through the ComponentLClickUp event below, only needed for player UI interaction
core:add_listener(
    "SacrificialOfferingsUITrigger",
    "UITrigger",
    function(context)
        return context:trigger():starts_with("sacrificialofferings|")
    end,
    function(context)
        -- etc
        local str = context:trigger()
        local data = string.gsub(str, "sacrificialofferings|", "")
        local sep = string.find(data, "+")
        local faction_key = string.sub(data, 1, sep - 1)
        local sacrifice_result = tonumber(string.sub(data, sep + 1))
        cm:faction_add_pooled_resource(faction_key, "lzd_sacrificial_offerings", "wh2_dlc12_resource_factor_sacrifices_battle", sacrifice_result)
    end,
    true
)

function sacrificial_offerings_manager:setup_faction(faction_key, post_battle_option_key, settings)
    -- if no settings are provided, use full default
    if not settings then
        settings = self.default_settings
    else
        -- if settings are provided, check that the specific args needed are there; if not, use default value
        if not settings.max_clamp then
            settings.max_clamp = self.default_settings.max_clamp
        end
        if not settings.min_clamp then
            settings.min_clamp = self.default_settings.min_clamp
        end
        if not settings.result_mod then
            settings.result_mod = self.default_settings.result_mod
        end
    end

    local sacrifice_result = 0 --: number | int

    local function calculate_result_on_pb()
        if cm:pending_battle_cache_num_defenders() >= 1 and cm:pending_battle_cache_num_attackers() >=1 then

            -- player variable is used to define which side the player was on, defense or offense
            local faction --: string

            -- enemy faction key
            local enemy_faction --: string

            for i = 1, cm:pending_battle_cache_num_attackers() do
                local _, _, faction_name = cm:pending_battle_cache_get_attacker(i)

                if faction_name == faction_key then
                    faction = "attacker"
                    break
                end
            end

            for i = 1, cm:pending_battle_cache_num_defenders() do
                local _, _, faction_name = cm:pending_battle_cache_get_defender(i)

                if faction_name == faction_key then
                    faction = "defender"
                    break
                end
            end

            if faction == "defender" then
                local _, _, this_faction = cm:pending_battle_cache_get_attacker(1)
                enemy_faction = this_faction
            elseif faction == "attacker" then
                local _, _, this_faction = cm:pending_battle_cache_get_defender(1)
                enemy_faction = this_faction
            end

            local attacker_won = cm:pending_battle_cache_attacker_victory()
            local attacker_value = cm:pending_battle_cache_attacker_value()

            local defender_won = cm:pending_battle_cache_defender_victory()
            local defender_value = cm:pending_battle_cache_defender_value()

            if not attacker_won and not defender_won then
                -- draw or retreat or flee, do nothing
                return
            end

            if faction == "attacker" then 
                if attacker_won then 
                    sacrifice_result = (defender_value / 100) --* multiplier

                    local kill_ratio = cm:model():pending_battle():percentage_of_defender_killed()

                    sacrifice_result = sacrifice_result * kill_ratio

                    if sacrifice_result >= settings.max_clamp then 
                        sacrifice_result = settings.max_clamp
                    elseif sacrifice_result <= settings.min_clamp then
                        sacrifice_result = settings.min_clamp
                    end
                end

            elseif faction == "defender" then
                if defender_won then
                    sacrifice_result = (attacker_value / 100) --* multiplier
                    local kill_ratio = cm:model():pending_battle():percentage_of_attacker_killed()

                    sacrifice_result = sacrifice_result * kill_ratio

                    if sacrifice_result >= settings.max_clamp then 
                        sacrifice_result = settings.max_clamp
                    elseif sacrifice_result <= settings.min_clamp then
                        sacrifice_result = settings.min_clamp
                    end
                end
            end

            sacrifice_result = math.floor(sacrifice_result)

            sacrifice_result = sacrifice_result * settings.result_mod
        end
    end

    -- listener for player only
    if cm:get_local_faction_name(true) == faction_key then

        -- post battle option UI
        core:add_listener(
            "SacrificialOfferingsPBUI"..faction_key,
            "PanelOpenedCampaign",
            function(context)
                return context.string == "popup_battle_results" and cm:pending_battle_cache_faction_is_involved(faction_key)
            end,
            function(context)
                -- set the Sacrifical Offerings var
                calculate_result_on_pb()

                if sacrifice_result == 0 then
                    -- issue!
                    return
                end

                core:add_listener(
                    "SacrificialOfferingsPlayerUI",
                    "ComponentMouseOn",
                    function(context)
                        return context.string == "enslave"..post_battle_option_key
                    end,
                    function(context)
                        cm:callback(function() 
                            local tt = find_uicomponent(core:get_ui_root(), "tooltip_captive_options")
                            local pr_uic = find_uicomponent(tt, "effects_list", "pooled_resources")

                            pr_uic:SetVisible(true)
                            local sotek_uic = core:get_or_create_component("sotek_uic", "ui/pr_captive_tooltip_template", pr_uic)
                            pr_uic:Adopt(sotek_uic:Address())

                            sotek_uic:SetState('positive')
                            sotek_uic:SetImagePath('UI/skins/warhammer2/sotek_sacrifieces_slaves_icon.png')
                            sotek_uic:SetStateText("Sacrificial Offerings: +"..sacrifice_result)

                            local value = find_uicomponent(sotek_uic, "value")
                            value:SetState('positive')
                            value:SetStateText('')
                        end, 0.1)
                    end,
                    true
                )
            end,
            true
        )

        -- settlement captured option
        core:add_listener(
            "SacrificialOfferingsODUI"..faction_key,
            "PanelOpenedCampaign",
            function(context)
                return context.string == "settlement_captured" and cm:get_local_faction_name(true) == faction_key
            end,
            function(context)
                -- set the Sacrifical Offerings var
                calculate_result_on_pb()

                if sacrifice_result == 0 then
                    -- issue!
                    return
                end

                local root = core:get_ui_root()
                local parent = find_uicomponent(root, "settlement_captured", "button_parent")

                local loot = find_uicomponent(parent, "1096")
                local sack = find_uicomponent(parent, "1118")

                do
                    local icon_parent = find_uicomponent(loot, "frame", "icon_parent")
                    local replen = find_uicomponent(icon_parent, "dy_replenish")
                    local sacrifical_offerings = UIComponent(replen:CopyComponent("lzd_sacrificial_offerings"))
                    local icon = find_uicomponent(sacrifical_offerings, "icon")

                    sacrifical_offerings:SetStateText(tostring(sacrifice_result))
                    sacrifical_offerings:SetTooltipText(effect.get_localised_string("pooled_resources_display_name_lzd_sacrificial_offerings") .. "||" .. effect.get_localised_string("pooled_resources_description_lzd_sacrificial_offerings"), true)

                    icon:SetImagePath("ui/skins/warhammer2/icon_skaven_slaves.png")
                end

                do
                    local icon_parent = find_uicomponent(sack, "frame", "icon_parent")
                    local replen = find_uicomponent(icon_parent, "dy_replenish")
                    local sacrifical_offerings = UIComponent(replen:CopyComponent("lzd_sacrificial_offerings"))
                    local icon = find_uicomponent(sacrifical_offerings, "icon")

                    sacrifical_offerings:SetStateText(tostring(sacrifice_result))
                    sacrifical_offerings:SetTooltipText(effect.get_localised_string("pooled_resources_display_name_lzd_sacrificial_offerings") .. "||" .. effect.get_localised_string("pooled_resources_description_lzd_sacrificial_offerings"), true)

                    icon:SetImagePath("ui/skins/warhammer2/icon_skaven_slaves.png")
                end
            end,
            true
        )
    end

    core:add_listener(
        "SacrificialOfferingsApply"..faction_key,
        "CharacterPostBattleEnslave",
        function(context)
            return context:character():faction():name() == faction_key
        end,
        function(context)
            calculate_result_on_pb()
            if sacrifice_result == 0 then
                -- issue!
                return
            end
            cm:faction_add_pooled_resource(faction_key, "lzd_sacrificial_offerings", "wh2_dlc12_resource_factor_sacrifices_battle", sacrifice_result)
        end,
        true
    )
end

local function init()
    sacrificial_offerings_manager:setup_faction("wh2_dlc12_lzd_cult_of_sotek", "wh2_dlc12_captive_option_enslave_cult_of_sotek")    
end

cm:add_first_tick_callback(function() init() end)