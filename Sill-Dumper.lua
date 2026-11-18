--!strict
--[[
    ========================================================================
    Sill ChessDuels Bot (Cross-Server Persistence + Auto-Queue Edition)
    - รองรับ queue_on_teleport ฉีดสคริปต์ตามไปห้องใหม่อัตโนมัติไม่ต้องกด Execute ซ้ำ
    - บันทึกและโหลดการตั้งค่าด้วย JSON อิสระ (ไม่หายเมื่อย้ายห้อง)
    - สแกนกดปุ่ม "Play now" / เลือกโหมดเวลา (1 min, 3 min, 10 min) อัตโนมัติ
    ========================================================================
]]

-- รอให้เกมและตัวละครโหลดเสร็จสมบูรณ์ก่อนทำงาน (สำคัญมากตอนเพิ่งย้ายห้องมา)
if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    task.wait(0.2)
    LocalPlayer = Players.LocalPlayer
end

-- ป้องกันการรันซ้ำซ้อนในห้องเดิม
if _G.SillChessBotCleanup then
    pcall(_G.SillChessBotCleanup)
end

-- ========================================================================
-- 📌 1. ระบบบันทึกการตั้งค่าถาวร (JSON State Persistence)
-- ========================================================================
local STATE_FILE = "SillChessBot_State.json"
local LOADER_FILE = "SillChessBot_AutoLoader.lua"

local Settings = {
    AutoPlay = false,
    AutoQueue = false,
    TimeMode = "10 min", -- "1 min", "3 min", "10 min"
    BotLevel = 4,
    BotDepth = 4,
    MinDelay = 0.5,
    MaxDelay = 2.0,
    AutoPersist = true
}

local function saveSettings()
    if type(writefile) == "function" then
        pcall(function()
            local encoded = HttpService:JSONEncode(Settings)
            writefile(STATE_FILE, encoded)
        end)
    end
end

local function loadSettings()
    if type(isfile) == "function" and type(readfile) == "function" then
        pcall(function()
            if isfile(STATE_FILE) then
                local decoded = HttpService:JSONDecode(readfile(STATE_FILE))
                if type(decoded) == "table" then
                    for k, v in pairs(decoded) do
                        if Settings[k] ~= nil then
                            Settings[k] = v
                        end
                    end
                end
            end
        end)
    end
end

-- โหลดค่าที่เคยตั้งไว้ทันทีก่อนสร้าง UI
loadSettings()

-- ========================================================================
-- 📌 2. โหลด SilL-UI และสร้างหน้าต่างควบคุม
-- ========================================================================
local okUI, SilL = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/sillbuilt/Sill-UI/refs/heads/main/SilL-UI.lua"))()
end)

if not okUI or not SilL then
    warn("[Sill ChessBot] ไม่สามารถโหลด SilL-UI ได้")
    return
end

local Window = SilL:CreateWindow({
    Name = "Sill ChessDuels Bot ♟️",
    Subtitle = "Auto-Teleport & Auto-Queue",
    Theme = "Ocean",
    Size = UDim2.fromOffset(520, 560),
    Config = {
        Enabled = false -- เราใช้ระบบ JSON ของเราเองที่เสถียรกว่า 100%
    }
})

-- ========================================================================
-- 📌 3. ระบบคลิกปุ่ม "Play now" และหาห้องใหม่อัตโนมัติ
-- ========================================================================
local PlayMove = ReplicatedStorage:WaitForChild("ChessRemotes"):WaitForChild("Action")
local Bot = require(ReplicatedStorage:WaitForChild("Chess"):WaitForChild("Bot"))

