-- Data structure management for machine attention tracking
-- Handles CRUD operations on the storage table

local Config = require("scripts.config")

local AttentionStorage = {}

-- Initialize storage structure
function AttentionStorage.init()
  if not storage.machines then
    storage.machines = {}
  end
end

-- Register a new crafting machine
-- @param entity LuaEntity - The crafting machine to track
-- @return boolean - Success status
function AttentionStorage.register_machine(entity)
  if not entity or not entity.valid then
    return false
  end

  local unit_number = entity.unit_number
  if not unit_number then
    return false
  end

  -- Don't re-register existing machines
  if storage.machines[unit_number] then
    return false
  end

  storage.machines[unit_number] = {
    entity = entity,
    attention = 0.0,  -- Start at normalized floor [0.0, 1.0]
    attention_delta = 0.0,  -- Rate of change per update (delta ramping)
    has_attention = false,  -- Start with no attention (direct proximity)
    target_attention = 0.0,  -- Start targeting floor
    attention_beacon = nil,  -- Reference to hidden beacon entity (added for speed system)
    attention_sprite_id = nil  -- Rendering ID for sprite indicator
  }

  return true
end

-- Get machine data by unit number
-- @param unit_number number - Entity unit number
-- @return table|nil - Machine data or nil if not found
function AttentionStorage.get_machine(unit_number)
  return storage.machines[unit_number]
end

-- Update attention value for a machine
-- @param unit_number number - Entity unit number
-- @param new_attention number - New attention value
function AttentionStorage.update_attention(unit_number, new_attention)
  local machine = storage.machines[unit_number]
  if machine then
    machine.attention = new_attention
  end
end

-- Set interpolation state for a machine
-- @param unit_number number - Entity unit number
-- @param target number - Target attention value
-- @param progress number - Interpolation progress [0.0, 1.0]
function AttentionStorage.set_interpolation(unit_number, target, progress)
  local machine = storage.machines[unit_number]
  if machine then
    machine.target_attention = target
    machine.interpolation_progress = progress
  end
end

-- Update has_attention state
-- @param unit_number number - Entity unit number
-- @param has_attention boolean - New state
function AttentionStorage.set_has_attention(unit_number, has_attention)
  local machine = storage.machines[unit_number]
  if machine then
    machine.has_attention = has_attention
  end
end

-- Remove a machine from tracking
-- @param unit_number number - Entity unit number
-- @return boolean - True if removed, false if not found
function AttentionStorage.remove_machine(unit_number)
  if storage.machines[unit_number] then
    storage.machines[unit_number] = nil
    return true
  end
  return false
end

-- Iterator for all tracked machines
-- @return iterator - Pairs iterator (unit_number, machine_data)
function AttentionStorage.iterate()
  return pairs(storage.machines)
end

-- Count total tracked machines
-- @return number - Total count
function AttentionStorage.count()
  local count = 0
  for _ in pairs(storage.machines) do
    count = count + 1
  end
  return count
end

-- Validate all entities and remove invalid ones
-- Call this on configuration changes or periodically
-- @param cleanup_beacon_fn function|nil - Optional function to clean up beacons
-- @return number - Number of invalid entities removed
function AttentionStorage.validate_all(cleanup_beacon_fn)
  local removed = 0
  local to_remove = {}

  for unit_number, machine in pairs(storage.machines) do
    if not machine.entity or not machine.entity.valid then
      table.insert(to_remove, {unit_number = unit_number, machine = machine})
    end
  end

  for _, entry in ipairs(to_remove) do
    -- Clean up beacon if cleanup function provided
    if cleanup_beacon_fn and entry.machine.attention_beacon then
      cleanup_beacon_fn(entry.machine)
    end

    -- Clean up rendering object
    if entry.machine.attention_sprite_id then
      entry.machine.attention_sprite_id:destroy()
    end

    storage.machines[entry.unit_number] = nil
    removed = removed + 1
  end

  return removed
end

return AttentionStorage
