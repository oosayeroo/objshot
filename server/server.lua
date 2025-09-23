-- server.lua
local SAVE_SUBDIR = 'objshot'  -- inside screenshot-basic/screenshots/

RegisterNetEvent('objshot:capture', function(modelName, batchLabel, token)
    local src = source
    if not src then return end

    local safe = tostring(modelName):gsub('[^%w%-_%.]', '_')
    local filename = ('%s/%s.webp'):format(SAVE_SUBDIR, safe)

    exports['screenshot-basic']:requestClientScreenshot(src, {
        fileName = filename,
        quality = 0.8,
        encoding = 'webp',
        -- (optional) maxWidth = 1280, maxHeight = 720,
    }, function(err, data)
        if err then
            print(('[objshot] ERROR saving %s: %s'):format(safe, err))
            TriggerClientEvent('objshot:capture:done', src, modelName, false, tostring(err), token)
        else
            print(('[objshot] Saved: %s.webp'):format(safe))
            TriggerClientEvent('objshot:capture:done', src, modelName, true, nil, token)
        end
    end)
end)


local function pretty_json(s)
    local indent, pretty = 0, {}
    local i = 1
    local in_string, esc = false, false
    while i <= #s do
        local c = s:sub(i, i)
        if in_string then
            table.insert(pretty, c)
            if esc then
                esc = false
            elseif c == "\\" then
                esc = true
            elseif c == '"' then
                in_string = false
            end
        else
            if c == '"' then
                in_string = true
                table.insert(pretty, c)
            elseif c == "{" or c == "[" then
                indent = indent + 1
                table.insert(pretty, c .. "\n" .. string.rep("  ", indent))
            elseif c == "}" or c == "]" then
                indent = indent - 1
                table.insert(pretty, "\n" .. string.rep("  ", indent) .. c)
            elseif c == "," then
                table.insert(pretty, c .. "\n" .. string.rep("  ", indent))
            elseif c == ":" then
                table.insert(pretty, ": ")
            elseif c:match("%s") then
                -- skip existing whitespace
            else
                table.insert(pretty, c)
            end
        end
        i = i + 1
    end
    return table.concat(pretty)
end

RegisterNetEvent('objshot:server:SaveAllVehiclesJSON', function(payload)
    local jsonTbl = json.encode(payload)
    -- payload is a JSON string where keys are model names
    if type(jsonTbl) ~= "string" or #jsonTbl == 0 then
        print("^1SaveAllVehiclesJSON: invalid payload^0")
        return
    end

    local ok, decoded = pcall(json.decode, jsonTbl)
    if not ok or type(decoded) ~= "table" then
        print("^1SaveAllVehiclesJSON: failed to decode JSON^0")
        return
    end

    -- Convert to an array and sort by .model (alphabetical, case-insensitive)
    local arr = {}
    for _, v in pairs(decoded) do
        if type(v) == "table" then
            table.insert(arr, v)
        end
    end
    table.sort(arr, function(a, b)
        local am = (a.model or ""):lower()
        local bm = (b.model or ""):lower()
        return am < bm
    end)

    local compact = json.encode(arr)
    local pretty = pretty_json(compact)

    local dateStr = os.date("%d-%m-%Y")  -- 23-09-2025
    local fileName = ("vehicles_%s.json"):format(dateStr)

    local resource = GetCurrentResourceName()
    -- You can choose pretty or compact. Pretty is nicer to read:
    local dataToSave = pretty

    local okSave = SaveResourceFile(resource, fileName, dataToSave, #dataToSave)
    if okSave then
        print(("Saved %d vehicles to %s/%s"):format(#arr, resource, fileName))
    else
        print(("^1Failed to save vehicles to %s/%s^0"):format(resource, fileName))
    end
end)
