--
-- FSDensityMapUtilExtension
--
-- Author: Sławek Jaskulski
-- Copyright (C) ModNext, All Rights Reserved.
--

FSDensityMapUtilExtension = {}

---Removes hidden manure markers after spray data is removed
function FSDensityMapUtilExtension.removeSprayArea(startWorldX, superFunc, ...)
  superFunc(startWorldX, ...)

  ManureGroundDepositor.clearHiddenManureArea(startWorldX, ...)
end

---Clears hidden manure markers after another spray layer is applied
function FSDensityMapUtilExtension.updateGroundTypeLayerArea(startWorldX, superFunc, ...)
  local changedArea, totalArea = superFunc(startWorldX, ...)

  ManureGroundDepositor.clearHiddenManureForGroundType(startWorldX, ...)

  return changedArea, totalArea
end

---
FSDensityMapUtil.removeSprayArea = Utils.overwrittenFunction(FSDensityMapUtil.removeSprayArea, FSDensityMapUtilExtension.removeSprayArea)
FSDensityMapUtil.setGroundTypeLayerArea = Utils.overwrittenFunction(FSDensityMapUtil.setGroundTypeLayerArea, FSDensityMapUtilExtension.updateGroundTypeLayerArea)
FSDensityMapUtil.updateFertilizerArea = Utils.overwrittenFunction(FSDensityMapUtil.updateFertilizerArea, FSDensityMapUtilExtension.updateGroundTypeLayerArea)
FSDensityMapUtil.updateLimeArea = Utils.overwrittenFunction(FSDensityMapUtil.updateLimeArea, FSDensityMapUtilExtension.updateGroundTypeLayerArea)
FSDensityMapUtil.updateHerbicideArea = Utils.overwrittenFunction(FSDensityMapUtil.updateHerbicideArea, FSDensityMapUtilExtension.updateGroundTypeLayerArea)
