local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer and LocalPlayer:WaitForChild("PlayerGui")

local Meavo = {}
Meavo.__index = Meavo

local Themes = {
	Dark = {
		Primary = Color3.fromRGB(99, 102, 241),
		OnPrimary = Color3.fromRGB(255, 255, 255),
		PrimaryContainer = Color3.fromRGB(55, 48, 90),
		OnPrimaryContainer = Color3.fromRGB(220, 215, 255),
		Secondary = Color3.fromRGB(100, 100, 120),
		Surface = Color3.fromRGB(28, 28, 36),
		OnSurface = Color3.fromRGB(240, 240, 245),
		SurfaceVariant = Color3.fromRGB(38, 38, 48),
		OnSurfaceVariant = Color3.fromRGB(170, 170, 185),
		Outline = Color3.fromRGB(55, 55, 70),
		Error = Color3.fromRGB(239, 68, 68),
		Background = Color3.fromRGB(18, 18, 24),
		Darker = Color3.fromRGB(12, 12, 16),
		Sidebar = Color3.fromRGB(22, 22, 30),
		Success = Color3.fromRGB(34, 197, 94),
		Warning = Color3.fromRGB(251, 146, 60),
		Card = Color3.fromRGB(32, 32, 42),
		Accent = Color3.fromRGB(99, 102, 241),
	},
	Midnight = {
		Primary = Color3.fromRGB(56, 189, 248),
		OnPrimary = Color3.fromRGB(10, 20, 30),
		PrimaryContainer = Color3.fromRGB(30, 50, 70),
		OnPrimaryContainer = Color3.fromRGB(180, 220, 255),
		Secondary = Color3.fromRGB(80, 100, 120),
		Surface = Color3.fromRGB(20, 24, 32),
		OnSurface = Color3.fromRGB(230, 235, 245),
		SurfaceVariant = Color3.fromRGB(30, 36, 48),
		OnSurfaceVariant = Color3.fromRGB(150, 165, 185),
		Outline = Color3.fromRGB(45, 55, 70),
		Error = Color3.fromRGB(248, 113, 113),
		Background = Color3.fromRGB(12, 14, 20),
		Darker = Color3.fromRGB(8, 10, 14),
		Sidebar = Color3.fromRGB(16, 18, 26),
		Success = Color3.fromRGB(52, 211, 153),
		Warning = Color3.fromRGB(251, 191, 36),
		Card = Color3.fromRGB(24, 28, 38),
		Accent = Color3.fromRGB(56, 189, 248),
	},
	Coffee = {
		Primary = Color3.fromRGB(72, 66, 58),
		OnPrimary = Color3.fromRGB(235, 228, 210),
		PrimaryContainer = Color3.fromRGB(210, 200, 180),
		OnPrimaryContainer = Color3.fromRGB(46, 42, 38),
		Secondary = Color3.fromRGB(90, 84, 76),
		Surface = Color3.fromRGB(232, 224, 208),
		OnSurface = Color3.fromRGB(46, 42, 38),
		SurfaceVariant = Color3.fromRGB(220, 212, 196),
		OnSurfaceVariant = Color3.fromRGB(90, 84, 76),
		Outline = Color3.fromRGB(78, 72, 64),
		Error = Color3.fromRGB(150, 50, 40),
		Background = Color3.fromRGB(232, 224, 208),
		Darker = Color3.fromRGB(48, 43, 38),
		Sidebar = Color3.fromRGB(220, 212, 196),
		Success = Color3.fromRGB(70, 110, 60),
		Warning = Color3.fromRGB(180, 120, 40),
		Card = Color3.fromRGB(240, 232, 216),
		Accent = Color3.fromRGB(120, 80, 50),
	},
	Nebula = {
		Primary = Color3.fromRGB(139, 92, 246),
		OnPrimary = Color3.fromRGB(255, 255, 255),
		PrimaryContainer = Color3.fromRGB(60, 40, 90),
		OnPrimaryContainer = Color3.fromRGB(230, 210, 255),
		Secondary = Color3.fromRGB(110, 100, 140),
		Surface = Color3.fromRGB(24, 22, 36),
		OnSurface = Color3.fromRGB(240, 238, 250),
		SurfaceVariant = Color3.fromRGB(36, 32, 52),
		OnSurfaceVariant = Color3.fromRGB(170, 160, 200),
		Outline = Color3.fromRGB(50, 45, 70),
		Error = Color3.fromRGB(244, 63, 94),
		Background = Color3.fromRGB(14, 12, 22),
		Darker = Color3.fromRGB(8, 6, 14),
		Sidebar = Color3.fromRGB(18, 16, 28),
		Success = Color3.fromRGB(52, 211, 153),
		Warning = Color3.fromRGB(251, 146, 60),
		Card = Color3.fromRGB(30, 26, 44),
		Accent = Color3.fromRGB(139, 92, 246),
	},
}

local DEFAULT_SOUNDS = {
	Hover = 408524543,
	Click = 4307186075,
	Notify = 644569388,
	Toggle = 6895079853,
	Volume = 0.32,
}

local DEFAULT_VISUAL = {
	WindowSize = UDim2.fromOffset(560, 380),
	HeaderHeight = 36,
	SidebarWidth = 140,
	IconSidebarWidth = 52,
	FooterHeight = 0,
	CornerRadius = 10,
	StrokeThickness = 1,
	Font = Enum.Font.Gotham,
	FontMedium = Enum.Font.GothamMedium,
	FontBold = Enum.Font.GothamBold,
	TextSize = 13,
	TitleSize = 14,
	TabHeight = 32,
	TabGap = 4,
	ElementGap = 8,
	BubbleEnabled = false,
	SidebarStyle = "List",
}

local TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
local TWEEN_FAST = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_SPRING = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_IN = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function deepCopy(t)
	if type(t) ~= "table" then return t end
	local n = {}
	for k, v in pairs(t) do n[k] = type(v) == "table" and deepCopy(v) or v end
	return n
end

local function merge(a, b)
	local r = deepCopy(a)
	if type(b) ~= "table" then return r end
	for k, v in pairs(b) do
		r[k] = (type(v) == "table" and type(r[k]) == "table") and merge(r[k], v) or v
	end
	return r
end

local function clamp(n, a, b) return math.max(a, math.min(b, n)) end
local function darken(c, a) return Color3.new(clamp(c.R*a,0,1), clamp(c.G*a,0,1), clamp(c.B*a,0,1)) end
local function lighten(c, a) return Color3.new(clamp(c.R+(1-c.R)*a,0,1), clamp(c.G+(1-c.G)*a,0,1), clamp(c.B+(1-c.B)*a,0,1)) end

local function resolveImage(id)
	if not id or id == 0 or id == "" then return nil end
	if type(id) == "number" then return "rbxassetid://" .. id end
	local s = tostring(id)
	if s:match("^rbxassetid://") or s:match("^http") or s:match("^rbxthumb://") then return s end
	if s:match("^%d+$") then return "rbxassetid://" .. s end
	return s
end

local function safeCall(fn, ...) if type(fn) == "function" then local ok, e = pcall(fn, ...) if not ok then warn("[Meavo]", e) end end end

local function playSound(id, vol)
	if not id or id == 0 then return end
	local s = Instance.new("Sound")
	s.SoundId = resolveImage(id) or ("rbxassetid://" .. tostring(id))
	s.Volume = vol or 0.32
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 3)
end

local function corner(o, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 8)
	c.Parent = o
	return c
end

local function stroke(o, col, th, tr)
	local s = Instance.new("UIStroke")
	s.Color = col or Color3.fromRGB(55, 55, 70)
	s.Thickness = th or 1
	s.Transparency = tr or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = o
	return s
end

local function pad(o, l, r, t, b)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, l or 0)
	p.PaddingRight = UDim.new(0, r or 0)
	p.PaddingTop = UDim.new(0, t or 0)
	p.PaddingBottom = UDim.new(0, b or 0)
	p.Parent = o
	return p
end

local function tween(o, info, props)
	local tw = TweenService:Create(o, info, props)
	tw:Play()
	return tw
end

local function applyImageBG(parent, cfg, z)
	if not cfg then return end
	local src = resolveImage(cfg.Image or cfg.Texture or cfg.AssetId or cfg.TextureId or cfg)
	if not src and type(cfg) ~= "table" then src = resolveImage(cfg) end
	if not src then return end
	local img = Instance.new("ImageLabel")
	img.Name = "MeavoBG"
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.ZIndex = z or 0
	img.ScaleType = (type(cfg) == "table" and cfg.ScaleType) or Enum.ScaleType.Crop
	img.ImageTransparency = (type(cfg) == "table" and cfg.Transparency) or 0
	img.ImageColor3 = (type(cfg) == "table" and cfg.Color) or Color3.new(1, 1, 1)
	img.Image = src
	img.Parent = parent
	return img
end

local Global = { Windows = {}, Capturing = nil }

local Component = {}
Component.__index = Component
function Component:SetVisible(v) if self._root then self._root.Visible = v end end
function Component:Destroy() if self._root then self._root:Destroy() self._root = nil end end
function Component:GetValue() return self.Value end

local Window, Tab, Section = {}, {}, {}
Window.__index = Window
Tab.__index = Tab
Section.__index = Section

function Meavo.new(config)
	config = config or {}
	local themeName = config.Theme or "Dark"
	local base = Themes[themeName] or Themes.Dark
	local theme = merge(base, config.Colors or config.ThemeColors)
	local sounds = merge(DEFAULT_SOUNDS, config.Sounds)
	local visual = merge(DEFAULT_VISUAL, config.Visual)
	if config.SidebarStyle then visual.SidebarStyle = config.SidebarStyle end

	if config.Parent then PlayerGui = config.Parent end
	assert(PlayerGui, "Meavo requires PlayerGui")

	local old = PlayerGui:FindFirstChild("Meavo")
	if old then old:Destroy() end

	local self = setmetatable({}, Window)
	self.Title = tostring(config.Title or "Meavo")
	self.ToggleKey = (typeof(config.Keybind) == "EnumItem" and config.Keybind) or Enum.KeyCode.RightShift
	self.Theme = theme
	self.Sounds = sounds
	self.Visual = visual
	self.Config = config
	self.Tabs = {}
	self._selected = nil
	self._connections = {}
	self._visible = true
	self._minimized = false
	self._closing = false
	self._interactive = true
	self._hasImages = false
	self._iconMode = visual.SidebarStyle == "Icons"

	local sg = Instance.new("ScreenGui")
	sg.Name = "Meavo"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.Parent = PlayerGui
	self._screen = sg

	local size = config.Size or visual.WindowSize
	local root = Instance.new("Frame")
	root.Name = "Window"
	root.Size = size
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.BackgroundColor3 = theme.Background
	root.BorderSizePixel = 0
	root.ClipsDescendants = true
	root.Parent = sg
	corner(root, visual.CornerRadius)
	stroke(root, theme.Outline, visual.StrokeThickness, 0.3)
	self._root = root
	self._homePos = root.Position
	self._homeSize = size

	if config.Background or config.BackgroundImage then
		applyImageBG(root, type(config.Background) == "table" and config.Background or { Image = config.Background or config.BackgroundImage }, 0)
		self._hasImages = true
		root.BackgroundTransparency = 0.25
	end

	local shield = Instance.new("Frame")
	shield.Name = "Shield"
	shield.Size = UDim2.fromScale(1, 1)
	shield.BackgroundTransparency = 1
	shield.Visible = false
	shield.ZIndex = 100
	shield.Parent = root
	self._shield = shield

	self:_buildHeader()
	self:_buildSidebar()
	self:_buildContent()

	if self._hasImages or config.ForceOutline then
		task.defer(function()
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("Frame") or d:IsA("TextButton") or d:IsA("ScrollingFrame") then
					if d.Name ~= "MeavoBG" and d.Name ~= "Shield" and not d:FindFirstChildOfClass("UIStroke") and not d:IsA("TextLabel") then
						stroke(d, theme.Outline, 1, 0.4)
					end
				end
			end
		end)
	end

	local dragging, dragStart, startPos = false
	self._header.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = i.Position
			startPos = root.Position
		end
	end)
	self._header.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
	end)
	table.insert(self._connections, UserInputService.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - dragStart
			root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end))
	table.insert(self._connections, UserInputService.InputBegan:Connect(function(i, gp)
		if gp or Global.Capturing then return end
		if i.UserInputType == Enum.UserInputType.Keyboard and i.KeyCode == self.ToggleKey then
			self:Toggle()
		end
	end))

	table.insert(Global.Windows, self)
	self:_intro()
	return self
