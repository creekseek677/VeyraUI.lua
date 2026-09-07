Veyra & Lumina

Two Roblox Luau UI libraries built around customizable interfaces, components, animations, notifications, themes, and lifecycle management.

This repository contains both Veyra UI and Lumina UI.

---

Contents

- "Veyra UI" (#veyra-ui)
  - "Creating a Window" (#creating-a-veyra-window)
  - "Tabs" (#veyra-tabs)
  - "Components" (#veyra-components)
  - "Convenience API" (#veyra-convenience-api)
  - "Notifications" (#veyra-notifications)
  - "Themes" (#veyra-themes)
  - "Animation System" (#veyra-animation-system)
  - "Settings & Persistence" (#veyra-settings--persistence)
  - "Intro & Key System" (#veyra-intro--key-system)
  - "Cleanup" (#veyra-cleanup)
- "Lumina UI" (#lumina-ui)
  - "Creating a Window" (#creating-a-lumina-window)
  - "Tabs & Sections" (#lumina-tabs--sections)
  - "Components" (#lumina-components)
  - "Notifications" (#lumina-notifications)
  - "Themes" (#lumina-themes)
  - "Animation System" (#lumina-animation-system)
  - "Intro & Key System" (#lumina-intro--key-system)
  - "Search" (#lumina-search)
  - "Cleanup" (#lumina-cleanup)
- "Veyra vs Lumina" (#veyra-vs-lumina)

---

Veyra UI

Veyra is the first library in this repository.

Its source exposes both a full configuration-based component API and a shorter convenience API for building interfaces.

Creating a Veyra Window

Veyra can create a window directly through "CreateWindow" or through the "New" helper.

local Veyra = loadstring(game:HttpGet("YOUR_VEYRA_SOURCE"))()

Veyra:Init()

local Window = Veyra:New("My Hub", "My subtitle")

"New" also accepts a configuration table.

local Window = Veyra:New({
    Title = "My Hub",
    Subtitle = "My subtitle"
})

Veyra automatically initializes when "New" is called before initialization.

---

Veyra Tabs

Tabs can be created through the convenience API:

local Tab = Window:Tab("Main")

The underlying API is:

local Tab = Window:CreateTab({
    Name = "Main"
})

Veyra tabs support:

- Sections
- Buttons
- Toggles
- Sliders
- Dropdowns
- Textboxes
- Keybinds
- Labels
- Dividers
- Color pickers

---

Veyra Components

The underlying tab API exposes:

Tab:CreateSection(config)
Tab:CreateButton(config)
Tab:CreateToggle(config)
Tab:CreateSlider(config)
Tab:CreateLabel(config)
Tab:CreateDropdown(config)
Tab:CreateTextbox(config)
Tab:CreateKeybind(config)
Tab:CreateDivider()
Tab:CreateColorPicker(config)

Components maintain their own cleanup state and can be destroyed independently.

For example, Veyra sliders expose:

Slider:Set(value)
Slider:Get()
Slider:Destroy()
Slider:IsDestroyed()

Dropdowns additionally expose:

Dropdown:Set(value)
Dropdown:Get()
Dropdown:Close()
Dropdown:SetOptions(options, keepValue)
Dropdown:Destroy()
Dropdown:IsDestroyed()

---

Veyra Convenience API

Veyra also provides shorter methods on tabs.

local Main = Window:Tab("Main")

Main:Section("General")

Main:Button("Test", function()
    print("Clicked")
end)

Main:Toggle("Enabled", false, function(value)
    print(value)
end)

Main:Slider("Power", 0, 100, 50, function(value)
    print(value)
end)

Main:Drop("Mode", {"A", "B", "C"}, function(value)
    print(value)
end)

Main:Key("Toggle Key", Enum.KeyCode.RightShift, function()
    print("Pressed")
end)

Main:Input("Name", "Enter a name...", function(value)
    print(value)
end)

Main:Label("Information", "Example label")

Main:Line()

Main:Color("Color", Color3.fromRGB(255, 255, 255), function(color)
    print(color)
end)

"ColorPicker" is also available as an alias:

Main:ColorPicker("Color", Color3.fromRGB(255, 255, 255), callback)

The convenience methods are wrappers around Veyra's underlying "Create*" component functions.

---

Veyra Window Actions

Windows support action buttons through:

Window:Action("Action", function()
    print("Action pressed")
end)

The underlying method is:

Window:AddAction({
    Name = "Action",
    Callback = function()
        print("Action pressed")
    end
})

Windows also expose tab selection and theme refreshing.

---

Veyra Notifications

Veyra has a dedicated notification manager.

Configuration-based notifications:

Veyra:Notify({
    Title = "Success",
    Description = "Operation completed.",
    Duration = 3,
    Type = "Success"
})

The library also accepts the shorter form:

Veyra:Notify("Hello", "This is a notification.", 3)

Supported notification types defined by the source include:

- "Info"
- "Success"
- "Warning"
- "Error"
- "Custom"

Notifications can include additional configuration such as:

- Icons/images
- Audio
- Custom bar colors
- Typewriter text
- Draggability
- Duration

Notifications have animated entry and exit behavior and can be individually closed.

Veyra also exposes:

Veyra:SetNotifDraggable(true)

---

Veyra Themes

Veyra includes built-in theme presets:

- "Dark"
- "Light"
- "Neon"
- "Cyan"
- "Glass"
- "Crimson"

Themes can be applied by name:

Veyra:ApplyTheme("Crimson")

Custom theme tables can also be supplied:

Veyra:SetTheme({
    Accent = Color3.fromRGB(255, 80, 120),
    Text = Color3.fromRGB(255, 255, 255)
})

The current theme can be retrieved with:

local Theme = Veyra:GetTheme()

The source also maintains theme listeners so active UI elements can refresh when the theme changes.

---

Veyra Background Images

Veyra's settings and window implementation support background images.

Window:SetBackgroundImage("123456789")

Background visibility can be controlled with:

Window:SetBackgroundImageEnabled(true)

Transparency can be changed with:

Window:SetBackgroundImageTransparency(0.3)

The source normalizes several Roblox image-reference formats, including numeric asset IDs and "rbxassetid://" references.

---

Veyra Animation System

Veyra exposes its animation system publicly:

Veyra.Animation

The animation system provides:

Veyra.Animation.Play(...)
Veyra.Animation.Spring(...)
Veyra.Animation.Shake(...)
Veyra.Animation.CancelAll(...)
Veyra.Animation.CancelOnObject(...)

The underlying animation implementation supports property interpolation and a scheduler-based update system.

Spring animations support configurable:

- "Stiffness"
- "Damping"
- "Mass"
- "OnComplete"

Shake animations support:

- "Magnitude"
- "Duration"
- "Frequency"
- "Property"
- "OnComplete"

The animation system is also responsible for many of the library's UI transitions.

---

Veyra Settings & Persistence

Veyra maintains a settings table containing configuration such as:

- Theme
- UI visibility
- UI toggle key
- Corner radius
- Background image
- Background image transparency
- Background image tint
- Outline color
- Custom image themes

Settings can be accessed through:

local Settings = Veyra:GetSettings()

They can be saved and loaded through:

Veyra:SaveSettings()
Veyra:LoadSettings()

The source uses JSON encoding and executor file functions when available.

---

Veyra UI Visibility

The window exposes:

Window:SetUIVisible(true)
Window:ToggleUIVisible()

The default toggle key is stored in Veyra's settings and defaults to "X".

The settings interface also exposes a keybind for changing this toggle.

---

Veyra Intro & Key System

Veyra can optionally display an intro:

Veyra:Init({
    Intro = true,
    IntroConfig = {
        Title = "Veyra",
        Subtitle = "Loading..."
    }
})

The library also exposes the key-system creator:

Veyra:CreateKeySystem(config)

The key-system implementation includes:

- Key input
- Validation
- Success/error notifications
- Get-key functionality
- Optional key link copying
- Failure callbacks
- Animated opening
- Animated closing
- Shake feedback for invalid keys

---

Veyra Cleanup

Veyra tracks windows, notifications, animations, theme listeners, connections, instances, and tasks.

Calling:

Veyra:Destroy()

cleans up active windows and notifications, cancels animations, clears theme listeners, and resets the initialization state.

You can check initialization with:

Veyra:IsInit()

---

Lumina UI

Lumina is the second UI library included in this repository.

The source is built around explicit "Window", "Tab", "Section", and "Component" objects.

Version: "1.2.0"

LuminaUI.Version

---

Creating a Lumina Window

Lumina exposes:

LuminaUI.CreateLib(title, themeName)

It also provides aliases:

LuminaUI.New
LuminaUI.new

Example:

local Lumina = loadstring(game:HttpGet("YOUR_LUMINA_SOURCE"))()

local Window = Lumina:CreateLib("My Hub")

A theme name can be supplied:

local Window = Lumina:CreateLib("My Hub", "CrimsonTheme")

---

Lumina Tabs & Sections

Lumina windows use explicit tab objects:

local Main = Window:NewTab("Main")

Tabs can contain sections:

local Section = Main:NewSection("General")

Lumina also creates a Welcome tab through:

Window:NewWelcomeTab()

Tabs can be selected directly:

Window:SelectTab(Main)

---

Lumina Components

Sections expose the following constructors:

Section:NewButton(...)
Section:NewToggle(...)
Section:NewSlider(...)
Section:NewDropdown(...)
Section:NewMultiDropdown(...)
Section:NewColorPicker(...)
Section:NewTextBox(...)
Section:NewKeybind(...)
Section:NewLabel(...)
Section:NewParagraph(...)
Section:NewDivider()

Example:

local Main = Window:NewTab("Main")
local Section = Main:NewSection("General")

local Toggle = Section:NewToggle(
    "Enabled",
    "Enable the feature",
    false,
    function(value)
        print(value)
    end
)

Lumina components inherit common component behavior.

Components support:

Component:SetVisible(true)
Component:Destroy()

Many stateful components additionally expose:

Component:Set(value)
Component:Get()

---

Lumina Toggle

Toggles maintain an internal boolean value.

Toggle:Set(true)

local value = Toggle:Get()

The component also provides animated visual changes when its state changes.

---

Lumina Slider

Sliders support:

- Minimum value
- Maximum value
- Step value
- Dragging
- Mouse input
- Touch input
- Callbacks

Example:

local Slider = Section:NewSlider(
    "Power",
    100,
    0,
    function(value)
        print(value)
    end,
    1
)

State can be changed with:

Slider:Set(50)

print(Slider:Get())

---

Lumina Dropdown

Lumina provides a standard dropdown:

local Dropdown = Section:NewDropdown(
    "Mode",
    {"One", "Two", "Three"},
    function(value)
        print(value)
    end
)

It supports:

Dropdown:Open()
Dropdown:Close()
Dropdown:Toggle()
Dropdown:Set(value)
Dropdown:Get()

The dropdown is scrollable when necessary.

---

Lumina Multi Dropdown

Lumina also includes a multi-selection dropdown:

local Multi = Section:NewMultiDropdown(
    "Features",
    {"A", "B", "C"},
    function(values)
        print(values)
    end
)

Selected values can be retrieved with:

local values = Multi:Get()

Multiple values can be assigned through:

Multi:Set({"A", "C"})

---

Lumina Color Picker

Lumina includes an HSV-style color picker with:

- Saturation/value selection
- Hue selection
- Color preview
- Hex display
- Mouse input
- Touch input

Example:

local Color = Section:NewColorPicker(
    "Color",
    Color3.fromRGB(255, 255, 255),
    function(color)
        print(color)
    end
)

State can be controlled through:

Color:Set(Color3.fromRGB(255, 0, 0))

local CurrentColor = Color:Get()

---

Lumina TextBox

Textboxes support:

local Input = Section:NewTextBox(
    "Username",
    "Enter username...",
    function(value)
        print(value)
    end
)

Values can be changed and retrieved through:

Input:Set("Example")
print(Input:Get())

---

Lumina Keybind

Lumina includes a keybind component:

local Key = Section:NewKeybind(
    "Toggle",
    Enum.KeyCode.RightShift,
    function()
        print("Pressed")
    end
)

The keybind enters a listening state when its key button is activated and can capture keyboard input.

---

Lumina Labels, Paragraphs & Dividers

Simple labels:

Section:NewLabel("Information")

Paragraphs:

Section:NewParagraph(
    "About",
    "This is a paragraph."
)

Dividers:

Section:NewDivider()

---

Lumina Notifications

Lumina has its own notification manager and notification container.

Lumina:Notify(
    "Success",
    "Operation completed.",
    3
)

Notifications support:

- Title
- Message
- Duration
- Animated entry
- Animated exit
- Theme updates
- Stacking
- Progress display

The notification implementation supports up to ten active notifications by default.

---

Lumina Themes

Lumina includes these default themes:

- "Lumina"
- "DarkTheme"
- "CrimsonTheme"
- "LightTheme"

Example:

Lumina:SetTheme("CrimsonTheme")

Custom theme values can also be supplied as a table containing "Color3" values:

Lumina:SetTheme({
    Background = Color3.fromRGB(20, 20, 20),
    Accent = Color3.fromRGB(255, 80, 80),
    Text = Color3.fromRGB(255, 255, 255)
})

The current theme can be retrieved with:

local Theme = Lumina:GetTheme()

Lumina keeps a registry of themed UI objects so theme changes can be applied to existing elements.

---

Lumina Animation System

Lumina contains its own custom tween implementation rather than relying solely on Roblox's standard tween workflow.

The animation system interpolates properties including:

- Numbers
- "Color3"
- "UDim"
- "UDim2"
- "Vector2"
- "Vector3"

Its easing implementation includes:

- Linear
- Quad
- Cubic
- Quart
- Quint
- Sine
- Circular
- Expo
- Back
- Elastic
- Bounce

Each family includes the relevant In, Out, and/or InOut variants.

Lumina also exposes animation timing presets:

Lumina.Animations.Fast
Lumina.Animations.Normal
Lumina.Animations.Slow
Lumina.Animations.Entrance

The source defines these as:

Fast     = 0.12
Normal   = 0.20
Slow     = 0.35
Entrance = 0.40

---

Lumina Intro & Key System

The intro is optional and disabled by default.

Lumina:Intro()

Or:

Lumina:Intro(
    true,
    "Lumina UI",
    "Loading..."
)

Lumina also provides an optional key system.

Lumina:KeySystem(
    {"key1", "key2"},
    function()
        print("Key accepted")
    end
)

The key-system configuration can include:

- Title
- Subtitle
- Note
- Placeholder
- "OnSuccess"
- "OnFail"
- "Callback"

The library's initialization sequence is:

Intro
  ↓
Key System
  ↓
Show Windows

---

Lumina Search

Lumina windows include search functionality through:

Window:FilterSearch(query)

The search checks tab names and section names and controls their visibility according to the query.

An empty query restores the normal tab visibility.

---

Lumina Touch Support

The source explicitly handles touch input for interactive components including:

- Sliders
- Color pickers

The window and notification layouts are also designed around the library's compact UI structure.

---

Lumina Cleanup

Lumina uses a component-based cleanup system.

Individual components track their connections and can be destroyed:

Component:Destroy()

The entire library can be destroyed with:

Lumina:Destroy()

"Unload" is an alias:

Lumina:Unload()

Destroying Lumina clears:

- Windows
- Notifications
- Themed-object registrations
- Global connections
- Notification UI
- Intro UI
- Key-system UI

---

Veyra vs Lumina

Both libraries provide the core building blocks required for constructing Roblox interfaces, but their source structures are different.

Area| Veyra UI| Lumina UI
Window creation| "New" / "CreateWindow"| "CreateLib" / "New" / "new"
Tab creation| "Tab" / "CreateTab"| "NewTab"
Sections| Yes| Yes
Buttons| Yes| Yes
Toggles| Yes| Yes
Sliders| Yes| Yes
Dropdown| Yes| Yes
Multi Dropdown| —| Yes
Color Picker| Yes| Yes
Textbox| Yes| Yes
Keybind| Yes| Yes
Labels| Yes| Yes
Paragraphs| —| Yes
Dividers| Yes| Yes
Notifications| Dedicated manager| Dedicated manager
Themes| Presets + custom tables| Presets + custom tables
Custom animation system| Yes| Yes
Spring animation| Yes| —
Shake animation| Yes| —
Typewriter utility| Yes| Yes
Intro| Yes| Yes
Key system| Yes| Yes
Search| —| Yes
Background images| Yes| —
Persistent settings| Yes| —
UI visibility controls| Yes| —
Window actions| Yes| —
Touch handling| Yes| Yes
Component visibility| Component-specific| Common component API
Global cleanup| Yes| Yes

API Style

Veyra exposes two layers of interaction.

The full API uses methods such as:

Tab:CreateToggle({...})
Tab:CreateSlider({...})
Tab:CreateDropdown({...})

while the wrapper API provides shorter calls:

Tab:Toggle(...)
Tab:Slider(...)
Tab:Drop(...)

Lumina instead centers its public construction API around explicit objects:

local Section = Window:NewTab("Main"):NewSection("General")
local Toggle = Section:NewToggle(...)

That distinction is an API structure difference, not a ranking of the libraries.

---

Source Files

The repository currently contains the two library implementations:

VeyraComplexte_Disassembly.lua
LuminaUI-4.lua

Veyra's source exposes its library through the returned "Library" object.

Lumina exposes the "LuminaUI" object and also assigns:

getgenv().LuminaUI = LuminaUI
getgenv().Lumina = LuminaUI

when "getgenv" is available.

---

License

No license information is defined by the two source files themselves.

Add a repository license separately if you intend to distribute either library under a specific license.

---

Credits

Veyra UI
Built around a configurable window/component system, custom animation engine, notification manager, themes, settings, and lifecycle handling.

Lumina UI
Built around explicit window/tab/section/component objects, custom animation, notifications, themes, intro/key-system flow, and search functionality.
