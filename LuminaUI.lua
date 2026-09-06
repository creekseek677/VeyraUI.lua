--[[
    LuminaUI - Independent Roblox UI Library
    Clean, polished, fully functional from scratch.
    Custom tween system, theme support, mobile-ready.
]]

local LuminaUI = {}
LuminaUI.__index = LuminaUI

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") or (LocalPlayer and LocalPlayer:WaitForChild("PlayerGui", 5))

-- ============================================================
-- HUB / EXECUTOR HELPERS
-- ============================================================

local function protectGui(gui)
    if not gui then return end
    pcall(function()
        if syn and syn.protect_gui then
            syn.protect_gui(gui)
        elseif protect_gui then
            protect_gui(gui)
        end
    end)
end

local function getGuiParent()
    local parent
    pcall(function()
        if gethui then
            parent = gethui()
        end
    end)
    if parent then return parent end

    local ok = pcall(function()
        parent = CoreGui
        local test = Instance.new("Folder")
        test.Parent = CoreGui
        test:Destroy()
    end)
    if ok and parent then return parent end

    if PlayerGui then return PlayerGui end
    if LocalPlayer then
        PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
        return PlayerGui
    end
    return nil
end

local function parentGui(gui)
    if not gui then return end
    protectGui(gui)
    local parent = getGuiParent()
    if parent then
        gui.Parent = parent
    else
        warn("[LuminaUI] No valid GUI parent found")
    end
end

-- ============================================================
-- CUSTOM TWEEN SYSTEM
-- ============================================================

local Tween = {}
Tween.__index = Tween

local activeTweens = {}
local tweenConnection = nil

local function startTweenLoop()
    if tweenConnection then return end
    tweenConnection = RunService.RenderStepped:Connect(function(dt)
        local now = os.clock()
        local toRemove = {}
        for i, t in ipairs(activeTweens) do
            if t.Cancelled then
                table.insert(toRemove, i)
            else
                local elapsed = now - t.StartTime
                local alpha = math.clamp(elapsed / t.Duration, 0, 1)
                local eased = t.EasingFunc(alpha)
                for prop, data in pairs(t.Properties) do
                    local current
                    if typeof(data.Start) == "number" then
                        current = data.Start + (data.Goal - data.Start) * eased
                    elseif typeof(data.Start) == "Color3" then
                        current = Color3.new(
                            data.Start.R + (data.Goal.R - data.Start.R) * eased,
                            data.Start.G + (data.Goal.G - data.Start.G) * eased,
                            data.Start.B + (data.Goal.B - data.Start.B) * eased
                        )
                    elseif typeof(data.Start) == "UDim2" then
                        current = UDim2.new(
                            data.Start.X.Scale + (data.Goal.X.Scale - data.Start.X.Scale) * eased,
                            data.Start.X.Offset + (data.Goal.X.Offset - data.Start.X.Offset) * eased,
                            data.Start.Y.Scale + (data.Goal.Y.Scale - data.Start.Y.Scale) * eased,
                            data.Start.Y.Offset + (data.Goal.Y.Offset - data.Start.Y.Offset) * eased
                        )
                    elseif typeof(data.Start) == "Vector2" then
                        current = Vector2.new(
                            data.Start.X + (data.Goal.X - data.Start.X) * eased,
                            data.Start.Y + (data.Goal.Y - data.Start.Y) * eased
                        )
                    elseif typeof(data.Start) == "UDim" then
                        current = UDim.new(
                            data.Start.Scale + (data.Goal.Scale - data.Start.Scale) * eased,
                            data.Start.Offset + (data.Goal.Offset - data.Start.Offset) * eased
                        )
                    end
                    if current ~= nil then
                        pcall(function() t.Instance[prop] = current end)
                    end
                end
                if alpha >= 1 then
                    if t.OnComplete then
                        pcall(t.OnComplete)
                    end
                    table.insert(toRemove, i)
                end
            end
        end
        for i = #toRemove, 1, -1 do
            table.remove(activeTweens, toRemove[i])
        end
        if #activeTweens == 0 and tweenConnection then
            tweenConnection:Disconnect()
            tweenConnection = nil
        end
    end)
end

local EasingStyles = {
    Linear = function(t) return t end,
    QuadIn = function(t) return t * t end,
    QuadOut = function(t) return t * (2 - t) end,
    QuadInOut = function(t)
        if t < 0.5 then return 2 * t * t end
        return -1 + (4 - 2 * t) * t
    end,
    CubicOut = function(t)
        local t1 = t - 1
        return t1 * t1 * t1 + 1
    end,
    BackOut = function(t)
        local c1 = 1.70158
        local c3 = c1 + 1
        return 1 + c3 * (t - 1)^3 + c1 * (t - 1)^2
    end,
    ExpoOut = function(t)
        if t == 1 then return 1 end
        return 1 - 2^(-10 * t)
    end
}

function Tween.new(instance, duration, properties, easingName, onComplete)
    local self = setmetatable({}, Tween)
    self.Instance = instance
    self.Duration = math.max(duration or 0.2, 0.001)
    self.Properties = {}
    self.EasingFunc = EasingStyles[easingName or "QuadOut"] or EasingStyles.QuadOut
    self.OnComplete = onComplete
    self.StartTime = os.clock()
    self.Cancelled = false

    for prop, goal in pairs(properties) do
        local ok, startVal = pcall(function() return instance[prop] end)
        if ok and startVal ~= nil then
            self.Properties[prop] = { Start = startVal, Goal = goal }
        end
    end

    table.insert(activeTweens, self)
    startTweenLoop()
    return self
end

function Tween:Cancel()
    self.Cancelled = true
end

function Tween:Destroy()
    self:Cancel()
end

local function tween(instance, duration, props, style, callback)
    return Tween.new(instance, duration, props, style, callback)
end

-- ============================================================
-- UTILITY
-- ============================================================

local function create(className, props)
    local obj = Instance.new(className)
    for k, v in pairs(props or {}) do
        if k ~= "Parent" then
            pcall(function() obj[k] = v end)
        end
    end
    if props and props.Parent then
        obj.Parent = props.Parent
    end
    return obj
end

local function round(n, places)
    local m = 10 ^ (places or 0)
    return math.floor(n * m + 0.5) / m
end

local function clamp(n, min, max)
    return math.max(min, math.min(max, n))
end

local function isTouchDevice()
    return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function safeCallback(fn, ...)
    if type(fn) == "function" then
        local ok, err = pcall(fn, ...)
        if not ok then
            warn("[LuminaUI] Callback error:", err)
        end
    end
end

local function disconnectAll(connections)
    if not connections then return end
    for _, conn in pairs(connections) do
        if typeof(conn) == "RBXScriptConnection" then
            conn:Disconnect()
        end
    end
    table.clear(connections)
end

-- ============================================================
-- THEME
-- ============================================================

local DefaultThemes = {
    DarkTheme = {
        Background = Color3.fromRGB(22, 22, 28),
        Secondary = Color3.fromRGB(30, 30, 38),
        Tertiary = Color3.fromRGB(38, 38, 48),
        Accent = Color3.fromRGB(120, 90, 255),
        AccentHover = Color3.fromRGB(140, 110, 255),
        Text = Color3.fromRGB(240, 240, 245),
        MutedText = Color3.fromRGB(160, 160, 175),
        Border = Color3.fromRGB(50, 50, 62),
        Success = Color3.fromRGB(80, 200, 120),
        Danger = Color3.fromRGB(230, 70, 70),
        ToggleOn = Color3.fromRGB(120, 90, 255),
        ToggleOff = Color3.fromRGB(55, 55, 68),
        SliderTrack = Color3.fromRGB(45, 45, 58),
        DropdownBg = Color3.fromRGB(28, 28, 36),
        Shadow = Color3.fromRGB(0, 0, 0),
    },
    CrimsonTheme = {
        Background = Color3.fromRGB(10, 10, 12),
        Secondary = Color3.fromRGB(16, 16, 18),
        Tertiary = Color3.fromRGB(24, 24, 28),
        Accent = Color3.fromRGB(220, 40, 40),
        AccentHover = Color3.fromRGB(255, 60, 60),
        Text = Color3.fromRGB(245, 245, 245),
        MutedText = Color3.fromRGB(160, 150, 150),
        Border = Color3.fromRGB(180, 30, 30),
        Success = Color3.fromRGB(60, 180, 90),
        Danger = Color3.fromRGB(255, 50, 50),
        ToggleOn = Color3.fromRGB(220, 40, 40),
        ToggleOff = Color3.fromRGB(40, 35, 35),
        SliderTrack = Color3.fromRGB(35, 30, 30),
        DropdownBg = Color3.fromRGB(14, 14, 16),
        Shadow = Color3.fromRGB(0, 0, 0),
    },
    LightTheme = {
        Background = Color3.fromRGB(245, 245, 250),
        Secondary = Color3.fromRGB(255, 255, 255),
        Tertiary = Color3.fromRGB(235, 235, 242),
        Accent = Color3.fromRGB(90, 100, 255),
        AccentHover = Color3.fromRGB(110, 120, 255),
        Text = Color3.fromRGB(25, 25, 35),
        MutedText = Color3.fromRGB(110, 110, 130),
        Border = Color3.fromRGB(210, 210, 220),
        Success = Color3.fromRGB(50, 170, 100),
        Danger = Color3.fromRGB(220, 60, 60),
        ToggleOn = Color3.fromRGB(90, 100, 255),
        ToggleOff = Color3.fromRGB(200, 200, 210),
        SliderTrack = Color3.fromRGB(220, 220, 230),
        DropdownBg = Color3.fromRGB(250, 250, 255),
        Shadow = Color3.fromRGB(0, 0, 0),
    }
}

local CurrentTheme = table.clone(DefaultThemes.DarkTheme)

-- ============================================================
-- LIBRARY STATE
-- ============================================================

