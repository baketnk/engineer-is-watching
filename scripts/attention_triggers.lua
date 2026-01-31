-- Attention trigger logic - determines whether a machine "has attention"
-- Theme: "When the engineer is away, the machines will play"

local Config = require("scripts.config")

local AttentionTriggers = {}

-- Check inverse proximity: machine has attention when NO players are nearby
-- This is the initial implementation - when the engineer is away, machines have attention
-- @param entity LuaEntity - The crafting machine to check
-- @return boolean - True if machine has attention (no players nearby)
function AttentionTriggers.check_inverse_proximity(entity)
	if not entity or not entity.valid then
		return false
	end

	-- Find all player characters within proximity radius
	local nearby_characters = entity.surface.find_entities_filtered({
		type = "character",
		position = entity.position,
		radius = Config.PROXIMITY_RADIUS,
	})

	-- Has attention when NO players are nearby (inverse proximity)
	return #nearby_characters == 0
end

-- Check if an entity has attention transmitter equipment installed
-- @param entity LuaEntity - Entity to check
-- @return boolean - True if entity has the attention transmitter
local function has_attention_equipment(entity)
	if not entity or not entity.valid or not entity.grid then
		return false
	end

	-- Check if the attention transmitter equipment is installed
	local equipment = entity.grid.find("eiw-attention-transmitter")
	return equipment ~= nil
end

-- ============================================================================
-- FACTOR-BASED ATTENTION API
-- Each factor returns its configured target value when active, 0.0 when inactive
-- ============================================================================

-- Get proximity attention target
-- @param entity LuaEntity - The crafting machine to check
-- @param proximity_radius number - The proximity radius to use for detection
-- @return number - Proximity target value or 0.0
function AttentionTriggers.get_proximity_target(entity, proximity_radius)
	if not entity or not entity.valid then
		return 0.0
	end

	-- Find all player characters within proximity radius
	local nearby_characters = entity.surface.find_entities_filtered({
		type = "character",
		position = entity.position,
		radius = proximity_radius,
	})

	return #nearby_characters > 0 and Config.PROXIMITY_ATTENTION_TARGET or 0.0
end

-- Get equipment attention target
-- @param entity LuaEntity - The crafting machine to check
-- @param proximity_radius number - The proximity radius to use for detection
-- @return number - Equipment target value or 0.0
function AttentionTriggers.get_equipment_target(entity, proximity_radius)
	if not entity or not entity.valid then
		return 0.0
	end

	-- Check for entities with attention transmitter equipment
	local nearby_entities = entity.surface.find_entities_filtered({
		position = entity.position,
		radius = proximity_radius,
	})

	for _, nearby_entity in ipairs(nearby_entities) do
		if has_attention_equipment(nearby_entity) then
			return Config.EQUIPMENT_ATTENTION_TARGET
		end
	end

	return 0.0
end

-- Get visibility attention target
-- @param entity LuaEntity - The crafting machine to check
-- @return number - Visibility target value or 0.0
function AttentionTriggers.get_visibility_target(entity)
	return AttentionTriggers.check_visibility(entity) and Config.VISIBILITY_ATTENTION_TARGET or 0.0
end

-- Get composite attention target from all non-GUI factors
-- Returns the maximum of proximity, visibility, and equipment targets
-- @param entity LuaEntity - The crafting machine to check
-- @param proximity_radius number - The proximity radius to use for detection
-- @return number - Maximum target value from all active factors
function AttentionTriggers.get_composite_target(entity, proximity_radius)
	if not entity or not entity.valid then
		return 0.0
	end

	local proximity = AttentionTriggers.get_proximity_target(entity, proximity_radius)
	local visibility = AttentionTriggers.get_visibility_target(entity)
	local equipment = AttentionTriggers.get_equipment_target(entity, proximity_radius)

	return math.max(proximity, visibility, equipment)
end

-- ============================================================================
-- LEGACY COMPATIBILITY API
-- ============================================================================

