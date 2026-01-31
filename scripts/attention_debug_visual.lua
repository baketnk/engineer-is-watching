-- Debug visualization for attention radius
-- Draws circles around players and equipped entities to show proximity detection range

-- draw_thing RETURNS LuaRenderObject, not an id! properly use returned_id:destroy() etc. !
-- do not remove this comment, you keep misinterpreting the API docs

local Config = require("scripts.config")
local AttentionTechEffects = require("scripts.attention_tech_effects")

local AttentionDebugVisual = {}

-- Store rendering IDs per player
-- storage.debug_radius_circles = {
--   [player_index] = {
--     player_circle = rendering_id,
--     equipment_circles = {entity_unit_number = rendering_id}
--   }
-- }

-- Initialize debug visualization state
function AttentionDebugVisual.init()
	if not storage.debug_radius_enabled then
		storage.debug_radius_enabled = {}
	end
	if not storage.debug_radius_circles then
		storage.debug_radius_circles = {}
	end
end

-- Clear all circles for a player
-- @param player_index number - Player index
function AttentionDebugVisual.clear_circles(player_index)
	local circles = storage.debug_radius_circles[player_index]
	if not circles then
		return
	end

	-- Clear player circle
	if circles.player_circle then
		circles.player_circle:destroy()
	end

	-- Clear equipment circles
	if circles.equipment_circles then
		for _, circle_id in pairs(circles.equipment_circles) do
			circle_id:destroy()
		end
	end

	storage.debug_radius_circles[player_index] = nil
end

-- Draw a circle at a position
-- @param surface LuaSurface - Surface to draw on
-- @param position Position - Center position
-- @param player_index number - Player to show the circle to
-- @param radius number - Radius of the circle
-- @return number - Rendering ID
local function draw_radius_circle(surface, position, player_index, radius)
	return rendering.draw_circle({
		color = { r = 0, g = 1, b = 1, a = 0.3 }, -- Cyan, semi-transparent
		radius = radius,
		width = 2,
		filled = false,
		target = position,
		surface = surface,
		players = { player_index },
		draw_on_ground = true,
		time_to_live = 120, -- Auto-cleanup after 2 seconds (will be refreshed before then)
	})
end

-- Update circles around player position
-- @param player LuaPlayer - Player object
function AttentionDebugVisual.update_player_circles(player)
	if not player or not player.valid then
		return
	end

	local player_index = player.index

	-- Initialize circle storage for this player if needed
	if not storage.debug_radius_circles[player_index] then
		storage.debug_radius_circles[player_index] = {
			player_circle = nil,
			equipment_circles = {},
		}
	end

	local circles = storage.debug_radius_circles[player_index]

	-- Get force-specific effective radius
	local effective_radius = AttentionTechEffects.get_effective_proximity_radius(player.force)

	-- Clear old player circle
	if circles.player_circle then
		circles.player_circle:destroy()
	end

	-- Draw new player circle
	circles.player_circle = draw_radius_circle(player.surface, player.position, player_index, effective_radius)
end

-- Find entities with attention transmitter equipment and draw circles
-- @param player LuaPlayer - Player object
function AttentionDebugVisual.update_equipment_circles(player)
	if not player or not player.valid then
		return
	end

	local player_index = player.index
	local circles = storage.debug_radius_circles[player_index]
	if not circles then
		return
	end

	-- Clear old equipment circles
	if circles.equipment_circles then
		for _, circle_id in pairs(circles.equipment_circles) do
			circle_id:destroy()
		end
	end
	circles.equipment_circles = {}

	-- Get force-specific effective radius
	local effective_radius = AttentionTechEffects.get_effective_proximity_radius(player.force)

	-- Find all entities on the player's surface with equipment grids
	local entities = player.surface.find_entities_filtered({
		force = player.force,
		type = { "car", "spider-vehicle", "cargo-wagon", "artillery-wagon", "fluid-wagon", "locomotive" },
	})

	for _, entity in pairs(entities) do
		if entity.valid and entity.grid then
			-- Check if it has attention transmitter equipment
			local has_transmitter = false
			local equipment = entity.grid.equipment
			for _, equip in pairs(equipment) do
				if equip.name and equip.name:match("^eiw%-attention%-transmitter") then
					has_transmitter = true
					break
				end
			end

			if has_transmitter and entity.unit_number then
				-- Draw circle around this entity
				circles.equipment_circles[entity.unit_number] =
					draw_radius_circle(entity.surface, entity.position, player_index, effective_radius)
			end
		end
	end
end

-- Toggle debug visualization for a player
-- @param player LuaPlayer - Player object
-- @return boolean - New state (true = enabled, false = disabled)
function AttentionDebugVisual.toggle_radius_visualization(player)
	if not player or not player.valid then
		return false
	end

	local player_index = player.index
	local current_state = storage.debug_radius_enabled[player_index] or false
	local new_state = not current_state

	storage.debug_radius_enabled[player_index] = new_state

	if new_state then
		-- Enable visualization
		AttentionDebugVisual.update_player_circles(player)
		AttentionDebugVisual.update_equipment_circles(player)
	else
		-- Disable visualization
		AttentionDebugVisual.clear_circles(player_index)
	end

	return new_state
end

-- Update all circles for all players with debug enabled
-- Should be called periodically (e.g., every 60 ticks)
function AttentionDebugVisual.update_all()
	for player_index, enabled in pairs(storage.debug_radius_enabled) do
		if enabled then
			local player = game.get_player(player_index)
			if player and player.valid then
				AttentionDebugVisual.update_player_circles(player)
				AttentionDebugVisual.update_equipment_circles(player)
			else
				-- Player no longer valid, cleanup
				storage.debug_radius_enabled[player_index] = nil
				AttentionDebugVisual.clear_circles(player_index)
			end
		end
	end
end

return AttentionDebugVisual