end

Meavo.CreateWindow = Meavo.new

function Window:_buildHeader()
	local v, t = self.Visual, self.Theme
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, v.HeaderHeight)
	header.BackgroundColor3 = t.Surface
	header.BorderSizePixel = 0
	header.ZIndex = 20
	header.Parent = self._root
	self._header = header
	stroke(header, t.Outline, 1, 0.5)

	if self.Config.HeaderBackground or self.Config.HeaderImage then
		applyImageBG(header, type(self.Config.HeaderBackground) == "table" and self.Config.HeaderBackground or { Image = self.Config.HeaderBackground or self.Config.HeaderImage }, 0)
		self._hasImages = true
	end

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -90, 1, 0)
	title.Position = UDim2.fromOffset(14, 0)
	title.Text = self.Title
	title.TextColor3 = t.OnSurface
	title.Font = v.FontMedium
	title.TextSize = v.TitleSize
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 22
	title.Parent = header
	self._titleLabel = title

	local function topBtn(txt, col, x, cb)
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromOffset(26, 22)
		b.Position = UDim2.new(1, -x, 0.5, 0)
		b.AnchorPoint = Vector2.new(0, 0.5)
		b.BackgroundColor3 = col
		b.BorderSizePixel = 0
		b.Text = txt
		b.TextColor3 = t.OnPrimary
		b.Font = v.FontBold
		b.TextSize = 14
		b.AutoButtonColor = false
		b.ZIndex = 22
		b.Parent = header
		corner(b, 5)
		b.MouseEnter:Connect(function() tween(b, TWEEN_FAST, {BackgroundColor3 = darken(col, 0.8)}) playSound(self.Sounds.Hover, self.Sounds.Volume*0.5) end)
		b.MouseLeave:Connect(function() tween(b, TWEEN_FAST, {BackgroundColor3 = col}) end)
		b.MouseButton1Click:Connect(function() playSound(self.Sounds.Click, self.Sounds.Volume) cb() end)
		return b
	end
	topBtn("×", t.Error, 34, function() self:Close() end)
	topBtn("–", t.Secondary, 64, function() self:Minimize() end)
end

function Window:_buildSidebar()
	local v, t = self.Visual, self.Theme
	local w = self._iconMode and v.IconSidebarWidth or v.SidebarWidth
	local side = Instance.new("Frame")
	side.Name = "Sidebar"
	side.Size = UDim2.new(0, w, 1, -v.HeaderHeight)
	side.Position = UDim2.fromOffset(0, v.HeaderHeight)
	side.BackgroundColor3 = t.Sidebar
	side.BorderSizePixel = 0
	side.ZIndex = 10
	side.Parent = self._root
	self._sidebar = side
	stroke(side, t.Outline, 1, 0.6)

	if self.Config.SidebarBackground or self.Config.SidebarImage then
		applyImageBG(side, type(self.Config.SidebarBackground) == "table" and self.Config.SidebarBackground or { Image = self.Config.SidebarBackground or self.Config.SidebarImage }, 0)
		self._hasImages = true
	end

	local list = Instance.new("ScrollingFrame")
	list.Name = "TabList"
	list.Size = UDim2.fromScale(1, 1)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 2
	list.ScrollBarImageColor3 = t.Primary
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.ZIndex = 11
	list.Parent = side
	pad(list, self._iconMode and 6 or 8, 6, 10, 10)
	self._tabList = list

	local lay = Instance.new("UIListLayout")
	lay.Padding = UDim.new(0, v.TabGap)
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Parent = list
end

function Window:_buildContent()
	local v, t = self.Visual, self.Theme
	local sw = self._iconMode and v.IconSidebarWidth or v.SidebarWidth
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -sw, 1, -v.HeaderHeight)
	content.Position = UDim2.fromOffset(sw, v.HeaderHeight)
	content.BackgroundColor3 = t.Background
	content.BorderSizePixel = 0
	content.ClipsDescendants = true
	content.ZIndex = 5
	content.Parent = self._root
	self._content = content

	if self.Config.ContentBackground or self.Config.ContentImage then
		applyImageBG(content, type(self.Config.ContentBackground) == "table" and self.Config.ContentBackground or { Image = self.Config.ContentBackground or self.Config.ContentImage }, 0)
		self._hasImages = true
	end
end

function Window:_setInteractive(v)
	self._interactive = v
	self._shield.Visible = not v
