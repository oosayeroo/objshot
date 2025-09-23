

-- never batch more than 1000 webp (300 png, 400 jpg) and ALWAYS push to git for every batch or it shits itself
local PropSet = { start = 19000, finish = 21000 } -- will only pull from start to end. so batches are possible

local running = false
local idx = 1
local cam = nil
local lastObj = nil
local startIdx, endIdx, batchLabel

local awaitingAck = false
local lastErr = nil
local captureToken = 0           -- NEW: identifies an in-flight capture
local currentToken = nil         -- token we’re currently waiting for

--========================
-- Utilities
--========================

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

-- Drop-in: centers camera on the model's bbox center in world space
-- Optional opts:
--   opts.fov            (number) default 70.0
--   opts.verticalBias   (0..1)   fraction of model height to nudge aim point up (default 0.1)
--   opts.distanceScale  (number) distance multiplier (default 1.0)
--   opts.heightLift     (number) extra world-units to lift the camera above aim point (default height*0.25)
local function positionCamera(ent, angleOffset, opts)
    if not cam or not DoesEntityExist(ent) then return end
    opts = opts or {}

    local model = GetEntityModel(ent)
    local min, max = GetModelDimensions(model)
    -- Handle rare invalid dimensions
    if not min or not max then
        -- fallback to old behavior
        local ex, ey, ez = table.unpack(GetEntityCoords(ent))
        local heading = GetEntityHeading(ent) + (angleOffset or -30.0)
        local rad = math.rad(heading)
        local dist = 3.0
        local cx = ex + math.sin(rad) * dist
        local cy = ey - math.cos(rad) * dist
        local cz = ez + 1.5
        SetCamCoord(cam, cx, cy, cz)
        PointCamAtEntity(cam, ent, 0.0, 0.0, 0.0, true)
        SetCamFov(cam, opts.fov or 70.0)
        return
    end

    -- Model-space center & extents
    local cx_m = (min.x + max.x) * 0.5
    local cy_m = (min.y + max.y) * 0.5
    local cz_m = (min.z + max.z) * 0.5
    local w    = (max.x - min.x)
    local d    = (max.y - min.y)
    local h    = (max.z - min.z)

    -- World-space aim point: bbox center + small upward bias so very tall props don't look bottom-heavy
    local aimBias = (opts.verticalBias or 0.10) * h
    local aim = GetOffsetFromEntityInWorldCoords(ent, cx_m, cy_m, cz_m + aimBias)

    -- Choose a distance based on the largest dimension; behaves like a "fit to frame"
    local largest = math.max(w, d, h)
    local baseRadius = math.max(1.0, largest) * 0.6
    local distance = baseRadius * (opts.distanceScale or 1.0) + 1.6

    -- 3/4 orbit around the aim point
    local heading = GetEntityHeading(ent) + (angleOffset or -30.0)
    local rad = math.rad(heading)

    -- Put camera around aim, and slightly above it so perspective isn’t flat
    local lift = opts.heightLift or (h * 0.25)
    local camX = aim.x + math.sin(rad) * distance
    local camY = aim.y - math.cos(rad) * distance
    local camZ = aim.z + lift

    SetCamCoord(cam, camX, camY, camZ+1)
    -- Aim at the exact aim point, not the entity origin
    PointCamAtCoord(cam, aim.x, aim.y, aim.z)
    SetCamFov(cam, opts.fov or 70.0)

    -- Optional: if something occludes or aim seems off on extreme shapes, nudge up a bit
    -- for 1–2 frames. Uncomment if needed:
    -- if not IsSphereVisible(aim.x, aim.y, aim.z, largest * 0.1) then
    --     SetCamCoord(cam, camX, camY, camZ + largest * 0.1)
    -- end
end


local function environmentPreset()
    NetworkOverrideClockTime(12, 0, 0)
    SetWeatherTypeNowPersist('EXTRASUNNY')
    SetArtificialLightsState(false)
end

-- Non-blocking prefetch to warm the streamer
local function prefetchModel(model)
    local hash = (type(model) == 'string') and joaat(model) or model
    RequestModel(hash)
end

-- Faster model loader with shorter timeout; returns hash or nil
local function loadModelFast(model, timeoutMs)
    local hash = (type(model) == 'string') and joaat(model) or model
    if HasModelLoaded(hash) then return hash end
    RequestModel(hash)
    local t0 = GetGameTimer()
    local limit = timeoutMs or 2500
    while not HasModelLoaded(hash) do
        Wait(0)
        if (GetGameTimer() - t0) > limit then return nil end
    end
    return hash
end

-- Light collision ready check (kept short)
local function waitCollisionReady(ent, maxMs)
    local t = GetGameTimer()
    local ex, ey, ez = table.unpack(GetEntityCoords(ent))
    RequestCollisionAtCoord(ex, ey, ez)
    while not HasCollisionLoadedAroundEntity(ent) do
        Wait(0)
        if (GetGameTimer() - t) > (maxMs or 250) then break end
    end
