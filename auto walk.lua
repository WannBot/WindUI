-- 🧠 AUTO WALK V3 (Full GUI)
-- Kombinasi versi lama + tambahan tombol Load/Play/Save/All
-- Tetap pakai sistem MoveTo (bukan tween)
-- Dibuat untuk executor Android (Fluxus/Codex/Deltax dsb.)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local mouse = player:GetMouse()

local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local hrp = character:WaitForChild("HumanoidRootPart")

local recording = false
local replaying = false
local shouldStopReplay = false
local platforms = {}
local pathData = {}

-----------------------------------------------------------
-- 🪟 GUI SETUP
-----------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Parent = player.PlayerGui
screenGui.ResetOnSpawn = false
screenGui.Name = "AutoWalkGuiV3"

local frame = Instance.new("Frame")
frame.Parent = screenGui
frame.BackgroundColor3 = Color3.fromRGB(210, 230, 255)
frame.Size = UDim2.new(0, 300, 0, 340)
frame.Position = UDim2.new(0, 40, 0.5, -170)
frame.Active = true
frame.Draggable = true

local title = Instance.new("TextLabel")
title.Parent = frame
title.BackgroundColor3 = Color3.fromRGB(70, 120, 200)
title.Size = UDim2.new(1, 0, 0, 28)
title.TextColor3 = Color3.new(1, 1, 1)
title.Text = "Auto Walk Controller V3"
title.Font = Enum.Font.SourceSansBold
title.TextScaled = true

local statusLabel = Instance.new("TextLabel")
statusLabel.Parent = frame
statusLabel.BackgroundTransparency = 1
statusLabel.Position = UDim2.new(0, 0, 0, 28)
statusLabel.Size = UDim2.new(1, 0, 0, 25)
statusLabel.Text = "Status: Idle"
statusLabel.TextColor3 = Color3.new(0, 0, 0)
statusLabel.Font = Enum.Font.SourceSans
statusLabel.TextScaled = true

local function setStatus(txt, color)
	statusLabel.Text = "Status: " .. txt
	if color then statusLabel.TextColor3 = color end
end

-----------------------------------------------------------
-- 🔘 BUTTON CREATOR
-----------------------------------------------------------
local function makeButton(name, text, order, color)
	local btn = Instance.new("TextButton")
	btn.Parent = frame
	btn.Name = name
	btn.Text = text
	btn.Size = UDim2.new(0, 260, 0, 28)
	btn.Position = UDim2.new(0, 20, 0, 60 + (order * 30))
	btn.BackgroundColor3 = color or Color3.fromRGB(150, 180, 255)
	btn.TextScaled = true
	btn.Font = Enum.Font.SourceSansBold
	return btn
end

local recordBtn = makeButton("Record", "🎬 Start Record", 0, Color3.fromRGB(255, 180, 120))
local stopRecordBtn = makeButton("StopRecord", "⏹ Stop Record", 1, Color3.fromRGB(255, 120, 120))
local playBtn = makeButton("PlayPath", "▶️ Play Recorded Path", 2, Color3.fromRGB(160, 255, 160))
local stopReplayBtn = makeButton("StopReplay", "⛔ Stop Replay", 3, Color3.fromRGB(255, 160, 160))
local saveBtn = makeButton("Save", "💾 Save Path", 4, Color3.fromRGB(150, 200, 255))
local loadBtn = makeButton("Load", "📂 Load JSON URL", 5, Color3.fromRGB(150, 255, 150))
local playLoadedBtn = makeButton("PlayLoaded", "▶️ Play Loaded Path", 6, Color3.fromRGB(180, 255, 180))
local playAllBtn = makeButton("PlayAll", "🌎 Play All (Path1→Path5)", 7, Color3.fromRGB(255, 240, 150))
local clearBtn = makeButton("Clear", "🧹 Clear Platforms", 8, Color3.fromRGB(210, 210, 255))

-----------------------------------------------------------
-- 💾 INPUT FIELD UNTUK LOAD JSON
-----------------------------------------------------------
local urlBox = Instance.new("TextBox")
urlBox.Parent = frame
urlBox.Size = UDim2.new(0, 260, 0, 25)
urlBox.Position = UDim2.new(0, 20, 0, 340 - 60)
urlBox.Text = "https://raw.githubusercontent.com/WannBot/WindUI/refs/heads/main/Path1.json"
urlBox.PlaceholderText = "Masukkan URL JSON di sini..."
urlBox.TextColor3 = Color3.new(0, 0, 0)
urlBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
urlBox.ClearTextOnFocus = false
urlBox.TextScaled = true
urlBox.Font = Enum.Font.SourceSansBold

-----------------------------------------------------------
-- 🧱 PLATFORM SYSTEM
-----------------------------------------------------------
local function clearPlatforms()
	for _, p in ipairs(platforms) do
		if p and p.Parent then p:Destroy() end
	end
	table.clear(platforms)
	table.clear(pathData)
end