end

function Window:_intro()
	local root = self._root
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(self._homeSize.X.Offset - 30, self._homeSize.Y.Offset - 20)
	root.Position = self._homePos + UDim2.fromOffset(0, 18)
	self:_setInteractive(false)
	tween(root, TWEEN_SPRING, { BackgroundTransparency = 0, Size = self._homeSize, Position = self._homePos })
	task.delay(0.35, function() if not self._closing then self:_setInteractive(true) end end)
end

function Window:_outro(destroy)
	if self._closing then return end
	self._closing = true
	self:_setInteractive(false)
	local root = self._root
	tween(root, TWEEN_IN, { Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1, Position = root.Position + UDim2.fromOffset(0, 16) })
	task.delay(0.22, function()
		if destroy then self:Destroy()
		else
			root.Visible = false
			root.Size = self._homeSize
			root.Position = self._homePos
			self._closing = false
		end
	end)
end

function Window:Toggle()
	if self._closing then return end
	self._visible = not self._visible
	if self._visible then self._root.Visible = true self:_intro()
	else self:_outro(false) end
end

function Window:Minimize()
	if self._closing then return end
	self._minimized = not self._minimized
	local v = self.Visual
	if self._minimized then
		tween(self._root, TWEEN, { Size = UDim2.fromOffset(self._root.AbsoluteSize.X, v.HeaderHeight) })
		self._sidebar.Visible = false
		self._content.Visible = false
	else
		self._sidebar.Visible = true
		self._content.Visible = true
		tween(self._root, TWEEN_SPRING, { Size = self._homeSize })
	end
end

function Window:Close() self:_outro(true) end

function Window:Destroy()
	for _, c in ipairs(self._connections) do pcall(function() c:Disconnect() end) end
	if self._screen then self._screen:Destroy() end
	for i, w in ipairs(Global.Windows) do if w == self then table.remove(Global.Windows, i) break end end
end

function Window:SetTitle(txt)
	self.Title = tostring(txt)
	if self._titleLabel then self._titleLabel.Text = self.Title end
end

function Window:Notify(msg, color, dur)
	msg = tostring(msg or "Notification")
	color = color or self.Theme.Primary
	dur = dur or 2.5
	playSound(self.Sounds.Notify, self.Sounds.Volume)
	local n = Instance.new("Frame")
	n.Size = UDim2.fromOffset(0, 38)
	n.Position = UDim2.new(0.5, 0, 0, 48)
	n.AnchorPoint = Vector2.new(0.5, 0)
	n.BackgroundColor3 = color
	n.BorderSizePixel = 0
	n.ZIndex = 120
	n.Parent = self._root
	corner(n, 8)
	stroke(n, self.Theme.Outline, 1, 0.3)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Text = msg
	l.TextColor3 = self.Theme.OnPrimary
	l.Font = self.Visual.FontMedium
	l.TextSize = 13
	l.ZIndex = 121
	l.Parent = n
	local w = clamp(#msg * 7.2 + 36, 150, 340)
	tween(n, TWEEN_SPRING, { Size = UDim2.fromOffset(w, 38) })
	task.delay(dur, function()
		if not n.Parent then return end
		tween(n, TWEEN, { Size = UDim2.fromOffset(0, 38), BackgroundTransparency = 1 })
		tween(l, TWEEN, { TextTransparency = 1 })
		task.delay(0.2, function() n:Destroy() end)
	end)
end

function Window:CreateTab(opts)
	opts = type(opts) == "string" and { Name = opts } or (opts or {})
	local name = tostring(opts.Name or opts.Text or "Tab")
	local icon = opts.Icon or ""
	local index = #self.Tabs + 1
	local t, v = self.Theme, self.Visual

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, self._iconMode and 40 or v.TabHeight)
	btn.BackgroundColor3 = t.Sidebar
	btn.BackgroundTransparency = 0
	btn.BorderSizePixel = 0
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.ZIndex = 12
	btn.LayoutOrder = index
	btn.Parent = self._tabList
	corner(btn, 8)

	local indicator = Instance.new("Frame")
	indicator.Name = "Ind"
	indicator.Size = UDim2.fromOffset(3, self._iconMode and 20 or 16)
	indicator.Position = UDim2.fromOffset(0, (btn.Size.Y.Offset - (self._iconMode and 20 or 16)) / 2)
	indicator.BackgroundColor3 = t.Primary
	indicator.BackgroundTransparency = index == 1 and 0 or 1
	indicator.BorderSizePixel = 0
	indicator.ZIndex = 13
	indicator.Parent = btn
	corner(indicator, 2)

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = self._iconMode and UDim2.fromScale(1, 1) or UDim2.new(1, -16, 1, 0)
	label.Position = self._iconMode and UDim2.fromScale(0, 0) or UDim2.fromOffset(12, 0)
	label.Text = self._iconMode and (icon ~= "" and icon or string.sub(name, 1, 1)) or name
	label.TextColor3 = index == 1 and t.OnSurface or t.OnSurfaceVariant
	label.Font = v.FontMedium
	label.TextSize = self._iconMode and 16 or v.TextSize
	label.TextXAlignment = self._iconMode and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left
	label.ZIndex = 13
	label.Parent = btn

	local overlay = Instance.new("Frame")
	overlay.Size = UDim2.fromScale(0, 1)
	overlay.BackgroundColor3 = t.Primary
	overlay.BackgroundTransparency = 0.85
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 12
	overlay.Parent = btn
	corner(overlay, 8)

	btn.MouseEnter:Connect(function()
		if self._selected ~= index then
			tween(overlay, TWEEN_FAST, { Size = UDim2.fromScale(1, 1) })
			playSound(self.Sounds.Hover, self.Sounds.Volume * 0.4)
		end
	end)
	btn.MouseLeave:Connect(function()
		if self._selected ~= index then tween(overlay, TWEEN_FAST, { Size = UDim2.fromScale(0, 1) }) end
	end)
	btn.MouseButton1Click:Connect(function()
		playSound(self.Sounds.Click, self.Sounds.Volume)
		self:SelectTab(index)
	end)

	local page = Instance.new("ScrollingFrame")
	page.Size = UDim2.fromScale(1, 1)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 3
	page.ScrollBarImageColor3 = t.Primary
	page.CanvasSize = UDim2.new(0, 0, 0, 0)
	page.Visible = false
	page.ZIndex = 6
	page.Parent = self._content
	pad(page, 14, 14, 12, 14)

	local pageLay = Instance.new("UIListLayout")
	pageLay.Padding = UDim.new(0, v.ElementGap)
	pageLay.SortOrder = Enum.SortOrder.LayoutOrder
	pageLay.Parent = page

	local tabData = {
		Index = index, Name = name, Button = btn, Indicator = indicator,
		Label = label, Overlay = overlay, Page = page, Sections = {}, Layout = pageLay,
	}
	self.Tabs[index] = tabData
	self._tabList.CanvasSize = UDim2.new(0, 0, 0, 12 + index * ((self._iconMode and 40 or v.TabHeight) + v.TabGap))

	if index == 1 then self:SelectTab(1) end
	return setmetatable({ _window = self, _data = tabData }, Tab)