local LibraryState = {
    Initialized = false,
    Windows = {},
    Notifications = {},
    NotificationContainer = nil,
    Keybinds = {},
    InputConnections = {},
    GlobalConnections = {},
    Destroyed = false,
    SearchQuery = "",
}

-- ============================================================
-- ANIMATION HELPERS
-- ============================================================

local function fadeIn(obj, duration)
    if not obj or not obj.Parent then return end
    local startTrans = obj.BackgroundTransparency or 1
    obj.BackgroundTransparency = 1
    tween(obj, duration or 0.25, { BackgroundTransparency = startTrans }, "QuadOut")
end

local function scaleIn(obj, duration)
    if not obj or not obj.Parent then return end
    local target = obj.Size
    obj.Size = UDim2.new(target.X.Scale * 0.9, target.X.Offset * 0.9, target.Y.Scale * 0.9, target.Y.Offset * 0.9)
    tween(obj, duration or 0.3, { Size = target }, "BackOut")
end

-- ============================================================
-- NOTIFICATION SYSTEM
-- ============================================================

local function ensureNotificationContainer()
    if LibraryState.NotificationContainer and LibraryState.NotificationContainer.Parent then
        return LibraryState.NotificationContainer
    end
    local screen = create("ScreenGui", {
        Name = "LuminaNotifications",
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 100
    })
    parentGui(screen)
    local container = create("Frame", {
        Name = "Container",
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 320, 1, 0),
        Position = UDim2.new(1, -340, 0, 20),
        Parent = screen
    })
    create("UIListLayout", {
        Padding = UDim.new(0, 10),
        SortOrder = Enum.SortOrder.LayoutOrder,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Top,
        Parent = container
    })
    LibraryState.NotificationContainer = container
    return container
end

function LuminaUI:Notify(title, message, duration)
    if LibraryState.Destroyed then return end
    duration = duration or 3
    title = tostring(title or "Notification")
    message = tostring(message or "")

    local container = ensureNotificationContainer()
    local notif = create("Frame", {
        Name = "Notification",
        BackgroundColor3 = CurrentTheme.Secondary,
        Size = UDim2.new(1, 0, 0, 0),
        ClipsDescendants = true,
        Parent = container
    })
    create("UICorner", { CornerRadius = UDim.new(0, 10), Parent = notif })
    create("UIStroke", {
        Color = CurrentTheme.Border,
        Thickness = 1,
        Transparency = 0.4,
        Parent = notif
    })

    local accentBar = create("Frame", {
        BackgroundColor3 = CurrentTheme.Accent,
        Size = UDim2.new(0, 4, 1, 0),
        BorderSizePixel = 0,
        Parent = notif
    })
    create("UICorner", { CornerRadius = UDim.new(0, 4), Parent = accentBar })

    local titleLabel = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -50, 0, 22),
        Position = UDim2.new(0, 16, 0, 10),
        Font = Enum.Font.GothamBold,
        Text = title,
        TextColor3 = CurrentTheme.Text,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = notif
    })

    local msgLabel = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -24, 0, 0),
        Position = UDim2.new(0, 16, 0, 32),
        Font = Enum.Font.Gotham,
        Text = message,
        TextColor3 = CurrentTheme.MutedText,
        TextSize = 13,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Parent = notif
    })

    local textBounds = msgLabel.TextBounds
    local height = math.max(60, 42 + textBounds.Y)
    msgLabel.Size = UDim2.new(1, -24, 0, textBounds.Y + 4)
    notif.Size = UDim2.new(1, 0, 0, height)

    notif.Position = UDim2.new(1, 40, 0, 0)
    notif.BackgroundTransparency = 1
    titleLabel.TextTransparency = 1
    msgLabel.TextTransparency = 1
    accentBar.BackgroundTransparency = 1

    tween(notif, 0.35, {
        Position = UDim2.new(0, 0, 0, 0),
        BackgroundTransparency = 0
    }, "ExpoOut")
    tween(titleLabel, 0.3, { TextTransparency = 0 }, "QuadOut")
    tween(msgLabel, 0.35, { TextTransparency = 0 }, "QuadOut")
    tween(accentBar, 0.3, { BackgroundTransparency = 0 }, "QuadOut")

    table.insert(LibraryState.Notifications, notif)

    task.delay(duration, function()
        if not notif or not notif.Parent then return end
        tween(notif, 0.3, {
            Position = UDim2.new(1, 40, 0, 0),
            BackgroundTransparency = 1
        }, "QuadIn", function()
            if notif and notif.Parent then
                notif:Destroy()
            end
            for i, n in ipairs(LibraryState.Notifications) do
                if n == notif then
                    table.remove(LibraryState.Notifications, i)
                    break
                end
            end
        end)
        tween(titleLabel, 0.25, { TextTransparency = 1 }, "QuadIn")
        tween(msgLabel, 0.25, { TextTransparency = 1 }, "QuadIn")
        tween(accentBar, 0.25, { BackgroundTransparency = 1 }, "QuadIn")
    end)
end

-- ============================================================
-- TOOLTIP
-- ============================================================

local activeTooltip = nil

local function showTooltip(text, anchor)
    if activeTooltip then
        activeTooltip:Destroy()
        activeTooltip = nil
    end
    if not text or text == "" then return end

    local parent = getGuiParent()
    local screen = parent and parent:FindFirstChild("LuminaTooltip")
    if not screen then
        screen = create("ScreenGui", {
            Name = "LuminaTooltip",
            ResetOnSpawn = false,
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
            DisplayOrder = 50
        })
        parentGui(screen)
    end

    local tip = create("Frame", {
        BackgroundColor3 = CurrentTheme.Tertiary,
        Size = UDim2.new(0, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.XY,
        Parent = screen
    })
    create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = tip })
    create("UIPadding", {
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
        PaddingTop = UDim.new(0, 6),
        PaddingBottom = UDim.new(0, 6),
        Parent = tip
    })
    create("UIStroke", {
        Color = CurrentTheme.Border,
        Thickness = 1,
        Transparency = 0.3,
        Parent = tip
    })

    local label = create("TextLabel", {
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.XY,
        Font = Enum.Font.Gotham,
        Text = text,
        TextColor3 = CurrentTheme.Text,
        TextSize = 12,
        TextWrapped = true,
        Parent = tip
    })

    local absPos = anchor.AbsolutePosition
    local absSize = anchor.AbsoluteSize
    local tipSize = tip.AbsoluteSize
    local x = absPos.X + absSize.X / 2 - tipSize.X / 2
    local y = absPos.Y - tipSize.Y - 8
    if y < 10 then
        y = absPos.Y + absSize.Y + 8
    end
    x = clamp(x, 10, workspace.ViewportSize.X - tipSize.X - 10)

    tip.Position = UDim2.fromOffset(x, y)
    tip.BackgroundTransparency = 1
    label.TextTransparency = 1
    tween(tip, 0.15, { BackgroundTransparency = 0 }, "QuadOut")
    tween(label, 0.15, { TextTransparency = 0 }, "QuadOut")

    activeTooltip = tip
end

local function hideTooltip()
    if activeTooltip then
        local tip = activeTooltip
        activeTooltip = nil
        tween(tip, 0.12, { BackgroundTransparency = 1 }, "QuadIn", function()
            if tip and tip.Parent then tip:Destroy() end
        end)
    end
end

-- ============================================================
-- COMPONENT BASE
-- ============================================================

local Component = {}
Component.__index = Component

function Component.new(section, name)
    local self = setmetatable({}, Component)
    self.Section = section
    self.Name = name or ""
    self.Connections = {}
    self.Destroyed = false
    self.Frame = nil
    self.Visible = true
    return self
end

function Component:Destroy()
    if self.Destroyed then return end
    self.Destroyed = true
    disconnectAll(self.Connections)
    if self.Frame and self.Frame.Parent then
        self.Frame:Destroy()
    end
    self.Frame = nil
end

function Component:SetVisible(vis)
    self.Visible = vis
    if self.Frame then
        self.Frame.Visible = vis
    end
end

-- ============================================================
-- BUTTON
-- ============================================================

local Button = setmetatable({}, { __index = Component })
Button.__index = Button

function Button.new(section, text, description, callback)
    local self = Component.new(section, text)
    setmetatable(self, Button)
    self.Callback = callback
    self.Description = description or ""

    local frame = create("Frame", {
        Name = "Button_" .. text,
        BackgroundColor3 = CurrentTheme.Tertiary,
        Size = UDim2.new(1, 0, 0, 40),
        Parent = section.Content
    })
    create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = frame })
    create("UIStroke", {
        Color = CurrentTheme.Border,
        Thickness = 1,
        Transparency = 0.5,
        Parent = frame
    })

    local btn = create("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Font = Enum.Font.GothamMedium,
        Text = text,
        TextColor3 = CurrentTheme.Text,
        TextSize = 14,
        AutoButtonColor = false,
        Parent = frame
    })

    self.Frame = frame
    self.Button = btn

    local function onHover(enter)
        if self.Destroyed then return end
        tween(frame, 0.15, {
            BackgroundColor3 = enter and CurrentTheme.Accent or CurrentTheme.Tertiary
        }, "QuadOut")
        tween(btn, 0.15, {
            TextColor3 = enter and Color3.new(1, 1, 1) or CurrentTheme.Text
        }, "QuadOut")
    end

    table.insert(self.Connections, btn.MouseEnter:Connect(function()
        onHover(true)
        if self.Description ~= "" then
            showTooltip(self.Description, frame)
        end
    end))
    table.insert(self.Connections, btn.MouseLeave:Connect(function()
        onHover(false)
        hideTooltip()
    end))
    table.insert(self.Connections, btn.MouseButton1Down:Connect(function()
        tween(frame, 0.08, { BackgroundColor3 = CurrentTheme.AccentHover }, "QuadOut")
    end))
    table.insert(self.Connections, btn.MouseButton1Up:Connect(function()
        tween(frame, 0.1, { BackgroundColor3 = CurrentTheme.Accent }, "QuadOut")
    end))
    table.insert(self.Connections, btn.Activated:Connect(function()
        if self.Destroyed then return end
        safeCallback(self.Callback)
    end))

    return self
