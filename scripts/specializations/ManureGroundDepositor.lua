--
-- ManureGroundDepositor
--
-- Author: Sławek Jaskulski
-- Copyright (C) ModNext, All Rights Reserved.
--

local modName = g_currentModName

ManureGroundDepositor = {}

---Checks if all prerequisite specializations are loaded
-- @param table specializations specializations
-- @return boolean hasPrerequisite true if all prerequisite specializations are loaded
function ManureGroundDepositor.prerequisitesPresent(specializations)
  return SpecializationUtil.hasSpecialization(Sprayer, specializations) and SpecializationUtil.hasSpecialization(FillUnit, specializations) and SpecializationUtil.hasSpecialization(WorkArea, specializations)
end

---Register functions
-- @param table vehicleType vehicle type
function ManureGroundDepositor.registerFunctions(vehicleType)
  SpecializationUtil.registerFunction(vehicleType, "getGroundTextureData", ManureGroundDepositor.getGroundTextureData)
  SpecializationUtil.registerFunction(vehicleType, "getGroundTextureOperations", ManureGroundDepositor.getGroundTextureOperations)
  SpecializationUtil.registerFunction(vehicleType, "captureGroundTextures", ManureGroundDepositor.captureGroundTextures)
  SpecializationUtil.registerFunction(vehicleType, "restoreGroundTextures", ManureGroundDepositor.restoreGroundTextures)
  SpecializationUtil.registerFunction(vehicleType, "finishConsumptionTracking", ManureGroundDepositor.finishConsumptionTracking)
  SpecializationUtil.registerFunction(vehicleType, "depositConsumedManure", ManureGroundDepositor.depositConsumedManure)
  SpecializationUtil.registerFunction(vehicleType, "getIsLineOnField", ManureGroundDepositor.getIsLineOnField)
end

---Register all function overwritings
-- @param table vehicleType vehicle type
function ManureGroundDepositor.registerOverwrittenFunctions(vehicleType)
  SpecializationUtil.registerOverwrittenFunction(vehicleType, "processSprayerArea", ManureGroundDepositor.processSprayerArea)
end

---Register all events that should be called for this specialization
-- @param table vehicleType vehicle type
function ManureGroundDepositor.registerEventListeners(vehicleType)
  SpecializationUtil.registerEventListener(vehicleType, "onPreLoad", ManureGroundDepositor)
  SpecializationUtil.registerEventListener(vehicleType, "onLoad", ManureGroundDepositor)
  SpecializationUtil.registerEventListener(vehicleType, "onDelete", ManureGroundDepositor)
  SpecializationUtil.registerEventListener(vehicleType, "onStartWorkAreaProcessing", ManureGroundDepositor)
  SpecializationUtil.registerEventListener(vehicleType, "onEndWorkAreaProcessing", ManureGroundDepositor)
  SpecializationUtil.registerEventListener(vehicleType, "onTurnedOff", ManureGroundDepositor)
  SpecializationUtil.registerEventListener(vehicleType, "onPreDetach", ManureGroundDepositor)
end

---Initializes state before asynchronous vehicle loading starts
function ManureGroundDepositor:onPreLoad(_)
  local spec = self["spec_" .. modName .. ".manureGroundDepositor"]
  self.spec_manureGroundDepositor = spec

  spec.sourceVehicle = nil
  spec.sourceFillUnitIndex = nil
  spec.sourceFillLevel = 0
  spec.externalUsage = 0
  spec.applicationAreas = {}
  spec.groundTextureAreas = {}
  spec.capturedManureGroundType = nil
  spec.fieldRemainderLiters = 0
  spec.fieldPixels = 0
  spec.totalPixels = 0
  spec.scatterSequenceIndex = 0
  spec.groundFillType = nil
  spec.minimumPlacementLiters = 0
end

---Completes initialization after the vehicle model has loaded
function ManureGroundDepositor:onLoad(_)
  local spec = self.spec_manureGroundDepositor
  spec.groundFillType = g_fillTypeManager:getFillTypeIndexByName("MANURE_DIRTY")

  if spec.groundFillType ~= nil and g_densityMapHeightManager ~= nil and g_densityMapHeightManager:getIsValid() then
    spec.minimumPlacementLiters = math.max(6, g_densityMapHeightManager:getMinValidLiterValue(spec.groundFillType) or 0)
  end
