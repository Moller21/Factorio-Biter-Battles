-- modules
require 'maps.mountain_fortress_v3.generate'
require 'maps.mountain_fortress_v3.player_list'
require 'maps.mountain_fortress_v3.commands'
require 'maps.mountain_fortress_v3.flamethrower_nerf'

require 'modules.dynamic_landfill'
require 'modules.shotgun_buff'
require 'modules.rocks_heal_over_time'
require 'modules.no_deconstruction_of_neutral_entities'
require 'modules.rocks_yield_ore_veins'
require 'modules.spawners_contain_biters'
require 'modules.biters_yield_coins'
require 'modules.wave_defense.main'
require 'modules.pistol_buffs'
require 'modules.mineable_wreckage_yields_scrap'

local CS = require 'maps.mountain_fortress_v3.surface'
local Server = require 'utils.server'
local Explosives = require 'modules.explosives'
local Entities = require 'maps.mountain_fortress_v3.entities'
local update_gui = require 'maps.mountain_fortress_v3.gui'
local ICW = require 'maps.mountain_fortress_v3.icw.main'
local WD = require 'modules.wave_defense.table'
local Map = require 'modules.map_info'
local RPG = require 'maps.mountain_fortress_v3.rpg'
local Terrain = require 'maps.mountain_fortress_v3.terrain'
local Event = require 'utils.event'
local WPT = require 'maps.mountain_fortress_v3.table'
local Locomotive = require 'maps.mountain_fortress_v3.locomotive'.locomotive_spawn
local render_train_hp = require 'maps.mountain_fortress_v3.locomotive'.render_train_hp
local Score = require 'comfy_panel.score'
local Poll = require 'comfy_panel.poll'
local Collapse = require 'modules.collapse'
local Difficulty = require 'modules.difficulty_vote'
local Task = require 'utils.task'

local Public = {}

local starting_items = {['pistol'] = 1, ['firearm-magazine'] = 16, ['rail'] = 16, ['wood'] = 16, ['explosives'] = 32}

local function disable_tech()
    game.forces.player.technologies['landfill'].enabled = false
    game.forces.player.technologies['optics'].researched = true
    game.forces.player.technologies['railway'].researched = true
    game.forces.player.technologies['land-mine'].enabled = false
end

local function set_difficulty()
    local Diff = Difficulty.get()
    local wave_defense_table = WD.get_table()
    local player_count = #game.connected_players
    if not Diff.difficulty_vote_value then
        Diff.difficulty_vote_value = 0.1
    end

    wave_defense_table.max_active_biters = 768 + player_count * (90 * Diff.difficulty_vote_value)

    -- threat gain / wave
    wave_defense_table.threat_gain_multiplier = 1.2 + player_count * Diff.difficulty_vote_value * 0.1

    local amount = player_count * 0.25 + 2
    amount = math.floor(amount)
    if amount > 6 then
        amount = 6
    end
    Collapse.set_amount(amount)

    wave_defense_table.wave_interval = 3600 - player_count * 60
    if wave_defense_table.wave_interval < 1800 then
        wave_defense_table.wave_interval = 1800
    end
end