local function addPlatform(pos, color)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Neon
	part.Color = color or Color3.fromRGB(255, 170, 70)
	part.Size = Vector3.new(1, 1, 1)
	part.Shape = Enum.PartType.Ball
	part.Position = pos
	part.Name = "PathPoint"
	part.Parent = workspace
	table.insert(platforms, part)
end

-----------------------------------------------------------
-- 🧭 RECORDING SYSTEM
-----------------------------------------------------------
local conn
recordBtn.MouseButton1Click:Connect(function()
	if recording then return end
	recording = true
	setStatus("Recording...", Color3.fromRGB(255,140,0))
	clearPlatforms()
	pathData = {}
	conn = mouse.Button1Down:Connect(function()
		if not recording then return end
		local target = mouse.Hit and mouse.Hit.p
		if target then
			local point = {X = target.X, Y = target.Y, Z = target.Z}
			table.insert(pathData, point)
			addPlatform(Vector3.new(target.X, target.Y, target.Z))
		end
	end)
end)

stopRecordBtn.MouseButton1Click:Connect(function()
	if not recording then return end
	recording = false
	if conn then conn:Disconnect() conn = nil end
	setStatus("Recording stopped", Color3.fromRGB(0,255,0))
end)

-----------------------------------------------------------
-- ▶️ REPLAY PATH
-----------------------------------------------------------
local function replay(data)
	if replaying or #data == 0 then return end
	replaying = true
	shouldStopReplay = false
	setStatus("Replaying path...", Color3.fromRGB(0,180,0))

	for i, pos in ipairs(data) do
		if shouldStopReplay then break end
		humanoid:MoveTo(Vector3.new(pos.X, pos.Y, pos.Z))
		humanoid.MoveToFinished:Wait()
		task.wait(0.1)
	end

	replaying = false
	setStatus("Replay finished", Color3.fromRGB(0,255,0))
end

playBtn.MouseButton1Click:Connect(function()
	replay(pathData)
end)

stopReplayBtn.MouseButton1Click:Connect(function()
	shouldStopReplay = true
	replaying = false
	setStatus("Stopped", Color3.fromRGB(255,255,0))
end)

-----------------------------------------------------------
-- 💾 SAVE / LOAD JSON
-----------------------------------------------------------
saveBtn.MouseButton1Click:Connect(function()
	if #pathData == 0 then
		setStatus("No path to save", Color3.fromRGB(255,0,0))
		return
	end
	local json = HttpService:JSONEncode(pathData)
	if writefile then
		writefile("AutoWalk_Path.json", json)
		setStatus("Saved to AutoWalk_Path.json", Color3.fromRGB(0,255,0))
	end
	if setclipboard then
		setclipboard(json)
		setStatus("Copied to clipboard", Color3.fromRGB(0,255,0))
	end
end)

loadBtn.MouseButton1Click:Connect(function()
	local url = urlBox.Text
	setStatus("Loading from URL...", Color3.fromRGB(0,120,255))
	local ok, res = pcall(function() return game:HttpGet(url) end)
	if not ok or not res or #res == 0 then
		setStatus("Failed to load", Color3.fromRGB(255,0,0))
		return
	end
	local ok2, data = pcall(function() return HttpService:JSONDecode(res) end)
	if not ok2 or typeof(data) ~= "table" then
		setStatus("Invalid JSON", Color3.fromRGB(255,0,0))
		return
	end
	clearPlatforms()
	for _, p in ipairs(data) do
		addPlatform(Vector3.new(p.X, p.Y, p.Z))
	end
	pathData = data
	setStatus("Loaded "..#data.." points", Color3.fromRGB(0,255,0))
end)

playLoadedBtn.MouseButton1Click:Connect(function()
	replay(pathData)
end)

-----------------------------------------------------------
-- 🌎 PLAY ALL (Path1→Path5)
-----------------------------------------------------------
playAllBtn.MouseButton1Click:Connect(function()
	task.spawn(function()
		for i = 1, 5 do
			local url = ("https://raw.githubusercontent.com/WannBot/WindUI/refs/heads/main/Path%d.json"):format(i)
			local ok, res = pcall(function() return game:HttpGet(url) end)
			if ok and res and #res > 0 then
				local ok2, data = pcall(function() return HttpService:JSONDecode(res) end)
				if ok2 then
					clearPlatforms()
					for _, p in ipairs(data) do
						addPlatform(Vector3.new(p.X, p.Y, p.Z))
					end
					pathData = data
					setStatus("Playing Path"..i, Color3.fromRGB(0,255,255))
					replay(data)
				end
			end
			if shouldStopReplay then break end
			task.wait(0.5)
		end
		setStatus("Finished All", Color3.fromRGB(0,255,0))
	end)
end)

clearBtn.MouseButton1Click:Connect(function()
	clearPlatforms()
	setStatus("Cleared all", Color3.fromRGB(100,100,255))
end)

setStatus("Idle", Color3.fromRGB(0,0,0))