end

---Called on start work area processing
function ManureGroundDepositor:onStartWorkAreaProcessing()
  self:captureGroundTextures()

  if not self.isServer then
    return
  end

  local spec = self.spec_manureGroundDepositor
  local sprayerSpec = self.spec_sprayer
  local parameters = sprayerSpec.workAreaParameters

  table.clear(spec.applicationAreas)
  spec.sourceVehicle = nil
  spec.sourceFillUnitIndex = nil
  spec.sourceFillLevel = 0
  spec.externalUsage = 0
  spec.fieldPixels = 0
  spec.totalPixels = 0

  if not sprayerSpec.isManureSpreader or parameters.sprayFillType ~= FillType.MANURE then
    spec.fieldRemainderLiters = 0
    return
  end

  local sourceVehicle = parameters.sprayVehicle
  local sourceFillUnitIndex = parameters.sprayVehicleFillUnitIndex

  if sourceVehicle == nil or sourceFillUnitIndex == nil then
    if self:getIsAIActive() and self:getIsSprayerExternallyFilled() and parameters.usage > 0 then
      spec.externalUsage = parameters.usage
    else
      spec.fieldRemainderLiters = 0
      return
    end
  else
    if sourceVehicle:getFillUnitFillType(sourceFillUnitIndex) ~= FillType.MANURE then
      spec.fieldRemainderLiters = 0
      return
    end

    spec.sourceVehicle = sourceVehicle
    spec.sourceFillUnitIndex = sourceFillUnitIndex
    spec.sourceFillLevel = sourceVehicle:getFillUnitFillLevel(sourceFillUnitIndex)
  end

  if spec.minimumPlacementLiters <= 0 and spec.groundFillType ~= nil and g_densityMapHeightManager ~= nil and g_densityMapHeightManager:getIsValid() then
    spec.minimumPlacementLiters = math.max(6, g_densityMapHeightManager:getMinValidLiterValue(spec.groundFillType) or 0)
  end
end

---Records the ground areas processed by the Sprayer specialization
-- @param function superFunc super function
-- @param table workArea work area
-- @param float dt time since last call in ms
-- @return float changedArea changed area
-- @return float totalArea total area
function ManureGroundDepositor:processSprayerArea(superFunc, workArea, dt)
  local changedArea, totalArea = superFunc(self, workArea, dt)
  local sprayerSpec = self.spec_sprayer
  local parameters = sprayerSpec.workAreaParameters
  local showGroundTexture = g_manureGroundSystem ~= nil and not g_manureGroundSystem:getHideGroundTexture() and not g_modIsLoaded["FS25_precisionFarming"]

  if showGroundTexture and sprayerSpec.isManureSpreader and parameters.sprayFillType == FillType.MANURE and parameters.isActive then
    local sprayType = g_sprayTypeManager:getSprayTypeByIndex(parameters.sprayType)

    if sprayType ~= nil and sprayType.sprayGroundType ~= nil and sprayType.sprayGroundType > 0 then
      local startX, _, startZ = getWorldTranslation(workArea.start)
      local widthX, _, widthZ = getWorldTranslation(workArea.width)
      local heightX, _, heightZ = getWorldTranslation(workArea.height)

      FSDensityMapUtil.setGroundTypeLayerArea(startX, startZ, widthX, widthZ, heightX, heightZ, sprayType.sprayGroundType)
    end
  end

  if not self.isServer then
    return changedArea, totalArea
  end

  local spec = self.spec_manureGroundDepositor

  if (spec.sourceVehicle == nil and spec.externalUsage <= 0) or not parameters.isActive then
    return changedArea, totalArea
  end

  local startX, _, startZ = getWorldTranslation(workArea.start)
  local widthX, _, widthZ = getWorldTranslation(workArea.width)
  local heightX, _, heightZ = getWorldTranslation(workArea.height)
  local _, fieldPixels, totalPixels = FSDensityMapUtil.getFieldDensity(startX, startZ, widthX, widthZ, heightX, heightZ)

  if totalPixels == nil or totalPixels <= 0 then
    return changedArea, totalArea
  end

  local sideX = widthX - startX
  local sideZ = widthZ - startZ
  local sideLength = MathUtil.vector2Length(sideX, sideZ)

  if sideLength <= 0.001 then
    return changedArea, totalArea
  end

  spec.applicationAreas[#spec.applicationAreas + 1] = {
    startX = startX,
    startZ = startZ,
    widthX = widthX,
    widthZ = widthZ,
    heightX = heightX,
    heightZ = heightZ,
  }
  spec.fieldPixels = spec.fieldPixels + math.max(fieldPixels or 0, 0)
  spec.totalPixels = spec.totalPixels + totalPixels
  return changedArea, totalArea
