--
-- ManureGroundSettingsEvent
--
-- Author: Sławek Jaskulski
-- Copyright (C) ModNext, All Rights Reserved.
--

ManureGroundSettingsEvent = {}

local ManureGroundSettingsEvent_mt = Class(ManureGroundSettingsEvent, Event)

InitEventClass(ManureGroundSettingsEvent, "ManureGroundSettingsEvent")

---Creates an empty event
-- @return table self event instance
function ManureGroundSettingsEvent.emptyNew()
  return Event.new(ManureGroundSettingsEvent_mt)
end

---Creates a settings event
-- @param boolean hideGroundTexture true to hide the standard manure ground texture
-- @return table self event instance
function ManureGroundSettingsEvent.new(hideGroundTexture)
  local self = ManureGroundSettingsEvent.emptyNew()
  self.hideGroundTexture = hideGroundTexture == true

  return self
end

---Reads the setting value
-- @param integer streamId stream id
-- @param table connection connection
function ManureGroundSettingsEvent:readStream(streamId, connection)
  self.hideGroundTexture = streamReadBool(streamId)

  self:run(connection)
end

---Writes the server setting
-- @param integer streamId stream id
-- @param table connection connection
function ManureGroundSettingsEvent:writeStream(streamId, _)
  streamWriteBool(streamId, self.hideGroundTexture)
end

---Applies a setting change
-- @param table connection connection
function ManureGroundSettingsEvent:run(connection)
  if connection:getIsServer() then
    g_manureGroundSystem:setHideGroundTexture(self.hideGroundTexture)
    return
  end

  connection:sendEvent(ManureGroundSettingsEvent.new(g_manureGroundSystem:getHideGroundTexture()))
end

---Sends a setting change to the server or all clients
-- @param boolean hideGroundTexture true to hide the standard manure ground texture
function ManureGroundSettingsEvent.sendEvent(hideGroundTexture)
  if g_server ~= nil then
    if g_manureGroundSystem:applyServerSetting(hideGroundTexture) then
      g_server:broadcastEvent(ManureGroundSettingsEvent.new(g_manureGroundSystem:getHideGroundTexture()), false)
    end
  end
end
