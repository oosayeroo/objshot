local SAVE_SUBDIR = 'objshot'  -- inside screenshot-basic/screenshots/

-- Capture a client screenshot and save it with the model name as the filename
RegisterNetEvent('objshot:capture', function(modelName)
    local src = source
    if not src then return end

    -- sanitize filename just in case
    local safe = tostring(modelName):gsub('[^%w%-_%.]', '_')
    local filename = ('%s/%s.png'):format(SAVE_SUBDIR, safe)

    exports['screenshot-basic']:requestClientScreenshot(src, {
        fileName = filename,
        quality = 1.0,
        encoding = 'png', -- force PNG so extension always matches
    }, function(err, data)
        if err then
            print(('[objshot] ERROR saving %s: %s'):format(safe, err))
        else
            print(('[objshot] Saved: %s.png'):format(safe))
        end
    end)
end)
