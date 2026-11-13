--[[
  AURORA HUB - FISCH (improved rebuild)
  Built by Friknnod
  Full auto-fish loop / perfect reel / auto sell / waypoints / player utils
  Custom glass UI: gradient accents, ripples, notifications, config save
  Toggle UI: RightShift
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local HttpService       = game:GetService("HttpService")
local Lighting          = game:GetService("Lighting")
local VirtualUser       = game:GetService("VirtualUser")

local player    = Players.LocalPlayer
local unpack    = table.unpack or unpack
local running   = true
local currentFPS, currentPing = 60, 0
local fishStatus = "idle"

--................................................................
-- CONFIG
--................................................................
local Config = {
    AutoFish   = false,
    AutoEquip  = true,
    AutoCast   = true,
    AutoShake  = true,
    AutoReel   = true,
    ReelMode   = "Perfect",
    CastDelay  = 1.2,
    ShakeDelay = 0.15,
    AutoSell   = false,
    SellInterval = 120,
    AntiAFK    = true,
    Noclip     = false,
    InfJump    = false,
    ApplySpeed = false,
    WalkSpeed  = 16,
    JumpPower  = 50,
    Watermark  = true,
    Blur       = false,
    Accent     = "Aurora",
}
local CONFIG_FILE = "Aurora_Fisch_Config.json"
local WAYPOINT_FILE = "Aurora_Fisch_Waypoints.json"

local function safeRead(file)
    if type(readfile) ~= "function" then return nil end
    local ok, exists = pcall(function() return isfile(file) end)
    if not (ok and exists) then return nil end
    local ok2, data = pcall(function() return readfile(file) end)
    if not ok2 then return nil end
    return data
end

local function safeWrite(file, data)
    if type(writefile) ~= "function" then return end
    pcall(function() writefile(file, data) end)
end

do
    local raw = safeRead(CONFIG_FILE)
    if raw then
        local ok, data = pcall(function() return HttpService:JSONDecode(raw) end)
        if ok and type(data) == "table" then
            for k, v in pairs(data) do
                if Config[k] ~= nil then Config[k] = v end
            end
        end
    end
end

local function saveConfig()
    safeWrite(CONFIG_FILE, HttpService:JSONEncode(Config))
end

--................................................................
-- REMOTES (Packages.Net wrapper + fallback scan)
--................................................................
local netOK, Net = pcall(function()
    local pkg = ReplicatedStorage:WaitForChild("Packages", 10)
    return pkg and pkg:WaitForChild("Net", 10) and require(pkg.Net)
end)

local remoteCache = {}
local function getRemote(name)
    if remoteCache[name] ~= nil then return remoteCache[name] or nil end
    local found
    if netOK and Net then
        local ok, res = pcall(function() return Net:RemoteEvent(name) end)
        if ok then found = res end
    end
    if not found then
        local pkg = ReplicatedStorage:FindFirstChild("Packages")
        local net = pkg and (pkg:FindFirstChild("Net") or pkg:FindFirstChild("_Net"))
        found = net and net:FindFirstChild(name)
    end
    remoteCache[name] = found or false
    return found
end

local function fireRemote(name, ...)
    local r = getRemote(name)
    if not r then return false end
    local args = { ... }
    local ok = pcall(function() r:FireServer(unpack(args)) end)
    if ok then return true end
    if #args > 0 then
        return pcall(function() r:FireServer() end)
    end
    return false
end

--................................................................
-- FISHING CORE
--................................................................
local function alive()
    local c = player.Character
    return c and c:FindFirstChildOfClass("Humanoid") and c:FindFirstChild("HumanoidRootPart")
end

local function getBobber()
    local c = player.Character
    if not c then return nil end
    return c:FindFirstChild("bobber") or c:FindFirstChild("Bobber")
end

local function reelGuiActive()
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then return false end
    for _, name in ipairs({ "reel", "Reel", "reelUI" }) do
        local g = pg:FindFirstChild(name)
        if g and g:IsA("ScreenGui") and g.Enabled then return true end
    end
    return false
end

local function equipRod()
    local c = player.Character
    if not c then return false end
    local held = c:FindFirstChildOfClass("Tool")
    if held and string.find(string.lower(held.Name), "rod") then return true end
    local bp = player:FindFirstChildOfClass("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and string.find(string.lower(t.Name), "rod") then
                local hum = c:FindFirstChildOfClass("Humanoid")
                if hum then hum:EquipTool(t) end
                return true
            end
        end
    end
    return false
end

local function autoSell()
    for _, name in ipairs({ "sellall", "SellAll", "sell" }) do
        if fireRemote(name) then
            return true
        end
    end
    -- fallback: merchant prompts
    local did = false
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") and d.ActionText
            and string.find(string.lower(d.ActionText), "sell") then
            if type(fireproximityprompt) == "function" then
                pcall(function() fireproximityprompt(d, 0) end)
            else
                pcall(function()
                    d.HoldDuration = 0
                    fireproximityprompt(d)
                end)
            end
            did = true
            break
        end
    end
    return did
end

-- master loop: cast management
task.spawn(function()
    while running do
        pcall(function()
            if not Config.AutoFish or not alive() then fishStatus = "idle" return end
            if Config.AutoEquip then equipRod() end
            if reelGuiActive() then fishStatus = "reeling" return end
            if getBobber() then fishStatus = "waiting / shake" return end
            fishStatus = "casting"
            if Config.AutoCast then fireRemote("casting", 100, false) end
            task.wait(math.max(Config.CastDelay, 0.3))
        end)
        task.wait(0.15)
    end
end)

-- shake loop
task.spawn(function()
    while running do
        if Config.AutoFish and Config.AutoShake and alive()
            and getBobber() and not reelGuiActive() then
            fishStatus = "shake"
            fireRemote("shake")
        end
        task.wait(math.max(Config.ShakeDelay, 0.05))
    end
end)

-- reel loop
task.spawn(function()
    while running do
        if Config.AutoFish and Config.AutoReel and reelGuiActive() then
            local pct
            if Config.ReelMode == "Safe" then
                pct = math.floor(55 + 40 * math.abs(math.sin(os.clock() * 2.5)))
            else
                pct = 100
            end
            fireRemote("reeling", pct)
            RunService.Heartbeat:Wait()
        else
            task.wait(0.1)
        end
    end
end)

-- auto sell loop
task.spawn(function()
    while running do
        task.wait(math.max(Config.SellInterval, 15))
        if Config.AutoSell and alive() then
            if autoSell() then notify("Auto Sell", "inventory sold") end
        end
    end
end)

-- anti-afk
player.Idled:Connect(function()
    if Config.AntiAFK then
        VirtualUser:CaptureController()
        VirtualUser:Click2(Vector2.new(), Vector2.new())
    end
end)

-- noclip
RunService.Stepped:Connect(function()
    if Config.Noclip and alive() then
        for _, p in ipairs(player.Character:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
        end
    end
end)

-- infinite jump
UserInputService.JumpRequest:Connect(function()
    if Config.InfJump and alive() then
        local hum = player.Character:FindFirstChildOfClass("Humanoid")
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
    end
end)

-- movement enforcement
task.spawn(function()
    while running do
        pcall(function()
            if Config.ApplySpeed and alive() then
                local hum = player.Character:FindFirstChildOfClass("Humanoid")
                hum.WalkSpeed = Config.WalkSpeed
                hum.UseJumpPower = true
                hum.JumpPower = Config.JumpPower
            end
        end)
        task.wait(0.5)
    end
end)

-- fps / ping meters
task.spawn(function()
    while running do
        local frames = 0
        local conn = RunService.RenderStepped:Connect(function() frames = frames + 1 end)
        task.wait(1)
        conn:Disconnect()
        currentFPS = frames
    end
end)

task.spawn(function()
    while running do
        pcall(function()
            local stats = game:GetService("Stats")
            local ss = stats:FindFirstChild("Network")
            ss = ss and ss:FindFirstChild("ServerStats")
            local dp = ss and ss:FindFirstChild("Data Ping")
            if dp then currentPing = math.floor(dp.Value + 0.5) end
        end)
        task.wait(1)
    end
end)

--................................................................
-- TELEPORTS
--................................................................
local Waypoints = {}
do
    local raw = safeRead(WAYPOINT_FILE)
    if raw then
        local ok, data = pcall(function() return HttpService:JSONDecode(raw) end)
        if ok and type(data) == "table" then Waypoints = data end
    end
end

local function saveWaypoints()
    safeWrite(WAYPOINT_FILE, HttpService:JSONEncode(Waypoints))
end

local ISLAND_NAMES = {
    "Moosewood", "Roslit Bay", "Sunstone Island", "Snowcap Island",
    "Ancient Isle", "Vertigo", "Desolate Deep", "Forsaken Shallows",
    "Harvestfall", "Terrapin Island", "Mushgrove", "Statue of Sovereignty",
    "Waveborne", "Lush Grove",
}

local function scanIslands()
    local found = {}
    local lowerWant = {}
    for _, n in ipairs(ISLAND_NAMES) do lowerWant[string.lower(n)] = n end
    for _, m in ipairs(workspace:GetDescendants()) do
        if m:IsA("Model") then
            local canon = lowerWant[string.lower(m.Name)]
            if canon and not table.find(found, canon) then
                table.insert(found, canon)
            end
        end
    end
    table.sort(found)
    return found
end

local function teleportTo(pos)
    local c = player.Character
    local hrp = c and c:FindFirstChild("HumanoidRootPart")
    if hrp then
        hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
    end
end

local function islandPosition(name)
    for _, m in ipairs(workspace:GetDescendants()) do
        if m:IsA("Model") and string.lower(m.Name) == string.lower(name) then
            local pivot = m:GetPivot()
            return pivot.Position + Vector3.new(0, 30, 0)
        end
    end
    return nil
end

--................................................................
-- THEME
--................................................................
local Accents = {
    Aurora = { c1 = Color3.fromRGB(0, 229, 195),   c2 = Color3.fromRGB(124, 92, 255) },
    Sunset = { c1 = Color3.fromRGB(255, 138, 76),  c2 = Color3.fromRGB(255, 64, 129) },
    Toxic  = { c1 = Color3.fromRGB(163, 230, 53),  c2 = Color3.fromRGB(34, 197, 94)  },
    Ice    = { c1 = Color3.fromRGB(125, 211, 252), c2 = Color3.fromRGB(99, 102, 241) },
}

local Theme = {
    Bg      = Color3.fromRGB(11, 14, 23),
    Card    = Color3.fromRGB(18, 22, 42),
    Card2   = Color3.fromRGB(26, 31, 56),
    Text    = Color3.fromRGB(235, 240, 255),
    SubText = Color3.fromRGB(148, 158, 190),
    Stroke  = Color3.fromRGB(60, 70, 120),
}

local accentGradients = {}
local accentSolids = {}
local watermark, blurEffect -- declared early so page callbacks close over them

local function accentPair()
    return Accents[Config.Accent] or Accents.Aurora
end

local function makeGradient(parent)
    local a = accentPair()
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new(a.c1, a.c2)
    g.Rotation = 90
    g.Parent = parent
    table.insert(accentGradients, g)
    return g
end

local function applyAccent()
    local a = accentPair()
    for _, g in ipairs(accentGradients) do
        g.Color = ColorSequence.new(a.c1, a.c2)
    end
    for _, inst in ipairs(accentSolids) do
        if inst.Parent then inst.BackgroundColor3 = a.c1 end
    end
end

--................................................................
-- UI HELPERS
--................................................................
local function create(class, props, children)
    local inst = Instance.new(class)
    for k, v in pairs(props) do
        if k ~= "Parent" then inst[k] = v end
    end
    if children then
        for _, c in ipairs(children) do c.Parent = inst end
    end
    if props.Parent then inst.Parent = props.Parent end
    return inst
end

local function corner(r)
    return create("UICorner", { CornerRadius = UDim.new(0, r) })
end

local function strokeOf(color, thick, transp)
    return create("UIStroke", {
        Color = color, Thickness = thick or 1,
        Transparency = transp or 0.4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })
end

local function pad(l, r, t, b)
    return create("UIPadding", {
        PaddingLeft = UDim.new(0, l), PaddingRight = UDim.new(0, r),
        PaddingTop = UDim.new(0, t), PaddingBottom = UDim.new(0, b),
    })
end

local function tween(inst, time, props, style, dir)
    local t = TweenService:Create(inst,
        TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
        props)
    t:Play()
    return t
end

local function ripple(parent, inputPos)
    if not parent:IsA("GuiObject") then return end
    local abs = parent.AbsolutePosition
    local rel = inputPos - abs
    local circle = create("Frame", {
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 0.65,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromOffset(rel.X, rel.Y),
        Size = UDim2.fromOffset(0, 0),
        ZIndex = parent.ZIndex + 5,
        Parent = parent,
    })
    corner(60).Parent = circle
    tween(circle, 0.45, {
        Size = UDim2.fromOffset(140, 140),
        BackgroundTransparency = 1,
    })
    game:GetService("Debris"):AddItem(circle, 0.5)
end

--................................................................
-- NOTIFICATIONS
--................................................................
local parentGui = (gethui and gethui()) or player:WaitForChild("PlayerGui")
do -- clear previous loads
    local old = parentGui:FindFirstChild("AuroraHub")
    if old then old:Destroy() end
end

local screenGui = create("ScreenGui", {
    Name = "AuroraHub", ResetOnSpawn = false, IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999,
    Parent = parentGui,
})
if syn and syn.protect_gui then pcall(function() syn.protect_gui(screenGui) end) end

local notifHolder = create("Frame", {
    AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.new(1, -16, 1, -16),
    Size = UDim2.fromOffset(300, 500),
    BackgroundTransparency = 1,
    Parent = screenGui,
})
create("UIListLayout", {
    FillDirection = Enum.FillDirection.Vertical,
    VerticalAlignment = Enum.VerticalAlignment.Bottom,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 8),
    Parent = notifHolder,
})

local notifId = 0
function notify(title, msg, dur)
    dur = dur or 4
    notifId = notifId + 1
    local a = accentPair()
    local card = create("CanvasGroup", {
        BackgroundColor3 = Theme.Card,
        Size = UDim2.new(1, 0, 0, 62),
        GroupTransparency = 1,
        LayoutOrder = notifId,
        Parent = notifHolder,
    })
    corner(12).Parent = card
    strokeOf(Theme.Stroke, 1, 0.35).Parent = card
    create("Frame", {
        BackgroundColor3 = a.c1, Size = UDim2.new(0, 3, 1, -14),
        Position = UDim2.new(0, 8, 0, 7), BorderSizePixel = 0, Parent = card,
    })
    create("TextLabel", {
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
        Text = title, TextSize = 14, TextColor3 = Theme.Text,
        Position = UDim2.new(0, 20, 0, 8), Size = UDim2.new(1, -28, 0, 16),
        TextXAlignment = Enum.TextXAlignment.Left, Parent = card,
    })
    create("TextLabel", {
        BackgroundTransparency = 1, Font = Enum.Font.Gotham,
        Text = msg, TextSize = 12, TextColor3 = Theme.SubText,
        TextWrapped = true,
        Position = UDim2.new(0, 20, 0, 27), Size = UDim2.new(1, -32, 0, 28),
        TextXAlignment = Enum.TextXAlignment.Left, Parent = card,
    })
    tween(card, 0.35, { GroupTransparency = 0 })
    task.delay(dur, function()
        if card.Parent then
            tween(card, 0.3, { GroupTransparency = 1 })
            task.wait(0.32)
            card:Destroy()
        end
    end)
end

--................................................................
-- MAIN WINDOW
--................................................................
create("ImageLabel", { -- drop shadow
    Name = "Shadow",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 6),
    Size = UDim2.new(1, 90, 1, 90),
    BackgroundTransparency = 1,
    Image = "rbxassetid://1316045217",
    ImageColor3 = Color3.fromRGB(0, 0, 0),
    ImageTransparency = 0.45,
    ScaleType = Enum.ScaleType.Slice,
    SliceCenter = Rect.new(49, 49, 450, 450),
    Parent = screenGui,
})

local main = create("Frame", {
    Name = "Main",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = UDim2.fromOffset(640, 440),
    BackgroundColor3 = Theme.Bg,
    BackgroundTransparency = 0.05,
    BorderSizePixel = 0,
    Parent = screenGui,
})
corner(16).Parent = main
local mainStroke = strokeOf(Theme.Stroke, 1.5, 0.25)
mainStroke.Parent = main
makeGradient(mainStroke)

-- header ----------------------------------------------------------
local header = create("Frame", {
    Size = UDim2.new(1, 0, 0, 46),
    BackgroundTransparency = 1,
    Parent = main,
})
pad(16, 12, 0, 0).Parent = header

local logo = create("TextLabel", {
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    Text = "AURORA",
    TextSize = 20,
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Position = UDim2.new(0, 16, 0, 10),
    Size = UDim2.new(0, 120, 0, 20),
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = header,
})
local logoGrad = makeGradient(logo)
logoGrad.Rotation = 0

create("TextLabel", {
    BackgroundTransparency = 1, Font = Enum.Font.Gotham,
    Text = "fisch · improved build · by Friknnod",
    TextSize = 12, TextColor3 = Theme.SubText,
    Position = UDim2.new(0, 17, 0, 30),
    Size = UDim2.new(0, 240, 0, 12),
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = header,
})

local clockChip = create("TextLabel", {
    BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
    Text = os.date("%H:%M"), TextSize = 12, TextColor3 = Theme.SubText,
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -180, 0, 15), Size = UDim2.new(0, 46, 0, 16),
    Parent = header,
})
local fpsChip = create("TextLabel", {
    BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
    Text = "60 fps", TextSize = 12, TextColor3 = Theme.SubText,
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -126, 0, 15), Size = UDim2.new(0, 60, 0, 16),
    TextXAlignment = Enum.TextXAlignment.Right,
    Parent = header,
})
local pingChip = create("TextLabel", {
    BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
    Text = "0 ms", TextSize = 12, TextColor3 = Theme.SubText,
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -62, 0, 15), Size = UDim2.new(0, 46, 0, 16),
    TextXAlignment = Enum.TextXAlignment.Right,
    Parent = header,
})

