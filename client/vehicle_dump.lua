--DATA DUMPS [VEHICLE]

-- CLIENT: Full Vehicle Data Dump (expanded schema)
-- Notes:
-- • Populates as many properties as FiveM/GTA natives expose at runtime.
-- • Some fields (e.g., full multi-language strings, exact DLC pack name, modkit string IDs,
--   complete bone tables, spawn frequency, weapon lists, etc.) are not directly exposed;
--   those are left nil or approximated with best-effort values and clear comments.

local veh = nil
local vehSpawnCoords = vector4(-957.15, -3263.03, 13.94, 59.99)

-- ========= helpers =========

local function safeDeleteVehicle(entity)
    if entity and DoesEntityExist(entity) then
        SetEntityAsMissionEntity(entity, true, true)
        DeleteVehicle(entity)
        if DoesEntityExist(entity) then
            DeleteEntity(entity)
        end
    end
end

local function loadVehicleModel(hash, timeoutMs)
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then return false end
    RequestModel(hash)
    local t0 = GetGameTimer()
    while not HasModelLoaded(hash) do
        Wait(0)
        if (GetGameTimer() - t0) > (timeoutMs or 5000) then break end
    end
    return HasModelLoaded(hash)
end

-- unsigned 32-bit + hex helpers
local function toUnsigned32(n)
    if n < 0 then
        return (0x100000000 + n) % 0x100000000
    end
    return n % 0x100000000
end
local function toHex(n)
    return string.format("0x%08X", toUnsigned32(n))
end

-- label helpers: try to resolve label -> text; falls back to raw label
local function safeGetLabelText(label)
    if not label or label == "" then return nil end
    local txt = GetLabelText(label)
    if txt == nil or txt == "NULL" or txt == "" then
        -- sometimes displayName is already the visible text (non-GXT)
        return label
    end
    return txt
end

local function getModelType(hash)
    if IsThisModelABoat(hash) then return "BOAT" end
    if IsThisModelAHeli(hash) then return "HELI" end
    if IsThisModelAPlane(hash) then return "PLANE" end
    if IsThisModelAQuadbike(hash) then return "QUADBIKE" end
    if IsThisModelABike(hash) then return "BIKE" end
    if IsThisModelACar(hash) then return "CAR" end
    if IsThisModelATrain(hash) then return "TRAIN" end
    return "OTHER"
end

-- vehicle layout hash -> label-ish mapping (best-effort; add more as needed)
local LAYOUT_HASH_TO_NAME = {
    [GetHashKey("LAYOUT_LOW")] = "LAYOUT_LOW",
    [GetHashKey("LAYOUT_LOW_RESTRICTED")] = "LAYOUT_LOW_RESTRICTED",
    [GetHashKey("LAYOUT_STD")] = "LAYOUT_STD",
    [GetHashKey("LAYOUT_STD_2")] = "LAYOUT_STD_2",
    [GetHashKey("LAYOUT_STD_3")] = "LAYOUT_STD_3",
    [GetHashKey("LAYOUT_VAN")] = "LAYOUT_VAN",
    [GetHashKey("LAYOUT_BIKE")] = "LAYOUT_BIKE",
    [GetHashKey("LAYOUT_HELI")] = "LAYOUT_HELI",
    [GetHashKey("LAYOUT_BOAT")] = "LAYOUT_BOAT",
    [GetHashKey("LAYOUT_TANK")] = "LAYOUT_TANK",
}

-- dashboard type: not directly exposed; we approximate using class
local function guessDashboardType(classId)
    -- This is an approximation to match strings like "SUPERGT" from your sample.
    if classId == 7 then return "SUPERGT" end
    if classId == 6 then return "SPORT" end
    if classId == 5 then return "SPORT_CLASSIC" end
    if classId == 4 then return "MUSCLE" end
    if classId == 14 then return "BOAT" end
    if classId == 15 then return "HELI" end
    if classId == 16 then return "PLANE" end
    return veh_data.VEHICLE_CLASSES[classId] or "UNKNOWN"
end