end

-- ============================================================
-- TOGGLE
-- ============================================================

local Toggle = setmetatable({}, { __index = Component })
Toggle.__index = Toggle

function Toggle.new(section, text, description, default, callback)
    local self = Component.new(section, text)
    setmetatable(self, Toggle)
    self.Callback = callback
    self.Description = description or ""
    self.Value = default == true
    self.SuppressCallback = false

    local frame = create("Frame", {
        Name = "Toggle_" .. text,
        BackgroundColor3 = CurrentTheme.Tertiary,
        Size = UDim2.new(1, 0, 0, 42),
        Parent = section.Content
    })
    create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = frame })
    create("UIStroke", {
        Color = CurrentTheme.Border,
        Thickness = 1,
        Transparency = 0.5,
        Parent = frame
    })

    local label = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -70, 1, 0),
        Position = UDim2.new(0, 14, 0, 0),
        Font = Enum.Font.GothamMedium,
        Text = text,
        TextColor3 = CurrentTheme.Text,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame
    })

    local track = create("Frame", {
        BackgroundColor3 = self.Value and CurrentTheme.ToggleOn or CurrentTheme.ToggleOff,
        Size = UDim2.new(0, 44, 0, 24),
        Position = UDim2.new(1, -58, 0.5, -12),
        Parent = frame
    })
    create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = track })

    local knob = create("Frame", {
        BackgroundColor3 = Color3.new(1, 1, 1),
        Size = UDim2.new(0, 18, 0, 18),
        Position = self.Value and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9),
        Parent = track
    })
    create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = knob })

    local hit = create("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Text = "",
        AutoButtonColor = false,
        Parent = frame
    })

    self.Frame = frame
    self.Track = track
    self.Knob = knob

    local function updateVisual(animate)
        local goalTrack = self.Value and CurrentTheme.ToggleOn or CurrentTheme.ToggleOff
        local goalKnob = self.Value and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
        if animate then
            tween(track, 0.2, { BackgroundColor3 = goalTrack }, "QuadOut")
            tween(knob, 0.2, { Position = goalKnob }, "BackOut")
        else
            track.BackgroundColor3 = goalTrack
            knob.Position = goalKnob
        end
    end

    table.insert(self.Connections, hit.Activated:Connect(function()
        if self.Destroyed then return end
        self.Value = not self.Value
        updateVisual(true)
        if not self.SuppressCallback then
            safeCallback(self.Callback, self.Value)
        end
    end))

    table.insert(self.Connections, hit.MouseEnter:Connect(function()
        if self.Description ~= "" then
            showTooltip(self.Description, frame)
        end
    end))
    table.insert(self.Connections, hit.MouseLeave:Connect(hideTooltip))

    function self:Set(val)
        if self.Destroyed then return end
        local newVal = val == true
        if self.Value == newVal then return end
        self.Value = newVal
        updateVisual(true)
        if not self.SuppressCallback then
            safeCallback(self.Callback, self.Value)
        end
    end

    function self:Get()
        return self.Value
    end

    return self
end

-- ============================================================
-- SLIDER
-- ============================================================

local Slider = setmetatable({}, { __index = Component })
Slider.__index = Slider

function Slider.new(section, text, max, min, callback, step)
    local self = Component.new(section, text)
    setmetatable(self, Slider)
    self.Callback = callback
    self.Min = min or 0
    self.Max = max or 100
    if self.Min > self.Max then
        self.Min, self.Max = self.Max, self.Min
    end
    self.Step = step or 1
    self.Value = self.Min
    self.SuppressCallback = false
    self.Dragging = false

    local frame = create("Frame", {
        Name = "Slider_" .. text,
        BackgroundColor3 = CurrentTheme.Tertiary,
        Size = UDim2.new(1, 0, 0, 58),
        Parent = section.Content
    })
    create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = frame })
    create("UIStroke", {
        Color = CurrentTheme.Border,
        Thickness = 1,
        Transparency = 0.5,
        Parent = frame
    })

    local label = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(0.6, 0, 0, 20),
        Position = UDim2.new(0, 14, 0, 8),
        Font = Enum.Font.GothamMedium,
        Text = text,
        TextColor3 = CurrentTheme.Text,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame
    })

    local valueLabel = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(0.35, 0, 0, 20),
        Position = UDim2.new(0.6, 0, 0, 8),
        Font = Enum.Font.Gotham,
        Text = tostring(self.Value),
        TextColor3 = CurrentTheme.Accent,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = frame
    })

    local track = create("Frame", {
        BackgroundColor3 = CurrentTheme.SliderTrack,
        Size = UDim2.new(1, -28, 0, 6),
        Position = UDim2.new(0, 14, 0, 40),
        Parent = frame
    })
    create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = track })

    local fill = create("Frame", {
        BackgroundColor3 = CurrentTheme.Accent,
        Size = UDim2.new(0, 0, 1, 0),
        Parent = track
    })
    create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = fill })

    local knob = create("Frame", {
        BackgroundColor3 = Color3.new(1, 1, 1),
        Size = UDim2.new(0, 16, 0, 16),
        Position = UDim2.new(0, -8, 0.5, -8),
        Parent = track
    })
    create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = knob })
    create("UIStroke", {
        Color = CurrentTheme.Accent,
        Thickness = 2,
        Parent = knob
    })

    self.Frame = frame
    self.Fill = fill
    self.Knob = knob
    self.ValueLabel = valueLabel
    self.Track = track

    local function updateVisual(val, animate)
        local ratio = 0
        if self.Max ~= self.Min then
            ratio = (val - self.Min) / (self.Max - self.Min)
        end
        ratio = clamp(ratio, 0, 1)
        local goalFill = UDim2.new(ratio, 0, 1, 0)
        local goalKnob = UDim2.new(ratio, -8, 0.5, -8)
        if animate then
            tween(fill, 0.1, { Size = goalFill }, "QuadOut")
            tween(knob, 0.1, { Position = goalKnob }, "QuadOut")
        else
            fill.Size = goalFill
            knob.Position = goalKnob
        end
        valueLabel.Text = tostring(round(val, self.Step < 1 and 2 or 0))
    end

    local function setFromPosition(inputPos)
        local absPos = track.AbsolutePosition.X
        local absSize = track.AbsoluteSize.X
        if absSize <= 0 then return end
        local ratio = clamp((inputPos - absPos) / absSize, 0, 1)
        local raw = self.Min + ratio * (self.Max - self.Min)
        local stepped = math.floor(raw / self.Step + 0.5) * self.Step
        stepped = clamp(stepped, self.Min, self.Max)
        if stepped ~= self.Value then
            self.Value = stepped
            updateVisual(self.Value, false)
            if not self.SuppressCallback then
                safeCallback(self.Callback, self.Value)
            end
        end
    end

    table.insert(self.Connections, track.InputBegan:Connect(function(input)
        if self.Destroyed then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            self.Dragging = true
            setFromPosition(input.Position.X)
        end
    end))

    table.insert(self.Connections, UserInputService.InputChanged:Connect(function(input)
        if not self.Dragging or self.Destroyed then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            setFromPosition(input.Position.X)
        end
    end))

    table.insert(self.Connections, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            self.Dragging = false
        end
    end))

    function self:Set(val)
        if self.Destroyed then return end
        local newVal = clamp(val, self.Min, self.Max)
        if self.Step then
            newVal = math.floor(newVal / self.Step + 0.5) * self.Step
        end
        if self.Value == newVal then return end
        self.Value = newVal
        updateVisual(self.Value, true)
        if not self.SuppressCallback then
            safeCallback(self.Callback, self.Value)
        end
    end

    function self:Get()
        return self.Value
    end

    updateVisual(self.Value, false)
    return self
end

-- ============================================================
-- DROPDOWN
-- ============================================================

local Dropdown = setmetatable({}, { __index = Component })
Dropdown.__index = Dropdown

