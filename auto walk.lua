-- ✅ Load Library Obsidian
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/deividcomsono/Obsidian/refs/heads/main/Library.lua"))()

-- ✅ Services
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local char = player.Character or player.CharacterAdded:Wait()
local hum = char:WaitForChild("Humanoid")

-- ✅ State
local walkEnabled, jumpEnabled, noclipEnabled = false, false, false
local walkSpeedValue, jumpPowerValue = 16, 50
local playAll, autoWalkActive = false, false

-- ✅ Utility
local function applyWalk()
    if hum then
        hum.WalkSpeed = walkEnabled and walkSpeedValue or 16
    end
end

local function applyJump()
    if hum then
        hum.JumpPower = jumpEnabled and jumpPowerValue or 50
    end
end

local function stopPath()
    autoWalkActive = false
end

local function playPathFile(filename)
    if not isfile(filename .. ".json") then
        warn("File tidak ditemukan:", filename)
        return
    end
    local data = HttpService:JSONDecode(readfile(filename .. ".json"))
    autoWalkActive = true
    for _, pos in ipairs(data) do
        if not autoWalkActive then break end
        hum:MoveTo(Vector3.new(pos.X, pos.Y, pos.Z))
        hum.MoveToFinished:Wait()
    end
    autoWalkActive = false
end

RunService.Stepped:Connect(function()
    if noclipEnabled and player.Character then
        for _, part in ipairs(player.Character:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end
end)

-- ✅ Buat Window / GUI via library
-- Contoh penggunaan dari `Example.lua` dalam repo:
-- di contoh mereka menulis:
--   local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
--   local Window = Library:CreateWindow({ Title = ..., Footer = ..., ToggleKeybind = ... })

local Window = Library:CreateWindow({
    Title = "Antartika Path Controller",
    Footer = "v1.0",
    ToggleKeybind = Enum.KeyCode.RightControl,
    AutoShow = true,
    Size = UDim2.new(0, 700, 0, 500)
})

-- 🟢 Tab Main Feature
local TabMain = Window:AddTab("Main", "gear") -- nama & icon, tergantung API

TabMain:AddLabel("⚙️ WalkSpeed Control")
TabMain:AddDropdown("Speed", {"10","16","25","35","50","75","100"}, "16", function(opt)
    walkSpeedValue = tonumber(opt)
    applyWalk()
end)
TabMain:AddToggle("WalkSpeed ON/OFF", false, function(state)
    walkEnabled = state
    applyWalk()
end)

TabMain:AddLabel("⚙️ JumpPower Control")
TabMain:AddDropdown("Power", {"25","50","75","100","150","200"}, "50", function(opt)
    jumpPowerValue = tonumber(opt)
    applyJump()
end)
TabMain:AddToggle("JumpPower ON/OFF", false, function(state)
    jumpEnabled = state
    applyJump()
end)

TabMain:AddLabel("🚫 NoClip")
TabMain:AddToggle("NoClip ON/OFF", false, function(state)
    noclipEnabled = state
end)

-- 🧭 Tab Auto Walk
local TabAuto = Window:AddTab("Auto Walk", "walk")

TabAuto:AddLabel("🗺️ MAP ANTARTIKA")

TabAuto:AddToggle("PLAY ALL (1→4)", false, function(state)
    playAll = state
    if state then
        task.spawn(function()
            playPathFile("Path1")
            if not playAll then return end
            playPathFile("Path2")
            if not playAll then return end
            playPathFile("Path3")
            if not playAll then return end
            playPathFile("Path4")
            playAll = false
        end)
    else
        stopPath()
    end
end)

TabAuto:AddToggle("BC > CP1 (Path 1)", false, function(state)
    if state then playPathFile("Path1") else stopPath() end
end)
TabAuto:AddToggle("CP1 > CP2 (Path 2)", false, function(state)
    if state then playPathFile("Path2") else stopPath() end
end)
TabAuto:AddToggle("CP2 > CP3 (Path 3)", false, function(state)
    if state then playPathFile("Path3") else stopPath() end
end)
TabAuto:AddToggle("CP3 > CP4 (Path 4)", false, function(state)
    if state then playPathFile("Path4") else stopPath() end
end)
TabAuto:AddToggle("CP4 > FINISH (Path 5)", false, function(state)
    if state then playPathFile("Path5") else stopPath() end
end)

-- ⚙️ Tab Setting
local TabSetting = Window:AddTab("Setting", "cog")

TabSetting:AddLabel("🎨 Tema UI")
TabSetting:AddDropdown("Select Theme", {"Dark","Light","Midnight"}, "Dark", function(opt)
    Window:ChangeTheme(opt)
end)

-- ✅ Tampilkan UI
Window:Init()
