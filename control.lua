-- Engineer Is Watching - Main control script
-- "When the engineer is away, the machines will play"

-- Load modules
local Config = require("scripts.config")
local AttentionStorage = require("scripts.attention_storage")
local AttentionUpdater = require("scripts.attention_updater")
local AttentionSpeed = require("scripts.attention_speed")
local EventHandlers = require("scripts.event_handlers")
local AttentionDebugVisual = require("scripts.attention_debug_visual")
local AttentionTechEffects = require("scripts.attention_tech_effects")

-- Runtime configuration cache (updated from settings)
local runtime_config = {
	attention_decay_rate = nil, -- Will be initialized in on_init
	attention_growth_rate = nil,
	min_attention = nil,
	max_attention = nil,
	delta_ramp_steps = nil,
}

-- Reinitialize runtime config from settings (called from multiple places)
local function init_runtime_config()
	runtime_config.attention_decay_rate = settings.global["eiw-attention-rate"].value
	runtime_config.attention_growth_rate = settings.global["eiw-attention-growth-rate"].value
	runtime_config.delta_ramp_steps = settings.global["eiw-delta-ramp-steps"].value
	runtime_config.min_attention = Config.MIN_ATTENTION
	runtime_config.max_attention = Config.MAX_ATTENTION
end

-- Initialize mod on first load
script.on_init(function()
	game.print("on_init")
	-- Initialize storage
	AttentionStorage.init()
	AttentionDebugVisual.init()
	AttentionTechEffects.init()

	-- Initialize tier system from startup settings
	AttentionSpeed.initialize_tiers()

	-- Initialize runtime config from settings
	init_runtime_config()

	-- Initialize debug verbose mode flag
	storage.verbose_debug = false

	-- Debug: log initialization
	game.print("[Engineer Is Watching] Initialized")
	game.print("  Update interval: " .. Config.UPDATE_INTERVAL .. " ticks")
	game.print("  Decay rate: " .. runtime_config.attention_decay_rate)
	game.print("  Growth rate: " .. runtime_config.attention_growth_rate)
end)

-- Handle save loading (runtime_config is local, not persisted)
script.on_load(function()
	-- Runtime config must be reinitialized on every load
	-- since it's a local variable, not stored in global storage
	-- Note: game global is not available in on_load
	init_runtime_config()

	-- Reinitialize tier system from settings
	-- (module-level variables are not persisted)
	AttentionSpeed.initialize_tiers()
end)

-- Handle configuration changes (mod updates, etc.)
script.on_configuration_changed(function(data)
	log("[Engineer Is Watching] on_configuration_changed called")

	-- Ensure storage exists
	AttentionStorage.init()
	AttentionDebugVisual.init()
	AttentionTechEffects.init()

	-- Ensure verbose debug flag exists
	if storage.verbose_debug == nil then
		storage.verbose_debug = false
	end

	-- Refresh runtime config from settings
	init_runtime_config()

	log("[Engineer Is Watching] Configuration changed complete")

	-- Invalidate technology caches (force recalculation)
	AttentionTechEffects.invalidate_all_caches()

	-- Reinitialize tier system (in case interval setting changed)
	AttentionSpeed.initialize_tiers()

	-- Recreate all beacons if interval changed (they may have wrong tier modules)
	for unit_number, machine_data in AttentionStorage.iterate() do
		-- Destroy old beacon
		if machine_data.attention_beacon and machine_data.attention_beacon.valid then
			machine_data.attention_beacon.destroy()
		end

		-- Get current speed multiplier
		local effective_params =
			AttentionTechEffects.get_effective_attention_params(machine_data.entity.force, runtime_config)
		local speed_multiplier = AttentionUpdater.get_speed_multiplier(machine_data.attention, effective_params)

		-- Recreate beacon with current tier
		machine_data.attention_beacon =
			AttentionSpeed.create_beacon(machine_data.entity, AttentionSpeed.attention_to_tier(speed_multiplier))
	end

	-- Validate all tracked entities and remove invalid ones (with beacon cleanup)
	local removed = AttentionStorage.validate_all(AttentionSpeed.cleanup_beacon)
	if removed > 0 then
		game.print("[Engineer Is Watching] Cleaned up " .. removed .. " invalid machines")
	end
end)

-- Register event handlers for entity lifecycle
EventHandlers.register()

