-- language: Luau, file: SillChessBot_AutoExec.lua, target: Roblox (Sill ChessDuels)
--!strict

--[[
    ========================================================================
    SILL CHESSDUELS - SILL X UI EDITION (FULL AUTO + TOP-PINNED SLIDE UI)
    - แถบหัวด้านบน (Topbar) ล็อกอยู่กับที่ 100% เวลาพับและกางเมนูจะไหลขึ้น-ลงด้านล่างอย่างนุ่มนวล
    - ซ่อนกรอบโปรไฟล์ (userBox) ตอนพับสนิท ไม่ลอยทับแถบหัว
    - Single-Instance Lock + Smart Cleanup (ป้องกันสคริปต์รันซ้อนตอนจบเกม)
    - Bot Profiles + แถบปรับ Level / Depth แยกอิสระ + โหมด Turbo Cap กันแพ้เวลา
    ========================================================================
]]

local ENV = (type(getgenv) == "function" and getgenv()) or _G

if ENV.SillChessBotCleanup then
    pcall(ENV.SillChessBotCleanup)
end

local AUTORUN_FILE = "SillChessBot_AutoExec.lua"
local STATE_FILE = "SillChessBot_State.json"

local BOT_SOURCE = [==[
if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    task.wait(0.2)
    LocalPlayer = Players.LocalPlayer
end

local ENV = (type(getgenv) == "function" and getgenv()) or _G

if ENV.SillChessBotCleanup then
    pcall(ENV.SillChessBotCleanup)
end

local function destroyOldUIs()
    local roots = {}
    pcall(function() if type(gethui) == "function" then table.insert(roots, gethui()) end end)
    pcall(function() table.insert(roots, CoreGui) end)
    pcall(function()
        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if pg then table.insert(roots, pg) end
    end)

    for _, root in ipairs(roots) do
        for _, child in ipairs(root:GetChildren()) do
            if child:IsA("ScreenGui") then
                local guiName = string.lower(child.Name)
                if string.find(guiName, "sill") then
                    pcall(function() child:Destroy() end)
                else
                    for _, desc in ipairs(child:GetDescendants()) do
                        if (desc:IsA("TextLabel") or desc:IsA("TextButton")) and string.find(desc.Text or "", "Sill ChessDuels", 1, true) then
                            pcall(function() child:Destroy() end)
                            break
                        end
                    end
                end
            end
        end
    end
end

destroyOldUIs()

local STATE_FILE = "SillChessBot_State.json"
local AUTORUN_FILE = "SillChessBot_AutoExec.lua"

local Settings = {
    AutoPlay = true,
    AutoQueue = true,
    PostGameAction = "New Game",
    TimeMode = "3 min",
    BotName = "Master - Apex (2800)",
    BotLevel = 10,
    BotDepth = 6,
    FastModeAutoCap = true,
    FastModeMaxDepth = 4,
    MinDelay = 0.2,
    MaxDelay = 0.8,
}

local function normalizeTimeMode(val)
    local s = string.lower(tostring(val or ""))
    if string.find(s, "10") then return "10 min" end
    if string.find(s, "3") then return "3 min" end
    if string.find(s, "1") then return "1 min" end
    return "3 min"
end

local function saveSettings()
    if type(writefile) == "function" then
        pcall(function()
            writefile(STATE_FILE, HttpService:JSONEncode(Settings))
        end)
    end
end

local function loadSettings()
    if type(isfile) == "function" and type(readfile) == "function" then
        pcall(function()
            if isfile(STATE_FILE) then
                local data = HttpService:JSONDecode(readfile(STATE_FILE))
                if type(data) == "table" then
                    for k, v in pairs(data) do
                        if Settings[k] ~= nil then
                            Settings[k] = v
                        end
                    end
                    Settings.TimeMode = normalizeTimeMode(Settings.TimeMode)
                end
            else
                saveSettings()
            end
        end)
    end
end

loadSettings()

local function getQueueFunc()
    return (syn and syn.queue_on_teleport)
        or queue_on_teleport
        or (fluxus and fluxus.queue_on_teleport)
        or queueonteleport
        or (getgenv and (getgenv().queue_on_teleport or getgenv().queueonteleport))
end

local function registerAutoTeleport()
    if ENV.SillChess_TeleportQueued then return end
    local qFunc = getQueueFunc()
    if not qFunc then return end

    ENV.SillChess_TeleportQueued = true
    local payload = [[
        repeat task.wait(0.2) until game:IsLoaded() and game:GetService("Players").LocalPlayer
        task.wait(1.2)
        if type(isfile) == "function" and isfile("]] .. AUTORUN_FILE .. [[") then
            loadfile("]] .. AUTORUN_FILE .. [[")()
        end
    ]]
    pcall(qFunc, payload)
end

local teleportConn = LocalPlayer.OnTeleport:Connect(function(state)
    saveSettings()
    if state == Enum.TeleportState.Started or state == Enum.TeleportState.InProgress then
        registerAutoTeleport()
    end
end)

local function loadLibrary()
    local urls = {
        "https://raw.githubusercontent.com/sillbuilt/Sill-UI/refs/heads/main/SilL-X-UI.lua",
        "https://raw.githubusercontent.com/sillbuilt/Sill-UI/refs/heads/main/SilL-UI.lua",
    }
    for _, url in ipairs(urls) do
        local ok, lib = pcall(function()
            local src = game:HttpGet(url)
            if not src or #src < 100 or string.find(src, "404: Not Found", 1, true) then
                error("Invalid source")
            end
            local fn = loadstring(src)
            return fn and fn() or nil
        end)
        if ok and type(lib) == "table" and lib.CreateWindow then
            return lib
        end
    end
    return nil
end

local SilL = loadLibrary()
local FULL_WINDOW_SIZE = UDim2.fromOffset(560, 620)

local Window = SilL and SilL:CreateWindow({
    Name = "Sill ChessDuels (Full Auto) ♟️",
    Subtitle = "Zero-Lag • SILL X UI • Custom Speed",
    Theme = "Ocean",
    Size = FULL_WINDOW_SIZE,
    Config = { Enabled = false }
})

local function notify(title, content, nType)
    if SilL and SilL.Notify then
        pcall(function()
            SilL:Notify({
                Title = title,
                Content = content,
                Type = nType or "Info",
                Duration = 2.5
            })
        end)
    end
end

local createdScreenGui = Window and Window.Gui or nil

-- 📌 ระบบพับและกางหน้าต่างแบบตรึงแถบด้านบน (Topbar อยู่กับที่ เมนูไหลลงด้านล่าง)
local function patchMinimizeButton()
    task.spawn(function()
        task.wait(0.35)

        local parentsToSearch = {}
        if Window and Window.Gui then
            table.insert(parentsToSearch, Window.Gui)
        end
        pcall(function() if type(gethui) == "function" then table.insert(parentsToSearch, gethui()) end end)
        pcall(function() table.insert(parentsToSearch, CoreGui) end)
        pcall(function()
            local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            if pg then table.insert(parentsToSearch, pg) end
        end)

        for _, root in ipairs(parentsToSearch) do
            for _, desc in ipairs(root:GetDescendants()) do
                if (desc:IsA("TextLabel") or desc:IsA("TextButton")) and string.find(desc.Text or "", "Sill ChessDuels", 1, true) then
                    local currGui = desc:FindFirstAncestorOfClass("ScreenGui")
                    if currGui then
                        createdScreenGui = currGui
                    end

                    local topbar = desc.Parent
                    local mainFrame = topbar and topbar.Parent
                    if not (mainFrame and mainFrame:IsA("Frame") and mainFrame.Size.Y.Offset >= 250) then
                        mainFrame = desc.Parent
                        while mainFrame and mainFrame ~= root do
                            if mainFrame:IsA("Frame") and mainFrame.Size.Y.Offset >= 250 then
                                break
                            end
                            mainFrame = mainFrame.Parent
                        end
                    end

                    if mainFrame and mainFrame:IsA("Frame") then
                        local actualTopbar = nil
                        local bodyFrame = nil
                        for _, ch in ipairs(mainFrame:GetChildren()) do
                            if ch:IsA("Frame") then
                                if ch.Size.Y.Offset > 0 and ch.Size.Y.Offset <= 55 then
                                    actualTopbar = ch
                                else
                                    bodyFrame = ch
                                end
                            end
                        end

                        -- หาโฟลเดอร์กรอบโปรไฟล์มุมซ้ายล่าง (userBox) เพื่อซ่อนไม่ให้ดันขึ้นมาทับแถบบนเวลาหดหน้าต่าง
                        local userBoxFrame = nil
                        if bodyFrame then
                            for _, sub in ipairs(bodyFrame:GetDescendants()) do
                                if sub:IsA("Frame") and sub.AnchorPoint.Y == 1 and sub.Size.Y.Offset == 40 then
                                    userBoxFrame = sub
                                    break
                                end
                            end
                        end

                        mainFrame.ClipsDescendants = true
                        local originalSize = mainFrame.Size
                        local isMinimized = false
                        local activeTween = nil

                        local searchScope = actualTopbar or mainFrame
                        for _, sub in ipairs(searchScope:GetDescendants()) do
                            if sub:IsA("TextButton") or sub:IsA("TextLabel") then
                                local t = string.gsub(sub.Text or "", "%s+", "")
                                if t == "-" or t == "−" or t == "–" or string.lower(sub.Name) == "minimize" then
                                    local btn = sub:IsA("GuiButton") and sub or (sub.Parent and sub.Parent:IsA("GuiButton") and sub.Parent) or sub

                                    if type(getconnections) == "function" and btn:IsA("GuiButton") then
                                        pcall(function()
                                            for _, c in ipairs(getconnections(btn.MouseButton1Click)) do c:Disable() end
                                            for _, c in ipairs(getconnections(btn.Activated)) do c:Disable() end
                                        end)
                                    end

                                    local function getScaleFactor()
                                        local uiScale = mainFrame:FindFirstChildOfClass("UIScale")
                                        return uiScale and uiScale.Scale or 1
                                    end

                                    local function toggleMinimize()
                                        if activeTween then
                                            pcall(function() activeTween:Cancel() end)
                                        end

                                        isMinimized = not isMinimized
                                        if Window then Window.Minimized = isMinimized end
                                        mainFrame.ClipsDescendants = true

                                        local topH = (actualTopbar and actualTopbar.Size.Y.Offset > 0) and actualTopbar.Size.Y.Offset or 42
                                        local scale = getScaleFactor()

                                        if isMinimized then
                                            if mainFrame.Size.Y.Offset > 100 then
                                                originalSize = mainFrame.Size
                                            end
                                            if sub:IsA("TextLabel") or sub:IsA("TextButton") then sub.Text = "+" end

                                            -- ซ่อนกรอบโปรไฟล์และปุ่ม Resize ทันทีก่อนรูดเก็บ เพื่อให้เมนูไหลขึ้นแบบคลีนๆ
                                            if userBoxFrame then userBoxFrame.Visible = false end
                                            for _, ch in ipairs(mainFrame:GetChildren()) do
                                                if ch:IsA("TextButton") then ch.Visible = false end
                                            end

                                            local currentH = mainFrame.Size.Y.Offset
                                            local deltaY = ((currentH - topH) * 0.5) * scale
                                            local targetPos = UDim2.new(
                                                mainFrame.Position.X.Scale,
                                                mainFrame.Position.X.Offset,
                                                mainFrame.Position.Y.Scale,
                                                mainFrame.Position.Y.Offset - deltaY
                                            )

                                            activeTween = TweenService:Create(mainFrame, TweenInfo.new(0.24, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                                                Size = UDim2.fromOffset(originalSize.X.Offset, topH),
                                                Position = targetPos
                                            })
                                            activeTween:Play()
                                            activeTween.Completed:Connect(function()
                                                if isMinimized and bodyFrame then
                                                    bodyFrame.Visible = false
                                                end
                                            end)
                                        else
                                            if sub:IsA("TextLabel") or sub:IsA("TextButton") then sub.Text = "–" end

                                            -- เปิด Body ให้พร้อมไหลลงมาจากใต้แถบหัวด้านบน
                                            if bodyFrame then bodyFrame.Visible = true end
                                            if userBoxFrame then userBoxFrame.Visible = false end

                                            local currentH = mainFrame.Size.Y.Offset
                                            local targetH = originalSize.Y.Offset
                                            local deltaY = ((targetH - currentH) * 0.5) * scale
                                            local targetPos = UDim2.new(
                                                mainFrame.Position.X.Scale,
                                                mainFrame.Position.X.Offset,
                                                mainFrame.Position.Y.Scale,
                                                mainFrame.Position.Y.Offset + deltaY
                                            )

                                            activeTween = TweenService:Create(mainFrame, TweenInfo.new(0.26, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                                                Size = originalSize,
                                                Position = targetPos
                                            })
                                            activeTween:Play()
                                            activeTween.Completed:Connect(function()
                                                if not isMinimized then
                                                    if userBoxFrame then userBoxFrame.Visible = true end
                                                    for _, ch in ipairs(mainFrame:GetChildren()) do
                                                        if ch:IsA("TextButton") then ch.Visible = true end
                                                    end
                                                end
                                            end)
                                        end
                                    end

                                    if btn:IsA("GuiButton") then
                                        btn.Activated:Connect(toggleMinimize)
                                    else
                                        btn.InputBegan:Connect(function(input)
                                            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                                                toggleMinimize()
                                            end
                                        end)
                                    end
                                    return
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
end

local trackedTextElements = {}

local function getScreenGuiOf(inst)
    local curr = inst.Parent
    while curr and curr ~= LocalPlayer do
        if curr:IsA("ScreenGui") then return curr end
        curr = curr.Parent
    end
    return nil
end

local function isOurOwnUI(inst)
    local sGui = getScreenGuiOf(inst)
    if not sGui then return false end
    if sGui == createdScreenGui then return true end
    if string.find(string.lower(sGui.Name), "sill") then return true end
    return false
end

local function registerTextElement(inst)
    if inst:IsA("TextLabel") or inst:IsA("TextButton") then
        if not isOurOwnUI(inst) then
            trackedTextElements[inst] = true
        end
    end
end

local playerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
local descAddedConn, descRemovingConn

if playerGui then
    for _, desc in ipairs(playerGui:GetDescendants()) do
        registerTextElement(desc)
    end
    descAddedConn = playerGui.DescendantAdded:Connect(registerTextElement)
    descRemovingConn = playerGui.DescendantRemoving:Connect(function(inst)
        trackedTextElements[inst] = nil
    end)
end

local function isElementVisible(guiObj)
    if not guiObj or not guiObj.Parent or not guiObj:IsA("GuiObject") then return false end
    if isOurOwnUI(guiObj) then return false end
    if not guiObj.Visible then return false end
    if guiObj.AbsoluteSize.X < 8 or guiObj.AbsoluteSize.Y < 8 then return false end

    local curr = guiObj.Parent
    while curr and curr ~= LocalPlayer do
        if curr:IsA("GuiObject") and not curr.Visible then
            return false
        elseif curr:IsA("ScreenGui") and not curr.Enabled then
            return false
        end
        curr = curr.Parent
    end
    return true
end

local function findBestClickableTarget(labelOrBtn)
    local curr = labelOrBtn
    for _ = 1, 5 do
        if not curr or curr:IsA("ScreenGui") then break end
        if curr:IsA("GuiButton") then return curr end
        curr = curr.Parent
    end
    if labelOrBtn.Parent and labelOrBtn.Parent:IsA("GuiObject") then
        return labelOrBtn.Parent
    end
    return labelOrBtn
end

local function clickGuiElement(rawElement)
    if not isElementVisible(rawElement) then return false end

    local target = findBestClickableTarget(rawElement)
    local candidates = { target, rawElement }
    if target.Parent and target.Parent:IsA("GuiObject") then
        table.insert(candidates, target.Parent)
    end

    for _, obj in ipairs(candidates) do
        if obj:IsA("GuiButton") then
            if type(firesignal) == "function" then
                pcall(function() firesignal(obj.MouseButton1Down) end)
                pcall(function() firesignal(obj.MouseButton1Up) end)
                pcall(function() firesignal(obj.MouseButton1Click) end)
                pcall(function() firesignal(obj.Activated) end)
            end
            if type(getconnections) == "function" then
                pcall(function()
                    for _, c in ipairs(getconnections(obj.MouseButton1Down)) do pcall(function() c:Fire() end) end
                    for _, c in ipairs(getconnections(obj.MouseButton1Up)) do pcall(function() c:Fire() end) end
                    for _, c in ipairs(getconnections(obj.MouseButton1Click)) do pcall(function() c:Fire() end) end
                    for _, c in ipairs(getconnections(obj.Activated)) do pcall(function() c:Fire() end) end
                end)
            end
        end
    end

    pcall(function()
        local pos = target.AbsolutePosition
        local size = target.AbsoluteSize
        local inset = GuiService:GetGuiInset()
        local clickX = math.floor(pos.X + (size.X * 0.5))
        local clickY = math.floor(pos.Y + (size.Y * 0.5) + inset.Y)

        VirtualInputManager:SendMouseMoveEvent(clickX, clickY, game)
        task.wait(0.03)
        VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, true, game, 1)
        task.wait(0.05)
        VirtualInputManager:SendMouseButtonEvent(clickX, clickY, 0, false, game, 1)
    end)

    return true
end

local function normalizeText(str)
    local s = string.lower(tostring(str or ""))
    return string.gsub(s, "^%s*(.-)%s*$", "%1")
end

local function stripSpaces(str)
    return string.gsub(normalizeText(str), "%s+", "")
end

local function findVisibleElementsByText(targets, exactOnly)
    local results = {}
    for desc in pairs(trackedTextElements) do
        if not desc.Parent then
            trackedTextElements[desc] = nil
        elseif isElementVisible(desc) then
            local txt = normalizeText(desc.Text)
            if #txt > 0 and #txt < 40 then
                for _, t in ipairs(targets) do
                    local targetNorm = normalizeText(t)
                    if txt == targetNorm or (not exactOnly and string.find(txt, targetNorm, 1, true)) then
                        table.insert(results, desc)
                        break
                    end
                end
            end
        end
    end
    return results
end

local function findTimeModeButtons(modeStr)
    local mode = normalizeTimeMode(modeStr)
    local num = string.match(mode, "%d+") or "3"
    local validPatterns = {
        [num .. "min"] = true,
        [num .. "mins"] = true,
        [num .. "minute"] = true,
        [num .. "minutes"] = true,
        [num .. "m"] = true,
        [num .. ":00"] = true,
    }

    local results = {}
    for desc in pairs(trackedTextElements) do
        if not desc.Parent then
            trackedTextElements[desc] = nil
        elseif isElementVisible(desc) then
            local compact = stripSpaces(desc.Text)
            if validPatterns[compact] then
                table.insert(results, desc)
            end
        end
    end
    return results
end

local function selectDesiredTimeMode()
    local timeButtons = findTimeModeButtons(Settings.TimeMode)
    local clickedAny = false
    for _, el in ipairs(timeButtons) do
        if clickGuiElement(el) then
            clickedAny = true
            task.wait(0.12)
        end
    end
    return clickedAny
end

local cachedScreenState = nil
local lastScreenCheck = 0

local function isLobbyOrPostGameVisible(forceRefresh)
    if not forceRefresh and (os.clock() - lastScreenCheck) < 0.35 then
        return cachedScreenState
    end
    lastScreenCheck = os.clock()

    local lobbyBtns = findVisibleElementsByText({ "play now" }, true)
    if #lobbyBtns > 0 then
        cachedScreenState = "LOBBY"
        return "LOBBY"
    end

    local postBtns = findVisibleElementsByText({
        "new game",
        "rematch",
        "you won",
        "you lost",
        "game review",
        "by resignation",
        "by checkmate",
        "by timeout",
        "by abandonment"
    }, false)

    if #postBtns > 0 then
        cachedScreenState = "POSTGAME"
        return "POSTGAME"
    end

    cachedScreenState = nil
    return nil
end

local lastQueueAction = 0

local function executeLobbyOrPostGameClick(screenState)
    if os.clock() - lastQueueAction < 2.8 then return end
    lastQueueAction = os.clock()

    if screenState == "POSTGAME" then
        selectDesiredTimeMode()
        task.wait(0.25)

        local postTargets = findVisibleElementsByText({ Settings.PostGameAction, "new game" }, true)
        if #postTargets == 0 then
            postTargets = findVisibleElementsByText({ Settings.PostGameAction, "new game" }, false)
        end
        for _, el in ipairs(postTargets) do
            clickGuiElement(el)
            task.wait(0.15)
        end
        notify("🔄 Auto New Game", "กดปุ่ม " .. Settings.PostGameAction .. " (" .. Settings.TimeMode .. ") แล้ว!", "Success")

    elseif screenState == "LOBBY" then
        selectDesiredTimeMode()
        task.wait(0.45)
        selectDesiredTimeMode()
        task.wait(0.25)

        local playNowTargets = findVisibleElementsByText({ "play now" }, true)
        for _, el in ipairs(playNowTargets) do
            clickGuiElement(el)
            task.wait(0.15)
        end
        notify("⚔️ Auto Queue", "ล็อกโหมด " .. Settings.TimeMode .. " และกด Play now แล้ว!", "Info")
    end
end

local PlayMove = ReplicatedStorage:WaitForChild("ChessRemotes"):WaitForChild("Action")
local Bot = require(ReplicatedStorage:WaitForChild("Chess"):WaitForChild("Bot"))

local cachedCurrentFns = {}
local lastGcScanTime = 0

local function clearMatchCache()
    table.clear(cachedCurrentFns)
    lastGcScanTime = 0
end

local function getActiveMatchObj()
    for i = #cachedCurrentFns, 1, -1 do
        local fn = cachedCurrentFns[i]
        local ok, obj = pcall(fn)
        if ok and type(obj) == "table" and obj.state and type(obj.state.board) == "table" then
            if not (rawget(obj, "ended") == true or rawget(obj.state, "ended") == true) then
                return obj
            end
        end
    end

    if os.clock() - lastGcScanTime < 1.5 then
        return nil
    end
    lastGcScanTime = os.clock()

    if type(filtergc) == "function" then
        local ok, found = pcall(function()
            return filtergc("function", { Name = "current" })
        end)
        if ok and type(found) == "table" then
            cachedCurrentFns = found
            for i = #found, 1, -1 do
                local s, obj = pcall(found[i])
                if s and type(obj) == "table" and obj.state and type(obj.state.board) == "table" then
                    if not (rawget(obj, "ended") == true or rawget(obj.state, "ended") == true) then
                        return obj
                    end
                end
            end
        end
    end

    return nil
end

local function getBoardSignature(State)
    local parts = table.create(66)
    parts[1] = tostring(State.turn)
    parts[2] = tostring(State.full or 0)
    for i = 1, 64 do
        parts[i + 2] = tostring(State.board[i] or 0)
    end
    return table.concat(parts, ",")
end

local function getMyColor(gameObj)
    for _, key in ipairs({ "color", "side", "myColor", "playerColor" }) do
        local v = rawget(gameObj, key)
        if v == 1 or v == -1 then return v end
        if v == "w" or v == "white" or v == "White" then return 1 end
        if v == "b" or v == "black" or v == "Black" then return -1 end
    end
    local w = rawget(gameObj, "white") or rawget(gameObj, "White")
    local b = rawget(gameObj, "black") or rawget(gameObj, "Black")
    if w == LocalPlayer or w == LocalPlayer.Name or w == LocalPlayer.UserId then return 1 end
    if b == LocalPlayer or b == LocalPlayer.Name or b == LocalPlayer.UserId then return -1 end
    return nil
end

local function getEffectiveDepth()
    local depth = Settings.BotDepth
    if Settings.FastModeAutoCap and (Settings.TimeMode == "1 min" or Settings.TimeMode == "3 min") then
        depth = math.min(depth, Settings.FastModeMaxDepth)
    end
    return depth
end

local function computeBestMove(State)
    local WKing, BKing = 5, 61
    for i = 1, 64 do
        if State.board[i] == 6 then WKing = i
        elseif State.board[i] == -6 then BKing = i end
    end

    local VirtualGame = {
        board = table.clone(State.board),
        turn = State.turn,
        castle = table.clone(State.castle),
        ep = State.ep,
        half = State.half,
        full = State.full,
        kings = { [1] = WKing, [-1] = BKing },
    }

    local activeDepth = getEffectiveDepth()

    local ok, _, bestMove = pcall(function()
        return Bot.analyze(VirtualGame, activeDepth, Settings.BotLevel)
    end)

    if ok and bestMove then return bestMove end
    return nil
end

local function sendMove(bestMove)
    pcall(function()
        PlayMove:FireServer("move", {
            from = bestMove.from,
            to = bestMove.to,
            promo = bestMove.promo or 0,
        })
    end)
end

if Window then
    local MainTab = Window:CreateTab("Full Auto Bot", 10886548710)
    local ControlSection = MainTab:CreateSection("ระบบอัตโนมัติครบวงจร (Full Auto-Play)")

    ControlSection:CreateToggle({
        Name = "🤖 เดินหมากอัตโนมัติ (Auto Play)",
        Description = "บอทคำนวณและเดินเองทันทีเมื่ออยู่ในกระดานแข่ง",
        CurrentValue = Settings.AutoPlay,
        Callback = function(Value)
            Settings.AutoPlay = Value
            saveSettings()
        end
    })

    ControlSection:CreateToggle({
        Name = "🔄 เลือกเวลา & กด Play now / New Game อัตโนมัติ",
        Description = "กดหาห้องเองและเริ่มเกมใหม่หลังจบเกมอัตโนมัติ",
        CurrentValue = Settings.AutoQueue,
        Callback = function(Value)
            Settings.AutoQueue = Value
            saveSettings()
        end
    })

    ControlSection:CreateDropdown({
        Name = "⏱️ โหมดเวลาที่จะเล่น (Time Mode)",
        Description = "คลิกเลือกปุ่ม 1 min, 3 min หรือ 10 min ก่อนกด Play now",
        Options = { "1 min", "3 min", "10 min" },
        CurrentOption = Settings.TimeMode,
        Callback = function(Option)
            local rawOpt = type(Option) == "table" and Option[1] or Option
            Settings.TimeMode = normalizeTimeMode(rawOpt)
            saveSettings()
            task.spawn(function()
                selectDesiredTimeMode()
                notify("⏱️ ตั้งค่าโหมดเวลา", "เลือกโหมด: " .. Settings.TimeMode .. " (Depth จริง: " .. getEffectiveDepth() .. ")", "Success")
            end)
        end
    })

    ControlSection:CreateDropdown({
        Name = "🏆 ปุ่มที่จะกดหลังจบเกม (Post-Game Action)",
        Description = "เลือกให้กด New Game หรือ Rematch",
        Options = { "New Game", "Rematch" },
        CurrentOption = Settings.PostGameAction,
        Callback = function(Option)
            Settings.PostGameAction = type(Option) == "table" and tostring(Option[1] or "New Game") or tostring(Option or "New Game")
            saveSettings()
        end
    })

    ControlSection:CreateButton({
        Name = "🎯 บังคับเดินหมาก 1 ตาเดี๋ยวนี้ (Manual Move)",
        Description = "กดเพื่อบังคับให้บอทคำนวณและเดินทันที",
        Callback = function()
            local obj = getActiveMatchObj()
            if obj and obj.state then
                local move = computeBestMove(obj.state)
                if move then sendMove(move) end
            end
        end
    })

    local ConfigSection = MainTab:CreateSection("ตั้งค่าโปรไฟล์บอท & ปรับความเร็วแยกอิสระ")

    local BotProfiles = {
        ["Beginner - Pip (200)"]        = { Level = 1, Depth = 1 },
        ["Beginner - Clover (500)"]     = { Level = 2, Depth = 1 },
        ["Casual - Bramble (800)"]      = { Level = 3, Depth = 2 },
        ["Casual - Maple (1100)"]       = { Level = 4, Depth = 2 },
        ["Intermediate - Flint (1400)"] = { Level = 5, Depth = 3 },
        ["Intermediate - Sable (1700)"] = { Level = 6, Depth = 3 },
        ["Advanced - Onyx (2000)"]      = { Level = 7, Depth = 4 },
        ["Advanced - Vesper (2300)"]    = { Level = 8, Depth = 4 },
        ["Master - Titan (2600)"]       = { Level = 9, Depth = 5 },
        ["Master - Apex (2800)"]        = { Level = 10, Depth = 6 }
    }

    local BotProfileNames = {
        "Beginner - Pip (200)",
        "Beginner - Clover (500)",
        "Casual - Bramble (800)",
        "Casual - Maple (1100)",
        "Intermediate - Flint (1400)",
        "Intermediate - Sable (1700)",
        "Advanced - Onyx (2000)",
        "Advanced - Vesper (2300)",
        "Master - Titan (2600)",
        "Master - Apex (2800)"
    }

    if not Settings.BotName then Settings.BotName = "Master - Apex (2800)" end

    local LevelSlider, DepthSlider

    ConfigSection:CreateDropdown({
        Name = "🧠 เลือกโปรไฟล์บอท (Bot Preset)",
        Description = "เลือกชื่อบอทเพื่อตั้งค่าเริ่มต้น (สามารถเลื่อนปรับแยกด้านล่างต่อได้)",
        Options = BotProfileNames,
        CurrentOption = Settings.BotName,
        Callback = function(Option)
            local rawOpt = type(Option) == "table" and Option[1] or Option
            Settings.BotName = rawOpt

            local profile = BotProfiles[rawOpt]
            if profile then
                Settings.BotLevel = profile.Level
                Settings.BotDepth = profile.Depth
                pcall(function() if LevelSlider and LevelSlider.Set then LevelSlider:Set(profile.Level, true) end end)
                pcall(function() if DepthSlider and DepthSlider.Set then DepthSlider:Set(profile.Depth, true) end end)
                saveSettings()
                notify("🧠 อัปเดตโปรไฟล์บอท", rawOpt .. " | Level: " .. profile.Level .. ", Depth: " .. getEffectiveDepth(), "Success")
            end
        end
    })

    LevelSlider = ConfigSection:CreateSlider({
        Name = "🎯 ปรับระดับความแม่นยำแยก (Bot Level)",
        Description = "ยิ่งสูงยิ่งเดินแม่น (Apex = 10)",
        Range = { 1, 10 },
        Min = 1, Max = 10, Increment = 1, Step = 1, Decimals = 0,
        CurrentValue = Settings.BotLevel,
        Callback = function(Value)
            Settings.BotLevel = Value
            saveSettings()
        end
    })

    DepthSlider = ConfigSection:CreateSlider({
        Name = "⚡ ปรับความลึก/ความเร็วคิดแยก (Bot Depth)",
        Description = "ลดค่านี้ถ้าบอทคิดช้าเกินไป (แนะนำ 4 สำหรับ 3 นาที, 6 สำหรับ 10 นาที)",
        Range = { 1, 6 },
        Min = 1, Max = 6, Increment = 1, Step = 1, Decimals = 0,
        CurrentValue = Settings.BotDepth,
        Callback = function(Value)
            Settings.BotDepth = Value
            saveSettings()
        end
    })

    ConfigSection:CreateToggle({
        Name = "🚀 เร่งความเร็วอัตโนมัติในโหมด 1-3 นาที (Turbo Cap)",
        Description = "จำกัด Depth ไม่ให้เกินค่าด้านล่างเมื่อเล่น 1 หรือ 3 นาที เพื่อป้องกันแพ้เวลา",
        CurrentValue = Settings.FastModeAutoCap,
        Callback = function(Value)
            Settings.FastModeAutoCap = Value
            saveSettings()
        end
    })

    ConfigSection:CreateSlider({
        Name = "🔥 เพดาน Depth สูงสุดตอนเล่น 1-3 นาที (Max Fast Depth)",
        Description = "หากเปิด Turbo Cap บอทจะใช้ Depth ไม่เกินค่านี้ในโหมดเกมเร็ว (แนะนำ 4)",
        Range = { 1, 6 },
        Min = 1, Max = 6, Increment = 1, Step = 1, Decimals = 0,
        CurrentValue = Settings.FastModeMaxDepth,
        Callback = function(Value)
            Settings.FastModeMaxDepth = Value
            saveSettings()
        end
    })

    local DelaySection = MainTab:CreateSection("ตั้งค่าดีเลย์การเดินหมาก")

    DelaySection:CreateSlider({
        Name = "⏳ ดีเลย์สุ่มขั้นต่ำ (วินาที)",
        Range = { 0, 10 },
        Min = 0, Max = 10, Increment = 0.1, Step = 0.1, Decimals = 1, Suffix = "s",
        CurrentValue = Settings.MinDelay,
        Callback = function(Value) Settings.MinDelay = Value saveSettings() end
    })

    DelaySection:CreateSlider({
        Name = "⌛ ดีเลย์สุ่มสูงสุด (วินาที)",
        Range = { 0, 15 },
        Min = 0, Max = 15, Increment = 0.1, Step = 0.1, Decimals = 1, Suffix = "s",
        CurrentValue = Settings.MaxDelay,
        Callback = function(Value) Settings.MaxDelay = Value saveSettings() end
    })

    patchMinimizeButton()
end

local running = true

ENV.SillChessBotCleanup = function()
    running = false
    if teleportConn then pcall(function() teleportConn:Disconnect() end) end
    if descAddedConn then pcall(function() descAddedConn:Disconnect() end) end
    if descRemovingConn then pcall(function() descRemovingConn:Disconnect() end) end
    if SilL and SilL.Destroy then pcall(function() SilL:Destroy() end) end
    if createdScreenGui then pcall(function() createdScreenGui:Destroy() end) end
    destroyOldUIs()
end
_G.SillChessBotCleanup = ENV.SillChessBotCleanup

task.spawn(function()
    local lastHandledSig = ""
    local lastAttemptTime = 0
    local retryCount = 0

    while running do
        local menuState = isLobbyOrPostGameVisible(false)

        if menuState ~= nil then
            lastHandledSig = ""
            retryCount = 0
            clearMatchCache()

            if Settings.AutoQueue then
                executeLobbyOrPostGameClick(menuState)
            end

            task.wait(0.6)
            continue
        end

        if Settings.AutoPlay then
            local gameObj = getActiveMatchObj()
            local State = gameObj and gameObj.state

            if State and State.board then
                local myColor = getMyColor(gameObj)
                if not myColor or State.turn == myColor then
                    local currentSig = getBoardSignature(State)
                    if currentSig ~= lastHandledSig then
                        retryCount = 0
                    end

                    local canRetry = (retryCount < 3) and ((os.clock() - lastAttemptTime) > 1.5)

                    if currentSig ~= lastHandledSig or canRetry then
                        local turnStart = os.clock()
                        local actualMin = math.min(Settings.MinDelay, Settings.MaxDelay)
                        local actualMax = math.max(Settings.MinDelay, Settings.MaxDelay)
                        local targetDelay = actualMin + (math.random() * (actualMax - actualMin))

                        local bestMove = computeBestMove(State)
                        local aborted = false

                        while (os.clock() - turnStart) < targetDelay do
                            if not running or not Settings.AutoPlay or isLobbyOrPostGameVisible(false) ~= nil then
                                aborted = true
                                break
                            end
                            local latestObj = getActiveMatchObj()
                            local latestState = latestObj and latestObj.state
                            if not latestState or getBoardSignature(latestState) ~= currentSig then
                                aborted = true
                                break
                            end
                            task.wait(0.06)
                        end

                        if not aborted and bestMove and Settings.AutoPlay and running then
                            sendMove(bestMove)
                            lastHandledSig = currentSig
                            lastAttemptTime = os.clock()
                            retryCount += 1
                        end
                    end
                end
            end
        end

        task.wait(0.1)
    end
end)

notify("พร้อมใช้งาน!", "โหลด SILL X UI แบบล็อกแถบหัวไหลลงล่างเรียบร้อย", "Success")
]==]

if type(writefile) == "function" then
    pcall(writefile, AUTORUN_FILE, BOT_SOURCE)
end

local fn, err = loadstring(BOT_SOURCE)
if fn then
    fn()
else
    warn("[Sill ChessBot Error]:", err)
end