function Dropdown.new(section, text, options, callback)
    local self = Component.new(section, text)
    setmetatable(self, Dropdown)
    self.Callback = callback
    self.Options = options or {}
    self.Value = self.Options[1] or ""
    self.Open = false
    self.SuppressCallback = false
    self.OptionButtons = {}

    local frame = create("Frame", {
        Name = "Dropdown_" .. text,
        BackgroundColor3 = CurrentTheme.Tertiary,
        Size = UDim2.new(1, 0, 0, 42),
        ClipsDescendants = true,
        Parent = section.Content
    })
    create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = frame })
    create("UIStroke", {
        Color = CurrentTheme.Border,
        Thickness = 1,
        Transparency = 0.5,
        Parent = frame
    })

    local header = create("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 42),
        Text = "",
        AutoButtonColor = false,
        Parent = frame
    })

    local label = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(0.45, 0, 1, 0),
        Position = UDim2.new(0, 14, 0, 0),
        Font = Enum.Font.GothamMedium,
        Text = text,
        TextColor3 = CurrentTheme.Text,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = header
    })

    local valueLabel = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(0.4, 0, 1, 0),
        Position = UDim2.new(0.45, 0, 0, 0),
        Font = Enum.Font.Gotham,
        Text = self.Value,
        TextColor3 = CurrentTheme.Accent,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = header
    })

    local arrow = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 20, 1, 0),
        Position = UDim2.new(1, -28, 0, 0),
        Font = Enum.Font.GothamBold,
        Text = "▾",
        TextColor3 = CurrentTheme.MutedText,
        TextSize = 14,
        Parent = header
    })

    local listFrame = create("Frame", {
        BackgroundColor3 = CurrentTheme.DropdownBg,
        Size = UDim2.new(1, -8, 0, 0),
        Position = UDim2.new(0, 4, 0, 42),
        ClipsDescendants = true,
        Visible = false,
        Parent = frame
    })
    create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = listFrame })

    local scroll = create("ScrollingFrame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = CurrentTheme.Accent,
        BorderSizePixel = 0,
        Parent = listFrame
    })
    create("UIListLayout", {
        Padding = UDim.new(0, 2),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = scroll
    })
    create("UIPadding", {
        PaddingTop = UDim.new(0, 4),
        PaddingBottom = UDim.new(0, 4),
        PaddingLeft = UDim.new(0, 4),
        PaddingRight = UDim.new(0, 4),
        Parent = scroll
    })

    self.Frame = frame
    self.ListFrame = listFrame
    self.Scroll = scroll
    self.ValueLabel = valueLabel
    self.Arrow = arrow

    local function rebuildOptions()
        for _, btn in ipairs(self.OptionButtons) do
            if btn and btn.Parent then btn:Destroy() end
        end
        table.clear(self.OptionButtons)

        for i, opt in ipairs(self.Options) do
            local optBtn = create("TextButton", {
                BackgroundColor3 = CurrentTheme.Tertiary,
                Size = UDim2.new(1, 0, 0, 32),
                Font = Enum.Font.Gotham,
                Text = tostring(opt),
                TextColor3 = CurrentTheme.Text,
                TextSize = 13,
                AutoButtonColor = false,
                LayoutOrder = i,
                Parent = scroll
            })
            create("UICorner", { CornerRadius = UDim.new(0, 5), Parent = optBtn })

            table.insert(self.Connections, optBtn.MouseEnter:Connect(function()
                tween(optBtn, 0.1, { BackgroundColor3 = CurrentTheme.Accent }, "QuadOut")
            end))
            table.insert(self.Connections, optBtn.MouseLeave:Connect(function()
                tween(optBtn, 0.1, { BackgroundColor3 = CurrentTheme.Tertiary }, "QuadOut")
            end))
            table.insert(self.Connections, optBtn.Activated:Connect(function()
                if self.Destroyed then return end
                self.Value = opt
                valueLabel.Text = tostring(opt)
                self:Close()
                if not self.SuppressCallback then
                    safeCallback(self.Callback, self.Value)
                end
            end))
            table.insert(self.OptionButtons, optBtn)
        end

        local contentHeight = #self.Options * 34 + 8
        scroll.CanvasSize = UDim2.new(0, 0, 0, contentHeight)
        self.ListHeight = math.min(contentHeight, 160)
    end

    function self:Open()
        if self.Open or self.Destroyed then return end
        self.Open = true
        listFrame.Visible = true
        arrow.Text = "▴"
        local h = self.ListHeight or 120
        tween(frame, 0.25, { Size = UDim2.new(1, 0, 0, 42 + h + 4) }, "QuadOut")
        tween(listFrame, 0.25, { Size = UDim2.new(1, -8, 0, h) }, "QuadOut")
    end

    function self:Close()
        if not self.Open or self.Destroyed then return end
        self.Open = false
        arrow.Text = "▾"
        tween(frame, 0.2, { Size = UDim2.new(1, 0, 0, 42) }, "QuadOut", function()
            if not self.Open then
                listFrame.Visible = false
            end
        end)
        tween(listFrame, 0.2, { Size = UDim2.new(1, -8, 0, 0) }, "QuadOut")
    end

    function self:Toggle()
        if self.Open then self:Close() else self:Open() end
    end

    table.insert(self.Connections, header.Activated:Connect(function()
        if self.Destroyed then return end
        self:Toggle()
    end))

    function self:Set(val)
        if self.Destroyed then return end
        local found = false
        for _, opt in ipairs(self.Options) do
            if opt == val then
                found = true
                break
            end
        end
        if not found then return end
        self.Value = val
        valueLabel.Text = tostring(val)
        if not self.SuppressCallback then
            safeCallback(self.Callback, self.Value)
        end
    end

    function self:Get()
        return self.Value
    end

    rebuildOptions()
    return self
end

-- ============================================================
-- MULTI DROPDOWN
-- ============================================================

local MultiDropdown = setmetatable({}, { __index = Component })
MultiDropdown.__index = MultiDropdown

function MultiDropdown.new(section, text, options, callback)
    local self = Component.new(section, text)
    setmetatable(self, MultiDropdown)
    self.Callback = callback
    self.Options = options or {}
    self.Selected = {}
    self.Open = false
    self.SuppressCallback = false
    self.OptionButtons = {}

    local frame = create("Frame", {
        Name = "MultiDropdown_" .. text,
        BackgroundColor3 = CurrentTheme.Tertiary,
        Size = UDim2.new(1, 0, 0, 42),
        ClipsDescendants = true,
        Parent = section.Content
    })
    create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = frame })
    create("UIStroke", {
        Color = CurrentTheme.Border,
        Thickness = 1,
        Transparency = 0.5,
        Parent = frame
    })

    local header = create("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 42),
        Text = "",
        AutoButtonColor = false,
        Parent = frame
    })

    local label = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(0.4, 0, 1, 0),
        Position = UDim2.new(0, 14, 0, 0),
        Font = Enum.Font.GothamMedium,
        Text = text,
        TextColor3 = CurrentTheme.Text,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = header
    })

    local valueLabel = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(0.45, 0, 1, 0),
        Position = UDim2.new(0.4, 0, 0, 0),
        Font = Enum.Font.Gotham,
        Text = "None",
        TextColor3 = CurrentTheme.Accent,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Right,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = header
    })

    local arrow = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 20, 1, 0),
        Position = UDim2.new(1, -28, 0, 0),
        Font = Enum.Font.GothamBold,
        Text = "▾",
        TextColor3 = CurrentTheme.MutedText,
        TextSize = 14,
        Parent = header
    })

    local listFrame = create("Frame", {
        BackgroundColor3 = CurrentTheme.DropdownBg,
        Size = UDim2.new(1, -8, 0, 0),
        Position = UDim2.new(0, 4, 0, 42),
        ClipsDescendants = true,
        Visible = false,
        Parent = frame
    })
    create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = listFrame })

    local scroll = create("ScrollingFrame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = CurrentTheme.Accent,
        BorderSizePixel = 0,
        Parent = listFrame
    })
    create("UIListLayout", {
        Padding = UDim.new(0, 2),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = scroll
    })
    create("UIPadding", {
        PaddingTop = UDim.new(0, 4),
        PaddingBottom = UDim.new(0, 4),
        PaddingLeft = UDim.new(0, 4),
        PaddingRight = UDim.new(0, 4),
        Parent = scroll
    })

    self.Frame = frame
    self.ListFrame = listFrame
    self.Scroll = scroll
    self.ValueLabel = valueLabel
    self.Arrow = arrow

    local function updateValueText()
        local keys = {}
        for k in pairs(self.Selected) do
            table.insert(keys, k)
        end
        table.sort(keys)
        if #keys == 0 then
            valueLabel.Text = "None"
        else
            valueLabel.Text = table.concat(keys, ", ")
        end
    end

    local function rebuildOptions()
        for _, btn in ipairs(self.OptionButtons) do
            if btn and btn.Parent then btn:Destroy() end
        end
        table.clear(self.OptionButtons)

        for i, opt in ipairs(self.Options) do
            local optBtn = create("TextButton", {
                BackgroundColor3 = self.Selected[opt] and CurrentTheme.Accent or CurrentTheme.Tertiary,
                Size = UDim2.new(1, 0, 0, 32),
                Font = Enum.Font.Gotham,
                Text = tostring(opt),
                TextColor3 = CurrentTheme.Text,
                TextSize = 13,
                AutoButtonColor = false,
                LayoutOrder = i,
                Parent = scroll
            })
            create("UICorner", { CornerRadius = UDim.new(0, 5), Parent = optBtn })

            table.insert(self.Connections, optBtn.Activated:Connect(function()
                if self.Destroyed then return end
                if self.Selected[opt] then
                    self.Selected[opt] = nil
                    tween(optBtn, 0.12, { BackgroundColor3 = CurrentTheme.Tertiary }, "QuadOut")
                else
                    self.Selected[opt] = true
                    tween(optBtn, 0.12, { BackgroundColor3 = CurrentTheme.Accent }, "QuadOut")
                end
                updateValueText()
                if not self.SuppressCallback then
                    local vals = {}
                    for k in pairs(self.Selected) do table.insert(vals, k) end
                    safeCallback(self.Callback, vals)
                end
            end))
            table.insert(self.OptionButtons, optBtn)
        end

        local contentHeight = #self.Options * 34 + 8
        scroll.CanvasSize = UDim2.new(0, 0, 0, contentHeight)
        self.ListHeight = math.min(contentHeight, 160)
    end

    function self:Open()
        if self.Open or self.Destroyed then return end
        self.Open = true
        listFrame.Visible = true
        arrow.Text = "▴"
        local h = self.ListHeight or 120
        tween(frame, 0.25, { Size = UDim2.new(1, 0, 0, 42 + h + 4) }, "QuadOut")
        tween(listFrame, 0.25, { Size = UDim2.new(1, -8, 0, h) }, "QuadOut")
    end

    function self:Close()
        if not self.Open or self.Destroyed then return end
        self.Open = false
        arrow.Text = "▾"
        tween(frame, 0.2, { Size = UDim2.new(1, 0, 0, 42) }, "QuadOut", function()
            if not self.Open then listFrame.Visible = false end
        end)
        tween(listFrame, 0.2, { Size = UDim2.new(1, -8, 0, 0) }, "QuadOut")
    end

    function self:Toggle()
        if self.Open then self:Close() else self:Open() end
    end

    table.insert(self.Connections, header.Activated:Connect(function()
        if self.Destroyed then return end
        self:Toggle()
    end))

    function self:Set(values)
        if self.Destroyed then return end
        table.clear(self.Selected)
        if type(values) == "table" then
            for _, v in ipairs(values) do
                self.Selected[v] = true
            end
        end
        rebuildOptions()
        updateValueText()
        if not self.SuppressCallback then
            local vals = {}
            for k in pairs(self.Selected) do table.insert(vals, k) end
            safeCallback(self.Callback, vals)
        end
    end

    function self:Get()
        local vals = {}
        for k in pairs(self.Selected) do table.insert(vals, k) end
        return vals
    end

    rebuildOptions()
    return self