end

function Window:SelectTab(index)
	self._selected = index
	local t = self.Theme
	for i, tab in pairs(self.Tabs) do
		local on = i == index
		tab.Page.Visible = on
		tab.Indicator.BackgroundTransparency = on and 0 or 1
		tab.Label.TextColor3 = on and t.OnSurface or t.OnSurfaceVariant
		tab.Button.BackgroundColor3 = on and t.SurfaceVariant or t.Sidebar
		tab.Overlay.Size = UDim2.fromScale(0, 1)
	end
end

function Tab:CreateSection(name)
	local win = self._window
	local page = self._data.Page
	local t, v = win.Theme, win.Visual

	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(1, 0, 0, 0)
	holder.AutomaticSize = Enum.AutomaticSize.Y
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.ZIndex = 7
	holder.Parent = page

	if name and name ~= "" then
		local header = Instance.new("TextLabel")
		header.BackgroundTransparency = 1
		header.Size = UDim2.new(1, 0, 0, 22)
		header.Text = tostring(name)
		header.TextColor3 = t.OnSurfaceVariant
		header.Font = v.FontMedium
		header.TextSize = 12
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.ZIndex = 8
		header.Parent = holder
	end

	local list = Instance.new("Frame")
	list.Name = "List"
	list.Size = UDim2.new(1, 0, 0, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(0, name and name ~= "" and 24 or 0)
	list.ZIndex = 7
	list.Parent = holder

	local lay = Instance.new("UIListLayout")
	lay.Padding = UDim.new(0, 6)
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Parent = list

	lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		local total = 0
		for _, c in ipairs(page:GetChildren()) do
			if c:IsA("GuiObject") and c.Visible then total = total + c.AbsoluteSize.Y + v.ElementGap end
		end
		page.CanvasSize = UDim2.new(0, 0, 0, total + 16)
	end)

	local sec = setmetatable({ _window = win, _tab = self, _list = list, Components = {} }, Section)
	table.insert(self._data.Sections, sec)
	return sec
end

function Section:_card(h)
	local t = self._window.Theme
	local root = Instance.new("Frame")
	root.Size = UDim2.new(1, 0, 0, h or 36)
	root.BackgroundColor3 = t.Card or t.SurfaceVariant
	root.BorderSizePixel = 0
	root.ZIndex = 8
	root.Parent = self._list
	corner(root, 8)
	stroke(root, t.Outline, 1, 0.55)
	return root
end

function Section:CreateButton(opts)
	opts = opts or {}
	local win = self._window
	local t = win.Theme
	local text = tostring(opts.Name or opts.Text or "Button")
	local col = opts.Color or t.Primary
	local cb = opts.Callback

	local root = Instance.new("TextButton")
	root.Size = UDim2.new(1, 0, 0, 34)
	root.BackgroundColor3 = col
	root.BorderSizePixel = 0
	root.Text = text
	root.TextColor3 = t.OnPrimary
	root.Font = win.Visual.FontMedium
	root.TextSize = 13
	root.AutoButtonColor = false
	root.ZIndex = 9
	root.Parent = self._list
	corner(root, 8)

	local ov = Instance.new("Frame")
	ov.Size = UDim2.fromScale(0, 1)
	ov.BackgroundColor3 = Color3.new(1, 1, 1)
	ov.BackgroundTransparency = 0.85
	ov.BorderSizePixel = 0
	ov.ZIndex = 10
	ov.Parent = root
	corner(ov, 8)

	root.MouseEnter:Connect(function() tween(ov, TWEEN_FAST, {Size = UDim2.fromScale(1,1)}) playSound(win.Sounds.Hover, win.Sounds.Volume*0.4) end)
	root.MouseLeave:Connect(function() tween(ov, TWEEN_FAST, {Size = UDim2.fromScale(0,1)}) end)
	root.MouseButton1Click:Connect(function()
		if not win._interactive then return end
		playSound(win.Sounds.Click, win.Sounds.Volume)
		safeCall(cb)
	end)

	local comp = setmetatable({ _root = root }, Component)
	table.insert(self.Components, comp)
	return comp
end

