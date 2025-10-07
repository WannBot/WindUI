-- WS Auto Walk Controller (Opsi B)
-- UI: Obsidian (deividcomsono / Linoria-based)
-- Fitur: Record (click-to-place), Load JSON (RAW GitHub), Save JSON (local/clipboard), Play/Stop, Clear, Chunking
-- Gerak avatar: SISTEM LAMA (Humanoid:MoveTo antar titik)

----------------------------------------------------
-- LOAD UI LIBRARIES
----------------------------------------------------
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library      = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

----------------------------------------------------
-- SERVICES & INIT
----------------------------------------------------
local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local mouse     = player:GetMouse()
local character = player.Character or player.CharacterAdded:Wait()
local hum       = character:WaitForChild("Humanoid")
local hrp       = character:WaitForChild("HumanoidRootPart")

-- refresh refs on respawn
player.CharacterAdded:Connect(function(char)
    character = char
    hum = char:WaitForChild("Humanoid")
    hrp = char:WaitForChild("HumanoidRootPart")
    task.wait(0.3)
    if _G.__WS_walkEnabled then hum.WalkSpeed = _G.__WS_walkSpeedValue or 16 end
    if _G.__WS_jumpEnabled then hum.UseJumpPower = true; hum.JumpPower = _G.__WS_jumpPowerValue or 50 end
end)

----------------------------------------------------
-- STATE (movement)
----------------------------------------------------
_G.__WS_walkEnabled     = false
_G.__WS_jumpEnabled     = false
_G.__WS_noclipEnabled   = false
_G.__WS_walkSpeedValue  = 16
_G.__WS_jumpPowerValue  = 50

-- apply helpers
local function applyWalk()
    if hum and hum.Parent then
        hum.WalkSpeed = _G.__WS_walkEnabled and _G.__WS_walkSpeedValue or 16
    end
end
local function applyJump()
    if hum and hum.Parent then
        hum.UseJumpPower = true
        hum.JumpPower = _G.__WS_jumpEnabled and _G.__WS_jumpPowerValue or 50
    end