local closeBtn = create("TextButton", {
    Text = "×", Font = Enum.Font.GothamBold, TextSize = 16,
    TextColor3 = Theme.SubText, BackgroundColor3 = Theme.Card,
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(26, 26),
    AutoButtonColor = false, BorderSizePixel = 0,
    Parent = header,
})
corner(8).Parent = closeBtn
closeBtn.MouseEnter:Connect(function()
    closeBtn.TextColor3 = Color3.fromRGB(255, 96, 96)
end)
closeBtn.MouseLeave:Connect(function()
    closeBtn.TextColor3 = Theme.SubText
end)

local minBtn = create("TextButton", {
    Text = "—", Font = Enum.Font.GothamBold, TextSize = 14,
    TextColor3 = Theme.SubText, BackgroundColor3 = Theme.Card,
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -40, 0.5, 0), Size = UDim2.fromOffset(26, 26),
    AutoButtonColor = false, BorderSizePixel = 0,
    Parent = header,
})
corner(8).Parent = minBtn

-- body ------------------------------------------------------------
local body = create("Frame", {
    Position = UDim2.new(0, 0, 0, 46),
    Size = UDim2.new(1, 0, 1, -46),
    BackgroundTransparency = 1,
    Parent = main,
})

local sidebar = create("Frame", {
    Size = UDim2.new(0, 178, 1, 0),
    BackgroundColor3 = Theme.Card,
    BackgroundTransparency = 0.35,
    BorderSizePixel = 0,
    Parent = body,
})
corner(16).Parent = sidebar