end

local function spawnAndFrame(modelName)
    local ped = PlayerPedId()
    local px, py, pz = table.unpack(GetEntityCoords(ped))
    local forward = GetEntityForwardVector(ped)
    local sx, sy, sz = px + forward.x * 2.5, py + forward.y * 2.5, pz

    local hash = loadModelFast(modelName, 2500)
    if not hash then return false, 'model timeout' end

    local obj = CreateObjectNoOffset(hash, sx, sy, sz, false, false, false)
    if not DoesEntityExist(obj) then return false, 'create failed' end

    SetEntityHeading(obj, GetEntityHeading(ped))   -- neutral; camera provides angle
    FreezeEntityPosition(obj, true)
    SetEntityCollision(obj, false, false)
    SetEntityLodDist(obj, 9999)
    SetEntityAsMissionEntity(obj, true, false)

    -- quick settle on ground; short collision wait
    PlaceObjectOnGroundProperly(obj)
    waitCollisionReady(obj, 200)

    lastObj = obj
    ensureCamera()
    positionCamera(obj, -30.0)

    -- let a couple frames render with camera locked
    Wait(0); Wait(0)
    return true
end

--========================
-- Screenshot ACK (event-driven)
--========================

RegisterNetEvent('objshot:capture:done', function(modelName, ok, err, token)
    if token ~= currentToken then
        -- Uncomment for debugging:
        print(("[objshot] (late/mismatch ack) %s token=%s (expecting %s)")
           :format(tostring(modelName), tostring(token), tostring(currentToken)))
        return
    end
    if ok then
        lastErr = nil
    else
        lastErr = err or 'unknown'
    end

    awaitingAck = false
end)

--========================
-- Commands
--========================

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
    startIdx   = tonumber(args[1]) or PropSet.start
    endIdx     = tonumber(args[2]) or PropSet.finish
    batchLabel = args[3] or ("set_" .. tostring(startIdx) .. "_" .. tostring(endIdx))

    -- Clamp within bounds
    startIdx = math.max(1, math.min(startIdx, #Object_List))
    endIdx   = math.max(1, math.min(endIdx,   #Object_List))
    if endIdx < startIdx then
        print("[objshot] Invalid range. finish < start.")
        return
    end

    -- hard safety: discourage very large batches (keep under 2000)
    local batchCount = (endIdx - startIdx + 1)
    if batchCount > 2000 then
        print(("[objshot] Warning: batch size %d > 2000. Clamping to 2000 to avoid issues."):format(batchCount))
        endIdx = startIdx + 2000 - 1
        batchCount = 2000
    end

    print(("[objshot] Starting batch %s: %d..%d of %d")
        :format(batchLabel or "default", startIdx, endIdx, #Object_List))

    running = true
    idx = startIdx
    environmentPreset()
    ensureCamera()

    -- prefetch next item up-front
    if (idx + 1) <= endIdx then
        prefetchModel(Object_List[idx + 1])
    end

    CreateThread(function()
        while running and idx <= endIdx do
            clearCurrent()
            lastErr = nil

            local name = Object_List[idx]
            local ok, err = spawnAndFrame(name)
            if not ok then
                print(("[objshot] Failed %s (%s)"):format(tostring(name), tostring(err)))
                idx = idx + 1
                if (idx + 1) <= endIdx then prefetchModel(Object_List[idx + 1]) end
                goto next_item
            end

            print(("[objshot] Capturing %s (%d/%d)")
                :format(name, (idx - startIdx + 1), (endIdx - startIdx + 1)))

            -- Fire screenshot and wait for the server ack with a token
            captureToken = captureToken + 1
            currentToken = captureToken
            awaitingAck = true
            lastErr = nil

            -- pass the token as 3rd arg
            TriggerServerEvent('objshot:capture', name, batchLabel, currentToken)

            -- >>> limit the scope of t0 so goto can't jump into it
            do
                -- wait up to ~2s for ack; proceed sooner if it arrives
                local t0 = GetGameTimer()
                while awaitingAck do
                    Wait(0)
                    if (GetGameTimer() - t0) > 5000 then
                        print("[objshot] Screenshot ack timed out; continuing…")
                        awaitingAck = false
                        break
                    end
                end
            end
            -- <<< end limited scope

            if lastErr then
                print(("[objshot] ERROR capturing %s: %s"):format(name, lastErr))
            end

            -- prefetch the next model while we move on
            if (idx + 1) <= endIdx then
                prefetchModel(Object_List[idx + 1])
            end

            ::next_item::
            idx = idx + 1
            Wait(0) -- yield a frame to keep things responsive
        end

        -- teardown
        clearCurrent()
        if cam then
            RenderScriptCams(false, true, 300, true, true, 0)
            DestroyCam(cam, false)
            cam = nil
            DisplayRadar(true)
        end
        running = false
        print("[objshot] Finished batch. [" .. tostring(batchLabel) .. "]")
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


--========================
-- Cleanup
--========================

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