function Section:CreateToggle(opts)
	opts = opts or {}
	local win = self._window
	local t = win.Theme
	local text = tostring(opts.Name or opts.Text or "Toggle")
	local state = opts.Default == true
	local cb = opts.Callback

	local root = self:_card(36)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -56, 1, 0)
	label.Position = UDim2.fromOffset(12, 0)
	label.Text = text
	label.TextColor3 = t.OnSurface
	label.Font = win.Visual.Font
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 10
	label.Parent = root

	local track = Instance.new("Frame")
	track.Size = UDim2.fromOffset(40, 20)
	track.Position = UDim2.new(1, -50, 0.5, 0)
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.BackgroundColor3 = state and t.Primary or t.Outline
	track.BorderSizePixel = 0
	track.ZIndex = 10
	track.Parent = root
	corner(track, 10)

	local knob = Instance.new("Frame")
	knob.Size = UDim2.fromOffset(16, 16)
	knob.Position = state and UDim2.new(1, -18, 0.5, 0) or UDim2.fromOffset(2, 2)
	knob.AnchorPoint = state and Vector2.new(0, 0.5) or Vector2.new(0, 0)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BorderSizePixel = 0
	knob.ZIndex = 11
	knob.Parent = track
	corner(knob, 8)

	local hit = Instance.new("TextButton")
	hit.Size = UDim2.fromScale(1, 1)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.ZIndex = 12
	hit.Parent = root

	local function set(v, fire)
		state = not not v
		tween(track, TWEEN_FAST, { BackgroundColor3 = state and t.Primary or t.Outline })
		tween(knob, TWEEN_FAST, {
			Position = state and UDim2.new(1, -18, 0.5, 0) or UDim2.fromOffset(2, 2),
			AnchorPoint = state and Vector2.new(0, 0.5) or Vector2.new(0, 0)
		})
		if fire then playSound(win.Sounds.Toggle, win.Sounds.Volume) safeCall(cb, state) end
	end

	hit.MouseButton1Click:Connect(function() if win._interactive then set(not state, true) end end)

	local comp = setmetatable({ _root = root, Value = state }, Component)
	comp.SetValue = function(_, v) set(v, false) end
	comp.GetValue = function() return state end
	table.insert(self.Components, comp)
	return comp
end

function Section:CreateSlider(opts)
	opts = opts or {}
	local win = self._window
	local t = win.Theme
	local text = tostring(opts.Name or opts.Text or "Slider")
	local min, max = opts.Min or 0, opts.Max or 100
	local value = opts.Default or min
	local inc = opts.Increment or 1
	local cb = opts.Callback

	local root = self:_card(50)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -16, 0, 18)
	label.Position = UDim2.fromOffset(12, 4)
	label.Text = text .. ": " .. tostring(value)
	label.TextColor3 = t.OnSurface
	label.Font = win.Visual.Font
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 10
	label.Parent = root

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, -24, 0, 6)
	bar.Position = UDim2.fromOffset(12, 30)
	bar.BackgroundColor3 = t.Outline
	bar.BorderSizePixel = 0
	bar.ZIndex = 10
	bar.Parent = root
	corner(bar, 3)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(clamp((value - min) / math.max(max - min, 1), 0, 1), 0, 1, 0)
	fill.BackgroundColor3 = t.Primary
	fill.BorderSizePixel = 0
	fill.ZIndex = 11
	fill.Parent = bar
	corner(fill, 3)

	local dragging = false
	local function update(x)
		local rel = clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
		value = math.floor((min + (max - min) * rel) / inc + 0.5) * inc
		value = clamp(value, min, max)
		fill.Size = UDim2.new((value - min) / math.max(max - min, 1), 0, 1, 0)
		label.Text = text .. ": " .. tostring(value)
		safeCall(cb, value)
	end

	bar.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			update(i.Position.X)
			playSound(win.Sounds.Click, win.Sounds.Volume * 0.35)
		end
	end)
	bar.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
	end)
	table.insert(win._connections, UserInputService.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then update(i.Position.X) end
	end))

	local comp = setmetatable({ _root = root, Value = value }, Component)
	comp.SetValue = function(_, v)
		value = clamp(v, min, max)
		fill.Size = UDim2.new((value - min) / math.max(max - min, 1), 0, 1, 0)
		label.Text = text .. ": " .. tostring(value)
	end
	table.insert(self.Components, comp)
	return comp
end

