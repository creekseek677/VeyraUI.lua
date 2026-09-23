local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService") 
local SoundService = game:GetService("SoundService")

local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local HttpService = game:GetService("HttpService")
local LocalizationService = game:GetService("LocalizationService")

local SurfaceBlur
local IconAssets
local Flipper
local GetIcon
local RegisterConfigElement, ListConfigs, SaveNamedConfig, LoadNamedConfig, DeleteNamedConfig
local AutoSaveEnabled, CurrentConfigName
local ConfigRegistry

local function NormalizeBackgroundImage(value)
	value = tostring(value or "")
	value = string.gsub(value, "^%s+", "")
	value = string.gsub(value, "%s+$", "")

	if value == "" then
		return ""
	end

	
	if string.sub(string.lower(value), 1, 13) == "rbxassetid://" then
		local id = string.match(value, "rbxassetid://(%d+)")
		return id and ("rbxassetid://" .. id) or ""
	end
	if string.sub(string.lower(value), 1, 10) == "rbxthumb://" then
		return value
	end

	
	local numericId = string.match(value, "^(%d+)$")
	if numericId then
		return "rbxassetid://" .. numericId
	end

	
	local urlId = string.match(value, "[?&]id=(%d+)")
	if not urlId then
		urlId = string.match(value, "/asset/(%d+)")
	end
	if not urlId then
		urlId = string.match(value, "assetId=(%d+)")
	end
	if urlId then
		return "rbxassetid://" .. urlId
	end

	return value
end

local CONFIG_FOLDER = "VeyraUI"
local CONFIG_FILE = "VeyraUI/settings.json"

local DefaultSettings = {
	Theme = "Dark",
	ToggleUIKey = "X",
	UIVisible = true,
	CornerRadius = 6, -- fixed nice rounding (slider no longer controls this)
	AccentHeight = 1, -- 0..1 fraction of window height for the left accent bar
	UseBackgroundImage = false,
	BackgroundImage = "",
	BackgroundImageTransparency = 0.32,
	BackgroundImageTint = Color3.fromRGB(255, 255, 255),
	OutlineColor = Color3.fromRGB(255, 255, 255),
	CustomImageThemes = {},
}

local Settings = {}
for k, v in pairs(DefaultSettings) do
	if type(v) == "table" then
		Settings[k] = table.clone(v)
	else
		Settings[k] = v
	end
end

local function ConfigEncode(tbl)
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(tbl)
	end)
	if ok and encoded then return encoded end

	local parts = {}
	for k, v in pairs(tbl) do
		local vs = tostring(v)
		if type(v) == "string" then
			vs = '"' .. (string.gsub(vs, '"', '\\"')) .. '"'
		elseif type(v) == "boolean" then
			vs = v and "true" or "false"
		end
		table.insert(parts, '"' .. tostring(k) .. '":' .. vs)
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function ConfigDecode(str)
	if type(str) ~= "string" or #str == 0 then return nil end
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(str)
	end)
	if ok and type(decoded) == "table" then return decoded end
	return nil
end

local function ConfigLoad()
	local raw = nil
	pcall(function()
		if type(isfile) == "function" and isfile(CONFIG_FILE) then
			raw = readfile(CONFIG_FILE)
		elseif type(readfile) == "function" then
			raw = readfile(CONFIG_FILE)
		end
	end)
	if not raw then return false end
	local data = ConfigDecode(raw)
	if type(data) ~= "table" then return false end
	for k, v in pairs(data) do
		Settings[k] = v
	end
	return true
end

local function ConfigSave()
	local payload = ConfigEncode(Settings)
	local ok = false
	pcall(function()
		if type(makefolder) == "function" then
			pcall(makefolder, CONFIG_FOLDER)
		end
		if type(writefile) == "function" then
			writefile(CONFIG_FILE, payload)
			ok = true
		end
	end)
	return ok
end

pcall(ConfigLoad)
Settings.CornerRadius = math.clamp(tonumber(Settings.CornerRadius) or 6, 0, 12)
Settings.AccentHeight = math.clamp(tonumber(Settings.AccentHeight) or 1, 0.05, 1)
Settings.BackgroundImageTransparency = math.clamp(tonumber(Settings.BackgroundImageTransparency) or 0.32, 0, 1)
if typeof(Settings.BackgroundImageTint) ~= "Color3" then
	local t = Settings.BackgroundImageTint
	if type(t) == "table" and t.R then
		Settings.BackgroundImageTint = Color3.new(tonumber(t.R) or 1, tonumber(t.G) or 1, tonumber(t.B) or 1)
	else
		Settings.BackgroundImageTint = Color3.fromRGB(255, 255, 255)
	end
end
if typeof(Settings.OutlineColor) ~= "Color3" then
	local t = Settings.OutlineColor
	if type(t) == "table" and t.R then
		Settings.OutlineColor = Color3.new(tonumber(t.R) or 1, tonumber(t.G) or 1, tonumber(t.B) or 1)
	else
		Settings.OutlineColor = Color3.fromRGB(255, 255, 255)
	end
end
if type(Settings.CustomImageThemes) ~= "table" then
	Settings.CustomImageThemes = {}
end

local Theme

local function IsImageThemeActive()
	return Settings.UseBackgroundImage == true
	and type(Settings.BackgroundImage) == "string"
	and Settings.BackgroundImage ~= ""
end

local function GetOutlineColor()
	if typeof(Settings.OutlineColor) == "Color3" then
		return Settings.OutlineColor
	end
	return Theme.OutlineAccent or Theme.Border or Color3.fromRGB(255, 255, 255)
end

local function KeyCodeFromName(name)
	if typeof(name) == "EnumItem" then return name end
	if type(name) ~= "string" or name == "" or name == "None" then
		return Enum.KeyCode.Unknown
	end
	local ok, kc = pcall(function()
		return Enum.KeyCode[name]
	end)
	if ok and kc then return kc end
	return Enum.KeyCode.Unknown
end

local function CreateSignal()
	local handlers = {}
	local destroyed = false
	local api = {}

	function api:Connect(fn)
		if destroyed or type(fn) ~= "function" then
			return { Disconnect = function() end, Connected = false }
		end
		local conn = { _fn = fn, Connected = true }
		function conn:Disconnect()
			if not self.Connected then return end
			self.Connected = false
			for i = #handlers, 1, -1 do
				if handlers[i] == self then
					table.remove(handlers, i)
					break
				end
			end
		end
		table.insert(handlers, conn)
		return conn
	end

	function api:Once(fn)
		local conn
		conn = api:Connect(function(...)
			conn:Disconnect()
			fn(...)
		end)
		return conn
	end

	function api:Fire(...)
		if destroyed then return end
		local snap = table.clone(handlers)
		for _, c in ipairs(snap) do
			if c.Connected then
				task.spawn(c._fn, ...)
			end
		end
	end

	function api:DisconnectAll()
		for _, c in ipairs(handlers) do
			c.Connected = false
		end
		table.clear(handlers)
	end

	function api:Destroy()
		if destroyed then return end
		destroyed = true
		api:DisconnectAll()
	end

	function api:IsDestroyed()
		return destroyed
	end

	return api
end

local function ProtectAndParent(sg)
	sg.ResetOnSpawn = false
	pcall(function()
		if type(syn) == "table" and type(syn.protect_gui) == "function" then
			syn.protect_gui(sg)
		end
	end)
	local ok = pcall(function()
		sg.Parent = game:GetService("CoreGui")
	end)
	if ok and sg.Parent then return end
	ok = pcall(function()
		if type(gethui) == "function" then
			sg.Parent = gethui()
		end
	end)
	if ok and sg.Parent then return end
	sg.Parent = PlayerGui
end

Theme = {
	Background = Color3.fromRGB(22, 22, 26),
	Secondary = Color3.fromRGB(30, 30, 36),
	Tertiary = Color3.fromRGB(38, 38, 46),
	Hover = Color3.fromRGB(48, 48, 58),
	Text = Color3.fromRGB(240, 240, 245),
	SecondaryText = Color3.fromRGB(160, 160, 170),
	MutedText = Color3.fromRGB(110, 110, 120),
	Accent = Color3.fromRGB(255, 255, 255),
	Border = Color3.fromRGB(55, 55, 65),
	ToggleOn = Color3.fromRGB(255, 255, 255),
	ToggleOff = Color3.fromRGB(60, 60, 70),
	SliderTrack = Color3.fromRGB(45, 45, 55),
	SliderFill = Color3.fromRGB(255, 255, 255),
	NotificationBackground = Color3.fromRGB(18, 18, 22),
	NotificationBorder = Color3.fromRGB(45, 45, 55),
	NotificationTitle = Color3.fromRGB(245, 245, 250),
	NotificationDescription = Color3.fromRGB(165, 165, 175),
	NotificationInfo = Color3.fromRGB(100, 160, 255),
	NotificationSuccess = Color3.fromRGB(80, 200, 120),
	NotificationWarning = Color3.fromRGB(255, 180, 60),
	NotificationError = Color3.fromRGB(255, 80, 80),
	OutlineAccent = Color3.fromRGB(90, 90, 100), 
	GradientSurfaceA = Color3.fromRGB(24, 26, 32),
	GradientSurfaceB = Color3.fromRGB(36, 39, 50),
	GradientPanelA = Color3.fromRGB(28, 30, 40),
	GradientPanelB = Color3.fromRGB(40, 44, 56),
	GradientAccentA = Color3.fromRGB(40, 40, 50),
	GradientAccentB = Color3.fromRGB(255, 255, 255),
	GradientBackgroundA = Color3.fromRGB(16, 18, 24),
	GradientBackgroundB = Color3.fromRGB(26, 29, 38),
	GradientRotation = 90,
	Font = Enum.Font.GothamMedium,
	FontBold = Enum.Font.GothamBold,
	FontMono = Enum.Font.Code,
	CornerRadius = 6,
	ElementHeight = 32,
	AnimationSpeed = 0.35,
	HoverSpeed = 0.15,
}

local ThemePresets = {
	Dark = {
		Background = Color3.fromRGB(22, 22, 26),
		Secondary = Color3.fromRGB(30, 30, 36),
		Tertiary = Color3.fromRGB(38, 38, 46),
		Hover = Color3.fromRGB(48, 48, 58),
		Text = Color3.fromRGB(240, 240, 245),
		SecondaryText = Color3.fromRGB(160, 160, 170),
		MutedText = Color3.fromRGB(110, 110, 120),
		Accent = Color3.fromRGB(255, 255, 255),
		Border = Color3.fromRGB(55, 55, 65),
		ToggleOn = Color3.fromRGB(255, 255, 255),
		ToggleOff = Color3.fromRGB(60, 60, 70),
		SliderTrack = Color3.fromRGB(45, 45, 55),
		SliderFill = Color3.fromRGB(255, 255, 255),
		NotificationBackground = Color3.fromRGB(18, 18, 22),
		NotificationBorder = Color3.fromRGB(45, 45, 55),
		NotificationTitle = Color3.fromRGB(245, 245, 250),
		NotificationDescription = Color3.fromRGB(165, 165, 175),
		NotificationInfo = Color3.fromRGB(100, 160, 255),
		NotificationSuccess = Color3.fromRGB(80, 200, 120),
		NotificationWarning = Color3.fromRGB(255, 180, 60),
		NotificationError = Color3.fromRGB(255, 80, 80),
		OutlineAccent = Color3.fromRGB(90, 90, 100), 
		GradientSurfaceA = Color3.fromRGB(24, 26, 32),
		GradientSurfaceB = Color3.fromRGB(36, 39, 50),
		GradientPanelA = Color3.fromRGB(28, 30, 40),
		GradientPanelB = Color3.fromRGB(42, 46, 58),
		GradientAccentA = Color3.fromRGB(40, 40, 50),
		GradientAccentB = Color3.fromRGB(255, 255, 255),
		GradientBackgroundA = Color3.fromRGB(20, 20, 20),
		GradientBackgroundB = Color3.fromRGB(30, 30, 30),
		GradientRotation = 135,
	},
	Light = {
		Background = Color3.fromRGB(245, 245, 248),
		Secondary = Color3.fromRGB(255, 255, 255),
		Tertiary = Color3.fromRGB(235, 235, 240),
		Hover = Color3.fromRGB(225, 225, 232),
		Text = Color3.fromRGB(20, 20, 28),
		SecondaryText = Color3.fromRGB(90, 90, 105),
		MutedText = Color3.fromRGB(140, 140, 155),
		Accent = Color3.fromRGB(30, 30, 40),
		Border = Color3.fromRGB(210, 210, 220),
		ToggleOn = Color3.fromRGB(40, 40, 50),
		ToggleOff = Color3.fromRGB(200, 200, 210),
		SliderTrack = Color3.fromRGB(220, 220, 230),
		SliderFill = Color3.fromRGB(40, 40, 50),
		NotificationBackground = Color3.fromRGB(255, 255, 255),
		NotificationBorder = Color3.fromRGB(220, 220, 230),
		NotificationTitle = Color3.fromRGB(20, 20, 28),
		NotificationDescription = Color3.fromRGB(90, 90, 105),
		NotificationInfo = Color3.fromRGB(40, 120, 220),
		NotificationSuccess = Color3.fromRGB(30, 160, 90),
		NotificationWarning = Color3.fromRGB(210, 140, 30),
		NotificationError = Color3.fromRGB(210, 50, 50),
		OutlineAccent = Color3.fromRGB(160, 160, 170), 
		GradientSurfaceA = Color3.fromRGB(248, 249, 252),
		GradientSurfaceB = Color3.fromRGB(229, 232, 239),
		GradientPanelA = Color3.fromRGB(255, 255, 255),
		GradientPanelB = Color3.fromRGB(238, 240, 246),
		GradientAccentA = Color3.fromRGB(255, 255, 255),
		GradientAccentB = Color3.fromRGB(30, 30, 40),
		GradientBackgroundA = Color3.fromRGB(241, 242, 247),
		GradientBackgroundB = Color3.fromRGB(223, 226, 234),
		GradientRotation = 90,
	},
	Neon = {
		Background = Color3.fromRGB(18, 12, 32),
		Secondary = Color3.fromRGB(28, 18, 48),
		Tertiary = Color3.fromRGB(40, 28, 64),
		Hover = Color3.fromRGB(52, 36, 80),
		Text = Color3.fromRGB(235, 225, 255),
		SecondaryText = Color3.fromRGB(170, 150, 230),
		MutedText = Color3.fromRGB(120, 100, 170),
		Accent = Color3.fromRGB(180, 80, 255),
		Border = Color3.fromRGB(80, 50, 120),
		ToggleOn = Color3.fromRGB(180, 80, 255),
		ToggleOff = Color3.fromRGB(50, 35, 80),
		SliderTrack = Color3.fromRGB(40, 28, 65),
		SliderFill = Color3.fromRGB(180, 80, 255),
		NotificationBackground = Color3.fromRGB(16, 12, 28),
		NotificationBorder = Color3.fromRGB(65, 40, 105),
		NotificationTitle = Color3.fromRGB(245, 235, 255),
		NotificationDescription = Color3.fromRGB(170, 150, 230),
		NotificationInfo = Color3.fromRGB(120, 160, 255),
		NotificationSuccess = Color3.fromRGB(80, 220, 160),
		NotificationWarning = Color3.fromRGB(255, 180, 80),
		NotificationError = Color3.fromRGB(255, 80, 120),
		OutlineAccent = Color3.fromRGB(255, 90, 180), 
		GradientSurfaceA = Color3.fromRGB(20, 14, 36),
		GradientSurfaceB = Color3.fromRGB(42, 28, 68),
		GradientPanelA = Color3.fromRGB(26, 18, 46),
		GradientPanelB = Color3.fromRGB(48, 32, 78),
		GradientAccentA = Color3.fromRGB(255, 80, 200), 
		GradientAccentB = Color3.fromRGB(140, 60, 255),
		GradientBackgroundA = Color3.fromRGB(20, 8, 42),
		GradientBackgroundB = Color3.fromRGB(96, 22, 92),
		GradientRotation = 135,
	},
	Cyan = {
		Background = Color3.fromRGB(0, 128, 128),        
		Secondary = Color3.fromRGB(0, 160, 160),        
		Tertiary = Color3.fromRGB(0, 128, 128),         
		Hover = Color3.fromRGB(0, 200, 200),            
		Text = Color3.fromRGB(255, 255, 255),
		SecondaryText = Color3.fromRGB(200, 255, 255),
		MutedText = Color3.fromRGB(150, 220, 220),
		Accent = Color3.fromRGB(0, 255, 255),           
		Border = Color3.fromRGB(0, 80, 80),
		ToggleOn = Color3.fromRGB(0, 255, 255),
		ToggleOff = Color3.fromRGB(0, 90, 90),
		SliderTrack = Color3.fromRGB(0, 80, 80),
		SliderFill = Color3.fromRGB(0, 255, 255),
		NotificationBackground = Color3.fromRGB(0, 80, 80),
		NotificationBorder = Color3.fromRGB(0, 120, 120),
		NotificationTitle = Color3.fromRGB(255, 255, 255),
		NotificationDescription = Color3.fromRGB(200, 255, 255),
		NotificationInfo = Color3.fromRGB(0, 200, 255),
		NotificationSuccess = Color3.fromRGB(0, 255, 200),
		NotificationWarning = Color3.fromRGB(255, 200, 0),
		NotificationError = Color3.fromRGB(255, 80, 80),
		OutlineAccent = Color3.fromRGB(0, 255, 255),    
		GradientSurfaceA = Color3.fromRGB(0, 160, 180),
		GradientSurfaceB = Color3.fromRGB(0, 100, 120),
		GradientPanelA = Color3.fromRGB(0, 140, 160),
		GradientPanelB = Color3.fromRGB(0, 90, 110),
		GradientAccentA = Color3.fromRGB(0, 100, 110),
		GradientAccentB = Color3.fromRGB(0, 255, 255),
		GradientBackgroundA = Color3.fromRGB(0, 110, 130),
		GradientBackgroundB = Color3.fromRGB(0, 70, 90),
		GradientRotation = 90,
	},
	Glass = {
		Background = Color3.fromRGB(18, 24, 38),
		Secondary = Color3.fromRGB(32, 42, 62),
		Tertiary = Color3.fromRGB(48, 62, 88),
		Hover = Color3.fromRGB(65, 85, 120),
		Text = Color3.fromRGB(250, 252, 255),
		SecondaryText = Color3.fromRGB(185, 205, 235),
		MutedText = Color3.fromRGB(140, 165, 200),
		Accent = Color3.fromRGB(255, 255, 255),
		Border = Color3.fromRGB(210, 225, 255),
		ToggleOn = Color3.fromRGB(255, 255, 255),
		ToggleOff = Color3.fromRGB(55, 70, 100),
		SliderTrack = Color3.fromRGB(45, 60, 90),
		SliderFill = Color3.fromRGB(230, 240, 255),
		NotificationBackground = Color3.fromRGB(16, 22, 36),
		NotificationBorder = Color3.fromRGB(190, 210, 245),
		NotificationTitle = Color3.fromRGB(255, 255, 255),
		NotificationDescription = Color3.fromRGB(190, 210, 240),
		NotificationInfo = Color3.fromRGB(120, 190, 255),
		NotificationSuccess = Color3.fromRGB(100, 240, 190),
		NotificationWarning = Color3.fromRGB(255, 210, 120),
		NotificationError = Color3.fromRGB(255, 110, 140),
		OutlineAccent = Color3.fromRGB(255, 255, 255), 
		GradientSurfaceA = Color3.fromRGB(55, 75, 110),
		GradientSurfaceB = Color3.fromRGB(30, 42, 68),
		GradientPanelA = Color3.fromRGB(40, 55, 85),
		GradientPanelB = Color3.fromRGB(22, 32, 52),
		GradientAccentA = Color3.fromRGB(40, 60, 95),
		GradientAccentB = Color3.fromRGB(255, 255, 255),
		GradientBackgroundA = Color3.fromRGB(22, 30, 48),
		GradientBackgroundB = Color3.fromRGB(10, 16, 30),
		GradientRotation = 125,
	},
	Crimson = {
		Background = Color3.fromRGB(8, 8, 10),
		Secondary = Color3.fromRGB(16, 16, 20),
		Tertiary = Color3.fromRGB(28, 28, 34),
		Hover = Color3.fromRGB(45, 20, 25),
		Text = Color3.fromRGB(245, 245, 250),
		SecondaryText = Color3.fromRGB(170, 170, 180),
		MutedText = Color3.fromRGB(110, 110, 120),
		Accent = Color3.fromRGB(220, 20, 60),
		Border = Color3.fromRGB(60, 10, 20),
		ToggleOn = Color3.fromRGB(220, 20, 60),
		ToggleOff = Color3.fromRGB(40, 40, 48),
		SliderTrack = Color3.fromRGB(35, 35, 42),
		SliderFill = Color3.fromRGB(220, 20, 60),
		NotificationBackground = Color3.fromRGB(10, 10, 12),
		NotificationBorder = Color3.fromRGB(80, 15, 30),
		NotificationTitle = Color3.fromRGB(250, 250, 255),
		NotificationDescription = Color3.fromRGB(180, 180, 190),
		NotificationInfo = Color3.fromRGB(220, 60, 60),
		NotificationSuccess = Color3.fromRGB(80, 200, 120),
		NotificationWarning = Color3.fromRGB(255, 180, 60),
		NotificationError = Color3.fromRGB(255, 60, 60),
		OutlineAccent = Color3.fromRGB(220, 20, 60),
		GradientSurfaceA = Color3.fromRGB(14, 14, 18),
		GradientSurfaceB = Color3.fromRGB(32, 32, 40),
		GradientPanelA = Color3.fromRGB(20, 20, 26),
		GradientPanelB = Color3.fromRGB(38, 38, 48),
		GradientAccentA = Color3.fromRGB(60, 10, 20),
		GradientAccentB = Color3.fromRGB(220, 20, 60),
		GradientBackgroundA = Color3.fromRGB(8, 8, 10),
		GradientBackgroundB = Color3.fromRGB(18, 18, 24),
		GradientRotation = 135,
	},

	Darker = {
		Background = Color3.fromRGB(18, 18, 20),
		Secondary = Color3.fromRGB(28, 28, 32),
		Tertiary = Color3.fromRGB(36, 36, 42),
		Hover = Color3.fromRGB(48, 48, 56),
		Text = Color3.fromRGB(235, 235, 240),
		SecondaryText = Color3.fromRGB(150, 150, 160),
		MutedText = Color3.fromRGB(100, 100, 110),
		Accent = Color3.fromRGB(72, 138, 182),
		Border = Color3.fromRGB(50, 50, 58),
		ToggleOn = Color3.fromRGB(72, 138, 182),
		ToggleOff = Color3.fromRGB(40, 40, 48),
		SliderTrack = Color3.fromRGB(40, 40, 48),
		SliderFill = Color3.fromRGB(72, 138, 182),
		NotificationBackground = Color3.fromRGB(14, 14, 16),
		NotificationBorder = Color3.fromRGB(45, 45, 52),
		NotificationTitle = Color3.fromRGB(245, 245, 250),
		NotificationDescription = Color3.fromRGB(160, 160, 170),
		NotificationInfo = Color3.fromRGB(72, 138, 182),
		NotificationSuccess = Color3.fromRGB(80, 200, 120),
		NotificationWarning = Color3.fromRGB(255, 180, 60),
		NotificationError = Color3.fromRGB(255, 80, 80),
		OutlineAccent = Color3.fromRGB(72, 138, 182),
		GradientSurfaceA = Color3.fromRGB(22, 22, 26),
		GradientSurfaceB = Color3.fromRGB(34, 34, 40),
		GradientPanelA = Color3.fromRGB(26, 26, 32),
		GradientPanelB = Color3.fromRGB(40, 40, 48),
		GradientAccentA = Color3.fromRGB(40, 70, 100),
		GradientAccentB = Color3.fromRGB(72, 138, 182),
		GradientBackgroundA = Color3.fromRGB(14, 14, 16),
		GradientBackgroundB = Color3.fromRGB(24, 24, 28),
		GradientRotation = 135,
	},
	Aqua = {
		Background = Color3.fromRGB(12, 22, 24),
		Secondary = Color3.fromRGB(20, 36, 40),
		Tertiary = Color3.fromRGB(28, 48, 52),
		Hover = Color3.fromRGB(40, 70, 75),
		Text = Color3.fromRGB(240, 248, 250),
		SecondaryText = Color3.fromRGB(160, 190, 195),
		MutedText = Color3.fromRGB(110, 140, 145),
		Accent = Color3.fromRGB(60, 165, 165),
		Border = Color3.fromRGB(40, 70, 70),
		ToggleOn = Color3.fromRGB(60, 165, 165),
		ToggleOff = Color3.fromRGB(30, 50, 52),
		SliderTrack = Color3.fromRGB(30, 50, 52),
		SliderFill = Color3.fromRGB(60, 165, 165),
		NotificationBackground = Color3.fromRGB(10, 18, 20),
		NotificationBorder = Color3.fromRGB(40, 70, 70),
		NotificationTitle = Color3.fromRGB(245, 250, 252),
		NotificationDescription = Color3.fromRGB(160, 190, 195),
		NotificationInfo = Color3.fromRGB(80, 180, 200),
		NotificationSuccess = Color3.fromRGB(80, 200, 160),
		NotificationWarning = Color3.fromRGB(255, 180, 60),
		NotificationError = Color3.fromRGB(255, 80, 100),
		OutlineAccent = Color3.fromRGB(60, 165, 165),
		GradientSurfaceA = Color3.fromRGB(20, 40, 44),
		GradientSurfaceB = Color3.fromRGB(40, 80, 84),
		GradientPanelA = Color3.fromRGB(24, 44, 48),
		GradientPanelB = Color3.fromRGB(48, 90, 94),
		GradientAccentA = Color3.fromRGB(30, 90, 90),
		GradientAccentB = Color3.fromRGB(60, 165, 165),
		GradientBackgroundA = Color3.fromRGB(10, 24, 28),
		GradientBackgroundB = Color3.fromRGB(30, 60, 64),
		GradientRotation = 125,
	},
	Amethyst = {
		Background = Color3.fromRGB(16, 12, 24),
		Secondary = Color3.fromRGB(28, 20, 42),
		Tertiary = Color3.fromRGB(40, 30, 58),
		Hover = Color3.fromRGB(55, 42, 78),
		Text = Color3.fromRGB(245, 240, 255),
		SecondaryText = Color3.fromRGB(175, 160, 200),
		MutedText = Color3.fromRGB(120, 105, 150),
		Accent = Color3.fromRGB(97, 62, 167),
		Border = Color3.fromRGB(60, 45, 85),
		ToggleOn = Color3.fromRGB(97, 62, 167),
		ToggleOff = Color3.fromRGB(40, 30, 55),
		SliderTrack = Color3.fromRGB(40, 30, 55),
		SliderFill = Color3.fromRGB(97, 62, 167),
		NotificationBackground = Color3.fromRGB(14, 10, 22),
		NotificationBorder = Color3.fromRGB(55, 40, 80),
		NotificationTitle = Color3.fromRGB(250, 245, 255),
		NotificationDescription = Color3.fromRGB(175, 160, 200),
		NotificationInfo = Color3.fromRGB(130, 100, 220),
		NotificationSuccess = Color3.fromRGB(100, 200, 150),
		NotificationWarning = Color3.fromRGB(255, 180, 80),
		NotificationError = Color3.fromRGB(255, 90, 120),
		OutlineAccent = Color3.fromRGB(140, 100, 210),
		GradientSurfaceA = Color3.fromRGB(30, 20, 48),
		GradientSurfaceB = Color3.fromRGB(55, 35, 90),
		GradientPanelA = Color3.fromRGB(36, 24, 56),
		GradientPanelB = Color3.fromRGB(60, 40, 95),
		GradientAccentA = Color3.fromRGB(70, 40, 120),
		GradientAccentB = Color3.fromRGB(160, 100, 230),
		GradientBackgroundA = Color3.fromRGB(18, 12, 32),
		GradientBackgroundB = Color3.fromRGB(48, 28, 72),
		GradientRotation = 135,
	},
	Rose = {
		Background = Color3.fromRGB(22, 12, 16),
		Secondary = Color3.fromRGB(36, 18, 26),
		Tertiary = Color3.fromRGB(52, 28, 38),
		Hover = Color3.fromRGB(70, 36, 50),
		Text = Color3.fromRGB(250, 240, 245),
		SecondaryText = Color3.fromRGB(200, 160, 175),
		MutedText = Color3.fromRGB(140, 110, 120),
		Accent = Color3.fromRGB(180, 55, 90),
		Border = Color3.fromRGB(90, 40, 55),
		ToggleOn = Color3.fromRGB(180, 55, 90),
		ToggleOff = Color3.fromRGB(45, 25, 32),
		SliderTrack = Color3.fromRGB(45, 25, 32),
		SliderFill = Color3.fromRGB(180, 55, 90),
		NotificationBackground = Color3.fromRGB(18, 10, 14),
		NotificationBorder = Color3.fromRGB(80, 35, 50),
		NotificationTitle = Color3.fromRGB(255, 245, 250),
		NotificationDescription = Color3.fromRGB(200, 160, 175),
		NotificationInfo = Color3.fromRGB(200, 80, 120),
		NotificationSuccess = Color3.fromRGB(90, 200, 140),
		NotificationWarning = Color3.fromRGB(255, 170, 70),
		NotificationError = Color3.fromRGB(255, 70, 90),
		OutlineAccent = Color3.fromRGB(200, 80, 120),
		GradientSurfaceA = Color3.fromRGB(40, 18, 28),
		GradientSurfaceB = Color3.fromRGB(70, 30, 48),
		GradientPanelA = Color3.fromRGB(48, 22, 34),
		GradientPanelB = Color3.fromRGB(80, 36, 55),
		GradientAccentA = Color3.fromRGB(100, 30, 55),
		GradientAccentB = Color3.fromRGB(200, 70, 110),
		GradientBackgroundA = Color3.fromRGB(20, 10, 14),
		GradientBackgroundB = Color3.fromRGB(50, 20, 32),
		GradientRotation = 135,
	},

}

local function EnsureCorner(obj, radius)
	if not obj or not obj:IsA("GuiObject") then return end
	local value = tonumber(radius)
	if value == nil then value = 2 end
	value = math.max(0, math.floor(value + 0.5))
	local corner = obj:FindFirstChild("VeyraCorner") or obj:FindFirstChildOfClass("UICorner")
	if not corner then
		corner = Instance.new("UICorner")
		corner.Name = "VeyraCorner"
		corner.Parent = obj
	elseif corner.Name ~= "VeyraCorner" then
		corner.Name = "VeyraCorner"
	end
	if corner.CornerRadius.Scale < 0.99 then
		corner.CornerRadius = UDim.new(0, value)
	end
	return corner
end

local AnimatedGradients = {}
local GradientAnimConn = nil
local GradientAnimTime = 0

local GRADIENT_ROTATE_SPEED = {
	Background = 12,
	Surface = 18,
	Panel = 22,
	Accent = 36,
	Default = 16,
}

local function UnregisterGradient(gradient)
	if not gradient then return end
	AnimatedGradients[gradient] = nil
end

local function RegisterGradient(gradient, kind, baseRotation)
	if not gradient or not gradient:IsA("UIGradient") then return end
	local existing = AnimatedGradients[gradient]
	if existing then
		existing.Kind = kind or existing.Kind or "Default"
		existing.Base = tonumber(baseRotation) or existing.Base or (Theme.GradientRotation or 90)
		existing.Speed = GRADIENT_ROTATE_SPEED[kind] or existing.Speed or GRADIENT_ROTATE_SPEED.Default
		return
	end
	AnimatedGradients[gradient] = {
		Kind = kind or "Default",
		Base = tonumber(baseRotation) or (Theme.GradientRotation or 90),
		Phase = math.random() * math.pi * 2,
		Speed = GRADIENT_ROTATE_SPEED[kind] or GRADIENT_ROTATE_SPEED.Default,
	}
	if not GradientAnimConn then
		GradientAnimConn = RunService.Heartbeat:Connect(function(dt)
			GradientAnimTime += dt
			local remove = {}
			for grad, meta in pairs(AnimatedGradients) do
				if not grad or not grad.Parent then
					table.insert(remove, grad)
				else
					grad.Rotation = (grad.Rotation + meta.Speed * dt) % 360
					local wave = math.sin(GradientAnimTime * 0.7 + meta.Phase) * 0.15
					grad.Offset = Vector2.new(wave, math.cos(GradientAnimTime * 0.45 + meta.Phase) * 0.08)
				end
			end
			for _, g in ipairs(remove) do
				AnimatedGradients[g] = nil
			end
			if next(AnimatedGradients) == nil and GradientAnimConn then
				GradientAnimConn:Disconnect()
				GradientAnimConn = nil
			end
		end)
	end
end

local function SetThemeGradient(obj, kind)
	if not obj or not obj:IsA("GuiObject") then return end
	local gradient = obj:FindFirstChild("VeyraGradient")
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Name = "VeyraGradient"
		gradient.Parent = obj
	end

	local a, b
	if kind == "Background" then
		a = Theme.GradientBackgroundA or Theme.Background
		b = Theme.GradientBackgroundB or Theme.Secondary
	elseif kind == "Surface" then
		a = Theme.GradientSurfaceA or Theme.Secondary
		b = Theme.GradientSurfaceB or Theme.Tertiary
	elseif kind == "Panel" then
		a = Theme.GradientPanelA or Theme.Tertiary
		b = Theme.GradientPanelB or Theme.Hover
	elseif kind == "Accent" then
		a = Theme.GradientAccentA or Theme.Accent
		b = Theme.GradientAccentB or Theme.Accent
	else
		a = Theme.GradientSurfaceA or Theme.Secondary
		b = Theme.GradientSurfaceB or Theme.Tertiary
	end

	obj.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	obj.BackgroundTransparency = 0
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, a),
		ColorSequenceKeypoint.new(0.5, a:Lerp(b, 0.5)),
		ColorSequenceKeypoint.new(1, b),
	})
	local baseRot = Theme.GradientRotation or 90
	if not AnimatedGradients[gradient] then
		gradient.Rotation = baseRot
	end
	RegisterGradient(gradient, kind, baseRot)
	return gradient
end

local function DecorateGuiTree(root)
	if not root then return end
	local function decorate(obj)
		if not obj:IsA("GuiObject") then return end
		local n = string.lower(obj.Name or "")
		if obj.BackgroundTransparency < 1 then
			if n ~= "root" and n ~= "body" and n ~= "contentcontainer" and n ~= "tabbar"
				and n ~= "outlineaccent" and n ~= "dim" and n ~= "resizegrip" and n ~= "backgroundimage"
				and n ~= "search" and n ~= "tabbg" and n ~= "titlebar" and n ~= "titlefix"
				and n ~= "sidebar" and n ~= "backgroundholder" then
				EnsureCorner(obj, Settings.CornerRadius or Theme.CornerRadius or 6)
			end
		end
	end
	decorate(root)
	for _, obj in ipairs(root:GetDescendants()) do
		decorate(obj)
	end
end

local ThemeListeners = {}

local function GetTheme()
	return Theme
end

local function SetTheme(t)
	if type(t) ~= "table" then return end
	for k, v in pairs(t) do
		Theme[k] = v
	end
	Theme.CornerRadius = math.max(0, math.floor(tonumber(Settings.CornerRadius or Theme.CornerRadius or 2) or 2))
	for _, fn in ipairs(ThemeListeners) do
		task.spawn(fn)
	end
end

local function ApplyThemePreset(name)
	if name == "Aurora" then name = "Cyan" end 
	local preset = ThemePresets[name]
	if not preset then
		warn("[VeyraUI] Unknown theme preset:", tostring(name))
		return false
	end
	SetTheme(preset)
	return true
end

local function OnThemeChange(fn)
	table.insert(ThemeListeners, fn)
	return function()
		local i = table.find(ThemeListeners, fn)
		if i then table.remove(ThemeListeners, i) end
	end
end

local function CreateCleanup()
	local connections, instances, tasks, callbacks = {}, {}, {}, {}
	local destroyed = false

	local api = {}

	function api:AddConnection(c)
		if destroyed then
			if c and c.Connected then c:Disconnect() end
			return
		end
		table.insert(connections, c)
	end

	function api:AddInstance(i)
		if destroyed then
			if i then i:Destroy() end
			return
		end
		table.insert(instances, i)
	end

	function api:AddTask(t)
		if destroyed then
			pcall(task.cancel, t)
			return
		end
		table.insert(tasks, t)
	end

	function api:AddCallback(fn)
		if destroyed then return end
		table.insert(callbacks, fn)
	end

	function api:Destroy()
		if destroyed then return end
		destroyed = true

		for _, i in ipairs(instances) do
			if i then
				pcall(function() TweenEngine.CancelOnObject(i) end)
			end
		end
		for _, c in ipairs(connections) do
			if c and c.Connected then pcall(function() c:Disconnect() end) end
		end
		for _, i in ipairs(instances) do
			if i and i.Parent then pcall(function() i:Destroy() end) end
		end
		for _, t in ipairs(tasks) do
			pcall(task.cancel, t)
		end
		for _, fn in ipairs(callbacks) do
			pcall(fn)
		end
		table.clear(connections)
		table.clear(instances)
		table.clear(tasks)
		table.clear(callbacks)
	end

	function api:IsDestroyed()
		return destroyed
	end

	return api
end

local Easing = {}

function Easing.Linear(t) return t end
function Easing.QuadIn(t) return t * t end
function Easing.QuadOut(t) return t * (2 - t) end
function Easing.QuadInOut(t)
	if t < 0.5 then return 2 * t * t end
	return -1 + (4 - 2 * t) * t
end
function Easing.CubicIn(t) return t * t * t end
function Easing.CubicOut(t)
	local t1 = t - 1
	return t1 * t1 * t1 + 1
end
function Easing.CubicInOut(t)
	if t < 0.5 then return 4 * t * t * t end
	local t1 = 2 * t - 2
	return 0.5 * t1 * t1 * t1 + 1
end
function Easing.QuartIn(t) return t * t * t * t end
function Easing.QuartOut(t)
	local t1 = t - 1
	return 1 - t1 * t1 * t1 * t1
end
function Easing.QuartInOut(t)
	if t < 0.5 then return 8 * t * t * t * t end
	local t1 = t - 1
	return 1 - 8 * t1 * t1 * t1 * t1
end
function Easing.QuintIn(t) return t * t * t * t * t end
function Easing.QuintOut(t)
	local t1 = t - 1
	return 1 + t1 * t1 * t1 * t1 * t1
end
function Easing.QuintInOut(t)
	if t < 0.5 then return 16 * t * t * t * t * t end
	local t1 = 2 * t - 2
	return 0.5 * t1 * t1 * t1 * t1 * t1 + 1
end
function Easing.SineIn(t) return 1 - math.cos(t * math.pi / 2) end
function Easing.SineOut(t) return math.sin(t * math.pi / 2) end
function Easing.SineInOut(t) return -0.5 * (math.cos(math.pi * t) - 1) end
function Easing.CircularIn(t) return 1 - math.sqrt(1 - t * t) end
function Easing.CircularOut(t) return math.sqrt(1 - (t - 1) * (t - 1)) end
function Easing.CircularInOut(t)
	if t < 0.5 then return 0.5 * (1 - math.sqrt(1 - 4 * t * t)) end
	return 0.5 * (math.sqrt(1 - (2 * t - 2) * (2 * t - 2)) + 1)
end
function Easing.ExpoIn(t)
	if t == 0 then return 0 end
	return math.pow(2, 10 * (t - 1))
end
function Easing.ExpoOut(t)
	if t == 1 then return 1 end
	return 1 - math.pow(2, -10 * t)
end
function Easing.ExpoInOut(t)
	if t == 0 then return 0 end
	if t == 1 then return 1 end
	if t < 0.5 then return 0.5 * math.pow(2, 20 * t - 10) end
	return 1 - 0.5 * math.pow(2, -20 * t + 10)
end
function Easing.BackIn(t)
	local s = 1.70158
	return t * t * ((s + 1) * t - s)
end
function Easing.BackOut(t)
	local s = 1.70158
	local t1 = t - 1
	return t1 * t1 * ((s + 1) * t1 + s) + 1
end
function Easing.BackInOut(t)
	local s = 1.70158 * 1.525
	if t < 0.5 then
		return 0.5 * (t * 2) * (t * 2) * ((s + 1) * (t * 2) - s)
	end
	local t1 = t * 2 - 2
	return 0.5 * (t1 * t1 * ((s + 1) * t1 + s) + 2)
end
function Easing.ElasticIn(t)
	if t == 0 or t == 1 then return t end
	return -math.pow(2, 10 * (t - 1)) * math.sin((t - 1.1) * 5 * math.pi)
end
function Easing.ElasticOut(t)
	if t == 0 or t == 1 then return t end
	return math.pow(2, -10 * t) * math.sin((t - 0.1) * 5 * math.pi) + 1
end
function Easing.ElasticInOut(t)
	if t == 0 or t == 1 then return t end
	t = t * 2
	if t < 1 then
		return -0.5 * math.pow(2, 10 * (t - 1)) * math.sin((t - 1.1) * 5 * math.pi)
	end
	return 0.5 * math.pow(2, -10 * (t - 1)) * math.sin((t - 1.1) * 5 * math.pi) + 1
end
function Easing.BounceOut(t)
	if t < 1 / 2.75 then
		return 7.5625 * t * t
	elseif t < 2 / 2.75 then
		t = t - 1.5 / 2.75
		return 7.5625 * t * t + 0.75
	elseif t < 2.5 / 2.75 then
		t = t - 2.25 / 2.75
		return 7.5625 * t * t + 0.9375
	else
		t = t - 2.625 / 2.75
		return 7.5625 * t * t + 0.984375
	end
end
function Easing.BounceIn(t) return 1 - Easing.BounceOut(1 - t) end
function Easing.BounceInOut(t)
	if t < 0.5 then return Easing.BounceIn(t * 2) * 0.5 end
	return Easing.BounceOut(t * 2 - 1) * 0.5 + 0.5
end

local EasingNamed = {
	Linear = Easing.Linear,
	QuadIn = Easing.QuadIn, QuadOut = Easing.QuadOut, QuadInOut = Easing.QuadInOut,
	CubicIn = Easing.CubicIn, CubicOut = Easing.CubicOut, CubicInOut = Easing.CubicInOut,
	QuartIn = Easing.QuartIn, QuartOut = Easing.QuartOut, QuartInOut = Easing.QuartInOut,
	QuintIn = Easing.QuintIn, QuintOut = Easing.QuintOut, QuintInOut = Easing.QuintInOut,
	SineIn = Easing.SineIn, SineOut = Easing.SineOut, SineInOut = Easing.SineInOut,
	CircularIn = Easing.CircularIn, CircularOut = Easing.CircularOut, CircularInOut = Easing.CircularInOut,
	ExpoIn = Easing.ExpoIn, ExpoOut = Easing.ExpoOut, ExpoInOut = Easing.ExpoInOut,
	BackIn = Easing.BackIn, BackOut = Easing.BackOut, BackInOut = Easing.BackInOut,
	ElasticIn = Easing.ElasticIn, ElasticOut = Easing.ElasticOut, ElasticInOut = Easing.ElasticInOut,
	BounceIn = Easing.BounceIn, BounceOut = Easing.BounceOut, BounceInOut = Easing.BounceInOut,
}

local function GetEasing(name)
	if type(name) == "function" then return name end
	return EasingNamed[name] or Easing.Linear
end

local ActiveAnims = {}
local SchedulerConn = nil
local AnimIdCounter = 0

local function SchedulerUpdate(dt)
	local remove = {}
	for id, anim in pairs(ActiveAnims) do
		if anim.Cancelled or anim._finished then
			table.insert(remove, id)
		else
			local ok, done = pcall(function()
				return anim:Update(dt)
			end)
			if not ok or done then
				anim._finished = true
				table.insert(remove, id)
				if ok and anim.OnComplete and not anim.Cancelled then

					task.spawn(anim.OnComplete)
				end
			end
		end
	end
	for _, id in ipairs(remove) do
		local anim = ActiveAnims[id]
		if anim then
			anim.Id = nil
		end
		ActiveAnims[id] = nil
	end
	if next(ActiveAnims) == nil and SchedulerConn then
		SchedulerConn:Disconnect()
		SchedulerConn = nil
	end
end

local function SchedulerAdd(anim)
	if anim.Cancelled or anim._finished then
		return nil
	end
	AnimIdCounter += 1
	local id = "a" .. AnimIdCounter
	anim.Id = id
	ActiveAnims[id] = anim
	if not SchedulerConn then
		SchedulerConn = RunService.Heartbeat:Connect(SchedulerUpdate)
	end
	return id
end

local function SchedulerRemove(anim)
	if anim and anim.Id and ActiveAnims[anim.Id] then
		ActiveAnims[anim.Id] = nil
		anim.Id = nil
	end
end

local function LerpNumber(a, b, t) return a + (b - a) * t end
local function LerpColor3(a, b, t)
	return Color3.new(LerpNumber(a.R, b.R, t), LerpNumber(a.G, b.G, t), LerpNumber(a.B, b.B, t))
end
local function LerpVector2(a, b, t) return Vector2.new(LerpNumber(a.X, b.X, t), LerpNumber(a.Y, b.Y, t)) end
local function LerpVector3(a, b, t)
	return Vector3.new(LerpNumber(a.X, b.X, t), LerpNumber(a.Y, b.Y, t), LerpNumber(a.Z, b.Z, t))
end
local function LerpUDim(a, b, t)
	return UDim.new(LerpNumber(a.Scale, b.Scale, t), LerpNumber(a.Offset, b.Offset, t))
end
local function LerpUDim2(a, b, t)
	return UDim2.new(
		LerpNumber(a.X.Scale, b.X.Scale, t), LerpNumber(a.X.Offset, b.X.Offset, t),
		LerpNumber(a.Y.Scale, b.Y.Scale, t), LerpNumber(a.Y.Offset, b.Y.Offset, t)
	)
end
local function LerpCFrame(a, b, t) return a:Lerp(b, t) end

local function GetLerp(v)
	local t = typeof(v)
	if t == "number" then return LerpNumber
	elseif t == "Color3" then return LerpColor3
	elseif t == "Vector2" then return LerpVector2
	elseif t == "Vector3" then return LerpVector3
	elseif t == "UDim" then return LerpUDim
	elseif t == "UDim2" then return LerpUDim2
	elseif t == "CFrame" then return LerpCFrame
	end
	return nil
end

local Animation = {}
Animation.__index = Animation

function Animation.new(object, goals, options)
	local self = setmetatable({}, Animation)
	options = options or {}
	self.Object = object
	self.Goals = goals
	self.Duration = math.max(options.Duration or 0.4, 0.001)
	self.Delay = options.Delay or 0
	self.EasingFn = GetEasing(options.Easing or "QuadOut")
	self.OnComplete = options.OnComplete
	self.Loop = options.Loop or false
	self.Yoyo = options.Yoyo or false
	self.Cancelled = false
	self._finished = false
	self.Elapsed = 0
	self.Started = false
	self.Direction = 1
	self.StartValues = {}
	self.LerpFns = {}
	self.Id = nil

	for prop, goal in pairs(goals) do
		local ok, current = pcall(function() return object[prop] end)
		if ok and current ~= nil then
			self.StartValues[prop] = current
			self.LerpFns[prop] = GetLerp(current)
		end
	end
	return self
end

function Animation:Update(dt)
	if self.Cancelled or self._finished then return true end

	if not self.Started then
		self.Elapsed += dt
		if self.Elapsed < self.Delay then return false end
		self.Started = true
		self.Elapsed = 0
	end

	self.Elapsed += dt
	local alpha = math.clamp(self.Elapsed / self.Duration, 0, 1)
	local eased = self.EasingFn(alpha)

	for prop, goal in pairs(self.Goals) do
		local lerp = self.LerpFns[prop]
		local start = self.StartValues[prop]
		if lerp and start ~= nil then
			local value = (self.Direction > 0) and lerp(start, goal, eased) or lerp(goal, start, eased)
			pcall(function()
				if self.Object and self.Object.Parent then
					self.Object[prop] = value
				end
			end)
		end
	end

	if self.Elapsed >= self.Duration then
		if self.Yoyo then
			self.Direction = -self.Direction
			self.Elapsed = 0
			return false
		elseif self.Loop then
			self.Elapsed = 0
			return false
		else
			for prop, goal in pairs(self.Goals) do
				local final = (self.Direction > 0) and goal or self.StartValues[prop]
				pcall(function()
					if self.Object and self.Object.Parent then
						self.Object[prop] = final
					end
				end)
			end
			self._finished = true
			return true
		end
	end
	return false
end

function Animation:Cancel()
	if self.Cancelled or self._finished then return end
	self.Cancelled = true
	self._finished = true

	self.OnComplete = nil
	SchedulerRemove(self)
end

function Animation:Play()
	if self.Cancelled or self._finished then return self end
	self.Id = SchedulerAdd(self)
	return self
end

local TweenEngine = {}

function TweenEngine.Play(object, goals, options)
	if not object or not object.Parent then return nil end
	local anim = Animation.new(object, goals, options)
	return anim:Play()
end

function TweenEngine.Spring(object, property, target, options)
	if not object or not object.Parent then return nil end
	options = options or {}
	local stiffness = options.Stiffness or 180
	local damping = options.Damping or 18
	local mass = options.Mass or 1

	local spring = setmetatable({}, Animation)
	spring.Object = object
	spring.Cancelled = false
	spring._finished = false
	spring.OnComplete = options.OnComplete
	spring.Property = property
	spring.Target = target
	spring.Stiffness = stiffness
	spring.Damping = damping
	spring.Mass = mass
	spring.Velocity = 0
	spring.Id = nil

	local ok, current = pcall(function() return object[property] end)
	if not ok then return nil end
	spring.Current = current

	function spring:Update(dt)
		if self.Cancelled or self._finished then return true end
		if not self.Object or not self.Object.Parent then
			self._finished = true
			return true
		end
		if typeof(self.Current) == "number" then
			local force = -self.Stiffness * (self.Current - self.Target)
			local damp = -self.Damping * self.Velocity
			local accel = (force + damp) / self.Mass
			self.Velocity += accel * dt
			self.Current += self.Velocity * dt
			pcall(function() self.Object[self.Property] = self.Current end)
			if math.abs(self.Current - self.Target) < 0.001 and math.abs(self.Velocity) < 0.001 then
				pcall(function() self.Object[self.Property] = self.Target end)
				self._finished = true
				return true
			end
		elseif typeof(self.Current) == "UDim2" then
			local cx, cy = self.Current.X.Offset, self.Current.Y.Offset
			local tx, ty = self.Target.X.Offset, self.Target.Y.Offset
			self.Velocity = self.Velocity or Vector2.zero
			local forceX = -self.Stiffness * (cx - tx)
			local forceY = -self.Stiffness * (cy - ty)
			local vx = self.Velocity.X + (forceX - self.Damping * self.Velocity.X) / self.Mass * dt
			local vy = self.Velocity.Y + (forceY - self.Damping * self.Velocity.Y) / self.Mass * dt
			self.Velocity = Vector2.new(vx, vy)
			cx += vx * dt
			cy += vy * dt
			self.Current = UDim2.new(self.Current.X.Scale, cx, self.Current.Y.Scale, cy)
			pcall(function() self.Object[self.Property] = self.Current end)
			if math.abs(cx - tx) < 0.5 and math.abs(cy - ty) < 0.5 and math.abs(vx) < 1 and math.abs(vy) < 1 then
				pcall(function() self.Object[self.Property] = self.Target end)
				self._finished = true
				return true
			end
		else
			self._finished = true
			return true
		end
		return false
	end

	function spring:Cancel()
		if self.Cancelled or self._finished then return end
		self.Cancelled = true
		self._finished = true
		self.OnComplete = nil
		SchedulerRemove(self)
	end

	function spring:Play()
		if self.Cancelled or self._finished then return self end
		self.Id = SchedulerAdd(self)
		return self
	end
	return spring:Play()
end

function TweenEngine.Shake(object, options)
	if not object or not object.Parent then return nil end
	options = options or {}
	local magnitude = options.Magnitude or 4
	local duration = options.Duration or 0.3
	local frequency = options.Frequency or 25
	local property = options.Property or "Position"

	local ok, original = pcall(function() return object[property] end)
	if not ok then return nil end

	local shake = setmetatable({}, Animation)
	shake.Object = object
	shake.Cancelled = false
	shake._finished = false
	shake.OnComplete = options.OnComplete
	shake.Original = original
	shake.Elapsed = 0
	shake.Duration = duration
	shake.Magnitude = magnitude
	shake.Frequency = frequency
	shake.Property = property
	shake.Id = nil

	function shake:Update(dt)
		if self.Cancelled or self._finished then
			pcall(function()
				if self.Object and self.Object.Parent then
					self.Object[self.Property] = self.Original
				end
			end)
			return true
		end
		if not self.Object or not self.Object.Parent then
			self._finished = true
			return true
		end
		self.Elapsed += dt
		if self.Elapsed >= self.Duration then
			pcall(function() self.Object[self.Property] = self.Original end)
			self._finished = true
			return true
		end
		local progress = self.Elapsed / self.Duration
		local damp = 1 - progress
		local ox = math.sin(self.Elapsed * self.Frequency * math.pi * 2) * self.Magnitude * damp
		local oy = math.cos(self.Elapsed * self.Frequency * math.pi * 1.7) * self.Magnitude * damp * 0.7
		if typeof(self.Original) == "UDim2" then
			pcall(function()
				self.Object[self.Property] = UDim2.new(
					self.Original.X.Scale, self.Original.X.Offset + ox,
					self.Original.Y.Scale, self.Original.Y.Offset + oy
				)
			end)
		end
		return false
	end

	function shake:Cancel()
		if self.Cancelled or self._finished then return end
		self.Cancelled = true
		self._finished = true
		self.OnComplete = nil
		pcall(function()
			if self.Object and self.Object.Parent then
				self.Object[self.Property] = self.Original
			end
		end)
		SchedulerRemove(self)
	end

	function shake:Play()
		if self.Cancelled or self._finished then return self end
		self.Id = SchedulerAdd(self)
		return self
	end
	return shake:Play()
end

function TweenEngine.CancelAll()
	for id, anim in pairs(ActiveAnims) do
		if anim and not anim.Cancelled then
			anim.Cancelled = true
			anim._finished = true
			anim.OnComplete = nil
			if anim.Cancel then
				pcall(function() anim:Cancel() end)
			end
		end
	end
	table.clear(ActiveAnims)
	if SchedulerConn then
		SchedulerConn:Disconnect()
		SchedulerConn = nil
	end
end

function TweenEngine.CancelOnObject(object)
	if not object then return end
	for id, anim in pairs(ActiveAnims) do
		if anim and anim.Object == object and not anim.Cancelled then
			anim:Cancel()
		end
	end
end

local UI_HOVER_SOUND_ID = "rbxassetid://10066936758"
local UI_CLICK_SOUND_ID = "rbxassetid://6042053626"
local UI_TOGGLE_SOUND_ID = "rbxassetid://6895079853"
local UI_HOVER_SCALE = 1.035
local UI_HOVER_TWEEN = 0.12

local UISoundFolder = SoundService:FindFirstChild("VeyraUISounds")
if not UISoundFolder then
	UISoundFolder = Instance.new("Folder")
	UISoundFolder.Name = "VeyraUISounds"
	UISoundFolder.Parent = SoundService
end

local function PlayUISound(soundId, volume, playbackSpeed)
	local ok = pcall(function()
		local sound = Instance.new("Sound")
		sound.Name = "VeyraUI"
		sound.SoundId = tostring(soundId or UI_CLICK_SOUND_ID)
		sound.Volume = tonumber(volume) or 0.35
		sound.PlaybackSpeed = tonumber(playbackSpeed) or 1
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.Parent = UISoundFolder
		sound:Play()
		task.delay(1.5, function()
			if sound and sound.Parent then sound:Destroy() end
		end)
	end)
	return ok
end

local function PlayUIHoverSound()
	return PlayUISound(UI_HOVER_SOUND_ID, 0.18, 1.15)
end

local function PlayUIClickSound()
	return PlayUISound(UI_CLICK_SOUND_ID, 0.38, 1)
end

local function PlayUIToggleSound()
	return PlayUISound(UI_TOGGLE_SOUND_ID, 0.32, 1.05)
end

local function PlayUIInteractionSound()
	return PlayUIClickSound()
end

local function AddInteractiveFeedback(guiObject, cleanup, options)
	if not guiObject or not guiObject:IsA("GuiObject") then return nil end
	options = options or {}
	local hoverScale = tonumber(options.HoverScale) or UI_HOVER_SCALE
	local doHover = options.Hover ~= false
	local playHoverSound = options.HoverSound ~= false
	local playActivateSound = options.ActivateSound ~= false
	local scaleObj = nil

	if doHover then
		scaleObj = guiObject:FindFirstChild("VeyraHoverScale")
		if not scaleObj then
			scaleObj = Instance.new("UIScale")
			scaleObj.Name = "VeyraHoverScale"
			scaleObj.Scale = 1
			scaleObj.Parent = guiObject
		end
	end

	local hovered = false
	local function tweenScale(target)
		if not scaleObj then return end
		TweenEngine.CancelOnObject(scaleObj)
		TweenEngine.Play(scaleObj, { Scale = target }, {
			Duration = tonumber(options.Duration) or UI_HOVER_TWEEN,
			Easing = "QuadOut",
		})
	end

	local connections = {}
	if doHover then
		table.insert(connections, guiObject.MouseEnter:Connect(function()
			hovered = true
			if options.Disabled and options.Disabled() then return end
			if playHoverSound then PlayUIHoverSound() end
			tweenScale(hoverScale)
		end))
		table.insert(connections, guiObject.MouseLeave:Connect(function()
			hovered = false
			if options.Disabled and options.Disabled() then return end
			tweenScale(1)
		end))
	end

	if playActivateSound and guiObject:IsA("GuiButton") then
		table.insert(connections, guiObject.Activated:Connect(function()
			if options.Disabled and options.Disabled() then return end
			PlayUIClickSound()
			if options.OnActivated then task.spawn(options.OnActivated) end
		end))
	end

	if cleanup then
		for _, c in ipairs(connections) do cleanup:AddConnection(c) end
		if scaleObj then cleanup:AddInstance(scaleObj) end
	end

	return {
		Scale = scaleObj,
		IsHovered = function() return hovered end,
		Reset = function() tweenScale(1) end,
	}
end

local function MakeDraggable(handle, target, options)
	options = options or {}
	target = target or handle
	local enabled = true
	local dragging = false
	local dragStart, startPos
	local conns = {}
	local activeMoveC, activeEndC = nil, nil

	local function clearDragConns()
		if activeMoveC then
			pcall(function() activeMoveC:Disconnect() end)
			activeMoveC = nil
		end
		if activeEndC then
			pcall(function() activeEndC:Disconnect() end)
			activeEndC = nil
		end
		dragging = false
	end

	local function update(input)
		local delta = input.Position - dragStart
		local newPos = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + delta.X,
			startPos.Y.Scale, startPos.Y.Offset + delta.Y
		)
		target.Position = newPos
		if options.OnDrag then options.OnDrag(newPos, delta) end
	end

	table.insert(conns, handle.InputBegan:Connect(function(input)
		if not enabled then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			clearDragConns()
			dragging = true
			dragStart = input.Position
			startPos = target.Position
			if options.OnDragStart then options.OnDragStart() end

			activeMoveC = UserInputService.InputChanged:Connect(function(inp)
				if (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) and dragging then
					update(inp)
				end
			end)
			activeEndC = UserInputService.InputEnded:Connect(function(inp)
				if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
					dragging = false
					clearDragConns()
					if options.OnDragEnd then options.OnDragEnd() end
				end
			end)
		end
	end))

	return {
		SetEnabled = function(s) enabled = s end,
		Destroy = function()
			clearDragConns()
			for _, c in ipairs(conns) do
				pcall(function() c:Disconnect() end)
			end
			table.clear(conns)
		end
	}
end

local function CreateTypewriter(label, options)
	options = options or {}
	local speed = options.Speed or 0.025
	local fullText = label.Text or ""
	local cancelled = false
	local finished = false
	local thread = nil

	local api = {}

	function api:Start(text)
		if text then fullText = text end
		cancelled = false
		finished = false
		label.Text = ""
		thread = task.spawn(function()
			for i = 1, #fullText do
				if cancelled then return end
				label.Text = string.sub(fullText, 1, i)
				local char = string.sub(fullText, i, i)
				local d = speed
				if char == "." or char == "!" or char == "?" then
					d = speed * 4
				elseif char == "," or char == ";" then
					d = speed * 2
				elseif char == " " then
					d = speed * 0.6
				end
				task.wait(d)
			end
			finished = true
			if options.OnComplete then options.OnComplete() end
		end)
	end

	function api:Finish()
		cancelled = true
		if thread then pcall(task.cancel, thread) end
		label.Text = fullText
		finished = true
	end

	function api:Cancel()
		cancelled = true
		if thread then pcall(task.cancel, thread) end
	end

	function api:IsFinished()
		return finished
	end

	return api
end

local function CreateEtherealSeparator(parent)
	local container = Instance.new("Frame")
	container.Name = "EtherealSeparator"
	container.BackgroundTransparency = 1
	container.Size = UDim2.new(1, 0, 0, 8)
	container.BorderSizePixel = 0
	container.Parent = parent

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BackgroundColor3 = Theme.NotificationTitle
	bar.BackgroundTransparency = 0.7
	bar.BorderSizePixel = 0
	bar.Size = UDim2.new(0.6, 0, 0, 1)
	bar.Position = UDim2.new(0.2, 0, 0.5, 0)
	bar.AnchorPoint = Vector2.new(0, 0.5)
	bar.Parent = container

	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.4),
		NumberSequenceKeypoint.new(0.5, 0.15),
		NumberSequenceKeypoint.new(0.8, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = bar

	local api = { Container = container, Bar = bar }

	function api:PlayIn(dur)
		dur = dur or 0.45
		bar.Size = UDim2.new(0, 0, 0, 1)
		bar.BackgroundTransparency = 1
		bar.Position = UDim2.new(0.5, 0, 0.5, 0)
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		TweenEngine.Play(bar, {
			Size = UDim2.new(0.7, 0, 0, 1),
			BackgroundTransparency = 0.65,
			Position = UDim2.new(0.15, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
		}, { Duration = dur, Easing = "ExpoOut" })
	end

	function api:PlayOut(dur)
		dur = dur or 0.25
		TweenEngine.Play(bar, {
			Size = UDim2.new(0, 0, 0, 1),
			BackgroundTransparency = 1,
			Position = UDim2.new(0.5, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
		}, { Duration = dur, Easing = "QuadIn" })
	end

	function api:Destroy()
		if container then container:Destroy() end
	end

	return api
end

local NotificationManager = {}
NotificationManager.__index = NotificationManager

local MAX_NOTIFICATIONS = 10
local NOTIF_CORNER = 16
local NOTIF_HEADER_H = 30
local NOTIF_WIDTH = 320

function NotificationManager.new()
	local self = setmetatable({}, NotificationManager)
	self.Notifications = {}
	self.Spacing = 12
	self.MaxNotifications = MAX_NOTIFICATIONS

	local gui = Instance.new("ScreenGui")
	gui.Name = "VeyraNotifications"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 2147483647
	ProtectAndParent(gui)

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.BackgroundTransparency = 1
	container.Size = UDim2.new(0, 360, 1, -24)
	container.Position = UDim2.new(1, -16, 1, -12)
	container.AnchorPoint = Vector2.new(1, 1)
	container.Parent = gui

	self.Gui = gui
	self.Container = container
	self.Draggable = true
	return self
end

local TYPE_COLORS = {
	Info = "NotificationInfo",
	Success = "NotificationSuccess",
	Warning = "NotificationWarning",
	Error = "NotificationError",
	Custom = "Accent",
}

function NotificationManager:Notify(config)
	config = config or {}

	local duration = config.Duration
	if duration == nil then duration = config.Length end
	if duration == nil then duration = 5 end
	local notifType = config.Type or "Info"
	local typewriterOpts = config.Typewriter
	local barColor = config.BarColor or Theme[TYPE_COLORS[notifType] or "NotificationInfo"] or Theme.Accent
	local audioId = config.Audio or config.Sound
	local imageId = config.Image or config.Icon

	local cleanup = CreateCleanup()
	local closed = false

	local bg = Theme.NotificationBackground or Theme.Background
	local bd = Theme.NotificationBorder or Theme.Border
	local titleCol = Theme.NotificationTitle or Theme.Text
	local descCol = Theme.NotificationDescription or Theme.SecondaryText
	local headBg = Theme.Secondary or bg

	local frame = Instance.new("Frame")
	frame.Name = "Notification"
	frame.BackgroundColor3 = bg
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(0, NOTIF_WIDTH, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.AnchorPoint = Vector2.new(0, 1)
	frame.Position = UDim2.new(0, 0, 1, 0)
	frame.ClipsDescendants = true
	frame.Parent = self.Container

	do
		local canDrag = true
		if config.Draggable == false then canDrag = false end
		if self.Draggable == false then canDrag = false end
		if canDrag then
			local dragApi = MakeDraggable(frame, frame)
			cleanup:AddCallback(function()
				if dragApi and dragApi.Destroy then dragApi:Destroy() end
			end)
		end
	end

	local function shade(c, mul)
		return Color3.new(
			math.clamp(c.R * mul, 0, 1),
			math.clamp(c.G * mul, 0, 1),
			math.clamp(c.B * mul, 0, 1)
		)
	end
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, shade(bg, 0.92)),
		ColorSequenceKeypoint.new(0.50, bg),
		ColorSequenceKeypoint.new(1.00, shade(bg, 1.08)),
	})
	gradient.Rotation = 0
	gradient.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = bd
	stroke.Thickness = 1
	stroke.Transparency = 0.3
	stroke.Parent = frame

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundColor3 = headBg
	header.BackgroundTransparency = 0.15
	header.BorderSizePixel = 0
	header.Size = UDim2.new(1, 0, 0, NOTIF_HEADER_H)
	header.ZIndex = 2
	header.Parent = frame

	local contentOffset = 14
	if imageId and tostring(imageId) ~= "" then
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.new(0, 22, 0, 22)
		icon.Position = UDim2.new(0, 12, 0.5, -11)
		icon.Image = tostring(imageId)
		icon.ScaleType = Enum.ScaleType.Fit
		icon.ZIndex = 4
		icon.Parent = header
		contentOffset = 40
		cleanup:AddInstance(icon)
	end

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -contentOffset - 12, 1, 0)
	title.Position = UDim2.new(0, contentOffset, 0, 0)
	title.Font = Theme.FontBold
	title.TextSize = 14
	title.TextColor3 = titleCol
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = config.Title or "Notification"
	title.ZIndex = 4
	title.Parent = header

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Position = UDim2.new(0, 0, 0, NOTIF_HEADER_H)
	body.Parent = frame

	local bodyPad = Instance.new("UIPadding")
	bodyPad.PaddingTop = UDim.new(0, 10)
	bodyPad.PaddingBottom = UDim.new(0, 16)
	bodyPad.PaddingLeft = UDim.new(0, 16)
	bodyPad.PaddingRight = UDim.new(0, 16)
	bodyPad.Parent = body

	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Padding = UDim.new(0, 6)
	bodyLayout.Parent = body

	local sep = CreateEtherealSeparator(body)
	sep.Container.LayoutOrder = 1

	local descText = config.Description or config.Content or ""
	local desc = Instance.new("TextLabel")
	desc.Name = "Description"
	desc.BackgroundTransparency = 1
	desc.Size = UDim2.new(1, 0, 0, 0)
	desc.AutomaticSize = Enum.AutomaticSize.Y
	desc.Font = Theme.Font
	desc.TextSize = 13
	desc.TextColor3 = descCol
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.TextWrapped = true
	desc.Text = descText
	desc.LayoutOrder = 2
	desc.Parent = body

	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.BackgroundColor3 = barColor
	accent.BorderSizePixel = 0
	
	accent.Size = UDim2.new(0, 3, 1, 0)
	accent.Position = UDim2.new(0, 0, 0, 0)
	accent.ZIndex = 5
	accent.Parent = frame

	local accentCorner = Instance.new("UICorner")
	accentCorner.CornerRadius = UDim.new(0, 2)
	accentCorner.Parent = accent

	local barBg = Instance.new("Frame")
	barBg.Name = "ProgressBG"
	barBg.BackgroundColor3 = Theme.Border or Color3.fromRGB(80, 80, 90)
	barBg.BackgroundTransparency = 0.7
	barBg.BorderSizePixel = 0
	barBg.Size = UDim2.new(1, 0, 0, 3)
	barBg.Position = UDim2.new(0, 0, 1, -3)
	barBg.ZIndex = 6
	barBg.Parent = frame

	local bar = Instance.new("Frame")
	bar.Name = "Progress"
	bar.BackgroundColor3 = barColor
	bar.BackgroundTransparency = 0.15
	bar.BorderSizePixel = 0
	bar.Size = UDim2.new(1, 0, 1, 0)
	bar.Parent = barBg

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = bar

	if duration <= 0 then
		barBg.Visible = false
	end

	cleanup:AddInstance(frame)

	if audioId and tostring(audioId) ~= "" then
		local sound = Instance.new("Sound")
		sound.SoundId = tostring(audioId)
		sound.Volume = 0.8
		sound.Parent = frame
		pcall(function() sound:Play() end)
		cleanup:AddInstance(sound)
	end

	local twTitle, twDesc
	local doTitle, doDesc, speed = false, false, 0.025
	if typewriterOpts == true then
		doTitle, doDesc = true, true
	elseif type(typewriterOpts) == "table" then
		doTitle = typewriterOpts.Title ~= false
		doDesc = typewriterOpts.Description ~= false
		speed = typewriterOpts.Speed or 0.025
	end
	if doTitle then twTitle = CreateTypewriter(title, { Speed = speed }) end
	if doDesc then twDesc = CreateTypewriter(desc, { Speed = speed }) end

	local notif = {
		Frame = frame,
		TitleLabel = title,
		DescLabel = desc,
		Separator = sep,
		Closed = false,
		Config = config,
		Cleanup = cleanup,
	}

	function notif:PlayEntry(targetPos)
		frame.Position = UDim2.new(0, 40, 1, targetPos.Y.Offset)
		frame.BackgroundTransparency = 1
		TweenEngine.Play(frame, {
			Position = targetPos,
			BackgroundTransparency = 0,
		}, { Duration = 0.45, Easing = "QuintOut" })

		task.delay(0.12, function()
			if not closed then sep:PlayIn(0.35) end
		end)
		task.delay(0.18, function()
			if closed then return end
			if twTitle then twTitle:Start(config.Title or "Notification") end
			if twDesc then twDesc:Start(descText) end
		end)

		if duration > 0 then
			TweenEngine.Play(bar, {
				Size = UDim2.new(0, 0, 1, 0),
			}, { Duration = duration, Easing = "Linear" })
		end
	end

	function notif:PlayExit(callback)
		if closed then return end
		closed = true
		notif.Closed = true
		if twTitle then twTitle:Finish() end
		if twDesc then twDesc:Finish() end
		sep:PlayOut(0.2)
		TweenEngine.CancelOnObject(bar)
		TweenEngine.Play(frame, {
			Position = UDim2.new(0, 60, 1, frame.Position.Y.Offset),
			BackgroundTransparency = 1,
		}, {
			Duration = 0.32,
			Easing = "QuintIn",
			OnComplete = function()
				cleanup:Destroy()
				sep:Destroy()
				if callback then callback() end
			end,
		})
	end

	function notif:Close()
		if closed then return end
		self.Manager:Remove(self)
	end

	function notif:SetTitle(text)
		config.Title = text
		if twTitle and not twTitle:IsFinished() then twTitle:Finish() end
		title.Text = text
	end

	function notif:SetDescription(text)
		config.Description = text
		if twDesc and not twDesc:IsFinished() then twDesc:Finish() end
		desc.Text = text
	end

	function notif:RefreshTheme()
		if closed or not frame or not frame.Parent then return end
		local nbg = Theme.NotificationBackground or Theme.Background
		local nbd = Theme.NotificationBorder or Theme.Border
		local nt = Theme.NotificationTitle or Theme.Text
		local nd = Theme.NotificationDescription or Theme.SecondaryText
		frame.BackgroundColor3 = nbg
		stroke.Color = nbd
		header.BackgroundColor3 = Theme.Secondary or nbg
		title.TextColor3 = nt
		desc.TextColor3 = nd
		local function shade(c, mul)
			return Color3.new(math.clamp(c.R*mul,0,1), math.clamp(c.G*mul,0,1), math.clamp(c.B*mul,0,1))
		end
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.00, shade(nbg, 0.92)),
			ColorSequenceKeypoint.new(0.50, nbg),
			ColorSequenceKeypoint.new(1.00, shade(nbg, 1.08)),
		})
	end
	local unhookTheme = OnThemeChange(function()
		if notif.RefreshTheme then notif:RefreshTheme() end
	end)
	cleanup:AddCallback(unhookTheme)

	notif.Manager = self
	table.insert(self.Notifications, 1, notif)

	local maxN = self.MaxNotifications or MAX_NOTIFICATIONS
	while #self.Notifications > maxN do
		local oldest = self.Notifications[#self.Notifications]
		if oldest and not oldest.Closed then
			oldest:Close()
		else
			table.remove(self.Notifications, #self.Notifications)
		end
	end

	task.defer(function()
		if closed then return end
		self:RepositionAll(true)
		notif:PlayEntry(self:GetPositionForIndex(1))
	end)

	if duration > 0 then
		local t = task.delay(duration, function()
			if not closed then notif:Close() end
		end)
		cleanup:AddTask(t)
	end

	return notif
end

function NotificationManager:GetPositionForIndex(index)

	local y = 0
	for i = 1, index - 1 do
		local n = self.Notifications[i]
		if n and n.Frame and not n.Closed then
			local h = n.Frame.AbsoluteSize.Y
			if h < 1 then h = 72 end
			y = y + h + self.Spacing
		end
	end

	local maxY = math.max(0, (self.Container.AbsoluteSize.Y > 0 and self.Container.AbsoluteSize.Y or 600) - 40)
	if y > maxY then

		y = math.min(y, maxY + 200)
	end

	return UDim2.new(0, 0, 1, -y)
end

function NotificationManager:RepositionAll(animate)
	local function apply()
		for i, notif in ipairs(self.Notifications) do
			if notif.Closed then continue end
			local target = self:GetPositionForIndex(i)
			if animate then
				TweenEngine.Play(notif.Frame, { Position = target }, { Duration = 0.3, Easing = "QuintOut" })
			else
				notif.Frame.Position = target
			end
		end
	end
	apply()

	task.defer(apply)
end

function NotificationManager:Remove(notif)
	local idx = table.find(self.Notifications, notif)
	if not idx then return end
	table.remove(self.Notifications, idx)
	notif:PlayExit(function()
		self:RepositionAll(true)
	end)
end

function NotificationManager:Clear()
	while #self.Notifications > 0 do
		self.Notifications[1]:Close()
	end
end

function NotificationManager:Destroy()
	self:Clear()
	if self.Gui then self.Gui:Destroy() end
end

local function GetParentForComponent(tab)
	if #tab.Sections > 0 then
		return tab.Sections[#tab.Sections].Content
	end
	return tab.Content
end

local function CreateSection(tab, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local collapsible = config.Collapsible == true
	local collapsed = collapsible and config.DefaultCollapsed == true
	local HEADER_H = 20
	local DESC_H = config.Description and 16 or 0
	local HEADER_GAP = config.Description and 8 or 0
	local CONTENT_GAP = 8

	local container = Instance.new("Frame")
	container.Name = "Section_" .. (config.Name or "Untitled")
	container.BackgroundTransparency = 1
	container.Size = UDim2.new(1, 0, 0, HEADER_H + DESC_H + HEADER_GAP)
	container.AutomaticSize = Enum.AutomaticSize.None
	container.Parent = tab.Content

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, CONTENT_GAP)
	layout.Parent = container

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, collapsible and -24 or 0, 0, HEADER_H)
	title.Font = Theme.FontBold
	title.TextSize = 13
	title.TextColor3 = Theme.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = config.Name or "Section"
	title.LayoutOrder = 0
	title.Parent = container

	local collapseButton
	local collapseArrow
	if collapsible then
		collapseButton = Instance.new("TextButton")
		collapseButton.Name = "CollapseButton"
		collapseButton.BackgroundTransparency = 1
		collapseButton.BorderSizePixel = 0
		collapseButton.AutoButtonColor = false
		collapseButton.Text = ""
		collapseButton.Size = UDim2.new(1, 0, 0, HEADER_H)
		collapseButton.Position = UDim2.new(0, 0, 0, 0)
		collapseButton.ZIndex = 5
		collapseButton.Parent = container

		collapseArrow = Instance.new("TextLabel")
		collapseArrow.Name = "CollapseArrow"
		collapseArrow.BackgroundTransparency = 1
		collapseArrow.Size = UDim2.fromOffset(18, HEADER_H)
		collapseArrow.Position = UDim2.new(1, -18, 0, 0)
		collapseArrow.Font = Theme.FontBold
		collapseArrow.TextSize = 11
		collapseArrow.TextXAlignment = Enum.TextXAlignment.Center
		collapseArrow.TextYAlignment = Enum.TextYAlignment.Center
		collapseArrow.TextColor3 = Theme.SecondaryText
		collapseArrow.Text = collapsed and ">" or "v"
		collapseArrow.ZIndex = 6
		collapseArrow.Parent = container
	end

	local descLabel = nil
	if config.Description then
		local d = Instance.new("TextLabel")
		d.BackgroundTransparency = 1
		d.Size = UDim2.new(1, 0, 0, DESC_H)
		d.Font = Theme.Font
		d.TextSize = 11
		d.TextColor3 = Theme.SecondaryText
		d.TextXAlignment = Enum.TextXAlignment.Left
		d.Text = config.Description
		d.LayoutOrder = 1
		d.Parent = container
		descLabel = d
	end

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(1, 0, 0, 0)
	content.AutomaticSize = Enum.AutomaticSize.Y
	content.LayoutOrder = config.Description and 2 or 1
	content.Parent = container

	local cl = Instance.new("UIListLayout")
	cl.SortOrder = Enum.SortOrder.LayoutOrder
	cl.Padding = UDim.new(0, 6)
	cl.Parent = content

	cleanup:AddInstance(container)

	local function updateSectionSize()
		if cleanup:IsDestroyed() or not container.Parent then return end
		local headerPart = HEADER_H + DESC_H + HEADER_GAP
		if collapsed then
			container.Size = UDim2.new(1, 0, 0, headerPart)
			return
		end
		local contentHeight = cl.AbsoluteContentSize.Y
		local total = headerPart
		if contentHeight > 0 then
			total += CONTENT_GAP + contentHeight
		end
		container.Size = UDim2.new(1, 0, 0, total)
	end

	local function applyCollapsedState(instant)
		if not collapsible then return end
		content.Visible = not collapsed
		if collapseArrow then
			collapseArrow.Text = collapsed and ">" or "v"
		end
		updateSectionSize()
	end

	cleanup:AddConnection(cl:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		updateSectionSize()
	end))
	cleanup:AddConnection(tab.Content:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		updateSectionSize()
	end))

	if collapseButton then
		AddInteractiveFeedback(collapseButton, cleanup, { Hover = false, ActivateSound = true })
		cleanup:AddConnection(collapseButton.Activated:Connect(function()
			collapsed = not collapsed
			section.Collapsed = collapsed
			applyCollapsedState(false)
		end))
	end

	applyCollapsedState(true)

	local section = {
		Container = container,
		Content = content,
		Cleanup = cleanup,
		Collapsible = collapsible,
		Collapsed = collapsed,
	}

	function section:SetCollapsed(value)
		if cleanup:IsDestroyed() or not collapsible then return end
		collapsed = value == true
		section.Collapsed = collapsed
		applyCollapsedState(true)
	end

	function section:Toggle()
		if cleanup:IsDestroyed() or not collapsible then return end
		section:SetCollapsed(not collapsed)
	end

	function section:Expand()
		self:SetCollapsed(false)
	end

	function section:Collapse()
		self:SetCollapsed(true)
	end

	function section:IsCollapsed()
		return collapsed
	end

	function section:RefreshTheme()
		if cleanup:IsDestroyed() then return end
		title.Font = Theme.FontBold
		title.TextColor3 = Theme.Text
		if descLabel then
			descLabel.Font = Theme.Font
			descLabel.TextColor3 = Theme.SecondaryText
		end
		if collapseArrow then
			collapseArrow.Font = Theme.FontBold
			collapseArrow.TextColor3 = Theme.SecondaryText
			collapseArrow.Text = collapsed and ">" or "v"
		end
	end

	function section:Destroy()
		cleanup:Destroy()
	end

	table.insert(tab.Sections, section)
	return section
end

local function CreateButton(tab, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local enabled = true
	local parent = GetParentForComponent(tab)

	local frame = Instance.new("TextButton")
	frame.Name = "Button_" .. (config.Name or "Untitled")
	frame.BackgroundColor3 = Theme.Secondary
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, Theme.ElementHeight)
	frame.AutoButtonColor = false
	frame.Text = ""
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.CornerRadius)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	stroke.Parent = frame

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 16)
	title.AnchorPoint = Vector2.new(0, 0.5)
	title.Position = UDim2.new(0, 0, 0.5, config.Description and -7 or 0)
	title.Font = Theme.Font
	title.TextSize = 13
	title.TextColor3 = Theme.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.Text = config.Name or "Button"
	title.Parent = frame

	local titlePadding = Instance.new("UIPadding")
	titlePadding.PaddingLeft = UDim.new(0, 12)
	titlePadding.PaddingRight = UDim.new(0, 12)
	titlePadding.Parent = title

	local desc
	if config.Description then
		desc = Instance.new("TextLabel")
		desc.BackgroundTransparency = 1
		desc.Size = UDim2.new(1, 0, 0, 14)
		desc.AnchorPoint = Vector2.new(0, 0.5)
		desc.Position = UDim2.new(0, 0, 0.5, 8)
		desc.Font = Theme.Font
		desc.TextSize = 11
		desc.TextColor3 = Theme.SecondaryText
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.TextYAlignment = Enum.TextYAlignment.Center
		desc.Text = config.Description
		desc.Parent = frame
		local descPadding = Instance.new("UIPadding")
		descPadding.PaddingLeft = UDim.new(0, 12)
		descPadding.PaddingRight = UDim.new(0, 12)
		descPadding.Parent = desc
	end

	local function applyImageStyle()
		if IsImageThemeActive() then
			frame.BackgroundTransparency = 0.82
			stroke.Color = GetOutlineColor()
			stroke.Thickness = 1.5
			stroke.Transparency = 0.15
		else
			frame.BackgroundTransparency = enabled and 0.1 or 0.5
			stroke.Color = Theme.Border
			stroke.Thickness = 1
			stroke.Transparency = 0.5
		end
	end
	applyImageStyle()

	AddInteractiveFeedback(frame, cleanup, { Disabled = function() return not enabled end })

	cleanup:AddConnection(frame.MouseEnter:Connect(function()
		if not enabled then return end
		if IsImageThemeActive() then
			TweenEngine.Play(frame, { BackgroundTransparency = 0.65 }, { Duration = Theme.HoverSpeed, Easing = "QuadOut" })
			TweenEngine.Play(stroke, { Transparency = 0.05 }, { Duration = Theme.HoverSpeed })
		else
			TweenEngine.Play(frame, { BackgroundColor3 = Theme.Hover }, { Duration = Theme.HoverSpeed, Easing = "QuadOut" })
		end
	end))
	cleanup:AddConnection(frame.MouseLeave:Connect(function()
		if not enabled then return end
		if IsImageThemeActive() then
			TweenEngine.Play(frame, { BackgroundTransparency = 0.82 }, { Duration = Theme.HoverSpeed, Easing = "QuadOut" })
			TweenEngine.Play(stroke, { Transparency = 0.15 }, { Duration = Theme.HoverSpeed })
		else
			TweenEngine.Play(frame, { BackgroundColor3 = Theme.Secondary }, { Duration = Theme.HoverSpeed, Easing = "QuadOut" })
		end
	end))
	cleanup:AddConnection(frame.MouseButton1Down:Connect(function()
		if not enabled then return end
		if IsImageThemeActive() then
			TweenEngine.Play(frame, { BackgroundTransparency = 0.55 }, { Duration = 0.08 })
		else
			TweenEngine.Play(frame, { BackgroundColor3 = Theme.Tertiary }, { Duration = 0.08 })
		end
	end))
	cleanup:AddConnection(frame.MouseButton1Up:Connect(function()
		if not enabled then return end
		if IsImageThemeActive() then
			TweenEngine.Play(frame, { BackgroundTransparency = 0.65 }, { Duration = 0.1 })
		else
			TweenEngine.Play(frame, { BackgroundColor3 = Theme.Hover }, { Duration = 0.1 })
		end
	end))

	cleanup:AddConnection(frame.Activated:Connect(function()
		if not enabled then return end

		local code = config.Script or config.Code
		if type(code) == "string" and #code > 0 then
			local ok, err = pcall(function()
				local fn = loadstring(code)
				if fn then
					fn()
				else
					warn("[VeyraUI] loadstring returned nil for button script")
				end
			end)
			if not ok then
				warn("[VeyraUI] Button script error:", err)
			end
		end

		if config.Callback then
			task.spawn(config.Callback)
		end
	end))

	cleanup:AddInstance(frame)

	local btn = { Frame = frame, Cleanup = cleanup }

	function btn:RefreshTheme()
		if cleanup:IsDestroyed() then return end
		frame.BackgroundColor3 = Theme.Secondary
		title.Font = Theme.Font
		title.TextColor3 = enabled and Theme.Text or Theme.MutedText
		if desc then
			desc.Font = Theme.Font
			desc.TextColor3 = enabled and Theme.SecondaryText or Theme.MutedText
		end
		applyImageStyle()
	end

	function btn:SetEnabled(state)
		enabled = state
		if not IsImageThemeActive() then
			frame.BackgroundTransparency = state and 0.1 or 0.5
		end
		title.TextColor3 = state and Theme.Text or Theme.MutedText
		if desc then desc.TextColor3 = state and Theme.SecondaryText or Theme.MutedText end
		applyImageStyle()
	end

	function btn:SetCallback(fn)
		config.Callback = fn
	end

	function btn:Destroy()
		cleanup:Destroy()
	end

	table.insert(tab.Components, btn)
	return btn
end

local function CreateToggle(tab, config)
	config = config or {}
	local cleanup = CreateCleanup()

	-- true/false OR "yes"/"no"
	local function parseYesNo(v, fallback)
		if v == nil then return fallback end
		if type(v) == "boolean" then return v end
		local s = string.lower(tostring(v))
		if s == "yes" or s == "y" or s == "on" or s == "true" or s == "1" then return true end
		if s == "no" or s == "n" or s == "off" or s == "false" or s == "0" then return false end
		return fallback
	end

	local value = parseYesNo(config.Default, false)
	local enabled = true
	local parent = GetParentForComponent(tab)

	-- Status = "yes" / "no" (optional). If set → switch LEFT, status badge RIGHT
	local statusText = config.Status or config.status
	if statusText ~= nil then
		if type(statusText) == "boolean" then
			statusText = statusText and "yes" or "no"
		else
			statusText = tostring(statusText)
		end
	end
	local hasStatus = statusText ~= nil and statusText ~= ""

	local frame = Instance.new("Frame")
	frame.Name = "Toggle_" .. (config.Name or "Untitled")
	frame.BackgroundColor3 = Theme.Secondary
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, Theme.ElementHeight)
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, math.max(Theme.CornerRadius or 0, 4))
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Name = "VeyraToggleStroke"
	stroke.Color = GetOutlineColor()
	stroke.Thickness = 1.25
	stroke.Transparency = 0.35
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame

	local function applyToggleImageStyle()
		local outline = GetOutlineColor()
		if IsImageThemeActive() then
			frame.BackgroundTransparency = 0.82
			stroke.Color = outline
			stroke.Thickness = 1.5
			stroke.Transparency = 0.15
		else
			frame.BackgroundTransparency = enabled and 0.15 or 0.5
			stroke.Color = outline
			stroke.Thickness = 1.25
			stroke.Transparency = 0.35
		end
	end
	applyToggleImageStyle()

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 16)
	title.AnchorPoint = Vector2.new(0, 0.5)
	title.Position = UDim2.new(0, 0, 0.5, config.Description and -7 or 0)
	title.Font = Theme.Font
	title.TextSize = 13
	title.TextColor3 = Theme.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.Text = config.Name or "Toggle"
	title.Parent = frame

	local titlePadding = Instance.new("UIPadding")
	if hasStatus then
		titlePadding.PaddingLeft = UDim.new(0, 56)
		titlePadding.PaddingRight = UDim.new(0, 72)
	else
		titlePadding.PaddingLeft = UDim.new(0, 12)
		titlePadding.PaddingRight = UDim.new(0, 64)
	end
	titlePadding.Parent = title

	local descLabel = nil
	if config.Description then
		descLabel = Instance.new("TextLabel")
		descLabel.BackgroundTransparency = 1
		descLabel.Size = UDim2.new(1, 0, 0, 14)
		descLabel.AnchorPoint = Vector2.new(0, 0.5)
		descLabel.Position = UDim2.new(0, 0, 0.5, 8)
		descLabel.Font = Theme.Font
		descLabel.TextSize = 11
		descLabel.TextColor3 = Theme.SecondaryText
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextYAlignment = Enum.TextYAlignment.Center
		descLabel.Text = config.Description
		descLabel.Parent = frame
		local descPadding = Instance.new("UIPadding")
		if hasStatus then
			descPadding.PaddingLeft = UDim.new(0, 56)
			descPadding.PaddingRight = UDim.new(0, 72)
		else
			descPadding.PaddingLeft = UDim.new(0, 12)
			descPadding.PaddingRight = UDim.new(0, 64)
		end
		descPadding.Parent = descLabel
	end

	local switch = Instance.new("Frame")
	switch.BackgroundColor3 = value and Theme.ToggleOn or Theme.ToggleOff
	switch.BorderSizePixel = 0
	switch.Size = UDim2.new(0, 40, 0, 22)
	if hasStatus then
		switch.Position = UDim2.new(0, 12, 0.5, -11) -- LEFT
	else
		switch.Position = UDim2.new(1, -52, 0.5, -11) -- RIGHT (default)
	end
	switch.Parent = frame

	local sc = Instance.new("UICorner")
	sc.CornerRadius = UDim.new(1, 0)
	sc.Parent = switch

	local switchStroke = Instance.new("UIStroke")
	switchStroke.Color = GetOutlineColor()
	switchStroke.Thickness = 1.25
	switchStroke.Transparency = value and 0.15 or 0.45
	switchStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	switchStroke.Parent = switch

	local knob = Instance.new("Frame")
	knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	knob.BorderSizePixel = 0
	knob.Size = UDim2.new(0, 16, 0, 16)
	knob.Position = value and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
	knob.Parent = switch

	local kc = Instance.new("UICorner")
	kc.CornerRadius = UDim.new(1, 0)
	kc.Parent = knob

	local statusBadge, statusLabel
	if hasStatus then
		statusBadge = Instance.new("Frame")
		statusBadge.Name = "Status"
		statusBadge.BackgroundColor3 = Theme.Tertiary
		statusBadge.BackgroundTransparency = 0.15
		statusBadge.BorderSizePixel = 0
		statusBadge.Size = UDim2.new(0, 56, 0, 22)
		statusBadge.Position = UDim2.new(1, -64, 0.5, -11)
		statusBadge.Parent = frame

		local sbCorner = Instance.new("UICorner")
		sbCorner.CornerRadius = UDim.new(0, 6)
		sbCorner.Parent = statusBadge

		local sbStroke = Instance.new("UIStroke")
		sbStroke.Color = GetOutlineColor()
		sbStroke.Thickness = 1
		sbStroke.Transparency = 0.4
		sbStroke.Parent = statusBadge

		statusLabel = Instance.new("TextLabel")
		statusLabel.BackgroundTransparency = 1
		statusLabel.Size = UDim2.new(1, 0, 1, 0)
		statusLabel.Font = Theme.FontBold
		statusLabel.TextSize = 11
		statusLabel.TextColor3 = Theme.Text
		statusLabel.TextXAlignment = Enum.TextXAlignment.Center
		statusLabel.TextYAlignment = Enum.TextYAlignment.Center
		statusLabel.Text = statusText
		statusLabel.Parent = statusBadge
	end

	local function updateVisual(animate)
		local targetColor = value and Theme.ToggleOn or Theme.ToggleOff
		local targetPos = value and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
		local st = value and 0.15 or 0.45
		if animate then
			TweenEngine.Play(switch, { BackgroundColor3 = targetColor }, { Duration = 0.2, Easing = "QuadOut" })
			TweenEngine.Play(knob, { Position = targetPos }, { Duration = 0.25, Easing = "BackOut" })
			TweenEngine.Play(switchStroke, { Transparency = st }, { Duration = 0.2, Easing = "QuadOut" })
		else
			switch.BackgroundColor3 = targetColor
			knob.Position = targetPos
			switchStroke.Transparency = st
		end
	end

	local hit = Instance.new("TextButton")
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.new(1, 0, 1, 0)
	hit.Text = ""
	hit.ZIndex = 5
	hit.Parent = frame

	local changed = CreateSignal()

	AddInteractiveFeedback(frame, cleanup, { Disabled = function() return not enabled end, ActivateSound = false })
	AddInteractiveFeedback(hit, cleanup, { Hover = false, ActivateSound = false, Disabled = function() return not enabled end })

	cleanup:AddConnection(hit.Activated:Connect(function()
		if not enabled then return end
		value = not value
		PlayUIToggleSound()
		updateVisual(true)
		changed:Fire(value)
		if config.Callback then task.spawn(config.Callback, value) end
	end))

	cleanup:AddInstance(frame)
	updateVisual(false)

	local toggle = { Frame = frame, Cleanup = cleanup, Changed = changed }

	function toggle:SetStatus(text)
		if not statusLabel then return end
		if type(text) == "boolean" then
			text = text and "yes" or "no"
		end
		statusLabel.Text = tostring(text or "")
	end

	function toggle:GetStatus()
		return statusLabel and statusLabel.Text or nil
	end

	function toggle:RefreshTheme()
		if cleanup:IsDestroyed() then return end
		frame.BackgroundColor3 = Theme.Secondary
		title.Font = Theme.Font
		title.TextColor3 = Theme.Text
		if descLabel then
			descLabel.Font = Theme.Font
			descLabel.TextColor3 = Theme.SecondaryText
		end
		updateVisual(false)
		applyToggleImageStyle()
		stroke.Color = GetOutlineColor()
		switchStroke.Color = GetOutlineColor()
		if statusBadge then
			statusBadge.BackgroundColor3 = Theme.Tertiary
			local s = statusBadge:FindFirstChildOfClass("UIStroke")
			if s then s.Color = GetOutlineColor() end
		end
		if statusLabel then
			statusLabel.Font = Theme.FontBold
			statusLabel.TextColor3 = Theme.Text
		end
	end

	function toggle:Set(v, suppress)
		v = parseYesNo(v, value)
		if value == v then return end
		value = v
		updateVisual(true)
		if not suppress then
			changed:Fire(value)
			if config.Callback then task.spawn(config.Callback, value) end
		end
	end

	function toggle:Get()
		return value
	end

	function toggle:SetEnabled(state)
		enabled = state and true or false
		applyToggleImageStyle()
	end

	function toggle:Destroy()
		changed:Destroy()
		cleanup:Destroy()
	end

	function toggle:IsDestroyed()
		return cleanup:IsDestroyed()
	end

	if config.Flag then
		RegisterConfigElement(config.Flag, "Toggle", function() return toggle:Get() end, function(v) toggle:Set(v, true) end)
	end
	table.insert(tab.Components, toggle)
	return toggle
end

local function CreateSlider(tab, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local minv = config.Min or 0
	local maxv = config.Max or 100
	local step = config.Step or 1
	local value = config.Default or minv
	local enabled = true
	local parent = GetParentForComponent(tab)
	local dragging = false

	local frame = Instance.new("Frame")
	frame.Name = "Slider_" .. (config.Name or "Untitled")
	frame.BackgroundColor3 = Theme.Secondary
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, 52)
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.CornerRadius)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	stroke.Parent = frame

	local function applySliderImageStyle()
		if IsImageThemeActive() then
			frame.BackgroundTransparency = 0.82
			stroke.Color = GetOutlineColor()
			stroke.Thickness = 1.5
			stroke.Transparency = 0.15
		else
			frame.BackgroundTransparency = 0.15
			stroke.Color = Theme.Border
			stroke.Thickness = 1
			stroke.Transparency = 0.5
		end
	end
	applySliderImageStyle()

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(0.7, 0, 0, 16)
	title.Position = UDim2.new(0, 12, 0, 8)
	title.Font = Theme.Font
	title.TextSize = 13
	title.TextColor3 = Theme.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = config.Name or "Slider"
	title.Parent = frame

	local valueLabel = Instance.new("TextLabel")
	valueLabel.BackgroundTransparency = 1
	valueLabel.Size = UDim2.new(0.3, -12, 0, 16)
	valueLabel.Position = UDim2.new(0.7, 0, 0, 8)
	valueLabel.Font = Theme.FontMono
	valueLabel.TextSize = 12
	valueLabel.TextColor3 = Theme.SecondaryText
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.Text = tostring(value)
	valueLabel.Parent = frame

	local track = Instance.new("Frame")
	track.BackgroundColor3 = Theme.SliderTrack
	track.BorderSizePixel = 0
	track.Size = UDim2.new(1, -24, 0, 4)
	track.Position = UDim2.new(0, 12, 1, -16)
	track.Parent = frame

	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(1, 0)
	tc.Parent = track

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Theme.SliderFill
	fill.BorderSizePixel = 0
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.Parent = track

	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(1, 0)
	fc.Parent = fill

	local knob = Instance.new("Frame")
	knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	knob.BorderSizePixel = 0
	knob.Size = UDim2.new(0, 12, 0, 12)
	knob.Position = UDim2.new(0, -6, 0.5, -6)
	knob.ZIndex = 2
	knob.Parent = track

	local kc = Instance.new("UICorner")
	kc.CornerRadius = UDim.new(1, 0)
	kc.Parent = knob

	local function snap(v)
		local s = math.floor((v - minv) / step + 0.5) * step + minv
		return math.clamp(s, minv, maxv)
	end

	local function setVisual(v, animate)
		local alpha = math.clamp((v - minv) / (maxv - minv), 0, 1)
		local ts = UDim2.new(alpha, 0, 1, 0)
		local tp = UDim2.new(alpha, -6, 0.5, -6)
		if animate then
			TweenEngine.Play(fill, { Size = ts }, { Duration = 0.15, Easing = "QuadOut" })
			TweenEngine.Play(knob, { Position = tp }, { Duration = 0.15, Easing = "QuadOut" })
		else
			fill.Size = ts
			knob.Position = tp
		end
		valueLabel.Text = tostring(math.floor(v * 100 + 0.5) / 100)
	end

	local changed = CreateSignal()

	local function updateFromInput(pos)
		local rel = math.clamp((pos.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		local raw = minv + rel * (maxv - minv)
		local newVal = snap(raw)
		if newVal ~= value then
			value = newVal
			setVisual(newVal, false)
			if changed then changed:Fire(newVal) end
			if config.Callback then task.spawn(config.Callback, newVal) end
		else
			setVisual(newVal, false)
		end
	end

	local hit = Instance.new("TextButton")
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.new(1, 0, 0, 20)
	hit.Position = UDim2.new(0, 0, 1, -24)
	hit.Text = ""
	hit.Parent = frame

	local moveConn, endConn = nil, nil
	local function clearSliderDrag()
		if moveConn then
			pcall(function() moveConn:Disconnect() end)
			moveConn = nil
		end
		if endConn then
			pcall(function() endConn:Disconnect() end)
			endConn = nil
		end
		dragging = false
	end

	cleanup:AddConnection(hit.InputBegan:Connect(function(input)
		if not enabled then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			clearSliderDrag()
			dragging = true
			updateFromInput(input.Position)

			moveConn = UserInputService.InputChanged:Connect(function(inp)
				if not dragging then return end
				if inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch then
					updateFromInput(inp.Position)
				end
			end)
			endConn = UserInputService.InputEnded:Connect(function(inp)
				if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
					clearSliderDrag()
				end
			end)
		end
	end))

	cleanup:AddCallback(clearSliderDrag)

	cleanup:AddInstance(frame)
	setVisual(value, false)

	local slider = { Frame = frame, Cleanup = cleanup, Changed = changed }

	function slider:RefreshTheme()
		if cleanup:IsDestroyed() then return end
		frame.BackgroundColor3 = Theme.Secondary
		title.Font = Theme.Font
		title.TextColor3 = Theme.Text
		valueLabel.Font = Theme.FontMono
		valueLabel.TextColor3 = Theme.SecondaryText
		track.BackgroundColor3 = Theme.SliderTrack
		fill.BackgroundColor3 = Theme.SliderFill
		applySliderImageStyle()
	end

	function slider:Set(v, suppress)
		v = snap(math.clamp(v, minv, maxv))
		if value == v then return end
		value = v
		setVisual(v, true)
		if not suppress then
			changed:Fire(v)
			if config.Callback then task.spawn(config.Callback, v) end
		end
	end

	function slider:Get()
		return value
	end

	function slider:Destroy()
		changed:Destroy()
		cleanup:Destroy()
	end

	function slider:IsDestroyed()
		return cleanup:IsDestroyed()
	end

	if config.Flag then
		RegisterConfigElement(config.Flag, "Slider", function() return slider:Get() end, function(v) slider:Set(v, true) end)
	end
	table.insert(tab.Components, slider)
	return slider
end

local function CreateLabel(tab, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local parent = GetParentForComponent(tab)

	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, config.Description and 36 or 20)
	frame.Parent = parent

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 16)
	title.Font = Theme.Font
	title.TextSize = 13
	title.TextColor3 = Theme.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = config.Name or "Label"
	title.Parent = frame

	local desc
	if config.Description then
		desc = Instance.new("TextLabel")
		desc.BackgroundTransparency = 1
		desc.Size = UDim2.new(1, 0, 0, 14)
		desc.Position = UDim2.new(0, 0, 0, 18)
		desc.Font = Theme.Font
		desc.TextSize = 11
		desc.TextColor3 = Theme.SecondaryText
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.Text = config.Description
		desc.Parent = frame
	end

	cleanup:AddInstance(frame)

	local label = { Frame = frame, TitleLabel = title, DescLabel = desc, Cleanup = cleanup }

	function label:RefreshTheme()
		if cleanup:IsDestroyed() then return end
		title.Font = Theme.Font
		title.TextColor3 = Theme.Text
		if desc then
			desc.Font = Theme.Font
			desc.TextColor3 = Theme.SecondaryText
		end
	end

	function label:SetTitle(t) title.Text = t end
	function label:SetDescription(t) if desc then desc.Text = t end end
	function label:Destroy() cleanup:Destroy() end

	table.insert(tab.Components, label)
	return label
end

local function CreateDropdown(tab, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local options = config.Options or {}
	local multiSelect = config.MultiSelect == true
	local value = config.Default
	if multiSelect then
		if type(value) ~= "table" then value = {} end
	else
		if value == nil then value = options[1] or "" end
	end
	local open = false
	local transitioning = false
	local destroyed = false
	local parent = GetParentForComponent(tab)
	local outsideConn = nil
	local closedHeight = Theme.ElementHeight
	local listGap = 4
	local optionH = 28

	local changed = CreateSignal()
	local dd = { Frame = nil, Cleanup = cleanup, Changed = changed }

	local frame = Instance.new("Frame")
	frame.Name = "Dropdown_" .. (config.Name or "Untitled")
	frame.BackgroundColor3 = Theme.Secondary
	frame.BackgroundTransparency = 0.05
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, closedHeight)
	frame.ClipsDescendants = true
	frame.Parent = parent
	dd.Frame = frame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.CornerRadius)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.OutlineAccent or Theme.Border
	stroke.Thickness = 1.5
	stroke.Transparency = 0.3
	stroke.Parent = frame

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, closedHeight)
	header.Position = UDim2.new(0, 0, 0, 0)
	header.ZIndex = 2
	header.Parent = frame

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -40, 1, 0)
	title.Position = UDim2.new(0, 12, 0, 0)
	title.Font = Theme.Font
	title.TextSize = 13
	title.TextColor3 = Theme.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = (config.Name or "Dropdown") .. ": " .. tostring(value)
	title.Parent = header

	local arrow = Instance.new("TextLabel")
	arrow.BackgroundTransparency = 1
	arrow.Size = UDim2.new(0, 20, 1, 0)
	arrow.Position = UDim2.new(1, -28, 0, 0)
	arrow.Font = Enum.Font.GothamBold
	arrow.TextSize = 12
	arrow.TextColor3 = Theme.SecondaryText
	arrow.Text = "▼"
	arrow.Parent = header

	local list = Instance.new("Frame")
	list.Name = "List"
	list.BackgroundColor3 = Theme.Secondary
	list.BackgroundTransparency = 0.02
	list.BorderSizePixel = 0
	list.Size = UDim2.new(1, 0, 0, 0)
	list.Position = UDim2.new(0, 0, 0, closedHeight)
	list.Visible = true
	list.ZIndex = 3
	list.ClipsDescendants = true
	list.Parent = frame

	local ls = Instance.new("UIStroke")
	ls.Color = Theme.OutlineAccent or Theme.Border
	ls.Thickness = 1.5
	ls.Transparency = 0.25
	ls.Parent = list

	local ll = Instance.new("UIListLayout")
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Padding = UDim.new(0, 0)
	ll.Parent = list

	
	
	local function getListHeight()
		return math.max(#options, 1) * optionH
	end

	local function getParentScroll()
		local p = frame.Parent
		while p do
			if p:IsA("ScrollingFrame") then
				return p
			end
			p = p.Parent
		end
		return nil
	end

	local function bumpParentCanvas(scrollIntoView)
		local scroll = getParentScroll()
		if not scroll then return end
		scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
		scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
		if not scrollIntoView then return end
		
		task.defer(function()
			if destroyed or not open or not frame.Parent then return end
			local absY = frame.AbsolutePosition.Y
			local absH = frame.AbsoluteSize.Y
			local scrollAbsY = scroll.AbsolutePosition.Y
			local scrollAbsH = scroll.AbsoluteSize.Y
			local canvasY = scroll.CanvasPosition.Y
			local bottomInView = (absY - scrollAbsY) + absH
			if bottomInView > scrollAbsH then
				local overshoot = bottomInView - scrollAbsH + 12
				scroll.CanvasPosition = Vector2.new(
					scroll.CanvasPosition.X,
					math.max(0, canvasY + overshoot)
				)
			end
		end)
	end

	local function forceClose(instant)
		if destroyed then return end
		open = false
		if outsideConn then
			outsideConn:Disconnect()
			outsideConn = nil
		end
		TweenEngine.CancelOnObject(list)
		TweenEngine.CancelOnObject(frame)
		arrow.Text = "▼"
		if instant then
			list.Size = UDim2.new(1, 0, 0, 0)
			frame.Size = UDim2.new(1, 0, 0, closedHeight)
			frame.ClipsDescendants = true
			frame.ZIndex = 1
			transitioning = false
			bumpParentCanvas()
		else
			transitioning = true
			TweenEngine.Play(list, { Size = UDim2.new(1, 0, 0, 0) }, {
				Duration = 0.18, Easing = "QuadIn",
			})
			TweenEngine.Play(frame, { Size = UDim2.new(1, 0, 0, closedHeight) }, {
				Duration = 0.2, Easing = "QuadIn",
				OnComplete = function()
					if not destroyed then
						frame.ClipsDescendants = true
						frame.ZIndex = 1
						transitioning = false
						bumpParentCanvas()
					end
				end,
			})
		end
	end

	local function openList()
		if destroyed or transitioning or open then return end
		if #options == 0 then return end
		if tab and tab.Components then
			for _, c in ipairs(tab.Components) do
				if c ~= dd and c.Close then pcall(function() c:Close() end) end
			end
		end
		transitioning = true
		open = true
		local height = getListHeight()
		local totalH = closedHeight + height

		frame.AnchorPoint = Vector2.new(0, 0)
		frame.ClipsDescendants = true
		frame.ZIndex = 30

		frame.Size = UDim2.new(1, 0, 0, closedHeight)

		list.Parent = frame
		list.AnchorPoint = Vector2.new(0, 0)
		list.Position = UDim2.new(0, 0, 0, closedHeight)
		list.Size = UDim2.new(1, 0, 0, 0)
		list.Visible = true
		list.BackgroundTransparency = 0.02
		list.BackgroundColor3 = Theme.Secondary
		list.ZIndex = 31
		list.ClipsDescendants = true

		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("TextButton") then
				child.Visible = true
				child.ZIndex = 32
				child.BackgroundTransparency = 0
				child.BackgroundColor3 = Theme.Secondary
				child.TextTransparency = 0
			end
		end

		TweenEngine.CancelOnObject(list)
		TweenEngine.CancelOnObject(frame)

		TweenEngine.Play(frame, {
			Size = UDim2.new(1, 0, 0, totalH),
		}, { Duration = 0.28, Easing = "QuadOut" })
		TweenEngine.Play(list, {
			Size = UDim2.new(1, 0, 0, height),
		}, {
			Duration = 0.28,
			Easing = "QuadOut",
			OnComplete = function()
				transitioning = false
				bumpParentCanvas(true)
			end,
		})
		arrow.Text = "▲"
		task.defer(function()
			bumpParentCanvas(true)
		end)

		task.defer(function()
			if destroyed or not open then return end
			outsideConn = UserInputService.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1
					and input.UserInputType ~= Enum.UserInputType.Touch then
					return
				end
				local pos = input.Position
				local absPos = frame.AbsolutePosition
				local absSize = frame.AbsoluteSize
				if pos.X < absPos.X or pos.X > absPos.X + absSize.X
					or pos.Y < absPos.Y or pos.Y > absPos.Y + absSize.Y then
					forceClose(false)
				end
			end)
			cleanup:AddConnection(outsideConn)
		end)
	end

	for i, opt in ipairs(options) do
		local btn = Instance.new("TextButton")
		btn.Name = "Opt_" .. tostring(i)
		btn.BackgroundColor3 = Theme.Secondary
		btn.BackgroundTransparency = 0
		btn.BorderSizePixel = 0
		btn.Size = UDim2.new(1, 0, 0, optionH)
		btn.Font = Theme.Font
		btn.TextSize = 13
		btn.TextColor3 = Theme.Text
		btn.TextTransparency = 0
		btn.Text = tostring(opt)
		btn.TextXAlignment = Enum.TextXAlignment.Left
		btn.AutoButtonColor = false
		btn.Visible = true
		btn.ZIndex = 4
		btn.LayoutOrder = i
		btn.Parent = list

		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 12)
		pad.Parent = btn

		AddInteractiveFeedback(btn, cleanup)

		btn.MouseEnter:Connect(function()
			if destroyed then return end
			TweenEngine.Play(btn, { BackgroundColor3 = Theme.Hover }, { Duration = 0.1 })
		end)
		btn.MouseLeave:Connect(function()
			if destroyed then return end
			TweenEngine.Play(btn, { BackgroundColor3 = Theme.Secondary }, { Duration = 0.1 })
		end)
		cleanup:AddConnection(btn.Activated:Connect(function()
			if destroyed or transitioning then return end
			value = opt
			title.Text = (config.Name or "Dropdown") .. ": " .. tostring(opt)
			changed:Fire(opt)
			if config.Callback then task.spawn(config.Callback, opt) end
			forceClose(false)
		end))
	end

	AddInteractiveFeedback(frame, cleanup)

	local hit = Instance.new("TextButton")
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.new(1, 0, 1, 0)
	hit.Text = ""
	hit.ZIndex = 5
	hit.Parent = header

	AddInteractiveFeedback(hit, cleanup, { Hover = false, ActivateSound = true })

	cleanup:AddConnection(hit.Activated:Connect(function()
		if destroyed or transitioning then return end
		if open then
			forceClose(false)
		else
			openList()
		end
	end))

	cleanup:AddInstance(frame)

	function dd:RefreshTheme()
		if destroyed or cleanup:IsDestroyed() then return end
		frame.BackgroundColor3 = Theme.Secondary
		frame.BackgroundTransparency = 0.05
		stroke.Color = Theme.OutlineAccent or Theme.Border
		stroke.Transparency = 0.3
		title.Font = Theme.Font
		title.TextColor3 = Theme.Text
		arrow.TextColor3 = Theme.SecondaryText
		list.BackgroundColor3 = Theme.Secondary
		list.BackgroundTransparency = 0.02
		ls.Color = Theme.OutlineAccent or Theme.Border
		ls.Transparency = 0.25
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("TextButton") then
				child.BackgroundColor3 = Theme.Secondary
				child.Font = Theme.Font
				child.TextColor3 = Theme.Text
			end
		end
	end

	function dd:Set(v, suppress)
		if destroyed then return end
		if value == v then return end
		value = v
		title.Text = (config.Name or "Dropdown") .. ": " .. tostring(v)
		if not suppress then
			changed:Fire(v)
			if config.Callback then task.spawn(config.Callback, v) end
		end
	end

	function dd:Get()
		return value
	end

	function dd:Close()
		forceClose(true)
	end

	function dd:SetOptions(newOptions, keepValue)
		if destroyed then return end
		options = newOptions or {}
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		for i, opt in ipairs(options) do
			local btn = Instance.new("TextButton")
			btn.Name = "Opt_" .. tostring(i)
			btn.BackgroundColor3 = Theme.Secondary
			btn.BackgroundTransparency = 0
			btn.BorderSizePixel = 0
			btn.Size = UDim2.new(1, 0, 0, optionH)
			btn.Font = Theme.Font
			btn.TextSize = 13
			btn.TextColor3 = Theme.Text
			btn.Text = tostring(opt)
			btn.TextXAlignment = Enum.TextXAlignment.Left
			btn.AutoButtonColor = false
			btn.ZIndex = 4
			btn.LayoutOrder = i
			btn.Parent = list
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, 12)
			pad.Parent = btn
			AddInteractiveFeedback(btn, cleanup)
			btn.MouseEnter:Connect(function()
				if destroyed then return end
				TweenEngine.Play(btn, { BackgroundColor3 = Theme.Hover }, { Duration = 0.1 })
			end)
			btn.MouseLeave:Connect(function()
				if destroyed then return end
				TweenEngine.Play(btn, { BackgroundColor3 = Theme.Secondary }, { Duration = 0.1 })
			end)
			cleanup:AddConnection(btn.Activated:Connect(function()
				if destroyed or transitioning then return end
				value = opt
				title.Text = (config.Name or "Dropdown") .. ": " .. tostring(opt)
				changed:Fire(opt)
				if config.Callback then task.spawn(config.Callback, opt) end
				forceClose(false)
			end))
		end
		if not keepValue or not table.find(options, value) then
			value = options[1] or ""
		end
		title.Text = (config.Name or "Dropdown") .. ": " .. tostring(value)
		if open then forceClose(true) end
	end

	function dd:Destroy()
		if destroyed then return end
		destroyed = true
		forceClose(true)
		TweenEngine.CancelOnObject(frame)
		TweenEngine.CancelOnObject(list)
		changed:Destroy()
		cleanup:Destroy()
	end

	function dd:IsDestroyed()
		return destroyed or cleanup:IsDestroyed()
	end

	table.insert(tab.Components, dd)
	return dd
end

local function CreateTextbox(tab, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local parent = GetParentForComponent(tab)

	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Theme.Secondary
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, Theme.ElementHeight)
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.CornerRadius)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	stroke.Parent = frame

	local box = Instance.new("TextBox")
	box.BackgroundTransparency = 1
	box.Size = UDim2.new(1, -24, 1, 0)
	box.Position = UDim2.new(0, 12, 0, 0)
	box.Font = Theme.FontMono
	box.TextSize = 13
	box.TextColor3 = Theme.Text
	box.PlaceholderColor3 = Theme.MutedText
	box.PlaceholderText = config.Placeholder or "Enter text..."
	box.Text = config.Default or ""
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Parent = frame

	if config.MaxLength then
		box:GetPropertyChangedSignal("Text"):Connect(function()
			if #box.Text > config.MaxLength then
				box.Text = string.sub(box.Text, 1, config.MaxLength)
			end
		end)
	end

	local changed = CreateSignal()

	cleanup:AddConnection(box.Focused:Connect(function()
		TweenEngine.Play(stroke, { Color = Theme.Accent, Transparency = 0.2 }, { Duration = 0.15 })
	end))
	cleanup:AddConnection(box.FocusLost:Connect(function(enter)
		TweenEngine.Play(stroke, { Color = Theme.Border, Transparency = 0.5 }, { Duration = 0.15 })
		changed:Fire(box.Text)
		if config.Callback then task.spawn(config.Callback, box.Text, enter) end
	end))

	cleanup:AddInstance(frame)

	local tb = { Frame = frame, Box = box, Cleanup = cleanup, Changed = changed }

	function tb:RefreshTheme()
		if cleanup:IsDestroyed() then return end
		frame.BackgroundColor3 = Theme.Secondary
		stroke.Color = Theme.Border
		box.Font = Theme.FontMono
		box.TextColor3 = Theme.Text
		box.PlaceholderColor3 = Theme.MutedText
	end

	function tb:Set(t, suppress)
		box.Text = t or ""
		if not suppress then
			changed:Fire(box.Text)
		end
	end
	function tb:Get() return box.Text end
	function tb:Clear()
		box.Text = ""
		changed:Fire("")
	end
	function tb:Destroy()
		changed:Destroy()
		cleanup:Destroy()
	end
	function tb:IsDestroyed()
		return cleanup:IsDestroyed()
	end

	table.insert(tab.Components, tb)
	return tb
end

local function CreateKeybind(tab, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local key = config.Default or Enum.KeyCode.Unknown
	local mode = config.Mode or "Toggle"
	local active = false
	local listening = false
	local destroyed = false
	local parent = GetParentForComponent(tab)

	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Theme.Secondary
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, Theme.ElementHeight)
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.CornerRadius)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	stroke.Parent = frame

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -80, 1, 0)
	title.Position = UDim2.new(0, 12, 0, 0)
	title.Font = Theme.Font
	title.TextSize = 13
	title.TextColor3 = Theme.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = config.Name or "Keybind"
	title.Parent = frame

	local keyLabel = Instance.new("TextLabel")
	keyLabel.BackgroundColor3 = Theme.Tertiary
	keyLabel.BorderSizePixel = 0
	keyLabel.Size = UDim2.new(0, 60, 0, 22)
	keyLabel.Position = UDim2.new(1, -72, 0.5, -11)
	keyLabel.Font = Theme.FontMono
	keyLabel.TextSize = 11
	keyLabel.TextColor3 = Theme.Text
	keyLabel.Text = (key == Enum.KeyCode.Unknown) and "None" or key.Name
	keyLabel.Parent = frame

	local kc = Instance.new("UICorner")
	kc.CornerRadius = UDim.new(0, 4)
	kc.Parent = keyLabel

	local hit = Instance.new("TextButton")
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.new(1, 0, 1, 0)
	hit.Text = ""
	hit.Parent = frame

	local function stopListening()
		if not listening then return end
		listening = false
		keyLabel.Text = (key == Enum.KeyCode.Unknown) and "None" or key.Name
		TweenEngine.Play(stroke, { Color = Theme.Border }, { Duration = 0.15 })
	end

	AddInteractiveFeedback(frame, cleanup)
	AddInteractiveFeedback(hit, cleanup, { Hover = false, ActivateSound = true, Disabled = function() return destroyed end })

	cleanup:AddConnection(hit.Activated:Connect(function()
		if destroyed then return end
		if listening then
			stopListening()
			return
		end
		listening = true
		keyLabel.Text = "..."
		TweenEngine.Play(stroke, { Color = Theme.Accent }, { Duration = 0.15 })
	end))

	cleanup:AddConnection(UserInputService.InputBegan:Connect(function(input, processed)
		if destroyed then return end
		if processed then return end

		if listening then

			if input.UserInputType == Enum.UserInputType.Keyboard or input.UserInputType == Enum.UserInputType.Gamepad1 then

				if input.KeyCode == Enum.KeyCode.Escape then
					stopListening()
					return
				end
				key = input.KeyCode
				keyLabel.Text = key.Name
				listening = false
				TweenEngine.Play(stroke, { Color = Theme.Border }, { Duration = 0.15 })

				if config.Name == "Toggle UI" then
					Settings.ToggleUIKey = key.Name
				end
			end
			return
		end

		if key == Enum.KeyCode.Unknown then return end
		if input.KeyCode == key and config.Callback then
			if mode == "Hold" then
				task.spawn(config.Callback, true)
			else
				active = not active
				task.spawn(config.Callback, active)
			end
		end
	end))

	if mode == "Hold" then
		cleanup:AddConnection(UserInputService.InputEnded:Connect(function(input)
			if destroyed then return end
			if key ~= Enum.KeyCode.Unknown and input.KeyCode == key and config.Callback then
				task.spawn(config.Callback, false)
			end
		end))
	end

	cleanup:AddInstance(frame)

	local kb = { Frame = frame, Cleanup = cleanup }

	function kb:RefreshTheme()
		if destroyed or cleanup:IsDestroyed() then return end
		frame.BackgroundColor3 = Theme.Secondary
		stroke.Color = Theme.Border
		title.Font = Theme.Font
		title.TextColor3 = Theme.Text
		keyLabel.BackgroundColor3 = Theme.Tertiary
		keyLabel.Font = Theme.FontMono
		keyLabel.TextColor3 = Theme.Text
	end

	function kb:Set(k)
		if destroyed then return end
		key = k or Enum.KeyCode.Unknown
		keyLabel.Text = (key == Enum.KeyCode.Unknown) and "None" or key.Name
		if listening then stopListening() end
	end

	function kb:Clear()
		self:Set(Enum.KeyCode.Unknown)
	end

	function kb:Get()
		return key
	end

	function kb:IsListening()
		return listening
	end

	function kb:Destroy()
		if destroyed then return end
		destroyed = true
		listening = false
		active = false
		TweenEngine.CancelOnObject(frame)
		TweenEngine.CancelOnObject(stroke)
		cleanup:Destroy()
	end

	table.insert(tab.Components, kb)
	return kb
end

local function CreateDivider(tab)
	local cleanup = CreateCleanup()
	local parent = GetParentForComponent(tab)

	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 0, 0, 12)
	frame.Parent = parent

	local line = Instance.new("Frame")
	line.BackgroundColor3 = Theme.Border
	line.BackgroundTransparency = 0.5
	line.BorderSizePixel = 0
	line.Size = UDim2.new(1, 0, 0, 1)
	line.Position = UDim2.new(0, 0, 0.5, 0)
	line.Parent = frame

	cleanup:AddInstance(frame)

	local div = { Frame = frame, Cleanup = cleanup }
	function div:RefreshTheme()
		if cleanup:IsDestroyed() then return end
		line.BackgroundColor3 = Theme.Border
	end
	function div:Destroy() cleanup:Destroy() end
	table.insert(tab.Components, div)
	return div
end

local function CreateColorPicker(tab, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local parent = GetParentForComponent(tab)
	local color = config.Default or config.Color or Color3.fromRGB(255, 255, 255)
	local h, s, v = color:ToHSV()
	local open = false
	local draggingSV, draggingHue = false, false

	local frame = Instance.new("Frame")
	frame.Name = "ColorPicker_" .. (config.Name or "Untitled")
	frame.BackgroundColor3 = Theme.Secondary
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, Theme.ElementHeight)
	frame.ClipsDescendants = true
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.CornerRadius)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Border
	stroke.Thickness = 1
	stroke.Transparency = 0.5
	stroke.Parent = frame

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -70, 1, 0)
	title.Position = UDim2.new(0, 12, 0, 0)
	title.Font = Theme.Font
	title.TextSize = 13
	title.TextColor3 = Theme.Text
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = config.Name or "Color"
	title.ZIndex = 2
	title.Parent = frame

	local preview = Instance.new("Frame")
	preview.Name = "Preview"
	preview.BackgroundColor3 = color
	preview.BorderSizePixel = 0
	preview.Size = UDim2.new(0, 36, 0, 20)
	preview.Position = UDim2.new(1, -48, 0.5, -10)
	preview.ZIndex = 2
	preview.Parent = frame

	local previewCorner = Instance.new("UICorner")
	previewCorner.CornerRadius = UDim.new(0, 4)
	previewCorner.Parent = preview

	local previewStroke = Instance.new("UIStroke")
	previewStroke.Color = Theme.Border
	previewStroke.Thickness = 1
	previewStroke.Transparency = 0.3
	previewStroke.Parent = preview

	
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = Theme.Secondary
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Size = UDim2.new(1, 0, 0, 0)
	panel.Position = UDim2.new(0, 0, 0, Theme.ElementHeight)
	panel.ClipsDescendants = true
	panel.Visible = true
	panel.ZIndex = 5
	panel.Parent = frame

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Theme.OutlineAccent or Theme.Border
	panelStroke.Thickness = 1.5
	panelStroke.Transparency = 0.25
	panelStroke.Parent = panel

	local panelPad = Instance.new("UIPadding")
	panelPad.PaddingTop = UDim.new(0, 10)
	panelPad.PaddingBottom = UDim.new(0, 10)
	panelPad.PaddingLeft = UDim.new(0, 12)
	panelPad.PaddingRight = UDim.new(0, 12)
	panelPad.Parent = panel

	
	local svSize = 120
	local sv = Instance.new("Frame")
	sv.Name = "SV"
	sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
	sv.BorderSizePixel = 0
	sv.Size = UDim2.new(0, svSize, 0, svSize)
	sv.Position = UDim2.new(0, 0, 0, 0)
	sv.ZIndex = 6
	sv.Parent = panel

	local svCorner = Instance.new("UICorner")
	svCorner.CornerRadius = UDim.new(0, 6)
	svCorner.Parent = sv

	local whiteGrad = Instance.new("UIGradient")
	whiteGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
	})
	whiteGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	whiteGrad.Rotation = 0
	whiteGrad.Parent = sv

	local blackOverlay = Instance.new("Frame")
	blackOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
	blackOverlay.BackgroundTransparency = 0
	blackOverlay.BorderSizePixel = 0
	blackOverlay.Size = UDim2.new(1, 0, 1, 0)
	blackOverlay.ZIndex = 7
	blackOverlay.Parent = sv

	local blackCorner = Instance.new("UICorner")
	blackCorner.CornerRadius = UDim.new(0, 6)
	blackCorner.Parent = blackOverlay

	local blackGrad = Instance.new("UIGradient")
	blackGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	blackGrad.Rotation = 90
	blackGrad.Parent = blackOverlay

	local svCursor = Instance.new("Frame")
	svCursor.Name = "Cursor"
	svCursor.BackgroundColor3 = Color3.new(1, 1, 1)
	svCursor.BorderSizePixel = 0
	svCursor.Size = UDim2.new(0, 12, 0, 12)
	svCursor.AnchorPoint = Vector2.new(0.5, 0.5)
	svCursor.Position = UDim2.new(s, 0, 1 - v, 0)
	svCursor.ZIndex = 8
	svCursor.Parent = sv

	local svCursorCorner = Instance.new("UICorner")
	svCursorCorner.CornerRadius = UDim.new(1, 0)
	svCursorCorner.Parent = svCursor

	local svCursorStroke = Instance.new("UIStroke")
	svCursorStroke.Color = Color3.new(0, 0, 0)
	svCursorStroke.Thickness = 1.5
	svCursorStroke.Parent = svCursor

	
	local hueBar = Instance.new("Frame")
	hueBar.Name = "Hue"
	hueBar.BackgroundColor3 = Color3.new(1, 1, 1)
	hueBar.BorderSizePixel = 0
	hueBar.Size = UDim2.new(0, 18, 0, svSize)
	hueBar.Position = UDim2.new(0, svSize + 10, 0, 0)
	hueBar.ZIndex = 6
	hueBar.Parent = panel

	local hueCorner = Instance.new("UICorner")
	hueCorner.CornerRadius = UDim.new(0, 4)
	hueCorner.Parent = hueBar

	local hueGrad = Instance.new("UIGradient")
	hueGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
		ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
		ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
		ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 255)),
		ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
		ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
		ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 0, 0)),
	})
	hueGrad.Rotation = 90
	hueGrad.Parent = hueBar

	local hueCursor = Instance.new("Frame")
	hueCursor.BackgroundColor3 = Color3.new(1, 1, 1)
	hueCursor.BorderSizePixel = 0
	hueCursor.Size = UDim2.new(1, 4, 0, 4)
	hueCursor.Position = UDim2.new(0, -2, h, -2)
	hueCursor.ZIndex = 8
	hueCursor.Parent = hueBar

	local hueCursorCorner = Instance.new("UICorner")
	hueCursorCorner.CornerRadius = UDim.new(1, 0)
	hueCursorCorner.Parent = hueCursor

	local hueCursorStroke = Instance.new("UIStroke")
	hueCursorStroke.Color = Color3.new(0, 0, 0)
	hueCursorStroke.Thickness = 1
	hueCursorStroke.Parent = hueCursor

	
	local hexLabel = Instance.new("TextLabel")
	hexLabel.BackgroundTransparency = 1
	hexLabel.Size = UDim2.new(0, 80, 0, 18)
	hexLabel.Position = UDim2.new(0, svSize + 36, 0, 0)
	hexLabel.Font = Theme.FontMono
	hexLabel.TextSize = 12
	hexLabel.TextColor3 = Theme.SecondaryText
	hexLabel.TextXAlignment = Enum.TextXAlignment.Left
	hexLabel.Text = string.format(
		"#%02X%02X%02X",
		math.clamp(math.floor(color.R * 255 + 0.5), 0, 255),
		math.clamp(math.floor(color.G * 255 + 0.5), 0, 255),
		math.clamp(math.floor(color.B * 255 + 0.5), 0, 255)
	)
	hexLabel.ZIndex = 6
	hexLabel.Parent = panel

	local bigPreview = Instance.new("Frame")
	bigPreview.BackgroundColor3 = color
	bigPreview.BorderSizePixel = 0
	bigPreview.Size = UDim2.new(0, 48, 0, 48)
	bigPreview.Position = UDim2.new(0, svSize + 36, 0, 28)
	bigPreview.ZIndex = 6
	bigPreview.Parent = panel

	local bigPreviewCorner = Instance.new("UICorner")
	bigPreviewCorner.CornerRadius = UDim.new(0, 6)
	bigPreviewCorner.Parent = bigPreview

	local bigPreviewStroke = Instance.new("UIStroke")
	bigPreviewStroke.Color = Theme.Border
	bigPreviewStroke.Thickness = 1
	bigPreviewStroke.Parent = bigPreview

	local changed = CreateSignal()
	local PANEL_H = svSize + 20

	local function applyColor(fire)
		color = Color3.fromHSV(h, s, v)
		preview.BackgroundColor3 = color
		bigPreview.BackgroundColor3 = color
		sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
		local r = math.clamp(math.floor(color.R * 255 + 0.5), 0, 255)
		local g = math.clamp(math.floor(color.G * 255 + 0.5), 0, 255)
		local b = math.clamp(math.floor(color.B * 255 + 0.5), 0, 255)
		hexLabel.Text = string.format("#%02X%02X%02X", r, g, b)
		svCursor.Position = UDim2.new(s, 0, 1 - v, 0)
		hueCursor.Position = UDim2.new(0, -2, h, -2)
		if fire then
			changed:Fire(color)
			if config.Callback then
				task.spawn(config.Callback, color)
			end
		end
	end

	local function updateFromSV(inputPos)
		local absPos = sv.AbsolutePosition
		local absSize = sv.AbsoluteSize
		if absSize.X < 1 or absSize.Y < 1 then return end
		local relX = math.clamp((inputPos.X - absPos.X) / absSize.X, 0, 1)
		local relY = math.clamp((inputPos.Y - absPos.Y) / absSize.Y, 0, 1)
		s = relX
		v = 1 - relY
		applyColor(true)
	end

	local function updateFromHue(inputPos)
		local absPos = hueBar.AbsolutePosition
		local absSize = hueBar.AbsoluteSize
		if absSize.Y < 1 then return end
		local relY = math.clamp((inputPos.Y - absPos.Y) / absSize.Y, 0, 1)
		h = relY
		if s <= 0.0001 then s = 1 end
		if v <= 0.0001 then v = 1 end
		applyColor(true)
	end

	
	local function isPrimary(input)
		return input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
	end

	cleanup:AddConnection(sv.InputBegan:Connect(function(input)
		if not open or not isPrimary(input) then return end
		draggingSV = true
		updateFromSV(input.Position)
	end))

	cleanup:AddConnection(hueBar.InputBegan:Connect(function(input)
		if not open or not isPrimary(input) then return end
		draggingHue = true
		updateFromHue(input.Position)
	end))

	cleanup:AddConnection(UserInputService.InputChanged:Connect(function(input)
		if not open then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if draggingSV then
			updateFromSV(input.Position)
		elseif draggingHue then
			updateFromHue(input.Position)
		end
	end))

	cleanup:AddConnection(UserInputService.InputEnded:Connect(function(input)
		if isPrimary(input) then
			draggingSV = false
			draggingHue = false
		end
	end))

	local cp = {
		Frame = frame,
		Cleanup = cleanup,
		Changed = changed,
	}

	local function setOpen(state)
		open = state
		if open then
			
			if tab and tab.Components then
				for _, c in ipairs(tab.Components) do
					if c ~= cp and c.Close then pcall(function() c:Close() end) end
				end
			end
			frame.Size = UDim2.new(1, 0, 0, Theme.ElementHeight + PANEL_H)
			panel.Size = UDim2.new(1, 0, 0, PANEL_H)
			frame.ZIndex = 20
		else
			frame.Size = UDim2.new(1, 0, 0, Theme.ElementHeight)
			panel.Size = UDim2.new(1, 0, 0, 0)
			frame.ZIndex = 1
			draggingSV = false
			draggingHue = false
		end
	end

	local hit = Instance.new("TextButton")
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.new(1, 0, 0, Theme.ElementHeight)
	hit.Text = ""
	hit.ZIndex = 3
	hit.Parent = frame

	AddInteractiveFeedback(frame, cleanup)
	AddInteractiveFeedback(hit, cleanup, { Hover = false, ActivateSound = true })

	cleanup:AddConnection(hit.Activated:Connect(function()
		setOpen(not open)
	end))

	cleanup:AddInstance(frame)
	applyColor(false)

	function cp:Set(c, suppress)
		if typeof(c) ~= "Color3" then return end
		color = c
		h, s, v = color:ToHSV()
		applyColor(not suppress)
	end

	function cp:Get()
		return color
	end

	function cp:Close()
		setOpen(false)
	end

	function cp:RefreshTheme()
		if cleanup:IsDestroyed() then return end
		frame.BackgroundColor3 = Theme.Secondary
		stroke.Color = Theme.Border
		title.Font = Theme.Font
		title.TextColor3 = Theme.Text
		previewStroke.Color = Theme.Border
		panel.BackgroundColor3 = Theme.Secondary
		panelStroke.Color = Theme.OutlineAccent or Theme.Border
		hexLabel.Font = Theme.FontMono
		hexLabel.TextColor3 = Theme.SecondaryText
		bigPreviewStroke.Color = Theme.Border
	end

	function cp:Destroy()
		changed:Destroy()
		cleanup:Destroy()
	end

	function cp:IsDestroyed()
		return cleanup:IsDestroyed()
	end

	table.insert(tab.Components, cp)
	return cp
end

local SIDEBAR_W_DEFAULT = 132
local TITLE_H = 40

local function CreateTab(window, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local name = config.Name or "Tab"

	local content = Instance.new("ScrollingFrame")
	content.Name = "TabContent_" .. name
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Size = UDim2.new(1, 0, 1, 0)
	content.Active = true
	content.ScrollingEnabled = true
	content.ScrollingDirection = Enum.ScrollingDirection.Y
	content.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	content.ClipsDescendants = true
	content.CanvasPosition = Vector2.new(0, 0)
	content.CanvasSize = UDim2.new(0, 0, 0, 0)
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ScrollBarThickness = UserInputService.TouchEnabled and 5 or 3
	content.ScrollBarImageColor3 = Theme.Border
	content.ScrollBarImageTransparency = 0.2
	content.Visible = false
	content.Parent = window.ContentContainer

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = content

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = content

	local canvasRefreshPending = false
	local function updateCanvasSize()
		if content.Parent == nil or canvasRefreshPending then return end
		canvasRefreshPending = true
		task.defer(function()
			canvasRefreshPending = false
			if content.Parent == nil then return end
			content.AutomaticCanvasSize = Enum.AutomaticSize.Y
			content.CanvasSize = UDim2.new(0, 0, 0, 0)
		end)
	end
	cleanup:AddConnection(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvasSize))
	cleanup:AddConnection(content:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateCanvasSize))
	cleanup:AddConnection(content.DescendantAdded:Connect(updateCanvasSize))
	cleanup:AddConnection(content.DescendantRemoving:Connect(updateCanvasSize))
	task.defer(updateCanvasSize)

	local tabBtn = Instance.new("TextButton")
	tabBtn.Name = "TabBtn_" .. name
	tabBtn.BackgroundTransparency = 1 
	tabBtn.BorderSizePixel = 0
	tabBtn.Size = UDim2.new(1, 0, 0, 30)
	tabBtn.Position = UDim2.new(0, 0, 0, 0)
	tabBtn.AnchorPoint = Vector2.new(0, 0)
	tabBtn.Font = Theme.Font
	tabBtn.TextSize = 12
	tabBtn.TextColor3 = Theme.SecondaryText
	tabBtn.Text = name
	tabBtn.TextXAlignment = Enum.TextXAlignment.Center
	tabBtn.TextTruncate = Enum.TextTruncate.AtEnd
	tabBtn.AutoButtonColor = false
	tabBtn.Active = true
	tabBtn.ClipsDescendants = false
	tabBtn.ZIndex = 2
	tabBtn.Parent = window.TabBar

	
	local tabBg = Instance.new("Frame")
	tabBg.Name = "TabBg"
	tabBg.BackgroundColor3 = Theme.Secondary
	tabBg.BackgroundTransparency = 1
	tabBg.BorderSizePixel = 0
	tabBg.Size = UDim2.new(1, 0, 1, 0)
	tabBg.Position = UDim2.new(0, 0, 0, 0)
	tabBg.ZIndex = 1
	tabBg.Parent = tabBtn

	local tabBgCorner = Instance.new("UICorner")
	tabBgCorner.Name = "VeyraFixedCorner"
	tabBgCorner.CornerRadius = UDim.new(0, 6)
	tabBgCorner.Parent = tabBg

		local btnPad = Instance.new("UIPadding")
	btnPad.PaddingLeft = UDim.new(0, 0)
	btnPad.PaddingRight = UDim.new(0, 0)
	btnPad.Parent = tabBtn

	cleanup:AddInstance(content)
	cleanup:AddInstance(tabBtn)

	local tab = {
		Name = name,
		Content = content,
		Button = tabBtn,
		TabBg = tabBg,
				Sections = {},
		Components = {},
		Cleanup = cleanup,
		Window = window,
	}

	AddInteractiveFeedback(tabBtn, cleanup)

	cleanup:AddConnection(tabBtn.Activated:Connect(function()
		if cleanup:IsDestroyed() then return end
		window:SelectTab(tab)
	end))

	function tab:SetActive(active)
		if active then
			content.Visible = true
			tabBtn.BackgroundTransparency = 1
			tabBtn.TextColor3 = Theme.Text
			
			tabBg.Size = UDim2.new(1, 0, 1, 0)
			tabBg.Position = UDim2.new(0, 0, 0, 0)
			tabBg.BackgroundTransparency = 0.2
			tabBg.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			local g = SetThemeGradient(tabBg, "Accent")
			if g then g.Rotation = 0 end 
		else
			content.Visible = false

			for _, c in ipairs(tab.Components) do
				if c.Close then pcall(function() c:Close() end) end
			end
			tabBtn.BackgroundTransparency = 1
			tabBtn.TextColor3 = Theme.SecondaryText
			tabBg.BackgroundTransparency = 1
			local grad = tabBg:FindFirstChild("VeyraGradient")
			if grad then grad:Destroy() end
			tabBg.BackgroundColor3 = Theme.Secondary
		end
	end

	function tab:RefreshTheme()
		if cleanup:IsDestroyed() then return end
		content.ScrollBarImageColor3 = Theme.Border
		tabBtn.Font = Theme.Font
		if content.Visible then
			tabBtn.BackgroundTransparency = 1
			tabBtn.TextColor3 = Theme.Text
			tabBg.Size = UDim2.new(1, 0, 1, 0)
			tabBg.Position = UDim2.new(0, 0, 0, 0)
			tabBg.BackgroundTransparency = 0.2
			tabBg.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			local g = SetThemeGradient(tabBg, "Accent")
			if g then g.Rotation = 0 end 
		else
			tabBtn.BackgroundTransparency = 1
			tabBtn.TextColor3 = Theme.SecondaryText
			tabBg.BackgroundTransparency = 1
			local grad = tabBg:FindFirstChild("VeyraGradient")
			if grad then grad:Destroy() end
			tabBg.BackgroundColor3 = Theme.Secondary
		end
		for _, s in ipairs(tab.Sections) do
			if s.RefreshTheme then s:RefreshTheme() end
		end
		for _, c in ipairs(tab.Components) do
			if c.RefreshTheme then c:RefreshTheme() end
		end
	end

	function tab:CreateSection(c) return CreateSection(tab, c) end
	function tab:CreateButton(c) return CreateButton(tab, c) end
	function tab:CreateToggle(c) return CreateToggle(tab, c) end
	function tab:CreateSlider(c) return CreateSlider(tab, c) end
	function tab:CreateLabel(c) return CreateLabel(tab, c) end
	function tab:CreateDropdown(c) return CreateDropdown(tab, c) end
	function tab:CreateTextbox(c) return CreateTextbox(tab, c) end
	function tab:CreateKeybind(c) return CreateKeybind(tab, c) end
	function tab:CreateDivider() return CreateDivider(tab) end
	function tab:CreateColorPicker(c) return CreateColorPicker(tab, c) end

	function tab:Destroy()
		for _, c in ipairs(tab.Components) do
			if c.Destroy then c:Destroy() end
		end
		for _, s in ipairs(tab.Sections) do
			if s.Destroy then s:Destroy() end
		end
		cleanup:Destroy()
	end

	return tab
end

local function SetupSettingsTab(window)
	if not window or window._SettingsReady then return end
	window._SettingsReady = true

	local settingsTab = window:CreateTab({ Name = "Settings" })
	settingsTab:CreateSection({ Name = "Profile" })

	do
		local parent = GetParentForComponent(settingsTab)
		local card = Instance.new("Frame")
		card.Name = "ProfileCard"
		card.BackgroundColor3 = Theme.Tertiary
		card.BackgroundTransparency = 0.05
		card.BorderSizePixel = 0
		card.Size = UDim2.new(1, 0, 0, 72)
		card.Parent = parent

		local stroke = Instance.new("UIStroke")
		stroke.Color = Theme.OutlineAccent or Theme.Border
		stroke.Thickness = 1.5
		stroke.Transparency = 0.25
		stroke.Parent = card

		local avatar = Instance.new("ImageLabel")
		avatar.Name = "Avatar"
		avatar.BackgroundColor3 = Theme.Secondary
		avatar.BorderSizePixel = 0
		avatar.Size = UDim2.new(0, 48, 0, 48)
		avatar.Position = UDim2.new(0, 12, 0.5, -24)
		avatar.Image = ""
		avatar.ScaleType = Enum.ScaleType.Crop
		avatar.Parent = card

		local avCorner = Instance.new("UICorner")
		avCorner.Name = "VeyraCorner"
		avCorner.CornerRadius = UDim.new(1, 0)
		avCorner.Parent = avatar

		local avStroke = Instance.new("UIStroke")
		avStroke.Color = Theme.OutlineAccent or Theme.Border
		avStroke.Thickness = 1.5
		avStroke.Transparency = 0.2
		avStroke.Parent = avatar

		local nameLabel = Instance.new("TextLabel")
		nameLabel.BackgroundTransparency = 1
		nameLabel.Size = UDim2.new(1, -76, 0, 18)
		nameLabel.Position = UDim2.new(0, 70, 0, 16)
		nameLabel.Font = Theme.FontBold
		nameLabel.TextSize = 14
		nameLabel.TextColor3 = Theme.Text
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Text = LocalPlayer.DisplayName or LocalPlayer.Name
		nameLabel.Parent = card

		local userLabel = Instance.new("TextLabel")
		userLabel.BackgroundTransparency = 1
		userLabel.Size = UDim2.new(1, -76, 0, 14)
		userLabel.Position = UDim2.new(0, 70, 0, 36)
		userLabel.Font = Theme.Font
		userLabel.TextSize = 12
		userLabel.TextColor3 = Theme.SecondaryText
		userLabel.TextXAlignment = Enum.TextXAlignment.Left
		userLabel.Text = "Hello, @" .. tostring(LocalPlayer.Name)
		userLabel.Parent = card

		local countryLabel = Instance.new("TextLabel")
		countryLabel.BackgroundTransparency = 1
		countryLabel.Size = UDim2.new(1, -76, 0, 14)
		countryLabel.Position = UDim2.new(0, 70, 0, 52)
		countryLabel.Font = Theme.Font
		countryLabel.TextSize = 11
		countryLabel.TextColor3 = Theme.MutedText
		countryLabel.TextXAlignment = Enum.TextXAlignment.Left
		countryLabel.Text = "Country: ..."
		countryLabel.Parent = card

		task.spawn(function()
			local ok, url = pcall(function()
				return Players:GetUserThumbnailAsync(
					LocalPlayer.UserId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size150x150
				)
			end)
			if ok and url and avatar and avatar.Parent then
				avatar.Image = url
			end
		end)

		task.spawn(function()
			local country = "Unknown"
			local ok, code = pcall(function()
				return LocalizationService:GetCountryRegionForPlayerAsync(LocalPlayer)
			end)
			if ok and type(code) == "string" and #code > 0 then
				country = code
			end
			if countryLabel and countryLabel.Parent then
				countryLabel.Text = "Country: " .. tostring(country)
			end
		end)

		local unhook = OnThemeChange(function()
			if not card or not card.Parent then return end
			card.BackgroundColor3 = Theme.Tertiary
			stroke.Color = Theme.OutlineAccent or Theme.Border
			stroke.Transparency = 0.25
			avatar.BackgroundColor3 = Theme.Secondary
			if avStroke then
				avStroke.Color = Theme.OutlineAccent or Theme.Border
			end
			nameLabel.TextColor3 = Theme.Text
			nameLabel.Font = Theme.FontBold
			userLabel.TextColor3 = Theme.SecondaryText
			userLabel.Font = Theme.Font
			countryLabel.TextColor3 = Theme.MutedText
			countryLabel.Font = Theme.Font
		end)
		window.Cleanup:AddCallback(unhook)
		window.Cleanup:AddInstance(card)
	end

	settingsTab:CreateSection({ Name = "Appearance" })

	
	local baseThemeNames = { "Dark", "Darker", "Light", "Neon", "Cyan", "Glass", "Crimson", "Aqua", "Amethyst", "Rose" }
	for name in pairs(ThemePresets) do
		if type(name) == "string" and not table.find(baseThemeNames, name) then
			table.insert(baseThemeNames, name)
		end
	end
	if type(Settings.CustomImageThemes) ~= "table" then
		Settings.CustomImageThemes = {}
	end

	local function buildThemeNames()
		local names = {}
		for _, n in ipairs(baseThemeNames) do
			table.insert(names, n)
		end
		for _, id in ipairs(Settings.CustomImageThemes) do
			if type(id) == "string" and #id > 0 and not table.find(names, id) then
				table.insert(names, id)
			end
		end
		return names
	end

	local themeNames = buildThemeNames()
	local currentTheme = Settings.Theme or "Dark"
	if currentTheme == "Aurora" then currentTheme = "Cyan" end
	if not table.find(themeNames, currentTheme) then
		if type(currentTheme) == "string" and #currentTheme > 0 and not ThemePresets[currentTheme] then
			if not table.find(Settings.CustomImageThemes, currentTheme) then
				table.insert(Settings.CustomImageThemes, currentTheme)
			end
			themeNames = buildThemeNames()
		else
			currentTheme = "Dark"
		end
	end

	pcall(function()
		if ThemePresets[currentTheme] then
			ApplyThemePreset(currentTheme)
		end
	end)

	local themeDropdown = settingsTab:CreateDropdown({
		Name = "Theme",
		Options = themeNames,
		Default = currentTheme,
		Callback = function(v)
			Settings.Theme = v
			if ThemePresets[v] then
				Settings.UseBackgroundImage = false
				if window.SetBackgroundImageEnabled then
					window:SetBackgroundImageEnabled(false)
				end
				ApplyThemePreset(v)
				if window.RefreshTheme then window:RefreshTheme() end
				Library:Notify({
					Title = "Theme",
					Description = "Applied " .. tostring(v),
					Duration = 2,
					Type = "Success",
				})
			else
				local img = NormalizeBackgroundImage(v)
				if img == "" then
					img = NormalizeBackgroundImage("rbxassetid://" .. tostring(v))
				end
				Settings.BackgroundImage = img
				Settings.UseBackgroundImage = true
				if window.SetBackgroundImage then window:SetBackgroundImage(img) end
				if window.SetBackgroundImageEnabled then window:SetBackgroundImageEnabled(true) end
				if ThemePresets.Dark then ApplyThemePreset("Dark") end
				Settings.Theme = v
				if window.RefreshTheme then window:RefreshTheme() end
				Library:Notify({
					Title = "Image Theme",
					Description = "Applied " .. tostring(v),
					Duration = 2,
					Type = "Success",
				})
			end
		end,
	})
	window._ThemeDropdown = themeDropdown
	if themeDropdown and themeDropdown.SetOptions then
		themeDropdown:SetOptions(themeNames, true)
		themeDropdown:Set(currentTheme, true)
	end

	settingsTab:CreateSlider({
		Name = "Accent Height",
		Min = 0.05,
		Max = 1,
		Step = 0.05,
		Default = tonumber(Settings.AccentHeight) or 1,
		Callback = function(v)
			Settings.AccentHeight = math.clamp(tonumber(v) or 1, 0.05, 1)
			if window.RefreshTheme then window:RefreshTheme() end
		end,
	})

	settingsTab:CreateSection({ Name = "Background" })

	settingsTab:CreateToggle({
		Name = "Image Background",
		Default = Settings.UseBackgroundImage == true,
		Callback = function(v)
			Settings.UseBackgroundImage = v == true
			if window.SetBackgroundImageEnabled then
				window:SetBackgroundImageEnabled(Settings.UseBackgroundImage)
			end
			if window.RefreshTheme then window:RefreshTheme() end
		end,
	})

	settingsTab:CreateTextbox({
		Name = "Background Image",
		Placeholder = "rbxassetid://... or texture id",
		Default = Settings.BackgroundImage or "",
		Callback = function(v)
			local raw = tostring(v or "")
			local img = NormalizeBackgroundImage(raw)
			Settings.BackgroundImage = img
			if img ~= "" then
				Settings.UseBackgroundImage = true
				if window.SetBackgroundImage then window:SetBackgroundImage(img) end
				if window.SetBackgroundImageEnabled then window:SetBackgroundImageEnabled(true) end

				local displayName = string.match(raw, "(%d+)") or raw
				displayName = tostring(displayName)
				if type(Settings.CustomImageThemes) ~= "table" then
					Settings.CustomImageThemes = {}
				end
				if not table.find(Settings.CustomImageThemes, displayName) then
					table.insert(Settings.CustomImageThemes, displayName)
				end
				Settings.Theme = displayName
				local newNames = buildThemeNames()
				if themeDropdown and themeDropdown.SetOptions then
					themeDropdown:SetOptions(newNames, true)
					themeDropdown:Set(displayName, true)
				end
				if ThemePresets.Dark then ApplyThemePreset("Dark") end
				if window.RefreshTheme then window:RefreshTheme() end
				Library:Notify({
					Title = "Image Theme Saved",
					Description = "Added to Theme dropdown: " .. displayName,
					Duration = 2.5,
					Type = "Success",
				})
			else
				if window.SetBackgroundImage then window:SetBackgroundImage("") end
				if window.RefreshTheme then window:RefreshTheme() end
			end
		end,
	})

	settingsTab:CreateSlider({
		Name = "Image Opacity",
		Min = 0,
		Max = 100,
		Default = math.floor((1 - math.clamp(tonumber(Settings.BackgroundImageTransparency) or 0.32, 0, 1)) * 100 + 0.5),
		Callback = function(v)
			local opacity = math.clamp(tonumber(v) or 68, 0, 100) / 100
			Settings.BackgroundImageTransparency = 1 - opacity
			if window.SetBackgroundImageTransparency then
				window:SetBackgroundImageTransparency(Settings.BackgroundImageTransparency)
			end
		end,
	})

	settingsTab:CreateColorPicker({
		Name = "Background Tint",
		Default = Settings.BackgroundImageTint or Color3.fromRGB(255, 255, 255),
		Callback = function(color)
			if typeof(color) ~= "Color3" then return end
			Settings.BackgroundImageTint = color
			if window.BackgroundImage and window.BackgroundImage.Parent then
				window.BackgroundImage.ImageColor3 = color
			end
			if window.RefreshTheme then window:RefreshTheme() end
		end,
	})

	settingsTab:CreateColorPicker({
		Name = "Outline Color",
		Default = Settings.OutlineColor or Color3.fromRGB(255, 255, 255),
		Callback = function(color)
			if typeof(color) ~= "Color3" then return end
			Settings.OutlineColor = color
			if window.RefreshTheme then window:RefreshTheme() end
		end,
	})

	settingsTab:CreateSection({ Name = "Controls" })

	window._UIVisible = Settings.UIVisible ~= false
	if window.Gui then
		window.Gui.Enabled = window._UIVisible
	end

	function window:SetUIVisible(state)
		window._UIVisible = state and true or false
		Settings.UIVisible = window._UIVisible
		if window.Gui then
			window.Gui.Enabled = window._UIVisible
		end
	end

	function window:ToggleUIVisible()
		window:SetUIVisible(not window._UIVisible)
	end

	local defaultKey = KeyCodeFromName(Settings.ToggleUIKey or "X")
	if defaultKey == Enum.KeyCode.Unknown then
		defaultKey = Enum.KeyCode.X
	end

	local kb = settingsTab:CreateKeybind({
		Name = "Toggle UI",
		Default = defaultKey,
		Mode = "Toggle",
		Callback = function()

			window:ToggleUIVisible()
		end,
	})

	do
		local oldSet = kb.Set
		function kb:Set(k)
			if oldSet then oldSet(self, k) end
			local name = (k and k ~= Enum.KeyCode.Unknown) and k.Name or "X"
			Settings.ToggleUIKey = name
		end
	end

	local uiKey = defaultKey
	local function refreshUiKey()
		uiKey = KeyCodeFromName(Settings.ToggleUIKey or "X")
		if uiKey == Enum.KeyCode.Unknown then
			uiKey = Enum.KeyCode.X
		end
	end
	refreshUiKey()

	local uiToggleConn = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		refreshUiKey()
		if input.KeyCode == uiKey then

			if window.Gui and not window.Gui.Enabled then
				window:SetUIVisible(true)
			end
		end
	end)
	window.Cleanup:AddConnection(uiToggleConn)

	settingsTab:CreateButton({
		Name = "Save Settings",
		Callback = function()

			if kb and kb.Get then
				local k = kb:Get()
				if k and k ~= Enum.KeyCode.Unknown then
					Settings.ToggleUIKey = k.Name
				end
			end
			local ok = ConfigSave()
			Library:Notify({
				Title = ok and "Saved" or "Save Failed",
				Description = ok and "Settings written to " .. CONFIG_FILE or "writefile unavailable",
				Duration = 3,
				Type = ok and "Success" or "Error",
			})
		end,
	})

	settingsTab:CreateButton({
		Name = "Reset Settings",
		Callback = function()
			for k, v in pairs(DefaultSettings) do
				Settings[k] = v
			end
			ApplyThemePreset(Settings.Theme)
			if kb and kb.Set then
				kb:Set(KeyCodeFromName(Settings.ToggleUIKey))
			end
			window:SetUIVisible(true)
			if window.SetBackgroundImage then
				window:SetBackgroundImage(Settings.BackgroundImage)
			end
			if window.BackgroundImage then
				window.BackgroundImage.ImageColor3 = Settings.BackgroundImageTint or Color3.fromRGB(255, 255, 255)
				window.BackgroundImage.ImageTransparency = Settings.BackgroundImageTransparency or 0.32
			end
			Library:Notify({
				Title = "Reset",
				Description = "Settings restored to defaults",
				Duration = 2,
				Type = "Info",
			})
		end,
	})

	

local function SetupConfigProfiles(window, settingsTab)
	if not settingsTab or not window then return end
	settingsTab:CreateSection({ Name = "Profiles" })
	local nameBox
	nameBox = settingsTab:CreateTextbox({
		Name = "Profile Name",
		Placeholder = "default",
		Default = CurrentConfigName or "default",
		Callback = function(t)
			CurrentConfigName = tostring(t or "default")
		end,
	})
	local profileDrop
	profileDrop = settingsTab:CreateDropdown({
		Name = "Profile",
		Options = ListConfigs(),
		Default = CurrentConfigName or "default",
		Callback = function(v)
			CurrentConfigName = tostring(v)
			if nameBox and nameBox.Set then nameBox:Set(tostring(v)) end
			if nameBox and nameBox.SetText then nameBox:SetText(tostring(v)) end
		end,
	})
	settingsTab:CreateButton({
		Name = "Save Profile",
		Callback = function()
			local n = CurrentConfigName or "default"
			if nameBox and nameBox.Get then n = nameBox:Get() or n end
			if nameBox and nameBox.GetText then n = nameBox:GetText() or n end
			SaveNamedConfig(n)
			if profileDrop and profileDrop.SetOptions then
				profileDrop:SetOptions(ListConfigs(), true)
			end
		end,
	})
	settingsTab:CreateButton({
		Name = "Load Profile",
		Callback = function()
			local n = CurrentConfigName or "default"
			LoadNamedConfig(n)
			for _, win in ipairs(Windows) do
				if win.RefreshTheme then pcall(function() win:RefreshTheme() end) end
			end
		end,
	})
	settingsTab:CreateButton({
		Name = "Delete Profile",
		Callback = function()
			DeleteNamedConfig(CurrentConfigName)
			if profileDrop and profileDrop.SetOptions then
				profileDrop:SetOptions(ListConfigs(), true)
			end
		end,
	})
	settingsTab:CreateToggle({
		Name = "Auto Save Profile",
		Default = AutoSaveEnabled == true,
		Callback = function(v)
			AutoSaveEnabled = v == true
		end,
	})
end

	pcall(function() SetupConfigProfiles(window, settingsTab) end)
	return settingsTab
end

local function ComputeResponsiveSize(config)
	config = config or {}
	local w = tonumber(config.Width)
	local h = tonumber(config.Height)
	if w == nil then w = 420 end
	if h == nil then h = 360 end
	w = math.max(280, math.floor(w))
	h = math.max(180, math.floor(h))
	return w, h, UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function CreateWindow(library, config)
	config = config or {}
	local cleanup = CreateCleanup()
	local width, height, isTouch = ComputeResponsiveSize(config)
	local minimized = false
	local tabs = {}
	local activeTab = nil
	local aspect = nil

	local gui = Instance.new("ScreenGui")
	gui.Name = "VeyraUI_" .. (config.Title or "Window")
	gui.DisplayOrder = 50
	gui.IgnoreGuiInset = true
	ProtectAndParent(gui)

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(width, height)
	root.AnchorPoint = Vector2.new(0, 0)
	root.Position = UDim2.new(0.5, -width / 2, 0.5, -height / 2)
	root.ClipsDescendants = true
	root.Parent = gui
	EnsureCorner(root, Settings.CornerRadius or Theme.CornerRadius or 2)

	local uiScale = Instance.new("UIScale")
	uiScale.Name = "VeyraScale"
	uiScale.Scale = 1
	uiScale.Parent = root

	local main = Instance.new("Frame")
	main.Name = "Main"
	main.BackgroundColor3 = Theme.Background
	main.BackgroundTransparency = 0
	main.BorderSizePixel = 0
	main.Size = UDim2.new(1, 0, 1, 0)
	main.ClipsDescendants = true
	main.Parent = root

	
	local bgHolder = Instance.new("Frame")
	bgHolder.Name = "BackgroundHolder"
	bgHolder.BackgroundTransparency = 1
	bgHolder.BorderSizePixel = 0
	bgHolder.Size = UDim2.new(1, 0, 1, 0)
	bgHolder.Position = UDim2.new(0, 0, 0, 0)
	bgHolder.ZIndex = 0
	bgHolder.ClipsDescendants = true
	bgHolder.Parent = main

	local backgroundImage = Instance.new("ImageLabel")
	backgroundImage.Name = "BackgroundImage"
	backgroundImage.BackgroundTransparency = 1
	backgroundImage.BorderSizePixel = 0
	backgroundImage.Size = UDim2.new(1, 0, 1, 0)
	backgroundImage.Position = UDim2.new(0, 0, 0, 0)
	backgroundImage.ZIndex = 0
	backgroundImage.ScaleType = Enum.ScaleType.Crop
	backgroundImage.ImageTransparency = math.clamp(tonumber(Settings.BackgroundImageTransparency) or 0.32, 0, 1)
	local configuredBackgroundImage = NormalizeBackgroundImage(Settings.BackgroundImage)
	Settings.BackgroundImage = configuredBackgroundImage
	backgroundImage.Image = configuredBackgroundImage
	backgroundImage.Visible = false
	backgroundImage.ImageColor3 = Color3.fromRGB(255, 255, 255)
	backgroundImage.Parent = bgHolder
	backgroundImage.ZIndex = 1
	backgroundImage.Visible = Settings.UseBackgroundImage == true and configuredBackgroundImage ~= ""

	local mainStroke = Instance.new("UIStroke")
	mainStroke.Color = Theme.OutlineAccent or Theme.Border
	mainStroke.Thickness = 1.5
	mainStroke.Transparency = 0.35
	mainStroke.Parent = main

	local outline = Instance.new("Frame")
	outline.Name = "OutlineAccent"
	outline.BackgroundColor3 = Theme.OutlineAccent or Color3.fromRGB(255, 255, 255)
	outline.BackgroundTransparency = 0.05
	outline.BorderSizePixel = 0
	-- Height controlled by Settings.AccentHeight (0..1), vertically centered
	local ah = math.clamp(tonumber(Settings.AccentHeight) or 1, 0.05, 1)
	outline.Size = UDim2.new(0, 2, ah, 0)
	outline.Position = UDim2.new(0, 0, (1 - ah) / 2, 0)
	outline.ZIndex = 5
	outline.Parent = main
	local outlineCorner = Instance.new("UICorner")
	outlineCorner.CornerRadius = UDim.new(1, 0) -- pill ends
	outlineCorner.Parent = outline

	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.BackgroundColor3 = Theme.Secondary
	titleBar.BackgroundTransparency = 0.15
	titleBar.BorderSizePixel = 0
	titleBar.Size = UDim2.new(1, 0, 0, TITLE_H)
	titleBar.ZIndex = 3
	titleBar.Parent = main
	SetThemeGradient(titleBar, "Surface")

	local titleFix = Instance.new("Frame")
	titleFix.BackgroundColor3 = Theme.Secondary
	titleFix.BackgroundTransparency = 0.15
	titleFix.BorderSizePixel = 0
	titleFix.Size = UDim2.new(1, 0, 0, 12)
	titleFix.Position = UDim2.new(0, 0, 1, -12)
	titleFix.Parent = titleBar

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.new(1, -90, 0, 16)
	titleLabel.Position = UDim2.new(0, 14, 0, 5)
	titleLabel.Font = Theme.FontBold
	titleLabel.TextSize = 13
	titleLabel.TextColor3 = Theme.Text
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Text = config.Title or "Veyra"
	titleLabel.ZIndex = 10
	titleLabel.Parent = titleBar

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Size = UDim2.new(1, -90, 0, 12)
	subtitle.Position = UDim2.new(0, 14, 0, 21)
	subtitle.Font = Theme.Font
	subtitle.TextSize = 10
	subtitle.TextColor3 = Theme.SecondaryText
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Text = config.Subtitle or ""
	subtitle.ZIndex = 10
	subtitle.Parent = titleBar

	local closeBtn = Instance.new("TextButton")
	closeBtn.BackgroundTransparency = 1
	closeBtn.Size = UDim2.new(0, 28, 0, 28)
	closeBtn.Position = UDim2.new(1, -32, 0.5, -14)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 15
	closeBtn.TextColor3 = Theme.SecondaryText
	closeBtn.Text = "×"
	closeBtn.ZIndex = 15
	closeBtn.Active = true
	closeBtn.Parent = titleBar

	local minBtn = Instance.new("TextButton")
	minBtn.BackgroundTransparency = 1
	minBtn.Size = UDim2.new(0, 28, 0, 28)
	minBtn.Position = UDim2.new(1, -58, 0.5, -14)
	minBtn.Font = Enum.Font.GothamBold
	minBtn.TextSize = 14
	minBtn.TextColor3 = Theme.SecondaryText
	minBtn.Text = "−"
	minBtn.ZIndex = 15
	minBtn.Active = true
	minBtn.Parent = titleBar

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, 0, 1, -TITLE_H)
	body.Position = UDim2.new(0, 0, 0, TITLE_H)
	body.ClipsDescendants = true
	body.ZIndex = 2
	body.Parent = main

	local SIDEBAR_W = SIDEBAR_W_DEFAULT
	if isTouch then
		if width < 400 then
			SIDEBAR_W = 108
		elseif width < 480 then
			SIDEBAR_W = 120
		end
	end

	local sidebar = Instance.new("Frame")
	sidebar.Name = "Sidebar"
	sidebar.BackgroundColor3 = Theme.Secondary
	sidebar.BackgroundTransparency = 0.35
	sidebar.BorderSizePixel = 0
	sidebar.Size = UDim2.new(0, SIDEBAR_W, 1, 0)
	sidebar.Parent = body
	SetThemeGradient(sidebar, "Panel")

	local searchBox = Instance.new("TextBox")
	searchBox.Name = "Search"
	searchBox.BackgroundColor3 = Theme.Tertiary
	searchBox.BackgroundTransparency = 0.2
	searchBox.BorderSizePixel = 0

	searchBox.Size = UDim2.new(1, -16, 0, 28)
	searchBox.Position = UDim2.new(0, 8, 0, 7)
	searchBox.Font = Theme.Font
	searchBox.TextSize = 11
	searchBox.TextColor3 = Theme.Text
	searchBox.PlaceholderColor3 = Theme.MutedText
	searchBox.PlaceholderText = "Search"
	searchBox.Text = ""
	searchBox.ClearTextOnFocus = false
	searchBox.Parent = sidebar

	local searchPad = Instance.new("UIPadding")
	searchPad.PaddingLeft = UDim.new(0, 8)
	searchPad.PaddingRight = UDim.new(0, 8)
	searchPad.Parent = searchBox

	local searchCorner = Instance.new("UICorner")
	searchCorner.Name = "VeyraFixedCorner"
	searchCorner.CornerRadius = UDim.new(0, 6)
	searchCorner.Parent = searchBox

	local tabBar = Instance.new("ScrollingFrame")
	tabBar.Name = "TabBar"
	tabBar.BackgroundTransparency = 1
	tabBar.BorderSizePixel = 0
	tabBar.Size = UDim2.new(1, 0, 1, -42)
	tabBar.Position = UDim2.new(0, 0, 0, 40)
	tabBar.CanvasSize = UDim2.new(0, 0, 0, 0)
	tabBar.AutomaticCanvasSize = Enum.AutomaticSize.Y
	tabBar.ScrollBarThickness = 0
	tabBar.ScrollingDirection = Enum.ScrollingDirection.Y
	tabBar.Active = true
	tabBar.Parent = sidebar

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Vertical
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Padding = UDim.new(0, 3)
	tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	tabLayout.Parent = tabBar

	local tabPad = Instance.new("UIPadding")
	tabPad.PaddingTop = UDim.new(0, 2)
	tabPad.PaddingLeft = UDim.new(0, 0)
	tabPad.PaddingRight = UDim.new(0, 0)
	tabPad.PaddingBottom = UDim.new(0, 6)
	tabPad.Parent = tabBar

	local contentContainer = Instance.new("Frame")
	contentContainer.Name = "ContentContainer"
	contentContainer.BackgroundTransparency = 1
	contentContainer.Size = UDim2.new(1, -SIDEBAR_W, 1, 0)
	contentContainer.Position = UDim2.new(0, SIDEBAR_W, 0, 0)
	contentContainer.ClipsDescendants = true
	contentContainer.Parent = body

	local window = {
		Gui = gui,
		Root = root,
		Main = main,
		Outline = outline,
		TitleBar = titleBar,
		Body = body,
		Sidebar = sidebar,
		TabBar = tabBar,
		ContentContainer = contentContainer,
		SearchBox = searchBox,
		BackgroundImage = backgroundImage,
		BgHolder = bgHolder,
		UIScale = uiScale,
		Tabs = tabs,
		Width = width,
		Height = height,
		Aspect = aspect,
		Cleanup = cleanup,
		Actions = {},
		_RestoredWidth = width,
		_RestoredHeight = height,
	}

	local function filterTabs()
		local raw = searchBox.Text or ""
		local q = string.lower((string.gsub(raw, "^%s+", "")))
		q = (string.gsub(q, "%s+$", ""))
		
		for _, child in ipairs(tabBar:GetChildren()) do
			if child:IsA("TextButton") and string.find(child.Name, "TabBtn_", 1, true) then
				local name = string.lower(tostring(child.Text or ""))
				local show = (q == "") or (string.find(name, q, 1, true) ~= nil)
				child.Visible = show
			end
		end
		
		for _, tab in ipairs(tabs) do
			if tab.Button and tab.Button.Parent then
				local name = string.lower(tostring(tab.Name or tab.Button.Text or ""))
				local show = (q == "") or (string.find(name, q, 1, true) ~= nil)
				tab.Button.Visible = show
			end
		end
	end
	cleanup:AddConnection(searchBox:GetPropertyChangedSignal("Text"):Connect(filterTabs))
	cleanup:AddConnection(searchBox.FocusLost:Connect(filterTabs))

	cleanup:AddConnection(searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		task.defer(filterTabs)
	end))
	searchBox.ClearTextOnFocus = false
	searchBox.TextEditable = true

	local drag = MakeDraggable(titleBar, root)
	cleanup:AddCallback(function() drag:Destroy() end)

	AddInteractiveFeedback(closeBtn, cleanup)
	AddInteractiveFeedback(minBtn, cleanup)

	cleanup:AddConnection(closeBtn.Activated:Connect(function()
		window:Close()
	end))
	cleanup:AddConnection(minBtn.Activated:Connect(function()
		window:ToggleMinimize()
	end))

	local function makeResizeHandle(name, size, pos, mode)
		local btn = Instance.new("TextButton")
		btn.Name = name
		btn.BackgroundTransparency = 1
		btn.Text = ""
		btn.Size = size
		btn.Position = pos
		btn.ZIndex = 25
		btn.AutoButtonColor = false
		btn.Parent = main
		AddInteractiveFeedback(btn, cleanup, { ActivateSound = false })
		cleanup:AddConnection(btn.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			if minimized then return end
			local startInput = input.Position
			local startSize = root.AbsoluteSize
			local moveC, endC
			moveC = UserInputService.InputChanged:Connect(function(inp)
				if inp.UserInputType ~= Enum.UserInputType.MouseMovement and inp.UserInputType ~= Enum.UserInputType.Touch then
					return
				end
				local dx = inp.Position.X - startInput.X
				local dy = inp.Position.Y - startInput.Y
				local newW = startSize.X
				local newH = startSize.Y
				if mode == "right" or mode == "corner" then
					
					newW = math.max(280, startSize.X + dx)
				end
				if mode == "bottom" or mode == "corner" then
					newH = math.max(180, startSize.Y + dy)
				end
				newW = math.floor(newW + 0.5)
				newH = math.floor(newH + 0.5)
				root.Size = UDim2.fromOffset(newW, newH)
				window.Width = newW
				window.Height = newH
				window._RestoredWidth = newW
				window._RestoredHeight = newH
			end)
			endC = UserInputService.InputEnded:Connect(function(inp)
				if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
					if moveC then moveC:Disconnect() end
					if endC then endC:Disconnect() end
				end
			end)
		end))
		return btn
	end

	local resizeGrip = makeResizeHandle("ResizeGrip", UDim2.new(0, 22, 0, 22), UDim2.new(1, -22, 1, -22), "corner")

	local gripVisual = Instance.new("Frame")
	gripVisual.BackgroundColor3 = Theme.Border
	gripVisual.BackgroundTransparency = 0.3
	gripVisual.BorderSizePixel = 0
	gripVisual.Size = UDim2.new(0, 10, 0, 2)
	gripVisual.Position = UDim2.new(1, -12, 1, -6)
	gripVisual.Rotation = -45
	gripVisual.ZIndex = 26
	gripVisual.Parent = main
	local grip2 = gripVisual:Clone()
	grip2.Position = UDim2.new(1, -8, 1, -6)
	grip2.Parent = main

	window._RestoredWidth = width
	window._RestoredHeight = height
	root.Size = UDim2.fromOffset(0, 0)
	main.BackgroundTransparency = 1
	local openTransparency = 0.02
	if Settings.Theme == "Glass" then
		openTransparency = 0.28
	elseif Settings.UseBackgroundImage == true and tostring(Settings.BackgroundImage or "") ~= "" then
		openTransparency = 0.35
	end
	TweenEngine.Play(root, {
		Size = UDim2.fromOffset(width, height),
	}, { Duration = 0.4, Easing = "BackOut" })
	TweenEngine.Play(main, { BackgroundTransparency = openTransparency }, {
		Duration = 0.32,
		Easing = "QuadOut",
		OnComplete = function()
			
			if not cleanup:IsDestroyed() and window and window.RefreshTheme then
				window:RefreshTheme()
			end
		end,
	})

	cleanup:AddInstance(gui)

	local function refitToViewport()
		if minimized or cleanup:IsDestroyed() then return end
		local cam = workspace.CurrentCamera
		if not cam then return end
		local vp = cam.ViewportSize
		local margin = 12
		local fitX = (vp.X - margin) / math.max(width, 1)
		local fitY = (vp.Y - margin) / math.max(height, 1)
		local scale = math.min(1, fitX, fitY)
		uiScale.Scale = math.clamp(scale, 0.5, 1)
		
		local fitW = math.max(280, math.floor(tonumber(window.Width) or width))
		local fitH = math.max(180, math.floor(tonumber(window.Height) or height))
		root.Size = UDim2.fromOffset(fitW, fitH)
		local aw = fitW * uiScale.Scale
		local ah = fitH * uiScale.Scale
		root.Position = UDim2.new(0.5, -aw / 2, 0.5, -ah / 2)
	end

	if workspace.CurrentCamera then
		cleanup:AddConnection(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			task.defer(function()
				refitToViewport()
			end)
		end))
	end
	cleanup:AddConnection(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local cam = workspace.CurrentCamera
		if cam then
			cleanup:AddConnection(cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				task.defer(function()
					refitToViewport()
				end)
			end))
			task.defer(function() refitToViewport() end)
		end
	end))

	local function clearVeyraGradients(rootObj)
		if not rootObj then return end
		local function clearOne(obj)
			if not obj or not obj:IsA("GuiObject") then return end
			local g = obj:FindFirstChild("VeyraGradient")
			if g then
				UnregisterGradient(g)
				pcall(function() g:Destroy() end)
			end
		end
		clearOne(rootObj)
		for _, d in ipairs(rootObj:GetDescendants()) do
			clearOne(d)
		end
	end

	local function refreshWindowTheme()
		if cleanup:IsDestroyed() then return end
		Theme.CornerRadius = math.max(0, math.floor(tonumber(Settings.CornerRadius or Theme.CornerRadius or 6) or 6))
		EnsureCorner(root, Theme.CornerRadius)
		EnsureCorner(main, Theme.CornerRadius)
		-- Accent height (0..1) – vertically centered left bar
		if outline and outline.Parent then
			local ah = math.clamp(tonumber(Settings.AccentHeight) or 1, 0.05, 1)
			outline.Size = UDim2.new(0, 2, ah, 0)
			outline.Position = UDim2.new(0, 0, (1 - ah) / 2, 0)
		end
		titleLabel.TextColor3 = Theme.Text
		titleLabel.Font = Theme.FontBold
		subtitle.TextColor3 = Theme.SecondaryText
		subtitle.Font = Theme.Font
		closeBtn.TextColor3 = Theme.SecondaryText
		minBtn.TextColor3 = Theme.SecondaryText
		searchBox.TextColor3 = Theme.Text
		searchBox.PlaceholderColor3 = Theme.MutedText
		searchBox.Font = Theme.Font

		local normalizedImage = NormalizeBackgroundImage(Settings.BackgroundImage)
		if Settings.BackgroundImage ~= normalizedImage then
			Settings.BackgroundImage = normalizedImage
		end
		local useImg = IsImageThemeActive()
		local outlineCol = GetOutlineColor()
		pcall(function() TweenEngine.CancelOnObject(main) end)

		if useImg then
			
			
			clearVeyraGradients(main)
			main.BackgroundColor3 = Theme.Background
			main.BackgroundTransparency = 1
			mainStroke.Color = outlineCol
			mainStroke.Transparency = 0.15
			mainStroke.Thickness = 1.6
			titleBar.BackgroundColor3 = Theme.Secondary
			titleBar.BackgroundTransparency = 0.72
			titleFix.BackgroundColor3 = Theme.Secondary
			titleFix.BackgroundTransparency = 0.72
			sidebar.BackgroundColor3 = Theme.Secondary
			sidebar.BackgroundTransparency = 0.72
			searchBox.BackgroundColor3 = Theme.Tertiary
			searchBox.BackgroundTransparency = 0.55
			outline.BackgroundColor3 = outlineCol
			outline.BackgroundTransparency = 0.05
			if backgroundImage then
				backgroundImage.Image = normalizedImage
				backgroundImage.ImageTransparency = math.clamp(
					tonumber(Settings.BackgroundImageTransparency) or 0.32, 0, 1
				)
				backgroundImage.ImageColor3 = Settings.BackgroundImageTint or Color3.fromRGB(255, 255, 255)
				backgroundImage.ZIndex = 0
				backgroundImage.Visible = true
			end
			if bgHolder and bgHolder.Parent then
				bgHolder.ZIndex = 0
			end
		else
			SetThemeGradient(main, "Background")
			SetThemeGradient(titleBar, "Surface")
			SetThemeGradient(sidebar, "Panel")
			mainStroke.Color = Theme.OutlineAccent or Theme.Border
			outline.BackgroundColor3 = Theme.OutlineAccent or Color3.fromRGB(255, 255, 255)
			searchBox.BackgroundColor3 = Theme.Tertiary
			titleFix.BackgroundColor3 = Theme.Secondary

			if Settings.Theme == "Glass" then
				main.BackgroundTransparency = 0.28
				mainStroke.Transparency = 0.15
				mainStroke.Thickness = 1.8
				titleBar.BackgroundTransparency = 0.35
				titleFix.BackgroundTransparency = 0.35
				sidebar.BackgroundTransparency = 0.42
				outline.BackgroundTransparency = 0.05
				outline.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				searchBox.BackgroundTransparency = 0.35
			else
				main.BackgroundTransparency = 0
				mainStroke.Transparency = 0.35
				mainStroke.Thickness = 1.5
				titleBar.BackgroundTransparency = 0.15
				titleFix.BackgroundTransparency = 0.15
				sidebar.BackgroundTransparency = 0.35
				outline.BackgroundTransparency = 0.05
				searchBox.BackgroundTransparency = 0.2
			end
			if backgroundImage then
				backgroundImage.Visible = false
			end
		end

		DecorateGuiTree(main)
		for _, tab in ipairs(tabs) do
			if tab.RefreshTheme then tab:RefreshTheme() end
		end
	end
	cleanup:AddCallback(OnThemeChange(refreshWindowTheme))
	cleanup:AddConnection(main.DescendantAdded:Connect(function(obj)
		task.defer(function()
			if obj and obj.Parent and not cleanup:IsDestroyed() then
				DecorateGuiTree(main)
			end
		end)
	end))
	DecorateGuiTree(main)

	function window:AddAction(actionConfig)
		actionConfig = actionConfig or {}
		local name = actionConfig.Name or "Action"
		local icon = actionConfig.Icon
		local callback = actionConfig.Callback
		if not window._ActionBar then
			window._ActionBar = Instance.new("Frame")
			window._ActionBar.Name = "ActionBar"
			window._ActionBar.BackgroundTransparency = 1
			window._ActionBar.Size = UDim2.new(0, 0, 0, 26)
			window._ActionBar.Position = UDim2.new(1, -64, 0.5, -13)
			window._ActionBar.AnchorPoint = Vector2.new(1, 0)
			window._ActionBar.ZIndex = 4
			window._ActionBar.Parent = titleBar
			local al = Instance.new("UIListLayout")
			al.FillDirection = Enum.FillDirection.Horizontal
			al.HorizontalAlignment = Enum.HorizontalAlignment.Right
			al.Padding = UDim.new(0, 4)
			al.Parent = window._ActionBar
		end
		local actionBar = window._ActionBar
		local btn = Instance.new("TextButton")
		btn.BackgroundColor3 = Theme.Tertiary
		btn.BackgroundTransparency = 0.3
		btn.BorderSizePixel = 0
		btn.Size = UDim2.new(0, 24, 0, 24)
		btn.AutoButtonColor = false
		btn.Text = ""
		btn.ZIndex = 5
		btn.Parent = actionBar

		if icon and tostring(icon) ~= "" then
			local img = Instance.new("ImageLabel")
			img.BackgroundTransparency = 1
			img.Size = UDim2.new(0, 14, 0, 14)
			img.Position = UDim2.new(0.5, -7, 0.5, -7)
			img.Image = tostring(icon)
			img.Parent = btn
		else
			local lbl = Instance.new("TextLabel")
			lbl.BackgroundTransparency = 1
			lbl.Size = UDim2.new(1, 0, 1, 0)
			lbl.Font = Theme.FontBold
			lbl.TextSize = 10
			lbl.TextColor3 = Theme.Text
			lbl.Text = string.sub(name, 1, 1)
			lbl.Parent = btn
		end
		btn.MouseEnter:Connect(function()
			TweenEngine.Play(btn, { BackgroundTransparency = 0.1 }, { Duration = 0.1 })
		end)
		btn.MouseLeave:Connect(function()
			TweenEngine.Play(btn, { BackgroundTransparency = 0.3 }, { Duration = 0.1 })
		end)
		AddInteractiveFeedback(btn, cleanup)
		btn.Activated:Connect(function()
			if callback then task.spawn(callback) end
		end)
		task.defer(function()
			local total = 0
			for _, ch in ipairs(actionBar:GetChildren()) do
				if ch:IsA("GuiObject") then total += ch.AbsoluteSize.X + 4 end
			end
			actionBar.Size = UDim2.new(0, math.max(total, 0), 0, 26)
		end)
		local act = { Button = btn, Name = name }
		table.insert(window.Actions, act)
		return act
	end

	function window:CreateTab(c)
		local tab = CreateTab(window, c)
		table.insert(tabs, tab)
		if not activeTab then
			window:SelectTab(tab)
		end
		return tab
	end

	function window:SelectTab(tab)
		if activeTab == tab then return end
		if activeTab then activeTab:SetActive(false) end
		activeTab = tab
		tab:SetActive(true)
	end

	function window:RefreshTheme()
		refreshWindowTheme()
	end

	function window:SetBackgroundImage(image)
		local value = NormalizeBackgroundImage(image)
		Settings.BackgroundImage = value

		if value ~= "" then
			Settings.UseBackgroundImage = true
		else
			Settings.UseBackgroundImage = false
		end

		backgroundImage.Image = value
		backgroundImage.ImageTransparency = math.clamp(tonumber(Settings.BackgroundImageTransparency) or 0.32, 0, 1)
		backgroundImage.ImageColor3 = Settings.BackgroundImageTint or Color3.fromRGB(255, 255, 255)
		backgroundImage.ZIndex = 1
		backgroundImage.Visible = Settings.UseBackgroundImage and value ~= ""
		refreshWindowTheme()
	end

	function window:SetBackgroundImageEnabled(enabled)
		Settings.UseBackgroundImage = enabled == true
		Settings.BackgroundImage = NormalizeBackgroundImage(Settings.BackgroundImage)
		backgroundImage.Image = Settings.BackgroundImage
		backgroundImage.ImageColor3 = Color3.fromRGB(255, 255, 255)
		backgroundImage.ZIndex = 1
		backgroundImage.Visible = Settings.UseBackgroundImage and Settings.BackgroundImage ~= ""
		refreshWindowTheme()
	end

	function window:SetBackgroundImageTransparency(value)
		Settings.BackgroundImageTransparency = math.clamp(tonumber(value) or 0.32, 0, 1)
		backgroundImage.ImageTransparency = Settings.BackgroundImageTransparency
		if backgroundImage.Visible then
			refreshWindowTheme()
		end
	end

	function window:ToggleMinimize()
		
		
		
		local grip = main:FindFirstChild("ResizeGrip")
		local gripR = main:FindFirstChild("ResizeRight")
		local gripB = main:FindFirstChild("ResizeBottom")

		if not minimized then
			window._RestoredWidth = math.max(280, math.floor(tonumber(window.Width) or width))
			window._RestoredHeight = math.max(180, math.floor(tonumber(window.Height) or height))
			window.Width = window._RestoredWidth
			window.Height = window._RestoredHeight
		end

		minimized = not minimized
		TweenEngine.CancelOnObject(root)
		TweenEngine.CancelOnObject(main)

		if minimized then
			body.Visible = false
			sidebar.Visible = false
			contentContainer.Visible = false
			if grip then grip.Visible = false end
			if gripR then gripR.Visible = false end
			if gripB then gripB.Visible = false end

			
			
			TweenEngine.Play(root, {
				Size = UDim2.fromOffset(window._RestoredWidth, TITLE_H),
			}, {
				Duration = 0.24,
				Easing = "QuadInOut",
			})
		else
			local restoreW = math.clamp(math.floor(tonumber(window._RestoredWidth) or width), 360, 900)
			local restoreH = math.clamp(math.floor(tonumber(window._RestoredHeight) or height), 220, 560)
			window.Width = restoreW
			window.Height = restoreH

			TweenEngine.Play(root, {
				Size = UDim2.fromOffset(restoreW, restoreH),
			}, {
				Duration = 0.26,
				Easing = "QuadOut",
				OnComplete = function()
					if minimized or cleanup:IsDestroyed() then return end
					body.Visible = true
					sidebar.Visible = true
					contentContainer.Visible = true
					if grip then grip.Visible = true end
					if gripR then gripR.Visible = true end
					if gripB then gripB.Visible = true end
				end,
			})
		end
	end

	function window:Close()
		if window._Closing or cleanup:IsDestroyed() then return end
		window._Closing = true

		TweenEngine.CancelOnObject(root)
		TweenEngine.CancelOnObject(main)

		
		root.ClipsDescendants = false
		main.ClipsDescendants = false

		local function fadeContent(obj)
			if not obj or not obj.Parent then return end
			if obj == backgroundImage or obj == bgHolder then return end

			if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
				TweenEngine.Play(obj, {
					TextTransparency = 1,
					BackgroundTransparency = 1,
				}, { Duration = 0.7, Easing = "QuadIn" })
			elseif obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
				TweenEngine.Play(obj, {
					ImageTransparency = 1,
					BackgroundTransparency = 1,
				}, { Duration = 0.7, Easing = "QuadIn" })
			elseif obj:IsA("GuiObject") then
				TweenEngine.Play(obj, {
					BackgroundTransparency = 1,
				}, { Duration = 0.7, Easing = "QuadIn" })
			end
		end

		for _, obj in ipairs(main:GetDescendants()) do
			fadeContent(obj)
		end

		
		task.delay(0.75, function()
			if cleanup:IsDestroyed() then return end

			main.Visible = false

			local shardLayer = Instance.new("Frame")
			shardLayer.Name = "VeyraDisassembly"
			shardLayer.BackgroundTransparency = 1
			shardLayer.BorderSizePixel = 0
			shardLayer.Size = UDim2.new(1, 0, 1, 0)
			shardLayer.Position = UDim2.new(0, 0, 0, 0)
			shardLayer.ZIndex = 100
			shardLayer.Parent = root
			cleanup:AddInstance(shardLayer)

			local cols, rows = 4, 4
			local shards = {}
			local index = 0

			for y = 1, rows do
				for x = 1, cols do
					index += 1

					local shard = Instance.new("Frame")
					shard.Name = "Shard_" .. x .. "_" .. y
					shard.BackgroundColor3 = Theme.Background
					shard.BackgroundTransparency = 0.02
					shard.BorderSizePixel = 0
					shard.Size = UDim2.new(1 / cols, 0, 1 / rows, 0)
					shard.Position = UDim2.new((x - 1) / cols, 0, (y - 1) / rows, 0)
					shard.ZIndex = 100 + y
					shard.Parent = shardLayer

					local gradient = main:FindFirstChild("VeyraGradient")
					if gradient then
						local g = gradient:Clone()
						g.Name = "VeyraGradient"
						g.Parent = shard
					end

					local stroke = Instance.new("UIStroke")
					stroke.Color = Theme.OutlineAccent or Theme.Border
					stroke.Thickness = 1
					stroke.Transparency = 0.5
					stroke.Parent = shard

					local dx = x - (cols + 1) / 2
					local dy = y - (rows + 1) / 2
					local direction = Vector2.new(dx, dy)
					if direction.Magnitude < 0.01 then
						direction = Vector2.new(0.25, -0.25)
					end
					direction = direction.Unit

					table.insert(shards, {
						Object = shard,
						Direction = direction,
						Distance = math.random(70, 150),
						Rotation = math.random(-38, 38),
						Index = index,
					})
				end
			end

			
			for _, data in ipairs(shards) do
				local shard = data.Object
				local startPos = shard.Position
				local targetPos = UDim2.new(
					startPos.X.Scale,
					startPos.X.Offset + data.Direction.X * data.Distance,
					startPos.Y.Scale,
					startPos.Y.Offset + data.Direction.Y * data.Distance
				)

				task.delay((data.Index - 1) * 0.035, function()
					if not shard.Parent or cleanup:IsDestroyed() then return end

					TweenEngine.Play(shard, {
						Position = targetPos,
						Rotation = data.Rotation,
						BackgroundTransparency = 1,
					}, {
						Duration = 4.15,
						Easing = "CubicIn",
					})

					local stroke = shard:FindFirstChildOfClass("UIStroke")
					if stroke then
						TweenEngine.Play(stroke, {
							Transparency = 1,
						}, { Duration = 4.15, Easing = "QuadIn" })
					end
				end)
			end

			task.delay(5.05, function()
				if cleanup:IsDestroyed() then return end
				window:Destroy()
			end)
		end)
	end

	function window:Destroy()

		pcall(function() TweenEngine.CancelOnObject(root) end)
		pcall(function() TweenEngine.CancelOnObject(main) end)
		for _, tab in ipairs(tabs) do
			pcall(function()
				if tab.Destroy then tab:Destroy() end
			end)
		end
		table.clear(tabs)
		pcall(function() cleanup:Destroy() end)

		pcall(function()
			if gui then gui:Destroy() end
		end)

		pcall(function()
			local idx = table.find(Windows, window)
			if idx then table.remove(Windows, idx) end
		end)

		pcall(function()
			if #Windows == 0 and NotifManager then
				NotifManager:Clear()
			end
		end)
	end

	pcall(function()
		SetupSettingsTab(window)
	end)

	if config.Acrylic or config.SurfaceBlur then
		pcall(function()
			window._SurfaceBlur = SurfaceBlur.new(window.Main)
			window.Cleanup:AddCallback(function()
				if window._SurfaceBlur then window._SurfaceBlur:Destroy() end
			end)
		end)
	end

	return window
end

local function PlayIntro(config)
	config = config or {}
	local duration = config.Duration or 1.5
	local titleText = config.Title or "Veyra"
	local subtitleText = config.Subtitle or ""
	local logoId = config.Logo
	local cleanup = CreateCleanup()
	local gui = Instance.new("ScreenGui")
	gui.Name = "VeyraIntro"
	gui.DisplayOrder = 2147483647
	gui.IgnoreGuiInset = true
	ProtectAndParent(gui)
	cleanup:AddInstance(gui)
	local overlay = Instance.new("Frame")
	overlay.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
	overlay.BorderSizePixel = 0
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.Parent = gui
	local center = Instance.new("Frame")
	center.BackgroundTransparency = 1
	center.Size = UDim2.new(0, 220, 0, 120)
	center.Position = UDim2.new(0.5, -110, 0.5, -60)
	center.Parent = overlay
	if logoId and tostring(logoId) ~= "" then
		local logo = Instance.new("ImageLabel")
		logo.BackgroundTransparency = 1
		logo.Size = UDim2.new(0, 48, 0, 48)
		logo.Position = UDim2.new(0.5, -24, 0, 0)
		logo.Image = tostring(logoId)
		logo.ScaleType = Enum.ScaleType.Fit
		logo.ImageTransparency = 1
		logo.Parent = center
		TweenEngine.Play(logo, { ImageTransparency = 0 }, { Duration = 0.4, Easing = "QuadOut" })
	end
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 28)
	title.Position = UDim2.new(0, 0, 0, logoId and 56 or 20)
	title.Font = Theme.FontBold
	title.TextSize = 22
	title.TextColor3 = Theme.Text
	title.Text = titleText
	title.TextTransparency = 1
	title.Parent = center
	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Size = UDim2.new(1, 0, 0, 18)
	subtitle.Position = UDim2.new(0, 0, 0, logoId and 86 or 50)
	subtitle.Font = Theme.Font
	subtitle.TextSize = 13
	subtitle.TextColor3 = Theme.SecondaryText
	subtitle.Text = subtitleText
	subtitle.TextTransparency = 1
	subtitle.Parent = center
	TweenEngine.Play(title, { TextTransparency = 0 }, { Duration = 0.45, Delay = 0.1, Easing = "QuadOut" })
	TweenEngine.Play(subtitle, { TextTransparency = 0 }, { Duration = 0.4, Delay = 0.2, Easing = "QuadOut" })
	local finished = false
	local function finish()
		if finished then return end
		finished = true
		TweenEngine.Play(overlay, { BackgroundTransparency = 1 }, {
			Duration = 0.35, Easing = "QuadIn",
			OnComplete = function() cleanup:Destroy() end,
		})
		TweenEngine.Play(title, { TextTransparency = 1 }, { Duration = 0.25, Easing = "QuadIn" })
		TweenEngine.Play(subtitle, { TextTransparency = 1 }, { Duration = 0.25, Easing = "QuadIn" })
	end
	cleanup:AddTask(task.delay(duration, finish))
	local skipBtn = Instance.new("TextButton")
	skipBtn.BackgroundTransparency = 1
	skipBtn.Size = UDim2.new(1, 0, 1, 0)
	skipBtn.Text = ""
	skipBtn.Parent = overlay
	cleanup:AddConnection(skipBtn.MouseButton1Click:Connect(finish))
	return { Skip = finish, Destroy = finish }
end

local function CreateKeySystem(config)
	config = config or {}
	if type(Settings.Theme) == "string" and ThemePresets[Settings.Theme] then
		ApplyThemePreset(Settings.Theme)
	end
	local cleanup = CreateCleanup()
	local closed = false
	local splitting = false

	local titleText = config.Title or "Key System"
	local bottomText = config.BottomLabel or config.BottomText or config.Footer or ""
	local link = config.Link or config.KeyLink
	local fixedKey = config.Key
	local validateFn = config.Validate
	local getKeyFn = config.GetKey or config.OnGetKey
	local onSuccess = config.OnSuccess or config.Callback
	local onFail = config.OnFail
	local width = math.clamp(tonumber(config.Width) or 360, 300, 420)
	local height = math.clamp(tonumber(config.Height) or 220, 190, 280)

	local function doValidate(key)
		if type(validateFn) == "function" then
			local ok, result = pcall(validateFn, key)
			return ok and result == true
		end
		if fixedKey ~= nil then
			return tostring(key) == tostring(fixedKey)
		end
		return type(key) == "string" and #key > 0
	end

	local function tryClipboard(text)
		if type(text) ~= "string" or #text == 0 then return false end
		local ok = false
		pcall(function()
			if type(setclipboard) == "function" then
				setclipboard(text)
				ok = true
			elseif type(toclipboard) == "function" then
				toclipboard(text)
				ok = true
			elseif type(set_clipboard) == "function" then
				set_clipboard(text)
				ok = true
			elseif type(Clipboard) == "table" and type(Clipboard.set) == "function" then
				Clipboard.set(text)
				ok = true
			end
		end)
		return ok
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "VeyraKeySystem"
	gui.DisplayOrder = 2147483646
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	ProtectAndParent(gui)
	cleanup:AddInstance(gui)

	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.Size = UDim2.new(1, 0, 1, 0)
	dim.ZIndex = 1
	dim.Parent = gui

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(0, 0)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.new(0.5, 0, 0.5, 0)
	root.ClipsDescendants = true
	root.ZIndex = 2
	root.Parent = gui

	local main = Instance.new("Frame")
	main.Name = "Main"
	main.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	main.BackgroundTransparency = 0
	main.BorderSizePixel = 0
	main.Size = UDim2.new(1, 0, 1, 0)
	main.ClipsDescendants = true
	main.Parent = root
	EnsureCorner(main, Settings.CornerRadius or 2)
	SetThemeGradient(main, "Background")

	local mainStroke = Instance.new("UIStroke")
	mainStroke.Color = Theme.OutlineAccent or Theme.Border
	mainStroke.Thickness = 1.5
	mainStroke.Transparency = 0.35
	mainStroke.Parent = main

	local outline = Instance.new("Frame")
	outline.Name = "OutlineAccent"
	outline.BackgroundColor3 = Theme.OutlineAccent or Color3.fromRGB(255, 255, 255)
	outline.BackgroundTransparency = 0.05
	outline.BorderSizePixel = 0
	outline.Size = UDim2.new(0, 1, 1, -20)
	outline.Position = UDim2.new(0, 0, 0, 10)
	outline.ZIndex = 5
	outline.Parent = main

	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.BackgroundColor3 = Theme.Secondary
	titleBar.BackgroundTransparency = 0.15
	titleBar.BorderSizePixel = 0
	titleBar.Size = UDim2.new(1, 0, 0, 36)
	titleBar.ZIndex = 3
	titleBar.Parent = main
	SetThemeGradient(titleBar, "Surface") 
	titleBar.BackgroundTransparency = 0

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.new(1, -40, 1, 0)
	titleLabel.Position = UDim2.new(0, 14, 0, 0)
	titleLabel.Font = Theme.FontBold
	titleLabel.TextSize = 14
	titleLabel.TextColor3 = Theme.Text
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Text = titleText
	titleLabel.ZIndex = 10
	titleLabel.Parent = titleBar

	local closeBtn = Instance.new("TextButton")
	closeBtn.BackgroundTransparency = 1
	closeBtn.Size = UDim2.new(0, 28, 0, 28)
	closeBtn.Position = UDim2.new(1, -30, 0.5, -14)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 15
	closeBtn.TextColor3 = Theme.SecondaryText
	closeBtn.Text = "×"
	closeBtn.ZIndex = 10
	closeBtn.Parent = titleBar

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, 0, 1, -36)
	body.Position = UDim2.new(0, 0, 0, 36)
	body.Parent = main

	local bodyPad = Instance.new("UIPadding")
	bodyPad.PaddingTop = UDim.new(0, 14)
	bodyPad.PaddingBottom = UDim.new(0, 12)
	bodyPad.PaddingLeft = UDim.new(0, 16)
	bodyPad.PaddingRight = UDim.new(0, 16)
	bodyPad.Parent = body

	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Padding = UDim.new(0, 10)
	bodyLayout.Parent = body

	local boxFrame = Instance.new("Frame")
	boxFrame.BackgroundColor3 = Theme.Secondary
	boxFrame.BackgroundTransparency = 0.15
	boxFrame.BorderSizePixel = 0
	boxFrame.Size = UDim2.new(1, 0, 0, Theme.ElementHeight)
	boxFrame.LayoutOrder = 1
	boxFrame.Parent = body

	local boxStroke = Instance.new("UIStroke")
	boxStroke.Color = Theme.Border
	boxStroke.Thickness = 1
	boxStroke.Transparency = 0.5
	boxStroke.Parent = boxFrame
	EnsureCorner(boxFrame, Settings.CornerRadius or 2)

	local keyBox = Instance.new("TextBox")
	keyBox.BackgroundTransparency = 1
	keyBox.Size = UDim2.new(1, -24, 1, 0)
	keyBox.Position = UDim2.new(0, 12, 0, 0)
	keyBox.Font = Theme.FontMono
	keyBox.TextSize = 13
	keyBox.TextColor3 = Theme.Text
	keyBox.PlaceholderColor3 = Theme.MutedText
	keyBox.PlaceholderText = config.Placeholder or "Enter key..."
	keyBox.Text = ""
	keyBox.ClearTextOnFocus = false
	keyBox.TextXAlignment = Enum.TextXAlignment.Left
	keyBox.Parent = boxFrame

	cleanup:AddConnection(keyBox.Focused:Connect(function()
		if closed or splitting then return end
		TweenEngine.Play(boxStroke, { Color = Theme.Accent, Transparency = 0.2 }, { Duration = 0.15 })
	end))
	cleanup:AddConnection(keyBox.FocusLost:Connect(function()
		if closed or splitting then return end
		TweenEngine.Play(boxStroke, { Color = Theme.Border, Transparency = 0.5 }, { Duration = 0.15 })
	end))

	local btnRow = Instance.new("Frame")
	btnRow.BackgroundTransparency = 1
	btnRow.Size = UDim2.new(1, 0, 0, Theme.ElementHeight)
	btnRow.LayoutOrder = 2
	btnRow.Parent = body

	local btnLayout = Instance.new("UIListLayout")
	btnLayout.FillDirection = Enum.FillDirection.Horizontal
	btnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	btnLayout.Padding = UDim.new(0, 8)
	btnLayout.Parent = btnRow

	local function makeBtn(name, order)
		local btn = Instance.new("TextButton")
		btn.Name = name
		btn.BackgroundColor3 = Theme.Secondary
		btn.BackgroundTransparency = 0.1
		btn.BorderSizePixel = 0
		btn.Size = UDim2.new(0.5, -4, 1, 0)
		btn.AutoButtonColor = false
		btn.Font = Theme.Font
		btn.TextSize = 13
		btn.TextColor3 = Theme.Text
		btn.Text = name
		btn.LayoutOrder = order
		btn.Parent = btnRow

		local stroke = Instance.new("UIStroke")
		stroke.Color = Theme.Border
		stroke.Thickness = 1
		stroke.Transparency = 0.5
		stroke.Parent = btn
		EnsureCorner(btn, Settings.CornerRadius or 2)

		btn.MouseEnter:Connect(function()
			if closed or splitting then return end
			TweenEngine.Play(btn, { BackgroundColor3 = Theme.Hover }, { Duration = Theme.HoverSpeed, Easing = "QuadOut" })
		end)
		btn.MouseLeave:Connect(function()
			if closed or splitting then return end
			TweenEngine.Play(btn, { BackgroundColor3 = Theme.Secondary }, { Duration = Theme.HoverSpeed, Easing = "QuadOut" })
		end)
		btn.MouseButton1Down:Connect(function()
			if closed or splitting then return end
			TweenEngine.Play(btn, { BackgroundColor3 = Theme.Tertiary }, { Duration = 0.08 })
		end)
		btn.MouseButton1Up:Connect(function()
			if closed or splitting then return end
			TweenEngine.Play(btn, { BackgroundColor3 = Theme.Hover }, { Duration = 0.1 })
		end)

		return btn
	end

	local getBtn = makeBtn("Get Key", 1)
	local enterBtn = makeBtn("Enter Key", 2)

	local bottomLabel = Instance.new("TextLabel")
	bottomLabel.BackgroundTransparency = 1
	bottomLabel.Size = UDim2.new(1, 0, 0, 28)
	bottomLabel.Font = Theme.Font
	bottomLabel.TextSize = 11
	bottomLabel.TextColor3 = Theme.SecondaryText
	bottomLabel.TextXAlignment = Enum.TextXAlignment.Center
	bottomLabel.TextYAlignment = Enum.TextYAlignment.Center
	bottomLabel.TextWrapped = true
	bottomLabel.Text = bottomText
	bottomLabel.LayoutOrder = 3
	bottomLabel.ZIndex = 10
	bottomLabel.Parent = body
	bottomLabel.Visible = (bottomText ~= "")

	local function refreshTheme()
		if closed or cleanup:IsDestroyed() then return end
		SetThemeGradient(main, "Background")
		SetThemeGradient(titleBar, "Surface") 
		mainStroke.Color = Theme.OutlineAccent or Theme.Border
		mainStroke.Transparency = 0.35
		titleLabel.TextColor3 = Theme.Text
		titleLabel.Font = Theme.FontBold
		closeBtn.TextColor3 = Theme.SecondaryText
		outline.BackgroundColor3 = Theme.OutlineAccent or Color3.fromRGB(255, 255, 255)
		boxFrame.BackgroundColor3 = Theme.Secondary
		boxStroke.Color = Theme.OutlineAccent or Theme.Border
		keyBox.Font = Theme.FontMono
		keyBox.TextColor3 = Theme.Text
		keyBox.PlaceholderColor3 = Theme.MutedText
		bottomLabel.TextColor3 = Theme.SecondaryText
		bottomLabel.Font = Theme.Font
		getBtn.BackgroundColor3 = Theme.Secondary
		getBtn.TextColor3 = Theme.Text
		getBtn.Font = Theme.Font
		enterBtn.BackgroundColor3 = Theme.Secondary
		enterBtn.TextColor3 = Theme.Text
		enterBtn.Font = Theme.Font
		DecorateGuiTree(main)
	end
	cleanup:AddCallback(OnThemeChange(refreshTheme))

	local function finishClose()
		if closed or splitting then return end
		closed = true
		TweenEngine.CancelOnObject(root)
		TweenEngine.CancelOnObject(main)
		TweenEngine.Play(dim, { BackgroundTransparency = 1 }, { Duration = 0.25, Easing = "QuadIn" })
		TweenEngine.Play(root, {
			Size = UDim2.fromOffset(0, 0),
		}, {
			Duration = 0.28,
			Easing = "QuadIn",
			OnComplete = function()
				cleanup:Destroy()
			end,
		})
		TweenEngine.Play(main, { BackgroundTransparency = 1 }, { Duration = 0.25, Easing = "QuadIn" })
		if config.OnClose then
			task.spawn(config.OnClose)
		end
	end

	local function playSplitAndOpen()
		if closed or splitting then return end
		splitting = true
		closed = true

		keyBox.TextEditable = false
		pcall(function() keyBox:ReleaseFocus() end)
		getBtn.Active = false
		enterBtn.Active = false
		closeBtn.Active = false

		if onSuccess then
			task.spawn(onSuccess)
		end

		local absW = root.AbsoluteSize.X
		local absH = root.AbsoluteSize.Y
		if absW < 10 then absW = width end
		if absH < 10 then absH = height end
		local halfW = math.floor(absW / 2)

		TweenEngine.Play(titleLabel, { TextTransparency = 1 }, { Duration = 0.15, Easing = "QuadIn" })
		TweenEngine.Play(closeBtn, { TextTransparency = 1 }, { Duration = 0.15, Easing = "QuadIn" })
		TweenEngine.Play(keyBox, { TextTransparency = 1 }, { Duration = 0.15, Easing = "QuadIn" })
		TweenEngine.Play(getBtn, { TextTransparency = 1, BackgroundTransparency = 1 }, { Duration = 0.15, Easing = "QuadIn" })
		TweenEngine.Play(enterBtn, { TextTransparency = 1, BackgroundTransparency = 1 }, { Duration = 0.15, Easing = "QuadIn" })
		TweenEngine.Play(bottomLabel, { TextTransparency = 1 }, { Duration = 0.15, Easing = "QuadIn" })
		TweenEngine.Play(boxFrame, { BackgroundTransparency = 1 }, { Duration = 0.15, Easing = "QuadIn" })
		TweenEngine.Play(boxStroke, { Transparency = 1 }, { Duration = 0.15, Easing = "QuadIn" })
		TweenEngine.Play(titleBar, { BackgroundTransparency = 1 }, { Duration = 0.18, Easing = "QuadIn" })
		TweenEngine.Play(mainStroke, { Transparency = 1 }, { Duration = 0.18, Easing = "QuadIn" })
		TweenEngine.Play(outline, { BackgroundTransparency = 1 }, { Duration = 0.12, Easing = "QuadIn" })

		local function makeHalf(name, side)
			local half = Instance.new("Frame")
			half.Name = name
			half.BackgroundColor3 = Theme.Background
			half.BackgroundTransparency = 0.02
			half.BorderSizePixel = 0
			half.ClipsDescendants = true
			half.ZIndex = 20
			half.Size = UDim2.fromOffset(halfW + 1, absH)
			half.AnchorPoint = Vector2.new(0, 0)
			half.Position = (side == "left") and UDim2.fromOffset(0, 0) or UDim2.fromOffset(halfW, 0)
			half.Parent = root
			EnsureCorner(half, Settings.CornerRadius or 2)
			SetThemeGradient(half, "Background")

			local stroke = Instance.new("UIStroke")
			stroke.Color = Theme.Border
			stroke.Thickness = 1
			stroke.Transparency = 0.45
			stroke.Parent = half

			local edge = Instance.new("Frame")
			edge.BackgroundColor3 = Theme.OutlineAccent or Color3.fromRGB(255, 255, 255)
			edge.BackgroundTransparency = 0.05
			edge.BorderSizePixel = 0
			edge.Size = UDim2.new(0, 2, 1, 0)
			edge.ZIndex = 21
			edge.Position = (side == "left") and UDim2.new(0, 0, 0, 0) or UDim2.new(1, -2, 0, 0)
			edge.Parent = half

			local seam = Instance.new("Frame")
			seam.BackgroundColor3 = Theme.Accent or Color3.fromRGB(255, 255, 255)
			seam.BackgroundTransparency = 0.55
			seam.BorderSizePixel = 0
			seam.Size = UDim2.new(0, 2, 1, 0)
			seam.ZIndex = 22
			seam.Position = (side == "left") and UDim2.new(1, -2, 0, 0) or UDim2.new(0, 0, 0, 0)
			seam.Parent = half

			return half, stroke, seam, edge
		end

		local leftHalf, leftStroke, leftSeam, leftEdge = makeHalf("LeftHalf", "left")
		local rightHalf, rightStroke, rightSeam, rightEdge = makeHalf("RightHalf", "right")
		main.Visible = false

		local travel = math.max(absW * 0.85, 200)
		local splitDur = 0.55

		TweenEngine.Play(leftSeam, { BackgroundTransparency = 0.1 }, { Duration = 0.1, Easing = "QuadOut" })
		TweenEngine.Play(rightSeam, { BackgroundTransparency = 0.1 }, { Duration = 0.1, Easing = "QuadOut" })
		TweenEngine.Play(dim, { BackgroundTransparency = 1 }, { Duration = splitDur, Easing = "QuadIn", Delay = 0.08 })

		task.delay(0.08, function()
			if cleanup:IsDestroyed() then return end

			TweenEngine.Play(leftHalf, {
				Position = UDim2.fromOffset(-travel, 0),
				BackgroundTransparency = 1,
			}, { Duration = splitDur, Easing = "ExpoOut" })
			TweenEngine.Play(leftStroke, { Transparency = 1 }, { Duration = splitDur * 0.65, Easing = "QuadIn" })
			TweenEngine.Play(leftSeam, { BackgroundTransparency = 1 }, { Duration = 0.22, Easing = "QuadIn" })
			TweenEngine.Play(leftEdge, { BackgroundTransparency = 1 }, { Duration = splitDur * 0.55, Easing = "QuadIn" })

			TweenEngine.Play(rightHalf, {
				Position = UDim2.fromOffset(halfW + travel, 0),
				BackgroundTransparency = 1,
			}, {
				Duration = splitDur,
				Easing = "ExpoOut",
				OnComplete = function()
					task.defer(function()
						cleanup:Destroy()
					end)
				end,
			})
			TweenEngine.Play(rightStroke, { Transparency = 1 }, { Duration = splitDur * 0.65, Easing = "QuadIn" })
			TweenEngine.Play(rightSeam, { BackgroundTransparency = 1 }, { Duration = 0.22, Easing = "QuadIn" })
			TweenEngine.Play(rightEdge, { BackgroundTransparency = 1 }, { Duration = splitDur * 0.55, Easing = "QuadIn" })
		end)
	end

	cleanup:AddConnection(closeBtn.MouseButton1Click:Connect(finishClose))

	cleanup:AddConnection(getBtn.MouseButton1Click:Connect(function()
		if closed or splitting then return end
		if type(getKeyFn) == "function" then
			task.spawn(getKeyFn)
			return
		end
		if link then
			local copied = tryClipboard(link)
			if Library and Library.Notify then
				Library:Notify({
					Title = copied and "Copied" or "Link",
					Description = copied and "Key link copied to clipboard" or tostring(link),
					Duration = 3,
					Type = copied and "Success" or "Info",
				})
			end
			return
		end
		if Library and Library.Notify then
			Library:Notify({
				Title = "Get Key",
				Description = "No link or GetKey callback configured",
				Duration = 3,
				Type = "Warning",
			})
		end
	end))

	local function attemptEnter()
		if closed or splitting then return end
		local key = keyBox.Text or ""
		if doValidate(key) then
			if Library and Library.Notify then
				Library:Notify({
					Title = "Success",
					Description = "Key accepted",
					Duration = 2,
					Type = "Success",
				})
			end
			playSplitAndOpen()
		else
			TweenEngine.Shake(root, { Magnitude = 5, Duration = 0.35, Frequency = 28 })
			if onFail then
				task.spawn(onFail, key)
			end
			if Library and Library.Notify then
				Library:Notify({
					Title = "Invalid Key",
					Description = "Please try again",
					Duration = 3,
					Type = "Error",
				})
			end
		end
	end

	cleanup:AddConnection(enterBtn.MouseButton1Click:Connect(attemptEnter))
	cleanup:AddConnection(keyBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			attemptEnter()
		end
	end))

	TweenEngine.Play(dim, { BackgroundTransparency = 0.45 }, { Duration = 0.35, Easing = "QuadOut" })
	main.BackgroundTransparency = 1
	TweenEngine.Play(root, {
		Size = UDim2.fromOffset(width, height),
	}, { Duration = 0.4, Easing = "BackOut" })
	TweenEngine.Play(main, { BackgroundTransparency = 0.02 }, { Duration = 0.32, Easing = "QuadOut" })

	local api = {
		Gui = gui,
		Root = root,
		Box = keyBox,
		Cleanup = cleanup,
	}

	function api:SetBottomLabel(text)
		bottomText = tostring(text or "")
		bottomLabel.Text = bottomText
		bottomLabel.Visible = (bottomText ~= "")
	end

	function api:SetTitle(text)
		titleText = tostring(text or "Key System")
		titleLabel.Text = titleText
	end

	function api:Close()
		finishClose()
	end

	function api:Destroy()
		closed = true
		splitting = false
		cleanup:Destroy()
	end

	function api:IsDestroyed()
		return closed or cleanup:IsDestroyed()
	end

	return api
end

IconAssets = {
	assets = {
		["lucide-accessibility"] = "rbxassetid://10709751939",
		["lucide-activity"] = "rbxassetid://10709752035",
		["lucide-air-vent"] = "rbxassetid://10709752131",
		["lucide-airplay"] = "rbxassetid://10709752254",
		["lucide-alarm-check"] = "rbxassetid://10709752405",
		["lucide-alarm-clock"] = "rbxassetid://10709752630",
		["lucide-alarm-clock-off"] = "rbxassetid://10709752508",
		["lucide-alarm-minus"] = "rbxassetid://10709752732",
		["lucide-alarm-plus"] = "rbxassetid://10709752825",
		["lucide-album"] = "rbxassetid://10709752906",
		["lucide-alert-circle"] = "rbxassetid://10709752996",
		["lucide-alert-octagon"] = "rbxassetid://10709753064",
		["lucide-alert-triangle"] = "rbxassetid://10709753149",
		["lucide-align-center"] = "rbxassetid://10709753570",
		["lucide-align-center-horizontal"] = "rbxassetid://10709753272",
		["lucide-align-center-vertical"] = "rbxassetid://10709753421",
		["lucide-align-end-horizontal"] = "rbxassetid://10709753692",
		["lucide-align-end-vertical"] = "rbxassetid://10709753808",
		["lucide-align-horizontal-distribute-center"] = "rbxassetid://10747779791",
		["lucide-align-horizontal-distribute-end"] = "rbxassetid://10747784534",
		["lucide-align-horizontal-distribute-start"] = "rbxassetid://10709754118",
		["lucide-align-horizontal-justify-center"] = "rbxassetid://10709754204",
		["lucide-align-horizontal-justify-end"] = "rbxassetid://10709754317",
		["lucide-align-horizontal-justify-start"] = "rbxassetid://10709754436",
		["lucide-align-horizontal-space-around"] = "rbxassetid://10709754590",
		["lucide-align-horizontal-space-between"] = "rbxassetid://10709754749",
		["lucide-align-justify"] = "rbxassetid://10709759610",
		["lucide-align-left"] = "rbxassetid://10709759764",
		["lucide-align-right"] = "rbxassetid://10709759895",
		["lucide-align-start-horizontal"] = "rbxassetid://10709760051",
		["lucide-align-start-vertical"] = "rbxassetid://10709760244",
		["lucide-align-vertical-distribute-center"] = "rbxassetid://10709760351",
		["lucide-align-vertical-distribute-end"] = "rbxassetid://10709760434",
		["lucide-align-vertical-distribute-start"] = "rbxassetid://10709760612",
		["lucide-align-vertical-justify-center"] = "rbxassetid://10709760814",
		["lucide-align-vertical-justify-end"] = "rbxassetid://10709761003",
		["lucide-align-vertical-justify-start"] = "rbxassetid://10709761176",
		["lucide-align-vertical-space-around"] = "rbxassetid://10709761324",
		["lucide-align-vertical-space-between"] = "rbxassetid://10709761434",
		["lucide-anchor"] = "rbxassetid://10709761530",
		["lucide-angry"] = "rbxassetid://10709761629",
		["lucide-annoyed"] = "rbxassetid://10709761722",
		["lucide-aperture"] = "rbxassetid://10709761813",
		["lucide-apple"] = "rbxassetid://10709761889",
		["lucide-archive"] = "rbxassetid://10709762233",
		["lucide-archive-restore"] = "rbxassetid://10709762058",
		["lucide-armchair"] = "rbxassetid://10709762327",
		["lucide-arrow-big-down"] = "rbxassetid://10747796644",
		["lucide-arrow-big-left"] = "rbxassetid://10709762574",
		["lucide-arrow-big-right"] = "rbxassetid://10709762727",
		["lucide-arrow-big-up"] = "rbxassetid://10709762879",
		["lucide-arrow-down"] = "rbxassetid://10709767827",
		["lucide-arrow-down-circle"] = "rbxassetid://10709763034",
		["lucide-arrow-down-left"] = "rbxassetid://10709767656",
		["lucide-arrow-down-right"] = "rbxassetid://10709767750",
		["lucide-arrow-left"] = "rbxassetid://10709768114",
		["lucide-arrow-left-circle"] = "rbxassetid://10709767936",
		["lucide-arrow-left-right"] = "rbxassetid://10709768019",
		["lucide-arrow-right"] = "rbxassetid://10709768347",
		["lucide-arrow-right-circle"] = "rbxassetid://10709768226",
		["lucide-arrow-up"] = "rbxassetid://10709768939",
		["lucide-arrow-up-circle"] = "rbxassetid://10709768432",
		["lucide-arrow-up-down"] = "rbxassetid://10709768538",
		["lucide-arrow-up-left"] = "rbxassetid://10709768661",
		["lucide-arrow-up-right"] = "rbxassetid://10709768787",
		["lucide-asterisk"] = "rbxassetid://10709769095",
		["lucide-at-sign"] = "rbxassetid://10709769286",
		["lucide-award"] = "rbxassetid://10709769406",
		["lucide-axe"] = "rbxassetid://10709769508",
		["lucide-axis-3d"] = "rbxassetid://10709769598",
		["lucide-baby"] = "rbxassetid://10709769732",
		["lucide-backpack"] = "rbxassetid://10709769841",
		["lucide-baggage-claim"] = "rbxassetid://10709769935",
		["lucide-banana"] = "rbxassetid://10709770005",
		["lucide-banknote"] = "rbxassetid://10709770178",
		["lucide-bar-chart"] = "rbxassetid://10709773755",
		["lucide-bar-chart-2"] = "rbxassetid://10709770317",
		["lucide-bar-chart-3"] = "rbxassetid://10709770431",
		["lucide-bar-chart-4"] = "rbxassetid://10709770560",
		["lucide-bar-chart-horizontal"] = "rbxassetid://10709773669",
		["lucide-barcode"] = "rbxassetid://10747360675",
		["lucide-baseline"] = "rbxassetid://10709773863",
		["lucide-bath"] = "rbxassetid://10709773963",
		["lucide-battery"] = "rbxassetid://10709774640",
		["lucide-battery-charging"] = "rbxassetid://10709774068",
		["lucide-battery-full"] = "rbxassetid://10709774206",
		["lucide-battery-low"] = "rbxassetid://10709774370",
		["lucide-battery-medium"] = "rbxassetid://10709774513",
		["lucide-beaker"] = "rbxassetid://10709774756",
		["lucide-bed"] = "rbxassetid://10709775036",
		["lucide-bed-double"] = "rbxassetid://10709774864",
		["lucide-bed-single"] = "rbxassetid://10709774968",
		["lucide-beer"] = "rbxassetid://10709775167",
		["lucide-bell"] = "rbxassetid://10709775704",
		["lucide-bell-minus"] = "rbxassetid://10709775241",
		["lucide-bell-off"] = "rbxassetid://10709775320",
		["lucide-bell-plus"] = "rbxassetid://10709775448",
		["lucide-bell-ring"] = "rbxassetid://10709775560",
		["lucide-bike"] = "rbxassetid://10709775894",
		["lucide-binary"] = "rbxassetid://10709776050",
		["lucide-bitcoin"] = "rbxassetid://10709776126",
		["lucide-bluetooth"] = "rbxassetid://10709776655",
		["lucide-bluetooth-connected"] = "rbxassetid://10709776240",
		["lucide-bluetooth-off"] = "rbxassetid://10709776344",
		["lucide-bluetooth-searching"] = "rbxassetid://10709776501",
		["lucide-bold"] = "rbxassetid://10747813908",
		["lucide-bomb"] = "rbxassetid://10709781460",
		["lucide-bone"] = "rbxassetid://10709781605",
		["lucide-book"] = "rbxassetid://10709781824",
		["lucide-book-open"] = "rbxassetid://10709781717",
		["lucide-bookmark"] = "rbxassetid://10709782154",
		["lucide-bookmark-minus"] = "rbxassetid://10709781919",
		["lucide-bookmark-plus"] = "rbxassetid://10709782044",
		["lucide-bot"] = "rbxassetid://10709782230",
		["lucide-box"] = "rbxassetid://10709782497",
		["lucide-box-select"] = "rbxassetid://10709782342",
		["lucide-boxes"] = "rbxassetid://10709782582",
		["lucide-briefcase"] = "rbxassetid://10709782662",
		["lucide-brush"] = "rbxassetid://10709782758",
		["lucide-bug"] = "rbxassetid://10709782845",
		["lucide-building"] = "rbxassetid://10709783051",
		["lucide-building-2"] = "rbxassetid://10709782939",
		["lucide-bus"] = "rbxassetid://10709783137",
		["lucide-cake"] = "rbxassetid://10709783217",
		["lucide-calculator"] = "rbxassetid://10709783311",
		["lucide-calendar"] = "rbxassetid://10709789505",
		["lucide-calendar-check"] = "rbxassetid://10709783474",
		["lucide-calendar-check-2"] = "rbxassetid://10709783392",
		["lucide-calendar-clock"] = "rbxassetid://10709783577",
		["lucide-calendar-days"] = "rbxassetid://10709783673",
		["lucide-calendar-heart"] = "rbxassetid://10709783835",
		["lucide-calendar-minus"] = "rbxassetid://10709783959",
		["lucide-calendar-off"] = "rbxassetid://10709788784",
		["lucide-calendar-plus"] = "rbxassetid://10709788937",
		["lucide-calendar-range"] = "rbxassetid://10709789053",
		["lucide-calendar-search"] = "rbxassetid://10709789200",
		["lucide-calendar-x"] = "rbxassetid://10709789407",
		["lucide-calendar-x-2"] = "rbxassetid://10709789329",
		["lucide-camera"] = "rbxassetid://10709789686",
		["lucide-camera-off"] = "rbxassetid://10747822677",
		["lucide-car"] = "rbxassetid://10709789810",
		["lucide-carrot"] = "rbxassetid://10709789960",
		["lucide-cast"] = "rbxassetid://10709790097",
		["lucide-charge"] = "rbxassetid://10709790202",
		["lucide-check"] = "rbxassetid://10709790644",
		["lucide-check-circle"] = "rbxassetid://10709790387",
		["lucide-check-circle-2"] = "rbxassetid://10709790298",
		["lucide-check-square"] = "rbxassetid://10709790537",
		["lucide-chef-hat"] = "rbxassetid://10709790757",
		["lucide-cherry"] = "rbxassetid://10709790875",
		["lucide-chevron-down"] = "rbxassetid://10709790948",
		["lucide-chevron-first"] = "rbxassetid://10709791015",
		["lucide-chevron-last"] = "rbxassetid://10709791130",
		["lucide-chevron-left"] = "rbxassetid://10709791281",
		["lucide-chevron-right"] = "rbxassetid://10709791437",
		["lucide-chevron-up"] = "rbxassetid://10709791523",
		["lucide-chevrons-down"] = "rbxassetid://10709796864",
		["lucide-chevrons-down-up"] = "rbxassetid://10709791632",
		["lucide-chevrons-left"] = "rbxassetid://10709797151",
		["lucide-chevrons-left-right"] = "rbxassetid://10709797006",
		["lucide-chevrons-right"] = "rbxassetid://10709797382",
		["lucide-chevrons-right-left"] = "rbxassetid://10709797274",
		["lucide-chevrons-up"] = "rbxassetid://10709797622",
		["lucide-chevrons-up-down"] = "rbxassetid://10709797508",
		["lucide-chrome"] = "rbxassetid://10709797725",
		["lucide-circle"] = "rbxassetid://10709798174",
		["lucide-circle-dot"] = "rbxassetid://10709797837",
		["lucide-circle-ellipsis"] = "rbxassetid://10709797985",
		["lucide-circle-slashed"] = "rbxassetid://10709798100",
		["lucide-citrus"] = "rbxassetid://10709798276",
		["lucide-clapperboard"] = "rbxassetid://10709798350",
		["lucide-clipboard"] = "rbxassetid://10709799288",
		["lucide-clipboard-check"] = "rbxassetid://10709798443",
		["lucide-clipboard-copy"] = "rbxassetid://10709798574",
		["lucide-clipboard-edit"] = "rbxassetid://10709798682",
		["lucide-clipboard-list"] = "rbxassetid://10709798792",
		["lucide-clipboard-signature"] = "rbxassetid://10709798890",
		["lucide-clipboard-type"] = "rbxassetid://10709798999",
		["lucide-clipboard-x"] = "rbxassetid://10709799124",
		["lucide-clock"] = "rbxassetid://10709805144",
		["lucide-clock-1"] = "rbxassetid://10709799535",
		["lucide-clock-10"] = "rbxassetid://10709799718",
		["lucide-clock-11"] = "rbxassetid://10709799818",
		["lucide-clock-12"] = "rbxassetid://10709799962",
		["lucide-clock-2"] = "rbxassetid://10709803876",
		["lucide-clock-3"] = "rbxassetid://10709803989",
		["lucide-clock-4"] = "rbxassetid://10709804164",
		["lucide-clock-5"] = "rbxassetid://10709804291",
		["lucide-clock-6"] = "rbxassetid://10709804435",
		["lucide-clock-7"] = "rbxassetid://10709804599",
		["lucide-clock-8"] = "rbxassetid://10709804784",
		["lucide-clock-9"] = "rbxassetid://10709804996",
		["lucide-cloud"] = "rbxassetid://10709806740",
		["lucide-cloud-cog"] = "rbxassetid://10709805262",
		["lucide-cloud-drizzle"] = "rbxassetid://10709805371",
		["lucide-cloud-fog"] = "rbxassetid://10709805477",
		["lucide-cloud-hail"] = "rbxassetid://10709805596",
		["lucide-cloud-lightning"] = "rbxassetid://10709805727",
		["lucide-cloud-moon"] = "rbxassetid://10709805942",
		["lucide-cloud-moon-rain"] = "rbxassetid://10709805838",
		["lucide-cloud-off"] = "rbxassetid://10709806060",
		["lucide-cloud-rain"] = "rbxassetid://10709806277",
		["lucide-cloud-rain-wind"] = "rbxassetid://10709806166",
		["lucide-cloud-snow"] = "rbxassetid://10709806374",
		["lucide-cloud-sun"] = "rbxassetid://10709806631",
		["lucide-cloud-sun-rain"] = "rbxassetid://10709806475",
		["lucide-cloudy"] = "rbxassetid://10709806859",
		["lucide-clover"] = "rbxassetid://10709806995",
		["lucide-code"] = "rbxassetid://10709810463",
		["lucide-code-2"] = "rbxassetid://10709807111",
		["lucide-codepen"] = "rbxassetid://10709810534",
		["lucide-codesandbox"] = "rbxassetid://10709810676",
		["lucide-coffee"] = "rbxassetid://10709810814",
		["lucide-cog"] = "rbxassetid://10709810948",
		["lucide-coins"] = "rbxassetid://10709811110",
		["lucide-columns"] = "rbxassetid://10709811261",
		["lucide-command"] = "rbxassetid://10709811365",
		["lucide-compass"] = "rbxassetid://10709811445",
		["lucide-component"] = "rbxassetid://10709811595",
		["lucide-concierge-bell"] = "rbxassetid://10709811706",
		["lucide-connection"] = "rbxassetid://10747361219",
		["lucide-contact"] = "rbxassetid://10709811834",
		["lucide-contrast"] = "rbxassetid://10709811939",
		["lucide-cookie"] = "rbxassetid://10709812067",
		["lucide-copy"] = "rbxassetid://10709812159",
		["lucide-copyleft"] = "rbxassetid://10709812251",
		["lucide-copyright"] = "rbxassetid://10709812311",
		["lucide-corner-down-left"] = "rbxassetid://10709812396",
		["lucide-corner-down-right"] = "rbxassetid://10709812485",
		["lucide-corner-left-down"] = "rbxassetid://10709812632",
		["lucide-corner-left-up"] = "rbxassetid://10709812784",
		["lucide-corner-right-down"] = "rbxassetid://10709812939",
		["lucide-corner-right-up"] = "rbxassetid://10709813094",
		["lucide-corner-up-left"] = "rbxassetid://10709813185",
		["lucide-corner-up-right"] = "rbxassetid://10709813281",
		["lucide-cpu"] = "rbxassetid://10709813383",
		["lucide-croissant"] = "rbxassetid://10709818125",
		["lucide-crop"] = "rbxassetid://10709818245",
		["lucide-cross"] = "rbxassetid://10709818399",
		["lucide-crosshair"] = "rbxassetid://10709818534",
		["lucide-crown"] = "rbxassetid://10709818626",
		["lucide-cup-soda"] = "rbxassetid://10709818763",
		["lucide-curly-braces"] = "rbxassetid://10709818847",
		["lucide-currency"] = "rbxassetid://10709818931",
		["lucide-database"] = "rbxassetid://10709818996",
		["lucide-delete"] = "rbxassetid://10709819059",
		["lucide-diamond"] = "rbxassetid://10709819149",
		["lucide-dice-1"] = "rbxassetid://10709819266",
		["lucide-dice-2"] = "rbxassetid://10709819361",
		["lucide-dice-3"] = "rbxassetid://10709819508",
		["lucide-dice-4"] = "rbxassetid://10709819670",
		["lucide-dice-5"] = "rbxassetid://10709819801",
		["lucide-dice-6"] = "rbxassetid://10709819896",
		["lucide-dices"] = "rbxassetid://10723343321",
		["lucide-diff"] = "rbxassetid://10723343416",
		["lucide-disc"] = "rbxassetid://10723343537",
		["lucide-divide"] = "rbxassetid://10723343805",
		["lucide-divide-circle"] = "rbxassetid://10723343636",
		["lucide-divide-square"] = "rbxassetid://10723343737",
		["lucide-dollar-sign"] = "rbxassetid://10723343958",
		["lucide-download"] = "rbxassetid://10723344270",
		["lucide-download-cloud"] = "rbxassetid://10723344088",
		["lucide-droplet"] = "rbxassetid://10723344432",
		["lucide-droplets"] = "rbxassetid://10734883356",
		["lucide-drumstick"] = "rbxassetid://10723344737",
		["lucide-edit"] = "rbxassetid://10734883598",
		["lucide-edit-2"] = "rbxassetid://10723344885",
		["lucide-edit-3"] = "rbxassetid://10723345088",
		["lucide-egg"] = "rbxassetid://10723345518",
		["lucide-egg-fried"] = "rbxassetid://10723345347",
		["lucide-electricity"] = "rbxassetid://10723345749",
		["lucide-electricity-off"] = "rbxassetid://10723345643",
		["lucide-equal"] = "rbxassetid://10723345990",
		["lucide-equal-not"] = "rbxassetid://10723345866",
		["lucide-eraser"] = "rbxassetid://10723346158",
		["lucide-euro"] = "rbxassetid://10723346372",
		["lucide-expand"] = "rbxassetid://10723346553",
		["lucide-external-link"] = "rbxassetid://10723346684",
		["lucide-eye"] = "rbxassetid://10723346959",
		["lucide-eye-off"] = "rbxassetid://10723346871",
		["lucide-factory"] = "rbxassetid://10723347051",
		["lucide-fan"] = "rbxassetid://10723354359",
		["lucide-fast-forward"] = "rbxassetid://10723354521",
		["lucide-feather"] = "rbxassetid://10723354671",
		["lucide-figma"] = "rbxassetid://10723354801",
		["lucide-file"] = "rbxassetid://10723374641",
		["lucide-file-archive"] = "rbxassetid://10723354921",
		["lucide-file-audio"] = "rbxassetid://10723355148",
		["lucide-file-audio-2"] = "rbxassetid://10723355026",
		["lucide-file-axis-3d"] = "rbxassetid://10723355272",
		["lucide-file-badge"] = "rbxassetid://10723355622",
		["lucide-file-badge-2"] = "rbxassetid://10723355451",
		["lucide-file-bar-chart"] = "rbxassetid://10723355887",
		["lucide-file-bar-chart-2"] = "rbxassetid://10723355746",
		["lucide-file-box"] = "rbxassetid://10723355989",
		["lucide-file-check"] = "rbxassetid://10723356210",
		["lucide-file-check-2"] = "rbxassetid://10723356100",
		["lucide-file-clock"] = "rbxassetid://10723356329",
		["lucide-file-code"] = "rbxassetid://10723356507",
		["lucide-file-cog"] = "rbxassetid://10723356830",
		["lucide-file-cog-2"] = "rbxassetid://10723356676",
		["lucide-file-diff"] = "rbxassetid://10723357039",
		["lucide-file-digit"] = "rbxassetid://10723357151",
		["lucide-file-down"] = "rbxassetid://10723357322",
		["lucide-file-edit"] = "rbxassetid://10723357495",
		["lucide-file-heart"] = "rbxassetid://10723357637",
		["lucide-file-image"] = "rbxassetid://10723357790",
		["lucide-file-input"] = "rbxassetid://10723357933",
		["lucide-file-json"] = "rbxassetid://10723364435",
		["lucide-file-json-2"] = "rbxassetid://10723364361",
		["lucide-file-key"] = "rbxassetid://10723364605",
		["lucide-file-key-2"] = "rbxassetid://10723364515",
		["lucide-file-line-chart"] = "rbxassetid://10723364725",
		["lucide-file-lock"] = "rbxassetid://10723364957",
		["lucide-file-lock-2"] = "rbxassetid://10723364861",
		["lucide-file-minus"] = "rbxassetid://10723365254",
		["lucide-file-minus-2"] = "rbxassetid://10723365086",
		["lucide-file-output"] = "rbxassetid://10723365457",
		["lucide-file-pie-chart"] = "rbxassetid://10723365598",
		["lucide-file-plus"] = "rbxassetid://10723365877",
		["lucide-file-plus-2"] = "rbxassetid://10723365766",
		["lucide-file-question"] = "rbxassetid://10723365987",
		["lucide-file-scan"] = "rbxassetid://10723366167",
		["lucide-file-search"] = "rbxassetid://10723366550",
		["lucide-file-search-2"] = "rbxassetid://10723366340",
		["lucide-file-signature"] = "rbxassetid://10723366741",
		["lucide-file-spreadsheet"] = "rbxassetid://10723366962",
		["lucide-file-symlink"] = "rbxassetid://10723367098",
		["lucide-file-terminal"] = "rbxassetid://10723367244",
		["lucide-file-text"] = "rbxassetid://10723367380",
		["lucide-file-type"] = "rbxassetid://10723367606",
		["lucide-file-type-2"] = "rbxassetid://10723367509",
		["lucide-file-up"] = "rbxassetid://10723367734",
		["lucide-file-video"] = "rbxassetid://10723373884",
		["lucide-file-video-2"] = "rbxassetid://10723367834",
		["lucide-file-volume"] = "rbxassetid://10723374172",
		["lucide-file-volume-2"] = "rbxassetid://10723374030",
		["lucide-file-warning"] = "rbxassetid://10723374276",
		["lucide-file-x"] = "rbxassetid://10723374544",
		["lucide-file-x-2"] = "rbxassetid://10723374378",
		["lucide-files"] = "rbxassetid://10723374759",
		["lucide-film"] = "rbxassetid://10723374981",
		["lucide-filter"] = "rbxassetid://10723375128",
		["lucide-fingerprint"] = "rbxassetid://10723375250",
		["lucide-flag"] = "rbxassetid://10723375890",
		["lucide-flag-off"] = "rbxassetid://10723375443",
		["lucide-flag-triangle-left"] = "rbxassetid://10723375608",
		["lucide-flag-triangle-right"] = "rbxassetid://10723375727",
		["lucide-flame"] = "rbxassetid://10723376114",
		["lucide-flashlight"] = "rbxassetid://10723376471",
		["lucide-flashlight-off"] = "rbxassetid://10723376365",
		["lucide-flask-conical"] = "rbxassetid://10734883986",
		["lucide-flask-round"] = "rbxassetid://10723376614",
		["lucide-flip-horizontal"] = "rbxassetid://10723376884",
		["lucide-flip-horizontal-2"] = "rbxassetid://10723376745",
		["lucide-flip-vertical"] = "rbxassetid://10723377138",
		["lucide-flip-vertical-2"] = "rbxassetid://10723377026",
		["lucide-flower"] = "rbxassetid://10747830374",
		["lucide-flower-2"] = "rbxassetid://10723377305",
		["lucide-focus"] = "rbxassetid://10723377537",
		["lucide-folder"] = "rbxassetid://10723387563",
		["lucide-folder-archive"] = "rbxassetid://10723384478",
		["lucide-folder-check"] = "rbxassetid://10723384605",
		["lucide-folder-clock"] = "rbxassetid://10723384731",
		["lucide-folder-closed"] = "rbxassetid://10723384893",
		["lucide-folder-cog"] = "rbxassetid://10723385213",
		["lucide-folder-cog-2"] = "rbxassetid://10723385036",
		["lucide-folder-down"] = "rbxassetid://10723385338",
		["lucide-folder-edit"] = "rbxassetid://10723385445",
		["lucide-folder-heart"] = "rbxassetid://10723385545",
		["lucide-folder-input"] = "rbxassetid://10723385721",
		["lucide-folder-key"] = "rbxassetid://10723385848",
		["lucide-folder-lock"] = "rbxassetid://10723386005",
		["lucide-folder-minus"] = "rbxassetid://10723386127",
		["lucide-folder-open"] = "rbxassetid://10723386277",
		["lucide-folder-output"] = "rbxassetid://10723386386",
		["lucide-folder-plus"] = "rbxassetid://10723386531",
		["lucide-folder-search"] = "rbxassetid://10723386787",
		["lucide-folder-search-2"] = "rbxassetid://10723386674",
		["lucide-folder-symlink"] = "rbxassetid://10723386930",
		["lucide-folder-tree"] = "rbxassetid://10723387085",
		["lucide-folder-up"] = "rbxassetid://10723387265",
		["lucide-folder-x"] = "rbxassetid://10723387448",
		["lucide-folders"] = "rbxassetid://10723387721",
		["lucide-form-input"] = "rbxassetid://10723387841",
		["lucide-forward"] = "rbxassetid://10723388016",
		["lucide-frame"] = "rbxassetid://10723394389",
		["lucide-framer"] = "rbxassetid://10723394565",
		["lucide-frown"] = "rbxassetid://10723394681",
		["lucide-fuel"] = "rbxassetid://10723394846",
		["lucide-function-square"] = "rbxassetid://10723395041",
		["lucide-gamepad"] = "rbxassetid://10723395457",
		["lucide-gamepad-2"] = "rbxassetid://10723395215",
		["lucide-gauge"] = "rbxassetid://10723395708",
		["lucide-gavel"] = "rbxassetid://10723395896",
		["lucide-gem"] = "rbxassetid://10723396000",
		["lucide-ghost"] = "rbxassetid://10723396107",
		["lucide-gift"] = "rbxassetid://10723396402",
		["lucide-gift-card"] = "rbxassetid://10723396225",
		["lucide-git-branch"] = "rbxassetid://10723396676",
		["lucide-git-branch-plus"] = "rbxassetid://10723396542",
		["lucide-git-commit"] = "rbxassetid://10723396812",
		["lucide-git-compare"] = "rbxassetid://10723396954",
		["lucide-git-fork"] = "rbxassetid://10723397049",
		["lucide-git-merge"] = "rbxassetid://10723397165",
		["lucide-git-pull-request"] = "rbxassetid://10723397431",
		["lucide-git-pull-request-closed"] = "rbxassetid://10723397268",
		["lucide-git-pull-request-draft"] = "rbxassetid://10734884302",
		["lucide-glass"] = "rbxassetid://10723397788",
		["lucide-glass-2"] = "rbxassetid://10723397529",
		["lucide-glass-water"] = "rbxassetid://10723397678",
		["lucide-glasses"] = "rbxassetid://10723397895",
		["lucide-globe"] = "rbxassetid://10723404337",
		["lucide-globe-2"] = "rbxassetid://10723398002",
		["lucide-grab"] = "rbxassetid://10723404472",
		["lucide-graduation-cap"] = "rbxassetid://10723404691",
		["lucide-grape"] = "rbxassetid://10723404822",
		["lucide-grid"] = "rbxassetid://10723404936",
		["lucide-grip-horizontal"] = "rbxassetid://10723405089",
		["lucide-grip-vertical"] = "rbxassetid://10723405236",
		["lucide-hammer"] = "rbxassetid://10723405360",
		["lucide-hand"] = "rbxassetid://10723405649",
		["lucide-hand-metal"] = "rbxassetid://10723405508",
		["lucide-hard-drive"] = "rbxassetid://10723405749",
		["lucide-hard-hat"] = "rbxassetid://10723405859",
		["lucide-hash"] = "rbxassetid://10723405975",
		["lucide-haze"] = "rbxassetid://10723406078",
		["lucide-headphones"] = "rbxassetid://10723406165",
		["lucide-heart"] = "rbxassetid://10723406885",
		["lucide-heart-crack"] = "rbxassetid://10723406299",
		["lucide-heart-handshake"] = "rbxassetid://10723406480",
		["lucide-heart-off"] = "rbxassetid://10723406662",
		["lucide-heart-pulse"] = "rbxassetid://10723406795",
		["lucide-help-circle"] = "rbxassetid://10723406988",
		["lucide-hexagon"] = "rbxassetid://10723407092",
		["lucide-highlighter"] = "rbxassetid://10723407192",
		["lucide-history"] = "rbxassetid://10723407335",
		["lucide-home"] = "rbxassetid://10723407389",
		["lucide-hourglass"] = "rbxassetid://10723407498",
		["lucide-ice-cream"] = "rbxassetid://10723414308",
		["lucide-image"] = "rbxassetid://10723415040",
		["lucide-image-minus"] = "rbxassetid://10723414487",
		["lucide-image-off"] = "rbxassetid://10723414677",
		["lucide-image-plus"] = "rbxassetid://10723414827",
		["lucide-import"] = "rbxassetid://10723415205",
		["lucide-inbox"] = "rbxassetid://10723415335",
		["lucide-indent"] = "rbxassetid://10723415494",
		["lucide-indian-rupee"] = "rbxassetid://10723415642",
		["lucide-infinity"] = "rbxassetid://10723415766",
		["lucide-info"] = "rbxassetid://10723415903",
		["lucide-inspect"] = "rbxassetid://10723416057",
		["lucide-italic"] = "rbxassetid://10723416195",
		["lucide-japanese-yen"] = "rbxassetid://10723416363",
		["lucide-joystick"] = "rbxassetid://10723416527",
		["lucide-key"] = "rbxassetid://10723416652",
		["lucide-keyboard"] = "rbxassetid://10723416765",
		["lucide-lamp"] = "rbxassetid://10723417513",
		["lucide-lamp-ceiling"] = "rbxassetid://10723416922",
		["lucide-lamp-desk"] = "rbxassetid://10723417016",
		["lucide-lamp-floor"] = "rbxassetid://10723417131",
		["lucide-lamp-wall-down"] = "rbxassetid://10723417240",
		["lucide-lamp-wall-up"] = "rbxassetid://10723417356",
		["lucide-landmark"] = "rbxassetid://10723417608",
		["lucide-languages"] = "rbxassetid://10723417703",
		["lucide-laptop"] = "rbxassetid://10723423881",
		["lucide-laptop-2"] = "rbxassetid://10723417797",
		["lucide-lasso"] = "rbxassetid://10723424235",
		["lucide-lasso-select"] = "rbxassetid://10723424058",
		["lucide-laugh"] = "rbxassetid://10723424372",
		["lucide-layers"] = "rbxassetid://10723424505",
		["lucide-layout"] = "rbxassetid://10723425376",
		["lucide-layout-dashboard"] = "rbxassetid://10723424646",
		["lucide-layout-grid"] = "rbxassetid://10723424838",
		["lucide-layout-list"] = "rbxassetid://10723424963",
		["lucide-layout-template"] = "rbxassetid://10723425187",
		["lucide-leaf"] = "rbxassetid://10723425539",
		["lucide-library"] = "rbxassetid://10723425615",
		["lucide-life-buoy"] = "rbxassetid://10723425685",
		["lucide-lightbulb"] = "rbxassetid://10723425852",
		["lucide-lightbulb-off"] = "rbxassetid://10723425762",
		["lucide-line-chart"] = "rbxassetid://10723426393",
		["lucide-link"] = "rbxassetid://10723426722",
		["lucide-link-2"] = "rbxassetid://10723426595",
		["lucide-link-2-off"] = "rbxassetid://10723426513",
		["lucide-list"] = "rbxassetid://10723433811",
		["lucide-list-checks"] = "rbxassetid://10734884548",
		["lucide-list-end"] = "rbxassetid://10723426886",
		["lucide-list-minus"] = "rbxassetid://10723426986",
		["lucide-list-music"] = "rbxassetid://10723427081",
		["lucide-list-ordered"] = "rbxassetid://10723427199",
		["lucide-list-plus"] = "rbxassetid://10723427334",
		["lucide-list-start"] = "rbxassetid://10723427494",
		["lucide-list-video"] = "rbxassetid://10723427619",
		["lucide-list-x"] = "rbxassetid://10723433655",
		["lucide-loader"] = "rbxassetid://10723434070",
		["lucide-loader-2"] = "rbxassetid://10723433935",
		["lucide-locate"] = "rbxassetid://10723434557",
		["lucide-locate-fixed"] = "rbxassetid://10723434236",
		["lucide-locate-off"] = "rbxassetid://10723434379",
		["lucide-lock"] = "rbxassetid://10723434711",
		["lucide-log-in"] = "rbxassetid://10723434830",
		["lucide-log-out"] = "rbxassetid://10723434906",
		["lucide-luggage"] = "rbxassetid://10723434993",
		["lucide-magnet"] = "rbxassetid://10723435069",
		["lucide-mail"] = "rbxassetid://10734885430",
		["lucide-mail-check"] = "rbxassetid://10723435182",
		["lucide-mail-minus"] = "rbxassetid://10723435261",
		["lucide-mail-open"] = "rbxassetid://10723435342",
		["lucide-mail-plus"] = "rbxassetid://10723435443",
		["lucide-mail-question"] = "rbxassetid://10723435515",
		["lucide-mail-search"] = "rbxassetid://10734884739",
		["lucide-mail-warning"] = "rbxassetid://10734885015",
		["lucide-mail-x"] = "rbxassetid://10734885247",
		["lucide-mails"] = "rbxassetid://10734885614",
		["lucide-map"] = "rbxassetid://10734886202",
		["lucide-map-pin"] = "rbxassetid://10734886004",
		["lucide-map-pin-off"] = "rbxassetid://10734885803",
		["lucide-maximize"] = "rbxassetid://10734886735",
		["lucide-maximize-2"] = "rbxassetid://10734886496",
		["lucide-medal"] = "rbxassetid://10734887072",
		["lucide-megaphone"] = "rbxassetid://10734887454",
		["lucide-megaphone-off"] = "rbxassetid://10734887311",
		["lucide-meh"] = "rbxassetid://10734887603",
		["lucide-menu"] = "rbxassetid://10734887784",
		["lucide-message-circle"] = "rbxassetid://10734888000",
		["lucide-message-square"] = "rbxassetid://10734888228",
		["lucide-mic"] = "rbxassetid://10734888864",
		["lucide-mic-2"] = "rbxassetid://10734888430",
		["lucide-mic-off"] = "rbxassetid://10734888646",
		["lucide-microscope"] = "rbxassetid://10734889106",
		["lucide-microwave"] = "rbxassetid://10734895076",
		["lucide-milestone"] = "rbxassetid://10734895310",
		["lucide-minimize"] = "rbxassetid://10734895698",
		["lucide-minimize-2"] = "rbxassetid://10734895530",
		["lucide-minus"] = "rbxassetid://10734896206",
		["lucide-minus-circle"] = "rbxassetid://10734895856",
		["lucide-minus-square"] = "rbxassetid://10734896029",
		["lucide-monitor"] = "rbxassetid://10734896881",
		["lucide-monitor-off"] = "rbxassetid://10734896360",
		["lucide-monitor-speaker"] = "rbxassetid://10734896512",
		["lucide-moon"] = "rbxassetid://10734897102",
		["lucide-more-horizontal"] = "rbxassetid://10734897250",
		["lucide-more-vertical"] = "rbxassetid://10734897387",
		["lucide-mountain"] = "rbxassetid://10734897956",
		["lucide-mountain-snow"] = "rbxassetid://10734897665",
		["lucide-mouse"] = "rbxassetid://10734898592",
		["lucide-mouse-pointer"] = "rbxassetid://10734898476",
		["lucide-mouse-pointer-2"] = "rbxassetid://10734898194",
		["lucide-mouse-pointer-click"] = "rbxassetid://10734898355",
		["lucide-move"] = "rbxassetid://10734900011",
		["lucide-move-3d"] = "rbxassetid://10734898756",
		["lucide-move-diagonal"] = "rbxassetid://10734899164",
		["lucide-move-diagonal-2"] = "rbxassetid://10734898934",
		["lucide-move-horizontal"] = "rbxassetid://10734899414",
		["lucide-move-vertical"] = "rbxassetid://10734899821",
		["lucide-music"] = "rbxassetid://10734905958",
		["lucide-music-2"] = "rbxassetid://10734900215",
		["lucide-music-3"] = "rbxassetid://10734905665",
		["lucide-music-4"] = "rbxassetid://10734905823",
		["lucide-navigation"] = "rbxassetid://10734906744",
		["lucide-navigation-2"] = "rbxassetid://10734906332",
		["lucide-navigation-2-off"] = "rbxassetid://10734906144",
		["lucide-navigation-off"] = "rbxassetid://10734906580",
		["lucide-network"] = "rbxassetid://10734906975",
		["lucide-newspaper"] = "rbxassetid://10734907168",
		["lucide-octagon"] = "rbxassetid://10734907361",
		["lucide-option"] = "rbxassetid://10734907649",
		["lucide-outdent"] = "rbxassetid://10734907933",
		["lucide-package"] = "rbxassetid://10734909540",
		["lucide-package-2"] = "rbxassetid://10734908151",
		["lucide-package-check"] = "rbxassetid://10734908384",
		["lucide-package-minus"] = "rbxassetid://10734908626",
		["lucide-package-open"] = "rbxassetid://10734908793",
		["lucide-package-plus"] = "rbxassetid://10734909016",
		["lucide-package-search"] = "rbxassetid://10734909196",
		["lucide-package-x"] = "rbxassetid://10734909375",
		["lucide-paint-bucket"] = "rbxassetid://10734909847",
		["lucide-paintbrush"] = "rbxassetid://10734910187",
		["lucide-paintbrush-2"] = "rbxassetid://10734910030",
		["lucide-palette"] = "rbxassetid://10734910430",
		["lucide-palmtree"] = "rbxassetid://10734910680",
		["lucide-paperclip"] = "rbxassetid://10734910927",
		["lucide-party-popper"] = "rbxassetid://10734918735",
		["lucide-pause"] = "rbxassetid://10734919336",
		["lucide-pause-circle"] = "rbxassetid://10735024209",
		["lucide-pause-octagon"] = "rbxassetid://10734919143",
		["lucide-pen-tool"] = "rbxassetid://10734919503",
		["lucide-pencil"] = "rbxassetid://10734919691",
		["lucide-percent"] = "rbxassetid://10734919919",
		["lucide-person-standing"] = "rbxassetid://10734920149",
		["lucide-phone"] = "rbxassetid://10734921524",
		["lucide-phone-call"] = "rbxassetid://10734920305",
		["lucide-phone-forwarded"] = "rbxassetid://10734920508",
		["lucide-phone-incoming"] = "rbxassetid://10734920694",
		["lucide-phone-missed"] = "rbxassetid://10734920845",
		["lucide-phone-off"] = "rbxassetid://10734921077",
		["lucide-phone-outgoing"] = "rbxassetid://10734921288",
		["lucide-pie-chart"] = "rbxassetid://10734921727",
		["lucide-piggy-bank"] = "rbxassetid://10734921935",
		["lucide-pin"] = "rbxassetid://10734922324",
		["lucide-pin-off"] = "rbxassetid://10734922180",
		["lucide-pipette"] = "rbxassetid://10734922497",
		["lucide-pizza"] = "rbxassetid://10734922774",
		["lucide-plane"] = "rbxassetid://10734922971",
		["lucide-play"] = "rbxassetid://10734923549",
		["lucide-play-circle"] = "rbxassetid://10734923214",
		["lucide-plus"] = "rbxassetid://10734924532",
		["lucide-plus-circle"] = "rbxassetid://10734923868",
		["lucide-plus-square"] = "rbxassetid://10734924219",
		["lucide-podcast"] = "rbxassetid://10734929553",
		["lucide-pointer"] = "rbxassetid://10734929723",
		["lucide-pound-sterling"] = "rbxassetid://10734929981",
		["lucide-power"] = "rbxassetid://10734930466",
		["lucide-power-off"] = "rbxassetid://10734930257",
		["lucide-printer"] = "rbxassetid://10734930632",
		["lucide-puzzle"] = "rbxassetid://10734930886",
		["lucide-quote"] = "rbxassetid://10734931234",
		["lucide-radio"] = "rbxassetid://10734931596",
		["lucide-radio-receiver"] = "rbxassetid://10734931402",
		["lucide-rectangle-horizontal"] = "rbxassetid://10734931777",
		["lucide-rectangle-vertical"] = "rbxassetid://10734932081",
		["lucide-recycle"] = "rbxassetid://10734932295",
		["lucide-redo"] = "rbxassetid://10734932822",
		["lucide-redo-2"] = "rbxassetid://10734932586",
		["lucide-refresh-ccw"] = "rbxassetid://10734933056",
		["lucide-refresh-cw"] = "rbxassetid://10734933222",
		["lucide-refrigerator"] = "rbxassetid://10734933465",
		["lucide-regex"] = "rbxassetid://10734933655",
		["lucide-repeat"] = "rbxassetid://10734933966",
		["lucide-repeat-1"] = "rbxassetid://10734933826",
		["lucide-reply"] = "rbxassetid://10734934252",
		["lucide-reply-all"] = "rbxassetid://10734934132",
		["lucide-rewind"] = "rbxassetid://10734934347",
		["lucide-rocket"] = "rbxassetid://10734934585",
		["lucide-rocking-chair"] = "rbxassetid://10734939942",
		["lucide-rotate-3d"] = "rbxassetid://10734940107",
		["lucide-rotate-ccw"] = "rbxassetid://10734940376",
		["lucide-rotate-cw"] = "rbxassetid://10734940654",
		["lucide-rss"] = "rbxassetid://10734940825",
		["lucide-ruler"] = "rbxassetid://10734941018",
		["lucide-russian-ruble"] = "rbxassetid://10734941199",
		["lucide-sailboat"] = "rbxassetid://10734941354",
		["lucide-save"] = "rbxassetid://10734941499",
		["lucide-scale"] = "rbxassetid://10734941912",
		["lucide-scale-3d"] = "rbxassetid://10734941739",
		["lucide-scaling"] = "rbxassetid://10734942072",
		["lucide-scan"] = "rbxassetid://10734942565",
		["lucide-scan-face"] = "rbxassetid://10734942198",
		["lucide-scan-line"] = "rbxassetid://10734942351",
		["lucide-scissors"] = "rbxassetid://10734942778",
		["lucide-screen-share"] = "rbxassetid://10734943193",
		["lucide-screen-share-off"] = "rbxassetid://10734942967",
		["lucide-scroll"] = "rbxassetid://10734943448",
		["lucide-search"] = "rbxassetid://10734943674",
		["lucide-send"] = "rbxassetid://10734943902",
		["lucide-separator-horizontal"] = "rbxassetid://10734944115",
		["lucide-separator-vertical"] = "rbxassetid://10734944326",
		["lucide-server"] = "rbxassetid://10734949856",
		["lucide-server-cog"] = "rbxassetid://10734944444",
		["lucide-server-crash"] = "rbxassetid://10734944554",
		["lucide-server-off"] = "rbxassetid://10734944668",
		["lucide-settings"] = "rbxassetid://10734950309",
		["lucide-settings-2"] = "rbxassetid://10734950020",
		["lucide-share"] = "rbxassetid://10734950813",
		["lucide-share-2"] = "rbxassetid://10734950553",
		["lucide-sheet"] = "rbxassetid://10734951038",
		["lucide-shield"] = "rbxassetid://10734951847",
		["lucide-shield-alert"] = "rbxassetid://10734951173",
		["lucide-shield-check"] = "rbxassetid://10734951367",
		["lucide-shield-close"] = "rbxassetid://10734951535",
		["lucide-shield-off"] = "rbxassetid://10734951684",
		["lucide-shirt"] = "rbxassetid://10734952036",
		["lucide-shopping-bag"] = "rbxassetid://10734952273",
		["lucide-shopping-cart"] = "rbxassetid://10734952479",
		["lucide-shovel"] = "rbxassetid://10734952773",
		["lucide-shower-head"] = "rbxassetid://10734952942",
		["lucide-shrink"] = "rbxassetid://10734953073",
		["lucide-shrub"] = "rbxassetid://10734953241",
		["lucide-shuffle"] = "rbxassetid://10734953451",
		["lucide-sidebar"] = "rbxassetid://10734954301",
		["lucide-sidebar-close"] = "rbxassetid://10734953715",
		["lucide-sidebar-open"] = "rbxassetid://10734954000",
		["lucide-sigma"] = "rbxassetid://10734954538",
		["lucide-signal"] = "rbxassetid://10734961133",
		["lucide-signal-high"] = "rbxassetid://10734954807",
		["lucide-signal-low"] = "rbxassetid://10734955080",
		["lucide-signal-medium"] = "rbxassetid://10734955336",
		["lucide-signal-zero"] = "rbxassetid://10734960878",
		["lucide-siren"] = "rbxassetid://10734961284",
		["lucide-skip-back"] = "rbxassetid://10734961526",
		["lucide-skip-forward"] = "rbxassetid://10734961809",
		["lucide-skull"] = "rbxassetid://10734962068",
		["lucide-slack"] = "rbxassetid://10734962339",
		["lucide-slash"] = "rbxassetid://10734962600",
		["lucide-slice"] = "rbxassetid://10734963024",
		["lucide-sliders"] = "rbxassetid://10734963400",
		["lucide-sliders-horizontal"] = "rbxassetid://10734963191",
		["lucide-smartphone"] = "rbxassetid://10734963940",
		["lucide-smartphone-charging"] = "rbxassetid://10734963671",
		["lucide-smile"] = "rbxassetid://10734964441",
		["lucide-smile-plus"] = "rbxassetid://10734964188",
		["lucide-snowflake"] = "rbxassetid://10734964600",
		["lucide-sofa"] = "rbxassetid://10734964852",
		["lucide-sort-asc"] = "rbxassetid://10734965115",
		["lucide-sort-desc"] = "rbxassetid://10734965287",
		["lucide-speaker"] = "rbxassetid://10734965419",
		["lucide-sprout"] = "rbxassetid://10734965572",
		["lucide-square"] = "rbxassetid://10734965702",
		["lucide-star"] = "rbxassetid://10734966248",
		["lucide-star-half"] = "rbxassetid://10734965897",
		["lucide-star-off"] = "rbxassetid://10734966097",
		["lucide-stethoscope"] = "rbxassetid://10734966384",
		["lucide-sticker"] = "rbxassetid://10734972234",
		["lucide-sticky-note"] = "rbxassetid://10734972463",
		["lucide-stop-circle"] = "rbxassetid://10734972621",
		["lucide-stretch-horizontal"] = "rbxassetid://10734972862",
		["lucide-stretch-vertical"] = "rbxassetid://10734973130",
		["lucide-strikethrough"] = "rbxassetid://10734973290",
		["lucide-subscript"] = "rbxassetid://10734973457",
		["lucide-sun"] = "rbxassetid://10734974297",
		["lucide-sun-dim"] = "rbxassetid://10734973645",
		["lucide-sun-medium"] = "rbxassetid://10734973778",
		["lucide-sun-moon"] = "rbxassetid://10734973999",
		["lucide-sun-snow"] = "rbxassetid://10734974130",
		["lucide-sunrise"] = "rbxassetid://10734974522",
		["lucide-sunset"] = "rbxassetid://10734974689",
		["lucide-superscript"] = "rbxassetid://10734974850",
		["lucide-swiss-franc"] = "rbxassetid://10734975024",
		["lucide-switch-camera"] = "rbxassetid://10734975214",
		["lucide-sword"] = "rbxassetid://10734975486",
		["lucide-swords"] = "rbxassetid://10734975692",
		["lucide-syringe"] = "rbxassetid://10734975932",
		["lucide-table"] = "rbxassetid://10734976230",
		["lucide-table-2"] = "rbxassetid://10734976097",
		["lucide-tablet"] = "rbxassetid://10734976394",
		["lucide-tag"] = "rbxassetid://10734976528",
		["lucide-tags"] = "rbxassetid://10734976739",
		["lucide-target"] = "rbxassetid://10734977012",
		["lucide-tent"] = "rbxassetid://10734981750",
		["lucide-terminal"] = "rbxassetid://10734982144",
		["lucide-terminal-square"] = "rbxassetid://10734981995",
		["lucide-text-cursor"] = "rbxassetid://10734982395",
		["lucide-text-cursor-input"] = "rbxassetid://10734982297",
		["lucide-thermometer"] = "rbxassetid://10734983134",
		["lucide-thermometer-snowflake"] = "rbxassetid://10734982571",
		["lucide-thermometer-sun"] = "rbxassetid://10734982771",
		["lucide-thumbs-down"] = "rbxassetid://10734983359",
		["lucide-thumbs-up"] = "rbxassetid://10734983629",
		["lucide-ticket"] = "rbxassetid://10734983868",
		["lucide-timer"] = "rbxassetid://10734984606",
		["lucide-timer-off"] = "rbxassetid://10734984138",
		["lucide-timer-reset"] = "rbxassetid://10734984355",
		["lucide-toggle-left"] = "rbxassetid://10734984834",
		["lucide-toggle-right"] = "rbxassetid://10734985040",
		["lucide-tornado"] = "rbxassetid://10734985247",
		["lucide-toy-brick"] = "rbxassetid://10747361919",
		["lucide-train"] = "rbxassetid://10747362105",
		["lucide-trash"] = "rbxassetid://10747362393",
		["lucide-trash-2"] = "rbxassetid://10747362241",
		["lucide-tree-deciduous"] = "rbxassetid://10747362534",
		["lucide-tree-pine"] = "rbxassetid://10747362748",
		["lucide-trees"] = "rbxassetid://10747363016",
		["lucide-trending-down"] = "rbxassetid://10747363205",
		["lucide-trending-up"] = "rbxassetid://10747363465",
		["lucide-triangle"] = "rbxassetid://10747363621",
		["lucide-trophy"] = "rbxassetid://10747363809",
		["lucide-truck"] = "rbxassetid://10747364031",
		["lucide-tv"] = "rbxassetid://10747364593",
		["lucide-tv-2"] = "rbxassetid://10747364302",
		["lucide-type"] = "rbxassetid://10747364761",
		["lucide-umbrella"] = "rbxassetid://10747364971",
		["lucide-underline"] = "rbxassetid://10747365191",
		["lucide-undo"] = "rbxassetid://10747365484",
		["lucide-undo-2"] = "rbxassetid://10747365359",
		["lucide-unlink"] = "rbxassetid://10747365771",
		["lucide-unlink-2"] = "rbxassetid://10747397871",
		["lucide-unlock"] = "rbxassetid://10747366027",
		["lucide-upload"] = "rbxassetid://10747366434",
		["lucide-upload-cloud"] = "rbxassetid://10747366266",
		["lucide-usb"] = "rbxassetid://10747366606",
		["lucide-user"] = "rbxassetid://10747373176",
		["lucide-user-check"] = "rbxassetid://10747371901",
		["lucide-user-cog"] = "rbxassetid://10747372167",
		["lucide-user-minus"] = "rbxassetid://10747372346",
		["lucide-user-plus"] = "rbxassetid://10747372702",
		["lucide-user-x"] = "rbxassetid://10747372992",
		["lucide-users"] = "rbxassetid://10747373426",
		["lucide-utensils"] = "rbxassetid://10747373821",
		["lucide-utensils-crossed"] = "rbxassetid://10747373629",
		["lucide-venetian-mask"] = "rbxassetid://10747374003",
		["lucide-verified"] = "rbxassetid://10747374131",
		["lucide-vibrate"] = "rbxassetid://10747374489",
		["lucide-vibrate-off"] = "rbxassetid://10747374269",
		["lucide-video"] = "rbxassetid://10747374938",
		["lucide-video-off"] = "rbxassetid://10747374721",
		["lucide-view"] = "rbxassetid://10747375132",
		["lucide-voicemail"] = "rbxassetid://10747375281",
		["lucide-volume"] = "rbxassetid://10747376008",
		["lucide-volume-1"] = "rbxassetid://10747375450",
		["lucide-volume-2"] = "rbxassetid://10747375679",
		["lucide-volume-x"] = "rbxassetid://10747375880",
		["lucide-wallet"] = "rbxassetid://10747376205",
		["lucide-wand"] = "rbxassetid://10747376565",
		["lucide-wand-2"] = "rbxassetid://10747376349",
		["lucide-watch"] = "rbxassetid://10747376722",
		["lucide-waves"] = "rbxassetid://10747376931",
		["lucide-webcam"] = "rbxassetid://10747381992",
		["lucide-wifi"] = "rbxassetid://10747382504",
		["lucide-wifi-off"] = "rbxassetid://10747382268",
		["lucide-wind"] = "rbxassetid://10747382750",
		["lucide-wrap-text"] = "rbxassetid://10747383065",
		["lucide-wrench"] = "rbxassetid://10747383470",
		["lucide-x"] = "rbxassetid://10747384394",
		["lucide-x-circle"] = "rbxassetid://10747383819",
		["lucide-x-octagon"] = "rbxassetid://10747384037",
		["lucide-x-square"] = "rbxassetid://10747384217",
		["lucide-zoom-in"] = "rbxassetid://10747384552",
		["lucide-zoom-out"] = "rbxassetid://10747384679",
	},
}

function GetIcon(name)
	if type(name) ~= "string" or name == "" then return nil end
	local key = name
	if not string.find(key, "lucide-", 1, true) then
		key = "lucide-" .. key
	end
	local assets = IconAssets and IconAssets.assets
	if assets and assets[key] then
		return assets[key]
	end
	return nil
end

local Lighting = game:GetService("Lighting")

local function _Mk(className, props)
	local inst = Instance.new(className)
	for k, v in pairs(props or {}) do
		if k ~= "Parent" then
			pcall(function() inst[k] = v end)
		end
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

SurfaceBlur = {}
SurfaceBlur.__index = SurfaceBlur

function SurfaceBlur.new(object)
	local self = setmetatable({
		_object = object,
		_folder = nil,
		_root = nil,
		_frame = nil,
		_dof = nil,
		_enabled = true,
		_connections = {},
	}, SurfaceBlur)
	self:_Initialize()
	return self
end

function SurfaceBlur:_CreateDepthOfField()
	local existingDOF = Lighting:FindFirstChild("VeyraSurfaceDOF")
	if existingDOF then existingDOF:Destroy() end
	local existingBlur = Lighting:FindFirstChild("VeyraSurfaceBlur")
	if existingBlur then existingBlur:Destroy() end
	self._dof = _Mk("DepthOfFieldEffect", {
		Name = "VeyraSurfaceDOF",
		FarIntensity = 0,
		FocusDistance = 0.05,
		InFocusRadius = 0.1,
		NearIntensity = 0.5,
		Parent = Lighting,
	})
	return self._dof
end

function SurfaceBlur:_CreateFolder()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local existing = cam:FindFirstChild("VeyraSurfaceBlur")
	if existing then existing:Destroy() end
	self._folder = _Mk("Folder", { Name = "VeyraSurfaceBlur", Parent = cam })
end

function SurfaceBlur:_CreateRoot()
	if not self._folder then return end
	local part = _Mk("Part", {
		Name = "Root",
		Color = Color3.new(0, 0, 0),
		Material = Enum.Material.Glass,
		Size = Vector3.new(1, 1, 0),
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		Locked = true,
		CastShadow = false,
		Transparency = 0.95,
		Parent = self._folder,
	})
	_Mk("SpecialMesh", { MeshType = Enum.MeshType.Brick, Parent = part })
	self._root = part
end

function SurfaceBlur:_CreateFrame()
	self._frame = _Mk("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = self._object,
	})
end

function SurfaceBlur:_Render(distance)
	distance = distance or 0.001
	local positions = { top_left = Vector2.new(), top_right = Vector2.new(), bottom_right = Vector2.new() }
	local function ViewportToWorld(location, dist)
		local ray = workspace.CurrentCamera:ScreenPointToRay(location.X, location.Y)
		return ray.Origin + ray.Direction * dist
	end
	local function GetOffset()
		local viewY = workspace.CurrentCamera.ViewportSize.Y
		return (viewY / 2560) * 24 + 4
	end
	local function UpdatePositions(size, position)
		positions.top_left = position
		positions.top_right = position + Vector2.new(size.X, 0)
		positions.bottom_right = position + size
	end
	local function Update()
		if not self._root or not self._enabled or not workspace.CurrentCamera then return end
		local tl = ViewportToWorld(positions.top_left, distance)
		local tr = ViewportToWorld(positions.top_right, distance)
		local br = ViewportToWorld(positions.bottom_right, distance)
		local width = (tr - tl).Magnitude
		local height = (tr - br).Magnitude
		self._root.CFrame = CFrame.fromMatrix(
			(tl + br) / 2,
			workspace.CurrentCamera.CFrame.XVector,
			workspace.CurrentCamera.CFrame.YVector,
			workspace.CurrentCamera.CFrame.ZVector
		)
		if self._root:FindFirstChildOfClass("SpecialMesh") then
			self._root.Mesh.Scale = Vector3.new(width, height, 0)
		end
	end
	local function OnChange()
		if not self._enabled or not self._frame then return end
		local offset = GetOffset()
		local size = self._frame.AbsoluteSize - Vector2.new(offset, offset)
		local position = self._frame.AbsolutePosition + Vector2.new(offset / 2, offset / 2)
		UpdatePositions(size, position)
		task.spawn(Update)
	end
	local cam = workspace.CurrentCamera
	if cam then
		table.insert(self._connections, cam:GetPropertyChangedSignal("CFrame"):Connect(Update))
		table.insert(self._connections, cam:GetPropertyChangedSignal("ViewportSize"):Connect(Update))
		table.insert(self._connections, cam:GetPropertyChangedSignal("FieldOfView"):Connect(Update))
	end
	if self._frame then
		table.insert(self._connections, self._frame:GetPropertyChangedSignal("AbsolutePosition"):Connect(OnChange))
		table.insert(self._connections, self._frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(OnChange))
	end
	table.insert(self._connections, RunService.RenderStepped:Connect(Update))
	task.spawn(OnChange)
end

function SurfaceBlur:_Initialize()
	self:_CreateDepthOfField()
	self:_CreateFolder()
	self:_CreateRoot()
	self:_CreateFrame()
	self:_Render(0.001)
end

function SurfaceBlur:SetEnabled(enabled)
	self._enabled = enabled and true or false
	if self._root then
		self._root.Transparency = self._enabled and 0.95 or 1
	end
	if self._dof then
		self._dof.Enabled = self._enabled
	end
end

function SurfaceBlur:Destroy()
	for _, c in ipairs(self._connections) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(self._connections)
	if self._folder then pcall(function() self._folder:Destroy() end) end
	local dof = Lighting:FindFirstChild("VeyraSurfaceDOF")
	if dof then pcall(function() dof:Destroy() end) end
	local blur = Lighting:FindFirstChild("VeyraSurfaceBlur")
	if blur then pcall(function() blur:Destroy() end) end
end

local CONFIG_ROOT = "VeyraConfigs"

local function EnsureConfigRoot()
	pcall(function()
		if type(makefolder) == "function" and type(isfolder) == "function" then
			if not isfolder(CONFIG_ROOT) then
				makefolder(CONFIG_ROOT)
			end
		elseif type(makefolder) == "function" then
			pcall(makefolder, CONFIG_ROOT)
		end
	end)
end

local function ConfigPath(name)
	name = tostring(name or "default"):gsub("[^%w%-%_]", "_")
	if name == "" then name = "default" end
	return CONFIG_ROOT .. "/" .. name .. ".json"
end

ListConfigs = function()
	local configs = {}
	EnsureConfigRoot()
	pcall(function()
		if type(listfiles) == "function" then
			for _, file in ipairs(listfiles(CONFIG_ROOT) or {}) do
				local n = string.match(file, CONFIG_ROOT .. "/(.+)%.json$")
					or string.match(file, CONFIG_ROOT .. "\\(.+)%.json$")
					or string.match(file, "([^/\\]+)%.json$")
				if n then table.insert(configs, n) end
			end
		end
	end)
	if #configs == 0 then table.insert(configs, "default") end
	return configs
end

ConfigRegistry = ConfigRegistry or {} 
AutoSaveEnabled = false
CurrentConfigName = "default"

RegisterConfigElement = function(flag, kind, getter, setter)
	if type(flag) ~= "string" or flag == "" then return end
	ConfigRegistry[flag] = {
		Kind = kind or "Any",
		Get = getter,
		Set = setter,
	}
end

local function CollectConfigPayload()
	local payload = {
		_meta = {
			Theme = Settings.Theme,
			CornerRadius = Settings.CornerRadius,
			UseBackgroundImage = Settings.UseBackgroundImage,
			BackgroundImage = Settings.BackgroundImage,
			BackgroundImageTransparency = Settings.BackgroundImageTransparency,
			ToggleUIKey = Settings.ToggleUIKey,
			UIVisible = Settings.UIVisible,
		},
		elements = {},
	}
	for flag, entry in pairs(ConfigRegistry) do
		local ok, val = pcall(entry.Get)
		if ok then
			local stored = val
			if typeof(val) == "Color3" then
				stored = { R = val.R, G = val.G, B = val.B, __type = "Color3" }
			elseif typeof(val) == "EnumItem" then
				stored = { Name = val.Name, EnumType = tostring(val.EnumType), __type = "EnumItem" }
			end
			payload.elements[flag] = { Kind = entry.Kind, Value = stored }
		end
	end
	return payload
end

local function ApplyConfigPayload(payload)
	if type(payload) ~= "table" then return false end
	if type(payload._meta) == "table" then
		for k, v in pairs(payload._meta) do
			Settings[k] = v
		end
		if type(Settings.Theme) == "string" and ThemePresets[Settings.Theme] then
			ApplyThemePreset(Settings.Theme)
		end
	end
	if type(payload.elements) == "table" then
		for flag, data in pairs(payload.elements) do
			local entry = ConfigRegistry[flag]
			if entry and entry.Set and type(data) == "table" then
				local v = data.Value
				if type(v) == "table" and v.__type == "Color3" then
					v = Color3.new(tonumber(v.R) or 1, tonumber(v.G) or 1, tonumber(v.B) or 1)
				elseif type(v) == "table" and v.__type == "EnumItem" and type(v.Name) == "string" then
					local ok, kc = pcall(function() return Enum.KeyCode[v.Name] end)
					if ok and kc then v = kc end
				end
				pcall(entry.Set, v)
			end
		end
	end
	return true
end

SaveNamedConfig = function(name)
	EnsureConfigRoot()
	name = name or CurrentConfigName or "default"
	CurrentConfigName = name
	local payload = CollectConfigPayload()
	local encoded = ConfigEncode(payload)
	local ok = false
	pcall(function()
		if type(writefile) == "function" then
			writefile(ConfigPath(name), encoded)
			ok = true
		end
	end)
	return ok
end

LoadNamedConfig = function(name)
	name = name or CurrentConfigName or "default"
	CurrentConfigName = name
	local raw = nil
	pcall(function()
		if type(readfile) == "function" then
			raw = readfile(ConfigPath(name))
		end
	end)
	if not raw then return false end
	local data = ConfigDecode(raw)
	return ApplyConfigPayload(data)
end

DeleteNamedConfig = function(name)
	name = name or CurrentConfigName
	if not name or name == "" then return false end
	local ok = false
	pcall(function()
		if type(delfile) == "function" then
			delfile(ConfigPath(name))
			ok = true
		elseif type(writefile) == "function" then
			writefile(ConfigPath(name), "{}")
			ok = true
		end
	end)
	return ok
end

local function MaybeAutoSave()
	if AutoSaveEnabled then
		pcall(SaveNamedConfig, CurrentConfigName)
	end
end

local function isMotor(value)
	local motorType = tostring(value):match("^Motor%((.+)%)$")

	if motorType then
		return true, motorType
	else
		return false
	end
end

local Connection = {}
Connection.__index = Connection

function Connection.new(signal, handler)
	return setmetatable({
		signal = signal,
		connected = true,
		_handler = handler,
	}, Connection)
end

function Connection:disconnect()
	if self.connected then
		self.connected = false

		for index, connection in pairs(self.signal._connections) do
			if connection == self then
				table.remove(self.signal._connections, index)
				return
			end
		end
	end
end

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({
		_connections = {},
		_threads = {},
	}, Signal)
end

function Signal:fire(...)
	for _, connection in pairs(self._connections) do
		connection._handler(...)
	end

	for _, thread in pairs(self._threads) do
		coroutine.resume(thread, ...)
	end

	self._threads = {}
end

function Signal:connect(handler)
	local connection = Connection.new(self, handler)
	table.insert(self._connections, connection)
	return connection
end

function Signal:wait()
	table.insert(self._threads, coroutine.running())
	return coroutine.yield()
end

local Linear = {}
Linear.__index = Linear

function Linear.new(targetValue, options)
	assert(targetValue, "Missing argument #1: targetValue")

	options = options or {}

	return setmetatable({
		_targetValue = targetValue,
		_velocity = options.velocity or 1,
	}, Linear)
end

function Linear:step(state, dt)
	local position = state.value
	local velocity = self._velocity
	local goal = self._targetValue

	local dPos = dt * velocity

	local complete = dPos >= math.abs(goal - position)
	position = position + dPos * (goal > position and 1 or -1)
	if complete then
		position = self._targetValue
		velocity = 0
	end

	return {
		complete = complete,
		value = position,
		velocity = velocity,
	}
end

local Instant = {}
Instant.__index = Instant

function Instant.new(targetValue)
	return setmetatable({
		_targetValue = targetValue,
	}, Instant)
end

function Instant:step()
	return {
		complete = true,
		value = self._targetValue,
	}
end

local VELOCITY_THRESHOLD = 0.001
local POSITION_THRESHOLD = 0.001

local EPS = 0.0001

local Spring = {}
Spring.__index = Spring

function Spring.new(targetValue, options)
	assert(targetValue, "Missing argument #1: targetValue")
	options = options or {}

	return setmetatable({
		_targetValue = targetValue,
		_frequency = options.frequency or 4,
		_dampingRatio = options.dampingRatio or 1,
	}, Spring)
end

function Spring:step(state, dt)

	local d = self._dampingRatio
	local f = self._frequency * 2 * math.pi
	local g = self._targetValue
	local p0 = state.value
	local v0 = state.velocity or 0

	local offset = p0 - g
	local decay = math.exp(-d * f * dt)

	local p1, v1

	if d == 1 then
		p1 = (offset * (1 + f * dt) + v0 * dt) * decay + g
		v1 = (v0 * (1 - f * dt) - offset * (f * f * dt)) * decay
	elseif d < 1 then
		local c = math.sqrt(1 - d * d)

		local i = math.cos(f * c * dt)
		local j = math.sin(f * c * dt)

		local z
		if c > EPS then
			z = j / c
		else
			local a = dt * f
			z = a + ((a * a) * (c * c) * (c * c) / 20 - c * c) * (a * a * a) / 6
		end

		local y
		if f * c > EPS then
			y = j / (f * c)
		else
			local b = f * c
			y = dt + ((dt * dt) * (b * b) * (b * b) / 20 - b * b) * (dt * dt * dt) / 6
		end

		p1 = (offset * (i + d * z) + v0 * y) * decay + g
		v1 = (v0 * (i - z * d) - offset * (z * f)) * decay
	else
		local c = math.sqrt(d * d - 1)

		local r1 = -f * (d - c)
		local r2 = -f * (d + c)

		local co2 = (v0 - offset * r1) / (2 * f * c)
		local co1 = offset - co2

		local e1 = co1 * math.exp(r1 * dt)
		local e2 = co2 * math.exp(r2 * dt)

		p1 = e1 + e2 + g
		v1 = e1 * r1 + e2 * r2
	end

	local complete = math.abs(v1) < VELOCITY_THRESHOLD and math.abs(p1 - g) < POSITION_THRESHOLD

	return {
		complete = complete,
		value = complete and g or p1,
		velocity = v1,
	}
end

local noop = function() end

local BaseMotor = {}
BaseMotor.__index = BaseMotor

function BaseMotor.new()
	return setmetatable({
		_onStep = Signal.new(),
		_onStart = Signal.new(),
		_onComplete = Signal.new(),
	}, BaseMotor)
end

function BaseMotor:onStep(handler)
	return self._onStep:connect(handler)
end

function BaseMotor:onStart(handler)
	return self._onStart:connect(handler)
end

function BaseMotor:onComplete(handler)
	return self._onComplete:connect(handler)
end

function BaseMotor:start()
	if not self._connection then
		self._connection = RunService.RenderStepped:Connect(function(deltaTime)
			self:step(deltaTime)
		end)
	end
end

function BaseMotor:stop()
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
end

BaseMotor.destroy = BaseMotor.stop

BaseMotor.step = noop
BaseMotor.getValue = noop
BaseMotor.setGoal = noop

function BaseMotor:__tostring()
	return "Motor"
end

local SingleMotor = setmetatable({}, BaseMotor)
SingleMotor.__index = SingleMotor

function SingleMotor.new(initialValue, useImplicitConnections)
	assert(initialValue, "Missing argument #1: initialValue")
	assert(typeof(initialValue) == "number", "initialValue must be a number!")

	local self = setmetatable(BaseMotor.new(), SingleMotor)

	if useImplicitConnections ~= nil then
		self._useImplicitConnections = useImplicitConnections
	else
		self._useImplicitConnections = true
	end

	self._goal = nil
	self._state = {
		complete = true,
		value = initialValue,
	}

	return self
end

function SingleMotor:step(deltaTime)
	if self._state.complete then
		return true
	end

	local newState = self._goal:step(self._state, deltaTime)

	self._state = newState
	self._onStep:fire(newState.value)

	if newState.complete then
		if self._useImplicitConnections then
			self:stop()
		end

		self._onComplete:fire()
	end

	return newState.complete
end

function SingleMotor:getValue()
	return self._state.value
end

function SingleMotor:setGoal(goal)
	self._state.complete = false
	self._goal = goal

	self._onStart:fire()

	if self._useImplicitConnections then
		self:start()
	end
end

function SingleMotor:__tostring()
	return "Motor(Single)"
end

local GroupMotor = setmetatable({}, BaseMotor)
GroupMotor.__index = GroupMotor

local function toMotor(value)
	if isMotor(value) then
		return value
	end

	local valueType = typeof(value)

	if valueType == "number" then
		return SingleMotor.new(value, false)
	elseif valueType == "table" then
		return GroupMotor.new(value, false)
	end

	error(("Unable to convert %q to motor; type %s is unsupported"):format(value, valueType), 2)
end

function GroupMotor.new(initialValues, useImplicitConnections)
	assert(initialValues, "Missing argument #1: initialValues")
	assert(typeof(initialValues) == "table", "initialValues must be a table!")
	assert(
		not initialValues.step,
		'initialValues contains disallowed property "step". Did you mean to put a table of values here?'
	)

	local self = setmetatable(BaseMotor.new(), GroupMotor)

	if useImplicitConnections ~= nil then
		self._useImplicitConnections = useImplicitConnections
	else
		self._useImplicitConnections = true
	end

	self._complete = true
	self._motors = {}

	for key, value in pairs(initialValues) do
		self._motors[key] = toMotor(value)
	end

	return self
end

function GroupMotor:step(deltaTime)
	if self._complete then
		return true
	end

	local allMotorsComplete = true

	for _, motor in pairs(self._motors) do
		local complete = motor:step(deltaTime)
		if not complete then

			allMotorsComplete = false
		end
	end

	self._onStep:fire(self:getValue())

	if allMotorsComplete then
		if self._useImplicitConnections then
			self:stop()
		end

		self._complete = true
		self._onComplete:fire()
	end

	return allMotorsComplete
end

function GroupMotor:setGoal(goals)
	assert(not goals.step, 'goals contains disallowed property "step". Did you mean to put a table of goals here?')

	self._complete = false
	self._onStart:fire()

	for key, goal in pairs(goals) do
		local motor = assert(self._motors[key], ("Unknown motor for key %s"):format(key))
		motor:setGoal(goal)
	end

	if self._useImplicitConnections then
		self:start()
	end
end

function GroupMotor:getValue()
	local values = {}

	for key, motor in pairs(self._motors) do
		values[key] = motor:getValue()
	end

	return values
end

function GroupMotor:__tostring()
	return "Motor(Group)"
end

Flipper = {
	SingleMotor = SingleMotor,
	GroupMotor = GroupMotor,

	Instant = Instant,
	Linear = Linear,
	Spring = Spring,

	isMotor = isMotor,
}


local Library = {}
Library.__index = Library

local NotifManager = NotificationManager.new()

local Windows = {}

function Library:CreateWindow(config)
	local win = CreateWindow(Library, config)
	table.insert(Windows, win)

	local oldDestroy = win.Destroy
	function win:Destroy()
		local idx = table.find(Windows, self)
		if idx then table.remove(Windows, idx) end
		if oldDestroy then oldDestroy(self) end
	end
	return win
end

function Library:Notify(config)
	return NotifManager:Notify(config)
end

function Library:SetNotifDraggable(enabled)
	NotifManager.Draggable = enabled and true or false
end
Library.NotifDraggable = true

function Library:CreateNode(config)
	config = config or {}

	if config.Content and not config.Description then
		config.Description = config.Content
	end
	if config.Length ~= nil and config.Duration == nil then
		config.Duration = config.Length
	end
	return NotifManager:Notify(config)
end

function Library:SetTheme(t)
	SetTheme(t)
end

function Library:ApplyTheme(name)
	return ApplyThemePreset(name)
end

function Library:GetTheme()
	return GetTheme()
end

function Library:GetSettings()
	return Settings
end

function Library:SaveSettings()
	return ConfigSave()
end

function Library:LoadSettings()
	return ConfigLoad()
end

Library.ThemePresets = ThemePresets
Library.Settings = Settings

local InitDone = false

local function KillPrevious()
	pcall(function()

		local snap = table.clone(Windows)
		table.clear(Windows)
		for _, win in ipairs(snap) do
			pcall(function()
				if win.Destroy then win:Destroy() end
			end)
		end

		if NotifManager then
			pcall(function() NotifManager:Clear() end)
			pcall(function()
				if NotifManager.Gui then NotifManager.Gui:Destroy() end
			end)
			NotifManager = NotificationManager.new()
		end

		pcall(function() TweenEngine.CancelAll() end)

		local parents = {}
		pcall(function() table.insert(parents, game:GetService("CoreGui")) end)
		pcall(function()
			if type(gethui) == "function" then table.insert(parents, gethui()) end
		end)
		pcall(function()
			local lp = game:GetService("Players").LocalPlayer
			if lp then table.insert(parents, lp:FindFirstChildOfClass("PlayerGui")) end
		end)
		for _, parent in ipairs(parents) do
			if parent then
				for _, child in ipairs(parent:GetChildren()) do
					if child:IsA("ScreenGui") then
						local n = child.Name
						if string.find(n, "Veyra") or string.find(n, "veyra") then
							pcall(function() child:Destroy() end)
						end
					end
				end
			end
		end
	end)
end

function Library:Init(options)
	options = options or {}

	KillPrevious()
	pcall(function()
		self:Destroy()
	end)
	InitDone = true

	if type(Settings.Theme) == "string" and ThemePresets[Settings.Theme] then
		ApplyThemePreset(Settings.Theme)
	end
	if type(options.Theme) == "string" then
		ApplyThemePreset(options.Theme)
	elseif type(options.Theme) == "table" then
		SetTheme(options.Theme)
	end

	if options.NotifDraggable ~= nil then
		NotifManager.Draggable = options.NotifDraggable and true or false
	end

	if options.Intro == true then
		task.spawn(function()
			PlayIntro(options.IntroConfig or {
				Title = options.Title or "Veyra",
				Subtitle = options.Subtitle or "",
			})
		end)
	end

	if type(options.KeySystem) == "table" then
		task.spawn(function()
			CreateKeySystem(options.KeySystem)
		end)
	end

	-- Simple: Init({ Title = "..." }) returns the window
	if options.Title or options.Name then
		return self:CreateWindow({
			Title = options.Title or options.Name or "Veyra",
			Subtitle = options.Subtitle or "",
			MobileToggle = options.MobileToggle,
			VeyraBlur = options.VeyraBlur,
			Size = options.Size,
		})
	end

	return Library
end

function Library:PlayIntro(config)
	return PlayIntro(config)
end

function Library:CreateKeySystem(config)
	return CreateKeySystem(config)
end

function Library:IsInit()
	return InitDone
end

function Library:Destroy()
	local snap = table.clone(Windows)
	table.clear(Windows)
	for _, win in ipairs(snap) do
		pcall(function() win:Destroy() end)
	end
	pcall(function() NotifManager:Destroy() end)
	pcall(function()
		NotifManager = NotificationManager.new()
	end)
	TweenEngine.CancelAll()
	table.clear(ThemeListeners)
	InitDone = false
	pcall(function()
		local parents = {}
		pcall(function() table.insert(parents, game:GetService("CoreGui")) end)
		pcall(function()
			if type(gethui) == "function" then table.insert(parents, gethui()) end
		end)
		pcall(function()
			local lp = game:GetService("Players").LocalPlayer
			if lp then table.insert(parents, lp:FindFirstChildOfClass("PlayerGui")) end
		end)
		for _, parent in ipairs(parents) do
			if parent then
				for _, child in ipairs(parent:GetChildren()) do
					if child:IsA("ScreenGui") and (child.Name == "VeyraKeySystem" or string.find(child.Name, "VeyraKey")) then
						pcall(function() child:Destroy() end)
					end
				end
			end
		end
	end)
end

Library.Animation = TweenEngine

local function wrapTab(tab)
	local t = tab
	function t:Section(name, desc)
		if type(name) == "table" then
			return self:CreateSection(name)
		end
		return self:CreateSection({ Name = name, Description = desc })
	end
	function t:Toggle(name, default, callback)
		-- Tab:Toggle({ Name = "...", Default = "no", Status = "yes", Callback = fn })
		if type(name) == "table" then
			return self:CreateToggle(name)
		end
		if type(default) == "function" then
			callback = default
			default = false
		end
		return self:CreateToggle({ Name = name, Default = default, Callback = callback })
	end
	function t:Slider(name, min, max, default, callback)
		if type(min) == "function" then
			callback = min
			min, max, default = 0, 100, 0
		elseif type(default) == "function" then
			callback = default
			default = min
		end
		return self:CreateSlider({
			Name = name,
			Min = min or 0,
			Max = max or 100,
			Default = default or min or 0,
			Callback = callback,
		})
	end
	function t:Button(name, callback)
		return self:CreateButton({ Name = name, Callback = callback })
	end
	function t:Drop(name, options, default, callback)
		if type(options) == "function" then
			callback = options
			options, default = {}, nil
		elseif type(default) == "function" then
			callback = default
			default = options and options[1]
		end
		return self:CreateDropdown({
			Name = name,
			Options = options or {},
			Default = default or (options and options[1]) or "",
			Callback = callback,
		})
	end
	function t:Key(name, key, callback)
		if type(key) == "function" then
			callback = key
			key = Enum.KeyCode.Unknown
		end
		return self:CreateKeybind({ Name = name, Default = key or Enum.KeyCode.Unknown, Callback = callback })
	end
	function t:Input(name, placeholder, callback)
		if type(placeholder) == "function" then
			callback = placeholder
			placeholder = ""
		end
		return self:CreateTextbox({ Name = name, Placeholder = placeholder or "", Callback = callback })
	end
	function t:Label(name, desc)
		return self:CreateLabel({ Name = name, Description = desc })
	end
	function t:Line()
		return self:CreateDivider()
	end
	function t:Color(name, default, callback)
		if type(default) == "function" then
			callback = default
			default = Color3.fromRGB(255, 255, 255)
		end
		return self:CreateColorPicker({
			Name = name,
			Default = default or Color3.fromRGB(255, 255, 255),
			Callback = callback,
		})
	end
	function t:ColorPicker(name, default, callback)
		return t:Color(name, default, callback)
	end
	return t
end

local function wrapWindow(win)
	local w = win
	function w:Tab(name)
		return wrapTab(self:CreateTab({ Name = name or "Tab" }))
	end
	function w:Action(name, callback)
		return self:AddAction({ Name = name, Callback = callback })
	end
	return w
end

function Library:New(title, subtitle)
	if not InitDone then
		self:Init()
	end
	local config
	if type(title) == "table" then
		config = title
	else
		config = {
			Title = title or "Veyra",
			Subtitle = subtitle or "",
		}
	end
	return wrapWindow(self:CreateWindow(config))
end

local _CreateWindow = Library.CreateWindow
function Library:CreateWindow(config)
	return wrapWindow(_CreateWindow(self, config))
end

local _Notify = Library.Notify
function Library:Notify(a, b, c)
	if type(a) == "table" then
		return _Notify(self, a)
	end
	return _Notify(self, {
		Title = tostring(a or "Notice"),
		Description = tostring(b or ""),
		Duration = tonumber(c) or 3,
		Type = "Info",
	})
end

function Library:GetIcon(name)
	return GetIcon(name)
end

function Library:EnableSurfaceBlur(window)
	if not window or not window.Main then return nil end
	if window._SurfaceBlur then
		window._SurfaceBlur:SetEnabled(true)
		return window._SurfaceBlur
	end
	local blur = SurfaceBlur.new(window.Main)
	window._SurfaceBlur = blur
	if window.Cleanup then
		window.Cleanup:AddCallback(function()
			if blur then blur:Destroy() end
		end)
	end
	return blur
end

function Library:DisableSurfaceBlur(window)
	if window and window._SurfaceBlur then
		window._SurfaceBlur:SetEnabled(false)
	end
end

function Library:RegisterFlag(flag, kind, getter, setter)
	RegisterConfigElement(flag, kind, getter, setter)
end

function Library:SaveConfig(name)
	local ok = SaveNamedConfig(name)
	if self.Notify then
		self:Notify({
			Title = ok and "Config Saved" or "Save Failed",
			Description = ok and ("Wrote " .. tostring(name or CurrentConfigName)) or "writefile unavailable",
			Duration = 2.5,
			Type = ok and "Success" or "Error",
		})
	end
	return ok
end

function Library:LoadConfig(name)
	local ok = LoadNamedConfig(name)
	for _, win in ipairs(Windows) do
		if win and win.RefreshTheme then pcall(function() win:RefreshTheme() end) end
	end
	if self.Notify then
		self:Notify({
			Title = ok and "Config Loaded" or "Load Failed",
			Description = ok and ("Applied " .. tostring(name or CurrentConfigName)) or "file missing or invalid",
			Duration = 2.5,
			Type = ok and "Success" or "Error",
		})
	end
	return ok
end

function Library:DeleteConfig(name)
	local ok = DeleteNamedConfig(name)
	if self.Notify then
		self:Notify({
			Title = ok and "Config Deleted" or "Delete Failed",
			Description = tostring(name or ""),
			Duration = 2,
			Type = ok and "Info" or "Warning",
		})
	end
	return ok
end

function Library:GetConfigs()
	return ListConfigs()
end

function Library:SetAutoSave(enabled)
	AutoSaveEnabled = enabled and true or false
end

function Library:GetCurrentConfig()
	return CurrentConfigName
end

Library.Icons = IconAssets
Library.SurfaceBlur = SurfaceBlur
Library.Version = "2.0.0-unified"
Library.Flipper = Flipper

local ExtendedKit = {}
do
	
	local okFlip = pcall(function()
		ExtendedKit.Flipper = Flipper
	end)

	
	function ExtendedKit.Icon(name)
		return GetIcon(name)
	end

	
	ExtendedKit.ListProfiles = ListConfigs
	ExtendedKit.SaveProfile = SaveNamedConfig
	ExtendedKit.LoadProfile = LoadNamedConfig
	ExtendedKit.DeleteProfile = DeleteNamedConfig
end

Library.ExtendedKit = ExtendedKit

local _MergedArchive = {
	AcrylicBuilders = [=[function Library._CreateButton(tab, config)
    local name = config.Name or "Button"
    local callback = config.Callback or function() end

    local frame = CreateInstance("Frame", {
        Name = "Button_" .. name,
        BackgroundColor3 = c.Secondary,
        BackgroundTransparency = 0.4,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, s.Button.Height),
        Parent = tab.content
    })
    CreateCorner(frame, 5)
    CreateStroke(frame)

    local nameLabel = CreateInstance("TextLabel", {
        Name = "Name",
        FontFace = f.Regular,
        TextColor3 = c.Text,
        Text = name,
        TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 10, 0.5, -10),
        TextSize = textsize.Normal,
        Size = UDim2.new(0, 200, 0, 20),
        Parent = frame
    })

    local icon = CreateInstance("ImageLabel", {
        Name = "Icon",
        BackgroundTransparency = 1,
        Image = "rbxassetid://10734898355",
        ImageColor3 = c.Text,
        Position = UDim2.new(1, -30, 0.5, -10),
        Size = UDim2.new(0, 20, 0, 20),
        Parent = frame
    })
    CreateInstance("UIAspectRatioConstraint", {
        Parent = icon
    })

    local button = CreateInstance("TextButton", {
        Name = "Button",
        Text = "",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Parent = frame
    })

    button.MouseButton1Click:Connect(function()
        CreateTween(frame, {BackgroundTransparency = 0.2}, animationspeed.Fast)
        task.wait(0.1)
        CreateTween(frame, {BackgroundTransparency = 0.4}, animationspeed.Fast)
        callback()
    end)

    return {
        SetText = function(_, text)
            nameLabel.Text = text
        end
    }
end

function Library._CreateToggle(tab, config)
    local name = config.Name or "Toggle"
    local default = config.Default or false
    local callback = config.Callback or function() end
    local flag = config.Flag
    local enabled = default

    local frame = CreateInstance("Frame", {
        Name = "Toggle_" .. name,
        BackgroundColor3 = c.Secondary,
        BackgroundTransparency = 0.4,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, s.Button.Height),
        Parent = tab.content
    })
    CreateCorner(frame, 5)
    CreateStroke(frame)

    local nameLabel = CreateInstance("TextLabel", {
        Name = "Name",
        FontFace = f.Regular,
        TextColor3 = c.Text,
        Text = name,
        TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 10, 0.5, -10),
        TextSize = textsize.Normal,
        Size = UDim2.new(0, 200, 0, 20),
        Parent = frame
    })

    local switchBg = CreateInstance("Frame", {
        Name = "SwitchBackground",
        BackgroundColor3 = enabled and c.Toggle.Enabled or c.Toggle.Disabled,
        Position = UDim2.new(1, -48, 0.5, -10),
        BorderSizePixel = 0,
        Size = UDim2.new(0, s.Toggle.Width, 0, s.Toggle.Height),
        Parent = frame
    })
    CreateCorner(switchBg, 100)

    local switchCircle = CreateInstance("Frame", {
        Name = "Circle",
        BackgroundColor3 = c.Toggle.Circle,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = enabled and UDim2.new(0, 21, 0.5, 0) or UDim2.new(0, 4, 0.5, 0),
        BorderSizePixel = 0,
        Size = UDim2.new(0, s.Toggle.Circle, 0, s.Toggle.Circle),
        Parent = switchBg
    })
    CreateCorner(switchCircle, 100)

    local toggleBtn = CreateInstance("TextButton", {
        Name = "ToggleButton",
        Text = "",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Parent = switchCircle
    })

    local button = CreateInstance("TextButton", {
        Name = "Button",
        Text = "",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Parent = frame
    })

    local function UpdateToggle()
        if enabled then
            CreateTween(switchBg, {BackgroundColor3 = c.Toggle.Enabled}, animationspeed.Normal)
            CreateTween(switchCircle, {Position = UDim2.new(0, 21, 0.5, 0)}, animationspeed.Normal)
        else
            CreateTween(switchBg, {BackgroundColor3 = c.Toggle.Disabled}, animationspeed.Normal)
            CreateTween(switchCircle, {Position = UDim2.new(0, 4, 0.5, 0)}, animationspeed.Normal)
        end
    end

    button.MouseButton1Click:Connect(function()
        enabled = not enabled
        UpdateToggle()
        callback(enabled)
    end)

    local methods = {
        SetValue = function(_, value)
            enabled = value
            UpdateToggle()
            callback(enabled)
        end,
        GetValue = function()
            return enabled
        end
    }

    if flag and tab._library then
        tab._library:_RegisterConfigElement(flag, "Toggle", 
            function() return enabled end,
            function(value) methods:SetValue(value) end
        )
    end

    return methods
end

function Library._CreateDropdown(tab, config)
    local name = config.Name or "Dropdown"
    local options = config.Options or {"Option 1", "Option 2", "Option 3"}
    local default = config.Default or options[1]
    local multiSelect = config.MultiSelect or false
    local callback = config.Callback or function() end
    local flag = config.Flag
    local selected = multiSelect and {} or default
    local expanded = false

    if multiSelect and type(default) == "table" then
        selected = default
    elseif multiSelect then
        selected = {}
    end

    local frame = CreateInstance("Frame", {
        Name = "Dropdown_" .. name,
        BackgroundColor3 = c.Secondary,
        BackgroundTransparency = 0.4,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, s.Dropdown.Height),
        ClipsDescendants = false,
        ZIndex = 1,
        Parent = tab.content
    })
    CreateCorner(frame, 5)
    CreateStroke(frame)

    local nameLabel = CreateInstance("TextLabel", {
        Name = "Name",
        FontFace = f.Regular,
        TextColor3 = c.Text,
        Text = name,
        TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 10, 0, 10),
        TextSize = textsize.Normal,
        Size = UDim2.new(0, 200, 0, 20),
        ZIndex = 1,
        Parent = frame
    })

    local selectedDisplay = CreateInstance("Frame", {
        Name = "SelectedDisplay",
        BackgroundColor3 = c.Secondary,
        BackgroundTransparency = 0.04,
        Position = UDim2.new(1, -145, 0, 6),
        BorderSizePixel = 0,
        Size = UDim2.new(0, 135, 0, 26),
        ZIndex = 2,
        Parent = frame
    })
    CreateCorner(selectedDisplay, 5)
    CreateStroke(selectedDisplay)

    local selectedLabel = CreateInstance("TextLabel", {
        Name = "SelectedLabel",
        FontFace = f.Regular,
        TextColor3 = c.Text,
        Text = multiSelect and (#selected > 0 and table.concat(selected, ", ") or "None") or tostring(selected),
        TextTruncate = Enum.TextTruncate.AtEnd,
        BackgroundTransparency = 1,
        TextSize = textsize.Small,
        Size = UDim2.new(1, -30, 1, 0),
        Position = UDim2.new(0, 10, 0, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 2,
        Parent = selectedDisplay
    })

    local arrow = CreateInstance("ImageLabel", {
        Name = "Arrow",
        Image = "rbxassetid://105558791071013",
        ImageColor3 = c.TextDark,
        BackgroundTransparency = 1,
        Position = UDim2.new(1, -20, 0.5, -5),
        Size = UDim2.new(0, 10, 0, 10),
        Rotation = 0,
        ZIndex = 2,
        Parent = selectedDisplay
    })

    local maxVisibleOptions = 5
    local totalOptionsHeight = math.min(#options * s.Dropdown.OptionHeight, maxVisibleOptions * s.Dropdown.OptionHeight)

    local optionsContainer = CreateInstance("Frame", {
        Name = "OptionsContainer",
        BackgroundColor3 = c.Secondary,
        BackgroundTransparency = 0.04,
        Position = UDim2.new(1, -145, 0, 38),
        BorderSizePixel = 0,
        Size = UDim2.new(0, 135, 0, totalOptionsHeight),
        Visible = false,
        ZIndex = 100,
        ClipsDescendants = true,
        Parent = frame
    })
    CreateCorner(optionsContainer, 5)
    CreateStroke(optionsContainer)

    local optionsScroll = CreateInstance("ScrollingFrame", {
        Name = "OptionsScroll",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0),
        CanvasSize = UDim2.new(0, 0, 0, #options * s.Dropdown.OptionHeight),
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = Color3.fromRGB(60, 60, 60),
        ZIndex = 100,
        Parent = optionsContainer
    })
    CreateListLayout(optionsScroll, 0, Enum.SortOrder.LayoutOrder)

    local function UpdateSelectedText()
        if multiSelect then
            selectedLabel.Text = #selected > 0 and table.concat(selected, ", ") or "None"
        else
            selectedLabel.Text = tostring(selected)
        end
    end

    local function CreateOptionButton(option)
        local optionBtn = CreateInstance("TextButton", {
            Name = option,
            FontFace = f.Regular,
            TextColor3 = c.Text,
            Text = option,
            BackgroundColor3 = Color3.fromRGB(30, 30, 30),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            TextSize = textsize.Small,
            Size = UDim2.new(1, 0, 0, s.Dropdown.OptionHeight),
            ZIndex = 100,
            Parent = optionsScroll
        })

        optionBtn.MouseEnter:Connect(function()
            CreateTween(optionBtn, {BackgroundTransparency = 0.5}, animationspeed.Fast)
        end)

        optionBtn.MouseLeave:Connect(function()
            CreateTween(optionBtn, {BackgroundTransparency = 1}, animationspeed.Fast)
        end)

        optionBtn.MouseButton1Click:Connect(function()
            if multiSelect then
                local index = table.find(selected, option)
                if index then
                    table.remove(selected, index)
                else
                    table.insert(selected, option)
                end
                UpdateSelectedText()
                callback(selected)
            else
                selected = option
                UpdateSelectedText()
                callback(selected)
                expanded = false
                optionsContainer.Visible = false
                CreateTween(arrow, {Rotation = 0}, animationspeed.Normal)
                frame.ZIndex = 1
            end
        end)

        return optionBtn
    end

    for _, option in ipairs(options) do
        CreateOptionButton(option)
    end

    local toggleBtn = CreateInstance("TextButton", {
        Name = "ToggleBtn",
        Text = "",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        ZIndex = 3,
        Parent = selectedDisplay
    })

    toggleBtn.MouseButton1Click:Connect(function()
        expanded = not expanded
        optionsContainer.Visible = expanded
        CreateTween(arrow, {Rotation = expanded and 180 or 0}, animationspeed.Normal)
        frame.ZIndex = expanded and 10 or 1
    end)

    local methods = {
        SetValue = function(_, value)
            if multiSelect and type(value) == "table" then
                selected = value
            elseif not multiSelect then
                selected = value
            end
            UpdateSelectedText()
            callback(selected)
        end,
        GetValue = function()
            return selected
        end,
        Refresh = function(_, newOptions)
            options = newOptions
            for _, child in ipairs(optionsScroll:GetChildren()) do
                if child:IsA("TextButton") then
                    child:Destroy()
                end
            end
            for _, option in ipairs(options) do
                CreateOptionButton(option)
            end
            optionsScroll.CanvasSize = UDim2.new(0, 0, 0, #options * s.Dropdown.OptionHeight)
            local newTotalHeight = math.min(#options * s.Dropdown.OptionHeight, maxVisibleOptions * s.Dropdown.OptionHeight)
            optionsContainer.Size = UDim2.new(0, 135, 0, newTotalHeight)
        end
    }

    if flag and tab._library then
        tab._library:_RegisterConfigElement(flag, "Dropdown", 
            function() return selected end,
            function(value) methods:SetValue(value) end
        )
    end

    return methods
end

function Library._CreateKeybind(tab, config, lib)
    local name = config.Name or "Keybind"
    local default = config.Default or Enum.KeyCode.F
    local callback = config.Callback or function() end
    local flag = config.Flag
    local currentKey = default
    local listening = false

    local frame = CreateInstance("Frame", {
        Name = "Keybind_" .. name,
        BackgroundColor3 = c.Secondary,
        BackgroundTransparency = 0.4,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, s.Button.Height),
        Parent = tab.content
    })
    CreateCorner(frame, 5)
    CreateStroke(frame)

    local nameLabel = CreateInstance("TextLabel", {
        Name = "Name",
        FontFace = f.Regular,
        TextColor3 = c.Text,
        Text = name,
        TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 10, 0.5, -10),
        TextSize = textsize.Normal,
        Size = UDim2.new(0, 200, 0, 20),
        Parent = frame
    })

    local keybindBox = CreateInstance("Frame", {
        Name = "KeybindBox",
        BackgroundColor3 = c.Secondary,
        BackgroundTransparency = 0.04,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        BorderSizePixel = 0,
        Size = UDim2.new(0, 30, 0, 26),
        Parent = frame
    })
    CreateCorner(keybindBox, 5)
    CreateStroke(keybindBox)

    local keyLabel = CreateInstance("TextLabel", {
        Name = "KeyLabel",
        FontFace = f.Regular,
        TextColor3 = c.Text,
        Text = currentKey.Name,
        BackgroundTransparency = 1,
        TextSize = textsize.Normal,
        Size = UDim2.new(1, 0, 1, 0),
        Parent = keybindBox
    })

    local button = CreateInstance("TextButton", {
        Name = "Button",
        Text = "",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Parent = keybindBox
    })

    local keybindId = name .. "_" .. tostring(tick())

    lib._keybinds[keybindId] = {
        key = currentKey,
        callback = callback
    }

    local function UpdateKeyDisplay()
        if listening then
            keyLabel.Text = "..."
            keybindBox.Size = UDim2.new(0, 43, 0, 26)
        else
            local keyName = currentKey.Name
            local textWidth = math.max(#keyName * 9 + 10, 24)
            keybindBox.Size = UDim2.new(0, textWidth, 0, 26)
            keyLabel.Text = keyName
        end
    end

    button.MouseButton1Click:Connect(function()
        listening = true
        UpdateKeyDisplay()
    end)

    local inputConnection
    inputConnection = ui.InputBegan:Connect(function(input, gameProcessed)
        if listening and input.UserInputType == Enum.UserInputType.Keyboard then
            currentKey = input.KeyCode
            listening = false
            lib._keybinds[keybindId].key = currentKey
            UpdateKeyDisplay()
        end
    end)

    table.insert(Connections, inputConnection)
    UpdateKeyDisplay()

    local methods = {
        SetKey = function(_, keyCode)
            currentKey = keyCode
            lib._keybinds[keybindId].key = currentKey
            UpdateKeyDisplay()
        end,
        GetKey = function()
            return currentKey
        end
    }

    if flag and lib then
        lib:_RegisterConfigElement(flag, "Keybind", 
            function() return currentKey end,
            function(value) methods:SetKey(value) end
        )
    end

    return methods
end

function Library._CreateColorPicker(tab, config)
    local name = config.Name or "Color Picker"
    local default = config.Default or Color3.fromRGB(255, 255, 255)
    local callback = config.Callback or function() end
    local flag = config.Flag
    local currentColor = default
    local hue, sat, val = currentColor:ToHSV()
    local expanded = false

    local frame = CreateInstance("Frame", {
        Name = "ColorPicker_" .. name,
        BackgroundColor3 = c.Secondary,
        BackgroundTransparency = 0.4,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, s.Button.Height),
        Parent = tab.content
    })
    CreateCorner(frame, 6)
    CreateStroke(frame)

    local nameLabel = CreateInstance("TextLabel", {
        Name = "Name",
        FontFace = f.Regular,
        TextColor3 = c.Text,
        Text = name,
        TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 10, 0, 0),
        TextSize = textsize.Normal,
        Size = UDim2.new(1, -50, 1, 0),
        Parent = frame
    })

    local colorPreview = CreateInstance("Frame", {
        Name = "ColorPreview",
        BackgroundColor3 = currentColor,
        Position = UDim2.new(1, -45, 0.5, -8),
        Size = UDim2.new(0, 35, 0, 16),
        ZIndex = 2,
        Parent = frame
    })
    CreateCorner(colorPreview, 4)
    CreateStroke(colorPreview)

    local previewBtn = CreateInstance("TextButton", {
        Text = "",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        ZIndex = 3,
        Parent = colorPreview
    })

    local pickerContainer = CreateInstance("Frame", {
        Name = "PickerContainer",
        BackgroundColor3 = Color3.fromRGB(20, 20, 20),
        BorderSizePixel = 0,
        Size = UDim2.new(0, 160, 0, 115),
        Visible = false,
        ZIndex = 3000,
        Parent = tab.content:FindFirstAncestorOfClass("ScreenGui") or tab.content
    })
    CreateCorner(pickerContainer, 6)

    local containerStroke = CreateInstance("UIStroke", {
        Color = Color3.fromRGB(40, 40, 40),
        Thickness = 1,
        Parent = pickerContainer
    })

    local svPicker = CreateInstance("Frame", {
        Name = "SVPicker",
        BackgroundColor3 = Color3.fromHSV(hue, 1, 1),
        Position = UDim2.new(0, 8, 0, 8),
        Size = UDim2.new(1, -16, 0, 85),
        ZIndex = 3001,
        Parent = pickerContainer
    })
    CreateCorner(svPicker, 4)

    local whiteLayer = CreateInstance("Frame", {
        BackgroundColor3 = Color3.new(1, 1, 1),
        Size = UDim2.new(1, 0, 1, 0),
        ZIndex = 3002,
        Parent = svPicker
    })
    CreateCorner(whiteLayer, 4)

    local whiteGrad = CreateInstance("UIGradient", {
        Color = ColorSequence.new(Color3.new(1, 1, 1)),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 1)
        }),
        Parent = whiteLayer
    })

    local blackLayer = CreateInstance("Frame", {
        BackgroundColor3 = Color3.new(0, 0, 0),
        Size = UDim2.new(1, 0, 1, 0),
        ZIndex = 3003,
        Parent = svPicker
    })
    CreateCorner(blackLayer, 4)

    local blackGrad = CreateInstance("UIGradient", {
        Color = ColorSequence.new(Color3.new(0, 0, 0)),
        Rotation = 90,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(1, 0)
        }),
        Parent = blackLayer
    })

    local svCursor = CreateInstance("Frame", {
        Name = "Cursor",
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(sat, 0, 1 - val, 0),
        Size = UDim2.new(0, 10, 0, 10),
        ZIndex = 3005,
        Parent = svPicker
    })

    local svCursorStroke = CreateInstance("UIStroke", {
        Thickness = 1.5,
        Color = Color3.new(1, 1, 1),
        Parent = svCursor
    })
    CreateCorner(svCursor, 100)

    local hueSlider = CreateInstance("Frame", {
        Name = "HueSlider",
        Position = UDim2.new(0, 8, 0, 98),
        Size = UDim2.new(1, -16, 0, 8),
        ZIndex = 3001,
        Parent = pickerContainer
    })
    CreateCorner(hueSlider, 100)

    local hueGrad = CreateInstance("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 1, 1)),
            ColorSequenceKeypoint.new(0.167, Color3.fromHSV(0.167, 1, 1)),
            ColorSequenceKeypoint.new(0.333, Color3.fromHSV(0.333, 1, 1)),
            ColorSequenceKeypoint.new(0.5, Color3.fromHSV(0.5, 1, 1)),
            ColorSequenceKeypoint.new(0.667, Color3.fromHSV(0.667, 1, 1)),
            ColorSequenceKeypoint.new(0.833, Color3.fromHSV(0.833, 1, 1)),
            ColorSequenceKeypoint.new(1, Color3.fromHSV(1, 1, 1))
        }),
        Parent = hueSlider
    })

    local hueCursor = CreateInstance("Frame", {
        Name = "HueCursor",
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(hue, 0, 0.5, 0),
        Size = UDim2.new(0, 10, 0, 10),
        ZIndex = 3005,
        Parent = hueSlider
    })
    CreateCorner(hueCursor, 100)
    CreateInstance("UIStroke", {
        Thickness = 1,
        Color = Color3.fromRGB(20, 20, 20),
        Parent = hueCursor
    })

    local function UpdateColor()
        currentColor = Color3.fromHSV(hue, sat, val)
        colorPreview.BackgroundColor3 = currentColor
        svPicker.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
        svCursor.Position = UDim2.new(sat, 0, 1 - val, 0)
        hueCursor.Position = UDim2.new(hue, 0, 0.5, 0)
        callback(currentColor)
    end

    local svDragging, hueDragging = false, false

    local function ProcessInput(input)
        if not pickerContainer.Visible then return end

        if svDragging then
            local size = svPicker.AbsoluteSize
            local pos = svPicker.AbsolutePosition
            sat = math.clamp((input.Position.X - pos.X) / size.X, 0, 1)
            val = 1 - math.clamp((input.Position.Y - pos.Y) / size.Y, 0, 1)
            UpdateColor()
        elseif hueDragging then
            local size = hueSlider.AbsoluteSize
            local pos = hueSlider.AbsolutePosition
            hue = math.clamp((input.Position.X - pos.X) / size.X, 0, 1)
            UpdateColor()
        end
    end

    svPicker.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            svDragging = true
            ProcessInput(input)
        end
    end)

    hueSlider.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            hueDragging = true
            ProcessInput(input)
        end
    end)

    ui.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            ProcessInput(input)
        end
    end)

    ui.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            svDragging = false
            hueDragging = false
        end
    end)

    local function ClosePicker()
        pickerContainer.Visible = false
        expanded = false
        if Library.ActivePicker == ClosePicker then
            Library.ActivePicker = nil
        end
    end

    local function OpenPicker()
        if Library.ActivePicker then
            Library.ActivePicker()
        end
        Library.ActivePicker = ClosePicker

        local btnPos = colorPreview.AbsolutePosition
        local viewport = workspace.CurrentCamera.ViewportSize
        local targetX = btnPos.X - 170
        local targetY = btnPos.Y

        if targetY + 115 > viewport.Y then
            targetY = viewport.Y - 125
        end
        if targetX < 0 then
            targetX = btnPos.X + 50
        end

        pickerContainer.Position = UDim2.new(0, targetX, 0, targetY)
        pickerContainer.Visible = true
        expanded = true
    end

    previewBtn.MouseButton1Click:Connect(function()
        if expanded then
            ClosePicker()
        else
            OpenPicker()
        end
    end)

    local methods = {
        SetColor = function(_, color)
            currentColor = color
            hue, sat, val = color:ToHSV()
            UpdateColor()
        end,
        GetColor = function()
            return currentColor
        end
    }

    if flag and tab._library then
        tab._library:_RegisterConfigElement(flag, "ColorPicker", 
            function() return currentColor end,
            function(value) methods:SetColor(value) end
        )
    end

    return methods
end

function Library._CreateTextBox(tab, config)
    local name = config.Name or "TextBox"
    local default = config.Default or ""
    local placeholder = config.Placeholder or "Enter text..."
    local callback = config.Callback or function() end
    local clearOnFocus = config.ClearOnFocus or false
    local numbersOnly = config.NumbersOnly or false
    local flag = config.Flag
    local currentText = default

    local frame = CreateInstance("Frame", {
        Name = "TextBox_" .. name,
        BackgroundColor3 = c.Secondary,
        BackgroundTransparency = 0.4,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, s.TextBox.Height),
        Parent = tab.content
    })
    CreateCorner(frame, 5)
    CreateStroke(frame)

    local nameLabel = CreateInstance("TextLabel", {
        Name = "Name",
        FontFace = f.Regular,
        TextColor3 = c.Text,
        Text = name,
        TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 10, 0.5, -10),
        TextSize = textsize.Normal,
        Size = UDim2.new(0, 150, 0, 20),
        Parent = frame
    })

    local icon = CreateInstance("ImageLabel", {
        Name = "Icon",
        BackgroundTransparency = 1,
        Image = "rbxassetid://93828793199781",
        ImageColor3 = c.TextDark,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -165, 0.5, 0),
        Size = UDim2.new(0, 18, 0, 18),
        Parent = frame
    })

    local textBoxContainer = CreateInstance("Frame", {
        Name = "TextBoxContainer",
        BackgroundColor3 = c.Secondary,
        BackgroundTransparency = 0.04,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        BorderSizePixel = 0,
        Size = UDim2.new(0, s.TextBox.InputWidth, 0, 26),
        Parent = frame
    })
    CreateCorner(textBoxContainer, 5)
    local textBoxStroke = CreateStroke(textBoxContainer)

    local textBox = CreateInstance("TextBox", {
        Name = "Input",
        FontFace = f.Regular,
        TextColor3 = c.Text,
        PlaceholderText = placeholder,
        PlaceholderColor3 = c.TextDark,
        Text = currentText,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        BackgroundTransparency = 1,
        TextSize = textsize.Small,
        Size = UDim2.new(1, -16, 1, 0),
        Position = UDim2.new(0, 8, 0, 0),
        ClearTextOnFocus = clearOnFocus,
        Parent = textBoxContainer
    })

    textBox.Focused:Connect(function()
        CreateTween(textBoxContainer, {BackgroundTransparency = 0}, animationspeed.Fast)
        CreateTween(textBoxStroke, {Color = c.Accent}, animationspeed.Fast)
        CreateTween(icon, {ImageColor3 = c.Text}, animationspeed.Fast)
    end)

    textBox.FocusLost:Connect(function(enterPressed)
        CreateTween(textBoxContainer, {BackgroundTransparency = 0.04}, animationspeed.Fast)
        CreateTween(textBoxStroke, {Color = c.Border}, animationspeed.Fast)
        CreateTween(icon, {ImageColor3 = c.TextDark}, animationspeed.Fast)
        
        if numbersOnly then
            local numValue = tonumber(textBox.Text)
            if numValue then
                currentText = tostring(numValue)
                textBox.Text = currentText
            else
                textBox.Text = currentText
            end
        else
            currentText = textBox.Text
        end
        
        callback(currentText, enterPressed)
    end)

    if numbersOnly then
        textBox:GetPropertyChangedSignal("Text"):Connect(function()
            local text = textBox.Text
            local filtered = text:gsub("[^%d%.%-]", "")
            if text ~= filtered then
                textBox.Text = filtered
            end
        end)
    end

    local methods = {
        SetText = function(_, text)
            currentText = tostring(text)
            textBox.Text = currentText
        end,
        GetText = function()
            return currentText
        end,
        SetPlaceholder = function(_, newPlaceholder)
            textBox.PlaceholderText = newPlaceholder
        end,
        Focus = function()
            textBox:CaptureFocus()
        end
    }

    if flag and tab._library then
        tab._library:_RegisterConfigElement(flag, "TextBox", 
            function() return currentText end,
            function(value) methods:SetText(value) end
        )
    end

    return methods
end

function Library._CreateConfigSection(tab)
    local lib = tab._library
    
    Library._CreateContentSection(tab, "Configuration")

    local configNameBox = Library._CreateTextBox(tab, {
        Name = "Config Name",
        Default = "default",
        Placeholder = "Enter config name...",
        Callback = function(text)
            lib._currentConfig = text
        end
    })

    local configDropdown
    configDropdown = Library._CreateDropdown(tab, {
        Name = "Select Config",
        Options = lib:GetConfigs(),
        Default = "default",
        Callback = function(selected)
            configNameBox:SetText(selected)
            lib._currentConfig = selected
        end
    })

    Library._CreateButton(tab, {
        Name = "Save Config",
        Callback = function()
            local configName = configNameBox:GetText()
            if configName and configName ~= "" then
                lib:SaveConfig(configName)
                configDropdown:Refresh(lib:GetConfigs())
            end
        end
    })

    Library._CreateButton(tab, {
        Name = "Load Config",
        Callback = function()
            local configName = configNameBox:GetText()
            if configName and configName ~= "" then
                lib:LoadConfig(configName)
            end
        end
    })

    Library._CreateButton(tab, {
        Name = "Delete Config",
        Callback = function()
            local configName = configNameBox:GetText()
            if configName and configName ~= "" then
                lib:DeleteConfig(configName)
                configDropdown:Refresh(lib:GetConfigs())
            end
        end
    })

    Library._CreateButton(tab, {
        Name = "Refresh Configs",
        Callback = function()
            configDropdown:Refresh(lib:GetConfigs())
            lib:Notify({
                Title = "Configs Refreshed",
                Description = "Config list updated",
                Duration = 2,
                Icon = "rbxassetid://10723356507"
            })
        end
    })

    Library._CreateToggle(tab, {
        Name = "Auto Save",
        Default = false,
        Callback = function(enabled)
            lib:SetAutoSave(enabled)
        end
    })

    return {
        RefreshConfigs = function()
            configDropdown:Refresh(lib:GetConfigs())
        end
    }
end

]=],
	FluentCreatorSlice = [=[local Creator = {
	Registry = {},
	Signals = {},
	TransparencyMotors = {},
	DefaultProperties = {
		ScreenGui = {
			ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		},
		Frame = {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
		},
		ScrollingFrame = {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderColor3 = Color3.new(0, 0, 0),
			ScrollBarImageColor3 = Color3.new(0, 0, 0),
		},
		TextLabel = {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderColor3 = Color3.new(0, 0, 0),
			Font = Enum.Font.SourceSans,
			Text = "",
			TextColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 1,
			TextSize = 14,
		},
		TextButton = {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderColor3 = Color3.new(0, 0, 0),
			AutoButtonColor = false,
			Font = Enum.Font.SourceSans,
			Text = "",
			TextColor3 = Color3.new(0, 0, 0),
			TextSize = 14,
		},
		TextBox = {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderColor3 = Color3.new(0, 0, 0),
			ClearTextOnFocus = false,
			Font = Enum.Font.SourceSans,
			Text = "",
			TextColor3 = Color3.new(0, 0, 0),
			TextSize = 14,
		},
		ImageLabel = {
			BackgroundTransparency = 1,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
		},
		ImageButton = {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderColor3 = Color3.new(0, 0, 0),
			AutoButtonColor = false,
		},
		CanvasGroup = {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
		},
	},
}

local function ApplyCustomProps(Object, Props)
	if Props.ThemeTag then
		Creator.AddThemeObject(Object, Props.ThemeTag)
	end
end

function Creator.AddSignal(Signal, Function)
	table.insert(Creator.Signals, Signal:Connect(Function))
end

function Creator.Disconnect()
	for Idx = #Creator.Signals, 1, -1 do
		local Connection = table.remove(Creator.Signals, Idx)
		Connection:Disconnect()
	end
end

function Creator.GetThemeProperty(Property)
	if Themes[Library.Theme][Property] then
		return Themes[Library.Theme][Property]
	end
	return Themes["Dark"][Property]
end

function Creator.UpdateTheme()
	for Instance, Object in next, Creator.Registry do
		for Property, ColorIdx in next, Object.Properties do
			Instance[Property] = Creator.GetThemeProperty(ColorIdx)
		end
	end

	for _, Motor in next, Creator.TransparencyMotors do
		Motor:setGoal(Flipper.Instant.new(Creator.GetThemeProperty("ElementTransparency")))
	end
end

function Creator.AddThemeObject(Object, Properties)
	local Idx = #Creator.Registry + 1
	local Data = {
		Object = Object,
		Properties = Properties,
		Idx = Idx,
	}

	Creator.Registry[Object] = Data
	Creator.UpdateTheme()
	return Object
end

function Creator.OverrideTag(Object, Properties)
	Creator.Registry[Object].Properties = Properties
	Creator.UpdateTheme()
end

function Creator.New(Name, Properties, Children)
	local Object = Instance.new(Name)

	for Name, Value in next, Creator.DefaultProperties[Name] or {} do
		Object[Name] = Value
	end

	for Name, Value in next, Properties or {} do
		if Name ~= "ThemeTag" then
			Object[Name] = Value
		end
	end

	for _, Child in next, Children or {} do
		Child.Parent = Object
	end

	ApplyCustomProps(Object, Properties)
	return Object
end

function Creator.SpringMotor(Initial, Instance, Prop, IgnoreDialogCheck, ResetOnThemeChange)
	IgnoreDialogCheck = IgnoreDialogCheck or false
	ResetOnThemeChange = ResetOnThemeChange or false
	local Motor = Flipper.SingleMotor.new(Initial)
	Motor:onStep(function(value)
		Instance[Prop] = value
	end)

	if ResetOnThemeChange then
		table.insert(Creator.TransparencyMotors, Motor)
	end

	local function SetValue(Value, Ignore)
		Ignore = Ignore or false
		if not IgnoreDialogCheck then
			if not Ignore then
				if Prop == "BackgroundTransparency" and Library.DialogOpen then
					return
				end
			end
		end
		Motor:setGoal(Flipper.Spring.new(Value, { frequency = 8 }))
	end

	return Motor, SetValue
end

local New = Creator.New

local GUI = New("ScreenGui", {
	Parent = RunService:IsStudio() and LocalPlayer.PlayerGui or CoreGui,
})
ProtectGui(GUI)
Library.GUI = GUI

function Library:SafeCallback(Function, ...)
	if not Function then
		return
	end

	local Success, Event = pcall(Function, ...)
	if not Success then
		local _, i = Event:find(":%d+: ")

		if not i then
			return Library:Notify({
				Title = "Interface",
				Content = "Callback error",
				SubContent = Event,
				Duration = 5,
			})
		end

		return Library:Notify({
			Title = "Interface",
			Content = "Callback error",
			SubContent = Event:sub(i + 1),
			Duration = 5,
		})
	end
end

function Library:Round(Number, Factor)
	if Factor == 0 then
		return math.floor(Number)
	end
	Number = tostring(Number)
	return Number:find("%.") and tonumber(Number:sub(1, Number:find("%.") + Factor)) or Number
end

local function map(value, inMin, inMax, outMin, outMax)
	return (value - inMin) * (outMax - outMin) / (inMax - inMin) + outMin
end

local function viewportPointToWorld(location, distance)
	local unitRay = game:GetService("Workspace").CurrentCamera:ScreenPointToRay(location.X, location.Y)
	return unitRay.Origin + unitRay.Direction * distance
end

local function getOffset()
	local viewportSizeY = game:GetService("Workspace").CurrentCamera.ViewportSize.Y
	return map(viewportSizeY, 0, 2560, 8, 56)
end

local function createAcrylic()
	local Part = Creator.New("Part", {
		Name = "Body",
		Color = Color3.new(0, 0, 0),
		Material = Enum.Material.Glass,
		Size = Vector3.new(1, 1, 0),
		Anchored = true,
		CanCollide = false,
		Locked = true,
		CastShadow = false,
		Transparency = 0.98,
	}, {
		Creator.New("SpecialMesh", {
			MeshType = Enum.MeshType.Brick,
			Offset = Vector3.new(0, 0, -0.000001),
		}),
	})

	return Part
end

local BlurFolder = Instance.new("Folder", game:GetService("Workspace").CurrentCamera)

local function createAcrylicBlur(distance)
	local cleanups = {}

	distance = distance or 0.001
	local positions = {
		topLeft = Vector2.new(),
		topRight = Vector2.new(),
		bottomRight = Vector2.new(),
	}
	local model = createAcrylic()
	model.Parent = BlurFolder

	local function updatePositions(size, position)
		positions.topLeft = position
		positions.topRight = position + Vector2.new(size.X, 0)
		positions.bottomRight = position + size
	end

	local function render()
		local res = game:GetService("Workspace").CurrentCamera
		if res then
			res = res.CFrame
		end
		local cond = res
		if not cond then
			cond = CFrame.new()
		end

		local camera = cond
		local topLeft = positions.topLeft
		local topRight = positions.topRight
		local bottomRight = positions.bottomRight

		local topLeft3D = viewportPointToWorld(topLeft, distance)
		local topRight3D = viewportPointToWorld(topRight, distance)
		local bottomRight3D = viewportPointToWorld(bottomRight, distance)

		local width = (topRight3D - topLeft3D).Magnitude
		local height = (topRight3D - bottomRight3D).Magnitude

		model.CFrame =
			CFrame.fromMatrix((topLeft3D + bottomRight3D) / 2, camera.XVector, camera.YVector, camera.ZVector)
		model.Mesh.Scale = Vector3.new(width, height, 0)
	end

	local function onChange(rbx)
		local offset = getOffset()
		local size = rbx.AbsoluteSize - Vector2.new(offset, offset)
		local position = rbx.AbsolutePosition + Vector2.new(offset / 2, offset / 2)

		updatePositions(size, position)
		task.spawn(render)
	end

	local function renderOnChange()
		local camera = game:GetService("Workspace").CurrentCamera
		if not camera then
			return
		end

		table.insert(cleanups, camera:GetPropertyChangedSignal("CFrame"):Connect(render))
		table.insert(cleanups, camera:GetPropertyChangedSignal("ViewportSize"):Connect(render))
		table.insert(cleanups, camera:GetPropertyChangedSignal("FieldOfView"):Connect(render))
		task.spawn(render)
	end

	model.Destroying:Connect(function()
		for _, item in cleanups do
			pcall(function()
				item:Disconnect()
			end)
		end
	end)

	renderOnChange()

	return onChange, model
end

local AcrylicBlur = function(distance)
	local Blur = {}
	local onChange, model = createAcrylicBlur(distance)

	local comp = Creator.New("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	})

	Creator.AddSignal(comp:GetPropertyChangedSignal("AbsolutePosition"), function()
		onChange(comp)
	end)

	Creator.AddSignal(comp:GetPropertyChangedSignal("AbsoluteSize"), function()
		onChange(comp)
	end)

	Blur.AddParent = function(Parent)
		Creator.AddSignal(Parent:GetPropertyChangedSignal("Visible"), function()
			Blur.SetVisibility(Parent.Visible)
		end)
	end

	Blur.SetVisibility = function(Value)
		model.Transparency = Value and 0.98 or 1
	end

	Blur.Frame = comp
	Blur.Model = model

	return Blur
end

local New = Creator.New

local AcrylicPaint = function(props)
	local AcrylicPaint = {}

	AcrylicPaint.Frame = New("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0.9,
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
	}, {
		New("ImageLabel", {
			Image = "rbxassetid://8992230677",
			ScaleType = "Slice",
			SliceCenter = Rect.new(Vector2.new(99, 99), Vector2.new(99, 99)),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.new(1, 120, 1, 116),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			BackgroundTransparency = 1,
			ImageColor3 = Color3.fromRGB(0, 0, 0),
			ImageTransparency = 0.7,
		}),

		New("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}),

		New("Frame", {
			BackgroundTransparency = 0.45,
			Size = UDim2.fromScale(1, 1),
			Name = "Background",
			ThemeTag = {
				BackgroundColor3 = "AcrylicMain",
			},
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
		}),

		New("Frame", {
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 0.4,
			Size = UDim2.fromScale(1, 1),
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),

			New("UIGradient", {
				Rotation = 90,
				ThemeTag = {
					Color = "AcrylicGradient",
				},
			}),
		}),

		New("ImageLabel", {
			Image = "rbxassetid://9968344105",
			ImageTransparency = 0.98,
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.new(0, 128, 0, 128),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
		}),

		New("ImageLabel", {
			Image = "rbxassetid://9968344227",
			ImageTransparency = 0.9,
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.new(0, 128, 0, 128),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ThemeTag = {
				ImageTransparency = "AcrylicNoise",
			},
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
		}),

		New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			New("UIStroke", {
				Transparency = 0.5,
				Thickness = 1,
				ThemeTag = {
					Color = "AcrylicBorder",
				},
			}),
		}),
	})

	local Blur

	if Library.UseAcrylic then
		Blur = AcrylicBlur()
		Blur.Frame.Parent = AcrylicPaint.Frame
		AcrylicPaint.Model = Blur.Model
		AcrylicPaint.AddParent = Blur.AddParent
		AcrylicPaint.SetVisibility = Blur.SetVisibility
	end

	return AcrylicPaint
end

local Acrylic = {
	AcrylicBlur = AcrylicBlur,
	CreateAcrylic = createAcrylic,
	AcrylicPaint = AcrylicPaint,
}

function Acrylic.init()
	local baseEffect = Instance.new("DepthOfFieldEffect")
	baseEffect.FarIntensity = 0
	baseEffect.InFocusRadius = 0.1
	baseEffect.NearIntensity = 1

	local depthOfFieldDefaults = {}

	function Acrylic.Enable()
		for _, effect in pairs(depthOfFieldDefaults) do
			effect.Enabled = false
		end
		baseEffect.Parent = Lighting
	end

	function Acrylic.Disable()
		for _, effect in pairs(depthOfFieldDefaults) do
			effect.Enabled = effect.enabled
		end
		baseEffect.Parent = nil
	end

	local function registerDefaults()
		local function register(object)
			if object:IsA("DepthOfFieldEffect") then
				depthOfFieldDefaults[object] = { enabled = object.Enabled }
			end
		end

		for _, child in pairs(Lighting:GetChildren()) do
			register(child)
		end

		if Workspace.CurrentCamera then
			for _, child in pairs(Workspace.CurrentCamera:GetChildren()) do
				register(child)
			end
		end
	end

	registerDefaults()
	Acrylic.Enable()
end

local Components = {
	Assets = {
	Close = "rbxassetid://9886659671",
	Min = "rbxassetid://9886659276",
	Max = "rbxassetid://9886659406",
	Restore = "rbxassetid://9886659001",
},
}

Components.Element = (function()
	local New = Creator.New

	local Spring = Flipper.Spring.new

	return function(Title, Desc, Parent, Hover)
		local Element = {}

		Element.TitleLabel = New("TextLabel", {
			FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium, Enum.FontStyle.Normal),
			Text = Title,
			TextColor3 = Color3.fromRGB(240, 240, 240),
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 14),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 1,
			ThemeTag = {
				TextColor3 = "Text",
			},
		})

		Element.DescLabel = New("TextLabel", {
			FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json"),
			Text = Desc,
			TextColor3 = Color3.fromRGB(200, 200, 200),
			TextSize = 12,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 14),
			ThemeTag = {
				TextColor3 = "SubText",
			},
		})

		Element.LabelHolder = New("Frame", {
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -28, 0, 0),
		}, {
			New("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),
			New("UIPadding", {
				PaddingBottom = UDim.new(0, 13),
				PaddingTop = UDim.new(0, 13),
			}),
			Element.TitleLabel,
			Element.DescLabel,
		})

		Element.Border = New("UIStroke", {
			Transparency = 0.5,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Color3.fromRGB(0, 0, 0),
			ThemeTag = {
				Color = "ElementBorder",
			},
		})

		Element.Frame = New("TextButton", {
			Size = UDim2.new(1, 0, 0, 0),
			BackgroundTransparency = 0.89,
			BackgroundColor3 = Color3.fromRGB(130, 130, 130),
			Parent = Parent,
			AutomaticSize = Enum.AutomaticSize.Y,
			Text = "",
			LayoutOrder = 7,
			ThemeTag = {
				BackgroundColor3 = "Element",
				BackgroundTransparency = "ElementTransparency",
			},
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
			Element.Border,
			Element.LabelHolder,
		})

		function Element:SetTitle(Set)
			Element.TitleLabel.Text = Set
		end

		function Element:SetDesc(Set)
			if Set == nil then
				Set = ""
			end
			if Set == "" then
				Element.DescLabel.Visible = false
			else
				Element.DescLabel.Visible = true
			end
			Element.DescLabel.Text = Set
		end

		function Element:Destroy()
			Element.Frame:Destroy()
		end

		Element:SetTitle(Title)
		Element:SetDesc(Desc)

		if Hover then
			local Motor, SetTransparency = Creator.SpringMotor(
				Creator.GetThemeProperty("ElementTransparency"),
				Element.Frame,
				"BackgroundTransparency",
				false,
				true
			)

			Creator.AddSignal(Element.Frame.MouseEnter, function()
				SetTransparency(Creator.GetThemeProperty("ElementTransparency") - Creator.GetThemeProperty("HoverChange"))
			end)
			Creator.AddSignal(Element.Frame.MouseLeave, function()
				SetTransparency(Creator.GetThemeProperty("ElementTransparency"))
			end)
			Creator.AddSignal(Element.Frame.MouseButton1Down, function()
				SetTransparency(Creator.GetThemeProperty("ElementTransparency") + Creator.GetThemeProperty("HoverChange"))
			end)
			Creator.AddSignal(Element.Frame.MouseButton1Up, function()
				SetTransparency(Creator.GetThemeProperty("ElementTransparency") - Creator.GetThemeProperty("HoverChange"))
			end)
		end

		return Element
	end
end)()

Components.Button = (function()
	local New = Creator.New

	local Spring = Flipper.Spring.new

	return function(Theme, Parent, DialogCheck)
		DialogCheck = DialogCheck or false
		local Button = {}

		Button.Title = New("TextLabel", {
			FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json"),
			TextColor3 = Color3.fromRGB(200, 200, 200),
			TextSize = 14,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ThemeTag = {
				TextColor3 = "Text",
			},
		})

		Button.HoverFrame = New("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ThemeTag = {
				BackgroundColor3 = "Hover",
			},
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
		})

		Button.Frame = New("TextButton", {
			Size = UDim2.new(0, 0, 0, 32),
			Parent = Parent,
			ThemeTag = {
				BackgroundColor3 = "DialogButton",
			},
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
			New("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Transparency = 0.65,
				ThemeTag = {
					Color = "DialogButtonBorder",
				},
			}),
			Button.HoverFrame,
			Button.Title,
		})

		local Motor, SetTransparency = Creator.SpringMotor(1, Button.HoverFrame, "BackgroundTransparency", DialogCheck)
		Creator.AddSignal(Button.Frame.MouseEnter, function()
			SetTransparency(0.97)
		end)
		Creator.AddSignal(Button.Frame.MouseLeave, function()
			SetTransparency(1)
		end)
		Creator.AddSignal(Button.Frame.MouseButton1Down, function()
			SetTransparency(1)
		end)
		Creator.AddSignal(Button.Frame.MouseButton1Up, function()
			SetTransparency(0.97)
		end)

		return Button
	end
end)()

Components.Textbox = (function()
	local TextService = game:GetService("TextService")
	local New = Creator.New

	return function(Parent, Acrylic)
		Acrylic = Acrylic or false
		local Textbox = {}

		Textbox.Input = New("TextBox", {
			FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json"),
			TextColor3 = Color3.fromRGB(200, 200, 200),
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromOffset(10, 0),
			ThemeTag = {
				TextColor3 = "Text",
				PlaceholderColor3 = "SubText",
			},
		})

		Textbox.Container = New("Frame", {
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Position = UDim2.new(0, 6, 0, 0),
			Size = UDim2.new(1, -12, 1, 0),
		}, {
			Textbox.Input,
		})

		Textbox.Indicator = New("Frame", {
			Size = UDim2.new(1, -4, 0, 1),
			Position = UDim2.new(0, 2, 1, 0),
			AnchorPoint = Vector2.new(0, 1),
			BackgroundTransparency = Acrylic and 0.5 or 0,
			ThemeTag = {
				BackgroundColor3 = Acrylic and "InputIndicator" or "DialogInputLine",
			},
		})

		Textbox.Frame = New("Frame", {
			Size = UDim2.new(0, 0, 0, 30),
			BackgroundTransparency = Acrylic and 0.9 or 0,
			Parent = Parent,
			ThemeTag = {
				BackgroundColor3 = Acrylic and "Input" or "DialogInput",
			},
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
			New("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Transparency = Acrylic and 0.5 or 0.65,
				ThemeTag = {
					Color = Acrylic and "InElementBorder" or "DialogButtonBorder",
				},
			}),
			Textbox.Indicator,
			Textbox.Container,
		})

		local function Update()
			local PADDING = 2
			local Reveal = Textbox.Container.AbsoluteSize.X

			if not Textbox.Input:IsFocused() or Textbox.Input.TextBounds.X <= Reveal - 2 * PADDING then
				Textbox.Input.Position = UDim2.new(0, PADDING, 0, 0)
			else
				local Cursor = Textbox.Input.CursorPosition
				if Cursor ~= -1 then
					local subtext = string.sub(Textbox.Input.Text, 1, Cursor - 1)
					local width = TextService:GetTextSize(
						subtext,
						Textbox.Input.TextSize,
						Textbox.Input.Font,
						Vector2.new(math.huge, math.huge)
					).X

					local CurrentCursorPos = Textbox.Input.Position.X.Offset + width
					if CurrentCursorPos < PADDING then
						Textbox.Input.Position = UDim2.fromOffset(PADDING - width, 0)
					elseif CurrentCursorPos > Reveal - PADDING - 1 then
						Textbox.Input.Position = UDim2.fromOffset(Reveal - width - PADDING - 1, 0)
					end
				end
			end
		end

		task.spawn(Update)

		Creator.AddSignal(Textbox.Input:GetPropertyChangedSignal("Text"), Update)
		Creator.AddSignal(Textbox.Input:GetPropertyChangedSignal("CursorPosition"), Update)

		Creator.AddSignal(Textbox.Input.Focused, function()
			Update()
			Textbox.Indicator.Size = UDim2.new(1, -2, 0, 2)
			Textbox.Indicator.Position = UDim2.new(0, 1, 1, 0)
			Textbox.Indicator.BackgroundTransparency = 0
			Creator.OverrideTag(Textbox.Frame, { BackgroundColor3 = Acrylic and "InputFocused" or "DialogHolder" })
			Creator.OverrideTag(Textbox.Indicator, { BackgroundColor3 = "Accent" })
		end)

		Creator.AddSignal(Textbox.Input.FocusLost, function()
			Update()
			Textbox.Indicator.Size = UDim2.new(1, -4, 0, 1)
			Textbox.Indicator.Position = UDim2.new(0, 2, 1, 0)
			Textbox.Indicator.BackgroundTransparency = 0.5
			Creator.OverrideTag(Textbox.Frame, { BackgroundColor3 = Acrylic and "Input" or "DialogInput" })
			Creator.OverrideTag(Textbox.Indicator, { BackgroundColor3 = Acrylic and "InputIndicator" or "DialogInputLine" })
		end)

		return Textbox
	end
end)()

Components.Section = (function()
	local New = Creator.New

	return function(Title, Parent)
		local Section = {}

		Section.Layout = New("UIListLayout", {
			Padding = UDim.new(0, 5),
		})

		Section.Container = New("Frame", {
			Size = UDim2.new(1, 0, 0, 26),
			Position = UDim2.fromOffset(0, 24),
			BackgroundTransparency = 1,
		}, {
			Section.Layout,
		})

		Section.Root = New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 26),
			LayoutOrder = 7,
			Parent = Parent,
		}, {
			New("TextLabel", {
				RichText = true,
				Text = Title,
				TextTransparency = 0,
				FontFace = Font.new("rbxassetid://12187365364", Enum.FontWeight.SemiBold, Enum.FontStyle.Normal),
				TextSize = 18,
				TextXAlignment = "Left",
				TextYAlignment = "Center",
				Size = UDim2.new(1, -16, 0, 18),
				Position = UDim2.fromOffset(0, 2),
				ThemeTag = {
					TextColor3 = "Text",
				},
			}),
			Section.Container,
		})

		Creator.AddSignal(Section.Layout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
			Section.Container.Size = UDim2.new(1, 0, 0, Section.Layout.AbsoluteContentSize.Y)
			Section.Root.Size = UDim2.new(1, 0, 0, Section.Layout.AbsoluteContentSize.Y + 25)
		end)
		return Section
	end
end)()

Components.TitleBar = (function()
	local Assets = Components.Assets

	local New = Creator.New
	local AddSignal = Creator.AddSignal

	return function(Config)
		local TitleBar = {}

		local function BarButton(Icon, Pos, Parent, Callback)
			local Button = {
				Callback = Callback or function() end,
			}

			Button.Frame = New("TextButton", {
				Size = UDim2.new(0, 34, 1, -8),
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 1,
				Parent = Parent,
				Position = Pos,
				Text = "",
				ThemeTag = {
					BackgroundColor3 = "Text",
				},
			}, {
				New("UICorner", {
					CornerRadius = UDim.new(0, 7),
				}),
				New("ImageLabel", {
					Image = Icon,
					Size = UDim2.fromOffset(16, 16),
					Position = UDim2.fromScale(0.5, 0.5),
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundTransparency = 1,
					Name = "Icon",
					ThemeTag = {
						ImageColor3 = "Text",
					},
				}),
			})

			local Motor, SetTransparency = Creator.SpringMotor(1, Button.Frame, "BackgroundTransparency")

			AddSignal(Button.Frame.MouseEnter, function()
				SetTransparency(0.94)
			end)
			AddSignal(Button.Frame.MouseLeave, function()
				SetTransparency(1, true)
			end)
			AddSignal(Button.Frame.MouseButton1Down, function()
				SetTransparency(0.96)
			end)
			AddSignal(Button.Frame.MouseButton1Up, function()
				SetTransparency(0.94)
			end)
			AddSignal(Button.Frame.MouseButton1Click, Button.Callback)

			Button.SetCallback = function(Func)
				Button.Callback = Func
			end

			return Button
		end

		TitleBar.Frame = New("Frame", {
			Size = UDim2.new(1, 0, 0, 42),
			BackgroundTransparency = 1,
			Parent = Config.Parent,
		}, {
			New("Frame", {
				Size = UDim2.new(1, -16, 1, 0),
				Position = UDim2.new(0, 16, 0, 0),
				BackgroundTransparency = 1,
			}, {
				New("UIListLayout", {
					Padding = UDim.new(0, 5),
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				New("TextLabel", {
					RichText = true,
					Text = Config.Title,
					FontFace = Font.new(
						"rbxasset://fonts/families/GothamSSm.json",
						Enum.FontWeight.Regular,
						Enum.FontStyle.Normal
					),
					TextSize = 12,
					TextXAlignment = "Left",
					TextYAlignment = "Center",
					Size = UDim2.fromScale(0, 1),
					AutomaticSize = Enum.AutomaticSize.X,
					BackgroundTransparency = 1,
					ThemeTag = {
						TextColor3 = "Text",
					},
				}),
				New("TextLabel", {
					RichText = true,
					Text = Config.SubTitle,
					TextTransparency = 0.4,
					FontFace = Font.new(
						"rbxasset://fonts/families/GothamSSm.json",
						Enum.FontWeight.Regular,
						Enum.FontStyle.Normal
					),
					TextSize = 12,
					TextXAlignment = "Left",
					TextYAlignment = "Center",
					Size = UDim2.fromScale(0, 1),
					AutomaticSize = Enum.AutomaticSize.X,
					BackgroundTransparency = 1,
					ThemeTag = {
						TextColor3 = "Text",
					},
				}),
			}),
			New("Frame", {
				BackgroundTransparency = 0.5,
				Size = UDim2.new(1, 0, 0, 1),
				Position = UDim2.new(0, 0, 1, 0),
				ThemeTag = {
					BackgroundColor3 = "TitleBarLine",
				},
			}),
		})

		TitleBar.CloseButton = BarButton(Assets.Close, UDim2.new(1, -4, 0, 4), TitleBar.Frame, function()
			Library.Window:Dialog({
				Title = "Close",
				Content = "Are you sure you want to unload the interface?",
				Buttons = {
					{
						Title = "Yes",
						Callback = function()
							Library:Destroy()
						end,
					},
					{
						Title = "No",
					},
				},
			})
		end)
		TitleBar.MaxButton = BarButton(Assets.Max, UDim2.new(1, -40, 0, 4), TitleBar.Frame, function()
			Config.Window.Maximize(not Config.Window.Maximized)
		end)
		TitleBar.MinButton = BarButton(Assets.Min, UDim2.new(1, -80, 0, 4), TitleBar.Frame, function()
			Library.Window:Minimize()
		end)

		return TitleBar
	end
end)()

Components.Notification = (function()
	local Spring = Flipper.Spring.new
	local Instant = Flipper.Instant.new
	local New = Creator.New

	local Notification = {}

	function Notification:Init(GUI)
		Notification.Holder = New("Frame", {
			Position = UDim2.new(1, -30, 1, -30),
			Size = UDim2.new(0, 310, 1, -30),
			AnchorPoint = Vector2.new(1, 1),
			BackgroundTransparency = 1,
			Parent = GUI,
		}, {
			New("UIListLayout", {
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
				Padding = UDim.new(0, 20),
			}),
		})
	end

	function Notification:New(Config)
		Config.Title = Config.Title or "Title"
		Config.Content = Config.Content or "Content"
		Config.SubContent = Config.SubContent or ""
		Config.Duration = Config.Duration or nil
		Config.Buttons = Config.Buttons or {}
		local NewNotification = {
			Closed = false,
		}

		NewNotification.AcrylicPaint = Acrylic.AcrylicPaint()

		NewNotification.Title = New("TextLabel", {
			Position = UDim2.new(0, 14, 0, 17),
			Text = Config.Title,
			RichText = true,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextTransparency = 0,
			FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json"),
			TextSize = 13,
			TextXAlignment = "Left",
			TextYAlignment = "Center",
			Size = UDim2.new(1, -12, 0, 12),
			TextWrapped = true,
			BackgroundTransparency = 1,
			ThemeTag = {
				TextColor3 = "Text",
			},
		})

		NewNotification.ContentLabel = New("TextLabel", {
			FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json"),
			Text = Config.Content,
			TextColor3 = Color3.fromRGB(240, 240, 240),
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 14),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 1,
			TextWrapped = true,
			ThemeTag = {
				TextColor3 = "Text",
			},
		})

		NewNotification.SubContentLabel = New("TextLabel", {
			FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json"),
			Text = Config.SubContent,
			TextColor3 = Color3.fromRGB(240, 240, 240),
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 14),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 1,
			TextWrapped = true,
			ThemeTag = {
				TextColor3 = "SubText",
			},
		})

		NewNotification.LabelHolder = New("Frame", {
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(14, 40),
			Size = UDim2.new(1, -28, 0, 0),
		}, {
			New("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 3),
			}),
			NewNotification.ContentLabel,
			NewNotification.SubContentLabel,
		})

		NewNotification.CloseButton = New("TextButton", {
			Text = "",
			Position = UDim2.new(1, -14, 0, 13),
			Size = UDim2.fromOffset(20, 20),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
		}, {
			New("ImageLabel", {
				Image = Components.Assets.Close,
				Size = UDim2.fromOffset(16, 16),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				ThemeTag = {
					ImageColor3 = "Text",
				},
			}),
		})

		NewNotification.Root = New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, 0),
			Position = UDim2.fromScale(1, 0),
		}, {
			NewNotification.AcrylicPaint.Frame,
			NewNotification.Title,
			NewNotification.CloseButton,
			NewNotification.LabelHolder,
		})

		if Config.Content == "" then
			NewNotification.ContentLabel.Visible = false
		end

		if Config.SubContent == "" then
			NewNotification.SubContentLabel.Visible = false
		end

		NewNotification.Holder = New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 200),
			Parent = Notification.Holder,
		}, {
			NewNotification.Root,
		})

		local RootMotor = Flipper.GroupMotor.new({
			Scale = 1,
			Offset = 60,
		})

		RootMotor:onStep(function(Values)
			NewNotification.Root.Position = UDim2.new(Values.Scale, Values.Offset, 0, 0)
		end)

		Creator.AddSignal(NewNotification.CloseButton.MouseButton1Click, function()
			NewNotification:Close()
		end)

		function NewNotification:Open()
			local ContentSize = NewNotification.LabelHolder.AbsoluteSize.Y
			NewNotification.Holder.Size = UDim2.new(1, 0, 0, 58 + ContentSize)

			RootMotor:setGoal({
				Scale = Spring(0, { frequency = 5 }),
				Offset = Spring(0, { frequency = 5 }),
			})
		end

		function NewNotification:Close()
			if not NewNotification.Closed then
				NewNotification.Closed = true
				task.spawn(function()
					RootMotor:setGoal({
						Scale = Spring(1, { frequency = 5 }),
						Offset = Spring(60, { frequency = 5 }),
					})
					task.wait(0.4)
					if Library.UseAcrylic then
						NewNotification.AcrylicPaint.Model:Destroy()
					end
					NewNotification.Holder:Destroy()
				end)
			end
		end

		NewNotification:Open()
		if Config.Duration then
			task.delay(Config.Duration, function()
				NewNotification:Close()
			end)
		end
		return NewNotification
	end

	return Notification
end)()

Components.Dialog = (function()
	local Spring = Flipper.Spring.new
	local Instant = Flipper.Instant.new
	local New = Creator.New

	local Dialog = {
		Window = nil,
	}

	function Dialog:Init(Window)
		Dialog.Window = Window
		return Dialog
	end

	function Dialog:Create()
		local NewDialog = {
			Buttons = 0,
		}

		NewDialog.TintFrame = New("TextButton", {
			Text = "",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 1,
			Parent = Dialog.Window.Root,
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
		})

		local TintMotor, TintTransparency = Creator.SpringMotor(1, NewDialog.TintFrame, "BackgroundTransparency", true)

		NewDialog.ButtonHolder = New("Frame", {
			Size = UDim2.new(1, -40, 1, -40),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
		}, {
			New("UIListLayout", {
				Padding = UDim.new(0, 10),
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})

		NewDialog.ButtonHolderFrame = New("Frame", {
			Size = UDim2.new(1, 0, 0, 70),
			Position = UDim2.new(0, 0, 1, -70),
			ThemeTag = {
				BackgroundColor3 = "DialogHolder",
			},
		}, {
			New("Frame", {
				Size = UDim2.new(1, 0, 0, 1),
				ThemeTag = {
					BackgroundColor3 = "DialogHolderLine",
				},
			}),
			NewDialog.ButtonHolder,
		})

		NewDialog.Title = New("TextLabel", {
			FontFace = Font.new(
				"rbxasset://fonts/families/GothamSSm.json",
				Enum.FontWeight.SemiBold,
				Enum.FontStyle.Normal
			),
			Text = "Dialog",
			TextColor3 = Color3.fromRGB(240, 240, 240),
			TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 22),
			Position = UDim2.fromOffset(20, 25),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 1,
			ThemeTag = {
				TextColor3 = "Text",
			},
		})

		NewDialog.Scale = New("UIScale", {
			Scale = 1,
		})

		local ScaleMotor, Scale = Creator.SpringMotor(1.1, NewDialog.Scale, "Scale")

		NewDialog.Root = New("CanvasGroup", {
			Size = UDim2.fromOffset(300, 165),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			GroupTransparency = 1,
			Parent = NewDialog.TintFrame,
			ThemeTag = {
				BackgroundColor3 = "Dialog",
			},
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			New("UIStroke", {
				Transparency = 0.5,
				ThemeTag = {
					Color = "DialogBorder",
				},
			}),
			NewDialog.Scale,
			NewDialog.Title,
			NewDialog.ButtonHolderFrame,
		})

		local RootMotor, RootTransparency = Creator.SpringMotor(1, NewDialog.Root, "GroupTransparency")

		function NewDialog:Open()
			Library.DialogOpen = true
			NewDialog.Scale.Scale = 1.1
			TintTransparency(0.75)
			RootTransparency(0)
			Scale(1)
		end

		function NewDialog:Close()
			Library.DialogOpen = false
			TintTransparency(1)
			RootTransparency(1)
			Scale(1.1)
			NewDialog.Root.UIStroke:Destroy()
			task.wait(0.15)
			NewDialog.TintFrame:Destroy()
		end

		function NewDialog:Button(Title, Callback)
			NewDialog.Buttons = NewDialog.Buttons + 1
			Title = Title or "Button"
			Callback = Callback or function() end

			local Button = Components.Button("", NewDialog.ButtonHolder, true)
			Button.Title.Text = Title

			for _, Btn in next, NewDialog.ButtonHolder:GetChildren() do
				if Btn:IsA("TextButton") then
					Btn.Size =
						UDim2.new(1 / NewDialog.Buttons, -(((NewDialog.Buttons - 1) * 10) / NewDialog.Buttons), 0, 32)
				end
			end

			Creator.AddSignal(Button.Frame.MouseButton1Click, function()
				Library:SafeCallback(Callback)
				pcall(function()
					NewDialog:Close()
				end)
			end)

			return Button
		end

		return NewDialog
	end

	return Dialog
end)()

Components.Tab = (function()
	local New = Creator.New
	local Spring = Flipper.Spring.new
	local Instant = Flipper.Instant.new

	local TabModule = {
		Window = nil,
		Tabs = {},
		Containers = {},
		SelectedTab = 0,
		TabCount = 0,
	}

	function TabModule:Init(Window)
		TabModule.Window = Window
		return TabModule
	end

	function TabModule:GetCurrentTabPos()
		local TabHolderPos = TabModule.Window.TabHolder.AbsolutePosition.Y
		local TabPos = TabModule.Tabs[TabModule.SelectedTab].Frame.AbsolutePosition.Y

		return TabPos - TabHolderPos
	end

	function TabModule:New(Title, Icon, Parent)
		local Window = TabModule.Window
		local Elements = Library.Elements

		TabModule.TabCount = TabModule.TabCount + 1
		local TabIndex = TabModule.TabCount

		local Tab = {
			Selected = false,
			Name = Title,
			Type = "Tab",
		}

		if Library:GetIcon(Icon) then
			Icon = Library:GetIcon(Icon)
		end

		if Icon == "" or nil then
			Icon = nil
		end

		Tab.Frame = New("TextButton", {
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundTransparency = 1,
			Parent = Parent,
			ThemeTag = {
				BackgroundColor3 = "Tab",
			},
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 6),
			}),
			New("TextLabel", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = Icon and UDim2.new(0, 30, 0.5, 0) or UDim2.new(0, 12, 0.5, 0),
				Text = Title,
				RichText = true,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextTransparency = 0,
				FontFace = Font.new(
					"rbxasset://fonts/families/GothamSSm.json",
					Enum.FontWeight.Regular,
					Enum.FontStyle.Normal
				),
				TextSize = 12,
				TextXAlignment = "Left",
				TextYAlignment = "Center",
				Size = UDim2.new(1, -12, 1, 0),
				BackgroundTransparency = 1,
				ThemeTag = {
					TextColor3 = "Text",
				},
			}),
			New("ImageLabel", {
				AnchorPoint = Vector2.new(0, 0.5),
				Size = UDim2.fromOffset(16, 16),
				Position = UDim2.new(0, 8, 0.5, 0),
				BackgroundTransparency = 1,
				Image = Icon and Icon or nil,
				ThemeTag = {
					ImageColor3 = "Text",
				},
			}),
		})

		local ContainerLayout = New("UIListLayout", {
			Padding = UDim.new(0, 5),
			SortOrder = Enum.SortOrder.LayoutOrder,
		})

		Tab.ContainerFrame = New("ScrollingFrame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Parent = Window.ContainerHolder,
			Visible = false,
			BottomImage = "rbxassetid://6889812791",
			MidImage = "rbxassetid://6889812721",
			TopImage = "rbxassetid://6276641225",
			ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255),
			ScrollBarImageTransparency = 0.95,
			ScrollBarThickness = 3,
			BorderSizePixel = 0,
			CanvasSize = UDim2.fromScale(0, 0),
			ScrollingDirection = Enum.ScrollingDirection.Y,
		}, {
			ContainerLayout,
			New("UIPadding", {
				PaddingRight = UDim.new(0, 10),
				PaddingLeft = UDim.new(0, 1),
				PaddingTop = UDim.new(0, 1),
				PaddingBottom = UDim.new(0, 1),
			}),
		})

		Creator.AddSignal(ContainerLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
			Tab.ContainerFrame.CanvasSize = UDim2.new(0, 0, 0, ContainerLayout.AbsoluteContentSize.Y + 2)
		end)

		Tab.Motor, Tab.SetTransparency = Creator.SpringMotor(1, Tab.Frame, "BackgroundTransparency")

		Creator.AddSignal(Tab.Frame.MouseEnter, function()
			Tab.SetTransparency(Tab.Selected and 0.85 or 0.89)
		end)
		Creator.AddSignal(Tab.Frame.MouseLeave, function()
			Tab.SetTransparency(Tab.Selected and 0.89 or 1)
		end)
		Creator.AddSignal(Tab.Frame.MouseButton1Down, function()
			Tab.SetTransparency(0.92)
		end)
		Creator.AddSignal(Tab.Frame.MouseButton1Up, function()
			Tab.SetTransparency(Tab.Selected and 0.85 or 0.89)
		end)
		Creator.AddSignal(Tab.Frame.MouseButton1Click, function()
			TabModule:SelectTab(TabIndex)
		end)

		TabModule.Containers[TabIndex] = Tab.ContainerFrame
		TabModule.Tabs[TabIndex] = Tab

		Tab.Container = Tab.ContainerFrame
		Tab.ScrollFrame = Tab.Container

		function Tab:AddSection(SectionTitle)
			local Section = { Type = "Section" }

			local SectionFrame = Components.Section(SectionTitle, Tab.Container)
			Section.Container = SectionFrame.Container
			Section.ScrollFrame = Tab.Container

			setmetatable(Section, Elements)
			return Section
		end

		setmetatable(Tab, Elements)
		return Tab
	end

	function TabModule:SelectTab(Tab)
		local Window = TabModule.Window

		TabModule.SelectedTab = Tab

		for _, TabObject in next, TabModule.Tabs do
			TabObject.SetTransparency(1)
			TabObject.Selected = false
		end
		TabModule.Tabs[Tab].SetTransparency(0.89)
		TabModule.Tabs[Tab].Selected = true

		Window.TabDisplay.Text = TabModule.Tabs[Tab].Name
		Window.SelectorPosMotor:setGoal(Spring(TabModule:GetCurrentTabPos(), { frequency = 6 }))

		task.spawn(function()
			Window.ContainerHolder.Parent = Window.ContainerAnim

			Window.ContainerPosMotor:setGoal(Spring(15, { frequency = 10 }))
			Window.ContainerBackMotor:setGoal(Spring(1, { frequency = 10 }))
			task.wait(0.12)
			for _, Container in next, TabModule.Containers do
				Container.Visible = false
			end
			TabModule.Containers[Tab].Visible = true
			Window.ContainerPosMotor:setGoal(Spring(0, { frequency = 5 }))
			Window.ContainerBackMotor:setGoal(Spring(0, { frequency = 8 }))
			task.wait(0.12)
			Window.ContainerHolder.Parent = Window.ContainerCanvas
		end)
	end

	return TabModule
end)()

Components.Window = (function()
	local Assets = Components.Assets

	local Spring = Flipper.Spring.new
	local Instant = Flipper.Instant.new
	local New = Creator.New

	return function(Config)

		local Window = {
			Minimized = false,
			Maximized = false,
			Size = Config.Size,
			CurrentPos = 0,
			TabWidth = 0,
			Position = UDim2.fromOffset(
				Camera.ViewportSize.X / 2 - Config.Size.X.Offset / 2,
				Camera.ViewportSize.Y / 2 - Config.Size.Y.Offset / 2
			),
		}

		local Dragging, DragInput, MousePos, StartPos = false
		local Resizing, ResizePos = false
		local MinimizeNotif = false

		Window.AcrylicPaint = Acrylic.AcrylicPaint()
		Window.TabWidth = Config.TabWidth

		local Selector = New("Frame", {
			Size = UDim2.fromOffset(4, 0),
			BackgroundColor3 = Color3.fromRGB(76, 194, 255),
			Position = UDim2.fromOffset(0, 17),
			AnchorPoint = Vector2.new(0, 0.5),
			ThemeTag = {
				BackgroundColor3 = "Accent",
			},
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 2),
			}),
		})

		local ResizeStartFrame = New("Frame", {
			Size = UDim2.fromOffset(20, 20),
			BackgroundTransparency = 1,
			Position = UDim2.new(1, -20, 1, -20),
		})

		Window.TabHolder = New("ScrollingFrame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ScrollBarImageTransparency = 1,
			ScrollBarThickness = 0,
			BorderSizePixel = 0,
			CanvasSize = UDim2.fromScale(0, 0),
			ScrollingDirection = Enum.ScrollingDirection.Y,
		}, {
			New("UIListLayout", {
				Padding = UDim.new(0, 4),
			}),
		})

		local TabFrame = New("Frame", {
			Size = UDim2.new(0, Window.TabWidth, 1, -66),
			Position = UDim2.new(0, 12, 0, 54),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
		}, {
			Window.TabHolder,
			Selector,
		})

		Window.TabDisplay = New("TextLabel", {
			RichText = true,
			Text = "Tab",
			TextTransparency = 0,
			FontFace = Font.new("rbxassetid://12187365364", Enum.FontWeight.SemiBold, Enum.FontStyle.Normal),
			TextSize = 28,
			TextXAlignment = "Left",
			TextYAlignment = "Center",
			Size = UDim2.new(1, -16, 0, 28),
			Position = UDim2.fromOffset(Window.TabWidth + 26, 56),
			BackgroundTransparency = 1,
			ThemeTag = {
				TextColor3 = "Text",
			},
		})

		Window.ContainerHolder = New("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		})

		Window.ContainerAnim = New("CanvasGroup", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		})

		Window.ContainerCanvas = New("Frame", {
			Size = UDim2.new(1, -Window.TabWidth - 32, 1, -102),
			Position = UDim2.fromOffset(Window.TabWidth + 26, 90),
			BackgroundTransparency = 1,
		}, {
			Window.ContainerAnim,
			Window.ContainerHolder
		})

		Window.Root = New("Frame", {
			BackgroundTransparency = 1,
			Size = Window.Size,
			Position = Window.Position,
			Parent = Config.Parent,
		}, {
			Window.AcrylicPaint.Frame,
			Window.TabDisplay,
			Window.ContainerCanvas,
			TabFrame,
			ResizeStartFrame,
		})

		Window.TitleBar = Components.TitleBar({
			Title = Config.Title,
			SubTitle = Config.SubTitle,
			Parent = Window.Root,
			Window = Window,
		})

		if Library.UseAcrylic then
			Window.AcrylicPaint.AddParent(Window.Root)
		end

		local SizeMotor = Flipper.GroupMotor.new({
			X = Window.Size.X.Offset,
			Y = Window.Size.Y.Offset,
		})

		local PosMotor = Flipper.GroupMotor.new({
			X = Window.Position.X.Offset,
			Y = Window.Position.Y.Offset,
		})

		Window.SelectorPosMotor = Flipper.SingleMotor.new(17)
		Window.SelectorSizeMotor = Flipper.SingleMotor.new(0)
		Window.ContainerBackMotor = Flipper.SingleMotor.new(0)
		Window.ContainerPosMotor = Flipper.SingleMotor.new(94)

		SizeMotor:onStep(function(values)
			Window.Root.Size = UDim2.new(0, values.X, 0, values.Y)
		end)

		PosMotor:onStep(function(values)
			Window.Root.Position = UDim2.new(0, values.X, 0, values.Y)
		end)

		local LastValue = 0
		local LastTime = 0
		Window.SelectorPosMotor:onStep(function(Value)
			Selector.Position = UDim2.new(0, 0, 0, Value + 17)
			local Now = tick()
			local DeltaTime = Now - LastTime

			if LastValue ~= nil then
				Window.SelectorSizeMotor:setGoal(Spring((math.abs(Value - LastValue) / (DeltaTime * 60)) + 16))
				LastValue = Value
			end
			LastTime = Now
		end)

		Window.SelectorSizeMotor:onStep(function(Value)
			Selector.Size = UDim2.new(0, 4, 0, Value)
		end)

		Window.ContainerBackMotor:onStep(function(Value)
			Window.ContainerAnim.GroupTransparency = Value
		end)

		Window.ContainerPosMotor:onStep(function(Value)
			Window.ContainerAnim.Position = UDim2.fromOffset(0, Value)
		end)

		local OldSizeX
		local OldSizeY
		Window.Maximize = function(Value, NoPos, Instant)
			Window.Maximized = Value
			Window.TitleBar.MaxButton.Frame.Icon.Image = Value and Assets.Restore or Assets.Max

			if Value then
				OldSizeX = Window.Size.X.Offset
				OldSizeY = Window.Size.Y.Offset
			end
			local SizeX = Value and Camera.ViewportSize.X or OldSizeX
			local SizeY = Value and Camera.ViewportSize.Y or OldSizeY
			SizeMotor:setGoal({
				X = Flipper[Instant and "Instant" or "Spring"].new(SizeX, { frequency = 6 }),
				Y = Flipper[Instant and "Instant" or "Spring"].new(SizeY, { frequency = 6 }),
			})
			Window.Size = UDim2.fromOffset(SizeX, SizeY)

			if not NoPos then
				PosMotor:setGoal({
					X = Spring(Value and 0 or Window.Position.X.Offset, { frequency = 6 }),
					Y = Spring(Value and 0 or Window.Position.Y.Offset, { frequency = 6 }),
				})
			end
		end

		Creator.AddSignal(Window.TitleBar.Frame.InputBegan, function(Input)
			if
				Input.UserInputType == Enum.UserInputType.MouseButton1
				or Input.UserInputType == Enum.UserInputType.Touch
			then
				Dragging = true
				MousePos = Input.Position
				StartPos = Window.Root.Position

				if Window.Maximized then
					StartPos = UDim2.fromOffset(
						Mouse.X - (Mouse.X * ((OldSizeX - 100) / Window.Root.AbsoluteSize.X)),
						Mouse.Y - (Mouse.Y * (OldSizeY / Window.Root.AbsoluteSize.Y))
					)
				end

				Input.Changed:Connect(function()
					if Input.UserInputState == Enum.UserInputState.End then
						Dragging = false
					end
				end)
			end
		end)

		Creator.AddSignal(Window.TitleBar.Frame.InputChanged, function(Input)
			if
				Input.UserInputType == Enum.UserInputType.MouseMovement
				or Input.UserInputType == Enum.UserInputType.Touch
			then
				DragInput = Input
			end
		end)

		Creator.AddSignal(ResizeStartFrame.InputBegan, function(Input)
			if
				Input.UserInputType == Enum.UserInputType.MouseButton1
				or Input.UserInputType == Enum.UserInputType.Touch
			then
				Resizing = true
				ResizePos = Input.Position
			end
		end)

		Creator.AddSignal(UserInputService.InputChanged, function(Input)
			if Input == DragInput and Dragging then
				local Delta = Input.Position - MousePos
				Window.Position = UDim2.fromOffset(StartPos.X.Offset + Delta.X, StartPos.Y.Offset + Delta.Y)
				PosMotor:setGoal({
					X = Instant(Window.Position.X.Offset),
					Y = Instant(Window.Position.Y.Offset),
				})

				if Window.Maximized then
					Window.Maximize(false, true, true)
				end
			end

			if
				(Input.UserInputType == Enum.UserInputType.MouseMovement or Input.UserInputType == Enum.UserInputType.Touch)
				and Resizing
			then
				local Delta = Input.Position - ResizePos
				local StartSize = Window.Size

				local TargetSize = Vector3.new(StartSize.X.Offset, StartSize.Y.Offset, 0) + Vector3.new(1, 1, 0) * Delta
				local TargetSizeClamped =
					Vector2.new(math.clamp(TargetSize.X, 470, 2048), math.clamp(TargetSize.Y, 380, 2048))

				SizeMotor:setGoal({
					X = Flipper.Instant.new(TargetSizeClamped.X),
					Y = Flipper.Instant.new(TargetSizeClamped.Y),
				})
			end
		end)

		Creator.AddSignal(UserInputService.InputEnded, function(Input)
			if Resizing == true or Input.UserInputType == Enum.UserInputType.Touch then
				Resizing = false
				Window.Size = UDim2.fromOffset(SizeMotor:getValue().X, SizeMotor:getValue().Y)
			end
		end)

		Creator.AddSignal(Window.TabHolder.UIListLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
			Window.TabHolder.CanvasSize = UDim2.new(0, 0, 0, Window.TabHolder.UIListLayout.AbsoluteContentSize.Y)
		end)

		Creator.AddSignal(UserInputService.InputBegan, function(Input)
			if
				type(Library.MinimizeKeybind) == "table"
				and Library.MinimizeKeybind.Type == "Keybind"
				and not UserInputService:GetFocusedTextBox()
			then
				if Input.KeyCode.Name == Library.MinimizeKeybind.Value then
					Window:Minimize()
				end
			elseif Input.KeyCode == Library.MinimizeKey and not UserInputService:GetFocusedTextBox() then
				Window:Minimize()
			end
		end)

		function Window:Minimize()
			Window.Minimized = not Window.Minimized
			Window.Root.Visible = not Window.Minimized
			if not MinimizeNotif then
				MinimizeNotif = true
				local Key = Library.MinimizeKeybind and Library.MinimizeKeybind.Value or Library.MinimizeKey.Name
				Library:Notify({
					Title = "Interface",
					Content = "Press " .. Key .. " to toggle the interface.",
					Duration = 6
				})
			end
		end

		function Window:Destroy()
			if Library.UseAcrylic then
				Window.AcrylicPaint.Model:Destroy()
			end
			Window.Root:Destroy()
		end

		local DialogModule = Components.Dialog:Init(Window)
		function Window:Dialog(Config)
			local Dialog = DialogModule:Create()
			Dialog.Title.Text = Config.Title

			local Content = New("TextLabel", {
				FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json"),
				Text = Config.Content,
				TextColor3 = Color3.fromRGB(240, 240, 240),
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				Size = UDim2.new(1, -40, 1, 0),
				Position = UDim2.fromOffset(20, 60),
				BackgroundTransparency = 1,
				Parent = Dialog.Root,
				ClipsDescendants = false,
				ThemeTag = {
					TextColor3 = "Text",
				},
			})

			New("UISizeConstraint", {
				MinSize = Vector2.new(300, 165),
				MaxSize = Vector2.new(620, math.huge),
				Parent = Dialog.Root,
			})

			Dialog.Root.Size = UDim2.fromOffset(Content.TextBounds.X + 40, 165)
			if Content.TextBounds.X + 40 > Window.Size.X.Offset - 120 then
				Dialog.Root.Size = UDim2.fromOffset(Window.Size.X.Offset - 120, 165)
				Content.TextWrapped = true
				Dialog.Root.Size = UDim2.fromOffset(Window.Size.X.Offset - 120, Content.TextBounds.Y + 150)
			end

			for _, Button in next, Config.Buttons do
				Dialog:Button(Button.Title, Button.Callback)
			end

			Dialog:Open()
		end

		local TabModule = Components.Tab:Init(Window)
		function Window:AddTab(TabConfig)
			return TabModule:New(TabConfig.Title, TabConfig.Icon, Window.TabHolder)
		end

		function Window:SelectTab(Tab)
			TabModule:SelectTab(1)
		end

		Creator.AddSignal(Window.TabHolder:GetPropertyChangedSignal("CanvasPosition"), function()
			LastValue = TabModule:GetCurrentTabPos() + 16
			LastTime = 0
			Window.SelectorPosMotor:setGoal(Instant(TabModule:GetCurrentTabPos()))
		end)

		return Window
	end
end)()

local ElementsTable = {}
local AddSignal = Creator.AddSignal

ElementsTable.Button = (function()
	local New = Creator.New

	local Element = {}
	Element.__index = Element
	Element.__type = "Button"

	function Element:New(Config)
		assert(Config.Title, "Button - Missing Title")
		Config.Callback = Config.Callback or function() end

		local ButtonFrame = Components.Element(Config.Title, Config.Description, self.Container, true)

		local ButtonIco = New("ImageLabel", {
			Image = "rbxassetid://10709791437",
			Size = UDim2.fromOffset(16, 16),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			BackgroundTransparency = 1,
			Parent = ButtonFrame.Frame,
			ThemeTag = {
				ImageColor3 = "Text",
			},
		})

		Creator.AddSignal(ButtonFrame.Frame.MouseButton1Click, function()
			self.Library:SafeCallback(Config.Callback)
		end)

		return ButtonFrame
	end

	return Element
end)()

ElementsTable.Colorpicker = (function()
	local TouchInputService = game:GetService("TouchInputService")

	local RenderStepped = RunService.RenderStepped
	local Mouse = LocalPlayer:GetMouse()

	local New = Creator.New

	local Element = {}
	Element.__index = Element
	Element.__type = "Colorpicker"

	function Element:New(Idx, Config)
		local Library = self.Library
		assert(Config.Title, "Colorpicker - Missing Title")
		assert(Config.Default, "AddColorPicker: Missing default value.")

		local Colorpicker = {
			Value = Config.Default,
			Transparency = Config.Transparency or 0,
			Type = "Colorpicker",
			Title = type(Config.Title) == "string" and Config.Title or "Colorpicker",
			Callback = Config.Callback or function(Color) end,
		}

		function Colorpicker:SetHSVFromRGB(Color)
			local H, S, V = Color3.toHSV(Color)
			Colorpicker.Hue = H
			Colorpicker.Sat = S
			Colorpicker.Vib = V
		end

		Colorpicker:SetHSVFromRGB(Colorpicker.Value)

		local ColorpickerFrame = Components.Element(Config.Title, Config.Description, self.Container, true)

		Colorpicker.SetTitle = ColorpickerFrame.SetTitle
		Colorpicker.SetDesc = ColorpickerFrame.SetDesc

		local DisplayFrameColor = New("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Colorpicker.Value,
			Parent = ColorpickerFrame.Frame,
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
		})

		local DisplayFrame = New("ImageLabel", {
			Size = UDim2.fromOffset(26, 26),
			Position = UDim2.new(1, -10, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Parent = ColorpickerFrame.Frame,
			Image = "http://www.roblox.com/asset/?id=14204231522",
			ImageTransparency = 0.45,
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(40, 40),
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
			DisplayFrameColor,
		})

		local function CreateColorDialog()
			local Dialog = Components.Dialog:Create()
			Dialog.Title.Text = Colorpicker.Title
			Dialog.Root.Size = UDim2.fromOffset(430, 330)

			local Hue, Sat, Vib = Colorpicker.Hue, Colorpicker.Sat, Colorpicker.Vib
			local Transparency = Colorpicker.Transparency

			local function CreateInput()
				local Box = Components.Textbox()
				Box.Frame.Parent = Dialog.Root
				Box.Frame.Size = UDim2.new(0, 90, 0, 32)

				return Box
			end

			local function CreateInputLabel(Text, Pos)
				return New("TextLabel", {
					FontFace = Font.new(
						"rbxasset://fonts/families/GothamSSm.json",
						Enum.FontWeight.Medium,
						Enum.FontStyle.Normal
					),
					Text = Text,
					TextColor3 = Color3.fromRGB(240, 240, 240),
					TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Left,
					Size = UDim2.new(1, 0, 0, 32),
					Position = Pos,
					BackgroundTransparency = 1,
					Parent = Dialog.Root,
					ThemeTag = {
						TextColor3 = "Text",
					},
				})
			end

			local function GetRGB()
				local Value = Color3.fromHSV(Hue, Sat, Vib)
				return { R = math.floor(Value.r * 255), G = math.floor(Value.g * 255), B = math.floor(Value.b * 255) }
			end

			local SatCursor = New("ImageLabel", {
				Size = UDim2.new(0, 18, 0, 18),
				ScaleType = Enum.ScaleType.Fit,
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Image = "http://www.roblox.com/asset/?id=4805639000",
			})

			local SatVibMap = New("ImageLabel", {
				Size = UDim2.fromOffset(180, 160),
				Position = UDim2.fromOffset(20, 55),
				Image = "rbxassetid://4155801252",
				BackgroundColor3 = Colorpicker.Value,
				BackgroundTransparency = 0,
				Parent = Dialog.Root,
			}, {
				New("UICorner", {
					CornerRadius = UDim.new(0, 4),
				}),
				SatCursor,
			})

			local OldColorFrame = New("Frame", {
				BackgroundColor3 = Colorpicker.Value,
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = Colorpicker.Transparency,
			}, {
				New("UICorner", {
					CornerRadius = UDim.new(0, 4),
				}),
			})

			local OldColorFrameChecker = New("ImageLabel", {
				Image = "http://www.roblox.com/asset/?id=14204231522",
				ImageTransparency = 0.45,
				ScaleType = Enum.ScaleType.Tile,
				TileSize = UDim2.fromOffset(40, 40),
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(112, 220),
				Size = UDim2.fromOffset(88, 24),
				Parent = Dialog.Root,
			}, {
				New("UICorner", {
					CornerRadius = UDim.new(0, 4),
				}),
				New("UIStroke", {
					Thickness = 2,
					Transparency = 0.75,
				}),
				OldColorFrame,
			})

			local DialogDisplayFrame = New("Frame", {
				BackgroundColor3 = Colorpicker.Value,
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 0,
			}, {
				New("UICorner", {
					CornerRadius = UDim.new(0, 4),
				}),
			})

			local DialogDisplayFrameChecker = New("ImageLabel", {
				Image = "http://www.roblox.com/asset/?id=14204231522",
				ImageTransparency = 0.45,
				ScaleType = Enum.ScaleType.Tile,
				TileSize = UDim2.fromOffset(40, 40),
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(20, 220),
				Size = UDim2.fromOffset(88, 24),
				Parent = Dialog.Root,
			}, {
				New("UICorner", {
					CornerRadius = UDim.new(0, 4),
				}),
				New("UIStroke", {
					Thickness = 2,
					Transparency = 0.75,
				}),
				DialogDisplayFrame,
			})

			local SequenceTable = {}

			for Color = 0, 1, 0.1 do
				table.insert(SequenceTable, ColorSequenceKeypoint.new(Color, Color3.fromHSV(Color, 1, 1)))
			end

			local HueSliderGradient = New("UIGradient", {
				Color = ColorSequence.new(SequenceTable),
				Rotation = 90,
			})

			local HueDragHolder = New("Frame", {
				Size = UDim2.new(1, 0, 1, -10),
				Position = UDim2.fromOffset(0, 5),
				BackgroundTransparency = 1,
			})

			local HueDrag = New("ImageLabel", {
				Size = UDim2.fromOffset(14, 14),
				Image = "http://www.roblox.com/asset/?id=12266946128",
				Parent = HueDragHolder,
				ThemeTag = {
					ImageColor3 = "DialogInput",
				},
			})

			local HueSlider = New("Frame", {
				Size = UDim2.fromOffset(12, 190),
				Position = UDim2.fromOffset(210, 55),
				Parent = Dialog.Root,
			}, {
				New("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
				HueSliderGradient,
				HueDragHolder,
			})

			local HexInput = CreateInput()
			HexInput.Frame.Position = UDim2.fromOffset(Config.Transparency and 260 or 240, 55)
			CreateInputLabel("Hex", UDim2.fromOffset(Config.Transparency and 360 or 340, 55))

			local RedInput = CreateInput()
			RedInput.Frame.Position = UDim2.fromOffset(Config.Transparency and 260 or 240, 95)
			CreateInputLabel("Red", UDim2.fromOffset(Config.Transparency and 360 or 340, 95))

			local GreenInput = CreateInput()
			GreenInput.Frame.Position = UDim2.fromOffset(Config.Transparency and 260 or 240, 135)
			CreateInputLabel("Green", UDim2.fromOffset(Config.Transparency and 360 or 340, 135))

			local BlueInput = CreateInput()
			BlueInput.Frame.Position = UDim2.fromOffset(Config.Transparency and 260 or 240, 175)
			CreateInputLabel("Blue", UDim2.fromOffset(Config.Transparency and 360 or 340, 175))

			local AlphaInput
			if Config.Transparency then
				AlphaInput = CreateInput()
				AlphaInput.Frame.Position = UDim2.fromOffset(260, 215)
				CreateInputLabel("Alpha", UDim2.fromOffset(360, 215))
			end

			local TransparencySlider, TransparencyDrag, TransparencyColor
			if Config.Transparency then
				local TransparencyDragHolder = New("Frame", {
					Size = UDim2.new(1, 0, 1, -10),
					Position = UDim2.fromOffset(0, 5),
					BackgroundTransparency = 1,
				})

				TransparencyDrag = New("ImageLabel", {
					Size = UDim2.fromOffset(14, 14),
					Image = "http://www.roblox.com/asset/?id=12266946128",
					Parent = TransparencyDragHolder,
					ThemeTag = {
						ImageColor3 = "DialogInput",
					},
				})

				TransparencyColor = New("Frame", {
					Size = UDim2.fromScale(1, 1),
				}, {
					New("UIGradient", {
						Transparency = NumberSequence.new({
							NumberSequenceKeypoint.new(0, 0),
							NumberSequenceKeypoint.new(1, 1),
						}),
						Rotation = 270,
					}),
					New("UICorner", {
						CornerRadius = UDim.new(1, 0),
					}),
				})

				TransparencySlider = New("Frame", {
					Size = UDim2.fromOffset(12, 190),
					Position = UDim2.fromOffset(230, 55),
					Parent = Dialog.Root,
					BackgroundTransparency = 1,
				}, {
					New("UICorner", {
						CornerRadius = UDim.new(1, 0),
					}),
					New("ImageLabel", {
						Image = "http://www.roblox.com/asset/?id=14204231522",
						ImageTransparency = 0.45,
						ScaleType = Enum.ScaleType.Tile,
						TileSize = UDim2.fromOffset(40, 40),
						BackgroundTransparency = 1,
						Size = UDim2.fromScale(1, 1),
						Parent = Dialog.Root,
					}, {
						New("UICorner", {
							CornerRadius = UDim.new(1, 0),
						}),
					}),
					TransparencyColor,
					TransparencyDragHolder,
				})
			end

			local function Display()
				SatVibMap.BackgroundColor3 = Color3.fromHSV(Hue, 1, 1)
				HueDrag.Position = UDim2.new(0, -1, Hue, -6)
				SatCursor.Position = UDim2.new(Sat, 0, 1 - Vib, 0)
				DialogDisplayFrame.BackgroundColor3 = Color3.fromHSV(Hue, Sat, Vib)

				HexInput.Input.Text = "#" .. Color3.fromHSV(Hue, Sat, Vib):ToHex()
				RedInput.Input.Text = GetRGB()["R"]
				GreenInput.Input.Text = GetRGB()["G"]
				BlueInput.Input.Text = GetRGB()["B"]

				if Config.Transparency then
					TransparencyColor.BackgroundColor3 = Color3.fromHSV(Hue, Sat, Vib)
					DialogDisplayFrame.BackgroundTransparency = Transparency
					TransparencyDrag.Position = UDim2.new(0, -1, 1 - Transparency, -6)
					AlphaInput.Input.Text = Library:Round((1 - Transparency) * 100, 0) .. "%"
				end
			end

			Creator.AddSignal(HexInput.Input.FocusLost, function(Enter)
				if Enter then
					local Success, Result = pcall(Color3.fromHex, HexInput.Input.Text)
					if Success and typeof(Result) == "Color3" then
						Hue, Sat, Vib = Color3.toHSV(Result)
					end
				end
				Display()
			end)

			Creator.AddSignal(RedInput.Input.FocusLost, function(Enter)
				if Enter then
					local CurrentColor = GetRGB()
					local Success, Result = pcall(Color3.fromRGB, RedInput.Input.Text, CurrentColor["G"], CurrentColor["B"])
					if Success and typeof(Result) == "Color3" then
						if tonumber(RedInput.Input.Text) <= 255 then
							Hue, Sat, Vib = Color3.toHSV(Result)
						end
					end
				end
				Display()
			end)

			Creator.AddSignal(GreenInput.Input.FocusLost, function(Enter)
				if Enter then
					local CurrentColor = GetRGB()
					local Success, Result =
						pcall(Color3.fromRGB, CurrentColor["R"], GreenInput.Input.Text, CurrentColor["B"])
					if Success and typeof(Result) == "Color3" then
						if tonumber(GreenInput.Input.Text) <= 255 then
							Hue, Sat, Vib = Color3.toHSV(Result)
						end
					end
				end
				Display()
			end)

			Creator.AddSignal(BlueInput.Input.FocusLost, function(Enter)
				if Enter then
					local CurrentColor = GetRGB()
					local Success, Result =
						pcall(Color3.fromRGB, CurrentColor["R"], CurrentColor["G"], BlueInput.Input.Text)
					if Success and typeof(Result) == "Color3" then
						if tonumber(BlueInput.Input.Text) <= 255 then
							Hue, Sat, Vib = Color3.toHSV(Result)
						end
					end
				end
				Display()
			end)

			if Config.Transparency then
				Creator.AddSignal(AlphaInput.Input.FocusLost, function(Enter)
					if Enter then
						pcall(function()
							local Value = tonumber(AlphaInput.Input.Text)
							if Value >= 0 and Value <= 100 then
								Transparency = 1 - Value * 0.01
							end
						end)
					end
					Display()
				end)
			end

			Creator.AddSignal(SatVibMap.InputBegan, function(Input)
				if
					Input.UserInputType == Enum.UserInputType.MouseButton1
					or Input.UserInputType == Enum.UserInputType.Touch
				then
					while UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
						local MinX = SatVibMap.AbsolutePosition.X
						local MaxX = MinX + SatVibMap.AbsoluteSize.X
						local MouseX = math.clamp(Mouse.X, MinX, MaxX)

						local MinY = SatVibMap.AbsolutePosition.Y
						local MaxY = MinY + SatVibMap.AbsoluteSize.Y
						local MouseY = math.clamp(Mouse.Y, MinY, MaxY)

						Sat = (MouseX - MinX) / (MaxX - MinX)
						Vib = 1 - ((MouseY - MinY) / (MaxY - MinY))
						Display()

						RenderStepped:Wait()
					end
				end
			end)

			Creator.AddSignal(HueSlider.InputBegan, function(Input)
				if
					Input.UserInputType == Enum.UserInputType.MouseButton1
					or Input.UserInputType == Enum.UserInputType.Touch
				then
					while UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
						local MinY = HueSlider.AbsolutePosition.Y
						local MaxY = MinY + HueSlider.AbsoluteSize.Y
						local MouseY = math.clamp(Mouse.Y, MinY, MaxY)

						Hue = ((MouseY - MinY) / (MaxY - MinY))
						Display()

						RenderStepped:Wait()
					end
				end
			end)

			if Config.Transparency then
				Creator.AddSignal(TransparencySlider.InputBegan, function(Input)
					if Input.UserInputType == Enum.UserInputType.MouseButton1 then
						while UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
							local MinY = TransparencySlider.AbsolutePosition.Y
							local MaxY = MinY + TransparencySlider.AbsoluteSize.Y
							local MouseY = math.clamp(Mouse.Y, MinY, MaxY)

							Transparency = 1 - ((MouseY - MinY) / (MaxY - MinY))
							Display()

							RenderStepped:Wait()
						end
					end
				end)
			end

			Display()

			Dialog:Button("Done", function()
				Colorpicker:SetValue({ Hue, Sat, Vib }, Transparency)
			end)
			Dialog:Button("Cancel")
			Dialog:Open()
		end

		function Colorpicker:Display()
			Colorpicker.Value = Color3.fromHSV(Colorpicker.Hue, Colorpicker.Sat, Colorpicker.Vib)

			DisplayFrameColor.BackgroundColor3 = Colorpicker.Value
			DisplayFrameColor.BackgroundTransparency = Colorpicker.Transparency

			Element.Library:SafeCallback(Colorpicker.Callback, Colorpicker.Value)
			Element.Library:SafeCallback(Colorpicker.Changed, Colorpicker.Value)
		end

		function Colorpicker:SetValue(HSV, Transparency)
			local Color = Color3.fromHSV(HSV[1], HSV[2], HSV[3])

			Colorpicker.Transparency = Transparency or 0
			Colorpicker:SetHSVFromRGB(Color)
			Colorpicker:Display()
		end

		function Colorpicker:SetValueRGB(Color, Transparency)
			Colorpicker.Transparency = Transparency or 0
			Colorpicker:SetHSVFromRGB(Color)
			Colorpicker:Display()
		end

		function Colorpicker:OnChanged(Func)
			Colorpicker.Changed = Func
			Func(Colorpicker.Value)
		end

		function Colorpicker:Destroy()
			ColorpickerFrame:Destroy()
			Library.Options[Idx] = nil
		end

		Creator.AddSignal(ColorpickerFrame.Frame.MouseButton1Click, function()
			CreateColorDialog()
		end)

		Colorpicker:Display()

		Library.Options[Idx] = Colorpicker
		return Colorpicker
	end

	return Element
end)()

ElementsTable.Dropdown = (function()
	local New = Creator.New

	local Element = {}
	Element.__index = Element
	Element.__type = "Dropdown"

	function Element:New(Idx, Config)
		local Library = self.Library

		local Dropdown = {
			Values = Config.Values,
			Value = Config.Default,
			Multi = Config.Multi,
			Buttons = {},
			Opened = false,
			Type = "Dropdown",
			Callback = Config.Callback or function() end,
		}

		local DropdownFrame = Components.Element(Config.Title, Config.Description, self.Container, false)
		DropdownFrame.DescLabel.Size = UDim2.new(1, -170, 0, 14)

		Dropdown.SetTitle = DropdownFrame.SetTitle
		Dropdown.SetDesc = DropdownFrame.SetDesc

		local DropdownDisplay = New("TextLabel", {
			FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
			Text = "Value",
			TextColor3 = Color3.fromRGB(240, 240, 240),
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -30, 0, 14),
			Position = UDim2.new(0, 8, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 1,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ThemeTag = {
				TextColor3 = "Text",
			},
		})

		local DropdownIco = New("ImageLabel", {
			Image = "rbxassetid://10709790948",
			Size = UDim2.fromOffset(16, 16),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			BackgroundTransparency = 1,
			ThemeTag = {
				ImageColor3 = "SubText",
			},
		})

		local DropdownInner = New("TextButton", {
			Size = UDim2.fromOffset(160, 30),
			Position = UDim2.new(1, -10, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundTransparency = 0.9,
			Parent = DropdownFrame.Frame,
			ThemeTag = {
				BackgroundColor3 = "DropdownFrame",
			},
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 5),
			}),
			New("UIStroke", {
				Transparency = 0.5,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				ThemeTag = {
					Color = "InElementBorder",
				},
			}),
			DropdownIco,
			DropdownDisplay,
		})

		local DropdownListLayout = New("UIListLayout", {
			Padding = UDim.new(0, 3),
		})

		local DropdownScrollFrame = New("ScrollingFrame", {
			Size = UDim2.new(1, -5, 1, -10),
			Position = UDim2.fromOffset(5, 5),
			BackgroundTransparency = 1,
			BottomImage = "rbxassetid://6889812791",
			MidImage = "rbxassetid://6889812721",
			TopImage = "rbxassetid://6276641225",
			ScrollBarImageColor3 = Color3.fromRGB(255, 255, 255),
			ScrollBarImageTransparency = 0.95,
			ScrollBarThickness = 4,
			BorderSizePixel = 0,
			CanvasSize = UDim2.fromScale(0, 0),
		}, {
			DropdownListLayout,
		})

		local DropdownHolderFrame = New("Frame", {
			Size = UDim2.fromScale(1, 0.6),
			ThemeTag = {
				BackgroundColor3 = "DropdownHolder",
			},
		}, {
			DropdownScrollFrame,
			New("UICorner", {
				CornerRadius = UDim.new(0, 7),
			}),
			New("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				ThemeTag = {
					Color = "DropdownBorder",
				},
			}),
			New("ImageLabel", {
				BackgroundTransparency = 1,
				Image = "http://www.roblox.com/asset/?id=5554236805",
				ScaleType = Enum.ScaleType.Slice,
				SliceCenter = Rect.new(23, 23, 277, 277),
				Size = UDim2.fromScale(1, 1) + UDim2.fromOffset(30, 30),
				Position = UDim2.fromOffset(-15, -15),
				ImageColor3 = Color3.fromRGB(0, 0, 0),
				ImageTransparency = 0.1,
			}),
		})

		local DropdownHolderCanvas = New("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(170, 300),
			Parent = self.Library.GUI,
			Visible = false,
		}, {
			DropdownHolderFrame,
			New("UISizeConstraint", {
				MinSize = Vector2.new(170, 0),
			}),
		})
		table.insert(Library.OpenFrames, DropdownHolderCanvas)

		local function RecalculateListPosition()
			local Add = 0
			if Camera.ViewportSize.Y - DropdownInner.AbsolutePosition.Y < DropdownHolderCanvas.AbsoluteSize.Y - 5 then
				Add = DropdownHolderCanvas.AbsoluteSize.Y
					- 5
					- (Camera.ViewportSize.Y - DropdownInner.AbsolutePosition.Y)
					+ 40
			end
			DropdownHolderCanvas.Position =
				UDim2.fromOffset(DropdownInner.AbsolutePosition.X - 1, DropdownInner.AbsolutePosition.Y - 5 - Add)
		end

		local ListSizeX = 0
		local function RecalculateListSize()
			if #Dropdown.Values > 10 then
				DropdownHolderCanvas.Size = UDim2.fromOffset(ListSizeX, 392)
			else
				DropdownHolderCanvas.Size = UDim2.fromOffset(ListSizeX, DropdownListLayout.AbsoluteContentSize.Y + 10)
			end
		end

		local function RecalculateCanvasSize()
			DropdownScrollFrame.CanvasSize = UDim2.fromOffset(0, DropdownListLayout.AbsoluteContentSize.Y)
		end

		RecalculateListPosition()
		RecalculateListSize()

		Creator.AddSignal(DropdownInner:GetPropertyChangedSignal("AbsolutePosition"), RecalculateListPosition)

		Creator.AddSignal(DropdownInner.MouseButton1Click, function()
			Dropdown:Open()
		end)

		Creator.AddSignal(UserInputService.InputBegan, function(Input)
			if
				Input.UserInputType == Enum.UserInputType.MouseButton1
				or Input.UserInputType == Enum.UserInputType.Touch
			then
				local AbsPos, AbsSize = DropdownHolderFrame.AbsolutePosition, DropdownHolderFrame.AbsoluteSize
				if
					Mouse.X < AbsPos.X
					or Mouse.X > AbsPos.X + AbsSize.X
					or Mouse.Y < (AbsPos.Y - 20 - 1)
					or Mouse.Y > AbsPos.Y + AbsSize.Y
				then
					Dropdown:Close()
				end
			end
		end)

		local ScrollFrame = self.ScrollFrame
		function Dropdown:Open()
			Dropdown.Opened = true
			ScrollFrame.ScrollingEnabled = false
			DropdownHolderCanvas.Visible = true
			TweenService:Create(
				DropdownHolderFrame,
				TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				{ Size = UDim2.fromScale(1, 1) }
			):Play()
		end

		function Dropdown:Close()
			Dropdown.Opened = false
			ScrollFrame.ScrollingEnabled = true
			DropdownHolderFrame.Size = UDim2.fromScale(1, 0.6)
			DropdownHolderCanvas.Visible = false
		end

		function Dropdown:Display()
			local Values = Dropdown.Values
			local Str = ""

			if Config.Multi then
				for Idx, Value in next, Values do
					if Dropdown.Value[Value] then
						Str = Str .. Value .. ", "
					end
				end
				Str = Str:sub(1, #Str - 2)
			else
				Str = Dropdown.Value or ""
			end

			DropdownDisplay.Text = (Str == "" and "--" or Str)
		end

		function Dropdown:GetActiveValues()
			if Config.Multi then
				local T = {}

				for Value, Bool in next, Dropdown.Value do
					table.insert(T, Value)
				end

				return T
			else
				return Dropdown.Value and 1 or 0
			end
		end

		function Dropdown:BuildDropdownList()
			local Values = Dropdown.Values
			local Buttons = {}

			for _, Element in next, DropdownScrollFrame:GetChildren() do
				if not Element:IsA("UIListLayout") then
					Element:Destroy()
				end
			end

			local Count = 0

			for Idx, Value in next, Values do
				local Table = {}

				Count = Count + 1

				local ButtonSelector = New("Frame", {
					Size = UDim2.fromOffset(4, 14),
					BackgroundColor3 = Color3.fromRGB(76, 194, 255),
					Position = UDim2.fromOffset(-1, 16),
					AnchorPoint = Vector2.new(0, 0.5),
					ThemeTag = {
						BackgroundColor3 = "Accent",
					},
				}, {
					New("UICorner", {
						CornerRadius = UDim.new(0, 2),
					}),
				})

				local ButtonLabel = New("TextLabel", {
					FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json"),
					Text = Value,
					TextColor3 = Color3.fromRGB(200, 200, 200),
					TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Left,
					BackgroundColor3 = Color3.fromRGB(255, 255, 255),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					Position = UDim2.fromOffset(10, 0),
					Name = "ButtonLabel",
					ThemeTag = {
						TextColor3 = "Text",
					},
				})

				local Button = New("TextButton", {
					Size = UDim2.new(1, -5, 0, 32),
					BackgroundTransparency = 1,
					ZIndex = 23,
					Text = "",
					Parent = DropdownScrollFrame,
					ThemeTag = {
						BackgroundColor3 = "DropdownOption",
					},
				}, {
					ButtonSelector,
					ButtonLabel,
					New("UICorner", {
						CornerRadius = UDim.new(0, 6),
					}),
				})

				local Selected

				if Config.Multi then
					Selected = Dropdown.Value[Value]
				else
					Selected = Dropdown.Value == Value
				end

				local BackMotor, SetBackTransparency = Creator.SpringMotor(1, Button, "BackgroundTransparency")
				local SelMotor, SetSelTransparency = Creator.SpringMotor(1, ButtonSelector, "BackgroundTransparency")
				local SelectorSizeMotor = Flipper.SingleMotor.new(6)

				SelectorSizeMotor:onStep(function(value)
					ButtonSelector.Size = UDim2.new(0, 4, 0, value)
				end)

				Creator.AddSignal(Button.MouseEnter, function()
					SetBackTransparency(Selected and 0.85 or 0.89)
				end)
				Creator.AddSignal(Button.MouseLeave, function()
					SetBackTransparency(Selected and 0.89 or 1)
				end)
				Creator.AddSignal(Button.MouseButton1Down, function()
					SetBackTransparency(0.92)
				end)
				Creator.AddSignal(Button.MouseButton1Up, function()
					SetBackTransparency(Selected and 0.85 or 0.89)
				end)

				function Table:UpdateButton()
					if Config.Multi then
						Selected = Dropdown.Value[Value]
						if Selected then
							SetBackTransparency(0.89)
						end
					else
						Selected = Dropdown.Value == Value
						SetBackTransparency(Selected and 0.89 or 1)
					end

					SelectorSizeMotor:setGoal(Flipper.Spring.new(Selected and 14 or 6, { frequency = 6 }))
					SetSelTransparency(Selected and 0 or 1)
				end

				ButtonLabel.InputBegan:Connect(function(Input)
					if
						Input.UserInputType == Enum.UserInputType.MouseButton1
						or Input.UserInputType == Enum.UserInputType.Touch
					then
						local Try = not Selected

						if Dropdown:GetActiveValues() == 1 and not Try and not Config.AllowNull then
						else
							if Config.Multi then
								Selected = Try
								Dropdown.Value[Value] = Selected and true or nil
							else
								Selected = Try
								Dropdown.Value = Selected and Value or nil

								for _, OtherButton in next, Buttons do
									OtherButton:UpdateButton()
								end
							end

							Table:UpdateButton()
							Dropdown:Display()

							Library:SafeCallback(Dropdown.Callback, Dropdown.Value)
							Library:SafeCallback(Dropdown.Changed, Dropdown.Value)
						end
					end
				end)

				Table:UpdateButton()
				Dropdown:Display()

				Buttons[Button] = Table
			end

			ListSizeX = 0
			for Button, Table in next, Buttons do
				if Button.ButtonLabel then
					if Button.ButtonLabel.TextBounds.X > ListSizeX then
						ListSizeX = Button.ButtonLabel.TextBounds.X
					end
				end
			end
			ListSizeX = ListSizeX + 30

			RecalculateCanvasSize()
			RecalculateListSize()
		end

		function Dropdown:SetValues(NewValues)
			if NewValues then
				Dropdown.Values = NewValues
			end

			Dropdown:BuildDropdownList()
		end

		function Dropdown:OnChanged(Func)
			Dropdown.Changed = Func
			Func(Dropdown.Value)
		end

		function Dropdown:SetValue(Val)
			if Dropdown.Multi then
				local nTable = {}

				for Value, Bool in next, Val do
					if table.find(Dropdown.Values, Value) then
						nTable[Value] = true
					end
				end

				Dropdown.Value = nTable
			else
				if not Val then
					Dropdown.Value = nil
				elseif table.find(Dropdown.Values, Val) then
					Dropdown.Value = Val
				end
			end

			Dropdown:BuildDropdownList()

			Library:SafeCallback(Dropdown.Callback, Dropdown.Value)
			Library:SafeCallback(Dropdown.Changed, Dropdown.Value)
		end

		function Dropdown:Destroy()
			DropdownFrame:Destroy()
			Library.Options[Idx] = nil
		end

		Dropdown:BuildDropdownList()
		Dropdown:Display()

		local Defaults = {}

		if type(Config.Default) == "string" then
			local Idx = table.find(Dropdown.Values, Config.Default)
			if Idx then
				table.insert(Defaults, Idx)
			end
		elseif type(Config.Default) == "table" then
			for _, Value in next, Config.Default do
				local Idx = table.find(Dropdown.Values, Value)
				if Idx then
					table.insert(Defaults, Idx)
				end
			end
		elseif type(Config.Default) == "number" and Dropdown.Values[Config.Default] ~= nil then
			table.insert(Defaults, Config.Default)
		end

		if next(Defaults) then
			for i = 1, #Defaults do
				local Index = Defaults[i]
				if Config.Multi then
					Dropdown.Value[Dropdown.Values[Index]] = true
				else
					Dropdown.Value = Dropdown.Values[Index]
				end

				if not Config.Multi then
					break
				end
			end

			Dropdown:BuildDropdownList()
			Dropdown:Display()
		end

		Library.Options[Idx] = Dropdown
		return Dropdown
	end

	return Element
end)()

ElementsTable.Input = (function()
	local New = Creator.New
	local AddSignal = Creator.AddSignal

	local Element = {}
	Element.__index = Element
	Element.__type = "Input"

	function Element:New(Idx, Config)
		local Library = self.Library
		assert(Config.Title, "Input - Missing Title")
		Config.Callback = Config.Callback or function() end

		local Input = {
			Value = Config.Default or "",
			Numeric = Config.Numeric or false,
			Finished = Config.Finished or false,
			Callback = Config.Callback or function(Value) end,
			Type = "Input",
		}

		local InputFrame = Components.Element(Config.Title, Config.Description, self.Container, false)

		Input.SetTitle = InputFrame.SetTitle
		Input.SetDesc = InputFrame.SetDesc

		local Textbox = Components.Textbox(InputFrame.Frame, true)
		Textbox.Frame.Position = UDim2.new(1, -10, 0.5, 0)
		Textbox.Frame.AnchorPoint = Vector2.new(1, 0.5)
		Textbox.Frame.Size = UDim2.fromOffset(160, 30)
		Textbox.Input.Text = Config.Default or ""
		Textbox.Input.PlaceholderText = Config.Placeholder or ""

		local Box = Textbox.Input

		function Input:SetValue(Text)
			if Config.MaxLength and #Text > Config.MaxLength then
				Text = Text:sub(1, Config.MaxLength)
			end

			if Input.Numeric then
				if (not tonumber(Text)) and Text:len() > 0 then
					Text = Input.Value
				end
			end

			Input.Value = Text
			Box.Text = Text

			Library:SafeCallback(Input.Callback, Input.Value)
			Library:SafeCallback(Input.Changed, Input.Value)
		end

		if Input.Finished then
			AddSignal(Box.FocusLost, function(enter)
				if not enter then
					return
				end
				Input:SetValue(Box.Text)
			end)
		else
			AddSignal(Box:GetPropertyChangedSignal("Text"), function()
				Input:SetValue(Box.Text)
			end)
		end

		function Input:OnChanged(Func)
			Input.Changed = Func
			Func(Input.Value)
		end

		function Input:Destroy()
			InputFrame:Destroy()
			Library.Options[Idx] = nil
		end

		Library.Options[Idx] = Input
		return Input
	end

	return Element
end)()

ElementsTable.Keybind = (function()
	local New = Creator.New

	local Element = {}
	Element.__index = Element
	Element.__type = "Keybind"

	function Element:New(Idx, Config)
		local Library = self.Library
		assert(Config.Title, "KeyBind - Missing Title")
		assert(Config.Default, "KeyBind - Missing default value.")

		local Keybind = {
			Value = Config.Default,
			Toggled = false,
			Mode = Config.Mode or "Toggle",
			Type = "Keybind",
			Callback = Config.Callback or function(Value) end,
			ChangedCallback = Config.ChangedCallback or function(New) end,
		}

		local Picking = false

		local KeybindFrame = Components.Element(Config.Title, Config.Description, self.Container, true)

		Keybind.SetTitle = KeybindFrame.SetTitle
		Keybind.SetDesc = KeybindFrame.SetDesc

		local KeybindDisplayLabel = New("TextLabel", {
			FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
			Text = Config.Default,
			TextColor3 = Color3.fromRGB(240, 240, 240),
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(0, 0, 0, 14),
			Position = UDim2.new(0, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			ThemeTag = {
				TextColor3 = "Text",
			},
		})

		local KeybindDisplayFrame = New("TextButton", {
			Size = UDim2.fromOffset(0, 30),
			Position = UDim2.new(1, -10, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundTransparency = 0.9,
			Parent = KeybindFrame.Frame,
			AutomaticSize = Enum.AutomaticSize.X,
			ThemeTag = {
				BackgroundColor3 = "Keybind",
			},
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 5),
			}),
			New("UIPadding", {
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 8),
			}),
			New("UIStroke", {
				Transparency = 0.5,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				ThemeTag = {
					Color = "InElementBorder",
				},
			}),
			KeybindDisplayLabel,
		})

		function Keybind:GetState()
			if UserInputService:GetFocusedTextBox() and Keybind.Mode ~= "Always" then
				return false
			end

			if Keybind.Mode == "Always" then
				return true
			elseif Keybind.Mode == "Hold" then
				if Keybind.Value == "None" then
					return false
				end

				local Key = Keybind.Value

				if Key == "MouseLeft" or Key == "MouseRight" then
					return Key == "MouseLeft" and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
						or Key == "MouseRight"
							and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
				else
					return UserInputService:IsKeyDown(Enum.KeyCode[Keybind.Value])
				end
			else
				return Keybind.Toggled
			end
		end

		function Keybind:SetValue(Key, Mode)
			Key = Key or Keybind.Key
			Mode = Mode or Keybind.Mode

			KeybindDisplayLabel.Text = Key
			Keybind.Value = Key
			Keybind.Mode = Mode
		end

		function Keybind:OnClick(Callback)
			Keybind.Clicked = Callback
		end

		function Keybind:OnChanged(Callback)
			Keybind.Changed = Callback
			Callback(Keybind.Value)
		end

		function Keybind:DoClick()
			Library:SafeCallback(Keybind.Callback, Keybind.Toggled)
			Library:SafeCallback(Keybind.Clicked, Keybind.Toggled)
		end

		function Keybind:Destroy()
			KeybindFrame:Destroy()
			Library.Options[Idx] = nil
		end

		Creator.AddSignal(KeybindDisplayFrame.InputBegan, function(Input)
			if
				Input.UserInputType == Enum.UserInputType.MouseButton1
				or Input.UserInputType == Enum.UserInputType.Touch
			then
				Picking = true
				KeybindDisplayLabel.Text = "..."

				wait(0.2)

				local Event
				Event = UserInputService.InputBegan:Connect(function(Input)
					local Key

					if Input.UserInputType == Enum.UserInputType.Keyboard then
						Key = Input.KeyCode.Name
					elseif Input.UserInputType == Enum.UserInputType.MouseButton1 then
						Key = "MouseLeft"
					elseif Input.UserInputType == Enum.UserInputType.MouseButton2 then
						Key = "MouseRight"
					end

					local EndedEvent
					EndedEvent = UserInputService.InputEnded:Connect(function(Input)
						if
							Input.KeyCode.Name == Key
							or Key == "MouseLeft" and Input.UserInputType == Enum.UserInputType.MouseButton1
							or Key == "MouseRight" and Input.UserInputType == Enum.UserInputType.MouseButton2
						then
							Picking = false

							KeybindDisplayLabel.Text = Key
							Keybind.Value = Key

							Library:SafeCallback(Keybind.ChangedCallback, Input.KeyCode or Input.UserInputType)
							Library:SafeCallback(Keybind.Changed, Input.KeyCode or Input.UserInputType)

							Event:Disconnect()
							EndedEvent:Disconnect()
						end
					end)
				end)
			end
		end)

		Creator.AddSignal(UserInputService.InputBegan, function(Input)
			if not Picking and not UserInputService:GetFocusedTextBox() then
				if Keybind.Mode == "Toggle" then
					local Key = Keybind.Value

					if Key == "MouseLeft" or Key == "MouseRight" then
						if
							Key == "MouseLeft" and Input.UserInputType == Enum.UserInputType.MouseButton1
							or Key == "MouseRight" and Input.UserInputType == Enum.UserInputType.MouseButton2
						then
							Keybind.Toggled = not Keybind.Toggled
							Keybind:DoClick()
						end
					elseif Input.UserInputType == Enum.UserInputType.Keyboard then
						if Input.KeyCode.Name == Key then
							Keybind.Toggled = not Keybind.Toggled
							Keybind:DoClick()
						end
					end
				end
			end
		end)

		Library.Options[Idx] = Keybind
		return Keybind
	end

	return Element
end)()

ElementsTable.Paragraph = (function()
	local Paragraph = {}
	Paragraph.__index = Paragraph
	Paragraph.__type = "Paragraph"

	function Paragraph:New(Config)
		assert(Config.Title, "Paragraph - Missing Title")
		Config.Content = Config.Content or ""

		local Paragraph = Components.Element(Config.Title, Config.Content, Paragraph.Container, false)
		Paragraph.Frame.BackgroundTransparency = 0.92
		Paragraph.Border.Transparency = 0.6

		return Paragraph
	end

	return Paragraph
end)()

ElementsTable.Slider = (function()
	local New = Creator.New

	local Element = {}
	Element.__index = Element
	Element.__type = "Slider"

	function Element:New(Idx, Config)
		local Library = self.Library
		assert(Config.Title, "Slider - Missing Title.")
		assert(Config.Default, "Slider - Missing default value.")
		assert(Config.Min, "Slider - Missing minimum value.")
		assert(Config.Max, "Slider - Missing maximum value.")
		assert(Config.Rounding, "Slider - Missing rounding value.")

		local Slider = {
			Value = nil,
			Min = Config.Min,
			Max = Config.Max,
			Rounding = Config.Rounding,
			Callback = Config.Callback or function(Value) end,
			Type = "Slider",
		}

		local Dragging = false

		local SliderFrame = Components.Element(Config.Title, Config.Description, self.Container, false)
		SliderFrame.DescLabel.Size = UDim2.new(1, -170, 0, 14)

		Slider.SetTitle = SliderFrame.SetTitle
		Slider.SetDesc = SliderFrame.SetDesc

		local SliderDot = New("ImageLabel", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, -7, 0.5, 0),
			Size = UDim2.fromOffset(14, 14),
			Image = "http://www.roblox.com/asset/?id=12266946128",
			ThemeTag = {
				ImageColor3 = "Accent",
			},
		})

		local SliderRail = New("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(7, 0),
			Size = UDim2.new(1, -14, 1, 0),
		}, {
			SliderDot,
		})

		local SliderFill = New("Frame", {
			Size = UDim2.new(0, 0, 1, 0),
			ThemeTag = {
				BackgroundColor3 = "Accent",
			},
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
		})

		local SliderDisplay = New("TextLabel", {
			FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json"),
			Text = "Value",
			TextSize = 12,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Right,
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 1,
			Size = UDim2.new(0, 100, 0, 14),
			Position = UDim2.new(0, -4, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			ThemeTag = {
				TextColor3 = "SubText",
			},
		})

		local SliderInner = New("Frame", {
			Size = UDim2.new(1, 0, 0, 4),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			BackgroundTransparency = 0.4,
			Parent = SliderFrame.Frame,
			ThemeTag = {
				BackgroundColor3 = "SliderRail",
			},
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
			New("UISizeConstraint", {
				MaxSize = Vector2.new(150, math.huge),
			}),
			SliderDisplay,
			SliderFill,
			SliderRail,
		})

		Creator.AddSignal(SliderDot.InputBegan, function(Input)
			if
				Input.UserInputType == Enum.UserInputType.MouseButton1
				or Input.UserInputType == Enum.UserInputType.Touch
			then
				Dragging = true
			end
		end)

		Creator.AddSignal(SliderDot.InputEnded, function(Input)
			if
				Input.UserInputType == Enum.UserInputType.MouseButton1
				or Input.UserInputType == Enum.UserInputType.Touch
			then
				Dragging = false
			end
		end)

		Creator.AddSignal(UserInputService.InputChanged, function(Input)
			if
				Dragging
				and (
					Input.UserInputType == Enum.UserInputType.MouseMovement
					or Input.UserInputType == Enum.UserInputType.Touch
				)
			then
				local SizeScale =
					math.clamp((Input.Position.X - SliderRail.AbsolutePosition.X) / SliderRail.AbsoluteSize.X, 0, 1)
				Slider:SetValue(Slider.Min + ((Slider.Max - Slider.Min) * SizeScale))
			end
		end)

		function Slider:OnChanged(Func)
			Slider.Changed = Func
			Func(Slider.Value)
		end

		function Slider:SetValue(Value)
			self.Value = Library:Round(math.clamp(Value, Slider.Min, Slider.Max), Slider.Rounding)
			SliderDot.Position = UDim2.new((self.Value - Slider.Min) / (Slider.Max - Slider.Min), -7, 0.5, 0)
			SliderFill.Size = UDim2.fromScale((self.Value - Slider.Min) / (Slider.Max - Slider.Min), 1)
			SliderDisplay.Text = tostring(self.Value)

			Library:SafeCallback(Slider.Callback, self.Value)
			Library:SafeCallback(Slider.Changed, self.Value)
		end

		function Slider:Destroy()
			SliderFrame:Destroy()
			Library.Options[Idx] = nil
		end

		Slider:SetValue(Config.Default)

		Library.Options[Idx] = Slider
		return Slider
	end

	return Element
end)()

ElementsTable.Toggle = (function()
	local New = Creator.New

	local Element = {}
	Element.__index = Element
	Element.__type = "Toggle"

	function Element:New(Idx, Config)
		local Library = self.Library
		assert(Config.Title, "Toggle - Missing Title")

		local Toggle = {
			Value = Config.Default or false,
			Callback = Config.Callback or function(Value) end,
			Type = "Toggle",
		}

		local ToggleFrame = Components.Element(Config.Title, Config.Description, self.Container, true)
		ToggleFrame.DescLabel.Size = UDim2.new(1, -54, 0, 14)

		Toggle.SetTitle = ToggleFrame.SetTitle
		Toggle.SetDesc = ToggleFrame.SetDesc

		local ToggleCircle = New("ImageLabel", {
			AnchorPoint = Vector2.new(0, 0.5),
			Size = UDim2.fromOffset(14, 14),
			Position = UDim2.new(0, 2, 0.5, 0),
			Image = "http://www.roblox.com/asset/?id=12266946128",
			ImageTransparency = 0.5,
			ThemeTag = {
				ImageColor3 = "ToggleSlider",
			},
		})

		local ToggleBorder = New("UIStroke", {
			Transparency = 0.5,
			ThemeTag = {
				Color = "ToggleSlider",
			},
		})

		local ToggleSlider = New("Frame", {
			Size = UDim2.fromOffset(36, 18),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Parent = ToggleFrame.Frame,
			BackgroundTransparency = 1,
			ThemeTag = {
				BackgroundColor3 = "Accent",
			},
		}, {
			New("UICorner", {
				CornerRadius = UDim.new(0, 9),
			}),
			ToggleBorder,
			ToggleCircle,
		})

		function Toggle:OnChanged(Func)
			Toggle.Changed = Func
			Func(Toggle.Value)
		end

		function Toggle:SetValue(Value)
			Value = not not Value
			Toggle.Value = Value

			Creator.OverrideTag(ToggleBorder, { Color = Toggle.Value and "Accent" or "ToggleSlider" })
			Creator.OverrideTag(ToggleCircle, { ImageColor3 = Toggle.Value and "ToggleToggled" or "ToggleSlider" })
			TweenService:Create(
				ToggleCircle,
				TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
				{ Position = UDim2.new(0, Toggle.Value and 19 or 2, 0.5, 0) }
			):Play()
			TweenService:Create(
				ToggleSlider,
				TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
				{ BackgroundTransparency = Toggle.Value and 0 or 1 }
			):Play()
			ToggleCircle.ImageTransparency = Toggle.Value and 0 or 0.5

			Library:SafeCallback(Toggle.Callback, Toggle.Value)
			Library:SafeCallback(Toggle.Changed, Toggle.Value)
		end

		function Toggle:Destroy()
			ToggleFrame:Destroy()
			Library.Options[Idx] = nil
		end

		Creator.AddSignal(ToggleFrame.Frame.MouseButton1Click, function()
			Toggle:SetValue(not Toggle.Value)
		end)

		Toggle:SetValue(Toggle.Value)

		Library.Options[Idx] = Toggle
		return Toggle
	end

	return Element
end)()

local Icons = {
	assets = {
		["lucide-accessibility"] = "rbxassetid://10709751939",
		["lucide-activity"] = "rbxassetid://10709752035",
		["lucide-air-vent"] = "rbxassetid://10709752131",
		["lucide-airplay"] = "rbxassetid://10709752254",
		["lucide-alarm-check"] = "rbxassetid://10709752405",
		["lucide-alarm-clock"] = "rbxassetid://10709752630",
		["lucide-alarm-clock-off"] = "rbxassetid://10709752508",
		["lucide-alarm-minus"] = "rbxassetid://10709752732",
		["lucide-alarm-plus"] = "rbxassetid://10709752825",
		["lucide-album"] = "rbxassetid://10709752906",
		["lucide-alert-circle"] = "rbxassetid://10709752996",
		["lucide-alert-octagon"] = "rbxassetid://10709753064",
		["lucide-alert-triangle"] = "rbxassetid://10709753149",
		["lucide-align-center"] = "rbxassetid://10709753570",
		["lucide-align-center-horizontal"] = "rbxassetid://10709753272",
		["lucide-align-center-vertical"] = "rbxassetid://10709753421",
		["lucide-align-end-horizontal"] = "rbxassetid://10709753692",
		["lucide-align-end-vertical"] = "rbxassetid://10709753808",
		["lucide-align-horizontal-distribute-center"] = "rbxassetid://10747779791",
		["lucide-align-horizontal-distribute-end"] = "rbxassetid://10747784534",
		["lucide-align-horizontal-distribute-start"] = "rbxassetid://10709754118",
		["lucide-align-horizontal-justify-center"] = "rbxassetid://10709754204",
		["lucide-align-horizontal-justify-end"] = "rbxassetid://10709754317",
		["lucide-align-horizontal-justify-start"] = "rbxassetid://10709754436",
		["lucide-align-horizontal-space-around"] = "rbxassetid://10709754590",
		["lucide-align-horizontal-space-between"] = "rbxassetid://10709754749",
		["lucide-align-justify"] = "rbxassetid://10709759610",
		["lucide-align-left"] = "rbxassetid://10709759764",
		["lucide-align-right"] = "rbxassetid://10709759895",
		["lucide-align-start-horizontal"] = "rbxassetid://10709760051",
		["lucide-align-start-vertical"] = "rbxassetid://10709760244",
		["lucide-align-vertical-distribute-center"] = "rbxassetid://10709760351",
		["lucide-align-vertical-distribute-end"] = "rbxassetid://10709760434",
		["lucide-align-vertical-distribute-start"] = "rbxassetid://10709760612",
		["lucide-align-vertical-justify-center"] = "rbxassetid://10709760814",
		["lucide-align-vertical-justify-end"] = "rbxassetid://10709761003",
		["lucide-align-vertical-justify-start"] = "rbxassetid://10709761176",
		["lucide-align-vertical-space-around"] = "rbxassetid://10709761324",
		["lucide-align-vertical-space-between"] = "rbxassetid://10709761434",
		["lucide-anchor"] = "rbxassetid://10709761530",
		["lucide-angry"] = "rbxassetid://10709761629",
		["lucide-annoyed"] = "rbxassetid://10709761722",
		["lucide-aperture"] = "rbxassetid://10709761813",
		["lucide-apple"] = "rbxassetid://10709761889",
		["lucide-archive"] = "rbxassetid://10709762233",
		["lucide-archive-restore"] = "rbxassetid://10709762058",
		["lucide-armchair"] = "rbxassetid://10709762327",
		["lucide-arrow-big-down"] = "rbxassetid://10747796644",
		["lucide-arrow-big-left"] = "rbxassetid://10709762574",
		["lucide-arrow-big-right"] = "rbxassetid://10709762727",
		["lucide-arrow-big-up"] = "rbxassetid://10709762879",
		["lucide-arrow-down"] = "rbxassetid://10709767827",
		["lucide-arrow-down-circle"] = "rbxassetid://10709763034",
		["lucide-arrow-down-left"] = "rbxassetid://10709767656",
		["lucide-arrow-down-right"] = "rbxassetid://10709767750",
		["lucide-arrow-left"] = "rbxassetid://10709768114",
		["lucide-arrow-left-circle"] = "rbxassetid://10709767936",
		["lucide-arrow-left-right"] = "rbxassetid://10709768019",
		["lucide-arrow-right"] = "rbxassetid://10709768347",
		["lucide-arrow-right-circle"] = "rbxassetid://10709768226",
		["lucide-arrow-up"] = "rbxassetid://10709768939",
		["lucide-arrow-up-circle"] = "rbxassetid://10709768432",
		["lucide-arrow-up-down"] = "rbxassetid://10709768538",
		["lucide-arrow-up-left"] = "rbxassetid://10709768661",
		["lucide-arrow-up-right"] = "rbxassetid://10709768787",
		["lucide-asterisk"] = "rbxassetid://10709769095",
		["lucide-at-sign"] = "rbxassetid://10709769286",
		["lucide-award"] = "rbxassetid://10709769406",
		["lucide-axe"] = "rbxassetid://10709769508",
		["lucide-axis-3d"] = "rbxassetid://10709769598",
		["lucide-baby"] = "rbxassetid://10709769732",
		["lucide-backpack"] = "rbxassetid://10709769841",
		["lucide-baggage-claim"] = "rbxassetid://10709769935",
		["lucide-banana"] = "rbxassetid://10709770005",
		["lucide-banknote"] = "rbxassetid://10709770178",
		["lucide-bar-chart"] = "rbxassetid://10709773755",
		["lucide-bar-chart-2"] = "rbxassetid://10709770317]=],
	FluentCreatorSlice2 = [=[",
		["lucide-bar-chart-3"] = "rbxassetid://10709770431",
		["lucide-bar-chart-4"] = "rbxassetid://10709770560",
		["lucide-bar-chart-horizontal"] = "rbxassetid://10709773669",
		["lucide-barcode"] = "rbxassetid://10747360675",
		["lucide-baseline"] = "rbxassetid://10709773863",
		["lucide-bath"] = "rbxassetid://10709773963",
		["lucide-battery"] = "rbxassetid://10709774640",
		["lucide-battery-charging"] = "rbxassetid://10709774068",
		["lucide-battery-full"] = "rbxassetid://10709774206",
		["lucide-battery-low"] = "rbxassetid://10709774370",
		["lucide-battery-medium"] = "rbxassetid://10709774513",
		["lucide-beaker"] = "rbxassetid://10709774756",
		["lucide-bed"] = "rbxassetid://10709775036",
		["lucide-bed-double"] = "rbxassetid://10709774864",
		["lucide-bed-single"] = "rbxassetid://10709774968",
		["lucide-beer"] = "rbxassetid://10709775167",
		["lucide-bell"] = "rbxassetid://10709775704",
		["lucide-bell-minus"] = "rbxassetid://10709775241",
		["lucide-bell-off"] = "rbxassetid://10709775320",
		["lucide-bell-plus"] = "rbxassetid://10709775448",
		["lucide-bell-ring"] = "rbxassetid://10709775560",
		["lucide-bike"] = "rbxassetid://10709775894",
		["lucide-binary"] = "rbxassetid://10709776050",
		["lucide-bitcoin"] = "rbxassetid://10709776126",
		["lucide-bluetooth"] = "rbxassetid://10709776655",
		["lucide-bluetooth-connected"] = "rbxassetid://10709776240",
		["lucide-bluetooth-off"] = "rbxassetid://10709776344",
		["lucide-bluetooth-searching"] = "rbxassetid://10709776501",
		["lucide-bold"] = "rbxassetid://10747813908",
		["lucide-bomb"] = "rbxassetid://10709781460",
		["lucide-bone"] = "rbxassetid://10709781605",
		["lucide-book"] = "rbxassetid://10709781824",
		["lucide-book-open"] = "rbxassetid://10709781717",
		["lucide-bookmark"] = "rbxassetid://10709782154",
		["lucide-bookmark-minus"] = "rbxassetid://10709781919",
		["lucide-bookmark-plus"] = "rbxassetid://10709782044",
		["lucide-bot"] = "rbxassetid://10709782230",
		["lucide-box"] = "rbxassetid://10709782497",
		["lucide-box-select"] = "rbxassetid://10709782342",
		["lucide-boxes"] = "rbxassetid://10709782582",
		["lucide-briefcase"] = "rbxassetid://10709782662",
		["lucide-brush"] = "rbxassetid://10709782758",
		["lucide-bug"] = "rbxassetid://10709782845",
		["lucide-building"] = "rbxassetid://10709783051",
		["lucide-building-2"] = "rbxassetid://10709782939",
		["lucide-bus"] = "rbxassetid://10709783137",
		["lucide-cake"] = "rbxassetid://10709783217",
		["lucide-calculator"] = "rbxassetid://10709783311",
		["lucide-calendar"] = "rbxassetid://10709789505",
		["lucide-calendar-check"] = "rbxassetid://10709783474",
		["lucide-calendar-check-2"] = "rbxassetid://10709783392",
		["lucide-calendar-clock"] = "rbxassetid://10709783577",
		["lucide-calendar-days"] = "rbxassetid://10709783673",
		["lucide-calendar-heart"] = "rbxassetid://10709783835",
		["lucide-calendar-minus"] = "rbxassetid://10709783959",
		["lucide-calendar-off"] = "rbxassetid://10709788784",
		["lucide-calendar-plus"] = "rbxassetid://10709788937",
		["lucide-calendar-range"] = "rbxassetid://10709789053",
		["lucide-calendar-search"] = "rbxassetid://10709789200",
		["lucide-calendar-x"] = "rbxassetid://10709789407",
		["lucide-calendar-x-2"] = "rbxassetid://10709789329",
		["lucide-camera"] = "rbxassetid://10709789686",
		["lucide-camera-off"] = "rbxassetid://10747822677",
		["lucide-car"] = "rbxassetid://10709789810",
		["lucide-carrot"] = "rbxassetid://10709789960",
		["lucide-cast"] = "rbxassetid://10709790097",
		["lucide-charge"] = "rbxassetid://10709790202",
		["lucide-check"] = "rbxassetid://10709790644",
		["lucide-check-circle"] = "rbxassetid://10709790387",
		["lucide-check-circle-2"] = "rbxassetid://10709790298",
		["lucide-check-square"] = "rbxassetid://10709790537",
		["lucide-chef-hat"] = "rbxassetid://10709790757",
		["lucide-cherry"] = "rbxassetid://10709790875",
		["lucide-chevron-down"] = "rbxassetid://10709790948",
		["lucide-chevron-first"] = "rbxassetid://10709791015",
		["lucide-chevron-last"] = "rbxassetid://10709791130",
		["lucide-chevron-left"] = "rbxassetid://10709791281",
		["lucide-chevron-right"] = "rbxassetid://10709791437",
		["lucide-chevron-up"] = "rbxassetid://10709791523",
		["lucide-chevrons-down"] = "rbxassetid://10709796864",
		["lucide-chevrons-down-up"] = "rbxassetid://10709791632",
		["lucide-chevrons-left"] = "rbxassetid://10709797151",
		["lucide-chevrons-left-right"] = "rbxassetid://10709797006",
		["lucide-chevrons-right"] = "rbxassetid://10709797382",
		["lucide-chevrons-right-left"] = "rbxassetid://10709797274",
		["lucide-chevrons-up"] = "rbxassetid://10709797622",
		["lucide-chevrons-up-down"] = "rbxassetid://10709797508",
		["lucide-chrome"] = "rbxassetid://10709797725",
		["lucide-circle"] = "rbxassetid://10709798174",
		["lucide-circle-dot"] = "rbxassetid://10709797837",
		["lucide-circle-ellipsis"] = "rbxassetid://10709797985",
		["lucide-circle-slashed"] = "rbxassetid://10709798100",
		["lucide-citrus"] = "rbxassetid://10709798276",
		["lucide-clapperboard"] = "rbxassetid://10709798350",
		["lucide-clipboard"] = "rbxassetid://10709799288",
		["lucide-clipboard-check"] = "rbxassetid://10709798443",
		["lucide-clipboard-copy"] = "rbxassetid://10709798574",
		["lucide-clipboard-edit"] = "rbxassetid://10709798682",
		["lucide-clipboard-list"] = "rbxassetid://10709798792",
		["lucide-clipboard-signature"] = "rbxassetid://10709798890",
		["lucide-clipboard-type"] = "rbxassetid://10709798999",
		["lucide-clipboard-x"] = "rbxassetid://10709799124",
		["lucide-clock"] = "rbxassetid://10709805144",
		["lucide-clock-1"] = "rbxassetid://10709799535",
		["lucide-clock-10"] = "rbxassetid://10709799718",
		["lucide-clock-11"] = "rbxassetid://10709799818",
		["lucide-clock-12"] = "rbxassetid://10709799962",
		["lucide-clock-2"] = "rbxassetid://10709803876",
		["lucide-clock-3"] = "rbxassetid://10709803989",
		["lucide-clock-4"] = "rbxassetid://10709804164",
		["lucide-clock-5"] = "rbxassetid://10709804291",
		["lucide-clock-6"] = "rbxassetid://10709804435",
		["lucide-clock-7"] = "rbxassetid://10709804599",
		["lucide-clock-8"] = "rbxassetid://10709804784",
		["lucide-clock-9"] = "rbxassetid://10709804996",
		["lucide-cloud"] = "rbxassetid://10709806740",
		["lucide-cloud-cog"] = "rbxassetid://10709805262",
		["lucide-cloud-drizzle"] = "rbxassetid://10709805371",
		["lucide-cloud-fog"] = "rbxassetid://10709805477",
		["lucide-cloud-hail"] = "rbxassetid://10709805596",
		["lucide-cloud-lightning"] = "rbxassetid://10709805727",
		["lucide-cloud-moon"] = "rbxassetid://10709805942",
		["lucide-cloud-moon-rain"] = "rbxassetid://10709805838",
		["lucide-cloud-off"] = "rbxassetid://10709806060",
		["lucide-cloud-rain"] = "rbxassetid://10709806277",
		["lucide-cloud-rain-wind"] = "rbxassetid://10709806166",
		["lucide-cloud-snow"] = "rbxassetid://10709806374",
		["lucide-cloud-sun"] = "rbxassetid://10709806631",
		["lucide-cloud-sun-rain"] = "rbxassetid://10709806475",
		["lucide-cloudy"] = "rbxassetid://10709806859",
		["lucide-clover"] = "rbxassetid://10709806995",
		["lucide-code"] = "rbxassetid://10709810463",
		["lucide-code-2"] = "rbxassetid://10709807111",
		["lucide-codepen"] = "rbxassetid://10709810534",
		["lucide-codesandbox"] = "rbxassetid://10709810676",
		["lucide-coffee"] = "rbxassetid://10709810814",
		["lucide-cog"] = "rbxassetid://10709810948",
		["lucide-coins"] = "rbxassetid://10709811110",
		["lucide-columns"] = "rbxassetid://10709811261",
		["lucide-command"] = "rbxassetid://10709811365",
		["lucide-compass"] = "rbxassetid://10709811445",
		["lucide-component"] = "rbxassetid://10709811595",
		["lucide-concierge-bell"] = "rbxassetid://10709811706",
		["lucide-connection"] = "rbxassetid://10747361219",
		["lucide-contact"] = "rbxassetid://10709811834",
		["lucide-contrast"] = "rbxassetid://10709811939",
		["lucide-cookie"] = "rbxassetid://10709812067",
		["lucide-copy"] = "rbxassetid://10709812159",
		["lucide-copyleft"] = "rbxassetid://10709812251",
		["lucide-copyright"] = "rbxassetid://10709812311",
		["lucide-corner-down-left"] = "rbxassetid://10709812396",
		["lucide-corner-down-right"] = "rbxassetid://10709812485",
		["lucide-corner-left-down"] = "rbxassetid://10709812632",
		["lucide-corner-left-up"] = "rbxassetid://10709812784",
		["lucide-corner-right-down"] = "rbxassetid://10709812939",
		["lucide-corner-right-up"] = "rbxassetid://10709813094",
		["lucide-corner-up-left"] = "rbxassetid://10709813185",
		["lucide-corner-up-right"] = "rbxassetid://10709813281",
		["lucide-cpu"] = "rbxassetid://10709813383",
		["lucide-croissant"] = "rbxassetid://10709818125",
		["lucide-crop"] = "rbxassetid://10709818245",
		["lucide-cross"] = "rbxassetid://10709818399",
		["lucide-crosshair"] = "rbxassetid://10709818534",
		["lucide-crown"] = "rbxassetid://10709818626",
		["lucide-cup-soda"] = "rbxassetid://10709818763",
		["lucide-curly-braces"] = "rbxassetid://10709818847",
		["lucide-currency"] = "rbxassetid://10709818931",
		["lucide-database"] = "rbxassetid://10709818996",
		["lucide-delete"] = "rbxassetid://10709819059",
		["lucide-diamond"] = "rbxassetid://10709819149",
		["lucide-dice-1"] = "rbxassetid://10709819266",
		["lucide-dice-2"] = "rbxassetid://10709819361",
		["lucide-dice-3"] = "rbxassetid://10709819508",
		["lucide-dice-4"] = "rbxassetid://10709819670",
		["lucide-dice-5"] = "rbxassetid://10709819801",
		["lucide-dice-6"] = "rbxassetid://10709819896",
		["lucide-dices"] = "rbxassetid://10723343321",
		["lucide-diff"] = "rbxassetid://10723343416",
		["lucide-disc"] = "rbxassetid://10723343537",
		["lucide-divide"] = "rbxassetid://10723343805",
		["lucide-divide-circle"] = "rbxassetid://10723343636",
		["lucide-divide-square"] = "rbxassetid://10723343737",
		["lucide-dollar-sign"] = "rbxassetid://10723343958",
		["lucide-download"] = "rbxassetid://10723344270",
		["lucide-download-cloud"] = "rbxassetid://10723344088",
		["lucide-droplet"] = "rbxassetid://10723344432",
		["lucide-droplets"] = "rbxassetid://10734883356",
		["lucide-drumstick"] = "rbxassetid://10723344737",
		["lucide-edit"] = "rbxassetid://10734883598",
		["lucide-edit-2"] = "rbxassetid://10723344885",
		["lucide-edit-3"] = "rbxassetid://10723345088",
		["lucide-egg"] = "rbxassetid://10723345518",
		["lucide-egg-fried"] = "rbxassetid://10723345347",
		["lucide-electricity"] = "rbxassetid://10723345749",
		["lucide-electricity-off"] = "rbxassetid://10723345643",
		["lucide-equal"] = "rbxassetid://10723345990",
		["lucide-equal-not"] = "rbxassetid://10723345866",
		["lucide-eraser"] = "rbxassetid://10723346158",
		["lucide-euro"] = "rbxassetid://10723346372",
		["lucide-expand"] = "rbxassetid://10723346553",
		["lucide-external-link"] = "rbxassetid://10723346684",
		["lucide-eye"] = "rbxassetid://10723346959",
		["lucide-eye-off"] = "rbxassetid://10723346871",
		["lucide-factory"] = "rbxassetid://10723347051",
		["lucide-fan"] = "rbxassetid://10723354359",
		["lucide-fast-forward"] = "rbxassetid://10723354521",
		["lucide-feather"] = "rbxassetid://10723354671",
		["lucide-figma"] = "rbxassetid://10723354801",
		["lucide-file"] = "rbxassetid://10723374641",
		["lucide-file-archive"] = "rbxassetid://10723354921",
		["lucide-file-audio"] = "rbxassetid://10723355148",
		["lucide-file-audio-2"] = "rbxassetid://10723355026",
		["lucide-file-axis-3d"] = "rbxassetid://10723355272",
		["lucide-file-badge"] = "rbxassetid://10723355622",
		["lucide-file-badge-2"] = "rbxassetid://10723355451",
		["lucide-file-bar-chart"] = "rbxassetid://10723355887",
		["lucide-file-bar-chart-2"] = "rbxassetid://10723355746",
		["lucide-file-box"] = "rbxassetid://10723355989",
		["lucide-file-check"] = "rbxassetid://10723356210",
		["lucide-file-check-2"] = "rbxassetid://10723356100",
		["lucide-file-clock"] = "rbxassetid://10723356329",
		["lucide-file-code"] = "rbxassetid://10723356507",
		["lucide-file-cog"] = "rbxassetid://10723356830",
		["lucide-file-cog-2"] = "rbxassetid://10723356676",
		["lucide-file-diff"] = "rbxassetid://10723357039",
		["lucide-file-digit"] = "rbxassetid://10723357151",
		["lucide-file-down"] = "rbxassetid://10723357322",
		["lucide-file-edit"] = "rbxassetid://10723357495",
		["lucide-file-heart"] = "rbxassetid://10723357637",
		["lucide-file-image"] = "rbxassetid://10723357790",
		["lucide-file-input"] = "rbxassetid://10723357933",
		["lucide-file-json"] = "rbxassetid://10723364435",
		["lucide-file-json-2"] = "rbxassetid://10723364361",
		["lucide-file-key"] = "rbxassetid://10723364605",
		["lucide-file-key-2"] = "rbxassetid://10723364515",
		["lucide-file-line-chart"] = "rbxassetid://10723364725",
		["lucide-file-lock"] = "rbxassetid://10723364957",
		["lucide-file-lock-2"] = "rbxassetid://10723364861",
		["lucide-file-minus"] = "rbxassetid://10723365254",
		["lucide-file-minus-2"] = "rbxassetid://10723365086",
		["lucide-file-output"] = "rbxassetid://10723365457",
		["lucide-file-pie-chart"] = "rbxassetid://10723365598",
		["lucide-file-plus"] = "rbxassetid://10723365877",
		["lucide-file-plus-2"] = "rbxassetid://10723365766",
		["lucide-file-question"] = "rbxassetid://10723365987",
		["lucide-file-scan"] = "rbxassetid://10723366167",
		["lucide-file-search"] = "rbxassetid://10723366550",
		["lucide-file-search-2"] = "rbxassetid://10723366340",
		["lucide-file-signature"] = "rbxassetid://10723366741",
		["lucide-file-spreadsheet"] = "rbxassetid://10723366962",
		["lucide-file-symlink"] = "rbxassetid://10723367098",
		["lucide-file-terminal"] = "rbxassetid://10723367244",
		["lucide-file-text"] = "rbxassetid://10723367380",
		["lucide-file-type"] = "rbxassetid://10723367606",
		["lucide-file-type-2"] = "rbxassetid://10723367509",
		["lucide-file-up"] = "rbxassetid://10723367734",
		["lucide-file-video"] = "rbxassetid://10723373884",
		["lucide-file-video-2"] = "rbxassetid://10723367834",
		["lucide-file-volume"] = "rbxassetid://10723374172",
		["lucide-file-volume-2"] = "rbxassetid://10723374030",
		["lucide-file-warning"] = "rbxassetid://10723374276",
		["lucide-file-x"] = "rbxassetid://10723374544",
		["lucide-file-x-2"] = "rbxassetid://10723374378",
		["lucide-files"] = "rbxassetid://10723374759",
		["lucide-film"] = "rbxassetid://10723374981",
		["lucide-filter"] = "rbxassetid://10723375128",
		["lucide-fingerprint"] = "rbxassetid://10723375250",
		["lucide-flag"] = "rbxassetid://10723375890",
		["lucide-flag-off"] = "rbxassetid://10723375443",
		["lucide-flag-triangle-left"] = "rbxassetid://10723375608",
		["lucide-flag-triangle-right"] = "rbxassetid://10723375727",
		["lucide-flame"] = "rbxassetid://10723376114",
		["lucide-flashlight"] = "rbxassetid://10723376471",
		["lucide-flashlight-off"] = "rbxassetid://10723376365",
		["lucide-flask-conical"] = "rbxassetid://10734883986",
		["lucide-flask-round"] = "rbxassetid://10723376614",
		["lucide-flip-horizontal"] = "rbxassetid://10723376884",
		["lucide-flip-horizontal-2"] = "rbxassetid://10723376745",
		["lucide-flip-vertical"] = "rbxassetid://10723377138",
		["lucide-flip-vertical-2"] = "rbxassetid://10723377026",
		["lucide-flower"] = "rbxassetid://10747830374",
		["lucide-flower-2"] = "rbxassetid://10723377305",
		["lucide-focus"] = "rbxassetid://10723377537",
		["lucide-folder"] = "rbxassetid://10723387563",
		["lucide-folder-archive"] = "rbxassetid://10723384478",
		["lucide-folder-check"] = "rbxassetid://10723384605",
		["lucide-folder-clock"] = "rbxassetid://10723384731",
		["lucide-folder-closed"] = "rbxassetid://10723384893",
		["lucide-folder-cog"] = "rbxassetid://10723385213",
		["lucide-folder-cog-2"] = "rbxassetid://10723385036",
		["lucide-folder-down"] = "rbxassetid://10723385338",
		["lucide-folder-edit"] = "rbxassetid://10723385445",
		["lucide-folder-heart"] = "rbxassetid://10723385545",
		["lucide-folder-input"] = "rbxassetid://10723385721",
		["lucide-folder-key"] = "rbxassetid://10723385848",
		["lucide-folder-lock"] = "rbxassetid://10723386005",
		["lucide-folder-minus"] = "rbxassetid://10723386127",
		["lucide-folder-open"] = "rbxassetid://10723386277",
		["lucide-folder-output"] = "rbxassetid://10723386386",
		["lucide-folder-plus"] = "rbxassetid://10723386531",
		["lucide-folder-search"] = "rbxassetid://10723386787",
		["lucide-folder-search-2"] = "rbxassetid://10723386674",
		["lucide-folder-symlink"] = "rbxassetid://10723386930",
		["lucide-folder-tree"] = "rbxassetid://10723387085",
		["lucide-folder-up"] = "rbxassetid://10723387265",
		["lucide-folder-x"] = "rbxassetid://10723387448",
		["lucide-folders"] = "rbxassetid://10723387721",
		["lucide-form-input"] = "rbxassetid://10723387841",
		["lucide-forward"] = "rbxassetid://10723388016",
		["lucide-frame"] = "rbxassetid://10723394389",
		["lucide-framer"] = "rbxassetid://10723394565",
		["lucide-frown"] = "rbxassetid://10723394681",
		["lucide-fuel"] = "rbxassetid://10723394846",
		["lucide-function-square"] = "rbxassetid://10723395041",
		["lucide-gamepad"] = "rbxassetid://10723395457",
		["lucide-gamepad-2"] = "rbxassetid://10723395215",
		["lucide-gauge"] = "rbxassetid://10723395708",
		["lucide-gavel"] = "rbxassetid://10723395896",
		["lucide-gem"] = "rbxassetid://10723396000",
		["lucide-ghost"] = "rbxassetid://10723396107",
		["lucide-gift"] = "rbxassetid://10723396402",
		["lucide-gift-card"] = "rbxassetid://10723396225",
		["lucide-git-branch"] = "rbxassetid://10723396676",
		["lucide-git-branch-plus"] = "rbxassetid://10723396542",
		["lucide-git-commit"] = "rbxassetid://10723396812",
		["lucide-git-compare"] = "rbxassetid://10723396954",
		["lucide-git-fork"] = "rbxassetid://10723397049",
		["lucide-git-merge"] = "rbxassetid://10723397165",
		["lucide-git-pull-request"] = "rbxassetid://10723397431",
		["lucide-git-pull-request-closed"] = "rbxassetid://10723397268",
		["lucide-git-pull-request-draft"] = "rbxassetid://10734884302",
		["lucide-glass"] = "rbxassetid://10723397788",
		["lucide-glass-2"] = "rbxassetid://10723397529",
		["lucide-glass-water"] = "rbxassetid://10723397678",
		["lucide-glasses"] = "rbxassetid://10723397895",
		["lucide-globe"] = "rbxassetid://10723404337",
		["lucide-globe-2"] = "rbxassetid://10723398002",
		["lucide-grab"] = "rbxassetid://10723404472",
		["lucide-graduation-cap"] = "rbxassetid://10723404691",
		["lucide-grape"] = "rbxassetid://10723404822",
		["lucide-grid"] = "rbxassetid://10723404936",
		["lucide-grip-horizontal"] = "rbxassetid://10723405089",
		["lucide-grip-vertical"] = "rbxassetid://10723405236",
		["lucide-hammer"] = "rbxassetid://10723405360",
		["lucide-hand"] = "rbxassetid://10723405649",
		["lucide-hand-metal"] = "rbxassetid://10723405508",
		["lucide-hard-drive"] = "rbxassetid://10723405749",
		["lucide-hard-hat"] = "rbxassetid://10723405859",
		["lucide-hash"] = "rbxassetid://10723405975",
		["lucide-haze"] = "rbxassetid://10723406078",
		["lucide-headphones"] = "rbxassetid://10723406165",
		["lucide-heart"] = "rbxassetid://10723406885",
		["lucide-heart-crack"] = "rbxassetid://10723406299",
		["lucide-heart-handshake"] = "rbxassetid://10723406480",
		["lucide-heart-off"] = "rbxassetid://10723406662",
		["lucide-heart-pulse"] = "rbxassetid://10723406795",
		["lucide-help-circle"] = "rbxassetid://10723406988",
		["lucide-hexagon"] = "rbxassetid://10723407092",
		["lucide-highlighter"] = "rbxassetid://10723407192",
		["lucide-history"] = "rbxassetid://10723407335",
		["lucide-home"] = "rbxassetid://10723407389",
		["lucide-hourglass"] = "rbxassetid://10723407498",
		["lucide-ice-cream"] = "rbxassetid://10723414308",
		["lucide-image"] = "rbxassetid://10723415040",
		["lucide-image-minus"] = "rbxassetid://10723414487",
		["lucide-image-off"] = "rbxassetid://10723414677",
		["lucide-image-plus"] = "rbxassetid://10723414827",
		["lucide-import"] = "rbxassetid://10723415205",
		["lucide-inbox"] = "rbxassetid://10723415335",
		["lucide-indent"] = "rbxassetid://10723415494",
		["lucide-indian-rupee"] = "rbxassetid://10723415642",
		["lucide-infinity"] = "rbxassetid://10723415766",
		["lucide-info"] = "rbxassetid://10723415903",
		["lucide-inspect"] = "rbxassetid://10723416057",
		["lucide-italic"] = "rbxassetid://10723416195",
		["lucide-japanese-yen"] = "rbxassetid://10723416363",
		["lucide-joystick"] = "rbxassetid://10723416527",
		["lucide-key"] = "rbxassetid://10723416652",
		["lucide-keyboard"] = "rbxassetid://10723416765",
		["lucide-lamp"] = "rbxassetid://10723417513",
		["lucide-lamp-ceiling"] = "rbxassetid://10723416922",
		["lucide-lamp-desk"] = "rbxassetid://10723417016",
		["lucide-lamp-floor"] = "rbxassetid://10723417131",
		["lucide-lamp-wall-down"] = "rbxassetid://10723417240",
		["lucide-lamp-wall-up"] = "rbxassetid://10723417356",
		["lucide-landmark"] = "rbxassetid://10723417608",
		["lucide-languages"] = "rbxassetid://10723417703",
		["lucide-laptop"] = "rbxassetid://10723423881",
		["lucide-laptop-2"] = "rbxassetid://10723417797",
		["lucide-lasso"] = "rbxassetid://10723424235",
		["lucide-lasso-select"] = "rbxassetid://10723424058",
		["lucide-laugh"] = "rbxassetid://10723424372",
		["lucide-layers"] = "rbxassetid://10723424505",
		["lucide-layout"] = "rbxassetid://10723425376",
		["lucide-layout-dashboard"] = "rbxassetid://10723424646",
		["lucide-layout-grid"] = "rbxassetid://10723424838",
		["lucide-layout-list"] = "rbxassetid://10723424963",
		["lucide-layout-template"] = "rbxassetid://10723425187",
		["lucide-leaf"] = "rbxassetid://10723425539",
		["lucide-library"] = "rbxassetid://10723425615",
		["lucide-life-buoy"] = "rbxassetid://10723425685",
		["lucide-lightbulb"] = "rbxassetid://10723425852",
		["lucide-lightbulb-off"] = "rbxassetid://10723425762",
		["lucide-line-chart"] = "rbxassetid://10723426393",
		["lucide-link"] = "rbxassetid://10723426722",
		["lucide-link-2"] = "rbxassetid://10723426595",
		["lucide-link-2-off"] = "rbxassetid://10723426513",
		["lucide-list"] = "rbxassetid://10723433811",
		["lucide-list-checks"] = "rbxassetid://10734884548",
		["lucide-list-end"] = "rbxassetid://10723426886",
		["lucide-list-minus"] = "rbxassetid://10723426986",
		["lucide-list-music"] = "rbxassetid://10723427081",
		["lucide-list-ordered"] = "rbxassetid://10723427199",
		["lucide-list-plus"] = "rbxassetid://10723427334",
		["lucide-list-start"] = "rbxassetid://10723427494",
		["lucide-list-video"] = "rbxassetid://10723427619",
		["lucide-list-x"] = "rbxassetid://10723433655",
		["lucide-loader"] = "rbxassetid://10723434070",
		["lucide-loader-2"] = "rbxassetid://10723433935",
		["lucide-locate"] = "rbxassetid://10723434557",
		["lucide-locate-fixed"] = "rbxassetid://10723434236",
		["lucide-locate-off"] = "rbxassetid://10723434379",
		["lucide-lock"] = "rbxassetid://10723434711",
		["lucide-log-in"] = "rbxassetid://10723434830",
		["lucide-log-out"] = "rbxassetid://10723434906",
		["lucide-luggage"] = "rbxassetid://10723434993",
		["lucide-magnet"] = "rbxassetid://10723435069",
		["lucide-mail"] = "rbxassetid://10734885430",
		["lucide-mail-check"] = "rbxassetid://10723435182",
		["lucide-mail-minus"] = "rbxassetid://10723435261",
		["lucide-mail-open"] = "rbxassetid://10723435342",
		["lucide-mail-plus"] = "rbxassetid://10723435443",
		["lucide-mail-question"] = "rbxassetid://10723435515",
		["lucide-mail-search"] = "rbxassetid://10734884739",
		["lucide-mail-warning"] = "rbxassetid://10734885015",
		["lucide-mail-x"] = "rbxassetid://10734885247",
		["lucide-mails"] = "rbxassetid://10734885614",
		["lucide-map"] = "rbxassetid://10734886202",
		["lucide-map-pin"] = "rbxassetid://10734886004",
		["lucide-map-pin-off"] = "rbxassetid://10734885803",
		["lucide-maximize"] = "rbxassetid://10734886735",
		["lucide-maximize-2"] = "rbxassetid://10734886496",
		["lucide-medal"] = "rbxassetid://10734887072",
		["lucide-megaphone"] = "rbxassetid://10734887454",
		["lucide-megaphone-off"] = "rbxassetid://10734887311",
		["lucide-meh"] = "rbxassetid://10734887603",
		["lucide-menu"] = "rbxassetid://10734887784",
		["lucide-message-circle"] = "rbxassetid://10734888000",
		["lucide-message-square"] = "rbxassetid://10734888228",
		["lucide-mic"] = "rbxassetid://10734888864",
		["lucide-mic-2"] = "rbxassetid://10734888430",
		["lucide-mic-off"] = "rbxassetid://10734888646",
		["lucide-microscope"] = "rbxassetid://10734889106",
		["lucide-microwave"] = "rbxassetid://10734895076",
		["lucide-milestone"] = "rbxassetid://10734895310",
		["lucide-minimize"] = "rbxassetid://10734895698",
		["lucide-minimize-2"] = "rbxassetid://10734895530",
		["lucide-minus"] = "rbxassetid://10734896206",
		["lucide-minus-circle"] = "rbxassetid://10734895856",
		["lucide-minus-square"] = "rbxassetid://10734896029",
		["lucide-monitor"] = "rbxassetid://10734896881",
		["lucide-monitor-off"] = "rbxassetid://10734896360",
		["lucide-monitor-speaker"] = "rbxassetid://10734896512",
		["lucide-moon"] = "rbxassetid://10734897102",
		["lucide-more-horizontal"] = "rbxassetid://10734897250",
		["lucide-more-vertical"] = "rbxassetid://10734897387",
		["lucide-mountain"] = "rbxassetid://10734897956",
		["lucide-mountain-snow"] = "rbxassetid://10734897665",
		["lucide-mouse"] = "rbxassetid://10734898592",
		["lucide-mouse-pointer"] = "rbxassetid://10734898476",
		["lucide-mouse-pointer-2"] = "rbxassetid://10734898194",
		["lucide-mouse-pointer-click"] = "rbxassetid://10734898355",
		["lucide-move"] = "rbxassetid://10734900011",
		["lucide-move-3d"] = "rbxassetid://10734898756",
		["lucide-move-diagonal"] = "rbxassetid://10734899164",
		["lucide-move-diagonal-2"] = "rbxassetid://10734898934",
		["lucide-move-horizontal"] = "rbxassetid://10734899414",
		["lucide-move-vertical"] = "rbxassetid://10734899821",
		["lucide-music"] = "rbxassetid://10734905958",
		["lucide-music-2"] = "rbxassetid://10734900215",
		["lucide-music-3"] = "rbxassetid://10734905665",
		["lucide-music-4"] = "rbxassetid://10734905823",
		["lucide-navigation"] = "rbxassetid://10734906744",
		["lucide-navigation-2"] = "rbxassetid://10734906332",
		["lucide-navigation-2-off"] = "rbxassetid://10734906144",
		["lucide-navigation-off"] = "rbxassetid://10734906580",
		["lucide-network"] = "rbxassetid://10734906975",
		["lucide-newspaper"] = "rbxassetid://10734907168",
		["lucide-octagon"] = "rbxassetid://10734907361",
		["lucide-option"] = "rbxassetid://10734907649",
		["lucide-outdent"] = "rbxassetid://10734907933",
		["lucide-package"] = "rbxassetid://10734909540",
		["lucide-package-2"] = "rbxassetid://10734908151",
		["lucide-package-check"] = "rbxassetid://10734908384",
		["lucide-package-minus"] = "rbxassetid://10734908626",
		["lucide-package-open"] = "rbxassetid://10734908793",
		["lucide-package-plus"] = "rbxassetid://10734909016",
		["lucide-package-search"] = "rbxassetid://10734909196",
		["lucide-package-x"] = "rbxassetid://10734909375",
		["lucide-paint-bucket"] = "rbxassetid://10734909847",
		["lucide-paintbrush"] = "rbxassetid://10734910187",
		["lucide-paintbrush-2"] = "rbxassetid://10734910030",
		["lucide-palette"] = "rbxassetid://10734910430",
		["lucide-palmtree"] = "rbxassetid://10734910680",
		["lucide-paperclip"] = "rbxassetid://10734910927",
		["lucide-party-popper"] = "rbxassetid://10734918735",
		["lucide-pause"] = "rbxassetid://10734919336",
		["lucide-pause-circle"] = "rbxassetid://10735024209",
		["lucide-pause-octagon"] = "rbxassetid://10734919143",
		["lucide-pen-tool"] = "rbxassetid://10734919503",
		["lucide-pencil"] = "rbxassetid://10734919691",
		["lucide-percent"] = "rbxassetid://10734919919",
		["lucide-person-standing"] = "rbxassetid://10734920149",
		["lucide-phone"] = "rbxassetid://10734921524",
		["lucide-phone-call"] = "rbxassetid://10734920305",
		["lucide-phone-forwarded"] = "rbxassetid://10734920508",
		["lucide-phone-incoming"] = "rbxassetid://10734920694",
		["lucide-phone-missed"] = "rbxassetid://10734920845",
		["lucide-phone-off"] = "rbxassetid://10734921077",
		["lucide-phone-outgoing"] = "rbxassetid://10734921288",
		["lucide-pie-chart"] = "rbxassetid://10734921727",
		["lucide-piggy-bank"] = "rbxassetid://10734921935",
		["lucide-pin"] = "rbxassetid://10734922324",
		["lucide-pin-off"] = "rbxassetid://10734922180",
		["lucide-pipette"] = "rbxassetid://10734922497",
		["lucide-pizza"] = "rbxassetid://10734922774",
		["lucide-plane"] = "rbxassetid://10734922971",
		["lucide-play"] = "rbxassetid://10734923549",
		["lucide-play-circle"] = "rbxassetid://10734923214",
		["lucide-plus"] = "rbxassetid://10734924532",
		["lucide-plus-circle"] = "rbxassetid://10734923868",
		["lucide-plus-square"] = "rbxassetid://10734924219",
		["lucide-podcast"] = "rbxassetid://10734929553",
		["lucide-pointer"] = "rbxassetid://10734929723",
		["lucide-pound-sterling"] = "rbxassetid://10734929981",
		["lucide-power"] = "rbxassetid://10734930466",
		["lucide-power-off"] = "rbxassetid://10734930257",
		["lucide-printer"] = "rbxassetid://10734930632",
		["lucide-puzzle"] = "rbxassetid://10734930886",
		["lucide-quote"] = "rbxassetid://10734931234",
		["lucide-radio"] = "rbxassetid://10734931596",
		["lucide-radio-receiver"] = "rbxassetid://10734931402",
		["lucide-rectangle-horizontal"] = "rbxassetid://10734931777",
		["lucide-rectangle-vertical"] = "rbxassetid://10734932081",
		["lucide-recycle"] = "rbxassetid://10734932295",
		["lucide-redo"] = "rbxassetid://10734932822",
		["lucide-redo-2"] = "rbxassetid://10734932586",
		["lucide-refresh-ccw"] = "rbxassetid://10734933056",
		["lucide-refresh-cw"] = "rbxassetid://10734933222",
		["lucide-refrigerator"] = "rbxassetid://10734933465",
		["lucide-regex"] = "rbxassetid://10734933655",
		["lucide-repeat"] = "rbxassetid://10734933966",
		["lucide-repeat-1"] = "rbxassetid://10734933826",
		["lucide-reply"] = "rbxassetid://10734934252",
		["lucide-reply-all"] = "rbxassetid://10734934132",
		["lucide-rewind"] = "rbxassetid://10734934347",
		["lucide-rocket"] = "rbxassetid://10734934585",
		["lucide-rocking-chair"] = "rbxassetid://10734939942",
		["lucide-rotate-3d"] = "rbxassetid://10734940107",
		["lucide-rotate-ccw"] = "rbxassetid://10734940376",
		["lucide-rotate-cw"] = "rbxassetid://10734940654",
		["lucide-rss"] = "rbxassetid://10734940825",
		["lucide-ruler"] = "rbxassetid://10734941018",
		["lucide-russian-ruble"] = "rbxassetid://10734941199",
		["lucide-sailboat"] = "rbxassetid://10734941354",
		["lucide-save"] = "rbxassetid://10734941499",
		["lucide-scale"] = "rbxassetid://10734941912",
		["lucide-scale-3d"] = "rbxassetid://10734941739",
		["lucide-scaling"] = "rbxassetid://10734942072",
		["lucide-scan"] = "rbxassetid://10734942565",
		["lucide-scan-face"] = "rbxassetid://10734942198",
		["lucide-scan-line"] = "rbxassetid://10734942351",
		["lucide-scissors"] = "rbxassetid://10734942778",
		["lucide-screen-share"] = "rbxassetid://10734943193",
		["lucide-screen-share-off"] = "rbxassetid://10734942967",
		["lucide-scroll"] = "rbxassetid://10734943448",
		["lucide-search"] = "rbxassetid://10734943674",
		["lucide-send"] = "rbxassetid://10734943902",
		["lucide-separator-horizontal"] = "rbxassetid://10734944115",
		["lucide-separator-vertical"] = "rbxassetid://10734944326",
		["lucide-server"] = "rbxassetid://10734949856",
		["lucide-server-cog"] = "rbxassetid://10734944444",
		["lucide-server-crash"] = "rbxassetid://10734944554",
		["lucide-server-off"] = "rbxassetid://10734944668",
		["lucide-settings"] = "rbxassetid://10734950309",
		["lucide-settings-2"] = "rbxassetid://10734950020",
		["lucide-share"] = "rbxassetid://10734950813",
		["lucide-share-2"] = "rbxassetid://10734950553",
		["lucide-sheet"] = "rbxassetid://10734951038",
		["lucide-shield"] = "rbxassetid://10734951847",
		["lucide-shield-alert"] = "rbxassetid://10734951173",
		["lucide-shield-check"] = "rbxassetid://10734951367",
		["lucide-shield-close"] = "rbxassetid://10734951535",
		["lucide-shield-off"] = "rbxassetid://10734951684",
		["lucide-shirt"] = "rbxassetid://10734952036",
		["lucide-shopping-bag"] = "rbxassetid://10734952273",
		["lucide-shopping-cart"] = "rbxassetid://10734952479",
