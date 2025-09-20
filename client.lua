-- never batch more than 300 and ALWAYS push to git for every batch or it shits itself
PropSet = { start = 1600, finish = 1800, } --will only pull from start to end. so batches are possible
local running = false
local idx = 1
local cam = nil
local lastObj = nil
local startIdx, endIdx, batchLabel

local function loadModel(model)
    local hash = (type(model) == 'string') and joaat(model) or model
    RequestModel(hash)
    local t = GetGameTimer()
    while not HasModelLoaded(hash) do
        Wait(0)
        if GetGameTimer() - t > 10000 then return nil end
    end
    return hash
end

local function clearCurrent()
    if DoesEntityExist(lastObj) then
        DeleteObject(lastObj)
        lastObj = nil
    end
end

local function ensureCamera()
    if not cam then
        cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
        RenderScriptCams(true, true, 350, true, true, 0)
        DisplayRadar(false)
    end
end

local function positionCamera(ent, angleOffset)
    if not cam or not DoesEntityExist(ent) then return end
    local ex, ey, ez = table.unpack(GetEntityCoords(ent))
    local min, max = GetModelDimensions(GetEntityModel(ent))
    local radius = math.max(1.0, #(max - min)) * 0.8
    local heading = GetEntityHeading(ent) + (angleOffset or -30.0) -- 3/4 view
    local rad = math.rad(heading)
    local dist = radius + 1.8
    local cx = ex + math.sin(rad) * dist
    local cy = ey - math.cos(rad) * dist
    local cz = ez + radius * 0.45
    SetCamCoord(cam, cx, cy, cz)
    PointCamAtEntity(cam, ent, 0.0, 0.0, 0.0, true)
    SetCamFov(cam, 75.0)
end

local function spawnAndFrame(modelName)
    local ped = PlayerPedId()
    local px, py, pz = table.unpack(GetEntityCoords(ped))
    local forward = GetEntityForwardVector(ped)
    local sx, sy, sz = px + forward.x * 2.5, py + forward.y * 2.5, pz

    local hash = loadModel(modelName)
    if not hash then return false, 'model timeout' end

    local obj = CreateObjectNoOffset(hash, sx, sy, sz, false, false, false)
    if not DoesEntityExist(obj) then return false, 'create failed' end

    SetEntityHeading(obj, GetEntityHeading(ped))                     -- neutral; camera gives the angle
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetEntityCollision(obj, false, false)
    SetEntityLodDist(obj, 9999)

    lastObj = obj
    ensureCamera()
    positionCamera(obj, -30.0)                     -- slight angle toward the front
    Wait(350)
    return true
end

local function environmentPreset()
    NetworkOverrideClockTime(12, 0, 0)
    SetWeatherTypeNowPersist('EXTRASUNNY')
    SetArtificialLightsState(false)
end

RegisterCommand('objectsgetimage', function(source, args)
    if running then
        print("[objshot] Already running.")
        return
    end
    if not Object_List or #Object_List == 0 then
        print("[objshot] No objects in Object_List.")
        return
    end

    -- Parse optional overrides: /objectsgetimage [start] [finish] [label]
    startIdx  = tonumber(args[1]) or PropSet.start
    endIdx    = tonumber(args[2]) or PropSet.finish
    batchLabel = args[3] or "set_"..tostring(startIdx).."_"..tostring(endIdx)

    -- Clamp within bounds
    startIdx = math.max(1, math.min(startIdx, #Object_List))
    endIdx   = math.max(1, math.min(endIdx,   #Object_List))
    if endIdx < startIdx then
        print("[objshot] Invalid range. finish < start.")
        return
    end

    print(("[objshot] Starting batch %s: %d..%d of %d")
        :format(batchLabel or "default", startIdx, endIdx, #Object_List))

    running = true
    idx = startIdx
    environmentPreset()
    ensureCamera()

    CreateThread(function()
        while running and idx <= endIdx do
            local name = Object_List[idx]
            clearCurrent()

            local ok, err = spawnAndFrame(name)
            if not ok then
                print(("[objshot] Failed %s (%s)"):format(tostring(name), tostring(err)))
                idx = idx + 1
                Wait(200)
                goto continue
            end

            print(("[objshot] Capturing %s (%d/%d)")
                :format(name, (idx - startIdx + 1), (endIdx - startIdx + 1)))
            -- Send batchLabel so server can save into a subfolder
            TriggerServerEvent('objshot:capture', name, batchLabel)

            Wait(500)
            idx = idx + 1
            Wait(400)

            ::continue::
            Wait(0)
        end

        clearCurrent()
        if cam then
            RenderScriptCams(false, true, 300, true, true, 0)
            DestroyCam(cam, false)
            cam = nil
            DisplayRadar(true)
        end
        running = false
        print("[objshot] Finished batch. ["..tostring(batchLabel).."]")
    end)
end, false)

RegisterCommand('stopobjectimage', function()
    if running then
        running = false
        print("[objshot] Stopping…")
    else
        print("[objshot] Not running.")
    end
end, false)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        clearCurrent()
        if cam then
            RenderScriptCams(false, true, 300, true, true, 0)
            DestroyCam(cam, false)
            cam = nil
        end
        DisplayRadar(true)
    end
end)