-- ฟังก์ชันจำลองการคลิกปุ่ม GUI ใน Roblox (รองรับทั้ง firesignal และ VirtualInputManager)
local function triggerGuiButton(btn: GuiButton)
    if not btn or not btn.Visible then return false end

    local clicked = false
    if type(firesignal) == "function" then
        pcall(function()
            firesignal(btn.MouseButton1Click)
            firesignal(btn.Activated)
            clicked = true
        end)
    end

    if not clicked and type(getconnections) == "function" then
        pcall(function()
            for _, conn in ipairs(getconnections(btn.MouseButton1Click)) do
                conn:Fire()
                clicked = true
            end
            for _, conn in ipairs(getconnections(btn.Activated)) do
                conn:Fire()
                clicked = true
            end
        end)
    end

    -- Fallback: จำลองคลิกเมาส์ลงตำแหน่งปุ่มบนหน้าจอ
    if not clicked then
        pcall(function()
            local pos = btn.AbsolutePosition
            local size = btn.AbsoluteSize
            local centerX = pos.X + (size.X / 2)
            local centerY = pos.Y + (size.Y / 2) + 36 -- ชดเชยขอบ Topbar
            VirtualInputManager:SendMouseButtonEvent(centerX, centerY, 0, true, game, 1)
            task.wait(0.05)
            VirtualInputManager:SendMouseButtonEvent(centerX, centerY, 0, false, game, 1)
            clicked = true
        end)
    end

    return clicked
end

-- ค้นหาปุ่มที่มีข้อความตรงกับที่ระบุ (เช่น "Play now", "10 min", "Play Again")
local function findAndClickButtonByText(targetTexts: { string }): boolean
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return false end

    for _, desc in ipairs(playerGui:GetDescendants()) do
        if desc:IsA("TextLabel") or desc:IsA("TextButton") then
            local text = string.lower(desc.Text or "")
            for _, target in ipairs(targetTexts) do
                if text == string.lower(target) or string.find(text, string.lower(target), 1, true) then
                    -- หาตัว GuiButton แม่ข่ายที่กดได้
                    local clickable: Instance? = desc
                    while clickable and clickable ~= playerGui and not clickable:IsA("GuiButton") do
                        clickable = clickable.Parent
                    end
                    if clickable and clickable:IsA("GuiButton") and clickable.Visible then
                        if triggerGuiButton(clickable) then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

local lastQueueAttempt = 0
local function attemptAutoQueue()
    if os.clock() - lastQueueAttempt < 3.5 then return end
    lastQueueAttempt = os.clock()

    -- 1. เลือกโหมดเวลาตามที่ตั้งไว้ (1 min, 3 min, 10 min)
    pcall(function()
        findAndClickButtonByText({ Settings.TimeMode })
    end)
    task.wait(0.2)

    -- 2. กดปุ่ม Play now หรือปุ่มเล่นใหม่หลังจบเกม
    local clicked = findAndClickButtonByText({
        "Play now",
        "Play Again",
        "New Game",
        "Find Match",
        "Next Match"
    })

    -- 3. ยิง Remote เสริมเผื่อหน้าต่าง UI ถูกพับอยู่
    pcall(function()
        local secondsMap = { ["1 min"] = 60, ["3 min"] = 180, ["10 min"] = 600 }
        local sec = secondsMap[Settings.TimeMode] or 600
        PlayMove:FireServer("queue", { time = sec, mode = Settings.TimeMode })
        PlayMove:FireServer("play", Settings.TimeMode)
    end)

    if clicked then
        SilL:Notify({
            Title = "⚔️ Auto Queue",
            Content = "กดค้นหาห้องใหม่ (" .. Settings.TimeMode .. ") แล้ว!",
            Type = "Info",
            Duration = 2.5
        })
    end
end

-- ========================================================================
-- 📌 4. ระบบคำนวณและเดินหมากรุกความเร็วสูง
-- ========================================================================
local cachedCurrentFn = nil
local lastGcScan = 0

