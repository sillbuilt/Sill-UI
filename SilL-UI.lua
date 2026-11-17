--[[
    SilL UI  v1.0
    Independent Roblox interface library, written from scratch.
    API shape is inspired by common Roblox UI libraries, but all
    implementation, structure and styling here are original.

    Inspired by: Rayfield Interface Suite (Sirius, shlex, iRay)
    This file does not contain Rayfield code or Rayfield assets.
]]

local Version = "1.0.0"

-- =====================================================================
-- Services
-- =====================================================================
local Players     = game:GetService("Players")
local UIS         = game:GetService("UserInputService")
local TS          = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local RunService  = game:GetService("RunService")
local CoreGui     = game:GetService("CoreGui")
local Lighting    = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer

-- =====================================================================
-- Theme
-- =====================================================================
local Theme = {
    Text        = Color3.fromRGB(240, 240, 245),
    TextDim     = Color3.fromRGB(160, 160, 172),
    Background  = Color3.fromRGB(28, 28, 34),
    Topbar      = Color3.fromRGB(22, 22, 27),
    Sidebar     = Color3.fromRGB(32, 32, 39),
    Panel       = Color3.fromRGB(24, 24, 30),
    Element     = Color3.fromRGB(40, 40, 50),
    ElementHover= Color3.fromRGB(52, 52, 64),
    Stroke      = Color3.fromRGB(60, 60, 74),
    Accent      = Color3.fromRGB(94, 122, 255),
    AccentDim   = Color3.fromRGB(70, 92, 200),
    Success     = Color3.fromRGB(80, 200, 120),
    Danger      = Color3.fromRGB(224, 96, 96),
    Warning     = Color3.fromRGB(240, 184, 80),
}

-- =====================================================================
-- Builders / helpers
-- =====================================================================
local function New(class, props, children)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do
        inst[k] = v
    end
    for _, child in ipairs(children or {}) do
        child.Parent = inst
    end
    return inst
end

