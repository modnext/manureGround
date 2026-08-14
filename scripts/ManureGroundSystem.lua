--
-- ManureGroundSystem
--
-- Author: Sławek Jaskulski
-- Copyright (C) ModNext, All Rights Reserved.
--

ManureGroundSystem = {}

local ManureGroundSystem_mt = Class(ManureGroundSystem)

---Creates a new manure ground system instance
-- @return table self system instance
function ManureGroundSystem.new()
  local self = setmetatable({}, ManureGroundSystem_mt)

  self.hideGroundTexture = false
  self.settingsElement = nil

  return self
end

---Returns whether the standard manure ground texture should be hidden
-- @return boolean hideGroundTexture hide standard manure ground texture
function ManureGroundSystem:getHideGroundTexture()
  return self.hideGroundTexture
end

---Sets whether the standard manure ground texture should be hidden
-- @param boolean hideGroundTexture hide standard manure ground texture
function ManureGroundSystem:setHideGroundTexture(hideGroundTexture)
  local normalizedValue = hideGroundTexture == true
  local hasChanged = self.hideGroundTexture ~= normalizedValue

  self.hideGroundTexture = normalizedValue

  if hasChanged and not self.hideGroundTexture then
    ManureGroundDepositor.deleteGroundTextureData()
  end

  if self.settingsElement ~= nil and self.settingsElement:getIsChecked() ~= self.hideGroundTexture then
    self.settingsElement:setIsChecked(self.hideGroundTexture, true)
  end

  return hasChanged
end

---Applies the setting on the server
-- @param boolean hideGroundTexture hide standard manure ground texture
function ManureGroundSystem:applyServerSetting(hideGroundTexture)
  if g_currentMission == nil or not g_currentMission:getIsServer() then
    return false
  end

  return self:setHideGroundTexture(hideGroundTexture)
end

---Called when the map is loaded
function ManureGroundSystem:loadMap()
  local settingsKey = "careerSavegame.settings.hideGroundTexture"

  self.settingsElement = nil
  self.hideGroundTexture = false
  ManureGroundDepositor.deleteGroundTextureData()

  if not g_currentMission:getIsServer() or g_currentMission.missionInfo.savegameDirectory == nil then
    return
  end

  local xmlFile = XMLFile.loadIfExists("ManureGroundCareerSavegameXML", g_currentMission.missionInfo.savegameDirectory .. "/careerSavegame.xml")

  if xmlFile ~= nil then
    self:setHideGroundTexture(xmlFile:getBool(settingsKey, false))
    xmlFile:delete()
  end
end

---Called when the map is deleted
function ManureGroundSystem:deleteMap()
  self.hideGroundTexture = false
  self.settingsElement = nil
  ManureGroundDepositor.deleteGroundTextureData()
end

---Creates the Manure Ground section in the game settings
-- @param table frame game settings frame
function ManureGroundSystem:createSettingsElements(frame)
  if frame == nil or frame.gameSettingsLayout == nil or frame.checkLimeRequired == nil then
    Logging.warning("FS25_manureGround: failed to create game settings elements")
    return
  end

  local layout = frame.gameSettingsLayout

  for _, element in ipairs(layout.elements) do
    if element:isa(TextElement) then
      element:clone(layout):setText(g_i18n:getText("manureGround_ui_header"))
      break
    end
  end

  local settingBox = frame.checkLimeRequired.parent:clone(layout, false)
  local settingElement = settingBox.elements[1]

  self.settingsElement = settingElement

  function settingElement.onClickCallback(_, state, element)
    g_manureGroundSystem:onClickHideGroundTexture(state, element)
  end

  settingElement:setIsChecked(self.hideGroundTexture, true)
  settingElement:updateSelection()
  settingBox.elements[2]:setText(g_i18n:getText("manureGround_settingTitle_hideGroundTexture"))
  settingElement.elements[1]:setText(g_i18n:getText("manureGround_settingDescription_hideGroundTexture"))
end

---Updates the Manure Ground setting when the settings frame is opened
-- @param table frame game settings frame
function ManureGroundSystem:onSettingsFrameOpen(frame)
  if g_currentMission == nil or not g_currentMission:getIsServer() then
    return
  end

  if self.settingsElement == nil then
    self:createSettingsElements(frame)
  end

  if self.settingsElement ~= nil then
    self.settingsElement:setIsChecked(self.hideGroundTexture, true)
    self.settingsElement:setDisabled(false)
    frame:updateAlternatingElements(frame.gameSettingsLayout)
  end
end

---Requests a change of the standard manure texture setting
-- @param integer state checkbox state
-- @param table element checkbox element
function ManureGroundSystem:onClickHideGroundTexture(state, element)
  if element ~= self.settingsElement then
    return
  end

  ManureGroundSettingsEvent.sendEvent(state == CheckedOptionElement.STATE_CHECKED)
end

---
FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(FSCareerMissionInfo.saveToXMLFile, function(missionInfo)
  local settingsKey = "careerSavegame.settings.hideGroundTexture"

  if g_currentMission ~= nil and missionInfo == g_currentMission.missionInfo and g_currentMission:getIsServer() and missionInfo.xmlFile ~= nil and missionInfo.xmlFile ~= 0 then
    setXMLBool(missionInfo.xmlFile, settingsKey, g_manureGroundSystem:getHideGroundTexture())
  end
end)

---
FSBaseMission.sendInitialClientState = Utils.appendedFunction(FSBaseMission.sendInitialClientState, function(mission, connection)
  if mission:getIsServer() then
    connection:sendEvent(ManureGroundSettingsEvent.new(g_manureGroundSystem:getHideGroundTexture()))
  end
end)

---
InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuSettingsFrame.onFrameOpen, function(frame)
  g_manureGroundSystem:onSettingsFrameOpen(frame)
end)

---
g_manureGroundSystem = ManureGroundSystem.new()
addModEventListener(g_manureGroundSystem)