end

-- ============================================================
-- COLOR PICKER
-- ============================================================

local ColorPicker = setmetatable({}, { __index = Component })
ColorPicker.__index = ColorPicker

local function rgbToHsv(c)
    local r, g, b = c.R, c.G, c.B
    local max = math.max(r, g, b)
    local min = math.min(r, g, b)
    local h, s, v = 0, 0, max
    local d = max - min
    s = max == 0 and 0 or d / max
    if max == min then
        h = 0
    else
        if max == r then
            h = (g - b) / d + (g < b and 6 or 0)
        elseif max == g then
            h = (b - r) / d + 2
        else
            h = (r - g) / d + 4
        end
        h = h / 6
    end
    return h, s, v
end

local function hsvToRgb(h, s, v)
    local r, g, b
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then r, g, b = v, t, p
    elseif i == 1 then r, g, b = q, v, p
    elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v
    elseif i == 4 then r, g, b = t, p, v
    else r, g, b = v, p, q end
    return Color3.new(r, g, b)
end

function ColorPicker.new(section, text, defaultColor, callback)
    local self = Component.new(section, text)
    setmetatable(self, ColorPicker)
    self.Callback = callback
    self.Color = defaultColor or Color3.fromRGB(255, 255, 255)
    self.Open = false
    self.SuppressCallback = false
    self.H, self.S, self.V = rgbToHsv(self.Color)

    local frame = create("Frame", {
        Name = "ColorPicker_" .. text,
        BackgroundColor3 = CurrentTheme.Tertiary,
        Size = UDim2.new(1, 0, 0, 42),
        ClipsDescendants = true,
        Parent = section.Content
    })
    create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = frame })
    create("UIStroke", {
        Color = CurrentTheme.Border,
        Thickness = 1,
        Transparency = 0.5,
        Parent = frame
    })

    local header = create("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 42),
        Text = "",
        AutoButtonColor = false,
        Parent = frame
    })

    local label = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -60, 1, 0),
        Position = UDim2.new(0, 14, 0, 0),
        Font = Enum.Font.GothamMedium,
        Text = text,
        TextColor3 = CurrentTheme.Text,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = header
    })

    local preview = create("Frame", {
        BackgroundColor3 = self.Color,
        Size = UDim2.new(0, 28, 0, 28),
        Position = UDim2.new(1, -42, 0.5, -14),
        Parent = header
    })
    create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = preview })
    create("UIStroke", {
        Color = CurrentTheme.Border,
        Thickness = 1,
        Parent = preview
    })

    local pickerFrame = create("Frame", {
        BackgroundColor3 = CurrentTheme.DropdownBg,
        Size = UDim2.new(1, -8, 0, 0),
        Position = UDim2.new(0, 4, 0, 42),
        ClipsDescendants = true,
        Visible = false,
        Parent = frame
    })
    create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = pickerFrame })
    create("UIPadding", {
        PaddingTop = UDim.new(0, 10),
        PaddingBottom = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
        Parent = pickerFrame
    })

    -- SV Square
    local svFrame = create("Frame", {
        BackgroundColor3 = Color3.fromHSV(self.H, 1, 1),
        Size = UDim2.new(0, 160, 0, 120),
        Position = UDim2.new(0, 0, 0, 0),
        Parent = pickerFrame
    })
    create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = svFrame })

    local whiteGrad = create("Frame", {
        BackgroundColor3 = Color3.new(1, 1, 1),
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 0,
        Parent = svFrame
    })
    create("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 1)
        }),
        Rotation = 0,
        Parent = whiteGrad
    })

    local blackGrad = create("Frame", {
        BackgroundColor3 = Color3.new(0, 0, 0),
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 0,
        Parent = svFrame
    })
    create("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(1, 0)
        }),
        Rotation = 90,
        Parent = blackGrad
    })

    local svCursor = create("Frame", {
        BackgroundColor3 = Color3.new(1, 1, 1),
        Size = UDim2.new(0, 12, 0, 12),
        Position = UDim2.new(self.S, -6, 1 - self.V, -6),
        Parent = svFrame
    })
    create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = svCursor })
    create("UIStroke", {
        Color = Color3.new(0, 0, 0),
        Thickness = 1.5,
        Parent = svCursor
    })

    -- Hue bar
    local hueFrame = create("Frame", {
        BackgroundColor3 = Color3.new(1, 1, 1),
        Size = UDim2.new(0, 20, 0, 120),
        Position = UDim2.new(0, 170, 0, 0),
        Parent = pickerFrame
    })
    create("UICorner", { CornerRadius = UDim.new(0, 4), Parent = hueFrame })
    create("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
            ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
            ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 255, 255)),
            ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
            ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
        }),
        Rotation = 90,
        Parent = hueFrame
    })

    local hueCursor = create("Frame", {
        BackgroundColor3 = Color3.new(1, 1, 1),
        Size = UDim2.new(1, 4, 0, 6),
        Position = UDim2.new(0, -2, self.H, -3),
        Parent = hueFrame
    })
    create("UICorner", { CornerRadius = UDim.new(0, 2), Parent = hueCursor })
    create("UIStroke", {
        Color = Color3.new(0, 0, 0),
        Thickness = 1,
        Parent = hueCursor
    })

    -- Preview large
    local bigPreview = create("Frame", {
        BackgroundColor3 = self.Color,
        Size = UDim2.new(0, 50, 0, 30),
        Position = UDim2.new(0, 200, 0, 0),
        Parent = pickerFrame
    })
    create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = bigPreview })

    local hexLabel = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 50, 0, 20),
        Position = UDim2.new(0, 200, 0, 36),
        Font = Enum.Font.Gotham,
        Text = "",
        TextColor3 = CurrentTheme.MutedText,
        TextSize = 11,
        Parent = pickerFrame
    })

    self.Frame = frame
    self.Preview = preview
    self.PickerFrame = pickerFrame
    self.SVFrame = svFrame
    self.SVCursor = svCursor
    self.HueFrame = hueFrame
    self.HueCursor = hueCursor
    self.BigPreview = bigPreview
    self.HexLabel = hexLabel

    local function updateColor(fromInput)
        self.Color = hsvToRgb(self.H, self.S, self.V)
        preview.BackgroundColor3 = self.Color
        bigPreview.BackgroundColor3 = self.Color
        svFrame.BackgroundColor3 = Color3.fromHSV(self.H, 1, 1)
        local r = math.floor(self.Color.R * 255)
        local g = math.floor(self.Color.G * 255)
        local b = math.floor(self.Color.B * 255)
        hexLabel.Text = string.format("#%02X%02X%02X", r, g, b)
        if fromInput and not self.SuppressCallback then
            safeCallback(self.Callback, self.Color)
        end
    end

    updateColor(false)

    local draggingSV, draggingHue = false, false

    table.insert(self.Connections, svFrame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSV = true
            local rel = input.Position - svFrame.AbsolutePosition
            self.S = clamp(rel.X / svFrame.AbsoluteSize.X, 0, 1)
            self.V = 1 - clamp(rel.Y / svFrame.AbsoluteSize.Y, 0, 1)
            svCursor.Position = UDim2.new(self.S, -6, 1 - self.V, -6)
            updateColor(true)
        end
    end))

    table.insert(self.Connections, hueFrame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingHue = true
            local rel = input.Position.Y - hueFrame.AbsolutePosition.Y
            self.H = clamp(rel / hueFrame.AbsoluteSize.Y, 0, 1)
            hueCursor.Position = UDim2.new(0, -2, self.H, -3)
            updateColor(true)
        end
    end))

    table.insert(self.Connections, UserInputService.InputChanged:Connect(function(input)
        if self.Destroyed then return end
        if draggingSV and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local rel = input.Position - svFrame.AbsolutePosition
            self.S = clamp(rel.X / svFrame.AbsoluteSize.X, 0, 1)
            self.V = 1 - clamp(rel.Y / svFrame.AbsoluteSize.Y, 0, 1)
            svCursor.Position = UDim2.new(self.S, -6, 1 - self.V, -6)
            updateColor(true)
        end
        if draggingHue and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local rel = input.Position.Y - hueFrame.AbsolutePosition.Y
            self.H = clamp(rel / hueFrame.AbsoluteSize.Y, 0, 1)
            hueCursor.Position = UDim2.new(0, -2, self.H, -3)
            updateColor(true)
        end
    end))

    table.insert(self.Connections, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSV = false
            draggingHue = false
        end
    end))

    function self:Open()
        if self.Open or self.Destroyed then return end
        self.Open = true
        pickerFrame.Visible = true
        tween(frame, 0.3, { Size = UDim2.new(1, 0, 0, 180) }, "QuadOut")
        tween(pickerFrame, 0.3, { Size = UDim2.new(1, -8, 0, 134) }, "QuadOut")
    end

    function self:Close()
        if not self.Open or self.Destroyed then return end
        self.Open = false
        tween(frame, 0.25, { Size = UDim2.new(1, 0, 0, 42) }, "QuadOut", function()
            if not self.Open then pickerFrame.Visible = false end
        end)
        tween(pickerFrame, 0.25, { Size = UDim2.new(1, -8, 0, 0) }, "QuadOut")
    end

    table.insert(self.Connections, header.Activated:Connect(function()
        if self.Destroyed then return end
        if self.Open then self:Close() else self:Open() end
    end))

    function self:Set(col)
        if self.Destroyed then return end
        if typeof(col) ~= "Color3" then return end
        self.Color = col
        self.H, self.S, self.V = rgbToHsv(col)
        svCursor.Position = UDim2.new(self.S, -6, 1 - self.V, -6)
        hueCursor.Position = UDim2.new(0, -2, self.H, -3)
        updateColor(true)
    end

    function self:Get()
        return self.Color
    end

    return self