local function Corner(r) return New("UICorner", { CornerRadius = UDim.new(0, r) }) end
local function Stroke(color, thickness)
    return New("UIStroke", { Color = color or Theme.Stroke, Thickness = thickness or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end
local function Pad(all, h, v)
    return New("UIPadding", {
        PaddingTop    = UDim.new(0, v or all or 0),
        PaddingBottom = UDim.new(0, v or all or 0),
        PaddingLeft   = UDim.new(0, h or all or 0),
        PaddingRight  = UDim.new(0, h or all or 0),
    })
end
local function Tween(inst, time, props, style)
    local ti = TweenInfo.new(time or 0.2, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local t = TS:Create(inst, ti, props)
    t:Play()
    return t
end

local function GetGuiParent()
    if gethui then
        local ok, hui = pcall(gethui)
        if ok and hui then return hui end
    end
    if syn and syn.protect_gui then
        return CoreGui
    end
    return CoreGui
end

-- Safe filesystem helpers (no-op if unsupported)
local function FS_available()
    return typeof(writefile) == "function" and typeof(readfile) == "function"
end
local function FS_safe(fn, ...)
    local ok, res = pcall(fn, ...)
    if ok then return res end
end

-- =====================================================================
-- Library root
-- =====================================================================
local SilL = {
    Version = Version,
    Theme = Theme,
    Flags = {},
    _windows = {},
    _activeWindow = nil,
}

-- =====================================================================
-- Notification system
-- =====================================================================
local NotifyLayer

local function EnsureNotifyLayer()
    if NotifyLayer and NotifyLayer.Parent then return NotifyLayer end
    local parent = GetGuiParent()
    local existing = parent:FindFirstChild("SilL_Notify")
    if existing then
        NotifyLayer = existing
        return NotifyLayer
    end
    local sg = New("ScreenGui", {
        Name = "SilL_Notify",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 999,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        Parent = parent,
    })
    NotifyLayer = sg
    return sg
end

function SilL:Notify(opts)
    opts = opts or {}
    local title = opts.Title or "SilL UI"
    local content = opts.Content or ""
    local duration = opts.Duration or 4
    local kind = opts.Type or "info"
    local icon = opts.Image

    local accentColor = Theme.Accent
    if kind == "success" then accentColor = Theme.Success
    elseif kind == "warn" then accentColor = Theme.Warning
    elseif kind == "error" then accentColor = Theme.Danger
    end

    local layer = EnsureNotifyLayer()

    local toast = New("Frame", {
        Name = "Toast",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, 30, 1, -80),
        Size = UDim2.new(0, 300, 0, 78),
        BackgroundColor3 = Theme.Panel,
        BackgroundTransparency = 0.08,
        BorderSizePixel = 0,
        Parent = layer,
    })
    Corner(10).Parent = toast
    Stroke(Theme.Stroke, 1).Parent = toast

    local accent = New("Frame", {
        Size = UDim2.new(0, 4, 1, -16),
        Position = UDim2.new(0, 8, 0, 8),
        BackgroundColor3 = accentColor,
        BorderSizePixel = 0,
        Parent = toast,
    })
    Corner(2).Parent = accent

    local titleLabel = New("TextLabel", {
        Position = UDim2.new(0, 22, 0, 10),
        Size = UDim2.new(1, -32, 0, 20),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = title,
        Parent = toast,
    })
    local contentLabel = New("TextLabel", {
        Position = UDim2.new(0, 22, 0, 32),
        Size = UDim2.new(1, -32, 0, 36),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextWrapped = true,
        TextColor3 = Theme.TextDim,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Text = content,
        Parent = toast,
    })

    Tween(toast, 0.35, { Position = UDim2.new(1, -24, 1, -80) })
    task.delay(duration, function()
        if not toast or not toast.Parent then return end
        Tween(toast, 0.3, { Position = UDim2.new(1, 30, 1, -80), BackgroundTransparency = 1 })
        Tween(titleLabel, 0.3, { TextTransparency = 1 })
        Tween(contentLabel, 0.3, { TextTransparency = 1 })
        Tween(accent, 0.3, { BackgroundTransparency = 1 })
        task.wait(0.35)
        if toast then toast:Destroy() end
    end)
end

-- =====================================================================
-- Window class
-- =====================================================================
local Window = {}
Window.__index = Window

function SilL:CreateWindow(opts)
    opts = opts or {}
    local name = opts.Name or "SilL UI"
    local subtitle = opts.Subtitle or ("v" .. Version)
    local size = opts.Size or UDim2.new(0, 520, 0, 500)
    local config = opts.Config or {}

    local parent = GetGuiParent()

    local sg = New("ScreenGui", {
        Name = "SilL_" .. name:gsub("%s+", "_"),
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 200,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        Parent = parent,
    })
    if syn and syn.protect_gui then pcall(syn.protect_gui, sg) end

    local main = New("Frame", {
        Name = "Main",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = size,
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = sg,
    })
    Corner(12).Parent = main
    Stroke(Theme.Stroke, 1).Parent = main

    -- Shadow (outer)
    local shadow = New("ImageLabel", {
        Name = "Shadow",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(1, 40, 1, 40),
        BackgroundTransparency = 1,
        Image = "rbxasset://textures/ui/Glow.png",
        ImageColor3 = Color3.new(0, 0, 0),
        ImageTransparency = 0.45,
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(64, 64, 192, 192),
        ZIndex = -1,
        Parent = sg,
    })

    -- Topbar
    local topbar = New("Frame", {
        Name = "Topbar",
        Size = UDim2.new(1, 0, 0, 44),
        BackgroundColor3 = Theme.Topbar,
        BorderSizePixel = 0,
        Parent = main,
    })
    local topCorner = Corner(12); topCorner.Parent = topbar

    local titleLabel = New("TextLabel", {
        Name = "Title",
        Position = UDim2.new(0, 16, 0, 8),
        Size = UDim2.new(1, -120, 0, 18),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        TextSize = 15,
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = name,
        Parent = topbar,
    })
    local subtitleLabel = New("TextLabel", {
        Name = "Subtitle",
        Position = UDim2.new(0, 16, 0, 24),
        Size = UDim2.new(1, -120, 0, 14),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextColor3 = Theme.TextDim,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = subtitle,
        Parent = topbar,
    })

    -- Window buttons
    local function TopButton(label, pos, onClick)
        local btn = New("TextButton", {
            Position = pos,
            Size = UDim2.new(0, 26, 0, 26),
            BackgroundColor3 = Theme.Element,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Font = Enum.Font.GothamBold,
            TextSize = 14,
            TextColor3 = Theme.Text,
            Text = label,
            Parent = topbar,
        })
        Corner(6).Parent = btn
        btn.MouseEnter:Connect(function()
            Tween(btn, 0.15, { BackgroundColor3 = Theme.ElementHover })
        end)
        btn.MouseLeave:Connect(function()
            Tween(btn, 0.15, { BackgroundColor3 = Theme.Element })
        end)
        btn.MouseButton1Click:Connect(onClick)
        return btn
    end

    -- Body: sidebar + pages
    local body = New("Frame", {
        Name = "Body",
        Position = UDim2.new(0, 0, 0, 44),
        Size = UDim2.new(1, 0, 1, -44),
        BackgroundTransparency = 1,
        Parent = main,
    })

    local sidebar = New("ScrollingFrame", {
        Name = "Sidebar",
        Size = UDim2.new(0, 150, 1, 0),
        BackgroundColor3 = Theme.Sidebar,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = Theme.Stroke,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Parent = body,
    })
    Pad(8, 8, 8).Parent = sidebar
    New("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
        Parent = sidebar,
    })

    local contentHolder = New("Frame", {
        Name = "Content",
        Position = UDim2.new(0, 150, 0, 0),
        Size = UDim2.new(1, -150, 1, 0),
        BackgroundTransparency = 1,
        Parent = body,
    })

    local pagesFolder = New("Folder", { Name = "Pages", Parent = contentHolder })

    -- Dragging (topbar)
    do
        local dragging, startPos, startFramePos
        topbar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                startPos = input.Position
                startFramePos = main.Position
            end
        end)
        topbar.InputChanged:Connect(function(input)
            if not dragging then return end
            if input.UserInputType ~= Enum.UserInputType.MouseMovement
                and input.UserInputType ~= Enum.UserInputType.Touch then return end
            local delta = input.Position - startPos
            main.Position = UDim2.new(
                startFramePos.X.Scale,
                startFramePos.X.Offset + delta.X,
                startFramePos.Y.Scale,
                startFramePos.Y.Offset + delta.Y
            )
        end)
        topbar.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)
    end

    -- Window state
    local state = {
        minimized = false,
        hidden = false,
        tabs = {},
        firstTab = nil,
        currentTab = nil,
        configFolder = config.Folder or "SilL/Configs",
        configFileName = config.FileName or ("config_" .. tostring(game.PlaceId)),
        configEnabled = config.Enabled == true,
        savedSize = size,
    }

    local function SaveConfig()
        if not state.configEnabled or not FS_available() then return end
        local data = {}
        for flag, entry in pairs(SilL.Flags) do
            if entry.__window == self then
                data[flag] = entry.CurrentValue
                    or entry.CurrentOption
                    or entry.CurrentKeybind
                    or entry.CurrentInput
                    or (entry.Color and { R = entry.Color.R*255, G = entry.Color.G*255, B = entry.Color.B*255 })
            end
        end
        FS_safe(function()
            if isfolder and not isfolder(state.configFolder) then
                makefolder(state.configFolder)
            end
            writefile(state.configFolder .. "/" .. state.configFileName .. ".json",
                HttpService:JSONEncode(data))
        end)
    end

    function self:LoadConfig()
        if not FS_available() then return end
        FS_safe(function()
            local path = state.configFolder .. "/" .. state.configFileName .. ".json"
            if not isfile(path) then return end
            local data = HttpService:JSONDecode(readfile(path))
            for flag, value in pairs(data) do
                local entry = SilL.Flags[flag]
                if entry and entry.__window == self then
                    pcall(function() entry:Set(value) end)
                end
            end
            self:Notify({ Title = "Config", Content = "Loaded config", Type = "success" })
        end)
    end

    function self:SaveConfig() SaveConfig() end

    -- Minimize
    local minBtn, closeBtn
    minBtn = TopButton("-", UDim2.new(1, -72, 0, 9), function()
        state.minimized = not state.minimized
        if state.minimized then
            state.savedSize = main.Size
            Tween(main, 0.3, { Size = UDim2.new(0, 520, 0, 44) })
            Tween(shadow, 0.3, { Size = UDim2.new(1, 40, 0, 84) })
            body.Visible = false
            minBtn.Text = "+"
        else
            Tween(main, 0.3, { Size = state.savedSize })
            Tween(shadow, 0.3, { Size = UDim2.new(1, 40, 1, 40) })
            body.Visible = true
            minBtn.Text = "-"
        end
    end)
    closeBtn = TopButton("x", UDim2.new(1, -40, 0, 9), function()
        state.hidden = true
        Tween(main, 0.3, { BackgroundTransparency = 1, Size = UDim2.new(0, 0, 0, 0) })
        Tween(shadow, 0.3, { ImageTransparency = 1 })
    end)

    -- Unhide key
    local toggleKey = Enum.KeyCode.RightShift
    UIS.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.KeyCode == toggleKey then
            state.hidden = not state.hidden
            if state.hidden then
                Tween(main, 0.3, { BackgroundTransparency = 1, Size = UDim2.new(0, 0, 0, 0) })
                Tween(shadow, 0.3, { ImageTransparency = 1 })
            else
                Tween(main, 0.3, { BackgroundTransparency = 0, Size = state.savedSize })
                Tween(shadow, 0.3, { ImageTransparency = 0.45, Size = UDim2.new(1, 40, 1, 40) })
            end
        end
    end)

    -- Tab buttons factory
    function self:CreateTab(tabName, icon)
        tabName = tabName or ("Tab " .. (#state.tabs + 1))

        local tabButton = New("TextButton", {
            Name = "Tab_" .. tabName:gsub("%s+", "_"),
            Size = UDim2.new(1, 0, 0, 32),
            BackgroundColor3 = Theme.Element,
            BackgroundTransparency = 0.4,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = "",
            Parent = sidebar,
        })
        Corner(6).Parent = tabButton
        local tabStroke = Stroke(Theme.Stroke, 1); tabStroke.Parent = tabButton

        local tabLabel = New("TextLabel", {
            Position = UDim2.new(0, 10, 0, 0),
            Size = UDim2.new(1, -20, 1, 0),
            BackgroundTransparency = 1,
            Font = Enum.Font.GothamMedium,
            TextSize = 13,
            TextColor3 = Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = tabName,
            Parent = tabButton,
        })

        local page = New("ScrollingFrame", {
            Name = "Page_" .. tabName:gsub("%s+", "_"),
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 4,
            ScrollBarImageColor3 = Theme.Stroke,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Visible = false,
            Parent = pagesFolder,
        })
        Pad(10, 12, 10).Parent = page
        New("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 8),
            Parent = page,
        })

        local tab = {
            Button = tabButton,
            Page = page,
            Name = tabName,
        }

        local function ShowTab()
            for _, t in pairs(state.tabs) do
                t.Page.Visible = false
                Tween(t.Button, 0.15, { BackgroundTransparency = 0.4, BackgroundColor3 = Theme.Element })
                t.Button.TextLabel = t.Button:FindFirstChildOfClass("TextLabel")
                if t.Button.TextLabel then
                    Tween(t.Button.TextLabel, 0.15, { TextColor3 = Theme.Text })
                end
            end
            page.Visible = true
            Tween(tabButton, 0.15, { BackgroundTransparency = 0, BackgroundColor3 = Theme.AccentDim })
            Tween(tabLabel, 0.15, { TextColor3 = Theme.Text })
            state.currentTab = tab
        end

        tabButton.MouseEnter:Connect(function()
            if state.currentTab ~= tab then
                Tween(tabButton, 0.15, { BackgroundTransparency = 0.15 })
            end
        end)
        tabButton.MouseLeave:Connect(function()
            if state.currentTab ~= tab then
                Tween(tabButton, 0.15, { BackgroundTransparency = 0.4 })
            end
        end)
        tabButton.MouseButton1Click:Connect(ShowTab)

        table.insert(state.tabs, tab)
        if not state.firstTab then
            state.firstTab = tab
            task.defer(ShowTab)
        end

        -- =================================================================
        -- Element factory helpers
        -- =================================================================
        local function CreateElementFrame(height)
            local f = New("Frame", {
                Size = UDim2.new(1, 0, 0, height or 38),
                BackgroundColor3 = Theme.Element,
                BorderSizePixel = 0,
                Parent = page,
            })
            Corner(8).Parent = f
            local s = Stroke(Theme.Stroke, 1); s.Parent = f
            return f, s
        end

        local function AddHover(frame, stroke)
            frame.MouseEnter:Connect(function()
                Tween(frame, 0.15, { BackgroundColor3 = Theme.ElementHover })
            end)
            frame.MouseLeave:Connect(function()
                Tween(frame, 0.15, { BackgroundColor3 = Theme.Element })
            end)
        end

        -- Section
        function tab:CreateSection(sectionName)
            local sec = New("Frame", {
                Size = UDim2.new(1, 0, 0, 26),
                BackgroundTransparency = 1,
                Parent = page,
            })
            local lbl = New("TextLabel", {
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamBold,
                TextSize = 13,
                TextColor3 = Theme.Accent,
                TextXAlignment = Enum.TextXAlignment.Left,
                Text = sectionName,
                Parent = sec,
            })
            return { Frame = sec, Set = function(_, v) lbl.Text = v end }
        end

        -- Label
        function tab:CreateLabel(text)
            local el, _ = CreateElementFrame(34)
            local lbl = New("TextLabel", {
                Position = UDim2.new(0, 12, 0, 0),
                Size = UDim2.new(1, -24, 1, 0),
                BackgroundTransparency = 1,
                Font = Enum.Font.Gotham,
                TextSize = 13,
                TextColor3 = Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextWrapped = true,
                Text = text,
                Parent = el,
            })
            return { Frame = el, Set = function(_, v) lbl.Text = v end }
        end

        -- Paragraph
        function tab:CreateParagraph(p)
            local el, _ = CreateElementFrame()
            el.AutomaticSize = Enum.AutomaticSize.Y
            el.Size = UDim2.new(1, 0, 0, 0)
            Pad(10, 12, 10).Parent = el
            New("UIListLayout", { Padding = UDim.new(0, 4), Parent = el })
            local t = New("TextLabel", {
                Size = UDim2.new(1, 0, 0, 18),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamBold,
                TextSize = 13,
                TextColor3 = Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                Text = p.Title or "",
                Parent = el,
            })
            local c = New("TextLabel", {
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                Font = Enum.Font.Gotham,
                TextSize = 12,
                TextWrapped = true,
                TextColor3 = Theme.TextDim,
                TextXAlignment = Enum.TextXAlignment.Left,
                Text = p.Content or "",
                Parent = el,
            })
            return {
                Frame = el,
                Set = function(_, np)
                    t.Text = np.Title or t.Text
                    c.Text = np.Content or c.Text
                end,
            }
        end

        -- Button
        function tab:CreateButton(b)
            local el, s = CreateElementFrame(38)
            AddHover(el, s)
            local btn = New("TextButton", {
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = "",
                Parent = el,
            })
            local lbl = New("TextLabel", {
                Position = UDim2.new(0, 12, 0, 0),
                Size = UDim2.new(1, -24, 1, 0),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamMedium,
                TextSize = 13,
                TextColor3 = Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                Text = b.Name or "Button",
                Parent = el,
            })
            btn.MouseButton1Click:Connect(function()
                local ok, err = pcall(b.Callback or function() end)
                if not ok then
                    self:Notify({ Title = "Error", Content = tostring(err), Type = "error" })
                end
            end)
            return {
                Frame = el,
                Set = function(_, v) lbl.Text = v end,
            }
        end

        -- Toggle
        function tab:CreateToggle(t)
            local el, s = CreateElementFrame(38)
            AddHover(el, s)
            local lbl = New("TextLabel", {
                Position = UDim2.new(0, 12, 0, 0),
                Size = UDim2.new(1, -72, 1, 0),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamMedium,
                TextSize = 13,
                TextColor3 = Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                Text = t.Name or "Toggle",
                Parent = el,
            })
            local track = New("Frame", {
                Name = "Track",
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -12, 0.5, 0),
                Size = UDim2.new(0, 40, 0, 20),
                BackgroundColor3 = Theme.Stroke,
                BorderSizePixel = 0,
                Parent = el,
            })
            Corner(10).Parent = track
            local knob = New("Frame", {
                Name = "Knob",
                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, 3, 0.5, 0),
                Size = UDim2.new(0, 14, 0, 14),
                BackgroundColor3 = Theme.Text,
                BorderSizePixel = 0,
                Parent = track,
            })
            Corner(7).Parent = knob

            local click = New("TextButton", {
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = "",
                Parent = el,
            })

            local currentValue = t.CurrentValue == true
            local entry = {
                __window = self,
                CurrentValue = currentValue,
                Set = function(_, v)
                    currentValue = v and true or false
                    entry.CurrentValue = currentValue
                    if currentValue then
                        Tween(track, 0.2, { BackgroundColor3 = Theme.Accent })
                        Tween(knob, 0.2, { Position = UDim2.new(1, -17, 0.5, 0) })
                    else
                        Tween(track, 0.2, { BackgroundColor3 = Theme.Stroke })
                        Tween(knob, 0.2, { Position = UDim2.new(0, 3, 0.5, 0) })
                    end
                    if t.Callback then pcall(t.Callback, currentValue) end
                end,
            }
            -- Initial paint
            if currentValue then
                track.BackgroundColor3 = Theme.Accent
                knob.Position = UDim2.new(1, -17, 0.5, 0)
            end

            click.MouseButton1Click:Connect(function()
                entry:Set(not currentValue)
                SaveConfig()
            end)

            if t.Flag then SilL.Flags[t.Flag] = entry end
            return entry
        end

        -- Slider
        function tab:CreateSlider(s)
            local minV = s.Range and s.Range[1] or 0
            local maxV = s.Range and s.Range[2] or 100
            local current = s.CurrentValue or minV

            local el, _ = CreateElementFrame(52)
            local lbl = New("TextLabel", {
                Position = UDim2.new(0, 12, 0, 6),
                Size = UDim2.new(1, -80, 0, 18),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamMedium,
                TextSize = 13,
                TextColor3 = Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                Text = s.Name or "Slider",
                Parent = el,
            })
            local valLbl = New("TextLabel", {
                Position = UDim2.new(1, -68, 0, 6),
                Size = UDim2.new(0, 56, 0, 18),
                BackgroundTransparency = 1,
                Font = Enum.Font.Gotham,
                TextSize = 12,
                TextColor3 = Theme.TextDim,
                TextXAlignment = Enum.TextXAlignment.Right,
                Text = tostring(current),
                Parent = el,
            })
            local track = New("Frame", {
                Position = UDim2.new(0, 12, 0, 32),
                Size = UDim2.new(1, -24, 0, 8),
                BackgroundColor3 = Theme.Stroke,
                BorderSizePixel = 0,
                Parent = el,
            })
            Corner(4).Parent = track
            local fill = New("Frame", {
                Size = UDim2.new((current - minV) / (maxV - minV), 0, 1, 0),
                BackgroundColor3 = Theme.Accent,
                BorderSizePixel = 0,
                Parent = track,
            })
            Corner(4).Parent = fill
            local knob = New("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new((current - minV) / (maxV - minV), 0, 0.5, 0),
                Size = UDim2.new(0, 14, 0, 14),
                BackgroundColor3 = Theme.Text,
                BorderSizePixel = 0,
                Parent = track,
            })
            Corner(7).Parent = knob

            local dragging = false
            local function updateFromInput(posX)
                local rel = math.clamp((posX - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
                local val = minV + (maxV - minV) * rel
                if s.Rounding then val = math.floor(val + 0.5) else
                    val = math.floor(val * 100 + 0.5) / 100
                end
                current = val
                fill.Size = UDim2.new(rel, 0, 1, 0)
                knob.Position = UDim2.new(rel, 0, 0.5, 0)
                valLbl.Text = tostring(val)
                if s.Callback then pcall(s.Callback, val) end
            end

            track.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                    dragging = true
                    updateFromInput(input.Position.X)
                end
            end)
            UIS.InputChanged:Connect(function(input)
                if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
                    or input.UserInputType == Enum.UserInputType.Touch) then
                    updateFromInput(input.Position.X)
                end
            end)
            UIS.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch then
                    if dragging then
                        dragging = false
                        SaveConfig()
                    end
                end
            end)

            local entry = {
                __window = self,
                CurrentValue = current,
                Set = function(_, v)
                    local clamped = math.clamp(v, minV, maxV)
                    local rel = (clamped - minV) / (maxV - minV)
                    current = clamped
                    entry.CurrentValue = clamped
                    fill.Size = UDim2.new(rel, 0, 1, 0)
                    knob.Position = UDim2.new(rel, 0, 0.5, 0)
                    valLbl.Text = tostring(clamped)
                    if s.Callback then pcall(s.Callback, clamped) end
                end,
            }
            if s.Flag then SilL.Flags[s.Flag] = entry end
            return entry
        end

        -- Input
        function tab:CreateInput(inp)
            local el, _ = CreateElementFrame(52)
            local lbl = New("TextLabel", {
                Position = UDim2.new(0, 12, 0, 6),
                Size = UDim2.new(1, -24, 0, 18),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamMedium,
                TextSize = 13,
                TextColor3 = Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                Text = inp.Name or "Input",
                Parent = el,
            })
            local box = New("TextBox", {
                Position = UDim2.new(0, 12, 0, 26),
                Size = UDim2.new(1, -24, 0, 20),
                BackgroundColor3 = Theme.Panel,
                BorderSizePixel = 0,
                Font = Enum.Font.Gotham,
                TextSize = 12,
                TextColor3 = Theme.Text,
                PlaceholderText = inp.Placeholder or "Enter text...",
                PlaceholderColor3 = Theme.TextDim,
                Text = inp.CurrentValue or "",
                ClearTextOnFocus = false,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = el,
            })
            Corner(4).Parent = box
            Pad(6, 6, 0).Parent = box

            local entry = {
                __window = self,
                CurrentValue = box.Text,
                Set = function(_, v)
                    box.Text = tostring(v)
                    entry.CurrentValue = box.Text
                    if inp.Callback then pcall(inp.Callback, entry.CurrentValue) end
                end,
            }
            box.FocusLost:Connect(function(enterPressed)
                entry.CurrentValue = box.Text
                if inp.Callback then pcall(inp.Callback, box.Text, enterPressed) end
                if inp.ClearOnFocusLost then box.Text = "" end
                SaveConfig()
            end)
            if inp.Flag then SilL.Flags[inp.Flag] = entry end
            return entry
        end

        -- Dropdown
        function tab:CreateDropdown(dd)
            local options = dd.Options or {}
            local multiple = dd.MultipleOptions == true
            local current
            if multiple then
                current = {}
                local init = dd.CurrentOption
                if typeof(init) == "table" then
                    for _, v in ipairs(init) do current[v] = true end
                elseif typeof(init) == "string" then
                    current[init] = true
                end
            else
                current = dd.CurrentOption or (options[1] or "")
            end

            local el, s = CreateElementFrame(38)
            AddHover(el, s)
            local lbl = New("TextLabel", {
                Position = UDim2.new(0, 12, 0, 0),
                Size = UDim2.new(1, -60, 1, 0),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamMedium,
                TextSize = 13,
                TextColor3 = Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                Text = dd.Name or "Dropdown",
                Parent = el,
            })
            local selectedLbl = New("TextLabel", {
                Position = UDim2.new(1, -50, 0, 0),
                Size = UDim2.new(0, 40, 1, 0),
                BackgroundTransparency = 1,
                Font = Enum.Font.Gotham,
                TextSize = 12,
                TextColor3 = Theme.TextDim,
                TextXAlignment = Enum.TextXAlignment.Right,
                Text = "v",
                Parent = el,
            })

            local list = New("ScrollingFrame", {
                Position = UDim2.new(0, 0, 1, 4),
                Size = UDim2.new(1, 0, 0, 0),
                BackgroundColor3 = Theme.Panel,
                BorderSizePixel = 0,
                ScrollBarThickness = 3,
                ScrollBarImageColor3 = Theme.Stroke,
                CanvasSize = UDim2.new(0, 0, 0, 0),
                AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ClipsDescendants = true,
                Visible = false,
                ZIndex = 20,
                Parent = el,
            })
            Corner(8).Parent = list
            Pad(4, 4, 4).Parent = list
            New("UIListLayout", { Padding = UDim.new(0, 3), Parent = list })

            local displayText = "..."
            local function updateDisplay()
                if multiple then
                    local keys = {}
                    for k, v in pairs(current) do if v then table.insert(keys, k) end end
                    if #keys == 0 then displayText = "None"
                    elseif #keys == 1 then displayText = keys[1]
                    else displayText = "Various" end
                else
                    displayText = tostring(current)
                end
            end
            updateDisplay()

            local optionButtons = {}
            for _, opt in ipairs(options) do
                local ob = New("TextButton", {
                    Size = UDim2.new(1, 0, 0, 26),
                    BackgroundColor3 = Theme.Element,
                    BorderSizePixel = 0,
                    AutoButtonColor = false,
                    Font = Enum.Font.Gotham,
                    TextSize = 12,
                    TextColor3 = Theme.Text,
                    Text = tostring(opt),
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Parent = list,
                })
                Corner(4).Parent = ob
                Pad(6, 8, 0).Parent = ob
                local obStroke = Stroke(Theme.Stroke, 1); obStroke.Parent = ob

                ob.MouseEnter:Connect(function()
                    Tween(ob, 0.12, { BackgroundColor3 = Theme.ElementHover })
                end)
                ob.MouseLeave:Connect(function()
                    Tween(ob, 0.12, { BackgroundColor3 = Theme.Element })
                end)
                ob.MouseButton1Click:Connect(function()
                    if multiple then
                        current[opt] = not current[opt] or nil
                        if current[opt] == false then current[opt] = nil end
                    else
                        current = opt
                    end
                    updateDisplay()
                    selectedLbl.Text = displayText
                    if dd.Callback then
                        local cbArg
                        if multiple then
                            cbArg = {}
                            for k, v in pairs(current) do if v then table.insert(cbArg, k) end end
                        else
                            cbArg = current
                        end
                        pcall(dd.Callback, cbArg)
                    end
                    if not multiple then
                        list.Visible = false
                        el.Size = UDim2.new(1, 0, 0, 38)
                    end
                    SaveConfig()
                end)
                table.insert(optionButtons, ob)
            end

            local entry = {
                __window = self,
                CurrentOption = multiple and current or current,
                Set = function(_, v)
                    if multiple then
                        current = {}
                        if typeof(v) == "table" then
                            for _, item in ipairs(v) do current[item] = true end
                        elseif typeof(v) == "string" then
                            current[v] = true
                        end
                    else
                        current = v
                    end
                    updateDisplay()
                    selectedLbl.Text = displayText
                    if dd.Callback then
                        pcall(dd.Callback, multiple and (function()
                            local out = {}
                            for k, vv in pairs(current) do if vv then table.insert(out, k) end end
                            return out
                        end)() or current)
                    end
                end,
            }

            local toggleBtn = New("TextButton", {
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundTransparency = 1,
                Text = "",
                Parent = el,
            })
            toggleBtn.MouseButton1Click:Connect(function()
                local open = list.Visible
                list.Visible = not open
                if open then
                    Tween(el, 0.2, { Size = UDim2.new(1, 0, 0, 38) })
                    Tween(list, 0.2, { Size = UDim2.new(1, 0, 0, 0) })
                    task.delay(0.2, function() list.Visible = false end)
                else
                    Tween(el, 0.2, { Size = UDim2.new(1, 0, 0, 38 + math.min(#options * 29 + 8, 180)) })
                    Tween(list, 0.2, { Size = UDim2.new(1, 0, 0, math.min(#options * 29 + 8, 180)) })
                end
            end)

            selectedLbl.Text = displayText
            if dd.Flag then SilL.Flags[dd.Flag] = entry end
            return entry
        end

        -- Keybind
        function tab:CreateKeybind(kb)
            local el, s = CreateElementFrame(38)
            AddHover(el, s)
            local lbl = New("TextLabel", {
                Position = UDim2.new(0, 12, 0, 0),
                Size = UDim2.new(1, -100, 1, 0),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamMedium,
                TextSize = 13,
                TextColor3 = Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                Text = kb.Name or "Keybind",
                Parent = el,
            })
            local keyBox = New("TextButton", {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -12, 0.5, 0),
                Size = UDim2.new(0, 84, 0, 24),
                BackgroundColor3 = Theme.Panel,
                BorderSizePixel = 0,
                AutoButtonColor = false,
                Font = Enum.Font.Gotham,
                TextSize = 12,
                TextColor3 = Theme.Text,
                Text = tostring(kb.CurrentKeybind or "None"),
                Parent = el,
            })
            Corner(4).Parent = keyBox
            local keyStroke = Stroke(Theme.Stroke, 1); keyStroke.Parent = keyBox

            local listening = false
            local currentKey = kb.CurrentKeybind

            keyBox.MouseButton1Click:Connect(function()
                listening = true
                keyBox.Text = "Press..."
                Tween(keyBox, 0.15, { BackgroundColor3 = Theme.AccentDim })
            end)

            local conn
            conn = UIS.InputBegan:Connect(function(input, gp)
                if listening then
                    if input.UserInputType == Enum.UserInputType.Keyboard then
                        listening = false
                        currentKey = input.KeyCode.Name
                        keyBox.Text = currentKey
                        Tween(keyBox, 0.15, { BackgroundColor3 = Theme.Panel })
                        entry.CurrentKeybind = currentKey
                        if kb.Callback and kb.CallbackKeyChange then
                            pcall(kb.CallbackKeyChange, currentKey)
                        end
                        SaveConfig()
                    end
                else
                    if currentKey and input.KeyCode == Enum.KeyCode[currentKey] and not gp then
                        if kb.Callback then pcall(kb.Callback) end
                    end
                end
            end)

            local entry = {
                __window = self,
                CurrentKeybind = currentKey,
                Set = function(_, v)
                    currentKey = v
                    entry.CurrentKeybind = v
                    keyBox.Text = tostring(v)
                end,
            }
            if kb.Flag then SilL.Flags[kb.Flag] = entry end
            return entry
        end

        -- ColorPicker
        function tab:CreateColorPicker(cp)
            local el, _ = CreateElementFrame(52)
            local lbl = New("TextLabel", {
                Position = UDim2.new(0, 12, 0, 6),
                Size = UDim2.new(1, -80, 0, 18),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamMedium,
                TextSize = 13,
                TextColor3 = Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                Text = cp.Name or "Color",
                Parent = el,
            })
            local preview = New("Frame", {
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -12, 0, 8),
                Size = UDim2.new(0, 60, 0, 22),
                BackgroundColor3 = cp.Color or Color3.fromRGB(255, 255, 255),
                BorderSizePixel = 0,
                Parent = el,
            })
            Corner(4).Parent = preview
            Stroke(Theme.Stroke, 1).Parent = preview

            -- Expanded area
            local expanded = New("Frame", {
                Position = UDim2.new(0, 12, 0, 38),
                Size = UDim2.new(1, -24, 0, 0),
                BackgroundTransparency = 1,
                ClipsDescendants = true,
                Parent = el,
            })
            local satVal = New("ImageLabel", {
                Size = UDim2.new(1, 0, 0, 80),
                BackgroundColor3 = Color3.fromRGB(255, 0, 0),
                BorderSizePixel = 0,
                Image = "rbxassetid://4155801252",
                ScaleType = Enum.ScaleType.Stretch,
                Parent = expanded,
            })
            local hueBar = New("ImageLabel", {
                Position = UDim2.new(0, 0, 0, 88),
                Size = UDim2.new(1, 0, 0, 14),
                BackgroundTransparency = 1,
                Image = "rbxassetid://5108535320",
                ScaleType = Enum.ScaleType.Stretch,
                Parent = expanded,
            })
            local hexBox = New("TextBox", {
                Position = UDim2.new(0, 0, 0, 108),
                Size = UDim2.new(0, 100, 0, 24),
                BackgroundColor3 = Theme.Panel,
                BorderSizePixel = 0,
                Font = Enum.Font.Code,
                TextSize = 12,
                TextColor3 = Theme.Text,
                Text = "#FFFFFF",
                Parent = expanded,
            })
            Corner(4).Parent = hexBox
            Pad(6, 6, 0).Parent = hexBox

            local currentColor = cp.Color or Color3.fromRGB(255, 255, 255)
            local h, sat, v = currentColor:ToHSV()
            local open = false

            local function refresh()
                currentColor = Color3.fromHSV(h, sat, v)
                satVal.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
                preview.BackgroundColor3 = currentColor
                hexBox.Text = string.format("#%02X%02X%02X",
                    math.floor(currentColor.R * 255 + 0.5),
                    math.floor(currentColor.G * 255 + 0.5),
                    math.floor(currentColor.B * 255 + 0.5))
                if cp.Callback then pcall(cp.Callback, currentColor) end
            end

            local pickingSV = false
            local pickingHue = false
            local function updateSV(x, y)
                local rx = math.clamp((x - satVal.AbsolutePosition.X) / satVal.AbsoluteSize.X, 0, 1)
                local ry = math.clamp((y - satVal.AbsolutePosition.Y) / satVal.AbsoluteSize.Y, 0, 1)
                sat = rx
                v = 1 - ry
                refresh()
            end
            local function updateHue(x)
                local rx = math.clamp((x - hueBar.AbsolutePosition.X) / hueBar.AbsoluteSize.X, 0, 1)
                h = rx
                refresh()
            end

            satVal.InputBegan:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.MouseButton1
                    or i.UserInputType == Enum.UserInputType.Touch then
                    pickingSV = true
                    updateSV(i.Position.X, i.Position.Y)
                end
            end)
            hueBar.InputBegan:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.MouseButton1
                    or i.UserInputType == Enum.UserInputType.Touch then
                    pickingHue = true
                    updateHue(i.Position.X)
                end
            end)
            UIS.InputChanged:Connect(function(i)
                if pickingSV and (i.UserInputType == Enum.UserInputType.MouseMovement
                    or i.UserInputType == Enum.UserInputType.Touch) then
                    updateSV(i.Position.X, i.Position.Y)
                end
                if pickingHue and (i.UserInputType == Enum.UserInputType.MouseMovement
                    or i.UserInputType == Enum.UserInputType.Touch) then
                    updateHue(i.Position.X)
                end
            end)
            UIS.InputEnded:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.MouseButton1
                    or i.UserInputType == Enum.UserInputType.Touch then
                    if pickingSV or pickingHue then SaveConfig() end
                    pickingSV = false
                    pickingHue = false
                end
            end)

            hexBox.FocusLost:Connect(function()
                local hex = hexBox.Text:gsub("#", "")
                local r = tonumber(hex:sub(1, 2), 16)
                local g = tonumber(hex:sub(3, 4), 16)
                local b = tonumber(hex:sub(5, 6), 16)
                if r and g and b then
                    local c = Color3.fromRGB(r, g, b)
                    h, sat, v = c:ToHSV()
                    refresh()
                    SaveConfig()
                end
            end)

            local click = New("TextButton", {
                Position = UDim2.new(0, 0, 0, 0),
                Size = UDim2.new(1, 0, 0, 34),
                BackgroundTransparency = 1,
                Text = "",
                Parent = el,
            })
            click.MouseButton1Click:Connect(function()
                open = not open
                if open then
                    Tween(el, 0.2, { Size = UDim2.new(1, 0, 0, 192) })
                    Tween(expanded, 0.2, { Size = UDim2.new(1, -24, 0, 140) })
                else
                    Tween(el, 0.2, { Size = UDim2.new(1, 0, 0, 52) })
                    Tween(expanded, 0.2, { Size = UDim2.new(1, -24, 0, 0) })
                end
            end)

            refresh()

            local entry = {
                __window = self,
                Color = currentColor,
                Set = function(_, c)
                    currentColor = c
                    h, sat, v = c:ToHSV()
                    refresh()
                end,
            }
            if cp.Flag then SilL.Flags[cp.Flag] = entry end
            return entry
        end

        return tab
    end

    -- Initial opening animation
    main.BackgroundTransparency = 1
    topbar.BackgroundTransparency = 1
    Tween(main, 0.3, { BackgroundTransparency = 0 })
    Tween(topbar, 0.3, { BackgroundTransparency = 0 })

    self:Notify({ Title = "SilL UI", Content = name .. " loaded", Type = "success" })

    return self
end

-- =====================================================================
-- Destroy
-- =====================================================================
function SilL:Destroy()
    for _, w in ipairs(SilL._windows) do
        if w._screenGui then w._screenGui:Destroy() end
    end
    SilL._windows = {}
end

return SilL
