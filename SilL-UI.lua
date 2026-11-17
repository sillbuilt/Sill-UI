--[[
    SilL UI v2.0.0
    - Runtime themes, search, collapsible sections, tooltips, dialogs
    - Config profiles + auto save, built-in Settings tab
    - Resizable window, mobile toggle button, notification stack
]]

local Players      = game:GetService("Players")
local UIS          = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService  = game:GetService("HttpService")
local CoreGui      = game:GetService("CoreGui")
local GuiService   = game:GetService("GuiService")
local RunService   = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local MB1, TOUCH, MOVE = Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch, Enum.UserInputType.MouseMovement
local AUTO_Y, AUTO_X = Enum.AutomaticSize.Y, Enum.AutomaticSize.X

local SilL = {
    Version = "2.0.0",
    Flags = {},
    Themes = {},
    CurrentThemeName = "Default",
    _connections = {},
    _registry = {},
    _themeCallbacks = {},
    _guis = {},
    _binding = false,
}

--==================== THEMES ====================--
local function RGB(r, g, b) return Color3.fromRGB(r, g, b) end

SilL.Themes.Default = {
    Text = RGB(240,240,245), TextDim = RGB(160,160,172), Background = RGB(28,28,34),
    Topbar = RGB(22,22,27), Sidebar = RGB(32,32,39), Panel = RGB(24,24,30),
    Element = RGB(40,40,50), ElementHover = RGB(52,52,64), Stroke = RGB(60,60,74),
    Accent = RGB(94,122,255), AccentDim = RGB(70,92,200), AccentText = RGB(255,255,255),
    Success = RGB(80,200,120), Danger = RGB(224,96,96), Warning = RGB(240,184,80),
}

local function Derive(over)
    local t = table.clone(SilL.Themes.Default)
    for k, v in pairs(over) do t[k] = v end
    return t
end

SilL.Themes.Midnight = Derive{Background=RGB(14,14,20), Topbar=RGB(10,10,15), Sidebar=RGB(18,18,26), Panel=RGB(12,12,18), Element=RGB(24,24,34), ElementHover=RGB(34,34,48), Stroke=RGB(44,44,60), Accent=RGB(140,100,255), AccentDim=RGB(110,76,210)}
SilL.Themes.Ocean    = Derive{Background=RGB(16,26,36), Topbar=RGB(12,20,28), Sidebar=RGB(20,32,44), Panel=RGB(14,22,31), Element=RGB(26,40,54), ElementHover=RGB(34,52,70), Stroke=RGB(44,64,84), Accent=RGB(0,170,220), AccentDim=RGB(0,130,175)}
SilL.Themes.Rose     = Derive{Background=RGB(32,24,30), Topbar=RGB(26,19,24), Sidebar=RGB(38,28,35), Panel=RGB(28,21,26), Element=RGB(48,35,44), ElementHover=RGB(62,45,57), Stroke=RGB(78,56,70), Accent=RGB(240,98,146), AccentDim=RGB(200,72,118)}
SilL.Themes.Emerald  = Derive{Background=RGB(20,30,26), Topbar=RGB(15,23,20), Sidebar=RGB(24,36,31), Panel=RGB(17,26,22), Element=RGB(30,45,38), ElementHover=RGB(40,58,50), Stroke=RGB(52,74,64), Accent=RGB(46,204,113), AccentDim=RGB(36,160,90)}
SilL.Themes.Light    = Derive{Text=RGB(30,30,38), TextDim=RGB(110,110,125), Background=RGB(244,245,250), Topbar=RGB(232,234,242), Sidebar=RGB(236,238,245), Panel=RGB(226,228,238), Element=RGB(255,255,255), ElementHover=RGB(240,242,250), Stroke=RGB(208,210,222), Accent=RGB(80,110,245), AccentDim=RGB(60,90,210)}

local Theme = SilL.Themes.Default

--==================== UTILITIES ====================--
local function Connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(SilL._connections, c)
    return c
end

local function OnTheme(fn) table.insert(SilL._themeCallbacks, fn) end

local function BindTheme(obj, prop, key)
    obj[prop] = Theme[key]
    table.insert(SilL._registry, {obj, prop, key})
end

local function New(class, props, children)
    local obj = Instance.new(class)
    if obj:IsA("GuiObject") then obj.BorderSizePixel = 0 end
    local parent
    for k, v in pairs(props or {}) do
        if k == "Parent" then parent = v
        elseif k == "Theme" then for p, key in pairs(v) do BindTheme(obj, p, key) end
        else obj[k] = v end
    end
    for _, c in ipairs(children or {}) do c.Parent = obj end
    if parent then obj.Parent = parent end
    return obj
end

local function Corner(r) return New("UICorner", {CornerRadius = UDim.new(0, r or 6)}) end
local function Stroke(key) return New("UIStroke", {Theme = {Color = key or "Stroke"}, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}) end
local function Pad(t, b, l, r)
    return New("UIPadding", {PaddingTop = UDim.new(0, t or 0), PaddingBottom = UDim.new(0, b or 0), PaddingLeft = UDim.new(0, l or 0), PaddingRight = UDim.new(0, r or 0)})
end
local function List(pad, dir)
    return New("UIListLayout", {Padding = UDim.new(0, pad or 6), SortOrder = Enum.SortOrder.LayoutOrder, FillDirection = dir or Enum.FillDirection.Vertical})
