-- WS Auto Walk Controller (FINAL)
-- UI: Obsidian (deividcomsono / Linoria-based)
-- Fitur: 100% mengikuti struktur "auto walk 1" (Record/Stop/Play/Save/Load)
-- Jalur gerak: sistem lama (Humanoid:MoveTo antar titik)
-- by WannBot x ChatGPT

----------------------------------------------------
-- LOAD UI LIBRARIES
----------------------------------------------------
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library      = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

----------------------------------------------------
-- SERVICES & INITIALS
----------------------------------------------------
local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local HttpService  = game:GetService("HttpService")
local UIS          = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local mouse     = player:GetMouse()
local character = player.Character or player.CharacterAdded:Wait()
local hum       = character:WaitForChild("Humanoid")
local hrp       = character:WaitForChild("HumanoidRootPart")

player.CharacterAdded:Connect(function(char)
	character = char
	hum = char:WaitForChild("Humanoid")
	hrp = char:WaitForChild("HumanoidRootPart")
	task.wait(0.25)
	if _G.__WS_walkEnabled then hum.WalkSpeed = _G.__WS_walkSpeedValue or 16 end
	if _G.__WS_jumpEnabled then hum.UseJumpPower = true; hum.JumpPower = _G.__WS_jumpPowerValue or 50 end
end)

----------------------------------------------------
-- STATES (MOVEMENT)
----------------------------------------------------
_G.__WS_walkEnabled     = false
_G.__WS_jumpEnabled     = false
_G.__WS_noclipEnabled   = false
_G.__WS_walkSpeedValue  = 16
_G.__WS_jumpPowerValue  = 50

RunService.Stepped:Connect(function()
	if _G.__WS_noclipEnabled and player.Character then
		for _, part in ipairs(player.Character:GetDescendants()) do
			if part:IsA("BasePart") then part.CanCollide = false end
		end
	end
end)

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

----------------------------------------------------
-- DATA STRUKTUR (mengikuti "auto walk 1")
----------------------------------------------------
-- Format penyimpanan:
-- {
--   redPlatforms    = { { position={X,Y,Z}, movements={ {position={X,Y,Z}, orientation={X,Y,Z}}, ... } }, ... },
--   yellowPlatforms = { { position={X,Y,Z} }, ... },
--   mappings        = {}  -- opsional (sesuai script lama, tidak digunakan saat replay dasar)
-- }

-- buffer rekaman satu segmen (dari red ke yellow)
local currentMovements = {}      -- array of { position={X,Y,Z}, orientation={X,Y,Z} }
local currentRedPosition = nil   -- {X,Y,Z}
local lastYellowPosition = nil   -- Vector3 (untuk auto-continue)

-- keseluruhan hasil rekaman multi-segmen
local redPlatforms    = {}       -- array segmen: { position=redPos, movements=currentMovements }
local yellowPlatforms = {}       -- array end points: { position=yellowPos }
local mappings        = {}       -- opsional

-- LOADED (hasil load dari JSON)
local loadedObject    = nil      -- object json full (dengan red/yellow)
local loadedPoints    = {}       -- flatten positions untuk visual/play cepat

-- flags
local recording       = false
local replaying       = false
local shouldStop      = false

----------------------------------------------------
-- UTIL VISUAL
----------------------------------------------------
local recordedParts   = {}   -- titik visual untuk recorded (merah)
local loadedParts     = {}   -- titik visual untuk loaded (kuning)

local function makeBall(pos: Vector3, color: Color3, name: string)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.Material = Enum.Material.Neon
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(0.9, 0.9, 0.9)
	p.Color = color
	p.Position = pos
	p.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(40, 16)
	bb.AlwaysOnTop = true
	bb.StudsOffset = Vector3.new(0, 1.2, 0)
	bb.Parent = p
	local tl = Instance.new("TextLabel")
	tl.BackgroundTransparency = 1
	tl.Size = UDim2.fromScale(1,1)
	tl.TextColor3 = Color3.new(1,1,1)
	tl.TextScaled = true
	tl.Font = Enum.Font.Code
	tl.Text = name
	tl.Parent = bb

	return p
end