end

-- ============================================================
-- TEXTBOX
-- ============================================================

local TextBoxComp = setmetatable({}, { __index = Component })
TextBoxComp.__index = TextBoxComp

function TextBoxComp.new(section, text, placeholder, callback)
    local self = Component.new(section, text)
    setmetatable(self, TextBoxComp)
    self.Callback = callback
    self.Value = ""
    self.SuppressCallback = false

    local frame = create("Frame", {
        Name = "TextBox_" .. text,
        BackgroundColor3 = CurrentTheme.Tertiary,
        Size = UDim2.new(1, 0, 0, 58),
        Parent = section.Content
    })
    create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = frame })
    create("UIStroke", {
        Color = CurrentTheme.Border,
        Thickness = 1,
        Transparency = 0.5,
        Parent = frame
    })

    local label = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -20, 0, 18),
        Position = UDim2.new(0, 14, 0, 6),
        Font = Enum.Font.GothamMedium,
        Text = text,
        TextColor3 = CurrentTheme.Text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame
    })

    local box = create("TextBox", {
        BackgroundColor3 = CurrentTheme.Secondary,
        Size = UDim2.new(1, -20, 0, 26),
        Position = UDim2.new(0, 10, 0, 26),
        Font = Enum.Font.Gotham,
        Text = "",
        PlaceholderText = placeholder or "Enter text...",
        PlaceholderColor3 = CurrentTheme.MutedText,
        TextColor3 = CurrentTheme.Text,
        TextSize = 13,
        ClearTextOnFocus = false,
        Parent = frame
    })
    create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = box })
    create("UIPadding", {
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
        Parent = box
    })

    self.Frame = frame
    self.Box = box

    table.insert(self.Connections, box.FocusLost:Connect(function(enter)
        if self.Destroyed then return end
        self.Value = box.Text
        if not self.SuppressCallback then
            safeCallback(self.Callback, self.Value)
        end
    end))

    function self:Set(val)
        if self.Destroyed then return end
        self.Value = tostring(val or "")
        box.Text = self.Value
        if not self.SuppressCallback then
            safeCallback(self.Callback, self.Value)
        end
    end

    function self:Get()
        return self.Value
    end

    return self
end

-- ============================================================
-- KEYBIND
-- ============================================================

local Keybind = setmetatable({}, { __index = Component })
Keybind.__index = Keybind

function Keybind.new(section, text, defaultKey, callback)
    local self = Component.new(section, text)
    setmetatable(self, Keybind)
    self.Callback = callback
    self.Key = defaultKey or Enum.KeyCode.RightShift
    self.Listening = false
    self.SuppressCallback = false

    local frame = create("Frame", {
        Name = "Keybind_" .. text,
        BackgroundColor3 = CurrentTheme.Tertiary,
        Size = UDim2.new(1, 0, 0, 42),
        Parent = section.Content
    })
    create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = frame })
    create("UIStroke", {
        Color = CurrentTheme.Border,
        Thickness = 1,
        Transparency = 0.5,
        Parent = frame
    })

    local label = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(0.55, 0, 1, 0),
        Position = UDim2.new(0, 14, 0, 0),
        Font = Enum.Font.GothamMedium,
        Text = text,
        TextColor3 = CurrentTheme.Text,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame
    })

    local keyBtn = create("TextButton", {
        BackgroundColor3 = CurrentTheme.Secondary,
        Size = UDim2.new(0, 90, 0, 28),
        Position = UDim2.new(1, -104, 0.5, -14),
        Font = Enum.Font.Gotham,
        Text = self.Key.Name,
        TextColor3 = CurrentTheme.Accent,
        TextSize = 12,
        AutoButtonColor = false,
        Parent = frame
    })
    create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = keyBtn })

    self.Frame = frame
    self.KeyBtn = keyBtn

    table.insert(self.Connections, keyBtn.Activated:Connect(function()
        if self.Destroyed then return end
        self.Listening = true
        keyBtn.Text = "..."
        tween(keyBtn, 0.1, { BackgroundColor3 = CurrentTheme.Accent }, "QuadOut")
    end))

    table.insert(self.Connections, UserInputService.InputBegan:Connect(function(input, processed)
        if self.Destroyed then return end
        if self.Listening then
            if input.UserInputType == Enum.UserInputType.Keyboard then
                self.Key = input.KeyCode
                keyBtn.Text = self.Key.Name
                self.Listening = false
                tween(keyBtn, 0.15, { BackgroundColor3 = CurrentTheme.Secondary }, "QuadOut")
            end
            return
        end
        if not processed and input.KeyCode == self.Key then
            if not self.SuppressCallback then
                safeCallback(self.Callback)
            end
        end
    end))

    function self:Set(key)
        if self.Destroyed then return end
        if typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode then
            self.Key = key
            keyBtn.Text = key.Name
        end
    end

    function self:Get()
        return self.Key
    end

    return self
end

-- ============================================================
-- LABEL
-- ============================================================

local Label = setmetatable({}, { __index = Component })
Label.__index = Label

function Label.new(section, text)
    local self = Component.new(section, text)
    setmetatable(self, Label)

    local frame = create("Frame", {
        Name = "Label_" .. text,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 24),
        Parent = section.Content
    })

    local label = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -10, 1, 0),
        Position = UDim2.new(0, 5, 0, 0),
        Font = Enum.Font.GothamMedium,
        Text = text,
        TextColor3 = CurrentTheme.MutedText,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame
    })

    self.Frame = frame
    self.Label = label
    return self
end

-- ============================================================
-- PARAGRAPH
-- ============================================================

local Paragraph = setmetatable({}, { __index = Component })
Paragraph.__index = Paragraph

function Paragraph.new(section, title, content)
    local self = Component.new(section, title)
    setmetatable(self, Paragraph)

    local frame = create("Frame", {
        Name = "Paragraph_" .. title,
        BackgroundColor3 = CurrentTheme.Tertiary,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = section.Content
    })
    create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = frame })
    create("UIStroke", {
        Color = CurrentTheme.Border,
        Thickness = 1,
        Transparency = 0.5,
        Parent = frame
    })
    create("UIPadding", {
        PaddingTop = UDim.new(0, 10),
        PaddingBottom = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 14),
        PaddingRight = UDim.new(0, 14),
        Parent = frame
    })

    local titleLabel = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 18),
        Font = Enum.Font.GothamBold,
        Text = title,
        TextColor3 = CurrentTheme.Text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = frame
    })

    local contentLabel = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        Position = UDim2.new(0, 0, 0, 22),
        Font = Enum.Font.Gotham,
        Text = content or "",
        TextColor3 = CurrentTheme.MutedText,
        TextSize = 12,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = frame
    })

    self.Frame = frame
    return self
end

-- ============================================================
-- DIVIDER
-- ============================================================

local Divider = setmetatable({}, { __index = Component })
Divider.__index = Divider

function Divider.new(section)
    local self = Component.new(section, "Divider")
    setmetatable(self, Divider)

    local frame = create("Frame", {
        Name = "Divider",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 14),
        Parent = section.Content
    })

    local line = create("Frame", {
        BackgroundColor3 = CurrentTheme.Border,
        Size = UDim2.new(1, -20, 0, 1),
        Position = UDim2.new(0, 10, 0.5, 0),
        BorderSizePixel = 0,
        Parent = frame
    })

    self.Frame = frame
    return self
end

-- ============================================================
-- SECTION
-- ============================================================

local Section = {}
Section.__index = Section

function Section.new(tab, name)
    local self = setmetatable({}, Section)
    self.Tab = tab
    self.Name = name
    self.Components = {}
    self.Destroyed = false

    local frame = create("Frame", {
        Name = "Section_" .. name,
        BackgroundColor3 = CurrentTheme.Secondary,
        Size = UDim2.new(1, -16, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = tab.Content
    })
    create("UICorner", { CornerRadius = UDim.new(0, 10), Parent = frame })
    create("UIStroke", {
        Color = CurrentTheme.Border,
        Thickness = 1,
        Transparency = 0.4,
        Parent = frame
    })
    create("UIPadding", {
        PaddingTop = UDim.new(0, 12),
        PaddingBottom = UDim.new(0, 12),
        PaddingLeft = UDim.new(0, 12),
        PaddingRight = UDim.new(0, 12),
        Parent = frame
    })
    create("UIListLayout", {
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = frame
    })

    local header = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 22),
        Font = Enum.Font.GothamBold,
        Text = name,
        TextColor3 = CurrentTheme.Text,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = 0,
        Parent = frame
    })

    self.Frame = frame
    self.Content = frame
    self.Header = header

    return self
end

function Section:NewButton(text, description, callback)
    local comp = Button.new(self, text, description, callback)
    table.insert(self.Components, comp)
    return comp
end

function Section:NewToggle(text, description, default, callback)
    if type(default) == "function" then
        callback = default
        default = false
    end
    local comp = Toggle.new(self, text, description, default, callback)
    table.insert(self.Components, comp)
    return comp
end

function Section:NewSlider(text, max, min, callback, step)
    if type(min) == "function" then
        callback = min
        min = 0
    end
    local comp = Slider.new(self, text, max, min, callback, step)
    table.insert(self.Components, comp)
    return comp
end