-- Direct proximity - machine has attention when player IS nearby
-- Machines work faster when the engineer is watching
-- Also checks for entities with attention transmitter equipment (e.g., spidertrons)
-- @param entity LuaEntity - The crafting machine to check
-- @param proximity_radius number - The proximity radius to use for detection
-- @return boolean - True if machine has attention (player nearby)
function AttentionTriggers.check_direct_proximity(entity, proximity_radius)
	if not entity or not entity.valid then
		return false
	end

	-- Find all player characters within proximity radius
	local nearby_characters = entity.surface.find_entities_filtered({
		type = "character",
		position = entity.position,
		radius = proximity_radius,
	})

	-- Has attention when players ARE nearby (direct proximity)
	if #nearby_characters > 0 then
		return true
	end

	-- disabled for testing to see if this causes siglag
	-- Also check for entities with attention transmitter equipment
	-- This includes spidertrons, tanks, etc. with equipment grids
	-- local nearby_entities = entity.surface.find_entities_filtered{
	--  position = entity.position,
	--  radius = proximity_radius
	-- }

	-- for _, nearby_entity in ipairs(nearby_entities) do
	--  if has_attention_equipment(nearby_entity) then
	--   return true
	--  end
	-- end

	return false
end

-- Convert entity position to chunk position
-- Chunks are 32x32 tiles in Factorio
-- @param position MapPosition - Entity position {x, y}
-- @return ChunkPosition - Chunk coordinates {x, y}
local function position_to_chunk(position)
	return {
		x = math.floor(position.x / 32),
		y = math.floor(position.y / 32),
	}
end

-- Check if entity is visible on any player's screen
-- Uses player position + display resolution to estimate screen bounds
-- @param entity LuaEntity - The crafting machine to check
-- @return boolean - True if machine is visible on any player's screen
function AttentionTriggers.check_visibility(entity)
	if not entity or not entity.valid then
		return false
	end

	local entity_pos = entity.position
	local surface = entity.surface
	local chunk_pos = position_to_chunk(entity_pos)

	-- Check all connected players
	for _, player in pairs(game.connected_players) do
		-- Skip players not on the same surface
		if player.surface == surface then
			-- Get player's view center (character position or cursor if in map view)
			local view_center = player.position

			-- Calculate visible area based on display resolution
			-- display_resolution is in pixels, convert to tiles
			local resolution = player.display_resolution
			local scale = player.display_scale or 1.0

			-- Calculate tiles visible on screen (half-width and half-height from center)
			-- Using Config.TILES_PER_PIXEL (1/32 tiles per pixel at default zoom)
			local half_width_tiles = (resolution.width / 2) * Config.TILES_PER_PIXEL / scale
			local half_height_tiles = (resolution.height / 2) * Config.TILES_PER_PIXEL / scale

			-- Check if entity is within screen bounds
			local dx = math.abs(entity_pos.x - view_center.x)
			local dy = math.abs(entity_pos.y - view_center.y)

			if dx <= half_width_tiles and dy <= half_height_tiles then
				-- Entity is in viewport, now check if it's visible (not in fog of war)
				if player.force.is_chunk_visible(surface, chunk_pos) then
					return true
				end
			end
		end
	end

	return false
end

-- Recent interaction check - machine has attention when recently interacted with
-- NOTE: The actual interaction boost is handled by on_gui_opened event in control.lua
-- which sets attention to max immediately. This function could be extended to provide
-- sustained attention based on interaction timestamps if needed.
-- @param entity LuaEntity - The crafting machine to check
-- @param machine_data table|nil - Machine data from storage (for timestamp checking)
-- @return boolean - True if machine was recently interacted with
function AttentionTriggers.check_recent_interaction(entity, machine_data)
	-- Currently returns false - the instant boost is handled by on_gui_opened event
	-- Future enhancement: could check machine_data.last_interaction_tick against
	-- current tick to provide sustained attention for a duration after interaction
	return false
end

-- Main entry point - check if machine has attention (factor-based)
-- Returns true if any attention factor is active (composite_target > 0.0)
-- @param entity LuaEntity - The crafting machine to check
-- @param proximity_radius number - The proximity radius to use for detection
-- @return boolean - True if machine has attention from any factor
function AttentionTriggers.check_attention(entity, proximity_radius)
	return AttentionTriggers.get_composite_target(entity, proximity_radius) > 0.0
end