-- basic flag sampler (best-effort: we infer from model checks & extras present)
local function collectFlags(veh, hash)
    local flags = {}

    -- sample interpretations
    if not DoesExtraExist(veh, 5) and not DoesExtraExist(veh, 6) then
        table.insert(flags, "FLAG_EXTRAS_OPTIONAL_OR_NONE")
    end
    if IsThisModelACar(hash) and (GetVehicleClass(veh) == 6 or GetVehicleClass(veh) == 7) then
        table.insert(flags, "FLAG_SPORTS_OR_SUPER")
    end
    if IsThisModelABoat(hash) then table.insert(flags, "FLAG_WATERCRAFT") end
    if IsThisModelAQuadbike(hash) then table.insert(flags, "FLAG_QUADBIKE") end
    if IsThisModelABike(hash) then table.insert(flags, "FLAG_BIKE") end

    -- Neon capability check (exists as slots, not necessarily enabled)
    local hasNeon = false
    for i=0,3 do
        if IsVehicleNeonLightEnabled(veh, i) then hasNeon = true break end
    end
    if hasNeon then table.insert(flags, "FLAG_CAN_HAVE_NEONS") end

    return flags
end

-- compute bounding center & radius from model AABB
local function calcBounds(minV, maxV)
    local cx = (minV.x + maxV.x) * 0.5
    local cy = (minV.y + maxV.y) * 0.5
    local cz = (minV.z + maxV.z) * 0.5
    local dx = (maxV.x - minV.x)
    local dy = (maxV.y - minV.y)
    local dz = (maxV.z - minV.z)
    local radius = math.sqrt(dx*dx + dy*dy + dz*dz) * 0.5
    return {X=cx, Y=cy, Z=cz}, radius
end

-- default colors (we snapshot fresh-spawn values)
local function getDefaultColors(veh)
    local primary, secondary = GetVehicleColours(veh)
    local pearlescent, wheels = GetVehicleExtraColours(veh)
    local interior = 0
    local dash = 0
    if DoesEntityExist(veh) then
        -- these natives exist in newer builds; if unavailable they return false
        local okInt, intCol = pcall(function()
            local col = Citizen.InvokeNative(0xF40DD601A65F7F19, veh, Citizen.ResultAsInteger()) -- GET_VEHICLE_INTERIOR_COLOR
            return true, col
        end)
        if okInt and intCol then interior = intCol end
        local okDash, dashCol = pcall(function()
            local col = Citizen.InvokeNative(0xF489F03FCD1D6C2C, veh, Citizen.ResultAsInteger()) -- GET_VEHICLE_DASHBOARD_COLOR
            return true, col
        end)
        if okDash and dashCol then dash = dashCol end
    end
    return {
        DefaultPrimaryColor   = primary or 0,
        DefaultSecondaryColor = secondary or 0,
        DefaultPearlColor     = pearlescent or 0,
        DefaultWheelsColor    = wheels or 0,
        DefaultInteriorColor  = interior or 0,
        DefaultDashboardColor = dash or 0,
    }
end

-- extras + required extras
local function getExtrasLists(veh)
    local extras, required = {}, {}
    for id = 0, 20 do
        if DoesExtraExist(veh, id) then
            table.insert(extras, id)
            -- dependency probing
            for dep = 0, 20 do
                if dep ~= id then
                    if DoesExtraExist(veh, dep) then
                        if not required[id] then required[id] = {} end
                        table.insert(required, dep) -- keep a flat list to match your sample
                    end
                end
            end
        end
    end
    -- dedupe flat list
    local seen, flat = {}, {}
    for _, v in ipairs(required) do
        if not seen[v] then seen[v] = true table.insert(flat, v) end
    end
    return extras, flat
end

local function collectBones(veh)
    local bones = {}
    for _, name in ipairs(veh_data.KNOWN_BONES) do
        local idx = GetEntityBoneIndexByName(veh, name)
        if idx ~= -1 then
            -- BoneId is not directly exposed for vehicles; use index as best-effort
            table.insert(bones, {
                BoneIndex = idx,
                BoneId = idx,
                BoneName = name
            })
        end
    end
    return bones
end

-- DLC name lookup (best-effort). If not found, fall back to "TitleUpdate"
local function getDlcNameForModel(hash)
    -- We try to scan DLC vehicles and match the model hash.
    -- If natives aren’t present/return nothing, default to "TitleUpdate".
    local dlcCount = GetNumDlcVehicles and GetNumDlcVehicles() or 0
    if dlcCount and dlcCount > 0 then
        for i=0, dlcCount-1 do
            local model = GetDlcVehicleModel(i)
            if model == hash then
                -- Try to get pack name (implementation differs per build; fallback string)
                return "DLC"
            end
        end
    end
    return "TitleUpdate"
