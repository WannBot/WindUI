--[[ 
WS • Auto Walk (Obsidian UI)
- UI: Obsidian (Library + ThemeManager + SaveManager)
- 3 Tabs: Main Control, Data, Platform List
- Status label real-time (tanpa "WS" prefix)
- Seluruh logika (record, replay, save, load, pathfinding, force move, chunking) disalin dari script lama dan TIDAK DIUBAH secara fungsional.

Catatan:
- Tidak membuat ScreenGui/Instance.new UI lama lagi.
- Semua tombol/event di-wire ke fungsi yang setara dengan versi lama.
]]

----------------------------------------------------------
-- DEPENDENCIES (Obsidian)
----------------------------------------------------------
local OBS_REPO = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(OBS_REPO.."Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(OBS_REPO.."addons/ThemeManager.lua"))()
local SaveManager  = loadstring(game:HttpGet(OBS_REPO.."addons/SaveManager.lua"))()

----------------------------------------------------------
-- SERVICES & PLAYER
----------------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer or Players.PlayerAdded:Wait()
player:WaitForChild("PlayerGui")

----------------------------------------------------------
-- STATE & DATA (disalin dari script lama)
----------------------------------------------------------
local recording = false
local replaying = false
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local lastPosition = nil

local platforms = {}           -- Red platforms (Part)
local yellowPlatforms = {}     -- Yellow platforms (Part)
local platformData = {}        -- [platform] = { {position=Vector3, orientation=Vector3, isJumping=bool}, ...}
local yellowToRedMapping = {}  -- [yellowPart] = redPart
local platformCounter = 0

-- Replay control
local currentReplayThread = nil
local shouldStopReplay = false
local currentPlatformIndex = 0
local totalPlatformsToPlay = 0

-- Force movement
local forceActiveConnection = nil
local forceSpeedMultiplier = 1.0
local isClimbing = false
local allConnections = {}

-- Chunk save
local saveChunks = {}
local currentChunkIndex = 0
local totalChunks = 0
local CHUNK_SIZE = 20

----------------------------------------------------------
-- HELPERS: Character/Force Movement (disalin)
----------------------------------------------------------
local function setupCharacterForce(characterToSetup)
    local humanoidToSetup = characterToSetup:WaitForChild("Humanoid")
    local function onStateChanged(_, newState)
        isClimbing = (newState == Enum.HumanoidStateType.Climbing)
    end
    local stateConnection = humanoidToSetup.StateChanged:Connect(onStateChanged)
    table.insert(allConnections, stateConnection)
end

local function stopForceMovement()
    if forceActiveConnection then
        forceActiveConnection:Disconnect()
        forceActiveConnection = nil
    end
    local char = player.Character
    if char and char.PrimaryPart then
        local rootPart = char.PrimaryPart
        rootPart.AssemblyLinearVelocity = Vector3.new(0, rootPart.AssemblyLinearVelocity.Y, 0)
    end
end

local function startForceMovement()
    if forceActiveConnection then return end
    forceActiveConnection = RunService.Heartbeat:Connect(function()
        local char = player.Character
        local rootPart = char and char.PrimaryPart
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not rootPart or not hum then
            stopForceMovement()
            return
        end
        if isClimbing then return end
        local verticalVelocity = rootPart.AssemblyLinearVelocity.Y
        local moveSpeed = hum.WalkSpeed * forceSpeedMultiplier
        local lookVector = rootPart.CFrame.LookVector
        local horizontalDirection = Vector3.new(lookVector.X, 0, lookVector.Z).Unit
        local horizontalVelocity = horizontalDirection * moveSpeed
        rootPart.AssemblyLinearVelocity = Vector3.new(horizontalVelocity.X, verticalVelocity, horizontalVelocity.Z)
    end)
end

local function calculatePath(start, goal)
    local path = PathfindingService:CreatePath()
    path:ComputeAsync(start, goal)
    return path
end

local function isCharacterMoving()
    local currentPosition = character.PrimaryPart.Position
    if lastPosition then
        local distance = (currentPosition - lastPosition).Magnitude
        lastPosition = currentPosition
        return distance > 0.05
    end
    lastPosition = currentPosition
    return false
end

local function addTextLabelToPlatform(platform, platformNumber)
    local billboardGui = Instance.new("BillboardGui")
    billboardGui.Size = UDim2.new(1, 0, 0.5, 0)
    billboardGui.StudsOffset = Vector3.new(0, 3, 0)
    billboardGui.AlwaysOnTop = true
    local textLabel = Instance.new("TextLabel")
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    textLabel.TextScaled = true
    textLabel.Text = tostring(platformNumber)
    textLabel.Parent = billboardGui
    billboardGui.Parent = platform
end

local function cleanupPlatform(platform)
    for i, p in ipairs(platforms) do
        if p == platform then
            table.remove(platforms, i)
            platformData[platform] = nil
            break
        end
    end
end

----------------------------------------------------------
-- SERIALIZE / DESERIALIZE (disalin)
----------------------------------------------------------
local function serializePlatformData()
    local data = { redPlatforms = {}, yellowPlatforms = {}, mappings = {} }
    for i, platform in ipairs(platforms) do
        local movementsData = {}
        for _, movement in ipairs(platformData[platform] or {}) do
            table.insert(movementsData, {
                position = { X = movement.position.X, Y = movement.position.Y, Z = movement.position.Z },
                orientation = { X = movement.orientation.X, Y = movement.orientation.Y, Z = movement.orientation.Z },
                isJumping = movement.isJumping
            })
        end
        table.insert(data.redPlatforms, {
            position = { X = platform.Position.X, Y = platform.Position.Y, Z = platform.Position.Z },
            movements = movementsData
        })
    end
    for i, yellowPlatform in ipairs(yellowPlatforms) do
        table.insert(data.yellowPlatforms, {
            position = { X = yellowPlatform.Position.X, Y = yellowPlatform.Position.Y, Z = yellowPlatform.Position.Z }
        })
        if yellowToRedMapping[yellowPlatform] then
            local redIndex = table.find(platforms, yellowToRedMapping[yellowPlatform])
            table.insert(data.mappings, redIndex)
        end
    end
    return HttpService:JSONEncode(data)
end

local function deserializePlatformData(jsonData)
    local success, data = pcall(function() return HttpService:JSONDecode(jsonData) end)
    if not success then
        return false, "Failed to decode JSON data"
    end
    if not data or type(data) ~= "table" then
        return false, "Invalid data format"
    end

    -- Clear existing
    for _, platform in ipairs(platforms) do platform:Destroy() end
    for _, yellowPlatform in ipairs(yellowPlatforms) do yellowPlatform:Destroy() end
    platforms, yellowPlatforms, yellowToRedMapping, platformData = {}, {}, {}, {}
    platformCounter = 0

    -- Red platforms
    if data.redPlatforms then
        for _, platformInfo in ipairs(data.redPlatforms) do
            local platform = Instance.new("Part")
            platform.Size = Vector3.new(5, 1, 5)
            platform.Position = Vector3.new(platformInfo.position.X, platformInfo.position.Y, platformInfo.position.Z)
            platform.Anchored = true
            platform.BrickColor = BrickColor.Red()
            platform.CanCollide = false
            platform.Parent = workspace

            local restoredMovements = {}
            if platformInfo.movements then
                for _, movement in ipairs(platformInfo.movements) do
                    table.insert(restoredMovements, {
                        position = Vector3.new(movement.position.X, movement.position.Y, movement.position.Z),
                        orientation = Vector3.new(movement.orientation.X, movement.orientation.Y, movement.orientation.Z),
                        isJumping = movement.isJumping
                    })
                end
            end
            platformData[platform] = restoredMovements

            addTextLabelToPlatform(platform, #platforms + 1)
            table.insert(platforms, platform)
            platformCounter += 1
        end
    end

    -- Yellow + mappings
    if data.yellowPlatforms then
        for i, yellowInfo in ipairs(data.yellowPlatforms) do
            local yellowPlatform = Instance.new("Part")
            yellowPlatform.Size = Vector3.new(5, 1, 5)
            yellowPlatform.Position = Vector3.new(yellowInfo.position.X, yellowInfo.position.Y, yellowInfo.position.Z)
            yellowPlatform.Anchored = true
            yellowPlatform.BrickColor = BrickColor.Yellow()
            yellowPlatform.CanCollide = false
            yellowPlatform.Parent = workspace

            if data.mappings and data.mappings[i] then
                addTextLabelToPlatform(yellowPlatform, data.mappings[i])
                if platforms[data.mappings[i]] then
                    yellowToRedMapping[yellowPlatform] = platforms[data.mappings[i]]
                end
            end
            table.insert(yellowPlatforms, yellowPlatform)
        end
    end

    return true
end

----------------------------------------------------------
-- RECORD / STOP / DELETE / DESTROY (dibuat fungsi)
----------------------------------------------------------
local function UpdateStatus(text)
    -- setter status untuk UI Obsidian (di-assign setelah UI dibuat)
    if getfenv().__WS_STATUS_LABEL then
        getfenv().__WS_STATUS_LABEL:SetText("Status: "..text)
    end
end

local function StartRecord()
    if recording then return end
    recording = true
    UpdateStatus("Recording")

    -- Jika sudah ada yellow, jalan ke titik terakhir dulu
    if #yellowPlatforms > 0 then
        local lastYellowPlatform = yellowPlatforms[#yellowPlatforms]
        local humanoidCurrent = character:WaitForChild("Humanoid")
        local rootPart = character:WaitForChild("HumanoidRootPart")
        if humanoidCurrent and humanoidCurrent.Health > 0 then
            local path = calculatePath(rootPart.Position, lastYellowPlatform.Position + Vector3.new(0,3,0))
            if path.Status == Enum.PathStatus.Success then
                for _, waypoint in ipairs(path:GetWaypoints()) do
                    humanoidCurrent:MoveTo(waypoint.Position)
                    if waypoint.Action == Enum.PathWaypointAction.Jump then
                        humanoidCurrent.Jump = true
                    end
                    humanoidCurrent.MoveToFinished:Wait()
                end
            else
                humanoidCurrent:MoveTo(lastYellowPlatform.Position + Vector3.new(0,3,0))
                humanoidCurrent.MoveToFinished:Wait()
            end
        end
    else
        -- Penjaga (no-op)
        if character and character.PrimaryPart then
            character:SetPrimaryPartCFrame(CFrame.new(character.PrimaryPart.Position))
        end
    end

    -- Buat red platform baru
    platformCounter += 1
    local platform = Instance.new("Part")
    platform.Name = "Platform " .. platformCounter
    platform.Size = Vector3.new(5, 1, 5)
    platform.Position = character.PrimaryPart.Position - Vector3.new(0, 3, 0)
    platform.Anchored = true
    platform.BrickColor = BrickColor.Red()
    platform.CanCollide = false
    platform.Parent = workspace
    addTextLabelToPlatform(platform, platformCounter)
    table.insert(platforms, platform)
    platformData[platform] = {}

    -- Rekam per Heartbeat
    task.spawn(function()
        while recording do
            if not platform or not platform.Parent then
                recording = false
                UpdateStatus("Error: Missing Red Platform (Recording Stopped)")
                break
            end
            if isCharacterMoving() then
                table.insert(platformData[platform], {
                    position   = character.PrimaryPart.Position,
                    orientation= character.PrimaryPart.Orientation,
                    isJumping  = humanoid.Jump
                })
            end
            RunService.Heartbeat:Wait()
        end
    end)
end

local function StopRecord()
    if not recording then return end
    recording = false
    UpdateStatus("Stopped Recording")

    local yellowPlatform = Instance.new("Part")
    yellowPlatform.Size = Vector3.new(5, 1, 5)
    yellowPlatform.Position = character.PrimaryPart.Position - Vector3.new(0, 3, 0)
    yellowPlatform.Anchored = true
    yellowPlatform.BrickColor = BrickColor.Yellow()
    yellowPlatform.CanCollide = false
    yellowPlatform.Parent = workspace

    addTextLabelToPlatform(yellowPlatform, platformCounter)
    table.insert(yellowPlatforms, yellowPlatform)
    yellowToRedMapping[yellowPlatform] = platforms[#platforms]
end

local function StopReplay()
    if replaying then
        shouldStopReplay = true
        replaying = false
        stopForceMovement()
        if character:FindFirstChild("Humanoid") and character:FindFirstChild("HumanoidRootPart") then
            character.Humanoid:MoveTo(character.HumanoidRootPart.Position)
        end
        UpdateStatus(("Stopped at Platform %d/%d"):format(math.max(currentPlatformIndex-1,0), totalPlatformsToPlay))
        task.delay(1.0, function() UpdateStatus("Idle") end)
    end
end

local function DestroyAll()
    for _, platform in ipairs(platforms) do platform:Destroy() end
    for _, yellowPlatform in ipairs(yellowPlatforms) do yellowPlatform:Destroy() end
    platforms, yellowPlatforms, platformData, yellowToRedMapping = {}, {}, {}, {}
    platformCounter = 0
    stopForceMovement()
    for _, c in ipairs(allConnections) do c:Disconnect() end
    allConnections = {}
    UpdateStatus("Idle")
end

local function DeleteLastPlatform()
    if #platforms == 0 then return end
    local lastPlatform = platforms[#platforms]
    lastPlatform:Destroy()
    cleanupPlatform(lastPlatform)

    -- hapus label/tampilan (di UI baru ini list pakai dropdown -> akan di-refresh)
    platformCounter -= 1

    -- Bersihkan yellow yang map ke platform yang sudah dihapus
    for yellowPlatform, redPlatform in pairs(yellowToRedMapping) do
        if not table.find(platforms, redPlatform) then
            yellowPlatform:Destroy()
            yellowToRedMapping[yellowPlatform] = nil
            local idx = table.find(yellowPlatforms, yellowPlatform)
            if idx then table.remove(yellowPlatforms, idx) end
        end
    end
end

----------------------------------------------------------
-- SAVE / NEXT CHUNK / LOAD (URL/RAW + stacking) (disalin)
----------------------------------------------------------
local function SaveAll()
    local jsonData = serializePlatformData()
    if #jsonData > 190000 then
        local allData = HttpService:JSONDecode(jsonData)
        saveChunks = {}
        local redCount = #allData.redPlatforms
        totalChunks = math.ceil(redCount / CHUNK_SIZE)
        for chunkIndex = 1, totalChunks do
            local startIndex = (chunkIndex-1)*CHUNK_SIZE + 1
            local endIndex = math.min(chunkIndex*CHUNK_SIZE, redCount)
            local chunk = { redPlatforms = {}, yellowPlatforms = {}, mappings = {} }
            for i = startIndex, endIndex do
                table.insert(chunk.redPlatforms, allData.redPlatforms[i])
            end
            for i, mapping in ipairs(allData.mappings) do
                if mapping >= startIndex and mapping <= endIndex then
                    table.insert(chunk.yellowPlatforms, allData.yellowPlatforms[i])
                    table.insert(chunk.mappings, mapping - startIndex + 1)
                end
            end
            saveChunks[chunkIndex] = HttpService:JSONEncode(chunk)
        end
        currentChunkIndex = 1
        setclipboard(saveChunks[currentChunkIndex])
        UpdateStatus(("Chunk %d/%d copied. Save then press Next Chunk"):format(currentChunkIndex, totalChunks))
    else
        setclipboard(jsonData)
        saveChunks, currentChunkIndex, totalChunks = {}, 0, 0
        UpdateStatus("Platform data copied to clipboard")
    end
end

local function NextChunk()
    if #saveChunks > 0 and currentChunkIndex < totalChunks then
        currentChunkIndex += 1
        setclipboard(saveChunks[currentChunkIndex])
        UpdateStatus(("Chunk %d/%d copied"):format(currentChunkIndex, totalChunks))
    elseif currentChunkIndex == totalChunks and totalChunks > 0 then
        UpdateStatus("All chunks have been copied")
    else
        UpdateStatus("No chunks to copy")
    end
end

local function _LoadFromString(input)
    local loadedSuccessfully = false
    if input:match("^https?://") then
        UpdateStatus("Loading 0%")
        local ok, response = pcall(function() return game:HttpGet(input) end)
        if ok and response then
            -- coba stacked line-per-line
            local combinedData = { redPlatforms={}, yellowPlatforms={}, mappings={} }
            local redOffset = 0
            local stackedOK = false
            for jsonStr in response:gmatch("[^\r\n]+") do
                local okj, chunk = pcall(function() return HttpService:JSONDecode(jsonStr) end)
                if okj and type(chunk)=="table" and type(chunk.redPlatforms)=="table" then
                    stackedOK = true
                    for _, rp in ipairs(chunk.redPlatforms) do table.insert(combinedData.redPlatforms, rp) end
                    if type(chunk.yellowPlatforms)=="table" then
                        for i, yp in ipairs(chunk.yellowPlatforms) do
                            table.insert(combinedData.yellowPlatforms, yp)
                            if type(chunk.mappings)=="table" and chunk.mappings[i] then
                                table.insert(combinedData.mappings, chunk.mappings[i] + redOffset)
                            end
                        end
                    end
                    redOffset += #chunk.redPlatforms
                end
            end
            if stackedOK then
                local combinedJson = HttpService:JSONEncode(combinedData)
                local ok2 = deserializePlatformData(combinedJson)
                loadedSuccessfully = ok2 and true or false
            else
                loadedSuccessfully = deserializePlatformData(response)
            end
        else
            UpdateStatus("Load failed (URL)")
            return
        end
    else
        -- RAW input: coba stacked
        local combinedData = { redPlatforms={}, yellowPlatforms={}, mappings={} }
        local redOffset = 0
        local stackedOK = false
        for jsonStr in input:gmatch("[^\r\n]+") do
            local okj, chunk = pcall(function() return HttpService:JSONDecode(jsonStr) end)
            if okj and type(chunk)=="table" and type(chunk.redPlatforms)=="table" then
                stackedOK = true
                for _, rp in ipairs(chunk.redPlatforms) do table.insert(combinedData.redPlatforms, rp) end
                if type(chunk.yellowPlatforms)=="table" then
                    for i, yp in ipairs(chunk.yellowPlatforms) do
                        table.insert(combinedData.yellowPlatforms, yp)
                        if type(chunk.mappings)=="table" and chunk.mappings[i] then
                            table.insert(combinedData.mappings, chunk.mappings[i] + redOffset)
                        end
                    end
                end
                redOffset += #chunk.redPlatforms
            end
        end
        if stackedOK then
            local combinedJson = HttpService:JSONEncode(combinedData)
            local ok2 = deserializePlatformData(combinedJson)
            loadedSuccessfully = ok2 and true or false
        else
            loadedSuccessfully = deserializePlatformData(input)
        end
    end

    if loadedSuccessfully then
        UpdateStatus("Platform data loaded")
    else
        UpdateStatus("Failed to parse/load data")
    end
end

----------------------------------------------------------
-- REPLAY PLATFORM (disalin, diringkas sebagai fungsi)
----------------------------------------------------------
local function walkToPlatform(destination)
    local humanoidCurrent = character:WaitForChild("Humanoid")
    local rootPart = character:WaitForChild("HumanoidRootPart")
    if not humanoidCurrent or humanoidCurrent.Health <= 0 then return end
    local path = calculatePath(rootPart.Position, destination)
    if path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()
        for _, waypoint in ipairs(waypoints) do
            if shouldStopReplay then break end
            humanoidCurrent:MoveTo(waypoint.Position)
            if waypoint.Action == Enum.PathWaypointAction.Jump then
                humanoidCurrent.Jump = true
            end
            humanoidCurrent.MoveToFinished:Wait()
        end
    else
        humanoidCurrent:MoveTo(destination)
        humanoidCurrent.MoveToFinished:Wait()
    end
end

local function ReplayFrom(indexStart)
    totalPlatformsToPlay = #platforms
    currentPlatformIndex = indexStart
    for i = indexStart, #platforms do
        if shouldStopReplay then break end
        UpdateStatus(("Playing from Platform %d/%d"):format(currentPlatformIndex, totalPlatformsToPlay))
        local currentPlatform = platforms[i]

        -- Phase 1: pathfind ke platform
        stopForceMovement()
        walkToPlatform(currentPlatform.Position + Vector3.new(0,3,0))
        if shouldStopReplay then break end

        -- Phase 2: interpolasi movement
        local movements = platformData[currentPlatform]
        if movements and #movements > 1 then
            startForceMovement()
            for j = 1, #movements-1 do
                if shouldStopReplay then break end
                local a = movements[j]
                local b = movements[j+1]
                b.isJumping = a.isJumping

                local startTime = tick()
                local distance = (b.position - a.position).Magnitude
                local duration = math.max(distance * 0.01, 0.01)
                local endTime = startTime + duration

                while tick() < endTime do
                    if shouldStopReplay then break end
                    local alpha = math.clamp((tick() - startTime)/duration, 0, 1)
                    local pos = a.position:Lerp(b.position, alpha)
                    local cfA = CFrame.fromEulerAnglesXYZ(math.rad(a.orientation.X), math.rad(a.orientation.Y), math.rad(a.orientation.Z))
                    local cfB = CFrame.fromEulerAnglesXYZ(math.rad(b.orientation.X), math.rad(b.orientation.Y), math.rad(b.orientation.Z))
                    local rot = cfA:Lerp(cfB, alpha)
                    character:SetPrimaryPartCFrame(CFrame.new(pos) * rot)
                    if b.isJumping then humanoid.Jump = true end
                    RunService.Heartbeat:Wait()
                end
            end
            stopForceMovement()
        end

        task.wait(0.5)
        currentPlatformIndex += 1
    end

    if not shouldStopReplay then
        UpdateStatus("Completed all platforms")
        task.wait(1)
    end
    replaying = false
    UpdateStatus("Idle")
    stopForceMovement()
end

local function PlayPlatform(index)
    if replaying then return end
    if currentReplayThread then shouldStopReplay = true task.wait() end
    if not index or index < 1 or index > #platforms then
        UpdateStatus("Invalid platform index")
        return
    end
    replaying = true
    shouldStopReplay = false
    currentReplayThread = task.spawn(function()
        ReplayFrom(index)
        currentReplayThread = nil
    end)
end

----------------------------------------------------------
-- PLATFORM LIST HELPERS (untuk Tab Platform List)
----------------------------------------------------------
local function GetPlatformList()
    local list = {}
    for i = 1, #platforms do
        list[i] = ("Platform %d"):format(i)
    end
    if #list == 0 then list = {"(no platforms)"} end
    return list
end

local function DeletePlatformIndex(idx)
    if not idx or idx < 1 or idx > #platforms then return end
    local p = platforms[idx]
    if p then p:Destroy() end
    cleanupPlatform(p)
    -- bersihkan yellow yang map ke platform ini
    for yellowPlatform, redPlatform in pairs(yellowToRedMapping) do
        if redPlatform == p then
            yellowPlatform:Destroy()
            yellowToRedMapping[yellowPlatform] = nil
            local iy = table.find(yellowPlatforms, yellowPlatform)
            if iy then table.remove(yellowPlatforms, iy) end
        end
    end
    platformCounter = #platforms
end

local function HighlightPlatformIndex(idx)
    if not idx or idx < 1 or idx > #platforms then return end
    local p = platforms[idx]
    if not p then return end
    local old = p.Color
    p.Color = Color3.fromRGB(0, 255, 0)
    task.delay(0.5, function() if p and p.Parent then p.Color = old end end)
end

----------------------------------------------------------
-- RESPAWN HANDLER (disalin)
----------------------------------------------------------
player.CharacterAdded:Connect(function(newCharacter)
    character = newCharacter
    humanoid = newCharacter:WaitForChild("Humanoid")
    lastPosition = nil
    UpdateStatus("Idle")

    for _, c in ipairs(allConnections) do c:Disconnect() end
    allConnections = {}
    setupCharacterForce(newCharacter)

    if recording then
        platforms, yellowPlatforms, platformData, yellowToRedMapping = {}, {}, {}, {}
        platformCounter = 0
    end

    stopForceMovement()
    shouldStopReplay = true
    replaying = false
    if currentReplayThread then
        task.cancel(currentReplayThread)
        currentReplayThread = nil
    end
end)

if player.Character then setupCharacterForce(player.Character) end

----------------------------------------------------------
-- OBSIDIAN UI
----------------------------------------------------------
local Window = Library:CreateWindow({
    Title = "WS",
    Footer = "Auto Walk (Obsidian)",
    Icon = 95816097006870,
    ShowCustomCursor = true,
})

local Tabs = {
    Main  = Window:AddTab("Main Control", "zap"),
    Data  = Window:AddTab("Data", "folder"),
    List  = Window:AddTab("Platform List", "map"),
    Theme = Window:AddTab("Setting", "settings"),
}

-- ===== Status label global (pojok bawah)
local StatusBox = Tabs.Main:AddRightGroupbox("Status")
local __statusLabel = StatusBox:AddLabel("Status: Idle")
getfenv().__WS_STATUS_LABEL = __statusLabel

-- ===== Tab Main Control
local MC_L = Tabs.Main:AddLeftGroupbox("Actions")
MC_L:AddButton("Record", StartRecord)
MC_L:AddButton("Stop Record", StopRecord)
MC_L:AddButton("Stop Replay", StopReplay)
MC_L:AddButton("Delete (Last Red)", DeleteLastPlatform)
MC_L:AddButton("Destroy All", DestroyAll)

-- ===== Tab Data
local D_L = Tabs.Data:AddLeftGroupbox("Save / Chunk")
D_L:AddButton("Save", SaveAll)
D_L:AddButton("Next Chunk", NextChunk)

local D_R = Tabs.Data:AddRightGroupbox("Load JSON/URL")
local _loadInput = ""
D_R:AddInput("WS_LoadInput", {
    Text = "Paste RAW JSON atau URL",
    Default = "",
    Placeholder = "https://... | { ...json... }",
    Finished = true,
    Callback = function(v) _loadInput = v or "" end
})
D_R:AddButton("Load", function()
    if (_loadInput or ""):gsub("%s","") == "" then
        UpdateStatus("No data to load")
        return
    end
    _LoadFromString(_loadInput)
end)

-- ===== Tab Platform List
local PL_L = Tabs.List:AddLeftGroupbox("Select Platform")
local currentList = GetPlatformList()
local currentIndex = 1
local dd = PL_L:AddDropdown("WS_PlatformPick", {
    Values = currentList,
    Default = currentList[1],
    Multi = false,
    Text = "Platforms",
    Callback = function(val)
        for i, v in ipairs(currentList) do
            if v == val then currentIndex = i break end
        end
    end
})
PL_L:AddButton("Refresh", function()
    currentList = GetPlatformList()
    dd:SetValues(currentList)
    dd:SetValue(currentList[1])
    currentIndex = 1
    UpdateStatus("Platform list refreshed")
end)

local PL_R = Tabs.List:AddRightGroupbox("Action")
PL_R:AddButton("Play Selected", function() PlayPlatform(currentIndex) end)
PL_R:AddButton("Delete Selected", function()
    DeletePlatformIndex(currentIndex)
    currentList = GetPlatformList()
    dd:SetValues(currentList)
    dd:SetValue(currentList[1])
    currentIndex = 1
end)
PL_R:AddButton("Highlight Selected", function() HighlightPlatformIndex(currentIndex) end)

-- ===== Theme / Config
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
ThemeManager:SetFolder("WS_UI")
SaveManager:SetFolder("WS_UI/config")
SaveManager:BuildConfigSection(Tabs.Theme)
ThemeManager:ApplyToTab(Tabs.Theme)
Library.ToggleKeybind = Enum.KeyCode.RightShift