local function clearParts(listTbl)
	for _, part in ipairs(listTbl) do
		if part and part.Parent then part:Destroy() end
	end
	table.clear(listTbl)
end

local function visualizeRecorded()
	clearParts(recordedParts)
	-- red = start each segment
	for i, seg in ipairs(redPlatforms) do
		local rp = seg.position
		local pos = Vector3.new(rp.X, rp.Y, rp.Z)
		table.insert(recordedParts, makeBall(pos, Color3.fromRGB(255,80,80), "RED_"..i))
		-- movements points (optional visual): kecil or beda warna
		for j, mv in ipairs(seg.movements or {}) do
			local p = Vector3.new(mv.position.X, mv.position.Y, mv.position.Z)
			table.insert(recordedParts, makeBall(p, Color3.fromRGB(255,120,120), ("M%d.%d"):format(i,j)))
		end
	end
	-- yellow = end each segment
	for i, yp in ipairs(yellowPlatforms) do
		local pos = Vector3.new(yp.position.X, yp.position.Y, yp.position.Z)
		table.insert(recordedParts, makeBall(pos, Color3.fromRGB(255,230,100), "YEL_"..i))
	end
end

local function visualizeLoaded()
	clearParts(loadedParts)
	-- tampilkan seluruh titik movements dari semua redPlatforms loaded
	if loadedObject and loadedObject.redPlatforms then
		for i, seg in ipairs(loadedObject.redPlatforms) do
			if seg.position then
				local rp = seg.position
				table.insert(loadedParts, makeBall(Vector3.new(rp.X, rp.Y, rp.Z), Color3.fromRGB(120,200,255), "LRED_"..i))
			end
			for j, mv in ipairs(seg.movements or {}) do
				local p = mv.position
				table.insert(loadedParts, makeBall(Vector3.new(p.X, p.Y, p.Z), Color3.fromRGB(100,220,255), ("LM%d.%d"):format(i,j)))
			end
		end
	end
	-- show yellows
	if loadedObject and loadedObject.yellowPlatforms then
		for i, yp in ipairs(loadedObject.yellowPlatforms) do
			local p = yp.position
			table.insert(loadedParts, makeBall(Vector3.new(p.X, p.Y, p.Z), Color3.fromRGB(180,240,120), "LYEL_"..i))
		end
	end
end

----------------------------------------------------
-- RECORD & STOP (100% gaya "auto walk 1")
----------------------------------------------------
local clickConn