end

-- handling metrics (guarded calls across builds)
local function getHandlingNumbers(hash)
    local maxBraking, maxBrakingMods, maxSpeed, maxTraction, accel, agility, moveRes = nil, nil, nil, nil, nil, nil, nil

    if GetVehicleModelMaxBraking then
        maxBraking = GetVehicleModelMaxBraking(hash)
    end
    if GetVehicleModelMaxBrakingMods then
        maxBrakingMods = GetVehicleModelMaxBrakingMods(hash)
    end
    if GetVehicleModelEstimatedMaxSpeed then
        maxSpeed = GetVehicleModelEstimatedMaxSpeed(hash) -- m/s
    end
    if GetVehicleModelMaxTraction then
        maxTraction = GetVehicleModelMaxTraction(hash)
    end
    if GetVehicleModelAcceleration then
        accel = GetVehicleModelAcceleration(hash)
    end
    -- Not standard across builds; try via native hash to avoid hard errors
    local okAgility, ag = pcall(function()
        return Citizen.InvokeNative(0x29DA3CA8D8B2692D, hash, Citizen.ResultAsFloat()) -- GET_VEHICLE_MODEL_AGILITY? (best-effort)
    end)
    if okAgility then agility = ag end

    local okMove, mr = pcall(function()
        return Citizen.InvokeNative(0x5AA3F878A178C4FC, hash, Citizen.ResultAsFloat()) -- GET_VEHICLE_MODEL_MOVE_RESISTANCE? (best-effort)
    end)
    if okMove then moveRes = mr end

    return maxBraking, maxBrakingMods, maxSpeed, maxTraction, accel, agility, moveRes
end

-- wheel count is native; knots only meaningful for boats
local function toKnots(mps)
    if not mps then return nil end
    return mps * 1.943844 -- m/s -> knots
end

-- layout id/name
local function getLayoutInfo(veh)
    local layoutHash = GetVehicleLayoutHash(veh)
    local name = LAYOUT_HASH_TO_NAME[layoutHash] or ("0x"..string.format("%08X", layoutHash))
    return name, layoutHash
end

-- default horn hash (not on all builds)
local function getDefaultHornInfo(veh)
    local hornHash, variation = nil, 0
    local ok1, hh = pcall(function()
        return Citizen.InvokeNative(0x02165D55000219AC, veh, Citizen.ResultAsInteger()) -- GET_VEHICLE_DEFAULT_HORN_HASH
    end)
    if ok1 then hornHash = hh end
    local ok2, var = pcall(function()
        return Citizen.InvokeNative(0xEEE4E0DB4F4EED03, veh, Citizen.ResultAsInteger()) -- GET_VEHICLE_DEFAULT_HORN_VARIATION
    end)
    if ok2 then variation = var end
    return hornHash, variation
end

-- collect default colors set variants (sample several spawns to mimic array)
local function collectDefaultColorSets(hash)
    local sets = {}
    for i=1,10 do
        local v = CreateVehicle(hash, vehSpawnCoords.x, vehSpawnCoords.y, vehSpawnCoords.z, vehSpawnCoords.w, false, false)
        if DoesEntityExist(v) then
            SetEntityAsMissionEntity(v, true, true)
            FreezeEntityPosition(v, true)
            SetEntityCollision(v, false, false)
            SetVehicleColours(v, 0, 0) -- do nothing; just snapshot provided defaults
            local set = getDefaultColors(v)
            table.insert(sets, set)
            safeDeleteVehicle(v)
        end
        Wait(0)
    end
    return sets
end

-- ========= main dumper =========