local function render_direction(surface)
    local counter = WPT.get('soft_reset_counter')
    if counter then
        rendering.draw_text {
            text = 'Welcome to Mountain Fortress v3!\nRun: ' .. counter,
            surface = surface,
            target = {-0, 10},
            color = {r = 0.98, g = 0.66, b = 0.22},
            scale = 3,
            font = 'heading-1',
            alignment = 'center',
            scale_with_zoom = false
        }
    else
        rendering.draw_text {
            text = 'Welcome to Mountain Fortress v3!',
            surface = surface,
            target = {-0, 10},
            color = {r = 0.98, g = 0.66, b = 0.22},
            scale = 3,
            font = 'heading-1',
            alignment = 'center',
            scale_with_zoom = false
        }
    end

    rendering.draw_text {
        text = '▼',
        surface = surface,
        target = {-0, 20},
        color = {r = 0.98, g = 0.66, b = 0.22},
        scale = 3,
        font = 'heading-1',
        alignment = 'center',
        scale_with_zoom = false
    }

    rendering.draw_text {
        text = '▼',
        surface = surface,
        target = {-0, 30},
        color = {r = 0.98, g = 0.66, b = 0.22},
        scale = 3,
        font = 'heading-1',
        alignment = 'center',
        scale_with_zoom = false
    }
    rendering.draw_text {
        text = '▼',
        surface = surface,
        target = {-0, 40},
        color = {r = 0.98, g = 0.66, b = 0.22},
        scale = 3,
        font = 'heading-1',
        alignment = 'center',
        scale_with_zoom = false
    }
    rendering.draw_text {
        text = '▼',
        surface = surface,
        target = {-0, 50},
        color = {r = 0.98, g = 0.66, b = 0.22},
        scale = 3,
        font = 'heading-1',
        alignment = 'center',
        scale_with_zoom = false
    }
    rendering.draw_text {
        text = '▼',
        surface = surface,
        target = {-0, 60},
        color = {r = 0.98, g = 0.66, b = 0.22},
        scale = 3,
        font = 'heading-1',
        alignment = 'center',
        scale_with_zoom = false
    }
    rendering.draw_text {
        text = 'Biters will attack this area.',
        surface = surface,
        target = {-0, 70},
        color = {r = 0.98, g = 0.66, b = 0.22},
        scale = 3,
        font = 'heading-1',
        alignment = 'center',
        scale_with_zoom = false
    }

    local x_min = -Terrain.level_width / 2
    local x_max = Terrain.level_width / 2

    surface.create_entity({name = 'electric-beam', position = {x_min, 74}, source = {x_min, 74}, target = {x_max, 74}})
    surface.create_entity({name = 'electric-beam', position = {x_min, 74}, source = {x_min, 74}, target = {x_max, 74}})
end

function Public.reset_map()
    local Settings = CS.get()
    local Diff = Difficulty.get()
    local this = WPT.get()
    local wave_defense_table = WD.get_table()
    local get_score = Score.get_table()

    for _, player in pairs(game.players) do
        if player.controller_type == defines.controllers.editor then
            player.toggle_map_editor()
        end
    end

    if not this.active_surface_index then
        this.active_surface_index = Settings.active_surface_index
    else
        this.active_surface_index = CS.create_surface()
    end

    Poll.reset()
    ICW.reset()
    game.reset_time_played()
    WPT.reset_table()

    disable_tech()

    local surface = game.surfaces[this.active_surface_index]
    surface.min_brightness = 0.5

    Explosives.set_surface_whitelist({[surface.name] = true})

    game.forces.player.set_spawn_position({-27, 25}, surface)
    game.forces.enemy.set_ammo_damage_modifier('bullet', 1)
    game.forces.enemy.set_turret_attack_modifier('gun-turret', 1)

    global.bad_fire_history = {}
    global.friendly_fire_history = {}
    global.landfill_history = {}
    global.mining_history = {}
    get_score.score_table = {}
    Diff.difficulty_poll_closing_timeout = game.tick + 90000
    Diff.difficulty_player_votes = {}

    Collapse.set_kill_entities(false)
    Collapse.set_speed(8)
    Collapse.set_amount(1)
    Collapse.set_max_line_size(Terrain.level_width)
    Collapse.set_surface(surface)
    Collapse.set_position({0, 162})
    Collapse.set_direction('north')
    Collapse.start_now(false)

    this.locomotive_health = 10000
    this.locomotive_max_health = 10000
    this.cargo_health = 10000
    this.cargo_max_health = 10000

    Locomotive(surface, {x = -18, y = 25})
    render_train_hp()
    render_direction(surface)
    RPG.rpg_reset_all_players()

    WD.reset_wave_defense()
    wave_defense_table.surface_index = this.active_surface_index
    wave_defense_table.target = this.locomotive_cargo
    wave_defense_table.nest_building_density = 32
    wave_defense_table.game_lost = false
    wave_defense_table.spawn_position = {x = 0, y = 100}

    set_difficulty()

    Task.start_queue()
    Task.set_queue_speed(2)

    this.chunk_load_tick = game.tick + 500
end