end

---Creates the reusable density-map data used to preserve existing ground textures
-- @return table data ground texture data or nil
function ManureGroundDepositor:getGroundTextureData()
  local data = ManureGroundDepositor.groundTextureData

  if data ~= nil then
    return data
  end

  local fieldGroundSystem = g_currentMission ~= nil and g_currentMission.fieldGroundSystem or nil

  if fieldGroundSystem == nil then
    return nil
  end

  local sprayTypeMapId, sprayTypeFirstChannel, sprayTypeNumChannels = fieldGroundSystem:getDensityMapData(FieldDensityMap.SPRAY_TYPE)
  local sprayTypeMaxValue = fieldGroundSystem:getMaxValue(FieldDensityMap.SPRAY_TYPE)

  if sprayTypeMapId == nil or sprayTypeNumChannels == nil or sprayTypeNumChannels <= 0 or sprayTypeMaxValue == nil then
    return nil
  end

  local snapshotMap = createBitVectorMap("manureGroundTextureSnapshot")
  local hiddenManureMap = createBitVectorMap("manureGroundHiddenManure")
  local densityMapSize = getDensityMapSize(sprayTypeMapId)
  local manureSprayType = g_sprayTypeManager:getSprayTypeByFillTypeIndex(FillType.MANURE)

  if densityMapSize == nil or densityMapSize <= 0 then
    delete(snapshotMap)
    delete(hiddenManureMap)
    return nil
  end

  loadBitVectorMapNew(snapshotMap, densityMapSize, densityMapSize, sprayTypeNumChannels, false)
  loadBitVectorMapNew(hiddenManureMap, densityMapSize, densityMapSize, 1, false)

  data = {
    snapshotMap = snapshotMap,
    hiddenManureMap = hiddenManureMap,
    sprayTypeMapId = sprayTypeMapId,
    sprayTypeFirstChannel = sprayTypeFirstChannel,
    sprayTypeNumChannels = sprayTypeNumChannels,
    sprayTypeMaxValue = sprayTypeMaxValue,
    manureGroundType = manureSprayType ~= nil and manureSprayType.sprayGroundType or nil,
    snapshotModifier = DensityMapModifier.new(snapshotMap, 0, sprayTypeNumChannels, g_terrainNode),
    hiddenManureModifier = DensityMapModifier.new(hiddenManureMap, 0, 1, g_terrainNode),
    hiddenManureFilter = DensityMapFilter.new(hiddenManureMap, 0, 1),
    sprayTypeModifier = DensityMapModifier.new(sprayTypeMapId, sprayTypeFirstChannel, sprayTypeNumChannels, g_terrainNode),
    operations = {},
  }
  data.hiddenManureFilter:setValueCompareParams(DensityValueCompareType.EQUAL, 1)
  ManureGroundDepositor.groundTextureData = data

  return data
end

---Deletes the temporary map used to preserve existing ground textures
function ManureGroundDepositor.deleteGroundTextureData()
  local data = ManureGroundDepositor.groundTextureData

  if data ~= nil then
    delete(data.snapshotMap)
    delete(data.hiddenManureMap)
    ManureGroundDepositor.groundTextureData = nil
  end
end