function ProcessVehicleData()
    local vehicleTable = GetAllVehicleModels()  -- array of model names
    local resultsByModel = {}
    local finished = 0
    print("Started creating FULL vehicle data dump")

    for _, modelName in ipairs(vehicleTable) do
        local hash = GetHashKey(modelName)

        local unsigned = toUnsigned32(hash)
        local hexHash = toHex(hash)

        -- display name labels
        local displayKey = GetDisplayNameFromVehicleModel(hash) or modelName
        local displayEnglish = safeGetLabelText(displayKey)

        -- manufacturer labels
        local makeKey = GetMakeNameFromVehicleModel(hash) -- returns label key (e.g., "TRUFFADE")
        local manufacturerUpper = makeKey or ""
        local manufacturerText = safeGetLabelText(makeKey) or manufacturerUpper

        local data = {
            Name = modelName,
            DisplayName = {
                Hash = unsigned,
                English = displayEnglish,
                -- Multi-language texts cannot be fetched at runtime without switching locales/files.
                German = displayEnglish, French = displayEnglish, Italian = displayEnglish,
                Russian = displayEnglish, Polish = displayEnglish, Name = displayKey,
                TraditionalChinese = displayEnglish, SimplifiedChinese = displayEnglish,
                Spanish = displayEnglish, Japanese = displayEnglish, Korean = displayEnglish,
                Portuguese = displayEnglish, Mexican = displayEnglish
            },
            Hash = unsigned,
            SignedHash = hash,
            HexHash = hexHash,
            DlcName = getDlcNameForModel(hash), -- best-effort ("TitleUpdate" if unknown)
            HandlingId = displayKey,            -- handling names typically match display key (approx)
            LayoutId = select(1, getLayoutInfo(veh or 0)) or nil,
            Manufacturer = manufacturerUpper,
            ManufacturerDisplayName = {
                Hash = toUnsigned32(GetHashKey(manufacturerUpper or "")),
                English = manufacturerText,
                German = manufacturerText, French = manufacturerText, Italian = manufacturerText,
                Russian = manufacturerText, Polish = manufacturerText, Name = manufacturerUpper,
                TraditionalChinese = manufacturerText, SimplifiedChinese = manufacturerText,
                Spanish = manufacturerText, Japanese = manufacturerText, Korean = manufacturerText,
                Portuguese = manufacturerText, Mexican = manufacturerText
            },
            Class = veh_data.VEHICLE_CLASSES[GetVehicleClassFromName and GetVehicleClassFromName(hash) or  GetVehicleClass(veh or 0) or 0] or "UNKNOWN",
            ClassId = GetVehicleClassFromName and GetVehicleClassFromName(hash) or 0,
            Type = getModelType(hash),
            PlateType = nil, -- we fill after spawning
            DashboardType = nil, -- set after spawning (approx by class)
            WheelType = nil, -- set after spawning
            Flags = {},

            Seats = GetVehicleModelNumberOfSeats(hash) or 0,
            Price = -1,                 -- not exposed; keep your sample’s -1
            MonetaryValue = 0,          -- not exposed; leave 0 or estimate externally

            HasConvertibleRoof = IsThisModelAConvertible and IsThisModelAConvertible(hash, false) or false,
            HasSirens = false,          -- set after spawning
            Weapons = {},               -- not exposed via simple natives; left empty
            ModKits = {},               -- best-effort after spawning

            DimensionsMin = nil,
            DimensionsMax = nil,
            BoundingCenter = nil,
            BoundingSphereRadius = nil,

            Rewards = nil,

            MaxBraking = nil,
            MaxBrakingMods = nil,
            MaxSpeed = nil,
            MaxTraction = nil,
            Acceleration = nil,
            Agility = nil,
            MaxKnots = 0.0,
            MoveResistance = nil,

            HasArmoredWindows = false,  -- not generally exposed; left false

            DefaultColors = {},

            DefaultBodyHealth = 1000.0, -- standard
            DirtLevelMin = 0.0,
            DirtLevelMax = 0.3,

            Trailers = {},              -- non-trivial to infer; left empty
            AdditionalTrailers = {},

            Extras = {},
            RequiredExtras = {},

            SpawnFrequency = nil,       -- game config only; not exposed
            WheelsCount = 0,

            HasParachute = false,       -- special cases only (not generally exposed)
            HasKers = false,            -- special cases only (not generally exposed)

            DefaultHorn = nil,
            DefaultHornVariation = 0,

            Bones = {}                  -- best-effort known-name probe
        }

        if loadVehicleModel(hash, 5000) then
            veh = CreateVehicle(hash, vehSpawnCoords.x, vehSpawnCoords.y, vehSpawnCoords.z, vehSpawnCoords.w, false, false)
            if DoesEntityExist(veh) then
                SetEntityAsMissionEntity(veh, true, true)
                SetEntityCollision(veh, false, false)
                FreezeEntityPosition(veh, true)
                SetEntityVisible(veh, true, true)

                -- Fill runtime-derived fields
                local classId = GetVehicleClass(veh)
                data.ClassId = classId or data.ClassId
                data.Class = veh_data.VEHICLE_CLASSES[data.ClassId or 0] or data.Class
                data.DashboardType = guessDashboardType(data.ClassId or 0)

                -- Plate & wheel type (enums -> strings)
                if GetVehiclePlateType then
                    local pt = GetVehiclePlateType(veh)
                    data.PlateType = veh_data.PLATE_TYPES[pt] or tostring(pt)
                end
                if GetVehicleWheelType then
                    local wt = GetVehicleWheelType(veh)
                    data.WheelType = veh_data.WHEEL_TYPES[wt] or tostring(wt)
                end

                data.HasSirens = DoesVehicleHaveSiren and DoesVehicleHaveSiren(veh) or false

                -- Model dimensions & derived bounds
                local minV = vector3(0.0,0.0,0.0)
                local maxV = vector3(0.0,0.0,0.0)
                local okDims = GetModelDimensions(hash, minV, maxV)
                if okDims then
                    data.DimensionsMin = {X=minV.x, Y=minV.y, Z=minV.z}
                    data.DimensionsMax = {X=maxV.x, Y=maxV.y, Z=maxV.z}
                    local center, radius = calcBounds(minV, maxV)
                    data.BoundingCenter = center
                    data.BoundingSphereRadius = radius
                end

                -- Handling & perf
                local maxBraking, maxBrakingMods, maxSpeed, maxTraction, accel, agility, moveRes = getHandlingNumbers(hash)
                data.MaxBraking = maxBraking
                data.MaxBrakingMods = maxBrakingMods
                data.MaxSpeed = maxSpeed
                data.MaxTraction = maxTraction
                data.Acceleration = accel
                data.Agility = agility
                data.MoveResistance = moveRes
                data.MaxKnots = IsThisModelABoat(hash) and toKnots(maxSpeed) or 0.0

                -- Defaults & counts
                data.WheelsCount = GetVehicleNumberOfWheels(veh) or 0

                -- Default color snapshots (take several spawns to build an array like your sample)
                data.DefaultColors = collectDefaultColorSets(hash)

                -- Mod kits (best-effort: capture available kit indices)
                if GetNumModKits then
                    local kits = GetNumModKits(veh) or 0
                    for i=0,(kits-1) do
                        table.insert(data.ModKits, ("modkit_%d"):format(i))
                    end
                end

                -- Extras & requirements
                local extras, req = getExtrasLists(veh)
                data.Extras = extras
                data.RequiredExtras = req

                -- Flags (best-effort)
                data.Flags = collectFlags(veh, hash)

                -- Horn info (if supported)
                local hornHash, hornVar = getDefaultHornInfo(veh)
                data.DefaultHorn = hornHash
                data.DefaultHornVariation = hornVar or 0

                -- Bones (best-effort by known names)
                data.Bones = collectBones(veh)
            end
        end

        -- cleanup per model
        if veh ~= nil and DoesEntityExist(veh) then
            safeDeleteVehicle(veh)
            veh = nil
        end
        if HasModelLoaded(hash) then SetModelAsNoLongerNeeded(hash) end

        -- final fallbacks that need a vehicle instance
        if not data.LayoutId then
            -- Try to compute via hash name mapping if no vehicle existed
            data.LayoutId = "UNKNOWN"
        end

        -- store under model key so we can alphabetize on the server
        resultsByModel[modelName] = data
        finished = finished + 1
        print(("Vehicle: [%s] Full dump logged"):format(tostring(modelName)))

        Wait(50) -- tweak if needed
    end

    print(("Completed %d vehicles (full dump)"):format(finished))

    TriggerServerEvent('objshot:server:SaveAllVehiclesJSON', resultsByModel)
end

RegisterCommand('getallvehicleData', function()
    ProcessVehicleData()
end, false)