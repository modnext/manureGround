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
  spec.fieldRemainderLiters = 0
  spec.fieldPixels = 0
  spec.totalPixels = 0
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
  local parameters = self.spec_sprayer.workAreaParameters

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

  if MathUtil.vector2LengthSq(widthX - startX, widthZ - startZ) <= 0.000001 then
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

---Called on end work area processing
function ManureGroundDepositor:onEndWorkAreaProcessing(_, _)
  if not self.isServer then
    return
  end

  self:finishConsumptionTracking()
end

---Called before detaching
function ManureGroundDepositor:onPreDetach(_, _)
  if self.isServer then
    self:finishConsumptionTracking()
    self.spec_manureGroundDepositor.fieldRemainderLiters = 0
  end
end

---Called when the spreader is turned off
function ManureGroundDepositor:onTurnedOff()
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
  local canTipToGround = spec.groundFillType ~= nil and g_densityMapHeightManager ~= nil and DensityMapHeightUtil.getCanTipToGround(spec.groundFillType)

  if not canTipToGround or minimumPlacementLiters <= 0 or #applicationAreas == 0 or spec.fieldPixels <= 0 or spec.totalPixels <= 0 then
    spec.fieldRemainderLiters = 0
    return
  end

  local tireTrackSystem = g_currentMission ~= nil and g_currentMission.tireTrackSystem or nil

  if tireTrackSystem == nil then
    spec.fieldRemainderLiters = 0
    return
  end

  local fieldFactor = math.clamp(spec.fieldPixels / spec.totalPixels, 0, 1)
  local availableLiters = spec.fieldRemainderLiters + consumedLiters * fieldFactor
  local pileCountMultiplier = 1.5
  local requestedPiles = math.floor(availableLiters * pileCountMultiplier / minimumPlacementLiters)
  local minimumDepositCount = 4
  spec.fieldRemainderLiters = availableLiters

  if requestedPiles < minimumDepositCount then
    return
  end

  local firstArea = applicationAreas[1]
  local sideDirectionX, sideDirectionZ = MathUtil.vector2Normalize(firstArea.widthX - firstArea.startX, firstArea.widthZ - firstArea.startZ)

  local maxDepositCount = 20
  local pileHalfLength = 0.1
  local pileRadius = 0.35
  local depositPositions = table.create(maxDepositCount * 2)
  local depositCount = 0
  local targetDepositCount = math.min(requestedPiles, maxDepositCount)
  local sideSpacing = 1 / (targetDepositCount - 1)
  local heightIndices = table.create(targetDepositCount)

  for index = 1, targetDepositCount do
    heightIndices[index] = index - 1
  end

  Utils.shuffle(heightIndices)

  for sideIndex = 0, targetDepositCount - 1 do
    local heightIndex = heightIndices[sideIndex + 1]
    local baseSideFactor = sideIndex * sideSpacing

    if baseSideFactor < 0.5 then
      baseSideFactor = 2 * baseSideFactor * baseSideFactor
    else
      local inverseSideFactor = 1 - baseSideFactor
      baseSideFactor = 1 - 2 * inverseSideFactor * inverseSideFactor
    end

    for _ = 1, 12 do
      local heightFactor = (heightIndex + math.random()) / targetDepositCount
      local minSideOffset = math.huge
      local maxSideOffset = -math.huge
      local centerX = nil
      local centerZ = nil

      for _, area in ipairs(applicationAreas) do
        local heightX = (area.heightX - area.startX) * heightFactor
        local heightZ = (area.heightZ - area.startZ) * heightFactor
        area.sliceStartX = area.startX + heightX
        area.sliceStartZ = area.startZ + heightZ
        area.sliceEndX = area.widthX + heightX
        area.sliceEndZ = area.widthZ + heightZ
        area.sliceStartOffset = area.sliceStartX * sideDirectionX + area.sliceStartZ * sideDirectionZ
        area.sliceEndOffset = area.sliceEndX * sideDirectionX + area.sliceEndZ * sideDirectionZ
        area.minSideOffset = math.min(area.sliceStartOffset, area.sliceEndOffset)
        area.maxSideOffset = math.max(area.sliceStartOffset, area.sliceEndOffset)
        minSideOffset = math.min(minSideOffset, area.minSideOffset)
        maxSideOffset = math.max(maxSideOffset, area.maxSideOffset)
      end

      local workingWidth = maxSideOffset - minSideOffset

      if workingWidth > 0.001 then
        local sideMargin = math.min(pileHalfLength / workingWidth, 0.5)
        local sideFactor = baseSideFactor
        local usableWidth = workingWidth * (1 - sideMargin * 2)

        if usableWidth > 0.001 then
          local minimumSideStep = math.min(pileRadius / usableWidth, sideSpacing)
          sideFactor = math.clamp(sideFactor, sideIndex * minimumSideStep, 1 - (targetDepositCount - sideIndex - 1) * minimumSideStep)

          if sideIndex > 0 and sideIndex < targetDepositCount - 1 then
            local maxSideJitter = math.min(0.05 / usableWidth, minimumSideStep * 0.15)
            sideFactor = math.clamp(sideFactor + (math.random() * 2 - 1) * maxSideJitter, 0, 1)
          end
        end

        sideFactor = sideMargin + sideFactor * (1 - sideMargin * 2)
        local sideOffset = minSideOffset + sideFactor * workingWidth
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
          local sliceWidth = selectedArea.sliceEndOffset - selectedArea.sliceStartOffset

          if math.abs(sliceWidth) > 0.001 then
            local sliceFactor = math.clamp((selectedSideOffset - selectedArea.sliceStartOffset) / sliceWidth, 0, 1)
            centerX = selectedArea.sliceStartX + (selectedArea.sliceEndX - selectedArea.sliceStartX) * sliceFactor
            centerZ = selectedArea.sliceStartZ + (selectedArea.sliceEndZ - selectedArea.sliceStartZ) * sliceFactor
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
  end

  if depositCount == 0 then
    return
  end

  local pileLiters = requestedPiles * minimumPlacementLiters / depositCount
  local tireTrackSystemId = tireTrackSystem.tireTrackSystemId

  for index = 1, depositCount do
    local centerX = depositPositions[index * 2 - 1]
    local centerZ = depositPositions[index * 2]
    local startX = centerX - sideDirectionX * pileHalfLength
    local startZ = centerZ - sideDirectionZ * pileHalfLength
    local endX = centerX + sideDirectionX * pileHalfLength
    local endZ = centerZ + sideDirectionZ * pileHalfLength
    local startY = getTerrainHeightAtWorldPos(g_terrainNode, startX, 0, startZ)
    local endY = getTerrainHeightAtWorldPos(g_terrainNode, endX, 0, endZ)

    tireTrackSystem.tireTrackSystemId = 0
    local success, placedLiters = pcall(DensityMapHeightUtil.tipToGroundAroundLine, self, pileLiters, spec.groundFillType, startX, startY, startZ, endX, endY, endZ, 0, pileRadius, nil, false, nil, false, true)
    tireTrackSystem.tireTrackSystemId = tireTrackSystemId

    if not success then
      error(placedLiters, 0)
    end

    placedLiters = math.clamp(placedLiters or 0, 0, pileLiters)
    spec.fieldRemainderLiters = math.max(spec.fieldRemainderLiters - placedLiters / pileCountMultiplier, 0)
  end
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
