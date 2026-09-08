local UEHelpers = require("UEHelpers")

local function resolvePath(filename)
    local searchPaths = {
        "ue4ss/Mods/OriginSwapper/" .. filename,
        "Mods/OriginSwapper/" .. filename,
        "OriginSwapper/" .. filename,
        filename
    }
    for _, p in ipairs(searchPaths) do
        local f = io.open(p, "r")
        if f then
            f:close()
            return p
        end
    end
    return "ue4ss/Mods/OriginSwapper/" .. filename
end

local configPath = resolvePath("config.ini")
local logPath = resolvePath("OriginSwapper.log")
local logFile = nil

local ORIGIN_MAP = {
    [1] = "BambergSmallholders",
    [2] = "OfTheVogtland",
    [3] = "WoodwrightsOfFranconia",
    [4] = "RegensburgGuildsmen",
    [5] = "SmithsOfPassau",
    [6] = "BornOfTheAlps",
    [7] = "StrasburgMasons",
    [8] = "NurembergProspectors",
    [9] = "WeidenHinterlanders",
}

local ORIGIN_NAMES_ES = {
    ["BambergSmallholders"]    = "Pequeños propietarios de Bamberg",
    ["OfTheVogtland"]          = "Del Vogtland",
    ["WoodwrightsOfFranconia"] = "Carpinteros de Franconia",
    ["RegensburgGuildsmen"]    = "Gremialistas de Ratisbona",
    ["SmithsOfPassau"]         = "Herreros de Passau",
    ["BornOfTheAlps"]          = "Nacidos de los Alpes",
    ["StrasburgMasons"]        = "Albañiles de Estrasburgo",
    ["NurembergProspectors"]   = "Prospectores de Núremberg",
    ["WeidenHinterlanders"]    = "Pobladores de Weiden",
}

local function log(msg)
    print("[OriginSwapper] " .. tostring(msg) .. "\n")
    if not logFile then
        logFile = io.open(logPath, "a")
    end
    if logFile then
        logFile:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. tostring(msg) .. "\n")
        logFile:flush()
    end
end

local function loadConfig()
    local cfg = {
        TargetOrigin = "StrasburgMasons",
        Hotkey = "F6",
        DebugLog = true
    }

    local f = io.open(configPath, "r")
    if not f then
        -- Try relative path
        f = io.open("Mods/OriginSwapper/config.ini", "r")
    end

    if f then
        for line in f:lines() do
            local clean = line:match("^[^;]+") or ""
            clean = clean:match("^%s*(.-)%s*$") or ""
            local k, v = clean:match("^([%w_]+)%s*=%s*(.+)$")
            if k and v then
                v = v:match("^%s*(.-)%s*$")
                if k == "TargetOrigin" then
                    local num = tonumber(v)
                    if num and ORIGIN_MAP[num] then
                        cfg.TargetOrigin = ORIGIN_MAP[num]
                    else
                        cfg.TargetOrigin = v
                    end
                elseif k == "Hotkey" then
                    cfg.Hotkey = v:upper()
                elseif k == "DebugLog" then
                    cfg.DebugLog = (v:lower() == "true")
                end
            end
        end
        f:close()
    else
        log("[WARN] config.ini not found. Using default: StrasburgMasons (F6)")
    end

    return cfg
end

local config = loadConfig()
local targetOrigin = config.TargetOrigin
local friendlyName = ORIGIN_NAMES_ES[targetOrigin] or targetOrigin

log("==================================================")
log("Manor Lords - OriginSwapper Initialized")
log(string.format("Target Origin: %s (%s)", targetOrigin, friendlyName))
log(string.format("Hotkey: [%s]", config.Hotkey))
log("==================================================")

local function getParamString(p)
    if not p then return "" end
    local str = ""
    pcall(function()
        local raw = p
        if p.get then raw = p:get() end
        if raw.ToString then str = raw:ToString() else str = tostring(raw) end
    end)
    return str
end

local function isAnyOrigin(s)
    if not s or s == "" or s == "None" then return false end
    for _, name in pairs(ORIGIN_MAP) do
        if s == name or string.find(s, name) then
            return true, name
        end
    end
    return false, nil
end