function Section:CreateDropdown(opts)
	opts = opts or {}
	local win = self._window
	local t = win.Theme
	local options = opts.Options or { "Option A", "Option B", "Option C" }
	local current = opts.Default or options[1]
	local cb = opts.Callback
	local text = tostring(opts.Name or opts.Text or "")

	local root = Instance.new("TextButton")
	root.Size = UDim2.new(1, 0, 0, 34)
	root.BackgroundColor3 = t.Card or t.SurfaceVariant
	root.BorderSizePixel = 0
	root.Text = (text ~= "" and (text .. ": ") or "") .. tostring(current) .. "  ▾"
	root.TextColor3 = t.OnSurface
	root.Font = win.Visual.Font
	root.TextSize = 13
	root.AutoButtonColor = false
	root.ZIndex = 9
	root.Parent = self._list
	corner(root, 8)
	stroke(root, t.Outline, 1, 0.5)

	local menu = Instance.new("Frame")
	menu.Size = UDim2.new(1, 0, 0, 0)
	menu.BackgroundColor3 = t.Surface
	menu.BorderSizePixel = 0
	menu.ClipsDescendants = true
	menu.Visible = false
	menu.ZIndex = 30
	menu.Parent = self._list
	corner(menu, 8)
	stroke(menu, t.Outline, 1)

	local open = false
	for i, opt in ipairs(options) do
		local o = Instance.new("TextButton")
		o.Size = UDim2.new(1, 0, 0, 28)
		o.Position = UDim2.fromOffset(0, (i - 1) * 28)
		o.BackgroundColor3 = t.Surface
		o.BorderSizePixel = 0
		o.Text = tostring(opt)
		o.TextColor3 = t.OnSurface
		o.Font = win.Visual.Font
		o.TextSize = 12
		o.AutoButtonColor = false
		o.ZIndex = 31
		o.Parent = menu
		o.MouseEnter:Connect(function() tween(o, TWEEN_FAST, { BackgroundColor3 = t.PrimaryContainer }) end)
		o.MouseLeave:Connect(function() tween(o, TWEEN_FAST, { BackgroundColor3 = t.Surface }) end)
		o.MouseButton1Click:Connect(function()
			current = opt
			root.Text = (text ~= "" and (text .. ": ") or "") .. tostring(opt) .. "  ▾"
			tween(menu, TWEEN, { Size = UDim2.new(1, 0, 0, 0) })
			task.delay(0.18, function() menu.Visible = false end)
			open = false
			playSound(win.Sounds.Click, win.Sounds.Volume)
			safeCall(cb, opt)
		end)
	end

	root.MouseEnter:Connect(function() tween(root, TWEEN_FAST, { BackgroundColor3 = darken(t.Card or t.SurfaceVariant, 0.92) }) playSound(win.Sounds.Hover, win.Sounds.Volume*0.35) end)
	root.MouseLeave:Connect(function() tween(root, TWEEN_FAST, { BackgroundColor3 = t.Card or t.SurfaceVariant }) end)
	root.MouseButton1Click:Connect(function()
		if not win._interactive then return end
		if open then
			tween(menu, TWEEN, { Size = UDim2.new(1, 0, 0, 0) })
			task.delay(0.18, function() menu.Visible = false end)
			open = false
		else
			menu.Visible = true
			tween(menu, TWEEN_SPRING, { Size = UDim2.new(1, 0, 0, #options * 28) })
			open = true
		end
	end)

	local comp = setmetatable({ _root = root, Value = current }, Component)
	comp.SetValue = function(_, v) current = v root.Text = (text ~= "" and (text .. ": ") or "") .. tostring(v) .. "  ▾" end
	table.insert(self.Components, comp)
	return comp
end

function Section:CreateLabel(opts)
	opts = opts or {}
	local win = self._window
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, opts.TextSize and opts.TextSize + 8 or 22)
	label.Text = tostring(opts.Text or opts.Name or "")
	label.TextColor3 = opts.Color or win.Theme.OnSurface
	label.Font = opts.Bold and win.Visual.FontMedium or win.Visual.Font
	label.TextSize = opts.TextSize or 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.ZIndex = 9
	label.Parent = self._list
	local comp = setmetatable({ _root = label, Value = label.Text }, Component)
	comp.SetValue = function(_, v) label.Text = tostring(v) end
	table.insert(self.Components, comp)
	return comp
end

function Section:CreateParagraph(opts)
	opts = opts or {}
	local win = self._window
	local t = win.Theme
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = t.Card or t.SurfaceVariant
	card.BorderSizePixel = 0
	card.ZIndex = 8
	card.Parent = self._list
	corner(card, 8)
	stroke(card, t.Outline, 1, 0.5)
	pad(card, 12, 12, 10, 10)
	local para = Instance.new("TextLabel")
	para.BackgroundTransparency = 1
	para.Size = UDim2.new(1, 0, 0, 0)
	para.AutomaticSize = Enum.AutomaticSize.Y
	para.Text = tostring(opts.Text or "")
	para.TextColor3 = t.OnSurfaceVariant
	para.Font = win.Visual.Font
	para.TextSize = 12
	para.TextWrapped = true
	para.TextXAlignment = Enum.TextXAlignment.Left
	para.TextYAlignment = Enum.TextYAlignment.Top
	para.ZIndex = 9
	para.Parent = card
	local comp = setmetatable({ _root = card }, Component)
	table.insert(self.Components, comp)
	return comp
end

function Section:CreateKeybind(opts)
	opts = opts or {}
	local win = self._window
	local t = win.Theme
	local text = tostring(opts.Name or opts.Text or "Keybind")
	local value = (typeof(opts.Default) == "EnumItem" and opts.Default) or Enum.KeyCode.E
	local cb = opts.Callback
	local capturing = false

	local root = self:_card(34)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -100, 1, 0)
	label.Position = UDim2.fromOffset(12, 0)
	label.Text = text
	label.TextColor3 = t.OnSurface
	label.Font = win.Visual.Font
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 10
	label.Parent = root

	local keyLbl = Instance.new("TextLabel")
	keyLbl.BackgroundTransparency = 1
	keyLbl.Size = UDim2.new(0, 88, 1, 0)
	keyLbl.Position = UDim2.new(1, -96, 0, 0)
	keyLbl.Text = value.Name
	keyLbl.TextColor3 = t.OnSurfaceVariant
	keyLbl.Font = win.Visual.FontMedium
	keyLbl.TextSize = 12
	keyLbl.TextXAlignment = Enum.TextXAlignment.Right
	keyLbl.ZIndex = 10
	keyLbl.Parent = root

	local hit = Instance.new("TextButton")
	hit.Size = UDim2.fromScale(1, 1)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.ZIndex = 11
	hit.Parent = root

	local function setCapture(v)
		capturing = v
		keyLbl.Text = v and "..." or value.Name
		if v then Global.Capturing = comp elseif Global.Capturing == comp then Global.Capturing = nil end
	end
	local function setKey(kc, fire)
		value = kc
		setCapture(false)
		keyLbl.Text = kc.Name
		if fire then safeCall(cb, kc) end
	end

	local comp = setmetatable({ _root = root, Value = value }, Component)
	hit.MouseButton1Click:Connect(function()
		if not win._interactive then return end
		if Global.Capturing and Global.Capturing ~= comp and Global.Capturing._setCapture then Global.Capturing._setCapture(false) end
		setCapture(true)
	end)
	local conn = UserInputService.InputBegan:Connect(function(i, gp)
		if gp or i.UserInputType ~= Enum.UserInputType.Keyboard then return end
		if capturing and Global.Capturing == comp then
			if i.KeyCode == Enum.KeyCode.Escape then setCapture(false) return end
			if i.KeyCode ~= Enum.KeyCode.Unknown then setKey(i.KeyCode, true) end
			return
		end
		if i.KeyCode == value and i.KeyCode ~= win.ToggleKey then safeCall(cb) end
	end)
	table.insert(win._connections, conn)
	comp._setCapture = setCapture
	comp.SetValue = function(_, v) if typeof(v) == "EnumItem" then setKey(v, false) end end
	table.insert(self.Components, comp)
	return comp
end

function Section:CreateColorPicker(opts)
	opts = opts or {}
	local win = self._window
	local t = win.Theme
	local text = tostring(opts.Name or opts.Text or "Color")
	local value = opts.Default or t.Primary
	local cb = opts.Callback
	local open = false

	local root = self:_card(34)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -52, 1, 0)
	label.Position = UDim2.fromOffset(12, 0)
	label.Text = text
	label.TextColor3 = t.OnSurface
	label.Font = win.Visual.Font
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 10
	label.Parent = root

	local swatch = Instance.new("TextButton")
	swatch.Size = UDim2.fromOffset(36, 18)
	swatch.Position = UDim2.new(1, -46, 0.5, 0)
	swatch.AnchorPoint = Vector2.new(0, 0.5)
	swatch.BackgroundColor3 = value
	swatch.BorderSizePixel = 0
	swatch.Text = ""
	swatch.AutoButtonColor = false
	swatch.ZIndex = 10
	swatch.Parent = root
	corner(swatch, 4)
	stroke(swatch, t.Outline, 1)

	local body = Instance.new("Frame")
	body.Size = UDim2.new(1, 0, 0, 0)
	body.BackgroundColor3 = t.Surface
	body.BorderSizePixel = 0
	body.ClipsDescendants = true
	body.Visible = false
	body.ZIndex = 25
	body.Parent = self._list
	corner(body, 8)
	stroke(body, t.Outline, 1)
	pad(body, 8, 8, 8, 8)

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(26, 26)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.Parent = body

	local presets = {
		t.Primary, t.Accent or t.Primary, t.Success, t.Warning, t.Error,
		Color3.fromRGB(56, 189, 248), Color3.fromRGB(244, 114, 182), Color3.fromRGB(250, 204, 21),
	}
	local function setColor(c, fire)
		value = c
		swatch.BackgroundColor3 = c
		if fire then playSound(win.Sounds.Click, win.Sounds.Volume * 0.4) safeCall(cb, c) end
	end
	for _, c in ipairs(presets) do
		local p = Instance.new("TextButton")
		p.BackgroundColor3 = c
		p.BorderSizePixel = 0
		p.Text = ""
		p.AutoButtonColor = false
		p.ZIndex = 26
		p.Parent = body
		corner(p, 4)
		p.MouseButton1Click:Connect(function() setColor(c, true) end)
	end

	swatch.MouseButton1Click:Connect(function()
		if not win._interactive then return end
		open = not open
		if open then
			body.Visible = true
			tween(body, TWEEN_SPRING, { Size = UDim2.new(1, 0, 0, 80) })
		else
			tween(body, TWEEN, { Size = UDim2.new(1, 0, 0, 0) })
			task.delay(0.18, function() body.Visible = false end)
		end
	end)

	local comp = setmetatable({ _root = root, Value = value }, Component)
	comp.SetValue = function(_, v) if typeof(v) == "Color3" then setColor(v, false) end end
	table.insert(self.Components, comp)
	return comp