create("UIListLayout", {
    Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder,
    Parent = sidebar,
})
pad(10, 10, 12, 12).Parent = sidebar

local content = create("Frame", {
    Position = UDim2.new(0, 190, 0, 0),
    Size = UDim2.new(1, -206, 1, 0),
    BackgroundTransparency = 1,
    Parent = body,
})

--................................................................
-- COMPONENTS
--................................................................
local pages = {}
local tabButtons = {}
local activePage = nil

local function makeTab(name, icon)
    local btn = create("TextButton", {
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = Theme.Card2,
        BackgroundTransparency = 1,
        Text = "", AutoButtonColor = false, BorderSizePixel = 0,
        LayoutOrder = #pages + 1,
        Parent = sidebar,
    })
    corner(10).Parent = btn
    local label = create("TextLabel", {
        BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
        Text = (icon and (icon .. "  ") or "") .. name,
        TextSize = 14, TextColor3 = Theme.SubText,
        Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -12, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = btn,
    })

    local scroll = create("ScrollingFrame", {
        BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 1, 0),
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = Theme.Stroke,
        Visible = false,
        Parent = content,
    })
    create("UIListLayout", {
        Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = scroll,
    })
    pad(4, 8, 4, 12).Parent = scroll

    local page = { Name = name, Button = btn, Label = label, Scroll = scroll }
    table.insert(pages, page)
    tabButtons[name] = btn

    btn.MouseButton1Click:Connect(function()
        ripple(btn, UserInputService:GetMouseLocation())
        for _, p in ipairs(pages) do
            p.Scroll.Visible = (p.Name == name)
            tween(p.Button, 0.2, {
                BackgroundTransparency = (p.Name == name) and 0.15 or 1,
            })
            p.Label.TextColor3 = (p.Name == name) and Theme.Text or Theme.SubText
        end
    end)
    return page