end
local function Tween(obj, props, t, style)
    local tw = TweenService:Create(obj, TweenInfo.new(t or 0.18, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
    tw:Play()
    return tw
end
local function SafeCall(fn, ...)
    if typeof(fn) ~= "function" then return end
    local ok, err = pcall(fn, ...)
    if not ok then warn("[SilL] Callback error: " .. tostring(err)) end
end
local function Fire(fn, ...) task.spawn(SafeCall, fn, ...) end

local order = 0
local function NextOrder() order += 1 return order end

local function Text(props)
    props.BackgroundTransparency = 1
    props.Font = props.Font or Enum.Font.GothamMedium
    props.TextSize = props.TextSize or 13
    props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
    if not props.Theme then props.Theme = {TextColor3 = "Text"} end
    return New("TextLabel", props)
end

local function GetGuiParent()
    if gethui then
        local ok, hui = pcall(gethui)
        if ok and hui then return hui end
    end
    return CoreGui
end

local function MakeScreenGui(name)
    local gui = New("ScreenGui", {Name = name, ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999})
    if syn and syn.protect_gui then pcall(syn.protect_gui, gui) end
    pcall(function() gui.Parent = GetGuiParent() end)
    if not gui.Parent then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end
    table.insert(SilL._guis, gui)
    return gui
end

local function MakeDraggable(handle, target)
    local state = {moved = 0}
    local dragging, startInput, startPos
    Connect(handle.InputBegan, function(i)
        if i.UserInputType == MB1 or i.UserInputType == TOUCH then
            dragging, startInput, startPos, state.moved = true, i.Position, target.Position, 0
        end
    end)
    Connect(UIS.InputChanged, function(i)
        if dragging and (i.UserInputType == MOVE or i.UserInputType == TOUCH) then
            local d = i.Position - startInput
            state.moved = math.max(state.moved, d.Magnitude)
            target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    Connect(UIS.InputEnded, function(i)
        if i.UserInputType == MB1 or i.UserInputType == TOUCH then dragging = false end
    end)
    return state
end

local function BindDrag(obj, onMove)
    local active = false
    Connect(obj.InputBegan, function(i)
        if i.UserInputType == MB1 or i.UserInputType == TOUCH then active = true onMove(i.Position) end
    end)
    Connect(UIS.InputChanged, function(i)
        if active and (i.UserInputType == MOVE or i.UserInputType == TOUCH) then onMove(i.Position) end
    end)
    Connect(UIS.InputEnded, function(i)
        if i.UserInputType == MB1 or i.UserInputType == TOUCH then active = false end
    end)
end

local function ToColor(x)
    if typeof(x) == "Color3" then return x end
    if type(x) == "string" then
        local ok, c = pcall(Color3.fromHex, (x:gsub("#", "")))
        if ok then return c end
    end
    if type(x) == "table" then
        return Color3.fromRGB(x.R or x[1] or 255, x.G or x[2] or 255, x.B or x[3] or 255)
    end
end

--==================== FILESYSTEM ====================--
local FS = {}
function FS.Available()
    return typeof(writefile) == "function" and typeof(readfile) == "function" and typeof(isfile) == "function"
end
function FS.Safe(fn, ...)
    if typeof(fn) ~= "function" then return nil end
    local ok, res = pcall(fn, ...)
    if ok then return res end
end
function FS.EnsureFolder(path)
    if typeof(isfolder) ~= "function" or typeof(makefolder) ~= "function" then return end
    local acc = ""
    for part in string.gmatch(path, "[^/\\]+") do
        acc = (acc == "") and part or (acc .. "/" .. part)
        if not FS.Safe(isfolder, acc) then FS.Safe(makefolder, acc) end
    end
end

--==================== THEME API ====================--
function SilL:SetTheme(t)
    if type(t) == "string" then
        if not SilL.Themes[t] then warn("[SilL] Unknown theme: " .. t) return end
        Theme = SilL.Themes[t]
        SilL.CurrentThemeName = t
    elseif type(t) == "table" then
        Theme = Derive(t)
        SilL.CurrentThemeName = "Custom"
    else
        return
    end
    local reg = SilL._registry
    for i = #reg, 1, -1 do
        local e = reg[i]
        if e[1].Parent == nil then table.remove(reg, i) else e[1][e[2]] = Theme[e[3]] end
    end
    for _, fn in ipairs(SilL._themeCallbacks) do pcall(fn) end
end

function SilL:AddTheme(name, tbl) SilL.Themes[name] = Derive(tbl) end

--==================== NOTIFICATIONS ====================--
local NotifyHolder
local function GetNotifyHolder()
    if NotifyHolder and NotifyHolder.Parent then return NotifyHolder end
    local gui = MakeScreenGui("SilL_Notify")
    NotifyHolder = New("Frame", {
        AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16),
        Size = UDim2.new(0, 300, 1, -32), BackgroundTransparency = 1, Parent = gui,
    }, {
        New("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
            VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Right}),
    })
    return NotifyHolder
end

local TypeColor = {Info = "Accent", Success = "Success", Warning = "Warning", Error = "Danger"}

function SilL:Notify(opts)
    if type(opts) == "string" then opts = {Content = opts} end
    opts = opts or {}
    local holder = GetNotifyHolder()
    local duration = opts.Duration or 4
    local colorKey = TypeColor[opts.Type or "Info"] or "Accent"

    local wrap = New("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, BackgroundTransparency = 1, LayoutOrder = NextOrder(), Parent = holder})
    local card = New("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, Position = UDim2.new(1, 40, 0, 0),
        Theme = {BackgroundColor3 = "Panel"}, Parent = wrap,
    }, {Corner(8), Stroke(), Pad(10, 10, 12, 12), List(6)})

    local row = New("Frame", {Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, LayoutOrder = 1, Parent = card})
    if opts.Image then
        New("ImageLabel", {Size = UDim2.fromOffset(16, 16), Position = UDim2.new(0, 0, 0.5, -8), BackgroundTransparency = 1,
            Image = type(opts.Image) == "number" and ("rbxassetid://" .. opts.Image) or opts.Image, Theme = {ImageColor3 = colorKey}, Parent = row})
    else
        New("Frame", {Size = UDim2.fromOffset(8, 8), Position = UDim2.new(0, 2, 0.5, -4), Theme = {BackgroundColor3 = colorKey}, Parent = row}, {Corner(4)})
    end
    Text({Text = opts.Title or "Notification", Font = Enum.Font.GothamBold, Size = UDim2.new(1, -22, 1, 0), Position = UDim2.fromOffset(22, 0), Parent = row})
    Text({Text = opts.Content or "", Font = Enum.Font.Gotham, TextSize = 12, TextWrapped = true, Theme = {TextColor3 = "TextDim"},
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, LayoutOrder = 2, Parent = card})
    local barBg = New("Frame", {Size = UDim2.new(1, 0, 0, 3), Theme = {BackgroundColor3 = "Element"}, LayoutOrder = 3, Parent = card}, {Corner(2)})
    local fill = New("Frame", {Size = UDim2.fromScale(1, 1), Theme = {BackgroundColor3 = colorKey}, Parent = barBg}, {Corner(2)})

    local closed = false
    local function close()
        if closed then return end
        closed = true
        Tween(card, {Position = UDim2.new(1, 40, 0, 0)}, 0.25).Completed:Connect(function() wrap:Destroy() end)
    end
    card.InputBegan:Connect(function(i) if i.UserInputType == MB1 or i.UserInputType == TOUCH then close() end end)

    Tween(card, {Position = UDim2.new(0, 0, 0, 0)}, 0.3, Enum.EasingStyle.Back)
    Tween(fill, {Size = UDim2.fromScale(0, 1)}, duration, Enum.EasingStyle.Linear)
    task.delay(duration, close)
end

--==================== WINDOW ====================--
function SilL:CreateWindow(opts)
    opts = opts or {}
    if opts.Theme then SilL:SetTheme(opts.Theme) end

    local Window = {
        Name = opts.Name or "SilL UI",
        Tabs = {},
        CurrentTab = nil,
        Visible = true,
        Minimized = false,
        Flags = SilL.Flags,
    }

    local tk = opts.ToggleKey or Enum.KeyCode.RightShift
    if type(tk) == "string" then tk = Enum.KeyCode[tk] end
    Window.ToggleKey = tk

    local subtitle = opts.Subtitle or ("v" .. SilL.Version)
    local sz = opts.Size or UDim2.fromOffset(580, 420)
    local minSize = opts.MinSize or Vector2.new(440, 300)
    local sidebarW = opts.SidebarWidth or 160

    local config = opts.Config or opts.ConfigurationSaving or {}
    config.Folder = config.Folder or "SilL"
    config.FileName = config.FileName or "default"
    local configEnabled = (config.Enabled == true) and FS.Available()
    Window._autoSave = config.AutoSave == true

    local cam = workspace.CurrentCamera
    local baseScale = opts.Scale or ((UIS.TouchEnabled and cam and cam.ViewportSize.X < 900) and 0.75 or 1)

    local gui = MakeScreenGui("SilL_" .. HttpService:GenerateGUID(false):sub(1, 8))
    Window.Gui = gui

    -- Main frame
    local Main = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(sz.X.Offset, sz.Y.Offset), Theme = {BackgroundColor3 = "Background"},
        ClipsDescendants = true, Parent = gui,
    }, {Corner(10), Stroke()})
    local Scale = New("UIScale", {Scale = baseScale * 0.9, Parent = Main})

    -- Topbar
    local Topbar = New("Frame", {Size = UDim2.new(1, 0, 0, 42), Theme = {BackgroundColor3 = "Topbar"}, Parent = Main}, {Corner(10)})
    New("Frame", {Size = UDim2.new(1, 0, 0, 10), Position = UDim2.new(0, 0, 1, -10), Theme = {BackgroundColor3 = "Topbar"}, Parent = Topbar})
    New("Frame", {Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, 0), Theme = {BackgroundColor3 = "Stroke"}, Parent = Topbar})
    Text({Text = Window.Name, Font = Enum.Font.GothamBold, TextSize = 14, Size = UDim2.new(1, -120, 0, 16), Position = UDim2.fromOffset(14, 6), Parent = Topbar})
    Text({Text = subtitle, Font = Enum.Font.Gotham, TextSize = 11, Theme = {TextColor3 = "TextDim"}, Size = UDim2.new(1, -120, 0, 14), Position = UDim2.fromOffset(14, 22), Parent = Topbar})

    local function TopButton(txt, x)
        local b = New("TextButton", {
            Text = txt, Font = Enum.Font.GothamBold, TextSize = 16, AutoButtonColor = false,
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, x, 0.5, 0), Size = UDim2.fromOffset(28, 28),
            BackgroundTransparency = 1, Theme = {BackgroundColor3 = "Element", TextColor3 = "TextDim"}, Parent = Topbar,
        }, {Corner(6)})
        b.MouseEnter:Connect(function() Tween(b, {BackgroundTransparency = 0}) end)
        b.MouseLeave:Connect(function() Tween(b, {BackgroundTransparency = 1}) end)
        return b
    end
    local CloseBtn = TopButton("×", -8)
    local MinBtn = TopButton("–", -40)

    -- Body
    local Body = New("Frame", {Position = UDim2.fromOffset(0, 43), Size = UDim2.new(1, 0, 1, -43), BackgroundTransparency = 1, Parent = Main})

    local Sidebar = New("Frame", {Size = UDim2.new(0, sidebarW, 1, 0), Theme = {BackgroundColor3 = "Sidebar"}, Parent = Body}, {Corner(10)})
    New("Frame", {Size = UDim2.new(1, 0, 0, 10), Theme = {BackgroundColor3 = "Sidebar"}, Parent = Sidebar})
    New("Frame", {Size = UDim2.new(0, 10, 1, 0), Position = UDim2.new(1, -10, 0, 0), Theme = {BackgroundColor3 = "Sidebar"}, Parent = Sidebar})
    New("Frame", {Size = UDim2.new(0, 1, 1, 0), Position = UDim2.new(1, 0, 0, 0), Theme = {BackgroundColor3 = "Stroke"}, Parent = Sidebar})

    local showUser = opts.ShowUser ~= false
    local TabList = New("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, showUser and -56 or 0), BackgroundTransparency = 1, ScrollBarThickness = 0,
        CanvasSize = UDim2.new(), AutomaticCanvasSize = AUTO_Y, ScrollingDirection = Enum.ScrollingDirection.Y, Parent = Sidebar,
    }, {List(4), Pad(8, 8, 8, 8)})

    if showUser then
        local userBox = New("Frame", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -8), Size = UDim2.new(1, -16, 0, 40),
            Theme = {BackgroundColor3 = "Element"}, Parent = Sidebar}, {Corner(6)})
        local avatar = New("ImageLabel", {Size = UDim2.fromOffset(28, 28), Position = UDim2.new(0, 6, 0.5, -14), BackgroundTransparency = 1, Parent = userBox}, {New("UICorner", {CornerRadius = UDim.new(1, 0)})})
        task.spawn(function()
            local ok, img = pcall(Players.GetUserThumbnailAsync, Players, LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
            if ok then avatar.Image = img end
        end)
        Text({Text = LocalPlayer.DisplayName, TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(1, -46, 0, 15), Position = UDim2.fromOffset(40, 5), Parent = userBox})
        Text({Text = "@" .. LocalPlayer.Name, Font = Enum.Font.Gotham, TextSize = 10, TextTruncate = Enum.TextTruncate.AtEnd, Theme = {TextColor3 = "TextDim"}, Size = UDim2.new(1, -46, 0, 13), Position = UDim2.fromOffset(40, 21), Parent = userBox})
    end

    local Content = New("Frame", {Position = UDim2.fromOffset(sidebarW + 1, 0), Size = UDim2.new(1, -sidebarW - 1, 1, 0), BackgroundTransparency = 1, Parent = Body})
    local Header = New("Frame", {Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1, Parent = Content})
    local TabTitle = Text({Text = "", Font = Enum.Font.GothamBold, TextSize = 16, Size = UDim2.new(1, -200, 1, 0), Position = UDim2.fromOffset(16, 0), TextTruncate = Enum.TextTruncate.AtEnd, Parent = Header})
    local SearchWrap = New("Frame", {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(170, 28),
        Theme = {BackgroundColor3 = "Element"}, Parent = Header}, {Corner(6), Stroke()})
    local SearchBox = New("TextBox", {Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0), BackgroundTransparency = 1, Text = "",
        PlaceholderText = "Search...", Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false,
        Theme = {TextColor3 = "Text", PlaceholderColor3 = "TextDim"}, Parent = SearchWrap})
    local Pages = New("Frame", {Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 1, -46), BackgroundTransparency = 1, ClipsDescendants = true, Parent = Content})

    -- Resize handle
    local Resize = New("TextButton", {Text = "◢", Font = Enum.Font.Gotham, TextSize = 12, AutoButtonColor = false, BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -2, 1, -2), Size = UDim2.fromOffset(16, 16), Theme = {TextColor3 = "TextDim"}, Parent = Main})
    do
        local resizing, rStart, rSize, rPos
        Connect(Resize.InputBegan, function(i)
            if i.UserInputType == MB1 or i.UserInputType == TOUCH then
                resizing, rStart, rPos = true, i.Position, Main.Position
                rSize = Vector2.new(Main.Size.X.Offset, Main.Size.Y.Offset)
            end
        end)
        Connect(UIS.InputChanged, function(i)
            if resizing and (i.UserInputType == MOVE or i.UserInputType == TOUCH) then
                local d = (i.Position - rStart) / baseScale
                local nw, nh = math.max(minSize.X, rSize.X + d.X), math.max(minSize.Y, rSize.Y + d.Y)
                Main.Size = UDim2.fromOffset(nw, nh)
                Main.Position = rPos + UDim2.fromOffset((nw - rSize.X) / 2 * baseScale, (nh - rSize.Y) / 2 * baseScale)
            end
        end)
        Connect(UIS.InputEnded, function(i)
            if i.UserInputType == MB1 or i.UserInputType == TOUCH then resizing = false end
        end)
    end

    MakeDraggable(Topbar, Main)

    -- Tooltip
    local Tip = New("TextLabel", {Visible = false, AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), Font = Enum.Font.Gotham, TextSize = 12,
        ZIndex = 100, Theme = {BackgroundColor3 = "Topbar", TextColor3 = "Text"}, Parent = gui}, {Corner(4), Stroke(), Pad(4, 4, 8, 8)})
    Connect(RunService.RenderStepped, function()
        if Tip.Visible then
            local m = UIS:GetMouseLocation() - GuiService:GetGuiInset()
            Tip.Position = UDim2.fromOffset(m.X + 14, m.Y + 10)
        end
    end)
    local function AttachTooltip(obj, txt)
        obj.MouseEnter:Connect(function() Tip.Text = txt Tip.Visible = true end)
        obj.MouseLeave:Connect(function() Tip.Visible = false end)
    end

    --========== Window methods ==========--
    function Window:SetVisible(v)
        self.Visible = v
        Tip.Visible = false
        if v then
            Main.Visible = true
            Scale.Scale = baseScale * 0.92
            Tween(Scale, {Scale = baseScale}, 0.22, Enum.EasingStyle.Back)
        else
            Tween(Scale, {Scale = baseScale * 0.92}, 0.12).Completed:Connect(function()
                if not self.Visible then Main.Visible = false end
            end)
        end
    end
    function Window:Toggle() self:SetVisible(not self.Visible) end

    function Window:SetMinimized(v)
        if v == self.Minimized then return end
        self.Minimized = v
        if v then
            self._restore = Main.Size
            local h = Main.Size.Y.Offset
            Body.Visible, Resize.Visible = false, false
            Tween(Main, {Size = UDim2.fromOffset(Main.Size.X.Offset, 42), Position = Main.Position - UDim2.fromOffset(0, (h - 42) / 2 * baseScale)}, 0.22)
        else
            local h = self._restore.Y.Offset
            Tween(Main, {Size = self._restore, Position = Main.Position + UDim2.fromOffset(0, (h - 42) / 2 * baseScale)}, 0.22).Completed:Connect(function()
                if not self.Minimized then Body.Visible, Resize.Visible = true, true end
            end)
        end
    end

    function Window:SetToggleKey(k)
        if type(k) == "string" then
            local ok, kc = pcall(function() return Enum.KeyCode[k] end)
            if ok and kc then self.ToggleKey = kc end
        elseif typeof(k) == "EnumItem" then
            self.ToggleKey = k
        end
    end

    function Window:Notify(o) SilL:Notify(o) end

    function Window:Dialog(d)
        d = d or {}
        local overlay = New("TextButton", {Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
            BackgroundTransparency = 1, ZIndex = 50, Parent = Main})
        local box = New("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(300, 0),
            AutomaticSize = AUTO_Y, Theme = {BackgroundColor3 = "Panel"}, Parent = overlay}, {Corner(10), Stroke(), Pad(16, 16, 16, 16), List(10)})
        local bScale = New("UIScale", {Scale = 0.9, Parent = box})
        Text({Text = d.Title or "Confirm", Font = Enum.Font.GothamBold, TextSize = 15, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 1, Parent = box})
        Text({Text = d.Content or "", Font = Enum.Font.Gotham, TextSize = 12, TextWrapped = true, Theme = {TextColor3 = "TextDim"},
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, LayoutOrder = 2, Parent = box})
        local row = New("Frame", {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 3, Parent = box}, {
            New("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
                Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}),
        })
        local function close()
            Tween(overlay, {BackgroundTransparency = 1}, 0.15)
            Tween(bScale, {Scale = 0.9}, 0.15)
            task.delay(0.15, function() overlay:Destroy() end)
        end
        for i, b in ipairs(d.Buttons or {{Name = "OK"}}) do
            local primary = (i == 1)
            local btn = New("TextButton", {Text = b.Name or "OK", Font = Enum.Font.GothamMedium, TextSize = 12, AutoButtonColor = false,
                AutomaticSize = AUTO_X, Size = UDim2.fromOffset(0, 30), LayoutOrder = i,
                Theme = primary and {BackgroundColor3 = "Accent", TextColor3 = "AccentText"} or {BackgroundColor3 = "Element", TextColor3 = "Text"},
                Parent = row}, {Corner(6), Pad(0, 0, 14, 14)})
            btn.Activated:Connect(function() close() Fire(b.Callback) end)
        end
        Tween(overlay, {BackgroundTransparency = 0.45}, 0.15)
        Tween(bScale, {Scale = 1}, 0.2, Enum.EasingStyle.Back)
    end

    function Window:Destroy() gui:Destroy() end

    --========== Config ==========--
    local function cfgPath(n) return config.Folder .. "/" .. (n or config.FileName) .. ".json" end

    function Window:SaveConfig(n)
        if not configEnabled then return false end
        local data = {}
        for flag, el in pairs(SilL.Flags) do
            local v = el.Value
            if typeof(v) == "Color3" then v = "#" .. v:ToHex() end
            data[flag] = v
        end
        FS.EnsureFolder(config.Folder)
        return pcall(writefile, cfgPath(n), HttpService:JSONEncode(data))
    end

    function Window:LoadConfig(n)
        if not configEnabled then return false end
        local path = cfgPath(n)
        if not FS.Safe(isfile, path) then return false end
        local raw = FS.Safe(readfile, path)
        if not raw then return false end
        local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
        if not ok or type(data) ~= "table" then return false end
        for flag, v in pairs(data) do
            local el = SilL.Flags[flag]
            if el and el.Set then task.spawn(pcall, el.Set, el, v) end
        end
        return true
    end

    function Window:ListConfigs()
        local out = {}
        if configEnabled and typeof(listfiles) == "function" then
            FS.EnsureFolder(config.Folder)
            for _, f in ipairs(FS.Safe(listfiles, config.Folder) or {}) do
                local name = tostring(f):match("([^/\\]+)%.json$")
                if name then table.insert(out, name) end
            end
        end
        table.sort(out)
        return out
    end

    function Window:DeleteConfig(n)
        if configEnabled and typeof(delfile) == "function" then FS.Safe(delfile, cfgPath(n)) end
    end

    function Window:_queueSave()
        if not self._autoSave or self._saveQueued then return end
        self._saveQueued = true
        task.delay(1, function() self._saveQueued = false self:SaveConfig() end)
    end

    local function RegisterFlag(api, flag)
        if flag then api.Flag = flag SilL.Flags[flag] = api end
    end
    local function Changed(api)
        if api.Flag then Window:_queueSave() end
    end

    --========== Element factory (used by Tab & Section) ==========--
    local function H(base, desc) return desc and (base + 16) or base end

    local function BuildElements(target, container, Tab)

        local function Base(height, name, o)
            o = o or {}
            local frame = New("Frame", {Size = UDim2.new(1, 0, 0, height), Theme = {BackgroundColor3 = "Element"},
                LayoutOrder = NextOrder(), Parent = container}, {Corner(6), Stroke()})
            local api = {Frame = frame, Name = name or "", Type = "Element"}
            local lockOverlay
            function api:SetVisible(v) api._hidden = not v frame.Visible = v end
            function api:Destroy()
                local idx = table.find(Tab.Elements, api)
                if idx then table.remove(Tab.Elements, idx) end
                if api.Flag then SilL.Flags[api.Flag] = nil end
                frame:Destroy()
            end
            function api:Lock(reason)
                api.Locked = true
                if lockOverlay then lockOverlay.Text = reason or "Locked" return end
                lockOverlay = New("TextButton", {Text = reason or "Locked", AutoButtonColor = false, Size = UDim2.fromScale(1, 1),
                    BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, TextColor3 = Color3.new(1, 1, 1),
                    Font = Enum.Font.GothamMedium, TextSize = 12, ZIndex = 10, Parent = frame}, {Corner(6)})
            end
            function api:Unlock()
                api.Locked = false
                if lockOverlay then lockOverlay:Destroy() lockOverlay = nil end
            end
            if o.Tooltip then AttachTooltip(frame, o.Tooltip) end
            if not o.NoHover then
                frame.MouseEnter:Connect(function() Tween(frame, {BackgroundColor3 = Theme.ElementHover}) end)
                frame.MouseLeave:Connect(function() Tween(frame, {BackgroundColor3 = Theme.Element}) end)
            end
            table.insert(Tab.Elements, api)
            return frame, api
        end

        local function Header(frame, name, desc, rightPad)
            local w = -(rightPad or 12) - 12
            local title = Text({Text = name, Size = UDim2.new(1, w, 0, 18), Position = UDim2.fromOffset(12, 9),
                TextTruncate = Enum.TextTruncate.AtEnd, Parent = frame})
            local d
            if desc then
                d = Text({Text = desc, Font = Enum.Font.Gotham, TextSize = 11, Theme = {TextColor3 = "TextDim"},
                    Size = UDim2.new(1, w, 0, 14), Position = UDim2.fromOffset(12, 28), TextTruncate = Enum.TextTruncate.AtEnd, Parent = frame})
            end
            return title, d
        end

        local function ClickArea(frame, height)
            return New("TextButton", {Text = "", BackgroundTransparency = 1, AutoButtonColor = false,
                Size = height and UDim2.new(1, 0, 0, height) or UDim2.fromScale(1, 1), Parent = frame})
        end

        -- Section
        function target:CreateSection(name, o)
            o = o or {}
            local holder = New("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, BackgroundTransparency = 1,
                LayoutOrder = NextOrder(), Parent = container}, {List(6)})
            local head = New("TextButton", {Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 0, Parent = holder})
            local title = Text({Text = string.upper(name or "Section"), Font = Enum.Font.GothamBold, TextSize = 11,
                Theme = {TextColor3 = "TextDim"}, Size = UDim2.new(1, -24, 1, 0), Position = UDim2.fromOffset(2, 0), Parent = head})
            local arrow = Text({Text = "›", Font = Enum.Font.GothamBold, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center,
                Theme = {TextColor3 = "TextDim"}, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -4, 0.5, 0),
                Size = UDim2.fromOffset(16, 16), Rotation = 90, Parent = head})
            local body = New("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, BackgroundTransparency = 1, LayoutOrder = 1, Parent = holder}, {List(6)})

            local Section = {Frame = holder, Collapsed = false}
            BuildElements(Section, body, Tab)
            function Section:Set(n) title.Text = string.upper(n) end
            function Section:SetCollapsed(c)
                Section.Collapsed = c
                body.Visible = not c
                Tween(arrow, {Rotation = c and 0 or 90}, 0.15)
            end
            head.Activated:Connect(function() Section:SetCollapsed(not Section.Collapsed) end)
            Section:SetCollapsed(o.Collapsed == true)
            return Section
        end

        -- Divider
        function target:CreateDivider()
            local f = New("Frame", {Size = UDim2.new(1, 0, 0, 1), Theme = {BackgroundColor3 = "Stroke"}, LayoutOrder = NextOrder(), Parent = container})
            return {Frame = f, Destroy = function() f:Destroy() end}
        end

        -- Label
        function target:CreateLabel(txt, o)
            o = type(o) == "table" and o or {}
            o.NoHover = true
            local frame, api = Base(32, txt, o)
            api.Type = "Label"
            local lbl = Text({Text = txt or "", Size = UDim2.new(1, -24, 1, 0), Position = UDim2.fromOffset(12, 0), TextWrapped = true, Parent = frame})
            if o.Color then lbl.TextColor3 = o.Color end
            function api:Set(t) lbl.Text = t api.Name = t end
            return api
        end

        -- Paragraph
        function target:CreateParagraph(p)
            p = p or {}
            local frame, api = Base(0, p.Title, {NoHover = true, Tooltip = p.Tooltip})
            api.Type = "Paragraph"
            frame.Size = UDim2.new(1, 0, 0, 0)
            frame.AutomaticSize = AUTO_Y
            Pad(10, 10, 12, 12).Parent = frame
            List(4).Parent = frame
            local t = Text({Text = p.Title or "Paragraph", Font = Enum.Font.GothamBold, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 1, Parent = frame})
            local c = Text({Text = p.Content or "", Font = Enum.Font.Gotham, TextSize = 12, TextWrapped = true, Theme = {TextColor3 = "TextDim"},
                Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, LayoutOrder = 2, Parent = frame})
            function api:Set(np)
                np = np or {}
                if np.Title then t.Text = np.Title api.Name = np.Title end
                if np.Content then c.Text = np.Content end
            end
            return api
        end

        -- Button
        function target:CreateButton(b)
            b = b or {}
            local frame, api = Base(H(36, b.Description), b.Name, b)
            api.Type = "Button"
            local title = Header(frame, b.Name or "Button", b.Description, 30)
            Text({Text = "›", Font = Enum.Font.GothamBold, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, Theme = {TextColor3 = "TextDim"},
                AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(16, 16), Parent = frame})
            ClickArea(frame).Activated:Connect(function()
                if api.Locked then return end
                Tween(frame, {BackgroundColor3 = Theme.AccentDim}, 0.08).Completed:Connect(function()
                    Tween(frame, {BackgroundColor3 = Theme.ElementHover}, 0.25)
                end)
                Fire(b.Callback)
            end)
            function api:Set(n) title.Text = n api.Name = n end
            return api
        end

        -- Toggle
        function target:CreateToggle(t)
            t = t or {}
            local frame, api = Base(H(38, t.Description), t.Name, t)
            api.Type = "Toggle"
            Header(frame, t.Name or "Toggle", t.Description, 56)
            local sw = New("Frame", {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(40, 20), Parent = frame},
                {New("UICorner", {CornerRadius = UDim.new(1, 0)}), Stroke()})
            local knob = New("Frame", {AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(14, 14), Position = UDim2.new(0, 3, 0.5, 0), Parent = sw},
                {New("UICorner", {CornerRadius = UDim.new(1, 0)})})
            api.Value = t.CurrentValue == true
            api.CurrentValue = api.Value
            local function render(anim)
                local tm = anim and 0.18 or 0
                Tween(sw, {BackgroundColor3 = api.Value and Theme.Accent or Theme.Panel}, tm)
                Tween(knob, {Position = api.Value and UDim2.new(1, -17, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
                    BackgroundColor3 = api.Value and Theme.AccentText or Theme.TextDim}, tm)
            end
            OnTheme(function() render(false) end)
            function api:Set(v, silent)
                api.Value = v and true or false
                api.CurrentValue = api.Value
                render(true)
                if not silent then Fire(t.Callback, api.Value) end
                Changed(api)
            end
            ClickArea(frame).Activated:Connect(function()
                if not api.Locked then api:Set(not api.Value) end
            end)
            render(false)
            RegisterFlag(api, t.Flag)
            return api
        end

        -- Slider
        function target:CreateSlider(s)
            s = s or {}
            local range = s.Range or {0, 100}
            local min, max = range[1], range[2]
            local inc = s.Increment or (s.Rounding and 10 ^ (-s.Rounding)) or 1
            local decimals = 0
            do
                local str = tostring(inc)
                local dot = str:find("%.")
                if dot then decimals = #str - dot end
            end
            local suffix = s.Suffix and (" " .. s.Suffix) or ""
            local frame, api = Base(H(52, s.Description), s.Name, s)
            api.Type = "Slider"
            Header(frame, s.Name or "Slider", s.Description, 92)
            local box = New("TextBox", {AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 7), Size = UDim2.fromOffset(76, 22),
                Font = Enum.Font.GothamMedium, TextSize = 12, ClearTextOnFocus = false, Text = "",
                Theme = {BackgroundColor3 = "Panel", TextColor3 = "Text"}, Parent = frame}, {Corner(4), Stroke()})
            local bar = New("Frame", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -12), Size = UDim2.new(1, -24, 0, 6),
                Theme = {BackgroundColor3 = "Panel"}, Parent = frame}, {Corner(3)})
            local fill = New("Frame", {Size = UDim2.fromScale(0, 1), Theme = {BackgroundColor3 = "Accent"}, Parent = bar}, {Corner(3)})
            local dot = New("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(12, 12),
                BackgroundColor3 = Color3.new(1, 1, 1), Parent = bar}, {New("UICorner", {CornerRadius = UDim.new(1, 0)})})
            local hit = New("TextButton", {Text = "", BackgroundTransparency = 1, AutoButtonColor = false, AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 22), Parent = bar})

            local function fmt(v) return string.format("%." .. decimals .. "f", v) end
            local function snap(v)
                v = math.clamp(v, min, max)
                v = min + math.floor((v - min) / inc + 0.5) * inc
                return math.clamp(tonumber(fmt(v)), min, max)
            end
            function api:Set(v, silent)
                v = snap(tonumber(v) or min)
                local changedVal = v ~= api.Value
                api.Value = v
                api.CurrentValue = v
                local a = (max == min) and 0 or (v - min) / (max - min)
                Tween(fill, {Size = UDim2.fromScale(a, 1)}, 0.08)
                Tween(dot, {Position = UDim2.fromScale(a, 0.5)}, 0.08)
                box.Text = fmt(v) .. suffix
                if changedVal and not silent then Fire(s.Callback, v) end
                if changedVal then Changed(api) end
            end
            BindDrag(hit, function(pos)
                if api.Locked then return end
                local a = math.clamp((pos.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
                api:Set(min + a * (max - min))
            end)
            box.FocusLost:Connect(function()
                local n = tonumber((box.Text:gsub("[^%d%.%-]", "")))
                if n and not api.Locked then api:Set(n) else box.Text = fmt(api.Value) .. suffix end
            end)
            api:Set(s.CurrentValue or min, true)
            RegisterFlag(api, s.Flag)
            return api
        end

        -- Input
        function target:CreateInput(inp)
            inp = inp or {}
            local frame, api = Base(H(38, inp.Description), inp.Name, inp)
            api.Type = "Input"
            Header(frame, inp.Name or "Input", inp.Description, 170)
            local box = New("TextBox", {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(150, 24),
                Font = Enum.Font.Gotham, TextSize = 12, ClearTextOnFocus = false, ClipsDescendants = true,
                Text = tostring(inp.CurrentValue or ""), PlaceholderText = inp.Placeholder or inp.PlaceholderText or "Type here...",
                TextXAlignment = Enum.TextXAlignment.Left,
                Theme = {BackgroundColor3 = "Panel", TextColor3 = "Text", PlaceholderColor3 = "TextDim"}, Parent = frame}, {Corner(4), Pad(0, 0, 8, 8)})
            local st = Stroke()
            st.Parent = box
            api.Value = box.Text
            api.CurrentValue = api.Value
            if inp.NumbersOnly then
                box:GetPropertyChangedSignal("Text"):Connect(function()
                    local f = box.Text:gsub("[^%d%.%-]", "")
                    if f ~= box.Text then box.Text = f end
                end)
            end
            local function out() return inp.NumbersOnly and tonumber(api.Value) or api.Value end
            box.Focused:Connect(function() Tween(st, {Color = Theme.Accent}) end)
            box.FocusLost:Connect(function(enter)
                Tween(st, {Color = Theme.Stroke})
                if api.Locked then return end
                api.Value = box.Text
                api.CurrentValue = api.Value
                Fire(inp.Callback, out(), enter)
                if inp.ClearOnFocusLost or inp.RemoveTextAfterFocusLost then box.Text = "" end
                Changed(api)
            end)
            function api:Set(v, silent)
                box.Text = tostring(v or "")
                api.Value = box.Text
                api.CurrentValue = api.Value
                if not silent then Fire(inp.Callback, out(), false) end
                Changed(api)
            end
            RegisterFlag(api, inp.Flag)
            return api
        end

        -- Dropdown
        function target:CreateDropdown(dd)
            dd = dd or {}
            local multi = dd.MultipleOptions or dd.Multi
            local options = dd.Options or {}
            local headH = H(38, dd.Description)
            local frame, api = Base(headH, dd.Name, dd)
            api.Type = "Dropdown"
            frame.ClipsDescendants = true
            Header(frame, dd.Name or "Dropdown", dd.Description, 180)
            local selLabel = Text({AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -32, 0, 9), Size = UDim2.fromOffset(145, 18),
                TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd, TextSize = 12,
                Theme = {TextColor3 = "TextDim"}, Text = "", Parent = frame})
            local arrow = Text({Text = "›", Font = Enum.Font.GothamBold, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center,
                Theme = {TextColor3 = "TextDim"}, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10),
                Size = UDim2.fromOffset(16, 16), Rotation = 90, Parent = frame})
            local headBtn = ClickArea(frame, headH)
            local search = New("TextBox", {Position = UDim2.fromOffset(10, headH), Size = UDim2.new(1, -20, 0, 26), Text = "", PlaceholderText = "Search...",
                Font = Enum.Font.Gotham, TextSize = 12, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left,
                Theme = {BackgroundColor3 = "Panel", TextColor3 = "Text", PlaceholderColor3 = "TextDim"}, Parent = frame}, {Corner(4), Stroke(), Pad(0, 0, 8, 8)})
            local listFrame = New("ScrollingFrame", {Position = UDim2.fromOffset(10, headH + 32), Size = UDim2.new(1, -20, 0, 0), BackgroundTransparency = 1,
                ScrollBarThickness = 2, CanvasSize = UDim2.new(), AutomaticCanvasSize = AUTO_Y, Theme = {ScrollBarImageColor3 = "Stroke"}, Parent = frame}, {List(4)})

            local open = false
            local buttons = {}

            if multi then
                local cur = dd.CurrentOption
                api.Value = type(cur) == "table" and table.clone(cur) or (cur and {cur} or {})
            else
                local cur = dd.CurrentOption
                api.Value = type(cur) == "table" and cur[1] or cur
            end
            api.CurrentValue = api.Value

            local function isSel(opt)
                if multi then return table.find(api.Value, opt) ~= nil end
                return api.Value == opt
            end
            local function updateLabel()
                if multi then
                    selLabel.Text = (#api.Value == 0) and "None" or table.concat(api.Value, ", ")
                else
                    selLabel.Text = api.Value and tostring(api.Value) or "None"
                end
            end
            local function renderOpts()
                for opt, b in pairs(buttons) do
                    local sel = isSel(opt)
                    b.BackgroundColor3 = sel and Theme.Accent or Theme.Panel
                    b.TextColor3 = sel and Theme.AccentText or Theme.Text
                end
            end
            local function resize(anim)
                local count = 0
                for _, b in pairs(buttons) do if b.Visible then count += 1 end end
                local lh = math.min(count, 5) * 30
                listFrame.Size = UDim2.new(1, -20, 0, lh)
                Tween(frame, {Size = UDim2.new(1, 0, 0, open and (headH + 32 + lh + 6) or headH)}, anim and 0.2 or 0)
                Tween(arrow, {Rotation = open and -90 or 90}, anim and 0.2 or 0)
            end
            local function emit()
                Fire(dd.Callback, multi and table.clone(api.Value) or api.Value)
                Changed(api)
            end
            local function build()
                for _, b in pairs(buttons) do b:Destroy() end
                buttons = {}
                for i, opt in ipairs(options) do
                    local b = New("TextButton", {Text = tostring(opt), Size = UDim2.new(1, -4, 0, 26), AutoButtonColor = false,
                        Font = Enum.Font.Gotham, TextSize = 12, LayoutOrder = i, Parent = listFrame}, {Corner(4)})
                    buttons[opt] = b
                    b.Activated:Connect(function()
                        if api.Locked then return end
                        if multi then
                            local idx = table.find(api.Value, opt)
                            if idx then table.remove(api.Value, idx) else table.insert(api.Value, opt) end
                        else
                            api.Value = opt
                            open = false
                        end
                        api.CurrentValue = api.Value
                        renderOpts() updateLabel() resize(true)
                        emit()
                    end)
                end
                renderOpts()
                resize(false)
            end
            OnTheme(renderOpts)

            headBtn.Activated:Connect(function()
                if api.Locked then return end
                open = not open
                if open then search.Text = "" end
                resize(true)
            end)
            search:GetPropertyChangedSignal("Text"):Connect(function()
                local q = search.Text:lower()
                for opt, b in pairs(buttons) do
                    b.Visible = (q == "") or (tostring(opt):lower():find(q, 1, true) ~= nil)
                end
                resize(false)
            end)

            function api:Set(v, silent)
                if multi then
                    api.Value = type(v) == "table" and table.clone(v) or (v and {v} or {})
                else
                    api.Value = type(v) == "table" and v[1] or v
                end
                api.CurrentValue = api.Value
                renderOpts() updateLabel()
                if not silent then emit() end
            end
            function api:Refresh(newOpts, keepSelection)
                options = newOpts or {}
                if keepSelection then
                    if multi then
                        local kept = {}
                        for _, v in ipairs(api.Value) do if table.find(options, v) then table.insert(kept, v) end end
                        api.Value = kept
                    elseif not table.find(options, api.Value) then
                        api.Value = nil
                    end
                else
                    api.Value = multi and {} or nil
                end
                api.CurrentValue = api.Value
                build() updateLabel()
            end
            function api:Add(opt) table.insert(options, opt) build() end
            function api:Remove(opt)
                local idx = table.find(options, opt)
                if idx then table.remove(options, idx) api:Refresh(options, true) end
            end
            function api:SetOpen(v) open = v resize(true) end

            build()
            updateLabel()
            RegisterFlag(api, dd.Flag)
            return api
        end

        -- Keybind
        function target:CreateKeybind(kb)
            kb = kb or {}
            local frame, api = Base(H(38, kb.Description), kb.Name, kb)
            api.Type = "Keybind"
            Header(frame, kb.Name or "Keybind", kb.Description, 110)
            local keyBtn = New("TextButton", {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(0, 24),
                AutomaticSize = AUTO_X, Font = Enum.Font.GothamMedium, TextSize = 12, AutoButtonColor = false,
                Theme = {BackgroundColor3 = "Panel", TextColor3 = "Text"}, Parent = frame}, {Corner(4), Stroke(), Pad(0, 0, 10, 10)})

            local function keyName(k)
                if typeof(k) == "EnumItem" then return k.Name end
                return k
            end
            api.Value = keyName(kb.CurrentKeybind or kb.Default) or "None"
            api.CurrentValue = api.Value
            keyBtn.Text = api.Value
            local binding = false

            local function matches(i)
                return api.Value ~= "None" and (i.KeyCode.Name == api.Value or i.UserInputType.Name == api.Value)
            end
            function api:Set(k, silent)
                api.Value = keyName(k) or "None"
                api.CurrentValue = api.Value
                keyBtn.Text = api.Value
                if not silent then Fire(kb.CallbackKeyChange, api.Value) end
                Changed(api)
            end
            keyBtn.Activated:Connect(function()
                if api.Locked then return end
                binding = true
                SilL._binding = true
                keyBtn.Text = "..."
            end)
            Connect(UIS.InputBegan, function(i, gp)
                if binding then
                    local name
                    if i.UserInputType == Enum.UserInputType.Keyboard then
                        name = i.KeyCode.Name
                    elseif i.UserInputType == Enum.UserInputType.MouseButton2 or i.UserInputType == Enum.UserInputType.MouseButton3 then
                        name = i.UserInputType.Name
                    else
                        return
                    end
                    if name == "Escape" or name == "Backspace" then name = "None" end
                    binding = false
                    task.defer(function() SilL._binding = false end)
                    api:Set(name)
                    return
                end
                if gp or api.Locked or not matches(i) then return end
                if kb.HoldToInteract then
                    api.Holding = true
                    Fire(kb.Callback, true)
                else
                    Fire(kb.Callback)
                end
            end)
            Connect(UIS.InputEnded, function(i)
                if kb.HoldToInteract and api.Holding and matches(i) then
                    api.Holding = false
                    Fire(kb.Callback, false)
                end
            end)
            RegisterFlag(api, kb.Flag)
            return api
        end

        -- Color Picker
        function target:CreateColorPicker(cp)
            cp = cp or {}
            local headH = H(38, cp.Description)
            local frame, api = Base(headH, cp.Name, cp)
            api.Type = "ColorPicker"
            frame.ClipsDescendants = true
            Header(frame, cp.Name or "Color", cp.Description, 60)
            local preview = New("TextButton", {Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -12, 0, (headH - 22) / 2), Size = UDim2.fromOffset(36, 22), Parent = frame}, {Corner(4), Stroke()})
            local headBtn = ClickArea(frame, headH)
            headBtn.Size = UDim2.new(1, -60, 0, headH)

            local py = headH + 4
            local sv = New("TextButton", {Text = "", AutoButtonColor = false, Position = UDim2.fromOffset(12, py), Size = UDim2.new(1, -170, 0, 120), Parent = frame}, {Corner(4)})
            New("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), Parent = sv}, {Corner(4),
                New("UIGradient", {Transparency = NumberSequence.new(0, 1)})})
            New("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), Parent = sv}, {Corner(4),
                New("UIGradient", {Transparency = NumberSequence.new(1, 0), Rotation = 90})})
            local svCursor = New("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 3, Parent = sv},
                {New("UICorner", {CornerRadius = UDim.new(1, 0)}), New("UIStroke", {Color = Color3.new(0, 0, 0), Thickness = 1})})

            local keys = {}
            for i = 0, 6 do table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV((i / 6) % 1, 1, 1))) end
            local hueBar = New("TextButton", {Text = "", AutoButtonColor = false, Position = UDim2.new(1, -150, 0, py), Size = UDim2.fromOffset(16, 120),
                BackgroundColor3 = Color3.new(1, 1, 1), Parent = frame}, {Corner(4), New("UIGradient", {Color = ColorSequence.new(keys), Rotation = 90})})
            local hueCursor = New("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(1, 4, 0, 4), BackgroundColor3 = Color3.new(1, 1, 1), Parent = hueBar},
                {Corner(2), New("UIStroke", {Color = Color3.new(0, 0, 0), Thickness = 1})})

            local function mkBox(y, ph)
                return New("TextBox", {Position = UDim2.new(1, -124, 0, y), Size = UDim2.fromOffset(112, 24), Font = Enum.Font.GothamMedium, TextSize = 12,
                    ClearTextOnFocus = false, Text = "", PlaceholderText = ph,
                    Theme = {BackgroundColor3 = "Panel", TextColor3 = "Text", PlaceholderColor3 = "TextDim"}, Parent = frame}, {Corner(4), Stroke()})
            end
            Text({Text = "HEX", TextSize = 10, Theme = {TextColor3 = "TextDim"}, Position = UDim2.new(1, -124, 0, py), Size = UDim2.fromOffset(112, 12), Parent = frame})
            local hexBox = mkBox(py + 14, "#FFFFFF")
            Text({Text = "RGB", TextSize = 10, Theme = {TextColor3 = "TextDim"}, Position = UDim2.new(1, -124, 0, py + 46), Size = UDim2.fromOffset(112, 12), Parent = frame})
            local rgbBox = mkBox(py + 60, "255, 255, 255")

            local h, s, v = (ToColor(cp.Color) or Color3.new(1, 1, 1)):ToHSV()
            local open = false

            local function render()
                local c = Color3.fromHSV(h, s, v)
                sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
                svCursor.Position = UDim2.fromScale(s, 1 - v)
                hueCursor.Position = UDim2.fromScale(0.5, h)
                preview.BackgroundColor3 = c
                hexBox.Text = "#" .. c:ToHex():upper()
                rgbBox.Text = string.format("%d, %d, %d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
                return c
            end
            local function commit(silent)
                local c = render()
                api.Value = c
                api.CurrentValue = c
                if not silent then Fire(cp.Callback, c) end
                Changed(api)
            end

            BindDrag(sv, function(p)
                if api.Locked then return end
                s = math.clamp((p.X - sv.AbsolutePosition.X) / sv.AbsoluteSize.X, 0, 1)
                v = 1 - math.clamp((p.Y - sv.AbsolutePosition.Y) / sv.AbsoluteSize.Y, 0, 1)
                commit()
            end)
            BindDrag(hueBar, function(p)
                if api.Locked then return end
                h = math.clamp((p.Y - hueBar.AbsolutePosition.Y) / hueBar.AbsoluteSize.Y, 0, 1)
                commit()
            end)
            hexBox.FocusLost:Connect(function()
                local c = ToColor(hexBox.Text)
                if c then h, s, v = c:ToHSV() commit() else render() end
            end)
            rgbBox.FocusLost:Connect(function()
                local r, g, b = rgbBox.Text:match("(%d+)%D+(%d+)%D+(%d+)")
                if r then
                    h, s, v = Color3.fromRGB(math.clamp(tonumber(r), 0, 255), math.clamp(tonumber(g), 0, 255), math.clamp(tonumber(b), 0, 255)):ToHSV()
                    commit()
                else
                    render()
                end
            end)

            local function toggleOpen()
                if api.Locked then return end
                open = not open
                Tween(frame, {Size = UDim2.new(1, 0, 0, open and (py + 132) or headH)}, 0.2)
            end
            headBtn.Activated:Connect(toggleOpen)
            preview.Activated:Connect(toggleOpen)

            function api:Set(c, silent)
                c = ToColor(c)
                if not c then return end
                h, s, v = c:ToHSV()
                commit(silent)
            end

            commit(true)
            RegisterFlag(api, cp.Flag)
            return api
        end

        -- Progress Bar
        function target:CreateProgressBar(pb)
            pb = pb or {}
            local maxV = pb.Max or 100
            local frame, api = Base(H(46, pb.Description), pb.Name, {NoHover = true, Tooltip = pb.Tooltip})
            api.Type = "ProgressBar"
            Header(frame, pb.Name or "Progress", pb.Description, 70)
            local pct = Text({Text = "0%", TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, Theme = {TextColor3 = "TextDim"},
                AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 9), Size = UDim2.fromOffset(60, 18), Parent = frame})
            local bar = New("Frame", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -10), Size = UDim2.new(1, -24, 0, 6),
                Theme = {BackgroundColor3 = "Panel"}, Parent = frame}, {Corner(3)})
            local fill = New("Frame", {Size = UDim2.fromScale(0, 1), Theme = {BackgroundColor3 = "Accent"}, Parent = bar}, {Corner(3)})
            function api:Set(val)
                val = math.clamp(tonumber(val) or 0, 0, maxV)
                api.Value = val
                Tween(fill, {Size = UDim2.fromScale(val / maxV, 1)}, 0.25)
                pct.Text = math.floor(val / maxV * 100 + 0.5) .. "%"
            end
            api:Set(pb.Value or 0)
            return api
        end
    end

    --========== Tabs ==========--
    function Window:SelectTab(tab)
        local prev = self.CurrentTab
        if prev then
            for _, el in ipairs(prev.Elements) do
                if el.Frame.Parent then el.Frame.Visible = not el._hidden end
            end
        end
        self.CurrentTab = tab
        for _, t in ipairs(self.Tabs) do
            t.Page.Visible = (t == tab)
            t:_render(true)
        end
        TabTitle.Text = tab.Name
        SearchBox.Text = ""
        tab.Page.Position = UDim2.fromOffset(0, 10)
        Tween(tab.Page, {Position = UDim2.fromOffset(0, 0)}, 0.2)
    end

    function Window:CreateTab(tabName, icon, _isSettings)
        local Tab = {Name = tabName or "Tab", Elements = {}, IsSettings = _isSettings}

        local btn = New("TextButton", {Text = "", AutoButtonColor = false, Size = UDim2.new(1, 0, 0, 34),
            LayoutOrder = _isSettings and 999999 or NextOrder(), Parent = TabList}, {Corner(6)})
        local indicator = New("Frame", {AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(0, 3, 0, 0),
            Theme = {BackgroundColor3 = "Accent"}, Parent = btn}, {Corner(2)})
        local textX = 12
        if icon then
            Tab._icon = New("ImageLabel", {BackgroundTransparency = 1, Size = UDim2.fromOffset(16, 16), AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, 12, 0.5, 0), Image = type(icon) == "number" and ("rbxassetid://" .. icon) or icon, Parent = btn})
            textX = 36
        end
        local lbl = Text({Text = Tab.Name, Theme = {}, Size = UDim2.new(1, -textX - 8, 1, 0), Position = UDim2.fromOffset(textX, 0),
            TextTruncate = Enum.TextTruncate.AtEnd, Parent = btn})

        local page = New("ScrollingFrame", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ScrollBarThickness = 3,
            CanvasSize = UDim2.new(), AutomaticCanvasSize = AUTO_Y, ScrollingDirection = Enum.ScrollingDirection.Y, Visible = false,
            Theme = {ScrollBarImageColor3 = "Stroke"}, Parent = Pages}, {List(6), Pad(2, 14, 14, 14)})
        Tab.Page = page

        function Tab:_render(anim)
            local sel = Window.CurrentTab == Tab
            local t = anim and 0.18 or 0
            Tween(btn, {BackgroundColor3 = sel and Theme.Element or Theme.Sidebar}, t)
            Tween(lbl, {TextColor3 = sel and Theme.Text or Theme.TextDim}, t)
            Tween(indicator, {Size = UDim2.new(0, 3, 0, sel and 16 or 0)}, t)
            if Tab._icon then Tween(Tab._icon, {ImageColor3 = sel and Theme.Accent or Theme.TextDim}, t) end
        end
        OnTheme(function() Tab:_render(false) end)

        btn.MouseEnter:Connect(function() if Window.CurrentTab ~= Tab then Tween(lbl, {TextColor3 = Theme.Text}) end end)
        btn.MouseLeave:Connect(function() if Window.CurrentTab ~= Tab then Tween(lbl, {TextColor3 = Theme.TextDim}) end end)
        btn.Activated:Connect(function() Window:SelectTab(Tab) end)

        BuildElements(Tab, page, Tab)
        table.insert(Window.Tabs, Tab)
        Tab:_render(false)

        if not Window.CurrentTab or (Window.CurrentTab.IsSettings and not _isSettings) then
            Window:SelectTab(Tab)
        end
        return Tab
    end

    -- Search
    Connect(SearchBox:GetPropertyChangedSignal("Text"), function()
        local tab = Window.CurrentTab
        if not tab then return end
        local q = SearchBox.Text:lower()
        for _, el in ipairs(tab.Elements) do
            if el.Frame.Parent then
                local match = (q == "") or ((el.Name or ""):lower():find(q, 1, true) ~= nil)
                el.Frame.Visible = match and not el._hidden
            end
        end
    end)

    -- Topbar buttons
    MinBtn.Activated:Connect(function() Window:SetMinimized(not Window.Minimized) end)
    CloseBtn.Activated:Connect(function()
        Window:Dialog({
            Title = "Close " .. Window.Name .. "?",
            Content = "Hide keeps scripts running (press " .. Window.ToggleKey.Name .. " to reopen). Unload removes the UI completely.",
            Buttons = {
                {Name = "Hide", Callback = function()
                    Window:SetVisible(false)
                    SilL:Notify({Title = "UI Hidden", Content = "Press " .. Window.ToggleKey.Name .. " to reopen.", Type = "Info", Duration = 3})
                end},
                {Name = "Unload", Callback = function() SilL:Destroy() end},
                {Name = "Cancel"},
            },
        })
    end)

    -- Toggle key
    Connect(UIS.InputBegan, function(i, gp)
        if gp or SilL._binding then return end
        if i.KeyCode == Window.ToggleKey then Window:Toggle() end
    end)

    -- Mobile button
    if opts.MobileButton or (opts.MobileButton == nil and UIS.TouchEnabled) then
        local mb = New("TextButton", {Text = opts.MobileText or string.sub(Window.Name, 1, 1), Font = Enum.Font.GothamBold, TextSize = 18,
            AutoButtonColor = false, Size = UDim2.fromOffset(46, 46), Position = UDim2.new(0, 20, 0.5, -23),
            Theme = {BackgroundColor3 = "Accent", TextColor3 = "AccentText"}, Parent = gui},
            {New("UICorner", {CornerRadius = UDim.new(1, 0)}), Stroke()})
        local st = MakeDraggable(mb, mb)
        mb.Activated:Connect(function() if st.moved < 8 then Window:Toggle() end end)
    end

    -- Built-in Settings tab
    if opts.SettingsTab ~= false then
        local S = Window:CreateTab("Settings", opts.SettingsIcon, true)
        local ui = S:CreateSection("Interface")
        local names = {}
        for n in pairs(SilL.Themes) do table.insert(names, n) end
        table.sort(names)
        ui:CreateDropdown({Name = "Theme", Options = names, CurrentOption = SilL.CurrentThemeName, Callback = function(v)
            if v then SilL:SetTheme(v) end
        end})
        ui:CreateKeybind({Name = "Toggle UI Key", CurrentKeybind = Window.ToggleKey.Name, CallbackKeyChange = function(k)
            Window:SetToggleKey(k)
        end})
        ui:CreateButton({Name = "Unload UI", Description = "Remove the interface completely", Callback = function()
            Window:Dialog({Title = "Unload UI?", Content = "This will destroy every window and notification.",
                Buttons = {{Name = "Unload", Callback = function() SilL:Destroy() end}, {Name = "Cancel"}}})
        end})

        if configEnabled then
            local cs = S:CreateSection("Configuration")
            local nameInput = cs:CreateInput({Name = "Config Name", Placeholder = "my-config", CurrentValue = config.FileName})
            local list = cs:CreateDropdown({Name = "Saved Configs", Options = Window:ListConfigs(), CurrentOption = config.FileName})
            cs:CreateButton({Name = "Save Config", Callback = function()
                local n = (nameInput.Value ~= "" and nameInput.Value) or "default"
                local ok = Window:SaveConfig(n)
                list:Refresh(Window:ListConfigs(), true)
                SilL:Notify({Title = "Config", Content = ok and ("Saved '" .. n .. "'") or "Save failed", Type = ok and "Success" or "Error"})
            end})
            cs:CreateButton({Name = "Load Config", Callback = function()
                if not list.Value then return SilL:Notify({Title = "Config", Content = "Select a config first", Type = "Warning"}) end
                local ok = Window:LoadConfig(list.Value)
                SilL:Notify({Title = "Config", Content = ok and ("Loaded '" .. list.Value .. "'") or "Load failed", Type = ok and "Success" or "Error"})
            end})
            cs:CreateButton({Name = "Delete Config", Callback = function()
                local n = list.Value
                if not n then return end
                Window:Dialog({Title = "Delete '" .. n .. "'?", Content = "This cannot be undone.", Buttons = {
                    {Name = "Delete", Callback = function()
                        Window:DeleteConfig(n)
                        list:Refresh(Window:ListConfigs(), false)
                        SilL:Notify({Title = "Config", Content = "Deleted '" .. n .. "'", Type = "Warning"})
                    end},
                    {Name = "Cancel"},
                }})
            end})
            cs:CreateButton({Name = "Refresh List", Callback = function() list:Refresh(Window:ListConfigs(), true) end})
            cs:CreateToggle({Name = "Auto Save", Description = "Save automatically when a value changes", CurrentValue = Window._autoSave,
                Callback = function(v) Window._autoSave = v end})
        end
    end

    Tween(Scale, {Scale = baseScale}, 0.25, Enum.EasingStyle.Back)
    table.insert(SilL._windows or {}, Window)
    return Window
end

--==================== CLEANUP ====================--
function SilL:Destroy()
    for _, c in ipairs(SilL._connections) do pcall(function() c:Disconnect() end) end
    for _, g in ipairs(SilL._guis) do pcall(function() g:Destroy() end) end
    table.clear(SilL._connections)
    table.clear(SilL._guis)
    table.clear(SilL._registry)
    table.clear(SilL._themeCallbacks)
    table.clear(SilL.Flags)
    NotifyHolder = nil
end

return SilL