-- ============================================================================
-- BATCH QUERY API (Performance Optimized)
-- These functions invert the search: instead of "for each machine, find players",
-- they do "for each player, find machines" - reducing O(N*M) to O(P+N)
-- ============================================================================

-- Find all tracked machine unit_numbers near any connected player
-- @param proximity_radius number - The proximity radius to use for detection
-- @return table - Set of unit_numbers {[unit_number] = true, ...}
function AttentionTriggers.get_machines_near_players(proximity_radius)
	local result = {}
	for _, player in pairs(game.connected_players) do
		local character = player.character
		if character and character.valid then
			local nearby = character.surface.find_entities_filtered({
				type = Config.CRAFTING_MACHINE_TYPES,
				position = character.position,
				radius = proximity_radius,
			})
			for _, entity in ipairs(nearby) do
				if entity.unit_number then
					result[entity.unit_number] = true
				end
			end
		end
	end
	return result
end

-- Helper: Check if a point is within bounding box
-- @param pos MapPosition - Point to check {x, y}
-- @param bounds table - Bounding box {left, right, top, bottom}
-- @return boolean - True if point is within bounds
local function point_in_bounds(pos, bounds)
	return pos.x >= bounds.left and pos.x <= bounds.right and pos.y >= bounds.top and pos.y <= bounds.bottom
end

-- Find all tracked machine unit_numbers in any player's viewport
-- Uses AttentionStorage to iterate machines (requires passing storage iterator)
-- @param machine_iterator function - Iterator from AttentionStorage.iterate()
-- @return table - Set of unit_numbers {[unit_number] = true, ...}
function AttentionTriggers.get_machines_in_viewports(machine_iterator)
	local result = {}

	-- Pre-calculate viewport bounds for each connected player
	local viewports = {}
	for _, player in pairs(game.connected_players) do
		local view_center = player.position
		local resolution = player.display_resolution
		local scale = player.display_scale or 1.0

		-- Calculate tiles visible on screen (half-width and half-height from center)
		local half_width_tiles = (resolution.width / 2) * Config.TILES_PER_PIXEL / scale
		local half_height_tiles = (resolution.height / 2) * Config.TILES_PER_PIXEL / scale

		table.insert(viewports, {
			surface = player.surface,
			force = player.force,
			bounds = {
				left = view_center.x - half_width_tiles,
				right = view_center.x + half_width_tiles,
				top = view_center.y - half_height_tiles,
				bottom = view_center.y + half_height_tiles,
			},
		})
	end

	-- Iterate machines, check if in any viewport (simple math, no API calls)
	for unit_number, machine_data in machine_iterator() do
		local entity = machine_data.entity
		if entity and entity.valid then
			local entity_pos = entity.position
			local entity_surface = entity.surface
			local chunk_pos = position_to_chunk(entity_pos)

			for _, vp in ipairs(viewports) do
				if entity_surface == vp.surface and point_in_bounds(entity_pos, vp.bounds) then
					-- Check fog of war visibility
					if vp.force.is_chunk_visible(entity_surface, chunk_pos) then
						result[unit_number] = true
						break
					end
				end
			end
		end
	end
	return result
end

-- Find machines near entities with attention transmitter equipment
-- @param proximity_radius number - The proximity radius for equipment effect
-- @return table - Set of unit_numbers {[unit_number] = true, ...}
function AttentionTriggers.get_machines_near_equipment(proximity_radius)
	local result = {}

	-- Find entities with grids near connected players
	for _, player in pairs(game.connected_players) do
		local character = player.character
		if character and character.valid then
			-- Search wider area to find equipment carriers
			local nearby_entities = character.surface.find_entities_filtered({
				position = character.position,
				radius = proximity_radius * 2, -- Wider search for equipment carriers
			})

			for _, carrier in ipairs(nearby_entities) do
				if has_attention_equipment(carrier) then
					-- Find machines near this equipment carrier
					local machines = carrier.surface.find_entities_filtered({
						type = Config.CRAFTING_MACHINE_TYPES,
						position = carrier.position,
						radius = proximity_radius,
					})
					for _, machine in ipairs(machines) do
						if machine.unit_number then
							result[machine.unit_number] = true
						end
					end
				end
			end
		end
	end
	return result
end

return AttentionTriggers