end
RunService.Stepped:Connect(function()
    if _G.__WS_noclipEnabled and player.Character then
        for _, part in ipairs(player.Character:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = false end
        end
    end
end)

----------------------------------------------------
-- STATE (auto walk – SISTEM LAMA)
----------------------------------------------------
local recording          = false
local platforms          = {}      -- list of all point Parts (visual)
local pathChunks         = { { } } -- list of chunks; each chunk is array of {X,Y,Z}
local currentChunkIndex  = 1

local replaying          = false
local shouldStopReplay   = false

-- helpers
local function clearPlatforms()
    for _, p in ipairs(platforms) do
        if p and p.Parent then p:Destroy() end
    end
    table.clear(platforms)
end

local function spawnPoint(pos, color)
    local part = Instance.new("Part")
    part.Name = "WS_AutoWalk_Point"
    part.Anchored = true
    part.CanCollide = false
    part.Material = Enum.Material.Neon
    part.Color = color or Color3.fromRGB(255,190,80)
    part.Size = Vector3.new(0.9, 0.9, 0.9)
    part.Shape = Enum.PartType.Ball
    part.Position = pos
    part.Parent = workspace
    table.insert(platforms, part)
end

local function flattenChunks(chunks)
    -- menerima { {points...}, {points...}, ... } atau flat array
    -- return flat array of {X,Y,Z}
    local flat = {}
    if #chunks == 0 then return flat end
    if chunks[1] and chunks[1].X ~= nil then
        -- sudah flat
        return chunks
    end
    for _, chunk in ipairs(chunks) do
        for _, p in ipairs(chunk) do table.insert(flat, p) end
    end
    return flat
end

local function visualizeFromData(data)
    clearPlatforms()
    local flat = flattenChunks(data)
    for _, pos in ipairs(flat) do
        spawnPoint(Vector3.new(pos.X, pos.Y, pos.Z))
    end
end

local function serializeToJSON()
    -- simpan sebagai flat array untuk kompatibilitas (Path1.json kamu)
    local flat = flattenChunks(pathChunks)
    return HttpService:JSONEncode(flat)
end

local function loadFromJSON(jsonStr)
    -- terima JSON flat atau chunked
    local data = HttpService:JSONDecode(jsonStr)
    local flat = flattenChunks(data)
    -- rebuild chunks jadi 1 chunk saja (biar sederhana)
    pathChunks = { {} }
    currentChunkIndex = 1
    for _, p in ipairs(flat) do
        table.insert(pathChunks[1], {X=p.X, Y=p.Y, Z=p.Z})
    end
    visualizeFromData(pathChunks)
end

local function replayFlat(flat)
    if replaying or #flat == 0 then return end
    replaying = true
    shouldStopReplay = false
    local h = player.Character:WaitForChild("Humanoid")
    for i, pos in ipairs(flat) do
        if shouldStopReplay then break end
        h:MoveTo(Vector3.new(pos.X, pos.Y, pos.Z) + Vector3.new(0, 3, 0))
        h.MoveToFinished:Wait()
        task.wait(0.20)
    end
    replaying = false
end

local function replayAll()
    local flat = flattenChunks(pathChunks)
    replayFlat(flat)
end

----------------------------------------------------
-- RECORDING (click-to-place)
----------------------------------------------------
local recordConn
local function startRecording()
    if recording then return end
    recording = true
    Library:Notify("Recording started (tap tanah untuk menambah titik)", 2)

    -- pastikan chunk ada
    pathChunks[currentChunkIndex] = pathChunks[currentChunkIndex] or {}

    -- klik kiri untuk tambah titik
    recordConn = mouse.Button1Down:Connect(function()
        if not recording then return end
        local target = mouse.Hit and mouse.Hit.p
        if target then
            local point = { X = target.X, Y = target.Y, Z = target.Z }
            table.insert(pathChunks[currentChunkIndex], point)
            spawnPoint(Vector3.new(point.X, point.Y, point.Z), Color3.fromRGB(255,150,90))
        end
    end)
end

local function stopRecording()
    if not recording then return end
    recording = false
    if recordConn then
        recordConn:Disconnect()
        recordConn = nil
    end
    Library:Notify("Recording stopped", 1.5)
end

local function nextChunk()
    currentChunkIndex += 1
    pathChunks[currentChunkIndex] = {}
    Library:Notify("New chunk: "..tostring(currentChunkIndex), 1.5)
end

local function clearAll()
    stopRecording()
    clearPlatforms()
    pathChunks = { {} }
    currentChunkIndex = 1
end

----------------------------------------------------
-- LOAD / SAVE (URL & local)
----------------------------------------------------
local function loadFromURL(url)
    local ok, res = pcall(function() return game:HttpGet(url) end)
    if not ok or not res or #res == 0 then
        Library:Notify("Download gagal / kosong", 2)
        return
    end
    local ok2 = pcall(function() loadFromJSON(res) end)
    if not ok2 then
        Library:Notify("JSON invalid", 2)
        return
    end
    Library:Notify("Loaded: "..tostring(#flattenChunks(pathChunks)).." titik", 2)
end

local function saveToFile(fname)
    local json = serializeToJSON()
    if writefile then
        writefile(fname, json)
        Library:Notify("Saved: "..fname, 2)
    else
        Library:Notify("Executor tidak support writefile", 2)
    end
    if setclipboard then
        setclipboard(json)
        Library:Notify("JSON copied to clipboard", 2)
    end
end

----------------------------------------------------
-- WINDOW & TABS (UI)
----------------------------------------------------
local Window = Library:CreateWindow({
    Title = "WS",
    Footer = "Antartika Path Controller",
    Icon = 95816097006870,
    NotifySide = "Right",
    ShowCustomCursor = true,
})

local Tabs = {
    Main    = Window:AddTab("Main Fiture", "user"),
    Auto    = Window:AddTab("Auto Walk",   "move"),
    Setting = Window:AddTab("Setting",     "settings"),
}

----------------------------------------------------
-- TAB: MAIN FITURE (Walk/Jump/Noclip)
----------------------------------------------------
local MainBox = Tabs.Main:AddLeftGroupbox("Movement")

MainBox:AddToggle("WS_Walk_Toggle", {
    Text = "WalkSpeed ON/OFF",
    Default = false,
    Callback = function(v) _G.__WS_walkEnabled = v; applyWalk() end
})
MainBox:AddSlider("WS_Walk_Slider", {
    Text = "Speed",
    Default = 16, Min = 10, Max = 100, Rounding = 0,
    Callback = function(v) _G.__WS_walkSpeedValue = v; if _G.__WS_walkEnabled then applyWalk() end end
})

MainBox:AddToggle("WS_Jump_Toggle", {
    Text = "JumpPower ON/OFF",
    Default = false,
    Callback = function(v) _G.__WS_jumpEnabled = v; applyJump() end
})
MainBox:AddSlider("WS_Jump_Slider", {
    Text = "JumpPower",
    Default = 50, Min = 25, Max = 200, Rounding = 0,
    Callback = function(v) _G.__WS_jumpPowerValue = v; if _G.__WS_jumpEnabled then applyJump() end end
})

MainBox:AddToggle("WS_NoClip_Toggle", {
    Text = "NoClip ON/OFF",
    Default = false,
    Callback = function(v) _G.__WS_noclipEnabled = v end
})

----------------------------------------------------
-- TAB: AUTO WALK (SEMUA FITUR AUTO WALK DI SINI)
----------------------------------------------------
local AutoBoxLeft  = Tabs.Auto:AddLeftGroupbox("Controls")
local AutoBoxRight = Tabs.Auto:AddRightGroupbox("Load / Save")

-- RECORDING
AutoBoxLeft:AddButton("Record (click-to-place)", function()
    startRecording()
end)
AutoBoxLeft:AddButton("Stop Record", function()
    stopRecording()
end)
AutoBoxLeft:AddButton("Next Chunk", function()
    nextChunk()
end)
AutoBoxLeft:AddDivider()
AutoBoxLeft:AddButton("Play Loaded Path", function()
    replayAll()
end)
AutoBoxLeft:AddButton("Stop", function()
    shouldStopReplay = true
    replaying = false
    Library:Notify("Stopped", 1.5)
end)
AutoBoxLeft:AddButton("Clear Visual & Data", function()
    clearAll()
    Library:Notify("Cleared", 1.5)
end)

-- URL INPUT + LOAD
local baseURL = "https://raw.githubusercontent.com/WannBot/WindUI/refs/heads/main/"
local currentURL = baseURL .. "Path1.json"

AutoBoxRight:AddInput("WS_URL_Input", {
    Text = "GitHub RAW URL",
    Default = currentURL,
    Placeholder = "https://raw.githubusercontent.com/<user>/<repo>/<branch>/Path1.json",
    Numeric = false, Finished = true,
    Callback = function(value)
        if value and #value > 0 then currentURL = value end
    end
})
AutoBoxRight:AddButton("Load URL & Visualize", function()
    loadFromURL(currentURL)
end)

-- QUICK BUTTONS (Path1–Path5 dari repo kamu)
AutoBoxRight:AddDivider()
for i = 1, 5 do
    AutoBoxRight:AddButton("Play Path"..i, function()
        loadFromURL(baseURL .. "Path"..i..".json")
        -- langsung mainkan setelah load:
        task.spawn(function()
            replayAll()
        end)
    end)
end

-- SAVE
AutoBoxRight:AddDivider()
AutoBoxRight:AddInput("WS_SaveName", {
    Text = "Save as filename",
    Default = "WS_Path_"..os.time()..".json",
    Placeholder = "contoh: MyRoute.json",
    Numeric = false, Finished = true,
    Callback = function(_) end
})
AutoBoxRight:AddButton("Save JSON (file + clipboard)", function()
    local obj = Library.Flags.WS_SaveName
    local fname = (type(obj) == "table" and obj.Value) and obj.Value or "WS_Path_"..os.time()..".json"
    if not fname:lower():match("%.json$") then fname = fname .. ".json" end
    saveToFile(fname)
end)

----------------------------------------------------
-- TAB: SETTING
----------------------------------------------------
local SettingBox = Tabs.Setting:AddLeftGroupbox("Theme / Config")
SettingBox:AddDropdown("ThemeSelect", {
    Values = { "Dark", "Light", "Aqua", "Midnight" },
    Default = "Dark",
    Text = "Select Theme",
    Callback = function(opt) Window:SetTheme(opt) end,
})

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
ThemeManager:SetFolder("WS")
SaveManager:SetFolder("WS/config")
SaveManager:BuildConfigSection(Tabs.Setting)
ThemeManager:ApplyToTab(Tabs.Setting)

Library.ToggleKeybind = Enum.KeyCode.RightShift