local function on_player_changed_position(event)
    local this = WPT.get()
    local player = game.players[event.player_index]
    local map_name = 'mountain_fortress_v3'

    if string.sub(player.surface.name, 0, #map_name) ~= map_name then
        return
    end

    local position = player.position
    local surface = game.surfaces[this.active_surface_index]

    if position.y >= 74 then
        player.teleport({position.x, position.y - 1}, surface)
        player.print('Forcefield does not approve.', {r = 0.98, g = 0.66, b = 0.22})
        if player.character then
            player.character.health = player.character.health - 5
            player.character.surface.create_entity({name = 'water-splash', position = position})
            if player.character.health <= 0 then
                player.character.die('enemy')
            end
        end
    end
end

local function on_player_joined_game(event)
    local this = WPT.get()
    local player = game.players[event.player_index]
    local surface = game.surfaces[this.active_surface_index]

    if not surface.is_chunk_generated({-20, 22}) then
        surface.request_to_generate_chunks({-20, 22}, 1)
    end

    set_difficulty(event)

    if not this.players then
        this.players = {}
    end

    if not this.players[player.index] then
        this.players[player.index] = {
            first_join = false,
            data = {}
        }
    end

    if not this.players[player.index].first_join then
        local loco_surface = game.surfaces[this.loco_surface.name]

        if player.surface.index ~= loco_surface.index then
            if not player.character then
                player.create_character()
            end
            player.teleport(
                loco_surface.find_non_colliding_position(
                    'character',
                    game.forces.player.get_spawn_position(loco_surface),
                    3,
                    0,
                    5
                ),
                loco_surface
            )
            for item, amount in pairs(starting_items) do
                player.insert({name = item, count = amount})
            end
        end
        player.print('Greetings, ' .. player.name .. '!', {r = 0.98, g = 0.66, b = 0.22})
        player.print('Please read the map info.', {r = 0.98, g = 0.66, b = 0.22})
        this.players[player.index].first_join = true
    end
end

local function on_player_left_game()
    set_difficulty()
end

local function on_pre_player_left_game(event)
    local this = WPT.get()
    local player = game.players[event.player_index]
    if player.controller_type == defines.controllers.editor then
        player.toggle_map_editor()
    end
    if player.character then
        this.offline_players[#this.offline_players + 1] = {
            index = event.player_index,
            name = player.name,
            tick = game.tick
        }
    end
end

local function remove_offline_players()
    local this = WPT.get()
    local offline_players = WPT.get('offline_players')
    local active_surface_index = WPT.get('active_surface_index')
    local surface = game.surfaces[active_surface_index]
    local keeper = '[color=blue]Cleaner:[/color]'
    local player_inv = {}
    local items = {}
    if #offline_players > 0 then
        local later = {}
        for i = 1, #offline_players, 1 do
            if
                offline_players[i] and game.players[offline_players[i].index] and
                    game.players[offline_players[i].index].connected
             then
                this.offline_players[i] = nil
            else
                if offline_players[i] and offline_players[i].tick < game.tick - 54000 then
                    local name = offline_players[i].name
                    player_inv[1] =
                        game.players[offline_players[i].index].get_inventory(defines.inventory.character_main)
                    player_inv[2] =
                        game.players[offline_players[i].index].get_inventory(defines.inventory.character_armor)
                    player_inv[3] =
                        game.players[offline_players[i].index].get_inventory(defines.inventory.character_guns)
                    player_inv[4] =
                        game.players[offline_players[i].index].get_inventory(defines.inventory.character_ammo)
                    player_inv[5] =
                        game.players[offline_players[i].index].get_inventory(defines.inventory.character_trash)
                    local pos = game.forces.player.get_spawn_position(surface)
                    local e =
                        surface.create_entity(
                        {
                            name = 'character',
                            position = pos,
                            force = 'neutral'
                        }
                    )
                    local inv = e.get_inventory(defines.inventory.character_main)
                    for ii = 1, 5, 1 do
                        if player_inv[ii].valid then
                            for iii = 1, #player_inv[ii], 1 do
                                if player_inv[ii][iii].valid then
                                    items[#items + 1] = player_inv[ii][iii]
                                end
                            end
                        end
                    end
                    if #items > 0 then
                        for item = 1, #items, 1 do
                            if items[item].valid then
                                inv.insert(items[item])
                            end
                        end
                        game.print(
                            keeper .. ' ' .. name .. ' has left his goodies! [gps=' .. pos.x .. ',' .. pos.y .. ']',
                            {r = 0.98, g = 0.66, b = 0.22}
                        )

                        e.die('neutral')
                    else
                        e.destroy()
                    end

                    for ii = 1, 5, 1 do
                        if player_inv[ii].valid then
                            player_inv[ii].clear()
                        end
                    end
                    this.offline_players[i] = nil
                else
                    later[#later + 1] = offline_players[i]
                end
            end
        end
        this.offline_players = {}
        if #later > 0 then
            for i = 1, #later, 1 do
                this.offline_players[#offline_players + 1] = later[i]
            end
        end
    end
end

local function disable_recipes()
    local force = game.forces.player
    force.recipes['cargo-wagon'].enabled = false
    force.recipes['fluid-wagon'].enabled = false
    force.recipes['artillery-wagon'].enabled = false
    force.recipes['locomotive'].enabled = false
    force.recipes['pistol'].enabled = false
end

local function on_research_finished(event)
    disable_recipes()
    event.research.force.character_inventory_slots_bonus = game.forces.player.mining_drill_productivity_bonus * 50 -- +5 Slots / level
    local mining_speed_bonus = game.forces.player.mining_drill_productivity_bonus * 5 -- +50% speed / level
    if event.research.force.technologies['steel-axe'].researched then
        mining_speed_bonus = mining_speed_bonus + 0.5
    end -- +50% speed for steel-axe research
    event.research.force.manual_mining_speed_modifier = mining_speed_bonus
end

local function is_locomotive_valid()
    local this = WPT.get()
    if not this.locomotive.valid then
        Entities.loco_died()
    end
end

local function has_the_game_ended()
    local this = WPT.get()
    if this.game_reset_tick then
        if this.game_reset_tick < game.tick then
            if not this.disable_reset then
                this.game_reset_tick = nil
                Public.reset_map()
            else
                if not this.reset_the_game then
                    game.print('Auto reset is disabled. Server is shutting down!', {r = 0.22, g = 0.88, b = 0.22})
                    local message = 'Auto reset is disabled. Server is shutting down!'
                    Server.to_discord_bold(table.concat {'*** ', message, ' ***'})
                    Server.stop_scenario()
                    this.reset_the_game = true
                end
            end
        end
        return
    end
end

local function chunk_load()
    local this = WPT.get()
    if this.chunk_load_tick then
        if this.chunk_load_tick < game.tick then
            this.chunk_load_tick = nil
            Task.set_queue_speed(0.8)
        end
    end
end

local on_tick = function()
    local active_surface_index = WPT.get('active_surface_index')
    local surface = game.surfaces[active_surface_index]
    local wave_defense_table = WD.get_table()

    if game.tick % 30 == 0 then
        for _, player in pairs(game.connected_players) do
            update_gui(player)
        end

        if game.tick % 1800 == 0 then
            local collapse_pos = Collapse.get_position()
            local position = surface.find_non_colliding_position('stone-furnace', collapse_pos, 128, 1)
            if position then
                wave_defense_table.spawn_position = position
            end
            remove_offline_players()
            Entities.set_scores()
        end
        is_locomotive_valid()
        has_the_game_ended()
        chunk_load()
    end
end

local on_init = function()
    local this = WPT.get()
    Public.reset_map()

    global.custom_highscore.description = 'Wagon distance reached:'

    this.rocks_yield_ore_maximum_amount = 500
    this.type_modifier = 1
    this.rocks_yield_ore_base_amount = 50
    this.rocks_yield_ore_distance_modifier = 0.025

    local T = Map.Pop_info()
    T.localised_category = 'mountain_fortress'
    T.main_caption_color = {r = 150, g = 150, b = 0}
    T.sub_caption_color = {r = 0, g = 150, b = 0}

    Explosives.set_destructible_tile('out-of-map', 1500)
    Explosives.set_destructible_tile('water', 1000)
    Explosives.set_destructible_tile('water-green', 1000)
    Explosives.set_destructible_tile('deepwater-green', 1000)
    Explosives.set_destructible_tile('deepwater', 1000)
    Explosives.set_destructible_tile('water-shallow', 1000)
end

Event.on_nth_tick(10, on_tick)
Event.on_init(on_init)
Event.add(defines.events.on_player_joined_game, on_player_joined_game)
Event.add(defines.events.on_player_left_game, on_player_left_game)
Event.add(defines.events.on_player_changed_position, on_player_changed_position)
Event.add(defines.events.on_research_finished, on_research_finished)
Event.add(defines.events.on_pre_player_left_game, on_pre_player_left_game)

return Public