end

function Section:CreateInput(opts)
	opts = opts or {}
	local win = self._window
	local t = win.Theme
	local placeholder = tostring(opts.Placeholder or opts.Name or "Input")
	local default = tostring(opts.Default or "")
	local cb = opts.Callback

	local root = self:_card(36)
	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, -16, 1, -8)
	box.Position = UDim2.fromOffset(8, 4)
	box.BackgroundTransparency = 1
	box.Text = default
	box.PlaceholderText = placeholder
	box.TextColor3 = t.OnSurface
	box.PlaceholderColor3 = t.OnSurfaceVariant
	box.Font = win.Visual.Font
	box.TextSize = 13
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.ClearTextOnFocus = false
	box.ZIndex = 10
	box.Parent = root
	box.FocusLost:Connect(function(enter)
		if enter then playSound(win.Sounds.Click, win.Sounds.Volume * 0.35) safeCall(cb, box.Text) end
	end)

	local comp = setmetatable({ _root = root, Value = default }, Component)
	comp.SetValue = function(_, v) box.Text = tostring(v) end
	comp.GetValue = function() return box.Text end
	table.insert(self.Components, comp)
	return comp
end

function Section:CreateDivider()
	local t = self._window.Theme
	local d = Instance.new("Frame")
	d.Size = UDim2.new(1, 0, 0, 1)
	d.BackgroundColor3 = t.Outline
	d.BackgroundTransparency = 0.5
	d.BorderSizePixel = 0
	d.ZIndex = 8
	d.Parent = self._list
	return d
end

return setmetatable({
	new = Meavo.new,
	CreateWindow = Meavo.new,
	Themes = Themes,
}, { __call = function(_, cfg) return Meavo.new(cfg) end })
