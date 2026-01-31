-- Core update logic for attention system
-- Handles periodic updates and smooth interpolation

local Config = require("scripts.config")
local AttentionStorage = require("scripts.attention_storage")
local AttentionTriggers = require("scripts.attention_triggers")
local AttentionVisual = require("scripts.attention_visual")
local AttentionSpeed = require("scripts.attention_speed")
local AttentionTechEffects = require("scripts.attention_tech_effects")

local AttentionUpdater = {}

-- Smootherstep interpolation (6t^5 - 15t^4 + 10t^3)
-- Maps normalized attention [0.0, 1.0] to actual speed multiplier [edge0, edge1]
-- @param t number - Normalized value [0.0, 1.0]
-- @param edge0 number - Minimum value (floor)
-- @param edge1 number - Maximum value (ceiling)
-- @return number - Smoothly interpolated value
function AttentionUpdater.smootherstep(t, edge0, edge1)
	-- Clamp t to [0, 1]
	t = math.max(0, math.min(1, t))

	-- Smootherstep: 6t^5 - 15t^4 + 10t^3
	local smooth = t * t * t * (t * (6 * t - 15) + 10)

	-- Map to range
	return edge0 + (edge1 - edge0) * smooth
end

-- Convert normalized attention [0,1] to actual speed multiplier [min,max]
-- @param normalized_attention number - Normalized attention value [0.0, 1.0]
-- @param effective_params table - Effective parameters with min/max values
-- @param quantum_mode boolean - If true, invert attention before applying smootherstep
-- @return number - Actual speed multiplier
function AttentionUpdater.get_speed_multiplier(normalized_attention, effective_params, quantum_mode)
	-- Invert attention if quantum mode enabled (100% attention = slowest, 0% = fastest)
	local attention = quantum_mode and (1.0 - normalized_attention) or normalized_attention

	return AttentionUpdater.smootherstep(attention, effective_params.min, effective_params.max)
end

-- Update a single machine's attention with a pre-computed target
-- Uses simplified linear growth/decay instead of delta ramping
-- @param unit_number number - Machine's unit number
-- @param machine_data table - Machine data from storage
-- @param target_attention number - Pre-computed target attention [0.0, 1.0]
-- @param effective_params table - Effective parameters with rates
-- @return boolean - False if entity was invalid and removed
function AttentionUpdater.update_machine_with_target(unit_number, machine_data, target_attention, effective_params)
	local entity = machine_data.entity

	-- Validate entity
	if not entity or not entity.valid then
		AttentionStorage.remove_machine(unit_number)
		return false
	end

	-- Migration: Convert old attention system to normalized [0.0, 1.0]
	if machine_data.attention == nil or machine_data.attention > 1.0 or machine_data.attention < 0.0 then
		local old_attention = machine_data.attention or Config.MIN_ATTENTION
		local min = Config.MIN_ATTENTION
		local max = Config.MAX_ATTENTION
		machine_data.attention = math.max(0, math.min(1, (old_attention - min) / (max - min)))
	end

	-- Update has_attention boolean (for compatibility)
	machine_data.has_attention = (target_attention > 0.0)
	machine_data.target_attention = target_attention

	-- Simplified linear growth/decay (no delta ramping)
	local current = machine_data.attention
	local target = target_attention

	if math.abs(current - target) > 0.001 then
		if target > current then
			-- Growing toward target
			machine_data.attention = math.min(target, current + effective_params.growth_rate)
		else
			-- Decaying toward target
			machine_data.attention = math.max(target, current - effective_params.decay_rate)
		end
	end

	-- Get actual speed multiplier for speed effects
	local speed_multiplier =
		AttentionUpdater.get_speed_multiplier(machine_data.attention, effective_params, Config.QUANTUM_ZENO_MODE)

	-- Update visual feedback (pass normalized attention [0.0, 1.0] and machine_data for debug)
	machine_data.attention_sprite_id =
		AttentionVisual.update(entity, machine_data.attention, machine_data.attention_sprite_id, machine_data)

	-- Update speed modifier beacon (pass speed_multiplier)
	machine_data.attention_beacon = AttentionSpeed.apply_speed_modifier(machine_data, speed_multiplier)

	return true