function Section:NewDropdown(text, options, callback)
    local comp = Dropdown.new(self, text, options, callback)
    table.insert(self.Components, comp)
    return comp
end

function Section:NewMultiDropdown(text, options, callback)
    local comp = MultiDropdown.new(self, text, options, callback)
    table.insert(self.Components, comp)
    return comp
end

function Section:NewColorPicker(text, defaultColor, callback)
    local comp = ColorPicker.new(self, text, defaultColor, callback)
    table.insert(self.Components, comp)
    return comp
end

function Section:NewTextBox(text, placeholder, callback)
    local comp = TextBoxComp.new(self, text, placeholder, callback)
    table.insert(self.Components, comp)
    return comp
end

function Section:NewKeybind(text, defaultKey, callback)
    local comp = Keybind.new(self, text, defaultKey, callback)
    table.insert(self.Components, comp)
    return comp
end

function Section:NewLabel(text)
    local comp = Label.new(self, text)
    table.insert(self.Components, comp)
    return comp
end

function Section:NewParagraph(title, content)
    local comp = Paragraph.new(self, title, content)
    table.insert(self.Components, comp)
    return comp
end

function Section:NewDivider()
    local comp = Divider.new(self)
    table.insert(self.Components, comp)
    return comp
end

function Section:Destroy()
    if self.Destroyed then return end
    self.Destroyed = true
    for _, comp in ipairs(self.Components) do
        if comp.Destroy then comp:Destroy() end
    end
    table.clear(self.Components)
    if self.Frame and self.Frame.Parent then
        self.Frame:Destroy()
    end
end

-- ============================================================
-- TAB
-- ============================================================

local Tab = {}
Tab.__index = Tab

function Tab.new(window, name, icon)
    local self = setmetatable({}, Tab)
    self.Window = window
    self.Name = name
    self.Icon = icon
    self.Sections = {}
    self.Destroyed = false
    self.Selected = false

    local tabBtn = create("TextButton", {
        Name = "Tab_" .. name,
        BackgroundColor3 = CurrentTheme.Secondary,
        Size = UDim2.new(1, -12, 0, 40),
        Font = Enum.Font.GothamMedium,
        Text = "  " .. name,
        TextColor3 = CurrentTheme.MutedText,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        AutoButtonColor = false,
        Parent = window.SidebarList
    })
    create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = tabBtn })

    local indicator = create("Frame", {
        BackgroundColor3 = CurrentTheme.Accent,
        Size = UDim2.new(0, 3, 0.6, 0),
        Position = UDim2.new(0, 0, 0.2, 0),
        Visible = false,
        Parent = tabBtn
    })
    create("UICorner", { CornerRadius = UDim.new(0, 2), Parent = indicator })

    local content = create("ScrollingFrame", {
        Name = "TabContent_" .. name,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = CurrentTheme.Accent,
        BorderSizePixel = 0,
        Visible = false,
        Parent = window.ContentArea
    })
    create("UIListLayout", {
        Padding = UDim.new(0, 12),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = content
    })
    create("UIPadding", {
        PaddingTop = UDim.new(0, 12),
        PaddingBottom = UDim.new(0, 12),
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
        Parent = content
    })

    local layout = content:FindFirstChildOfClass("UIListLayout")
    table.insert(window.Connections, layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        content.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 24)
    end))

    self.Button = tabBtn
    self.Indicator = indicator
    self.Content = content

    table.insert(window.Connections, tabBtn.Activated:Connect(function()
        if self.Destroyed then return end
        window:SelectTab(self)
    end))

    table.insert(window.Connections, tabBtn.MouseEnter:Connect(function()
        if not self.Selected then
            tween(tabBtn, 0.12, { BackgroundColor3 = CurrentTheme.Tertiary }, "QuadOut")
        end
    end))
    table.insert(window.Connections, tabBtn.MouseLeave:Connect(function()
        if not self.Selected then
            tween(tabBtn, 0.12, { BackgroundColor3 = CurrentTheme.Secondary }, "QuadOut")
        end
    end))

    return self
end

function Tab:NewSection(name)
    local sec = Section.new(self, name)
    table.insert(self.Sections, sec)
    return sec
end

function Tab:Select()
    self.Selected = true
    self.Content.Visible = true
    self.Indicator.Visible = true
    tween(self.Button, 0.15, {
        BackgroundColor3 = CurrentTheme.Tertiary,
        TextColor3 = CurrentTheme.Text
    }, "QuadOut")
end

function Tab:Deselect()
    self.Selected = false
    self.Content.Visible = false
    self.Indicator.Visible = false
    tween(self.Button, 0.15, {
        BackgroundColor3 = CurrentTheme.Secondary,
        TextColor3 = CurrentTheme.MutedText
    }, "QuadOut")
end

function Tab:Destroy()
    if self.Destroyed then return end
    self.Destroyed = true
    for _, sec in ipairs(self.Sections) do
        sec:Destroy()
    end
    table.clear(self.Sections)
    if self.Button and self.Button.Parent then self.Button:Destroy() end
    if self.Content and self.Content.Parent then self.Content:Destroy() end
end

-- ============================================================
-- WINDOW
-- ============================================================

local Window = {}
Window.__index = Window

function Window.new(library, title, themeName)
    local self = setmetatable({}, Window)
    self.Library = library
    self.Title = title or "Lumina UI"
    self.Tabs = {}
    self.Connections = {}
    self.Destroyed = false
    self.Minimized = false
    self.SelectedTab = nil
    self.Dragging = false
    self.DragStart = nil
    self.StartPos = nil

    if themeName and DefaultThemes[themeName] then
        CurrentTheme = table.clone(DefaultThemes[themeName])
    end

    local screenGui = create("ScreenGui", {
        Name = "LuminaUI_" .. HttpService:GenerateGUID(false):sub(1, 8),
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 10
    })
    parentGui(screenGui)

    local main = create("Frame", {
        Name = "Main",
        BackgroundColor3 = CurrentTheme.Background,
        Size = UDim2.new(0, 580, 0, 420),
        Position = UDim2.new(0.5, -290, 0.5, -210),
        Parent = screenGui
    })
    create("UICorner", { CornerRadius = UDim.new(0, 12), Parent = main })
    create("UIStroke", {
        Color = CurrentTheme.Border,
        Thickness = 1.5,
        Transparency = 0.3,
        Parent = main
    })

    -- Title bar
    local titleBar = create("Frame", {
        Name = "TitleBar",
        BackgroundColor3 = CurrentTheme.Secondary,
        Size = UDim2.new(1, 0, 0, 44),
        Parent = main
    })
    create("UICorner", { CornerRadius = UDim.new(0, 12), Parent = titleBar })

    local titleCover = create("Frame", {
        BackgroundColor3 = CurrentTheme.Secondary,
        Size = UDim2.new(1, 0, 0, 14),
        Position = UDim2.new(0, 0, 1, -14),
        BorderSizePixel = 0,
        Parent = titleBar
    })

    local titleLabel = create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -100, 1, 0),
        Position = UDim2.new(0, 16, 0, 0),
        Font = Enum.Font.GothamBold,
        Text = self.Title,
        TextColor3 = CurrentTheme.Text,
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = titleBar
    })

    local minimizeBtn = create("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 32, 0, 32),
        Position = UDim2.new(1, -72, 0.5, -16),
        Font = Enum.Font.GothamBold,
        Text = "─",
        TextColor3 = CurrentTheme.MutedText,
        TextSize = 16,
        AutoButtonColor = false,
        Parent = titleBar
    })

    local closeBtn = create("TextButton", {
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 32, 0, 32),
        Position = UDim2.new(1, -40, 0.5, -16),
        Font = Enum.Font.GothamBold,
        Text = "✕",
        TextColor3 = CurrentTheme.MutedText,
        TextSize = 14,
        AutoButtonColor = false,
        Parent = titleBar
    })

    -- Sidebar (leaves room for title bar + footer)
    local sidebar = create("Frame", {
        Name = "Sidebar",
        BackgroundColor3 = CurrentTheme.Secondary,
        Size = UDim2.new(0, 150, 1, -68),
        Position = UDim2.new(0, 0, 0, 44),
        Parent = main
    })

    local sidebarList = create("ScrollingFrame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, -50),
        Position = UDim2.new(0, 0, 0, 8),
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = CurrentTheme.Accent,
        BorderSizePixel = 0,
        Parent = sidebar
    })
    create("UIListLayout", {
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        Parent = sidebarList
    })
    create("UIPadding", {
        PaddingTop = UDim.new(0, 4),
        PaddingBottom = UDim.new(0, 4),
        Parent = sidebarList
    })

    -- Search
    local searchBox = create("TextBox", {
        BackgroundColor3 = CurrentTheme.Tertiary,
        Size = UDim2.new(1, -16, 0, 32),
        Position = UDim2.new(0, 8, 1, -42),
        Font = Enum.Font.Gotham,
        Text = "",
        PlaceholderText = "Search...",
        PlaceholderColor3 = CurrentTheme.MutedText,
        TextColor3 = CurrentTheme.Text,
        TextSize = 12,
        ClearTextOnFocus = false,
        Parent = sidebar
    })
    create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = searchBox })
    create("UIPadding", {
        PaddingLeft = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 8),
        Parent = searchBox
    })

    -- Content area
    local contentArea = create("Frame", {
        Name = "ContentArea",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -150, 1, -68),
        Position = UDim2.new(0, 150, 0, 44),
        ClipsDescendants = true,
        Parent = main
    })

    -- Footer credit
    local footer = create("Frame", {
        Name = "Footer",
        BackgroundColor3 = CurrentTheme.Secondary,
        Size = UDim2.new(1, 0, 0, 24),
        Position = UDim2.new(0, 0, 1, -24),
        BorderSizePixel = 0,
        Parent = main
    })
    create("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -16, 1, 0),
        Position = UDim2.new(0, 8, 0, 0),
        Font = Enum.Font.Gotham,
        Text = "thanks for using Lumina UI Library, benefits: no skibidi toilet images will be shown",
        TextColor3 = CurrentTheme.MutedText,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = footer
    })

    self.ScreenGui = screenGui
    self.Main = main
    self.TitleBar = titleBar
    self.Sidebar = sidebar
    self.SidebarList = sidebarList
    self.ContentArea = contentArea
    self.SearchBox = searchBox
    self.MinimizeBtn = minimizeBtn
    self.CloseBtn = closeBtn

    -- Dragging
    table.insert(self.Connections, titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            self.Dragging = true
            self.DragStart = input.Position
            self.StartPos = main.Position
        end
    end))

    table.insert(self.Connections, UserInputService.InputChanged:Connect(function(input)
        if self.Dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - self.DragStart
            main.Position = UDim2.new(
                self.StartPos.X.Scale,
                self.StartPos.X.Offset + delta.X,
                self.StartPos.Y.Scale,
                self.StartPos.Y.Offset + delta.Y
            )
        end
    end))

    table.insert(self.Connections, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            self.Dragging = false
        end
    end))

    -- Minimize
    table.insert(self.Connections, minimizeBtn.Activated:Connect(function()
        if self.Destroyed then return end
        self:ToggleMinimize()
    end))
    table.insert(self.Connections, minimizeBtn.MouseEnter:Connect(function()
        tween(minimizeBtn, 0.1, { TextColor3 = CurrentTheme.Text }, "QuadOut")
    end))
    table.insert(self.Connections, minimizeBtn.MouseLeave:Connect(function()
        tween(minimizeBtn, 0.1, { TextColor3 = CurrentTheme.MutedText }, "QuadOut")
    end))

    -- Close
    table.insert(self.Connections, closeBtn.Activated:Connect(function()
        if self.Destroyed then return end
        self:Close()
    end))
    table.insert(self.Connections, closeBtn.MouseEnter:Connect(function()
        tween(closeBtn, 0.1, { TextColor3 = CurrentTheme.Danger }, "QuadOut")
    end))
    table.insert(self.Connections, closeBtn.MouseLeave:Connect(function()
        tween(closeBtn, 0.1, { TextColor3 = CurrentTheme.MutedText }, "QuadOut")
    end))

    -- Search
    table.insert(self.Connections, searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        if self.Destroyed then return end
        self:FilterSearch(searchBox.Text)
    end))

    -- Entrance animation
    main.Size = UDim2.new(0, 580 * 0.9, 0, 420 * 0.9)
    main.BackgroundTransparency = 1
    tween(main, 0.4, {
        Size = UDim2.new(0, 580, 0, 420),
        BackgroundTransparency = 0
    }, "BackOut")

    table.insert(LibraryState.Windows, self)

    -- Auto Welcome tab (always first)
    task.defer(function()
        if self.Destroyed then return end
        self:NewWelcomeTab()
    end)

    return self