end

local function section(page, title)
    local card = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Card,
        BackgroundTransparency = 0.15,
        BorderSizePixel = 0,
        LayoutOrder = #page.Scroll:GetChildren(),
        Parent = page.Scroll,
    })
    corner(12).Parent = card
    strokeOf(Theme.Stroke, 1, 0.55).Parent = card
    create("UIListLayout", {
        Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = card,
    })
    pad(4, 4, 2, 8).Parent = card
    create("TextLabel", {
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
        Text = string.upper(title), TextSize = 11,
        TextColor3 = Theme.SubText,
        Position = UDim2.new(0, 14, 0, 10), Size = UDim2.new(1, -28, 0, 14),
        TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = 0, Parent = card,
    })
    return card
end

local function toggle(parent, text, key, callback)
    local row = create("TextButton", {
        Size = UDim2.new(1, -8, 0, 34),
        BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
        LayoutOrder = 1, Parent = parent,
    })
    create("TextLabel", {
        BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
        Text = text, TextSize = 13, TextColor3 = Theme.Text,
        Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -90, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Left, Parent = row,
    })
    local pill = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(44, 22),
        BackgroundColor3 = Theme.Card2,
        BorderSizePixel = 0, Parent = row,
    })
    corner(11).Parent = pill
    local knob = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.fromOffset(16, 16),
        BackgroundColor3 = Theme.SubText,
        BorderSizePixel = 0, Parent = pill,
    })
    corner(8).Parent = knob

    local function set(state, silent)
        Config[key] = state
        local a = accentPair()
        if state then
            pill.BackgroundColor3 = a.c1
            tween(knob, 0.18, { Position = UDim2.new(1, -19, 0.5, 0), BackgroundColor3 = Color3.fromRGB(255, 255, 255) })
        else
            pill.BackgroundColor3 = Theme.Card2
            tween(knob, 0.18, { Position = UDim2.new(0, 3, 0.5, 0), BackgroundColor3 = Theme.SubText })
        end
        if not silent and callback then callback(state) end
        saveConfig()
    end

    row.MouseButton1Click:Connect(function()
        ripple(row, UserInputService:GetMouseLocation())
        set(not Config[key])
    end)
    set(Config[key], true)
    return { Set = set }