local function applyTargetOrigin()
    -- Reload config in case user modified config.ini while in-game
    config = loadConfig()
    targetOrigin = config.TargetOrigin
    friendlyName = ORIGIN_NAMES_ES[targetOrigin] or targetOrigin

    log("--------------------------------------------------")
    log(string.format("Starting Origin Swap -> '%s' (%s)...", targetOrigin, friendlyName))
    local actions = 0

    -- 1. Trigger Native UI Pipeline on RegionDevelopmentPerksPanel
    local panels = FindAllOf("RegionDevelopmentPerksPanel")
    if panels and #panels > 0 then
        log(string.format("Found %d open RegionDevelopmentPerksPanel widgets.", #panels))
        for i, panel in ipairs(panels) do
            pcall(function()
                log(string.format("  Executing native perk confirmation on panel %d...", i))
                panel:SetSelectedPerkName(FName(targetOrigin))
                panel:ConfirmPerkSelection(FName(targetOrigin))
                panel:PerkSelectionAccepted()
                panel:UpdatePanel(FName(targetOrigin))
                log("  >>> Successfully applied selection via native UI pipeline!")
                actions = actions + 1
            end)
        end
    else
        log("[INFO] 'Orígenes' menu is not currently open on screen.")
    end

    -- 2. Update MLSaveGame in memory
    local saves = FindAllOf("MLSaveGame")
    if saves then
        for _, sg in ipairs(saves) do
            pcall(function()
                if sg.savedRegions then
                    for r = 1, #sg.savedRegions do
                        local sr = sg.savedRegions[r]
                        local rName = getParamString(sr.CustomName)

                        if sr.ActivePerks then
                            sr.ActivePerks:ForEach(function(k, v)
                                local vStr = getParamString(v)
                                local isOrig, oldName = isAnyOrigin(vStr)
                                if isOrig and oldName ~= targetOrigin then
                                    local rk = k
                                    if k.get then rk = k:get() end
                                    sr.ActivePerks:Add(rk, FName(targetOrigin))
                                    log(string.format("  >>> SaveGame Region '%s' ActivePerk: '%s' -> '%s'", rName, oldName, targetOrigin))
                                    actions = actions + 1
                                end
                            end)
                        end

                        if sr.Tags then
                            for i = 1, #sr.Tags do
                                local tStr = getParamString(sr.Tags[i])
                                local isOrig, oldName = isAnyOrigin(tStr)
                                if isOrig and oldName ~= targetOrigin then
                                    sr.Tags[i] = FName(targetOrigin)
                                    log(string.format("  >>> SaveGame Region '%s' Tag[%d]: '%s' -> '%s'", rName, i, oldName, targetOrigin))
                                    actions = actions + 1
                                end
                            end
                        end
                    end
                end
            end)
        end
    end

    -- 3. Update live ARegion actors and PerkComponents
    local regions = FindAllOf("Region")
    if regions then
        for _, reg in ipairs(regions) do
            local rName = getParamString(reg.regionName)

            -- Check live PerkComponent
            local pc = reg.PerkComponent
            if pc and pc:IsValid() then
                pcall(function()
                    pc:GetClass():ForEachProperty(function(prop)
                        local pName = prop:GetFName():ToString()
                        local ok, val = pcall(function() return pc[pName] end)
                        if ok and val ~= nil then
                            local vStr = getParamString(val)
                            local isOrig, oldName = isAnyOrigin(vStr)
                            if isOrig and oldName ~= targetOrigin then
                                pc[pName] = FName(targetOrigin)
                                log(string.format("  >>> Live PerkComponent on '%s' (%s): '%s' -> '%s'", rName, pName, oldName, targetOrigin))
                                actions = actions + 1
                            end
                        end
                    end)
                end)
            end

            -- Check live Region Tags
            if reg.Tags then
                for i = 1, #reg.Tags do
                    local tStr = getParamString(reg.Tags[i])
                    local isOrig, oldName = isAnyOrigin(tStr)
                    if isOrig and oldName ~= targetOrigin then
                        reg.Tags[i] = FName(targetOrigin)
                        log(string.format("  >>> Live Region '%s' Tag[%d]: '%s' -> '%s'", rName, i, oldName, targetOrigin))
                        actions = actions + 1
                    end
                end
            end
        end
    end

    log(string.format(">>> Execution complete. Applied %d updates.", actions))
    log(">>> Please save the game (Escape -> Guardar partida) to commit the changes!")
    log("--------------------------------------------------")
end

-- Register Configured Hotkey
local keyConstant = Key[config.Hotkey] or Key.F6
RegisterKeyBindAsync(keyConstant, {}, function()
    ExecuteInGameThread(function()
        applyTargetOrigin()
    end)
end)
