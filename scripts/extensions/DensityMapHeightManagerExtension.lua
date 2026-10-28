--
-- DensityMapHeightManagerExtension
--
-- Author: Sławek Jaskulski
-- Copyright (C) ModNext, All Rights Reserved.
--

DensityMapHeightManagerExtension = {}

---Normalizes MANURE_DIRTY visual heights and keeps its final index consistent on server and clients
function DensityMapHeightManagerExtension.initialize(self, superFunc, ...)
  local heightType = self:getDensityMapHeightTypeByFillTypeName("MANURE_DIRTY")

  if heightType == nil then
    return superFunc(self, ...)
  end

  local terrainDetailHeightId = g_currentMission.terrainDetailHeightId
  local mappings = heightType.visualHeightMapping

  if terrainDetailHeightId ~= nil and terrainDetailHeightId ~= 0 and mappings ~= nil and #mappings > 0 then
    local heightNumChannels = getDensityMapHeightNumChannels(terrainDetailHeightId)
    local mapMaxHeight = getDensityMapMaxHeight(terrainDetailHeightId)

    if heightNumChannels ~= nil and mapMaxHeight ~= nil and mapMaxHeight > 0 then
      local referenceHeightNumChannels = 6
      local referenceMaxHeight = 4
      local maxMappingValue = 2 ^ heightNumChannels
      local valueScale = 2 ^ (heightNumChannels - referenceHeightNumChannels) * referenceMaxHeight / mapMaxHeight

      for _, mapping in ipairs(mappings) do
        mapping.realValue = math.clamp(MathUtil.round(mapping.realValue * valueScale), 1, maxMappingValue)
        mapping.visualValue = math.clamp(MathUtil.round(mapping.visualValue * valueScale), 1, maxMappingValue)
      end

      if math.abs(valueScale - 1) > 0.0001 then
        Logging.info("FS25_manureGround: normalized MANURE_DIRTY visual height mapping for %d height channels and %.3f m map height", heightNumChannels, mapMaxHeight)
      end
    end
  end

  if heightType.index < #self.heightTypes then
    table.remove(self.heightTypes, heightType.index)
    table.insert(self.heightTypes, heightType)
    table.clear(self.heightTypeIndexToFillTypeIndex)

    for index, entry in ipairs(self.heightTypes) do
      entry.index = index
      self.heightTypeIndexToFillTypeIndex[index] = entry.fillTypeIndex
    end
  end

  return superFunc(self, ...)
end

---
DensityMapHeightManager.initialize = Utils.overwrittenFunction(DensityMapHeightManager.initialize, DensityMapHeightManagerExtension.initialize)