local function getActiveGameObj()
    if cachedCurrentFn then
        local ok, obj = pcall(cachedCurrentFn)
        if ok and type(obj) == "table" and obj.state and obj.state.board then
            return obj
        end
        cachedCurrentFn = nil
    end

    if os.clock() - lastGcScan < 0.5 then return nil end
    lastGcScan = os.clock()

    if type(filtergc) == "function" then
        local found = filtergc("function", { Name = "current" })
        if type(found) == "table" then
            for _, fn in ipairs(found) do
                local ok, obj = pcall(fn)
                if ok and type(obj) == "table" and obj.state and obj.state.board then
                    cachedCurrentFn = fn
                    return obj
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

    local ok, _, bestMove = pcall(function()
        return Bot.analyze(VirtualGame, Settings.BotDepth, Settings.BotLevel)
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

-- ========================================================================
-- 📌 5. สร้าง UI Elements (ดึงค่าเริ่มต้นจาก Settings ที่โหลดมา)
-- ========================================================================
local MainTab = Window:CreateTab("Chess Bot", 10886548710)
local ControlSection = MainTab:CreateSection("ควบคุมบอท & จับคู่อัตโนมัติ")

ControlSection:CreateToggle({
    Name = "🤖 โหมดเดินหมากอัตโนมัติ (Auto Play)",
    Description = "จำสถานะข้ามห้องอัตโนมัติ ไม่ต้องกดเปิดใหม่",
    CurrentValue = Settings.AutoPlay,
    Callback = function(Value)
        Settings.AutoPlay = Value
        saveSettings()
    end
})

ControlSection:CreateToggle({
    Name = "⚔️ กดหาห้องใหม่อัตโนมัติ (Auto Play Now / Queue)",
    Description = "กดปุ่ม Play now ในหน้าเมนูและหลังจบเกมให้อัตโนมัติ",
    CurrentValue = Settings.AutoQueue,
    Callback = function(Value)
        Settings.AutoQueue = Value
        saveSettings()
    end
})

ControlSection:CreateDropdown({
    Name = "⏱️ โหมดเวลาที่จะกดหาห้อง (Time Control)",
    Description = "เลือกโหมดเวลาบนหน้าเมนู Play (1 min, 3 min, 10 min)",
    Options = { "1 min", "3 min", "10 min" },
    CurrentOption = Settings.TimeMode,
    Callback = function(Option)
        if type(Option) == "table" then
            Settings.TimeMode = tostring(Option[1] or "10 min")
        else
            Settings.TimeMode = tostring(Option or "10 min")
        end
        saveSettings()
    end
})

ControlSection:CreateButton({
    Name = "🎯 บังคับเดินทันที 1 ตา (Manual Move)",
    Description = "คำนวณและเดินหมากทันทีโดยไม่รอดีเลย์",
    Callback = function()
        local gameObj = getActiveGameObj()
        if not gameObj then return end
        local move = computeBestMove(gameObj.state)
        if move then sendMove(move) end
    end
})

local ConfigSection = MainTab:CreateSection("ตั้งค่าความเก่ง & เวลาสุ่ม (Auto-Saved)")

ConfigSection:CreateSlider({
    Name = "🧠 ระดับความฉลาดบอท (Bot Level)",
    Description = "ความแม่นยำในการประเมินหมาก (1-10)",
    Min = 1, Max = 10,
    CurrentValue = Settings.BotLevel,
    Callback = function(Value)
        Settings.BotLevel = Value
        saveSettings()
    end
})

ConfigSection:CreateSlider({
    Name = "👁️ ความลึกการคิด (Depth)",
    Description = "แนะนำ 3-4 เพื่อความไว (5-6 จะใช้เวลาคิดนานขึ้น)",
    Min = 1, Max = 6,
    CurrentValue = Settings.BotDepth,
    Callback = function(Value)
        Settings.BotDepth = Value
        saveSettings()
    end
})

ConfigSection:CreateSlider({
    Name = "⏳ ดีเลย์สุ่มขั้นต่ำ (วินาที)",
    Description = "เวลาคิดน้อยที่สุดก่อนเดินหมาก",
    Min = 0, Max = 10,
    Increment = 0.1, Step = 0.1, Decimals = 1,
    CurrentValue = Settings.MinDelay,
    Callback = function(Value)
        Settings.MinDelay = Value
        saveSettings()
    end
})

ConfigSection:CreateSlider({
    Name = "⌛ ดีเลย์สุ่มสูงสุด (วินาที)",
    Description = "เวลาคิดนานที่สุดก่อนเดินหมาก",
    Min = 0, Max = 15,
    Increment = 0.1, Step = 0.1, Decimals = 1,
    CurrentValue = Settings.MaxDelay,
    Callback = function(Value)
        Settings.MaxDelay = Value
        saveSettings()
    end
})

-- ========================================================================
-- 📌 6. ระบบ queue_on_teleport (สืบทอดสคริปต์ข้ามเซิร์ฟเวอร์อัตโนมัติ)
-- ========================================================================
local function getQueueTeleportFunc()
    return (syn and syn.queue_on_teleport)
        or queue_on_teleport
        or (fluxus and fluxus.queue_on_teleport)
        or (queueonteleport)
end

local teleportQueued = false
local function setupTeleportPersistence()
    local qFunc = getQueueTeleportFunc()
    if not qFunc then
        warn("[Sill ChessBot] Executor ของคุณไม่รองรับ queue_on_teleport")
        return
    end

    -- ผูกกับ OnTeleport เพื่อบันทึกค่าล่าสุดและส่งโค้ดไปรันที่ห้องถัดไป
    LocalPlayer.OnTeleport:Connect(function()
        if teleportQueued or not Settings.AutoPersist then return end
        teleportQueued = true
        saveSettings()

        pcall(function()
            qFunc([[
                repeat task.wait() until game:IsLoaded()
                if type(isfile) == "function" and isfile("]] .. LOADER_FILE .. [[") then
                    loadfile("]] .. LOADER_FILE .. [[")()
                end
            ]])
        end)
    end)
end

setupTeleportPersistence()

-- ========================================================================
-- 📌 7. ลูปทำงานหลัก (สลับระหว่าง เดินหมากในเกม <-> กดหาห้องเมื่อจบเกม)
-- ========================================================================
local running = true
_G.SillChessBotCleanup = function()
    running = false
end

task.spawn(function()
    local lastHandledSig = ""
    local lastAttemptTime = 0
    local retryCount = 0

    while running do
        local gameObj = getActiveGameObj()
        local State = gameObj and gameObj.state

        if State and State.board then
            -- อยู่ในกระดานหมากรุกที่กำลังเล่นอยู่
            if Settings.AutoPlay then
                local myColor = getMyColor(gameObj)
                if not myColor or State.turn == myColor then
                    local currentSig = getBoardSignature(State)
                    if currentSig ~= lastHandledSig then
                        retryCount = 0
                    end

                    local canRetry = (retryCount < 2) and ((os.clock() - lastAttemptTime) > 1.8)
                    if currentSig ~= lastHandledSig or canRetry then
                        local turnStart = os.clock()
                        local actualMin = math.min(Settings.MinDelay, Settings.MaxDelay)
                        local actualMax = math.max(Settings.MinDelay, Settings.MaxDelay)
                        local targetDelay = actualMin + (math.random() * (actualMax - actualMin))

                        local bestMove = computeBestMove(State)

                        local aborted = false
                        while (os.clock() - turnStart) < targetDelay do
                            if not running or not Settings.AutoPlay then aborted = true break end
                            local latestObj = getActiveGameObj()
                            local latestState = latestObj and latestObj.state
                            if not latestState or getBoardSignature(latestState) ~= currentSig then
                                aborted = true
                                break
                            end
                            task.wait(0.03)
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
            task.wait(0.05)
        else
            -- ไม่ได้อยู่ในกระดาน (อยู่หน้าเมนู Play now หรือเพิ่งจบเกม)
            lastHandledSig = ""
            retryCount = 0

            if Settings.AutoQueue then
                attemptAutoQueue()
            end
            task.wait(0.8)
        end
    end
end)

SilL:Notify({
    Title = "พร้อมทำงานข้ามห้องอัตโนมัติ!",
    Content = string.format("สถานะ AutoPlay: %s | AutoQueue: %s", tostring(Settings.AutoPlay), tostring(Settings.AutoQueue)),
    Type = "Success",
    Duration = 4
})
