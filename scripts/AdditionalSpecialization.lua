--
-- AdditionalSpecialization
--
-- Author: Sławek Jaskulski
-- Copyright (C) ModNext, All Rights Reserved.
--

local modName = g_currentModName

AdditionalSpecialization = {}

---Adds the depositor only to sprayer vehicle types
---@param typeManager table
function AdditionalSpecialization.finalizeTypes(typeManager)
  if typeManager.typeName ~= "vehicle" or not g_modIsLoaded[modName] then
    return
  end

  local specializationName = modName .. ".manureGroundDepositor"

  for typeName, typeEntry in pairs(typeManager:getTypes()) do
    local hasSprayer = SpecializationUtil.hasSpecialization(Sprayer, typeEntry.specializations)

    if hasSprayer and typeEntry.specializationsByName[specializationName] == nil then
      typeManager:addSpecialization(typeName, specializationName)
    end
  end
end

---
TypeManager.finalizeTypes = Utils.prependedFunction(TypeManager.finalizeTypes, AdditionalSpecialization.finalizeTypes)