-- Register debug commands if enabled by setting
local function register_debug_commands()
	if not settings.global["eiw-enable-debug-commands"].value then
		-- Unregister all debug commands
		commands.remove_command("attention-debug")
		commands.remove_command("attention-radius-debug")
		commands.remove_command("attention-show")
		commands.remove_command("attention-set-min")
		commands.remove_command("attention-set-max")
		commands.remove_command("attention-set-decay-rate")
		commands.remove_command("attention-set-growth-rate")
		commands.remove_command("attention-set-ramp-steps")
		commands.remove_command("attention-proximity-check")
		commands.remove_command("attention-stats")
		commands.remove_command("attention-verbose")
		commands.remove_command("attention-explode")
		return
	end

	-- Debug command: Show total tracked machines
	commands.add_command("attention-debug", "Show attention system statistics", function(event)
		local count = AttentionStorage.count()
		local player = game.get_player(event.player_index)
		if player then
			local effective_radius = AttentionTechEffects.get_effective_proximity_radius(player.force)
			player.print("[Engineer Is Watching] Tracking " .. count .. " machines")
			player.print(
				"Update interval: "
					.. Config.UPDATE_INTERVAL
					.. " ticks ("
					.. (Config.UPDATE_INTERVAL / 60)
					.. " seconds)"
			)
			player.print("Proximity radius: " .. effective_radius .. " tiles")
			player.print("Runtime config initialized: " .. tostring(runtime_config.attention_decay_rate ~= nil))
			if runtime_config.attention_decay_rate then
				player.print("  Decay rate: " .. runtime_config.attention_decay_rate)
				player.print("  Growth rate: " .. runtime_config.attention_growth_rate)
				player.print("  Delta ramp steps: " .. runtime_config.delta_ramp_steps)
			end
		end
	end)

	-- Debug command: Toggle radius visualization
	commands.add_command(
		"attention-radius-debug",
		"Toggle visual display of attention proximity radius",
		function(event)
			local player = game.get_player(event.player_index)
			if not player then
				return
			end

			local new_state = AttentionDebugVisual.toggle_radius_visualization(player)
			if new_state then
				local effective_radius = AttentionTechEffects.get_effective_proximity_radius(player.force)
				player.print(
					"[Engineer Is Watching] Radius visualization enabled (cyan circles show "
						.. effective_radius
						.. " tile range)"
				)
			else
				player.print("[Engineer Is Watching] Radius visualization disabled")
			end
		end
	)

	-- Debug command: Show attention for selected entity
	commands.add_command(
		"attention-show",
		"Show attention value for selected entity (hold cursor over machine)",
		function(event)
			local player = game.get_player(event.player_index)
			if not player then
				return
			end

			local selected = player.selected
			if not selected or not selected.valid then
				player.print("[Engineer Is Watching] No entity selected (hover cursor over a machine)")
				return
			end

			local unit_number = selected.unit_number
			if not unit_number then
				player.print("[Engineer Is Watching] Selected entity has no unit number")
				return
			end

			local machine = AttentionStorage.get_machine(unit_number)
			if not machine then
				player.print("[Engineer Is Watching] Entity is not tracked (not a crafting machine?)")
				return
			end

			-- Display detailed info
			player.print("[Engineer Is Watching] Machine: " .. selected.name)
			player.print(
				"  Attention: "
					.. string.format("%.3f", machine.attention)
					.. " ("
					.. math.floor(machine.attention * 100)
					.. "%)"
			)
			player.print("  Has Attention: " .. tostring(machine.has_attention))
			player.print("  Target: " .. string.format("%.3f", machine.target_attention))
			player.print("  Delta: " .. string.format("%.5f", machine.attention_delta or 0))

			-- Show beacon info
			if machine.attention_beacon and machine.attention_beacon.valid then
				-- Extract tier from module instead of beacon name
				local module_inventory = machine.attention_beacon.get_module_inventory()
				local tier = "unknown"
				if module_inventory and not module_inventory.is_empty() then
					local contents = module_inventory.get_contents()
					for _, item in pairs(contents) do
						local item_name = item.name
						local tier_match = item_name:match("eiw%-attention%-module%-(%d+)")
						if tier_match then
							tier = tier_match
							break
						end
					end
				end
				player.print("  Speed Beacon: Active (tier " .. tier .. "%)")
			else
				player.print("  Speed Beacon: None")
			end
		end
	)

	-- Runtime tweaking commands (temporary overrides, not persisted)
	commands.add_command("attention-set-min", "Set minimum attention value (0.1-1.0)", function(event)
		local player = game.get_player(event.player_index)
		if not player then
			return
		end

		local param = tonumber(event.parameter)
		if not param or param < 0.1 or param > 1.0 then
			player.print("[Engineer Is Watching] Usage: /attention-set-min <value> (0.1-1.0)")
			return
		end

		runtime_config.min_attention = param
		player.print("[Engineer Is Watching] Minimum attention set to " .. param .. " (temporary override)")
	end)

	commands.add_command("attention-set-max", "Set maximum attention value (1.0-3.0)", function(event)
		local player = game.get_player(event.player_index)
		if not player then
			return
		end

		local param = tonumber(event.parameter)
		if not param or param < 1.0 or param > 3.0 then
			player.print("[Engineer Is Watching] Usage: /attention-set-max <value> (1.0-3.0)")
			return
		end

		runtime_config.max_attention = param
		player.print("[Engineer Is Watching] Maximum attention set to " .. param .. " (temporary override)")
	end)

	commands.add_command("attention-set-decay-rate", "Set attention decay rate (0.01-0.5)", function(event)
		local player = game.get_player(event.player_index)
		if not player then
			return
		end

		local param = tonumber(event.parameter)
		if not param or param < 0.01 or param > 0.5 then
			player.print("[Engineer Is Watching] Usage: /attention-set-decay-rate <value> (0.01-0.5)")
			return
		end

		runtime_config.attention_decay_rate = param
		player.print("[Engineer Is Watching] Attention decay rate set to " .. param .. " (temporary override)")
	end)

	commands.add_command("attention-set-growth-rate", "Set attention growth rate (0.01-0.5)", function(event)
		local player = game.get_player(event.player_index)
		if not player then
			return
		end

		local param = tonumber(event.parameter)
		if not param or param < 0.01 or param > 0.5 then
			player.print("[Engineer Is Watching] Usage: /attention-set-growth-rate <value> (0.01-0.5)")
			return
		end

		runtime_config.attention_growth_rate = param
		player.print("[Engineer Is Watching] Attention growth rate set to " .. param .. " (temporary override)")
	end)

	commands.add_command("attention-set-ramp-steps", "Set delta ramp steps (1-20)", function(event)
		local player = game.get_player(event.player_index)
		if not player then
			return
		end

		local param = tonumber(event.parameter)
		if not param or param < 1 or param > 20 then
			player.print("[Engineer Is Watching] Usage: /attention-set-ramp-steps <value> (1-20)")
			return
		end

		runtime_config.delta_ramp_steps = param
		player.print("[Engineer Is Watching] Delta ramp steps set to " .. param .. " (temporary override)")
	end)

	-- Debug command: Check proximity triggers for selected entity
	commands.add_command(
		"attention-proximity-check",
		"Show what entities are triggering attention for selected machine",
		function(event)
			local player = game.get_player(event.player_index)
			if not player then
				return
			end

			local selected = player.selected
			if not selected or not selected.valid then
				player.print("[Engineer Is Watching] No entity selected (hover cursor over a machine)")
				return
			end

			local unit_number = selected.unit_number
			if not unit_number then
				player.print("[Engineer Is Watching] Selected entity has no unit number")
				return
			end

			local machine = AttentionStorage.get_machine(unit_number)
			if not machine then
				player.print("[Engineer Is Watching] Entity is not tracked (not a crafting machine?)")
				return
			end

			local effective_radius = AttentionTechEffects.get_effective_proximity_radius(selected.force)
			player.print("[Engineer Is Watching] Proximity check for: " .. selected.name)
			player.print("  Proximity radius: " .. effective_radius .. " tiles")

			-- Check for player characters nearby
			local nearby_characters = selected.surface.find_entities_filtered({
				type = "character",
				position = selected.position,
				radius = effective_radius,
			})
			player.print("  Characters nearby: " .. #nearby_characters)
			for i, char in pairs(nearby_characters) do
				local distance =
					math.sqrt((char.position.x - selected.position.x) ^ 2 + (char.position.y - selected.position.y) ^ 2)
				player.print(
					"    [" .. i .. "] " .. char.name .. " at distance " .. string.format("%.1f", distance) .. " tiles"
				)
				if char.player then
					player.print("        Player: " .. char.player.name)
				end
			end

			-- Check for entities with attention equipment
			local nearby_entities = selected.surface.find_entities_filtered({
				position = selected.position,
				radius = effective_radius,
			})

			local equipment_count = 0
			for _, entity in ipairs(nearby_entities) do
				if entity.grid then
					local equipment = entity.grid.find("eiw-attention-transmitter")
					if equipment then
						equipment_count = equipment_count + 1
						local distance = math.sqrt(
							(entity.position.x - selected.position.x) ^ 2
								+ (entity.position.y - selected.position.y) ^ 2
						)
						player.print(
							"    [E] "
								.. entity.name
								.. " with attention transmitter at "
								.. string.format("%.1f", distance)
								.. " tiles"
						)
					end
				end
			end

			player.print("  Entities with attention transmitter: " .. equipment_count)
			player.print("  Current attention state: " .. (machine.has_attention and "HAS ATTENTION" or "NO ATTENTION"))
			player.print("  Total entities in radius: " .. #nearby_entities)
		end
	)

	-- Debug command: Show statistics about all tracked machines
	commands.add_command("attention-stats", "Show statistics about attention state across all machines", function(event)
		local player = game.get_player(event.player_index)
		if not player then
			return
		end

		local total = 0
		local with_attention = 0
		local without_attention = 0
		local at_max = 0
		local at_min = 0
		local transitioning = 0

		for unit_number, machine_data in AttentionStorage.iterate() do
			total = total + 1

			if machine_data.has_attention then
				with_attention = with_attention + 1
			else
				without_attention = without_attention + 1
			end

			-- Check if at extremes
			if machine_data.attention >= 0.99 then
				at_max = at_max + 1
			elseif machine_data.attention <= 0.01 then
				at_min = at_min + 1
			else
				transitioning = transitioning + 1
			end
		end

		player.print("[Engineer Is Watching] Attention Statistics:")
		player.print("  Total tracked machines: " .. total)
		player.print("  Machines with attention (player nearby): " .. with_attention)
		player.print("  Machines without attention: " .. without_attention)
		player.print("  At maximum (≥99%): " .. at_max)
		player.print("  At minimum (≤1%): " .. at_min)
		player.print("  Transitioning (1%-99%): " .. transitioning)

		if total > 0 then
			player.print("  % with attention: " .. string.format("%.1f", (with_attention / total) * 100) .. "%")
		end
	end)

	-- Debug command: Toggle verbose update logging
	commands.add_command("attention-verbose", "Toggle verbose debug logging in update loop", function(event)
		local player = game.get_player(event.player_index)
		if not player then
			return
		end

		storage.verbose_debug = not storage.verbose_debug
		player.print(
			"[Engineer Is Watching] Verbose debug logging " .. (storage.verbose_debug and "ENABLED" or "DISABLED")
		)
		if storage.verbose_debug then
			player.print("  Updates will print detailed information to console every tick")
			player.print("  WARNING: This will spam the console heavily!")
		end
	end)

	-- Debug command: Force extreme attention value to test clamping
	commands.add_command(
		"attention-explode",
		"Force extreme attention on nearest machine to test clamping",
		function(event)
			local player = game.get_player(event.player_index)
			if not player then
				return
			end

			-- Find nearest crafting machine
			local nearest = nil
			local nearest_distance = nil

			for unit_number, machine_data in AttentionStorage.iterate() do
				if machine_data.entity and machine_data.entity.valid then
					local distance = math.sqrt(
						(machine_data.entity.position.x - player.position.x) ^ 2
							+ (machine_data.entity.position.y - player.position.y) ^ 2
					)

					if not nearest_distance or distance < nearest_distance then
						nearest = machine_data
						nearest_distance = distance
					end
				end
			end

			if not nearest then
				player.print("[Engineer Is Watching] No tracked machines found")
				return
			end

			local old_value = nearest.attention
			nearest.attention = 3.0 -- Extreme value (300% of normalized max)
			nearest.target_attention = 3.0

			player.print("[Engineer Is Watching] EXPLODE! Nearest machine attention:")
			player.print("  Old value: " .. string.format("%.3f", old_value))
			player.print("  New value: " .. string.format("%.3f", nearest.attention))
			player.print("  Distance: " .. string.format("%.1f", nearest_distance) .. " tiles")
			player.print("  Machine: " .. nearest.entity.name)
			player.print("  Next update will clamp to [0.0, 1.0] range")
		end
	)
end

-- Initialize debug commands on startup
register_debug_commands()

-- Handle runtime mod setting changes
script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
	if event.setting == "eiw-attention-rate" then
		runtime_config.attention_decay_rate = settings.global["eiw-attention-rate"].value
		game.print("[Engineer Is Watching] Attention decay rate changed to " .. runtime_config.attention_decay_rate)
	elseif event.setting == "eiw-attention-growth-rate" then
		runtime_config.attention_growth_rate = settings.global["eiw-attention-growth-rate"].value
		game.print("[Engineer Is Watching] Attention growth rate changed to " .. runtime_config.attention_growth_rate)
	elseif event.setting == "eiw-delta-ramp-steps" then
		runtime_config.delta_ramp_steps = settings.global["eiw-delta-ramp-steps"].value
		game.print("[Engineer Is Watching] Delta ramp steps changed to " .. runtime_config.delta_ramp_steps)
	elseif event.setting == "eiw-enable-debug-commands" then
		register_debug_commands()
		local state = settings.global["eiw-enable-debug-commands"].value
		game.print("[Engineer Is Watching] Debug commands " .. (state and "enabled" or "disabled"))
	end
end)

-- on_nth_tick is a singleton per value of n!!!
script.on_nth_tick(Config.UPDATE_INTERVAL, function()
	if storage.verbose_debug then
		game.print("[DEBUG] Update tick fired at game tick " .. game.tick)
	end
	AttentionUpdater.update_all(runtime_config)
	-- disabling for perf checking
	-- AttentionDebugVisual.update_all()
end)

-- Clean up debug visualization when player leaves
script.on_event(defines.events.on_player_left_game, function(event)
	AttentionDebugVisual.clear_circles(event.player_index)
end)

-- Clean up debug visualization when player dies
script.on_event(defines.events.on_player_died, function(event)
	AttentionDebugVisual.clear_circles(event.player_index)
end)

-- Handle GUI opened - boost attention when player interacts with a machine
script.on_event(defines.events.on_gui_opened, function(event)
	local player = game.get_player(event.player_index)
	if not player then
		return
	end

	local entity = event.entity
	if not entity or not entity.valid then
		return
	end

	-- Only process tracked crafting machines
	local unit_number = entity.unit_number
	if not unit_number then
		return
	end

	local machine_data = AttentionStorage.get_machine(unit_number)
	if not machine_data then
		return
	end

	-- Mark GUI as open
	machine_data.gui_open = true

	-- Trigger immediate update for responsive feedback
	AttentionUpdater.update_machine(unit_number, machine_data, runtime_config)
end)

-- Handle GUI closed - clear the open flag to resume normal attention behavior
script.on_event(defines.events.on_gui_closed, function(event)
	local player = game.get_player(event.player_index)
	if not player then
		return
	end

	local entity = event.entity
	if not entity or not entity.valid then
		return
	end

	local unit_number = entity.unit_number
	if not unit_number then
		return
	end

	local machine_data = AttentionStorage.get_machine(unit_number)
	if not machine_data then
		return
	end

	-- Clear GUI open flag
	machine_data.gui_open = false

	-- Trigger immediate update to start decay
	AttentionUpdater.update_machine(unit_number, machine_data, runtime_config)
end)

-- Handle technology research completion
script.on_event(defines.events.on_research_finished, function(event)
	local tech = event.research
	if not tech then
		return
	end

	-- Check if this is one of our attention technologies
	if
		tech.name == "eiw-attention-floor"
		or tech.name == "eiw-attention-ceiling"
		or tech.name == "eiw-attention-decay-slowdown"
		or tech.name == "eiw-attention-growth-boost"
		or tech.name:match("^eiw%-attention%-range%-%d+$")
	then
		-- Invalidate the cache for this force
		AttentionTechEffects.invalidate_cache(tech.force)

		-- Log research completion for debugging
		if tech.name:match("^eiw%-attention%-range%-%d+$") then
			local new_radius = AttentionTechEffects.get_effective_proximity_radius(tech.force)
			game.print(
				"[Engineer Is Watching] "
					.. tech.name
					.. " researched - Proximity radius increased to "
					.. new_radius
					.. " tiles"
			)
		else
			game.print("[Engineer Is Watching] " .. tech.name .. " level " .. tech.level .. " researched")
		end
	end
end)

-- Optional: Remote interface for other mods
remote.add_interface("engineer_is_watching", {
	-- Get attention value for an entity
	get_attention = function(entity)
		if not entity or not entity.valid or not entity.unit_number then
			return nil
		end
		local machine = AttentionStorage.get_machine(entity.unit_number)
		return machine and machine.attention or nil
	end,

	-- Get count of tracked machines
	get_machine_count = function()
		return AttentionStorage.count()
	end,
})
