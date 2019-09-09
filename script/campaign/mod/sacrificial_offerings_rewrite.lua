sacrificial_offerings_manager = {}

sacrificial_offerings_manager.__tostring = "SACRIFICIAL OFFERINGS MANAGER"
sacrificial_offerings_manager.__index = sacrificial_offerings_manager

sacrificial_offerings_manager.settings = {
    max_clamp = 100,    -- highest value for the offerings
    min_clamp = 5,      -- lowest value for the offerings
    result_mod = 1      -- multiplier for the end result
}

function sacrificial_offerings_manager:change_setting(setting_key, value)
    if not self.settings[setting_key] then
        -- setting doesn't exist, cancel
        return
    end

    self.settings[setting_key] = value
end

function sacrificial_offerings_manager:setup_faction(faction_key, post_battle_option_key)
    local settings = self.settings

    -- listener for player only
    if cm:get_local_faction() == faction_key then
        core:add_listener(
            "SacrificialOfferings"..faction_key,
            "PanelOpenedCampaign",
            function(context)
                return context.string == "popup_battle_results" and cm:pending_battle_cache_faction_is_involved(faction_key) and cm:get_faction(faction_key):is_human()
            end,
            function(context)
                -- needed to prevent some weird bugginess
                if cm:pending_battle_cache_num_defenders() >= 1 and cm:pending_battle_cache_num_attackers() >=1 then

                    -- player variable is used to define which side the player was on, defense or offense
                    local player_faction --: string

                    -- enemy faction key
                    local enemy_faction --: string

                    for i = 1, cm:pending_battle_cache_num_attackers() do
                        local _, __, faction_name = cm:pending_battle_cache_get_attacker(i)

                        if faction_name == faction_key then
                            player_faction = "attacker"
                            break
                        end
                    end

                    for i = 1, cm:pending_battle_cache_num_defenders() do
                        local _, __, faction_name = cm:pending_battle_cache_get_defender(i)

                        if faction_name == faction_key then
                            player_faction = "defender"
                            break
                        end
                    end

                    if player_faction == "defender" then
                        local this_char_cqi, this_mf_cqi, this_faction = cm:pending_battle_cache_get_attacker(1)
                        enemy_faction = this_faction
                    elseif player_faction == "attacker" then
                        local this_char_cqi, this_mf_cqi, this_faction = cm:pending_battle_cache_get_defender(1)
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

                    out("POST-BATTLE: Sotek fought as ["..player_faction.."].")
                    out("POST-BATTLE: Enemy faction key ["..enemy_faction.."].")

                    -- divide value of defender and attacker armies, to get a multiplier for NP value, if the player wins
                    -- base the amount of NP lost on how many troops were lost

                    local sacrifice_result = 0 --: number

                    if player_faction == "attacker" then 
                        if attacker_won then 
                            --local multiplier = defender_value / attacker_value 
                            out("POST-BATTLE: Enemy value is "..defender_value)
                            out("POST-BATTLE: Sotek value is "..attacker_value)
                            --multiplier = math.clamp(multiplier, 0.1, 2.5)
                            --out("POST-BATTLE: Multiplier is "..multiplier)

                            sacrifice_result = (defender_value / 100) --* multiplier
                            out("POST-BATTLE: Initial result is "..sacrifice_result)
                            local kill_ratio = cm:model():pending_battle():percentage_of_defender_killed()
                            out("POST-BATTLE: Kill ration is "..kill_ratio)

                            sacrifice_result = sacrifice_result * kill_ratio
                            out("POST-BATTLE: End product is "..sacrifice_result)

                            if sacrifice_result >= settings.max_clamp then 
                                out("POST-BATTLE: Original Sacrifice Result is "..sacrifice_result)
                                sacrifice_result = settings.max_clamp
                            elseif sacrifice_result <= settings.min_clamp then
                                sacrifice_result = settings.min_clamp
                            end
                        end
                    elseif player_faction == "defender" then
                        if defender_won then
                            --local multiplier = attacker_value / defender_value
                            out("POST-BATTLE: Enemy value is "..attacker_value)
                            out("POST-BATTLE: Sotek value is "..defender_value)
                            --multiplier = math.clamp(multiplier, 0.1, 2.5)
                            --out("POST-BATTLE: Multiplier is "..multiplier)

                            sacrifice_result = (attacker_value / 100) --* multiplier
                            local kill_ratio = cm:model():pending_battle():percentage_of_attacker_killed()

                            sacrifice_result = sacrifice_result * kill_ratio

                            if sacrifice_result >= settings.max_clamp then 
                                out("POST-BATTLE: Original Sacrifice Result is "..sacrifice_result)
                                sacrifice_result = settings.max_clamp
                            elseif sacrifice_result <= settings.min_clamp then
                                sacrifice_result = settings.min_clamp
                            end
                        end
                    end

                    sacrifice_result = math.floor(sacrifice_result)

                    sacrifice_result = sacrifice_result * settings.result_mod

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

                    -- add the NP when that button is pressed
                    core:add_listener(
                        "SacrificialOfferingsPlayerApply"..faction_key,
                        "ComponentLClickUp",
                        function(context)
                            return context.string == "enslave"..post_battle_option_key
                        end,
                        function(context)
                            -- add on the PR and log it!
                            cm:faction_add_pooled_resource(faction_key, "lzd_sacrificial_offerings", "wh2_dlc12_resource_factor_sacrifices_battle", sacrifice_result)
                        end,
                        false
                    )

                    -- remove the above listener when the panel closed, to prevent any over-hang
                    core:add_listener(
                        "SacrificialOfferingsPlayerCancel"..faction_key,
                        "PanelClosedCampaign",
                        function(context)
                            return context.string == "popup_battle_results"
                        end,
                        function(context)
                            core:remove_listener("SacrificialOfferingsPlayerApply"..faction_key)
                        end,
                        false
                    )
                end    
            end,
            true
        )
    else
        core:add_listener(
            "SacrificialOfferingsAI"..faction_key,
            "CharacterPostBattleEnslave",
            function(context)
                return context:character():faction():name() == faction_key and not context:character():faction():is_human()
            end,
            function(context)
                if cm:pending_battle_cache_num_defenders() >= 1 and cm:pending_battle_cache_num_attackers() >=1 then

                    -- player variable is used to define which side the player was on, defense or offense
                    local ai_faction --: string

                    -- enemy faction key
                    local enemy_faction --: string

                    for i = 1, cm:pending_battle_cache_num_attackers() do
                        local _, __, faction_name = cm:pending_battle_cache_get_attacker(i)

                        if faction_name == faction_key then
                            ai_faction = "attacker"
                            break
                        end
                    end

                    for i = 1, cm:pending_battle_cache_num_defenders() do
                        local _, __, faction_name = cm:pending_battle_cache_get_defender(i)

                        if faction_name == faction_key then
                            ai_faction = "defender"
                            break
                        end
                    end

                    if ai_faction == "defender" then
                        local this_char_cqi, this_mf_cqi, this_faction = cm:pending_battle_cache_get_attacker(1)
                        enemy_faction = this_faction
                    elseif ai_faction == "attacker" then
                        local this_char_cqi, this_mf_cqi, this_faction = cm:pending_battle_cache_get_defender(1)
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

                    local sacrifice_result = 0 --: number

                    if ai_faction == "attacker" then 
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

                    elseif ai_faction == "defender" then
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

                    cm:faction_add_pooled_resource(faction_key, "lzd_sacrificial_offerings", "wh2_dlc12_resource_factor_sacrifices_battle", sacrifice_result)
                end
            end,
            true
        )
    end
end

local function init()
    sacrificial_offerings_manager:setup_faction("wh2_dlc12_lzd_cult_of_sotek", "wh2_dlc12_captive_option_enslave_cult_of_sotek")    
end

cm:add_first_tick_callback(function() init() end)