local function startRecording()
	if recording then return end

	-- auto-continue: kalau ada yellow terakhir → gerakkan avatar dulu ke sana
	if lastYellowPosition then
		local h = player.Character:WaitForChild("Humanoid")
		h:MoveTo(lastYellowPosition + Vector3.new(0,3,0))
		h.MoveToFinished:Wait()
	end

	currentMovements = {}
	currentRedPosition = nil
	recording = true

	clickConn = mouse.Button1Down:Connect(function()
		if UIS:GetFocusedTextBox() then return end
		local cf = mouse.Hit; if not cf then return end
		local pos = cf.p
		local look = (hrp.CFrame.LookVector) -- orientation simple

		-- set red (start) jika belum ada
		if not currentRedPosition then
			currentRedPosition = {X = pos.X, Y = pos.Y, Z = pos.Z}
			table.insert(redPlatforms, {
				position  = currentRedPosition,
				movements = currentMovements
			})
			visualizeRecorded()
			return
		end

		-- tambahkan movement point
		table.insert(currentMovements, {
			position    = {X = pos.X, Y = pos.Y, Z = pos.Z},
			orientation = {X = look.X, Y = look.Y, Z = look.Z}
		})

		-- visual incremental
		table.insert(recordedParts, makeBall(pos, Color3.fromRGB(255,120,120), ("M%d"):format(#currentMovements)))
	end)

	Library:Notify("Recording ON (click world to add points)", 2)
end

local function stopRecording()
	if not recording then return end
	recording = false
	if clickConn then clickConn:Disconnect(); clickConn = nil end

	-- tentukan yellow = titik akhir segmen
	local lastPoint
	if #currentMovements > 0 then
		lastPoint = currentMovements[#currentMovements].position
	else
		-- kalau belum ada movement, pakai red sebagai end (fallback)
		lastPoint = currentRedPosition or {X = hrp.Position.X, Y = hrp.Position.Y, Z = hrp.Position.Z}
	end
	local yp = { position = { X = lastPoint.X, Y = lastPoint.Y, Z = lastPoint.Z } }
	table.insert(yellowPlatforms, yp)
	lastYellowPosition = Vector3.new(yp.position.X, yp.position.Y, yp.position.Z)

	visualizeRecorded()
	Library:Notify("Recording OFF (yellow created)", 2)
end

local function undoLastRecorded()
	-- hapus point movement terakhir dari segmen berjalan (kalau sedang record)
	if recording and #currentMovements > 0 then
		currentMovements[#currentMovements] = nil
	else
		-- kalau tidak recording: hapus segmen terakhir (red + moves + yellow)
		if #yellowPlatforms > 0 then yellowPlatforms[#yellowPlatforms] = nil end
		if #redPlatforms > 0 then redPlatforms[#redPlatforms] = nil end
		-- reset lastYellowPosition
		if #yellowPlatforms > 0 then
			local yp = yellowPlatforms[#yellowPlatforms].position
			lastYellowPosition = Vector3.new(yp.X, yp.Y, yp.Z)
		else
			lastYellowPosition = nil
		end
	end
	visualizeRecorded()
end

local function clearRecordedAll()
	table.clear(currentMovements)
	currentRedPosition = nil
	table.clear(redPlatforms)
	table.clear(yellowPlatforms)
	lastYellowPosition = nil
	visualizeRecorded()
end

----------------------------------------------------
-- SERIALIZE / DESERIALIZE (persis gaya auto walk 1)
----------------------------------------------------
local function buildObject()
	return {
		redPlatforms    = redPlatforms,
		yellowPlatforms = yellowPlatforms,
		mappings        = mappings
	}
end

local function saveToFile(filenameNoExt)
	local obj = buildObject()
	local json = HttpService:JSONEncode(obj)
	local fn = (filenameNoExt or "MyRecordedPath") .. ".json"
	writefile(fn, json)
	Library:Notify("Saved: "..fn, 2)
end

local function loadFromString(jsonStr)
	local data = HttpService:JSONDecode(jsonStr)

	-- reset LOADED
	loadedObject = nil
	table.clear(loadedPoints)

	-- kasus 1: struktur auto walk 1 (object)
	if typeof(data) == "table" and data.redPlatforms then
		loadedObject = data
		-- flatten untuk play cepat: gabungkan semua movements dari tiap red
		for _, seg in ipairs(data.redPlatforms) do
			for _, mv in ipairs(seg.movements or {}) do
				if mv.position then table.insert(loadedPoints, mv.position) end
			end
		end
		visualizeLoaded()
		return true
	end

	-- kasus 2: fallback array [{X,Y,Z}, ...]
	if typeof(data) == "table" and data[1] and data[1].X then
		loadedObject = {
			redPlatforms    = { { position = data[1], movements = {} } },
			yellowPlatforms = { { position = data[#data] } },
			mappings        = {}
		}
		for _, pos in ipairs(data) do table.insert(loadedPoints, pos) end
		visualizeLoaded()
		return true
	end

	return false
end

----------------------------------------------------
-- REPLAY (sistem lama)
----------------------------------------------------
local function replayPositions(listPoints)
	if replaying or #listPoints == 0 then return end
	replaying, shouldStop = true, false
	local h = player.Character:WaitForChild("Humanoid")
	for i, p in ipairs(listPoints) do
		if shouldStop then break end
		h:MoveTo(Vector3.new(p.X, p.Y, p.Z) + Vector3.new(0,3,0))
		h.MoveToFinished:Wait()
		task.wait(0.20)
	end
	replaying = false
end

local function replayRecorded()
	-- gabungkan semua movements dari semua segmen recorded (persis gaya loaded)
	local buf = {}
	for _, seg in ipairs(redPlatforms) do
		for _, mv in ipairs(seg.movements or {}) do
			if mv.position then table.insert(buf, mv.position) end
		end
	end
	replayPositions(buf)
end

local function replayLoaded()
	-- kalau ada loadedObject, gunakan seluruh movements
	if loadedObject and loadedObject.redPlatforms then
		local buf = {}
		for _, seg in ipairs(loadedObject.redPlatforms) do
			for _, mv in ipairs(seg.movements or {}) do
				if mv.position then table.insert(buf, mv.position) end
			end
		end
		replayPositions(buf)
		return
	end
	-- fallback ke loadedPoints flatten
	replayPositions(loadedPoints)
end

local function stopReplay()
	shouldStop = true
	replaying = false
end

----------------------------------------------------
-- UI WINDOW & TABS
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
-- TAB: MAIN FITURE
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
-- TAB: AUTO WALK  (SEMUA FITUR DARI AUTO WALK 1 DI SINI)
----------------------------------------------------
local AutoL  = Tabs.Auto:AddLeftGroupbox("Record / Replay")
local AutoR  = Tabs.Auto:AddRightGroupbox("Save / Load / Preset")

-- RECORD controls (start/stop/undo/clear)
AutoL:AddButton("Start Record", function() startRecording() end)
AutoL:AddButton("Stop Record",  function() stopRecording()  end)
AutoL:AddButton("Undo Last",    function() undoLastRecorded() end)

AutoL:AddDivider()
AutoL:AddButton("Play RECORDED", function() replayRecorded() end)
AutoL:AddButton("Stop Replay",   function() stopReplay() end)
AutoL:AddButton("Clear RECORDED",function() clearRecordedAll() end)

-- SAVE (local file)
AutoR:AddInput("SaveName", {
	Text = "Filename (no .json)",
	Default = "MyRecordedPath",
	Finished = true,
	Callback = function(v) _G.__WS_SaveName = (v and #v>0) and v or "MyRecordedPath" end
})
AutoR:AddButton("Save RECORDED → file (.json)", function()
	saveToFile(_G.__WS_SaveName or "MyRecordedPath")
end)

-- LOAD (URL / raw JSON)
local currentURL = "https://raw.githubusercontent.com/WannBot/WindUI/refs/heads/main/Path1.json"
AutoR:AddInput("URLInput", {
	Text = "GitHub RAW URL / Raw JSON",
	Default = currentURL,
	Placeholder = "https://raw.githubusercontent.com/<user>/<repo>/<branch>/PathX.json",
	Finished = true,
	Callback = function(v) if v and #v>0 then currentURL = v end end
})

AutoR:AddButton("Load to LOADED (visualize)", function()
	local src = currentURL or ""
	local ok, res
	if src:match("^https?://") then
		ok, res = pcall(function() return game:HttpGet(src) end)
	else
		ok, res = true, src
	end
	if not ok or not res then
		Library:Notify("Load failed", 2)
		return
	end
	local ok2 = loadFromString(res)
	if not ok2 then
		Library:Notify("Invalid JSON structure", 2)
	else
		Library:Notify("Loaded OK", 1.5)
	end
end)

AutoR:AddButton("Play LOADED", function()
	replayLoaded()
end)

AutoR:AddButton("Clear LOADED", function()
	loadedObject = nil
	table.clear(loadedPoints)
	clearParts(loadedParts)
	Library:Notify("LOADED cleared", 1.2)
end)

-- Preset Path1..Path5 dari repo kamu
AutoR:AddDivider()
local baseURL = "https://raw.githubusercontent.com/WannBot/WindUI/refs/heads/main/"
AutoR:AddButton("Play ALL (Path1→Path5)", function()
	task.spawn(function()
		for i=1,5 do
			local ok, res = pcall(function() return game:HttpGet(baseURL.."Path"..i..".json") end)
			if not ok then break end
			if loadFromString(res) then
				replayLoaded()
				if shouldStop then break end
				task.wait(0.25)
			else
				break
			end
		end
	end)
end)

for i=1,5 do
	AutoR:AddButton("Play Path"..i, function()
		local ok, res = pcall(function() return game:HttpGet(baseURL.."Path"..i..".json") end)
		if not ok then Library:Notify("DL fail Path"..i, 2) return end
		if not loadFromString(res) then Library:Notify("Invalid JSON Path"..i, 2) return end
		replayLoaded()
	end)
end

----------------------------------------------------
-- TAB: SETTING (Theme/Config)
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
