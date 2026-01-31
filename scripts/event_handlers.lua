-- Event handlers for entity lifecycle management

local Config = require("scripts.config")
local AttentionStorage = require("scripts.attention_storage")
local AttentionVisual = require("scripts.attention_visual")
local AttentionSpeed = require("scripts.attention_speed")

local EventHandlers = {}

-- Check if entity is a crafting machine we should track
-- @param entity LuaEntity - Entity to check
-- @return boolean - True if it's a trackable crafting machine
function EventHandlers.is_crafting_machine(entity)
  if not entity or not entity.valid then
    return false
  end

  -- Check if entity type matches any crafting machine type
  for _, machine_type in ipairs(Config.CRAFTING_MACHINE_TYPES) do
    if entity.type == machine_type then
      return true
    end
  end

  return false
end

-- Handle entity creation
-- @param event EventData - Event data from on_built_entity or on_robot_built_entity
function EventHandlers.on_entity_built(event)
  local entity = event.created_entity or event.entity
  if not entity or not entity.valid then
    return
  end

  -- Only track crafting machines
  if not EventHandlers.is_crafting_machine(entity) then
    return
  end

  -- Register the machine
  if AttentionStorage.register_machine(entity) then
    local machine_data = AttentionStorage.get_machine(entity.unit_number)
    if machine_data then
      -- Set initial visual feedback (use normalized attention value [0.0, 1.0])
      -- Capture the rendering ID for the sprite
      machine_data.attention_sprite_id = AttentionVisual.update(
        entity,
        machine_data.attention,
        nil,
        machine_data
      )

      -- Initialize the speed beacon for this machine
      -- Calculate initial speed multiplier (machine starts at normalized 0.0)
      local initial_speed = Config.MIN_ATTENTION  -- Speed multiplier range [0.5, 1.5]
      machine_data.attention_beacon = AttentionSpeed.initialize_beacon(machine_data, initial_speed)
    end
  end
end

-- Handle entity removal
-- @param event EventData - Event data from various destruction events
function EventHandlers.on_entity_removed(event)
  local entity = event.entity
  if not entity or not entity.valid then
    return
  end

  -- Only process if it has a unit_number (which means it could be tracked)
  local unit_number = entity.unit_number
  if not unit_number then
    return
  end

  -- Clean up the speed beacon and rendering before removing from storage
  local machine_data = AttentionStorage.get_machine(unit_number)
  if machine_data then
    AttentionSpeed.cleanup_beacon(machine_data)

    -- Clean up the sprite rendering
    AttentionVisual.clear(entity, machine_data.attention_sprite_id)
  end

  -- Remove from storage if tracked
  AttentionStorage.remove_machine(unit_number)
end

-- Register all event handlers
function EventHandlers.register()
  -- Entity creation events
  script.on_event(defines.events.on_built_entity, EventHandlers.on_entity_built)
  script.on_event(defines.events.on_robot_built_entity, EventHandlers.on_entity_built)
  script.on_event(defines.events.script_raised_built, EventHandlers.on_entity_built)
  script.on_event(defines.events.script_raised_revive, EventHandlers.on_entity_built)

  -- Entity destruction events
  script.on_event(defines.events.on_entity_died, EventHandlers.on_entity_removed)
  script.on_event(defines.events.on_player_mined_entity, EventHandlers.on_entity_removed)
  script.on_event(defines.events.on_robot_mined_entity, EventHandlers.on_entity_removed)
  script.on_event(defines.events.script_raised_destroy, EventHandlers.on_entity_removed)

  -- Additional destruction events
  script.on_event(defines.events.on_space_platform_mined_entity, EventHandlers.on_entity_removed)
end

return EventHandlers