end

local function slider(parent, text, min, max, default, key, callback)
    local row = create("Frame", {
        Size = UDim2.new(1, -8, 0, 52),
        BackgroundTransparency = 1, LayoutOrder = 1, Parent = parent,
    })
    create("TextLabel", {
        BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
        Text = text, TextSize = 13, TextColor3 = Theme.Text,
        Position = UDim2.new(0, 12, 0, 4), Size = UDim2.new(0.6, 0, 0, 16),
        TextXAlignment = Enum.TextXAlignment.Left, Parent = row,
    })
    local valueLabel = create("TextLabel", {
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
        Text = tostring(default), TextSize = 12, TextColor3 = Theme.Text,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -12, 0, 4), Size = UDim2.new(0.4, -12, 0, 16),
        TextXAlignment = Enum.TextXAlignment.Right, Parent = row,
    })
    local track = create("Frame", {
        Position = UDim2.new(0, 12, 0, 30),
        Size = UDim2.new(1, -24, 0, 6),
        BackgroundColor3 = Theme.Card2,
        BorderSizePixel = 0, Parent = row,
    })
    corner(3).Parent = track
    local fill = create("Frame", {
        Size = UDim2.new((default - min) / (max - min), 0, 1, 0),
        BackgroundColor3 = accentPair().c1,
        BorderSizePixel = 0, Parent = track,
    })
    corner(3).Parent = fill
    makeGradient(fill)
    table.insert(accentSolids, fill)
    local knob = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new((default - min) / (max - min), 0, 0.5, 0),
        Size = UDim2.fromOffset(12, 12),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0, ZIndex = 3, Parent = track,
    })
    corner(6).Parent = knob

    local dragging = false
    local function apply(scale)
        scale = math.clamp(scale, 0, 1)
        local value = math.floor(min + (max - min) * scale * 100 + 0.5) / 100
        Config[key] = value
        valueLabel.Text = tostring(value)
        fill.Size = UDim2.new(scale, 0, 1, 0)
        knob.Position = UDim2.new(scale, 0, 0.5, 0)
        if callback then callback(value) end
        saveConfig()
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            local rel = (input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X
            apply(rel)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local rel = (input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X
            apply(rel)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    return { Set = apply }
end

local function button(parent, text, callback)
    local btn = create("TextButton", {
        Size = UDim2.new(1, -8, 0, 34),
        BackgroundColor3 = Theme.Card2,
        BackgroundTransparency = 0.2,
        Font = Enum.Font.GothamMedium,
        Text = text, TextSize = 13, TextColor3 = Theme.Text,
        AutoButtonColor = false, BorderSizePixel = 0,
        ClipsDescendants = true,
        LayoutOrder = 1, Parent = parent,
    })
    corner(10).Parent = btn
    strokeOf(Theme.Stroke, 1, 0.6).Parent = btn
    btn.MouseButton1Click:Connect(function()
        ripple(btn, UserInputService:GetMouseLocation())
        if callback then callback() end
    end)
    return btn
end

local function dropdown(parent, text, items, default, onChange)
    local container = create("Frame", {
        Size = UDim2.new(1, -8, 0, 36),
        BackgroundTransparency = 1, LayoutOrder = 1, Parent = parent,
    })
    local btn = create("TextButton", {
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = Theme.Card2,
        BackgroundTransparency = 0.2,
        Font = Enum.Font.GothamMedium,
        Text = text .. ":  " .. (default or "select"),
        TextSize = 13, TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        AutoButtonColor = false, BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = container,
    })
    corner(10).Parent = btn
    strokeOf(Theme.Stroke, 1, 0.6).Parent = btn
    pad(12, 12, 0, 0).Parent = btn
    local arrow = create("TextLabel", {
        BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
        Text = "▾", TextSize = 13, TextColor3 = Theme.SubText,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(14, 14),
        Parent = btn,
    })
    local list = create("Frame", {
        Position = UDim2.new(0, 0, 0, 38),
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundColor3 = Theme.Card2,
        BorderSizePixel = 0, Visible = false,
        ClipsDescendants = true,
        Parent = container,
    })
    corner(10).Parent = list
    local listLayout = create("UIListLayout", {
        Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = list,
    })

    local function refresh(newItems)
        items = newItems or items
        for _, c in ipairs(list:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
        end
        for i, item in ipairs(items) do
            local opt = create("TextButton", {
                Size = UDim2.new(1, 0, 0, 26),
                BackgroundTransparency = 1,
                Font = Enum.Font.Gotham,
                Text = item, TextSize = 12, TextColor3 = Theme.SubText,
                AutoButtonColor = false, BorderSizePixel = 0,
                LayoutOrder = i, Parent = list,
            })
            opt.MouseEnter:Connect(function() opt.TextColor3 = Theme.Text end)
            opt.MouseLeave:Connect(function() opt.TextColor3 = Theme.SubText end)
            opt.MouseButton1Click:Connect(function()
                btn.Text = text .. ":  " .. item
                container.Size = UDim2.new(1, -8, 0, 36)
                list.Visible = false
                if onChange then onChange(item) end
            end)
        end
        return items
    end
    refresh()

    local open = false
    btn.MouseButton1Click:Connect(function()
        open = not open
        arrow.Text = open and "▴" or "▾"
        local n = #items
        local h = math.min(n * 28 + 6, 140)
        list.Visible = open
        container.Size = open and UDim2.new(1, -8, 0, 40 + h) or UDim2.new(1, -8, 0, 36)
        list.Size = open and UDim2.new(1, 0, 0, h) or UDim2.new(1, 0, 0, 0)
        if open and n > 5 then
            list.ClipsDescendants = true
        end
    end)

    return { Refresh = refresh }
end

local function textbox(parent, text, placeholder, callback)
    local row = create("Frame", {
        Size = UDim2.new(1, -8, 0, 34),
        BackgroundTransparency = 1, LayoutOrder = 1, Parent = parent,
    })
    create("TextLabel", {
        BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
        Text = text, TextSize = 13, TextColor3 = Theme.Text,
        Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(0.4, 0, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Left, Parent = row,
    })
    local box = create("TextBox", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.new(0.5, -12, 0, 28),
        BackgroundColor3 = Theme.Card2,
        Font = Enum.Font.Gotham, TextSize = 12,
        Text = "", PlaceholderText = placeholder,
        PlaceholderColor3 = Theme.SubText,
        TextColor3 = Theme.Text,
        ClearTextOnFocus = false, BorderSizePixel = 0,
        Parent = row,
    })
    corner(8).Parent = box
    pad(8, 8, 0, 0).Parent = box
    box.FocusLost:Connect(function(enter)
        if enter and callback then callback(box.Text) end
    end)
    return box
end

--................................................................
-- PAGES
--................................................................
local pFishing = makeTab("Fishing", "🎣")
local pAuto    = makeTab("Automation", "⚡")
local pTele    = makeTab("Teleports", "🧭")
local pPlayer  = makeTab("Player", "🏃")
local pMisc    = makeTab("Misc", "⚙")

-- FISHING ---------------------------------------------------------
local fishSec = section(pFishing, "auto fish")
toggle(fishSec, "Master Auto Fish", "AutoFish", function(state)
    if state then notify("Auto Fish", "loop started") end
end)
toggle(fishSec, "Auto Equip Rod", "AutoEquip")
toggle(fishSec, "Auto Cast", "AutoCast")
toggle(fishSec, "Auto Shake", "AutoShake")
toggle(fishSec, "Auto Reel", "AutoReel")

local reelSec = section(pFishing, "tuning")
dropdown(reelSec, "Reel Mode", { "Perfect", "Safe" }, Config.ReelMode, function(item)
    Config.ReelMode = item
    saveConfig()
end)
slider(reelSec, "Cast Delay (s)", 0.3, 3, Config.CastDelay, "CastDelay")
slider(reelSec, "Shake Delay (s)", 0.05, 0.5, Config.ShakeDelay, "ShakeDelay")

local statSec = section(pFishing, "status")
local statusLabel = create("TextLabel", {
    BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
    Text = "status: idle", TextSize = 13, TextColor3 = Theme.SubText,
    Position = UDim2.new(0, 12, 0, 6), Size = UDim2.new(1, -24, 0, 18),
    TextXAlignment = Enum.TextXAlignment.Left,
    LayoutOrder = 1, Parent = statSec,
})
button(statSec, "Sell Inventory Now", function()
    if autoSell() then
        notify("Sell", "sold inventory")
    else
        notify("Sell", "no sell remote / prompt found", 5)
    end
end)

-- AUTOMATION ------------------------------------------------------
local sellSec = section(pAuto, "selling")
toggle(sellSec, "Auto Sell", "AutoSell")
slider(sellSec, "Sell Interval (s)", 30, 600, Config.SellInterval, "SellInterval")

local afkSec = section(pAuto, "idle protection")
toggle(afkSec, "Anti-AFK", "AntiAFK", function(state)
    if state then notify("Anti-AFK", "idled hook armed") end
end)

-- TELEPORTS -------------------------------------------------------
local islandSec = section(pTele, "islands")
local islandNames = {}
local islandDrop = dropdown(islandSec, "Island", {}, "scan first", function(name)
    local pos = islandPosition(name)
    if pos then
        teleportTo(pos)
        notify("Teleport", "arrived: " .. name)
    else
        notify("Teleport", "island model not found", 5)
    end
end)
button(islandSec, "Scan Islands", function()
    islandNames = scanIslands()
    islandDrop.Refresh(islandNames)
    notify("Scan", table.concat(islandNames, ", ") ~= "" and ("found " .. #islandNames .. " islands") or "none matched")
end)

local wpSec = section(pTele, "waypoints")
local wpNames = {}
local wpDrop = dropdown(wpSec, "Waypoint", {}, "none saved", function(name)
    local wp = Waypoints[name]
    if wp then
        teleportTo(Vector3.new(wp.x, wp.y, wp.z))
        notify("Teleport", "waypoint: " .. name)
    end
end)
local wpBox = textbox(wpSec, "Name", "my spot", nil)
button(wpSec, "Save Current Position", function()
    local c = player.Character
    local hrp = c and c:FindFirstChild("HumanoidRootPart")
    if not hrp then notify("Waypoint", "no character") return end
    local name = wpBox.Text ~= "" and wpBox.Text or ("pos" .. tostring(#wpNames + 1))
    local p = hrp.Position
    Waypoints[name] = { x = p.X, y = p.Y, z = p.Z }
    if not table.find(wpNames, name) then table.insert(wpNames, name) end
    saveWaypoints()
    wpDrop.Refresh(wpNames)
    notify("Waypoint", "saved: " .. name)
end)
button(wpSec, "Refresh Waypoints", function()
    wpNames = {}
    for name in pairs(Waypoints) do table.insert(wpNames, name) end
    table.sort(wpNames)
    wpDrop.Refresh(wpNames)
    notify("Waypoints", "refreshed")
end)

-- PLAYER ----------------------------------------------------------
local moveSec = section(pPlayer, "movement")
toggle(moveSec, "Apply Speed / Jump", "ApplySpeed")
slider(moveSec, "Walk Speed", 16, 250, Config.WalkSpeed, "WalkSpeed")
slider(moveSec, "Jump Power", 50, 300, Config.JumpPower, "JumpPower")
toggle(moveSec, "Noclip", "Noclip")
toggle(moveSec, "Infinite Jump", "InfJump")

-- MISC ------------------------------------------------------------
local uiSec = section(pMisc, "interface")
dropdown(uiSec, "Accent", { "Aurora", "Sunset", "Toxic", "Ice" }, Config.Accent, function(item)
    Config.Accent = item
    applyAccent()
    saveConfig()
    notify("Theme", item .. " accent applied")
end)
toggle(uiSec, "Watermark", "Watermark", function(state)
    if watermark then watermark.Visible = state end
end)
toggle(uiSec, "Ambient Blur", "Blur", function(state)
    if blurEffect then blurEffect.Enabled = state end
end)

local cfgSec = section(pMisc, "config")
button(cfgSec, "Save Config", function()
    saveConfig()
    notify("Config", "saved to " .. CONFIG_FILE)
end)
button(cfgSec, "Reload Config", function()
    local raw = safeRead(CONFIG_FILE)
    if raw then
        local ok, data = pcall(function() return HttpService:JSONDecode(raw) end)
        if ok then
            for k, v in pairs(data) do
                if Config[k] ~= nil then Config[k] = v end
            end
            notify("Config", "reloaded")
            return
        end
    end
    notify("Config", "no config file found", 5)
end)
button(cfgSec, "Unload Aurora", function()
    unload()
end)

create("TextLabel", {
    BackgroundTransparency = 1, Font = Enum.Font.Gotham,
    Text = "AURORA · fisch build · by Friknnod · toggle UI: RightShift",
    TextSize = 11, TextColor3 = Theme.SubText,
    AnchorPoint = Vector2.new(0.5, 1),
    Position = UDim2.new(0.5, 0, 1, -6),
    Size = UDim2.new(1, 0, 0, 12),
    LayoutOrder = 99, Parent = pMisc.Scroll,
})

--................................................................
-- WATERMARK
--................................................................
watermark = create("CanvasGroup", {
    Position = UDim2.new(0, 14, 0, 14),
    Size = UDim2.fromOffset(268, 30),
    BackgroundColor3 = Theme.Bg,
    BackgroundTransparency = 0.25,
    BorderSizePixel = 0,
    GroupTransparency = 0,
    Parent = screenGui,
})
corner(10).Parent = watermark
strokeOf(Theme.Stroke, 1, 0.5).Parent = watermark
local wmText = create("TextLabel", {
    BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
    Text = "AURORA · by Friknnod · 60 fps · 0 ms", TextSize = 12,
    TextColor3 = Theme.Text,
    Size = UDim2.new(1, 0, 1, 0), Parent = watermark,
})
watermark.Visible = Config.Watermark

do -- watermark drag
    local dragging, dragStart, startPos = false, nil, nil
    watermark.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = watermark.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            watermark.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

--................................................................
-- WINDOW BEHAVIOR
--................................................................
do -- window drag
    local dragging, dragStart, startPos = false, nil, nil
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
            screenGui.Shadow.Position = UDim2.new(main.Position.X.Scale, main.Position.X.Offset, main.Position.Y.Scale, main.Position.Y.Offset + 6)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    body.Visible = not minimized
    tween(main, 0.3, {
        Size = minimized and UDim2.fromOffset(640, 46) or UDim2.fromOffset(640, 440),
    })
end)

closeBtn.MouseButton1Click:Connect(function()
    unload()
end)

UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        minimized = false
        body.Visible = true
        main.Visible = not main.Visible
        screenGui.Shadow.Visible = main.Visible
        if main.Visible then
            main.Size = UDim2.fromOffset(640, 36)
            tween(main, 0.35, { Size = UDim2.fromOffset(640, 440) })
        end
    end
end)

--................................................................
-- STATUS / METERS REFRESH
--................................................................
task.spawn(function()
    while running do
        statusLabel.Text = "status: " .. fishStatus
        fpsChip.Text = tostring(currentFPS) .. " fps"
        pingChip.Text = tostring(currentPing) .. " ms"
        wmText.Text = "AURORA · by Friknnod · " .. tostring(currentFPS) .. " fps · " .. tostring(currentPing) .. " ms"
        task.wait(0.5)
    end
end)

task.spawn(function()
    while running do
        clockChip.Text = os.date("%H:%M")
        task.wait(10)
    end
end)

--................................................................
-- BOOT
--................................................................
blurEffect = create("BlurEffect", { Size = 0, Enabled = Config.Blur, Parent = Lighting })
if Config.Blur then blurEffect.Size = 14 end

applyAccent()

-- open first tab
do
    local first = pages[1]
    first.Scroll.Visible = true
    first.Button.BackgroundTransparency = 0.15
    first.Label.TextColor3 = Theme.Text
end

main.Size = UDim2.fromOffset(640, 30)
tween(main, 0.4, { Size = UDim2.fromOffset(640, 440) })

notify("Aurora", "loaded · built by Friknnod · RightShift to toggle", 5)
notify("Auto Fish", "master toggle is in the Fishing tab")

--................................................................
-- UNLOAD (defined late so it closes over everything)
--................................................................
function unload()
    running = false
    saveConfig()
    saveWaypoints()
    pcall(function() blurEffect:Destroy() end)
    pcall(function() screenGui:Destroy() end)
end