end

-- Legacy update function for single machine (kept for compatibility)
-- @param unit_number number - Machine's unit number
-- @param machine_data table - Machine data from storage
-- @param runtime_config table - Runtime configuration with attention rate and min/max values
function AttentionUpdater.update_machine(unit_number, machine_data, runtime_config)
	local entity = machine_data.entity

	-- Validate entity
	if not entity or not entity.valid then
		AttentionStorage.remove_machine(unit_number)
		return
	end

	-- Set GUI factor target
	if machine_data.gui_open then
		machine_data.gui_target = Config.GUI_ATTENTION_TARGET
	else
		machine_data.gui_target = 0.0
	end

	-- Get force-specific effective parameters (includes technology modifiers)
	local effective_params = AttentionTechEffects.get_effective_attention_params(entity.force, runtime_config)

	-- Get force-specific proximity radius
	local proximity_radius = AttentionTechEffects.get_effective_proximity_radius(entity.force)

	-- Get composite target from all factors (legacy per-machine search)
	local composite_target = AttentionTriggers.get_composite_target(entity, proximity_radius)
	local target_attention = math.max(composite_target, machine_data.gui_target or 0.0)

	-- Use the new simplified update function
	AttentionUpdater.update_machine_with_target(unit_number, machine_data, target_attention, effective_params)
end

-- Main update function called every UPDATE_INTERVAL ticks
-- Uses inverted search pattern: for each player, find machines (instead of vice versa)
-- Complexity: O(P + N) instead of O(N * M) where P=players, N=machines, M=entities per search
-- @param runtime_config table - Runtime configuration with attention rate and min/max values
function AttentionUpdater.update_all(runtime_config)
	-- Get the default force for tech effects (use first connected player's force, or "player")
	local default_force = game.forces["player"]
	for _, player in pairs(game.connected_players) do
		default_force = player.force
		break
	end

	-- Get force-specific effective parameters and proximity radius
	local effective_params = AttentionTechEffects.get_effective_attention_params(default_force, runtime_config)
	local proximity_radius = AttentionTechEffects.get_effective_proximity_radius(default_force)

	-- ========================================================================
	-- PHASE 1: Build attention sets (O(P) searches, P = connected players)
	-- ========================================================================

	-- Set of unit_numbers near any player character
	local proximity_set = AttentionTriggers.get_machines_near_players(proximity_radius)

	-- Set of unit_numbers in any player viewport
	local visibility_set = AttentionTriggers.get_machines_in_viewports(AttentionStorage.iterate)

	-- Set of unit_numbers near attention transmitter equipment
	local equipment_set = AttentionTriggers.get_machines_near_equipment(proximity_radius)

	-- ========================================================================
	-- PHASE 2: Update each machine with simple set lookups (O(N))
	-- ========================================================================

	for unit_number, machine_data in AttentionStorage.iterate() do
		-- Set GUI factor target
		if machine_data.gui_open then
			machine_data.gui_target = Config.GUI_ATTENTION_TARGET
		else
			machine_data.gui_target = 0.0
		end

		-- Calculate composite target from set membership
		local target = machine_data.gui_target or 0.0

		if proximity_set[unit_number] then
			target = math.max(target, Config.PROXIMITY_ATTENTION_TARGET)
		end
		if visibility_set[unit_number] then
			target = math.max(target, Config.VISIBILITY_ATTENTION_TARGET)
		end
		if equipment_set[unit_number] then
			target = math.max(target, Config.EQUIPMENT_ATTENTION_TARGET)
		end

		-- Update machine with computed target
		AttentionUpdater.update_machine_with_target(unit_number, machine_data, target, effective_params)
	end
end

return AttentionUpdater
