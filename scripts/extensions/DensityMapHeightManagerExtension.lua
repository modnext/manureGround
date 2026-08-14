--
-- DensityMapHeightManagerExtension
--
-- Author: Sławek Jaskulski
-- Copyright (C) ModNext, All Rights Reserved.
--

DensityMapHeightManagerExtension = {}

---Keeps the MANURE_DIRTY height type at the same final index on server and clients
function DensityMapHeightManagerExtension.initialize(self, superFunc, ...)
  local heightType = self:getDensityMapHeightTypeByFillTypeName("MANURE_DIRTY")

  local referenceHeightNumChannels = 6
  local referenceMaxHeight = 4

  if heightType ~= nil then
    local terrainDetailHeightId = g_currentMission ~= nil and g_currentMission.terrainDetailHeightId or nil
    local mappings = heightType.visualHeightMapping

    if terrainDetailHeightId ~= nil and terrainDetailHeightId ~= 0 and mappings ~= nil and #mappings > 0 then
      local heightNumChannels = getDensityMapHeightNumChannels(terrainDetailHeightId)
      local mapMaxHeight = getDensityMapMaxHeight(terrainDetailHeightId)

      if heightNumChannels ~= nil and mapMaxHeight ~= nil and mapMaxHeight > 0 then
        local maxFillLevel = 2 ^ heightNumChannels
        local valueScale = 2 ^ (heightNumChannels - referenceHeightNumChannels) * referenceMaxHeight / mapMaxHeight

        for _, mapping in ipairs(mappings) do
          mapping.realValue = math.min(maxFillLevel, math.max(1, math.floor(mapping.realValue * valueScale + 0.5)))
          mapping.visualValue = math.min(maxFillLevel, math.max(1, math.floor(mapping.visualValue * valueScale + 0.5)))
        end

        if math.abs(valueScale - 1) > 0.0001 then
          Logging.info("FS25_manureGround: normalized MANURE_DIRTY visual height mapping for %d height channels and %.3f m map height", heightNumChannels, mapMaxHeight)
        end
      end
    end

    local heightTypePosition = nil

    for index, entry in ipairs(self.heightTypes) do
      if entry == heightType then
        heightTypePosition = index
        break
      end
    end

    if heightTypePosition ~= nil and heightTypePosition < #self.heightTypes then
      table.remove(self.heightTypes, heightTypePosition)
      table.insert(self.heightTypes, heightType)
      table.clear(self.heightTypeIndexToFillTypeIndex)

      for index, entry in ipairs(self.heightTypes) do
        entry.index = index
        self.heightTypeIndexToFillTypeIndex[index] = entry.fillTypeIndex
      end
    end
  end

  return superFunc(self, ...)
end

---
DensityMapHeightManager.initialize = Utils.overwrittenFunction(DensityMapHeightManager.initialize, DensityMapHeightManagerExtension.initialize)