---Creates batched capture and restore operations for the manure terrain value
-- @param table data ground texture data
-- @param integer manureGroundType manure terrain value
-- @return table operations capture and restore operations
function ManureGroundDepositor:getGroundTextureOperations(data, manureGroundType)
  local operations = data.operations[manureGroundType]

  if operations ~= nil then
    return operations
  end

  operations = {
    capture = DensityMapMultiModifier.new(),
    inject = DensityMapMultiModifier.new(),
    mark = DensityMapMultiModifier.new(),
    clear = DensityMapMultiModifier.new(),
    restore = DensityMapMultiModifier.new(),
  }
  operations.capture:addExecuteSet(0, data.snapshotModifier)

  for groundType = 1, data.sprayTypeMaxValue - 1 do
    local sourceFilter = DensityMapFilter.new(data.sprayTypeMapId, data.sprayTypeFirstChannel, data.sprayTypeNumChannels)
    sourceFilter:setValueCompareParams(DensityValueCompareType.EQUAL, groundType)
    operations.capture:addExecuteSet(groundType, data.snapshotModifier, sourceFilter)

    local snapshotFilter = DensityMapFilter.new(data.snapshotMap, 0, data.sprayTypeNumChannels)
    snapshotFilter:setValueCompareParams(DensityValueCompareType.EQUAL, groundType)
    operations.restore:addExecuteSet(groundType, data.sprayTypeModifier, snapshotFilter)
  end

  local manureFilter = DensityMapFilter.new(data.sprayTypeMapId, data.sprayTypeFirstChannel, data.sprayTypeNumChannels)
  manureFilter:setValueCompareParams(DensityValueCompareType.EQUAL, manureGroundType)
  operations.inject:addExecuteSet(manureGroundType, data.sprayTypeModifier, data.hiddenManureFilter)
  operations.mark:addExecuteSet(1, data.hiddenManureModifier, manureFilter)
  operations.clear:addExecuteSet(0, data.sprayTypeModifier, manureFilter)

  data.operations[manureGroundType] = operations

  return operations
end

---Clears hidden manure markers when the game removes spray data
function ManureGroundDepositor.clearHiddenManureArea(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, blockedSprayTypeIndex, customFilter)
  local data = ManureGroundDepositor.groundTextureData

  if data == nil then
    return
  end

  if blockedSprayTypeIndex ~= nil then
    local blockedSprayType = g_sprayTypeManager:getSprayTypeByIndex(blockedSprayTypeIndex)

    if blockedSprayType ~= nil and data.manureGroundType ~= nil and blockedSprayType.sprayGroundType == data.manureGroundType then
      return
    end
  end

  data.hiddenManureModifier:setParallelogramWorldCoords(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, DensityCoordType.POINT_POINT_POINT)
  data.hiddenManureModifier:executeSet(0, customFilter)
end

---Clears hidden manure markers when another spray layer is applied
function ManureGroundDepositor.clearHiddenManureForGroundType(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ, groundType)
  local data = ManureGroundDepositor.groundTextureData

  if data ~= nil and groundType ~= data.manureGroundType then
    ManureGroundDepositor.clearHiddenManureArea(startWorldX, startWorldZ, widthWorldX, widthWorldZ, heightWorldX, heightWorldZ)
  end
end