end

function Window:NewTab(name, icon)
    local tab = Tab.new(self, name, icon)
    table.insert(self.Tabs, tab)
    if not self.SelectedTab then
        self:SelectTab(tab)
    end
    return tab
end

function Window:NewWelcomeTab()
    local tab = self:NewTab("Welcome")
    local sec = tab:NewSection("Welcome")

    local displayName = "Player"
    pcall(function()
        displayName = LocalPlayer.DisplayName or LocalPlayer.Name or "Player"
    end)

    sec:NewLabel("Wazzup n welcome to Lumina UI @" .. displayName)
    sec:NewParagraph(
        "IP Address",
        "This is your IP Address if you were wondering (I'm not gonna show ur I'm jk)"
    )

    local countryLabel = sec:NewLabel("Oh hey! Detecting your country...")

    task.spawn(function()
        local country = "Unknown"
        local ok, result = pcall(function()
            local response = HttpService:GetAsync("http://ip-api.com/json/")
            local data = HttpService:JSONDecode(response)
            if data and data.country then
                return data.country
            end
            return nil
        end)

        if ok and result then
            country = result
        else
            pcall(function()
                local loc = game:GetService("LocalizationService")
                if loc and loc.RobloxLocaleId then
                    country = loc.RobloxLocaleId
                end
            end)
        end

        if countryLabel and not countryLabel.Destroyed and countryLabel.Label then
            countryLabel.Label.Text = 'Oh hey! You\'re in "' .. tostring(country) .. '" THATS COOL!'
        end
    end)

    sec:NewDivider()
    sec:NewParagraph(
        "Info",
        "You're running LuminaUI. Enjoy the clean interface — tabs, toggles, sliders, color pickers and more are ready to go."
    )

    return tab
end

function Window:SelectTab(tab)
    if self.SelectedTab == tab then return end
    if self.SelectedTab then
        self.SelectedTab:Deselect()
    end
    self.SelectedTab = tab
    tab:Select()
end

function Window:ToggleMinimize()
    if self.Destroyed then return end
    self.Minimized = not self.Minimized
    if self.Minimized then
        tween(self.Main, 0.3, { Size = UDim2.new(0, 580, 0, 44) }, "QuadOut")
        self.Sidebar.Visible = false
        self.ContentArea.Visible = false
        self.MinimizeBtn.Text = "□"
    else
        self.Sidebar.Visible = true
        self.ContentArea.Visible = true
        tween(self.Main, 0.3, { Size = UDim2.new(0, 580, 0, 420) }, "QuadOut")
        self.MinimizeBtn.Text = "─"
    end
end

function Window:FilterSearch(query)
    query = string.lower(query or "")
    for _, tab in ipairs(self.Tabs) do
        local tabMatch = query == "" or string.find(string.lower(tab.Name), query, 1, true)
        local anySectionMatch = false
        for _, sec in ipairs(tab.Sections) do
            local secMatch = query == "" or string.find(string.lower(sec.Name), query, 1, true)
            local anyCompMatch = false
            for _, comp in ipairs(sec.Components) do
                local nameMatch = query == "" or (comp.Name and string.find(string.lower(comp.Name), query, 1, true))
                if comp.SetVisible then
                    comp:SetVisible(nameMatch or secMatch or tabMatch)
                end
                if nameMatch then anyCompMatch = true end
            end
            if sec.Frame then
                sec.Frame.Visible = secMatch or anyCompMatch or tabMatch
            end
            if secMatch or anyCompMatch then anySectionMatch = true end
        end
        if tab.Button then
            tab.Button.Visible = tabMatch or anySectionMatch
        end
    end
end

function Window:Close()
    if self.Destroyed then return end
    self.Destroyed = true

    tween(self.Main, 0.25, {
        Size = UDim2.new(0, 580 * 0.85, 0, 420 * 0.85),
        BackgroundTransparency = 1
    }, "QuadIn", function()
        for _, tab in ipairs(self.Tabs) do
            tab:Destroy()
        end
        table.clear(self.Tabs)
        disconnectAll(self.Connections)
        if self.ScreenGui and self.ScreenGui.Parent then
            self.ScreenGui:Destroy()
        end
        for i, w in ipairs(LibraryState.Windows) do
            if w == self then
                table.remove(LibraryState.Windows, i)
                break
            end
        end
    end)
end

function Window:Destroy()
    self:Close()
end

-- ============================================================
-- LIBRARY PUBLIC API
-- ============================================================

LuminaUI.Version = "1.1.0"

function LuminaUI.CreateLib(title, themeName)
    if LibraryState.Destroyed then
        LibraryState.Destroyed = false
        LibraryState.Initialized = false
    end
    return Window.new(LuminaUI, title, themeName)
end

-- Alias some hubs prefer
LuminaUI.New = LuminaUI.CreateLib
LuminaUI.new = LuminaUI.CreateLib

function LuminaUI:SetTheme(themeTable)
    if type(themeTable) ~= "table" then return end
    for k, v in pairs(themeTable) do
        if CurrentTheme[k] ~= nil and typeof(v) == "Color3" then
            CurrentTheme[k] = v
        end
    end
end

function LuminaUI:GetTheme()
    return table.clone(CurrentTheme)
end

function LuminaUI:Init()
    if LibraryState.Initialized then return self end
    LibraryState.Initialized = true
    LibraryState.Destroyed = false

    ensureNotificationContainer()

    table.insert(LibraryState.GlobalConnections, Players.PlayerRemoving:Connect(function(p)
        if p == LocalPlayer then
            for _, w in ipairs(LibraryState.Windows) do
                if w.Close then pcall(function() w:Close() end) end
            end
        end
    end))

    return self
end

function LuminaUI:Destroy()
    if LibraryState.Destroyed then return end
    LibraryState.Destroyed = true

    for _, w in ipairs(LibraryState.Windows) do
        if w.Close then pcall(function() w:Close() end) end
    end
    table.clear(LibraryState.Windows)

    for _, n in ipairs(LibraryState.Notifications) do
        if n and n.Parent then pcall(function() n:Destroy() end) end
    end
    table.clear(LibraryState.Notifications)

    disconnectAll(LibraryState.GlobalConnections)

    if LibraryState.NotificationContainer and LibraryState.NotificationContainer.Parent then
        pcall(function() LibraryState.NotificationContainer.Parent:Destroy() end)
    end
    LibraryState.NotificationContainer = nil

    -- Clean leftover tooltips
    local parent = getGuiParent()
    if parent then
        local tip = parent:FindFirstChild("LuminaTooltip")
        if tip then pcall(function() tip:Destroy() end) end
    end

    LibraryState.Initialized = false
end

-- Common hub alias
function LuminaUI:Unload()
    self:Destroy()
end

-- Register into getgenv when available (hubs love this)
pcall(function()
    if getgenv then
        getgenv().LuminaUI = LuminaUI
        getgenv().Lumina = LuminaUI
    end
end)

return LuminaUI