---Captures existing ground textures before the spreader changes them
function ManureGroundDepositor:captureGroundTextures()
  local spec = self.spec_manureGroundDepositor
  local sprayerSpec = self.spec_sprayer
  local parameters = sprayerSpec.workAreaParameters

  self:restoreGroundTextures(false)

  if g_manureGroundSystem == nil or not g_manureGroundSystem:getHideGroundTexture() or not sprayerSpec.isManureSpreader or parameters.sprayFillType ~= FillType.MANURE or parameters.sprayFillLevel <= 0 then
    return
  end

  if not self.isServer and self.currentUpdateDistance > Sprayer.CLIENT_DM_UPDATE_RADIUS then
    return
  end

  local sprayType = g_sprayTypeManager:getSprayTypeByIndex(parameters.sprayType)

  if sprayType == nil or sprayType.sprayGroundType == nil or sprayType.sprayGroundType <= 0 then
    return
  end

  local data = self:getGroundTextureData()

  if data == nil then
    return
  end

  if sprayType.sprayGroundType >= data.sprayTypeMaxValue then
    return
  end

  local operations = self:getGroundTextureOperations(data, sprayType.sprayGroundType)
  spec.capturedManureGroundType = sprayType.sprayGroundType

  for _, workArea in ipairs(self:getTypedWorkAreas(WorkAreaType.SPRAYER)) do
    if self:getIsWorkAreaActive(workArea) then
      local startX, _, startZ = getWorldTranslation(workArea.start)
      local widthX, _, widthZ = getWorldTranslation(workArea.width)
      local heightX, _, heightZ = getWorldTranslation(workArea.height)

      operations.capture:updateParallelogramWorldCoords(startX, startZ, widthX, widthZ, heightX, heightZ, DensityCoordType.POINT_POINT_POINT)
      operations.capture:execute()
      operations.inject:updateParallelogramWorldCoords(startX, startZ, widthX, widthZ, heightX, heightZ, DensityCoordType.POINT_POINT_POINT)
      operations.inject:execute()
      spec.groundTextureAreas[#spec.groundTextureAreas + 1] = workArea
    end
  end
end

---Restores previous textures and removes only manure applied during a processed pass
-- @param boolean hasProcessed true if the base work-area pass applied spray data
function ManureGroundDepositor:restoreGroundTextures(hasProcessed)
  local spec = self.spec_manureGroundDepositor

  if spec == nil then
    return
  end

  local data = ManureGroundDepositor.groundTextureData
  local manureGroundType = spec.capturedManureGroundType
  local groundTextureAreas = spec.groundTextureAreas

  if data ~= nil and manureGroundType ~= nil and groundTextureAreas ~= nil then
    local operations = self:getGroundTextureOperations(data, manureGroundType)

    for _, workArea in ipairs(groundTextureAreas) do
      local startX, _, startZ = getWorldTranslation(workArea.start)
      local widthX, _, widthZ = getWorldTranslation(workArea.width)
      local heightX, _, heightZ = getWorldTranslation(workArea.height)

      if hasProcessed then
        operations.mark:updateParallelogramWorldCoords(startX, startZ, widthX, widthZ, heightX, heightZ, DensityCoordType.POINT_POINT_POINT)
        operations.mark:execute()
      end

      operations.clear:updateParallelogramWorldCoords(startX, startZ, widthX, widthZ, heightX, heightZ, DensityCoordType.POINT_POINT_POINT)
      operations.clear:execute()
      operations.restore:updateParallelogramWorldCoords(startX, startZ, widthX, widthZ, heightX, heightZ, DensityCoordType.POINT_POINT_POINT)
      operations.restore:execute()
    end
  end

  if groundTextureAreas ~= nil then
    table.clear(groundTextureAreas)
  end

  spec.capturedManureGroundType = nil
end

---Called on end work area processing
function ManureGroundDepositor:onEndWorkAreaProcessing(_, _)
  self:restoreGroundTextures(self.spec_sprayer.workAreaParameters.isActive)

  if not self.isServer then
    return
  end

  self:finishConsumptionTracking()
end

---Called before detaching
function ManureGroundDepositor:onPreDetach(_, _)
  self:restoreGroundTextures(false)

  if self.isServer then
    self:finishConsumptionTracking()
    self.spec_manureGroundDepositor.fieldRemainderLiters = 0
  end
end

---Called when the spreader is turned off
function ManureGroundDepositor:onTurnedOff()
  self:restoreGroundTextures(false)

  if self.isServer then
    self:finishConsumptionTracking()
    self.spec_manureGroundDepositor.fieldRemainderLiters = 0
  end
end

---Finishes fill level tracking for the current work area pass
function ManureGroundDepositor:finishConsumptionTracking()
  if not self.isServer then
    return
  end

  local spec = self.spec_manureGroundDepositor
  local sourceVehicle = spec.sourceVehicle
  local consumedLiters = spec.externalUsage

  if sourceVehicle ~= nil and not sourceVehicle.isDeleted and spec.sourceFillUnitIndex ~= nil then
    local remainingFillLevel = sourceVehicle:getFillUnitFillLevel(spec.sourceFillUnitIndex)
    consumedLiters = math.max(spec.sourceFillLevel - remainingFillLevel, 0)
  end

  if consumedLiters > 0 then
    self:depositConsumedManure(consumedLiters)
  end

  spec.sourceVehicle = nil
  spec.sourceFillUnitIndex = nil
  spec.sourceFillLevel = 0
  spec.externalUsage = 0
  spec.fieldPixels = 0
  spec.totalPixels = 0
  table.clear(spec.applicationAreas)
end

---Called when the spreader is deleted
function ManureGroundDepositor:onDelete()
  local spec = self.spec_manureGroundDepositor

  if spec == nil then
    return
  end

  self:restoreGroundTextures(false)

  if self.isServer then
    if spec.applicationAreas ~= nil then
      table.clear(spec.applicationAreas)
    end

    spec.fieldRemainderLiters = 0
    spec.fieldPixels = 0
    spec.totalPixels = 0
    spec.sourceVehicle = nil
    spec.sourceFillUnitIndex = nil
    spec.sourceFillLevel = 0
    spec.externalUsage = 0
  end
end

---Deposits the field-covered share of consumed manure across the working width
-- @param float consumedLiters consumed manure in liters
function ManureGroundDepositor:depositConsumedManure(consumedLiters)
  if not self.isServer then
    return
  end

  local spec = self.spec_manureGroundDepositor
  local applicationAreas = spec.applicationAreas
  local minimumPlacementLiters = spec.minimumPlacementLiters
  local groundHeightType = g_densityMapHeightManager ~= nil and g_densityMapHeightManager:getIsValid() and g_densityMapHeightManager:getDensityMapHeightTypeByFillTypeIndex(spec.groundFillType) or nil

  if groundHeightType == nil or minimumPlacementLiters <= 0 or #applicationAreas == 0 or spec.fieldPixels <= 0 or spec.totalPixels <= 0 then
    spec.fieldRemainderLiters = 0
    return
  end

  local fieldFactor = math.clamp(spec.fieldPixels / spec.totalPixels, 0, 1)
  local availableLiters = spec.fieldRemainderLiters + consumedLiters * fieldFactor
  local requestedPiles = math.floor(availableLiters / minimumPlacementLiters)
  spec.fieldRemainderLiters = availableLiters

  if requestedPiles == 0 then
    return
  end

  local sideDirectionX, _, sideDirectionZ = localDirectionToWorld(self.rootNode, 1, 0, 0)
  local sideDirectionLength = MathUtil.vector2Length(sideDirectionX, sideDirectionZ)

  if sideDirectionLength <= 0.001 then
    return
  end

  sideDirectionX = sideDirectionX / sideDirectionLength
  sideDirectionZ = sideDirectionZ / sideDirectionLength

  local minSideOffset = math.huge
  local maxSideOffset = -math.huge

  for _, area in ipairs(applicationAreas) do
    local fourthX = area.widthX + area.heightX - area.startX
    local fourthZ = area.widthZ + area.heightZ - area.startZ
    local startOffset = area.startX * sideDirectionX + area.startZ * sideDirectionZ
    local widthOffset = area.widthX * sideDirectionX + area.widthZ * sideDirectionZ
    local heightOffset = area.heightX * sideDirectionX + area.heightZ * sideDirectionZ
    local fourthOffset = fourthX * sideDirectionX + fourthZ * sideDirectionZ

    area.minSideOffset = math.min(startOffset, widthOffset, heightOffset, fourthOffset)
    area.maxSideOffset = math.max(startOffset, widthOffset, heightOffset, fourthOffset)
    minSideOffset = math.min(minSideOffset, area.minSideOffset)
    maxSideOffset = math.max(maxSideOffset, area.maxSideOffset)
  end

  local workingWidth = maxSideOffset - minSideOffset

  if workingWidth <= 0.001 then
    return
  end

  local maxDepositCount = 20
  local pileHalfLength = 0.1
  local pileRadius = 0.35
  local depositPositions = table.create(maxDepositCount * 2)
  local depositCount = 0
  local targetDepositCount = math.min(requestedPiles, maxDepositCount)

  for _ = 1, maxDepositCount do
    local sequenceIndex = spec.scatterSequenceIndex
    local columnIndex = math.floor(sequenceIndex / 2)

    if sequenceIndex % 2 == 1 then
      columnIndex = maxDepositCount - 1 - columnIndex
    end

    spec.scatterSequenceIndex = (sequenceIndex + 1) % maxDepositCount

    for _ = 1, 12 do
      local sideFactor = (columnIndex + math.random()) / maxDepositCount
      local sideOffset = minSideOffset + sideFactor * workingWidth
      local centerX = nil
      local centerZ = nil
      local selectedArea = nil
      local selectedSideOffset = sideOffset
      local nearestDistance = math.huge

      for _, area in ipairs(applicationAreas) do
        local sideLength = area.maxSideOffset - area.minSideOffset

        if sideLength > 0.001 then
          local clampedOffset = math.clamp(sideOffset, area.minSideOffset, area.maxSideOffset)
          local distance = math.abs(sideOffset - clampedOffset)

          if distance < nearestDistance then
            selectedArea = area
            selectedSideOffset = clampedOffset
            nearestDistance = distance

            if distance <= 0.001 then
              break
            end
          end
        end
      end

      if selectedArea ~= nil then
        local heightFactor = math.random()
        local heightX = (selectedArea.heightX - selectedArea.startX) * heightFactor
        local heightZ = (selectedArea.heightZ - selectedArea.startZ) * heightFactor
        local sliceStartX = selectedArea.startX + heightX
        local sliceStartZ = selectedArea.startZ + heightZ
        local sliceEndX = selectedArea.widthX + heightX
        local sliceEndZ = selectedArea.widthZ + heightZ
        local sliceStartOffset = sliceStartX * sideDirectionX + sliceStartZ * sideDirectionZ
        local sliceEndOffset = sliceEndX * sideDirectionX + sliceEndZ * sideDirectionZ
        local sliceWidth = sliceEndOffset - sliceStartOffset

        if math.abs(sliceWidth) > 0.001 then
          local sliceFactor = (selectedSideOffset - sliceStartOffset) / sliceWidth

          if sliceFactor >= 0 and sliceFactor <= 1 then
            centerX = sliceStartX + (sliceEndX - sliceStartX) * sliceFactor
            centerZ = sliceStartZ + (sliceEndZ - sliceStartZ) * sliceFactor
          end
        end
      end

      if centerX ~= nil then
        local startX = centerX - sideDirectionX * pileHalfLength
        local startZ = centerZ - sideDirectionZ * pileHalfLength
        local endX = centerX + sideDirectionX * pileHalfLength
        local endZ = centerZ + sideDirectionZ * pileHalfLength

        if self:getIsLineOnField(startX, startZ, endX, endZ) then
          depositCount = depositCount + 1
          depositPositions[depositCount * 2 - 1] = centerX
          depositPositions[depositCount * 2] = centerZ
          break
        end
      end
    end

    if depositCount == targetDepositCount then
      break
    end
  end

  if depositCount == 0 then
    return
  end

  local pileLiters = requestedPiles * minimumPlacementLiters / depositCount
  local tireTrackSystem = g_currentMission.tireTrackSystem
  local tireTrackSystemId = tireTrackSystem.tireTrackSystemId

  tireTrackSystem.tireTrackSystemId = 0

  for index = 1, depositCount do
    local centerX = depositPositions[index * 2 - 1]
    local centerZ = depositPositions[index * 2]
    local startX = centerX - sideDirectionX * pileHalfLength
    local startZ = centerZ - sideDirectionZ * pileHalfLength
    local endX = centerX + sideDirectionX * pileHalfLength
    local endZ = centerZ + sideDirectionZ * pileHalfLength
    local startY = getTerrainHeightAtWorldPos(g_terrainNode, startX, 0, startZ)
    local endY = getTerrainHeightAtWorldPos(g_terrainNode, endX, 0, endZ)

    local placedLiters = DensityMapHeightUtil.tipToGroundAroundLine(self, pileLiters, spec.groundFillType, startX, startY, startZ, endX, endY, endZ, 0, pileRadius, nil, false, nil, false, true)
    placedLiters = math.clamp(placedLiters or 0, 0, pileLiters)
    spec.fieldRemainderLiters = math.max(spec.fieldRemainderLiters - placedLiters, 0)
  end

  tireTrackSystem.tireTrackSystemId = tireTrackSystemId
end

---Checks if the full deposit line is on a field
-- @param float startX start world x
-- @param float startZ start world z
-- @param float endX end world x
-- @param float endZ end world z
-- @return boolean isOnField true if the full line is on a field
function ManureGroundDepositor:getIsLineOnField(startX, startZ, endX, endZ)
  for step = 0, 2 do
    local factor = step / 2
    local x = startX + factor * (endX - startX)
    local z = startZ + factor * (endZ - startZ)

    if not FSDensityMapUtil.getFieldDataAtWorldPosition(x, 0, z) then
      return false
    end
  end

  return true
end
