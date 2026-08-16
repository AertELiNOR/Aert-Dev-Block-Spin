-- =========================================================
-- Aert-Dev | Block Spin Script (Fixed Edition)
-- =========================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local Stats = game:GetService("Stats")
local NetworkStats = Stats.Network.ServerStatsItem["Data Ping"]
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local Mouse = LocalPlayer:GetMouse()

-- Configuration State
local Config = {
    Aimbot = false,
    AimbotKey = Enum.UserInputType.MouseButton2,
    AimbotToggleKey = Enum.KeyCode.Q,
    AimbotSmoothness = 100,
    
    SilentAim = true,
    RedLineLock = true,
    FOV = 300,
    ShowFOV = true,
    
    ESP = true,
    ESP_HealthText = true,
    ESP_HealthBar = true,
    ESP_Item = true,
    ESP_GroundItem = true,
    
    WalkSpeedEnabled = false,
    SpeedMultiplier = 1.2,
    JumpPowerEnabled = false,
    JumpPower = 50,
    
    InfiniteStamina = true,
    GodMode = false,
    NoFallDamage = false,
    
    ToggleKey = Enum.KeyCode.RightControl
}

-- Config Save & Load System
local ConfigFileName = "AertDev_Config.json"

local function SaveConfig()
    if writefile then
        pcall(function()
            local saveTable = {}
            for k, v in pairs(Config) do
                if typeof(v) == "EnumItem" then
                    saveTable[k] = v.Name
                else
                    saveTable[k] = v
                end
            end
            writefile(ConfigFileName, HttpService:JSONEncode(saveTable))
        end)
    end
end

local function LoadConfig()
    if readfile and isfile and isfile(ConfigFileName) then
        local success, data = pcall(function()
            return HttpService:JSONDecode(readfile(ConfigFileName))
        end)
        if success and type(data) == "table" then
            for k, v in pairs(data) do
                if (k == "ToggleKey" or k == "AimbotKey" or k == "AimbotToggleKey") and type(v) == "string" then
                    local successKey, keyEnum = pcall(function() return Enum.KeyCode[v] end)
                    local successMouse, mouseEnum = pcall(function() return Enum.UserInputType[v] end)
                    
                    if successKey and keyEnum then 
                        Config[k] = keyEnum 
                    elseif successMouse and mouseEnum then 
                        Config[k] = mouseEnum 
                    end
                elseif Config[k] ~= nil then
                    Config[k] = v
                end
            end
        end
    end
end

LoadConfig()

------------------------------------------------------------------
-- 0. Item Database & Scanner Engine
------------------------------------------------------------------
local WeaponDB = {}
local PreloadedImages = {}
local ESPCache = {}

local RARITY_COLORS = {
    ["Common"] = Color3.fromRGB(220, 220, 220),
    ["Uncommon"] = Color3.fromRGB(99, 255, 52),
    ["Rare"] = Color3.fromRGB(51, 170, 255),
    ["Epic"] = Color3.fromRGB(210, 50, 255),
    ["Legendary"] = Color3.fromRGB(255, 160, 0),
    ["Omega"] = Color3.fromRGB(255, 30, 60),
}

local RARITY_RANK = {
    ["Common"] = 1,
    ["Uncommon"] = 2,
    ["Rare"] = 3,
    ["Epic"] = 4,
    ["Legendary"] = 5,
    ["Omega"] = 6
}

local function generateUniqueKey(tool)
    if not tool or not tool:IsA("Tool") then return nil end
    local itemId = tool:GetAttribute("ItemId") or tool:GetAttribute("Id")
    if itemId and itemId ~= "" and (typeof(itemId) == "string" or typeof(itemId) == "number") then
        return "ITEMID_" .. tostring(itemId)
    end
    
    local partsData = {}
    for _, part in ipairs(tool:GetDescendants()) do
        if part:IsA("SpecialMesh") and part.MeshId and part.MeshId ~= "" and part.MeshId ~= "rbxassetid://" then
            table.insert(partsData, "MESH_"..part.MeshId.."|TEX_"..(part.TextureId or "NOTEX"))
        elseif part:IsA("MeshPart") and part.MeshId and part.MeshId ~= "" and part.MeshId ~= "rbxassetid://" then
            table.insert(partsData, "MESH_"..part.MeshId.."|TEX_"..(part.TextureID or "NOTEX"))
        elseif part:IsA("Decal") and part.Texture and part.Texture ~= "" and part.Texture ~= "rbxassetid://" then
            table.insert(partsData, "DECAL_"..part.Texture)
        elseif part:IsA("Part") then
            table.insert(partsData, "PART_"..part.Name.."_"..part.Size.X.."x"..part.Size.Y.."x"..part.Size.Z)
        end
    end
    
    if #partsData > 0 then
        table.sort(partsData)
        return "MESHKEY_" .. table.concat(partsData, ";")
    end
    
    local displayName = tool:GetAttribute("DisplayName") or tool.Name
    local toolName = tool.Name
    local rarity = tool:GetAttribute("RarityName") or tool:GetAttribute("Rarity") or "Unknown"
    local imageId = tool:GetAttribute("ImageId") or "NOIMAGE"
    return "NAME_" .. displayName .. "_" .. toolName .. "_" .. rarity .. "_" .. imageId
end

local function registerItems(folder)
    for _, tool in ipairs(folder:GetDescendants()) do
        if not tool:IsA("Tool") then continue end
        local key = generateUniqueKey(tool)
        if not key then continue end
        local displayName = tool:GetAttribute("DisplayName") or tool.Name
        local imageId = tool:GetAttribute("ImageId") or "rbxassetid://7072725737"
        local rarity = tool:GetAttribute("RarityName") or tool:GetAttribute("Rarity") or "Common"
        
        WeaponDB[key] = {
            Name = displayName,
            Rarity = rarity,
            ImageId = imageId,
            ToolName = tool.Name,
            Key = key
        }
        
        if imageId and imageId ~= "" and not PreloadedImages[imageId] then
            PreloadedImages[imageId] = true
            task.spawn(function()
                pcall(function()
                    ContentProvider:PreloadAsync({imageId})
                end)
            end)
        end
    end
end

pcall(function()
    local itemsFolder = ReplicatedStorage:WaitForChild("Items", 5)
    if itemsFolder then registerItems(itemsFolder) end
    for _, obj in ipairs(ReplicatedStorage:GetChildren()) do
        if obj:IsA("Folder") and (obj.Name:find("Weapon") or obj.Name:find("Item") or obj.Name:find("Tool")) then
            registerItems(obj)
        end
    end
    registerItems(game:GetService("StarterPack"))
end)

local function getWeaponInfo(tool)
    if not tool or not tool:IsA("Tool") then return nil end
    local key = generateUniqueKey(tool)
    return WeaponDB[key]
end

------------------------------------------------------------------
-- 1. Drawing API & Target Selection
------------------------------------------------------------------
local FOVCircle = Drawing.new("Circle")
FOVCircle.Color = Color3.fromRGB(255, 255, 255)
FOVCircle.Thickness = 1.5
FOVCircle.NumSides = 64
FOVCircle.Filled = false
FOVCircle.Transparency = 0.8
FOVCircle.Visible = false

local RedLine = Drawing.new("Line")
RedLine.Color = Color3.fromRGB(255, 40, 40)
RedLine.Thickness = 2
RedLine.Transparency = 1
RedLine.Visible = false

local function getScreenCenter()
    return Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
end

local function getClosestPlayerToCenter()
    local closestPlayer, closestHead = nil, nil
    local shortestDistance = Config.FOV
    local centerPos = getScreenCenter()

    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("Head") then
            local hum = player.Character:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local head = player.Character.Head
                local screenPos, onScreen = Camera:WorldToViewportPoint(head.Position)
                if onScreen then
                    local dist = (Vector2.new(screenPos.X, screenPos.Y) - centerPos).Magnitude
                    if dist < shortestDistance then
                        shortestDistance = dist
                        closestPlayer = player
                        closestHead = head
                    end
                end
            end
        end
    end
    return closestPlayer, closestHead
end

------------------------------------------------------------------
-- 2. UI Creation & Modern Dark Theme Interface
------------------------------------------------------------------
local ProtectedGui = (gethui and gethui()) or CoreGui
if ProtectedGui:FindFirstChild("AertDevUI") then ProtectedGui.AertDevUI:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AertDevUI"
ScreenGui.ResetOnSpawn = false

if gethui then ScreenGui.Parent = gethui()
elseif syn and syn.protect_gui then syn.protect_gui(ScreenGui); ScreenGui.Parent = CoreGui
else ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

-- ปุ่มลอยแบบ Text สไตล์โมเดิร์น รองรับการลากย้ายที่
local FloatingToggle = Instance.new("TextButton")
FloatingToggle.Size = UDim2.new(0, 110, 0, 38)
FloatingToggle.Position = UDim2.new(0, 25, 0.5, -19)
FloatingToggle.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
FloatingToggle.Text = "Aert-Dev"
FloatingToggle.TextColor3 = Color3.fromRGB(240, 240, 250)
FloatingToggle.Font = Enum.Font.GothamBold
FloatingToggle.TextSize = 13
FloatingToggle.Draggable = true
FloatingToggle.Active = true
FloatingToggle.Parent = ScreenGui

local FTCorner = Instance.new("UICorner")
FTCorner.CornerRadius = UDim.new(0, 8)
FTCorner.Parent = FloatingToggle

local FTStroke = Instance.new("UIStroke")
FTStroke.Color = Color3.fromRGB(99, 102, 241)
FTStroke.Thickness = 1.5
FTStroke.Parent = FloatingToggle

-- ป้ายแสดง FPS & Ping (ขยายความกว้างเป็น 210 พิกเซล ให้มีพื้นที่กว้างขึ้น)
local StatsLabel = Instance.new("TextLabel")
StatsLabel.Size = UDim2.new(0, 210, 0, 28)
StatsLabel.Position = UDim2.new(0, 145, 0, 15)
StatsLabel.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
StatsLabel.BackgroundTransparency = 0.2
StatsLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
StatsLabel.Font = Enum.Font.Code
StatsLabel.TextSize = 12
StatsLabel.RichText = true
StatsLabel.Text = " FPS:  60 | Ping:   0ms"
StatsLabel.AutomaticSize = Enum.AutomaticSize.None
StatsLabel.TextXAlignment = Enum.TextXAlignment.Left
StatsLabel.Parent = ScreenGui

local StatsCorner = Instance.new("UICorner")
StatsCorner.CornerRadius = UDim.new(0, 8)
StatsCorner.Parent = StatsLabel

local StatsStroke = Instance.new("UIStroke")
StatsStroke.Color = Color3.fromRGB(45, 45, 60)
StatsStroke.Thickness = 1
StatsStroke.Parent = StatsLabel

-- ป้ายแสดงสถานะ Aimbot (ขยายความกว้างเป็น 210 พิกเซล ให้เท่ากัน)
local AimbotStatusLabel = Instance.new("TextLabel")
AimbotStatusLabel.Size = UDim2.new(0, 210, 0, 28)
AimbotStatusLabel.Position = UDim2.new(0, 145, 0, 50)
AimbotStatusLabel.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
AimbotStatusLabel.BackgroundTransparency = 0.2
AimbotStatusLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
AimbotStatusLabel.Font = Enum.Font.Code
AimbotStatusLabel.TextSize = 12
AimbotStatusLabel.RichText = true
AimbotStatusLabel.Text = ' Aimbot: <font color="#FF4D4D">OFF</font>'
AimbotStatusLabel.AutomaticSize = Enum.AutomaticSize.None
AimbotStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
AimbotStatusLabel.Parent = ScreenGui

local ASCorner = Instance.new("UICorner")
ASCorner.CornerRadius = UDim.new(0, 8)
ASCorner.Parent = AimbotStatusLabel

local ASStroke = Instance.new("UIStroke")
ASStroke.Color = Color3.fromRGB(45, 45, 60)
ASStroke.Thickness = 1
ASStroke.Parent = AimbotStatusLabel

-- Modern Dark Styled MainFrame
local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 580, 0, 400)
MainFrame.Position = UDim2.new(0.5, -290, 0.5, -200)
MainFrame.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

FloatingToggle.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 12)
MainCorner.Parent = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(40, 40, 55)
MainStroke.Thickness = 1.5
MainStroke.Parent = MainFrame

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 50)
Header.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
Header.BorderSizePixel = 0
Header.Parent = MainFrame

local HeaderCorner = Instance.new("UICorner")
HeaderCorner.CornerRadius = UDim.new(0, 12)
HeaderCorner.Parent = Header

local TitleLbl = Instance.new("TextLabel")
TitleLbl.Size = UDim2.new(1, -30, 1, 0)
TitleLbl.Position = UDim2.new(0, 20, 0, 0)
TitleLbl.BackgroundTransparency = 1
TitleLbl.Text = "Aert-Dev | Block spin"
TitleLbl.TextColor3 = Color3.fromRGB(245, 245, 250)
TitleLbl.Font = Enum.Font.GothamBold
TitleLbl.TextSize = 16
TitleLbl.TextXAlignment = Enum.TextXAlignment.Left
TitleLbl.Parent = Header

local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.new(0, 160, 1, -50)
Sidebar.Position = UDim2.new(0, 0, 0, 50)
Sidebar.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
Sidebar.BorderSizePixel = 0
Sidebar.Parent = MainFrame

local SidebarList = Instance.new("UIListLayout")
SidebarList.Padding = UDim.new(0, 6)
SidebarList.SortOrder = Enum.SortOrder.LayoutOrder
SidebarList.Parent = Sidebar

local SidebarPadding = Instance.new("UIPadding")
SidebarPadding.PaddingTop = UDim.new(0, 12)
SidebarPadding.PaddingLeft = UDim.new(0, 8)
SidebarPadding.PaddingRight = UDim.new(0, 8)
SidebarPadding.Parent = Sidebar

local ContentArea = Instance.new("Frame")
ContentArea.Size = UDim2.new(1, -175, 1, -60)
ContentArea.Position = UDim2.new(0, 170, 0, 55)
ContentArea.BackgroundTransparency = 1
ContentArea.Parent = MainFrame

local TabPages = {}

local function createTab(name)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 38)
    btn.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
    btn.BackgroundTransparency = 1
    btn.Text = "   " .. name
    btn.TextColor3 = Color3.fromRGB(150, 150, 170)
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 13
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.Parent = Sidebar

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 8)
    btnCorner.Parent = btn

    local page = Instance.new("ScrollingFrame")
    page.Size = UDim2.new(1, 0, 1, 0)
    page.BackgroundTransparency = 1
    page.ScrollBarThickness = 3
    page.Visible = false
    page.Parent = ContentArea

    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, 10)
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Parent = page

    TabPages[name] = {Button = btn, Page = page}

    btn.MouseButton1Click:Connect(function()
        for _, t in pairs(TabPages) do
            t.Page.Visible = false
            t.Button.TextColor3 = Color3.fromRGB(150, 150, 170)
            t.Button.BackgroundTransparency = 1
        end
        page.Visible = true
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.BackgroundTransparency = 0
        btn.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
    end)

    return page
end

local CombatPage = createTab("COMBAT")
local ESPPage = createTab("ESP")
local CharacterPage = createTab("CHARACTER")
local MiscPage = createTab("MISC")

TabPages["COMBAT"].Page.Visible = true
TabPages["COMBAT"].Button.TextColor3 = Color3.fromRGB(255, 255, 255)
TabPages["COMBAT"].Button.BackgroundTransparency = 0
TabPages["COMBAT"].Button.BackgroundColor3 = Color3.fromRGB(24, 24, 32)

local function createSectionTitle(page, title)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 24)
    lbl.BackgroundTransparency = 1
    lbl.Text = title
    lbl.TextColor3 = Color3.fromRGB(99, 102, 241)
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = page
end

local function createSwitch(page, text, defaultConfig, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -10, 0, 42)
    frame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
    frame.Parent = page

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.7, 0, 1, 0)
    label.Position = UDim2.new(0, 14, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(235, 235, 240)
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    local toggleBg = Instance.new("TextButton")
    toggleBg.Size = UDim2.new(0, 46, 0, 24)
    toggleBg.Position = UDim2.new(1, -56, 0.5, -12)
    toggleBg.Text = ""
    toggleBg.Parent = frame

    local toggleCorner = Instance.new("UICorner")
    toggleCorner.CornerRadius = UDim.new(1, 0)
    toggleCorner.Parent = toggleBg

    local circle = Instance.new("Frame")
    circle.Size = UDim2.new(0, 18, 0, 18)
    circle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    circle.Parent = toggleBg

    local circleCorner = Instance.new("UICorner")
    circleCorner.CornerRadius = UDim.new(1, 0)
    circleCorner.Parent = circle

    local state = defaultConfig
    local function updateVisual()
        if state then
            toggleBg.BackgroundColor3 = Color3.fromRGB(99, 102, 241)
            circle.Position = UDim2.new(1, -20, 0.5, -9)
        else
            toggleBg.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
            circle.Position = UDim2.new(0, 2, 0.5, -9)
        end
    end
    updateVisual()

    toggleBg.MouseButton1Click:Connect(function()
        state = not state
        updateVisual()
        callback(state)
        SaveConfig()
    end)

    return {
        SetState = function(newState)
            state = newState
            updateVisual()
        end
    }
end

local function createSlider(page, text, min, max, default, isMultiplier, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -10, 0, 48)
    frame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
    frame.Parent = page

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.6, 0, 0, 20)
    label.Position = UDim2.new(0, 14, 0, 6)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(235, 235, 240)
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    local valLabel = Instance.new("TextLabel")
    valLabel.Size = UDim2.new(0.3, 0, 0, 20)
    valLabel.Position = UDim2.new(0.7, -14, 0, 6)
    valLabel.BackgroundTransparency = 1
    valLabel.Text = isMultiplier and ("*" .. tostring(default)) or tostring(default)
    valLabel.TextColor3 = Color3.fromRGB(170, 170, 190)
    valLabel.Font = Enum.Font.GothamBold
    valLabel.TextSize = 13
    valLabel.TextXAlignment = Enum.TextXAlignment.Right
    valLabel.Parent = frame

    local sliderBar = Instance.new("TextButton")
    sliderBar.Size = UDim2.new(1, -28, 0, 6)
    sliderBar.Position = UDim2.new(0, 14, 0, 32)
    sliderBar.BackgroundColor3 = Color3.fromRGB(35, 35, 48)
    sliderBar.Text = ""
    sliderBar.Parent = frame

    local sliderBarCorner = Instance.new("UICorner")
    sliderBarCorner.CornerRadius = UDim.new(1, 0)
    sliderBarCorner.Parent = sliderBar

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(99, 102, 241)
    fill.BorderSizePixel = 0
    fill.Parent = sliderBar

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = fill

    local dragging = false
    local function updateSlider(input)
        local pos = math.clamp((input.Position.X - sliderBar.AbsolutePosition.X) / sliderBar.AbsoluteSize.X, 0, 1)
        fill.Size = UDim2.new(pos, 0, 1, 0)
        local val = isMultiplier and (math.floor((min + (max - min) * pos) * 10) / 10) or math.floor(min + (max - min) * pos)
        valLabel.Text = isMultiplier and ("*" .. tostring(val)) or tostring(val)
        callback(val)
    end

    sliderBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            updateSlider(input)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and dragging then 
            dragging = false 
            SaveConfig()
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then updateSlider(input) end
    end)
end

local function createKeybind(page, text, defaultKey, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -10, 0, 42)
    frame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
    frame.Parent = page

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.6, 0, 1, 0)
    label.Position = UDim2.new(0, 14, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(235, 235, 240)
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    local bindBtn = Instance.new("TextButton")
    bindBtn.Size = UDim2.new(0, 100, 0, 28)
    bindBtn.Position = UDim2.new(1, -112, 0.5, -14)
    bindBtn.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
    bindBtn.Text = typeof(defaultKey) == "EnumItem" and defaultKey.Name or tostring(defaultKey)
    bindBtn.TextColor3 = Color3.fromRGB(235, 235, 240)
    bindBtn.Font = Enum.Font.GothamBold
    bindBtn.TextSize = 12
    bindBtn.Parent = frame

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 6)
    btnCorner.Parent = bindBtn

    local binding = false
    bindBtn.MouseButton1Click:Connect(function()
        binding = true
        bindBtn.Text = "..."
    end)

    UserInputService.InputBegan:Connect(function(input)
        if binding then
            if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode ~= Enum.KeyCode.Escape then
                binding = false
                bindBtn.Text = input.KeyCode.Name
                callback(input.KeyCode)
                SaveConfig()
            elseif input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.MouseButton3 then
                binding = false
                bindBtn.Text = input.UserInputType.Name
                callback(input.UserInputType)
                SaveConfig()
            end
        end
    end)
end

-- Options Construction
createSectionTitle(CombatPage, "AIMBOT (CAMERA LOCK)")
local aimbotSwitch = createSwitch(CombatPage, "Enable Aimbot", Config.Aimbot, function(v) Config.Aimbot = v end)
createKeybind(CombatPage, "Aimbot Keybind", Config.AimbotKey, function(newKey) Config.AimbotKey = newKey end)
createKeybind(CombatPage, "Toggle Aimbot Key", Config.AimbotToggleKey, function(newKey) Config.AimbotToggleKey = newKey end)
createSlider(CombatPage, "Aim Smoothness (%)", 1, 100, Config.AimbotSmoothness, false, function(v) Config.AimbotSmoothness = v end)

createSectionTitle(CombatPage, "SILENT AIM")
createSwitch(CombatPage, "Silent Aim", Config.SilentAim, function(v) Config.SilentAim = v end)
createSwitch(CombatPage, "Red Line Lock", Config.RedLineLock, function(v) Config.RedLineLock = v end)
createSwitch(CombatPage, "Show FOV Circle", Config.ShowFOV, function(v) Config.ShowFOV = v end)
createSlider(CombatPage, "FOV Radius", 50, 800, Config.FOV, false, function(v) Config.FOV = v end)

createSectionTitle(ESPPage, "PLAYER ESP")
createSwitch(ESPPage, "Enable ESP", Config.ESP, function(v) Config.ESP = v end)
createSwitch(ESPPage, "Show Health Text (HP)", Config.ESP_HealthText, function(v) Config.ESP_HealthText = v end)
createSwitch(ESPPage, "Show Health Bar", Config.ESP_HealthBar, function(v) Config.ESP_HealthBar = v end)
createSwitch(ESPPage, "Show Held Item (Uncommon+)", Config.ESP_Item, function(v) Config.ESP_Item = v end)

createSectionTitle(ESPPage, "GROUND ITEM ESP")

createSectionTitle(CharacterPage, "MOVEMENT & HEALTH")
createSwitch(CharacterPage, "WalkSpeed Hack", Config.WalkSpeedEnabled, function(v) Config.WalkSpeedEnabled = v end)
createSlider(CharacterPage, "Speed Multiplier", 1, 2, Config.SpeedMultiplier, true, function(v) Config.SpeedMultiplier = v end)
createSwitch(CharacterPage, "JumpPower Hack", Config.JumpPowerEnabled, function(v) Config.JumpPowerEnabled = v end)
createSlider(CharacterPage, "Jump Value", 30, 100, Config.JumpPower, false, function(v) Config.JumpPower = v end)
createSwitch(CharacterPage, "Infinite Stamina", Config.InfiniteStamina, function(v) Config.InfiniteStamina = v end)
createSwitch(CharacterPage, "God Mode", Config.GodMode, function(v) Config.GodMode = v end)
createSwitch(CharacterPage, "No Fall Damage", Config.NoFallDamage, function(v) Config.NoFallDamage = v end)

createSectionTitle(MiscPage, "SETTINGS")
createKeybind(MiscPage, "Toggle Menu Keybind", Config.ToggleKey, function(newKey)
    Config.ToggleKey = newKey
end)

------------------------------------------------------------------
-- 3. Dynamic Real-time Combined Player ESP System
------------------------------------------------------------------
local function createCombinedESP(player)
    if player == LocalPlayer then return end

    if ESPCache[player] then
        if ESPCache[player].Billboard then ESPCache[player].Billboard:Destroy() end
        if ESPCache[player].Highlight then ESPCache[player].Highlight:Destroy() end
        if ESPCache[player].Box then ESPCache[player].Box:Remove() end
        if ESPCache[player].Connection then ESPCache[player].Connection:Disconnect() end
        ESPCache[player] = nil
    end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "AertDevESP_" .. player.Name
    billboard.Size = UDim2.new(0, 240, 0, 140)
    billboard.ExtentsOffset = Vector3.new(0, 3.5, 0)
    billboard.AlwaysOnTop = true
    billboard.LightInfluence = 0
    billboard.ResetOnSpawn = false
    billboard.Enabled = false
    billboard.Parent = ScreenGui

    local mainContainer = Instance.new("Frame")
    mainContainer.Size = UDim2.new(1, 0, 1, 0)
    mainContainer.BackgroundTransparency = 1
    mainContainer.Parent = billboard

    local mainLayout = Instance.new("UIListLayout")
    mainLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    mainLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
    mainLayout.SortOrder = Enum.SortOrder.LayoutOrder
    mainLayout.Padding = UDim.new(0, 3)
    mainLayout.Parent = mainContainer

    local itemContainer = Instance.new("Frame")
    itemContainer.Size = UDim2.new(1, 0, 0, 42)
    itemContainer.BackgroundTransparency = 1
    itemContainer.LayoutOrder = 1
    itemContainer.Visible = false
    itemContainer.Parent = mainContainer

    local itemLayout = Instance.new("UIGridLayout")
    itemLayout.Name = "UIGridLayout"
    itemLayout.CellSize = UDim2.new(0, 38, 0, 38)
    itemLayout.CellPadding = UDim2.new(0, 4, 0, 4)
    itemLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    itemLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    itemLayout.SortOrder = Enum.SortOrder.LayoutOrder
    itemLayout.Parent = itemContainer

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, 0, 0, 15)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    nameLabel.TextStrokeTransparency = 0
    nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = 13
    nameLabel.LayoutOrder = 2
    nameLabel.Parent = mainContainer

    local healthBarBg = Instance.new("Frame")
    healthBarBg.Size = UDim2.new(0.6, 0, 0, 5)
    healthBarBg.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    healthBarBg.BorderSizePixel = 0
    healthBarBg.LayoutOrder = 3
    healthBarBg.Parent = mainContainer

    local healthBarCorner = Instance.new("UICorner")
    healthBarCorner.CornerRadius = UDim.new(1, 0)
    healthBarCorner.Parent = healthBarBg

    local healthBarFill = Instance.new("Frame")
    healthBarFill.Size = UDim2.new(1, 0, 1, 0)
    healthBarFill.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
    healthBarFill.BorderSizePixel = 0
    healthBarFill.Parent = healthBarBg

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = healthBarFill

    local hpText = Instance.new("TextLabel")
    hpText.Size = UDim2.new(1, 0, 0, 13)
    hpText.BackgroundTransparency = 1
    hpText.TextColor3 = Color3.fromRGB(255, 255, 255)
    hpText.TextStrokeTransparency = 0
    hpText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    hpText.Font = Enum.Font.GothamBold
    hpText.TextSize = 12
    hpText.LayoutOrder = 4
    hpText.Parent = mainContainer

    local highlight = Instance.new("Highlight")
    highlight.Name = "AertDevHighlight_" .. player.Name
    highlight.FillTransparency = 0.5
    highlight.OutlineTransparency = 0
    highlight.Enabled = false
    highlight.Parent = ProtectedGui

    local box = Drawing.new("Square")
    box.Thickness = 1.5
    box.Filled = false
    box.Transparency = 1
    box.Visible = false

    local lastToolsKey = ""
    local function updateItems(char)
        if not (Config.ESP and Config.ESP_Item) then
            itemContainer.Visible = false
            return
        end

        local currentTools = {}
        local keyString = ""

        local function scan(folder)
            if not folder then return end
            for _, tool in ipairs(folder:GetChildren()) do
                if tool:IsA("Tool") and tool.Name ~= "Fists" then
                    local info = getWeaponInfo(tool)
                    if info and (RARITY_RANK[info.Rarity] or 1) >= 2 then
                        table.insert(currentTools, info)
                        keyString = keyString .. info.Key .. "|"
                    end
                end
            end
        end

        scan(char)
        scan(player:FindFirstChild("Backpack"))

        if keyString == lastToolsKey then return end 
        lastToolsKey = keyString

        for _, child in ipairs(itemContainer:GetChildren()) do
            if child:IsA("Frame") then child:Destroy() end
        end
        
        local grid = itemContainer:FindFirstChild("UIGridLayout")
        if not grid then
            grid = Instance.new("UIGridLayout")
            grid.Name = "UIGridLayout"
            grid.CellSize = UDim2.new(0, 38, 0, 38)
            grid.CellPadding = UDim2.new(0, 4, 0, 4)
            grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
            grid.VerticalAlignment = Enum.VerticalAlignment.Center
            grid.SortOrder = Enum.SortOrder.LayoutOrder
            grid.Parent = itemContainer
        end

        if #currentTools > 0 then
            itemContainer.Visible = true
            for i, info in ipairs(currentTools) do
                local color = RARITY_COLORS[info.Rarity] or Color3.fromRGB(255, 255, 255)
                
                local card = Instance.new("Frame")
                card.Size = UDim2.new(0, 38, 0, 38)
                card.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
                card.BackgroundTransparency = 0.2
                card.BorderSizePixel = 0
                card.LayoutOrder = i
                card.Parent = itemContainer

                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(0, 6)
                corner.Parent = card

                local stroke = Instance.new("UIStroke")
                stroke.Color = color
                stroke.Thickness = 2
                stroke.Transparency = 0
                stroke.Parent = card

                local img = Instance.new("ImageLabel")
                img.Parent = card
                img.Size = UDim2.new(0.85, 0, 0.85, 0)
                img.Position = UDim2.new(0.075, 0, 0.075, 0)
                img.BackgroundTransparency = 1
                img.Image = info.ImageId or "rbxassetid://7072725737"
                img.ScaleType = Enum.ScaleType.Fit
            end
        else
            itemContainer.Visible = false
        end
    end

    local function checkInSafeZone(char, hrp)
        if not hrp then return false end
        if char:GetAttribute("SafeZone") or char:GetAttribute("InSafeZone") or player:GetAttribute("SafeZone") then
            return true
        end
        local safeZonesFolder = workspace:FindFirstChild("SafeZones") or workspace:FindFirstChild("SafeZone")
        if safeZonesFolder then
            for _, zone in ipairs(safeZonesFolder:GetDescendants()) do
                if zone:IsA("BasePart") then
                    local relativePos = zone.CFrame:PointToObjectSpace(hrp.Position)
                    local size = zone.Size / 2
                    if math.abs(relativePos.X) <= size.X and math.abs(relativePos.Y) <= size.Y and math.abs(relativePos.Z) <= size.Z then
                        return true
                    end
                end
            end
        end
        return false
    end

    local lastItemScanTime = 0
    local renderConn = RunService.RenderStepped:Connect(function()
        if not Config.ESP or not player.Parent then
            billboard.Enabled = false
            highlight.Enabled = false
            box.Visible = false
            return
        end

        local char = player.Character
        if not char then
            billboard.Enabled = false
            highlight.Enabled = false
            box.Visible = false
            return
        end

        local head = char:FindFirstChild("Head")
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")

        if head and hum and hum.Health > 0 and hrp then
            billboard.Adornee = head
            billboard.Enabled = true

            local inSafeZone = checkInSafeZone(char, hrp)

            highlight.Adornee = char
            highlight.Enabled = true
            
            if inSafeZone then
                highlight.FillColor = Color3.fromRGB(46, 204, 113)
                highlight.OutlineColor = Color3.fromRGB(46, 204, 113)
                nameLabel.TextColor3 = Color3.fromRGB(46, 204, 113)
            else
                highlight.FillColor = Color3.fromRGB(255, 255, 255)
                highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
                nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
            end

            nameLabel.Text = string.format("%s (@%s)", player.DisplayName, player.Name)

            local cf = hrp.CFrame
            local size = char:GetExtentsSize()
            local topPos, topOnScreen = Camera:WorldToViewportPoint((cf + Vector3.new(0, size.Y / 2 + 0.5, 0)).Position)
            local bottomPos, bottomOnScreen = Camera:WorldToViewportPoint((cf - Vector3.new(0, size.Y / 2 + 0.5, 0)).Position)

            if topOnScreen or bottomOnScreen then
                local height = math.abs(topPos.Y - bottomPos.Y)
                local width = height / 2
                box.Size = Vector2.new(width, height)
                box.Position = Vector2.new(topPos.X - width / 2, topPos.Y)
                box.Color = inSafeZone and Color3.fromRGB(46, 204, 113) or Color3.fromRGB(255, 255, 255)
                box.Visible = true
            else
                box.Visible = false
            end

            local hpPercent = math.clamp(hum.Health / hum.MaxHealth, 0, 1)

            if Config.ESP_HealthBar then
                healthBarBg.Visible = true
                healthBarFill.Size = UDim2.new(hpPercent, 0, 1, 0)
                if hpPercent >= 0.6 then healthBarFill.BackgroundColor3 = Color3.fromRGB(46, 204, 113)
                elseif hpPercent >= 0.3 then healthBarFill.BackgroundColor3 = Color3.fromRGB(243, 156, 18)
                else healthBarFill.BackgroundColor3 = Color3.fromRGB(231, 76, 60) end
            else
                healthBarBg.Visible = false
            end

            if Config.ESP_HealthText then
                hpText.Visible = true
                hpText.Text = string.format("HP: %d/%d", math.floor(hum.Health), hum.MaxHealth)
            else
                hpText.Visible = false
            end

            if os.clock() - lastItemScanTime > 0.5 then
                updateItems(char)
                lastItemScanTime = os.clock()
            end
        else
            billboard.Enabled = false
            highlight.Enabled = false
            box.Visible = false
        end
    end)

    ESPCache[player] = { Billboard = billboard, Highlight = highlight, Box = box, Connection = renderConn }
end

for _, p in ipairs(Players:GetPlayers()) do
    if p ~= LocalPlayer then createCombinedESP(p) end
end

Players.PlayerAdded:Connect(function(p)
    if p ~= LocalPlayer then createCombinedESP(p) end
end)

Players.PlayerRemoving:Connect(function(p)
    if ESPCache[p] then
        if ESPCache[p].Billboard then ESPCache[p].Billboard:Destroy() end
        if ESPCache[p].Highlight then ESPCache[p].Highlight:Destroy() end
        if ESPCache[p].Box then ESPCache[p].Box:Remove() end
        if ESPCache[p].Connection then ESPCache[p].Connection:Disconnect() end
        ESPCache[p] = nil
    end
end)

------------------------------------------------------------------
-- 4. Pure Ground Item ESP System (Integrated Cleanly)
------------------------------------------------------------------
if CoreGui:FindFirstChild("PureGroundItemESP") then
    CoreGui.PureGroundItemESP:Destroy()
end

local GroundItemScreenGui = Instance.new("ScreenGui")
GroundItemScreenGui.Name = "PureGroundItemESP"
GroundItemScreenGui.ResetOnSpawn = false
if gethui then
    GroundItemScreenGui.Parent = gethui()
else
    GroundItemScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

local GroundItemRarityColors = {
    ["Common"] = Color3.fromRGB(200, 200, 200),
    ["Uncommon"] = Color3.fromRGB(0, 255, 0),
    ["Rare"] = Color3.fromRGB(0, 150, 255),
    ["Epic"] = Color3.fromRGB(163, 53, 238),
    ["Legendary"] = Color3.fromRGB(255, 165, 0),
}

local TrackedGroundItems = {}

local function getTargetPartForGroundItem(obj)
    if obj:IsA("Tool") then
        return obj:FindFirstChild("Handle") or obj:FindFirstChildWhichIsA("BasePart", true)
    elseif obj:IsA("Model") then
        return obj.PrimaryPart or obj:FindFirstChild("Handle") or obj:FindFirstChildWhichIsA("BasePart", true)
    elseif obj:IsA("BasePart") then
        return obj
    end
    return nil
end

local function getGroundItemInfo(obj)
    local name = obj.Name
    local nameLower = name:lower()
    local rarity = "Common"
    
    if nameLower:find("glock") then
        rarity = "Rare"
    elseif nameLower:find("ammo") or nameLower:find("buckshot") then
        rarity = "Uncommon"
    elseif nameLower:find("shotgun") or nameLower:find("rifle") then
        rarity = "Rare"
    end
    
    return name, GroundItemRarityColors[rarity] or Color3.fromRGB(200, 200, 200)
end

local function isAllowedGroundItem(obj)
    if not obj or not obj.Parent then return false end
    if obj == workspace.CurrentCamera then return false end

    if obj:IsDescendantOf(Players) then return false end
    local model = obj:FindFirstAncestorOfClass("Model")
    if model and model:FindFirstChildOfClass("Humanoid") then
        return false
    end

    local name = obj.Name:lower()
    
    if name:find("tile") or name:find("bathroom") or name:find("placeholder") or name:find("pot") 
        or name:find("hitbox") or name:find("box") or name:find("door") or name:find("wall") 
        or name:find("fuse") or name:find("shelving") or name:find("mesh") 
        or name:find("sign") or name:find("zone") or name:find("guncase") or name:find("dummy")
        or name:find("storage") or name:find("safe") or name:find("crate") or name:find("gunsmith")
        or name == "part" or name == "model" or name == "terrain" or name == "baseplate" 
        or name == "humanoidrootpart" or name == "head" or name == "torso" then
        return false
    end

    local isTargetItem = name:find("glock") or name:find("ammo") or name:find("shotgun") or name:find("rifle") or name:find("pistol") or name:find("buckshot")
    if not isTargetItem and not obj:IsA("Tool") then
        return false
    end

    local ancestor = obj.Parent
    while ancestor and ancestor ~= workspace do
        local anName = ancestor.Name:lower()
        if anName:find("shelf") or anName:find("showcase") or anName:find("display") or anName:find("counter") 
            or anName:find("rack") or anName:find("cabinet") or anName:find("case") or anName:find("stand") 
            or anName:find("store") or anName:find("shop") or anName:find("furniture") or anName:find("glass") then
            return false
        end
        ancestor = ancestor.Parent
    end

    return true
end

local function createGroundItemTag(obj)
    if TrackedGroundItems[obj] then return end

    local targetPart = getTargetPartForGroundItem(obj)
    if not targetPart then return end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "ItemTag"
    billboard.Size = UDim2.new(0, 112, 0, 24)
    billboard.StudsOffset = Vector3.new(0, 1.5, 0)
    billboard.AlwaysOnTop = true
    billboard.Adornee = targetPart
    billboard.Enabled = Config.ESP_GroundItem
    billboard.Parent = GroundItemScreenGui

    local textLabel = Instance.new("TextLabel")
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.TextScaled = true
    textLabel.Font = Enum.Font.GothamBold

    local displayName, color = getGroundItemInfo(obj)

    textLabel.Text = displayName
    textLabel.TextColor3 = color
    textLabel.TextStrokeTransparency = 0
    textLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    textLabel.Parent = billboard

    TrackedGroundItems[obj] = billboard

    obj.AncestryChanged:Connect(function(_, parent)
        if not parent or not parent:IsDescendantOf(workspace) then
            if TrackedGroundItems[obj] then
                TrackedGroundItems[obj]:Destroy()
                TrackedGroundItems[obj] = nil
            end
        end
    end)
end

for _, obj in ipairs(workspace:GetDescendants()) do
    pcall(function()
        if isAllowedGroundItem(obj) then
            createGroundItemTag(obj)
        end
    end)
end

workspace.DescendantAdded:Connect(function(obj)
    task.wait(0.1)
    pcall(function()
        if isAllowedGroundItem(obj) then
            createGroundItemTag(obj)
        end
    end)
end)

createSwitch(ESPPage, "Show Ground Items (Pure ESP)", Config.ESP_GroundItem, function(v)
    Config.ESP_GroundItem = v
    GroundItemScreenGui.Enabled = v
    for _, tag in pairs(TrackedGroundItems) do
        if tag then tag.Enabled = v end
    end
end)

------------------------------------------------------------------
-- 5. Main Loop, Metatable Hooks & Input
------------------------------------------------------------------
local CurrentAimTarget = nil
local CurrentAimHead = nil
local IsAiming = false

local rawMeta = getrawmetatable and getrawmetatable(game)
if rawMeta and setreadonly then
    setreadonly(rawMeta, false)
    local oldNamecall = rawMeta.__namecall
    rawMeta.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()

        if Config.InfiniteStamina and (method == "FireServer" or method == "InvokeServer") then
            local name = tostring(self.Name):lower()
            if name:find("stamina") or name:find("drain") or name:find("deplete") or name:find("energy") or name:find("sprint") then
                return nil
            end
        end

        if Config.SilentAim and not checkcaller() then
            if method == "Raycast" or method == "FindPartOnRay" or method == "FindPartOnRayWithIgnoreList" or method == "FindPartOnRayWithWhitelist" then
                if CurrentAimTarget and CurrentAimHead then
                    local args = {...}
                    if method == "Raycast" and self == workspace then
                        local origin = args[1]
                        local direction = args[2]
                        if origin and direction then
                            args[2] = (CurrentAimHead.Position - origin).Unit * direction.Magnitude
                            return oldNamecall(self, unpack(args))
                        end
                    elseif method:find("FindPartOnRay") then
                        local oldRay = args[1]
                        if typeof(oldRay) == "Ray" then
                            local origin = oldRay.Origin
                            local direction = oldRay.Direction
                            args[1] = Ray.new(origin, (CurrentAimHead.Position - origin).Unit * direction.Magnitude)
                            return oldNamecall(self, unpack(args))
                        end
                    end
                end
            end
        end

        return oldNamecall(self, ...)
    end)

    local oldIndex = rawMeta.__index
    rawMeta.__index = newcclosure(function(self, idx)
        if Config.SilentAim and not checkcaller() and self == Mouse then
            if CurrentAimTarget and CurrentAimHead then
                if idx == "Hit" then return CurrentAimHead.CFrame
                elseif idx == "Target" then return CurrentAimHead end
            end
        end
        return oldIndex(self, idx)
    end)
end

local currentFPS = 60
local currentPing = 0

RunService.RenderStepped:Connect(function(deltaTime)
    if deltaTime > 0 then
        local instantFPS = 1 / deltaTime
        currentFPS = math.floor(currentFPS * 0.9 + instantFPS * 0.1 + 0.5)
    end

    pcall(function()
        currentPing = math.floor(NetworkStats:GetValue() + 0.5)
    end)

    local pingColor = "#2ECC71"
    if currentPing > 300 then pingColor = "#FF4D4D"
    elseif currentPing > 100 then pingColor = "#FF9F43" end

    StatsLabel.Text = string.format(" FPS: %3d | Ping: <font color=\"%s\">%3dms</font>", currentFPS, pingColor, currentPing)

    if Config.Aimbot then
        AimbotStatusLabel.Text = ' Aimbot: <font color="#2ECC71">ON</font>'
    else
        AimbotStatusLabel.Text = ' Aimbot: <font color="#FF4D4D">OFF</font>'
    end

    local centerPos = getScreenCenter()
    
    FOVCircle.Position = centerPos
    FOVCircle.Radius = Config.FOV
    FOVCircle.Visible = Config.ShowFOV and (Config.SilentAim or Config.Aimbot)

    if Config.SilentAim or Config.Aimbot then
        CurrentAimTarget, CurrentAimHead = getClosestPlayerToCenter()
    else
        CurrentAimTarget, CurrentAimHead = nil, nil
    end

    if Config.Aimbot and IsAiming and CurrentAimHead then
        local targetCFrame = CFrame.new(Camera.CFrame.Position, CurrentAimHead.Position)
        if Config.AimbotSmoothness >= 100 then
            Camera.CFrame = targetCFrame
        else
            Camera.CFrame = Camera.CFrame:Lerp(targetCFrame, Config.AimbotSmoothness / 100)
        end
    end

    if Config.SilentAim and Config.RedLineLock then
        if CurrentAimTarget and CurrentAimHead then
            local headPos, onScreen = Camera:WorldToViewportPoint(CurrentAimHead.Position)
            if onScreen then
                RedLine.From = centerPos
                RedLine.To = Vector2.new(headPos.X, headPos.Y)
                RedLine.Visible = true
            else RedLine.Visible = false end
        else RedLine.Visible = false end
    else RedLine.Visible = false end

    local char = LocalPlayer.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")

        if Config.WalkSpeedEnabled and hum and hrp and hum.MoveDirection.Magnitude > 0 then
            local baseSpeed = 16
            local targetSpeed = baseSpeed * Config.SpeedMultiplier
            local speedBoost = (targetSpeed - baseSpeed) * deltaTime
            hrp.CFrame = hrp.CFrame + (hum.MoveDirection * speedBoost)
        end

        if hum and Config.JumpPowerEnabled then 
            hum.UseJumpPower = true 
            hum.JumpPower = Config.JumpPower 
        end

        if hum and Config.GodMode then hum.Health = hum.MaxHealth end
        if hum and Config.NoFallDamage then hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false) end

        if Config.InfiniteStamina then
            local function maxOutStamina(targetObject)
                if not targetObject then return end
                for _, child in pairs(targetObject:GetChildren()) do
                    local name = child.Name:lower()
                    if name:find("stamina") or name:find("energy") or name:find("sprint") then
                        if child:IsA("NumberValue") or child:IsA("IntValue") then
                            local maxVal = targetObject:FindFirstChild("Max" .. child.Name) or targetObject:FindFirstChild(child.Name .. "Max")
                            child.Value = maxVal and maxVal.Value or 130
                        end
                    end
                end
                for attrName, attrValue in pairs(targetObject:GetAttributes()) do
                    local name = attrName:lower()
                    if (name:find("stamina") or name:find("energy") or name:find("sprint")) and type(attrValue) == "number" then
                        targetObject:SetAttribute(attrName, 130)
                    end
                end
            end
            maxOutStamina(char)
            maxOutStamina(LocalPlayer)
            maxOutStamina(hum)
        end
    end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed then
        if input.UserInputType == Enum.UserInputType.Keyboard then
            if input.KeyCode == Config.ToggleKey then
                MainFrame.Visible = not MainFrame.Visible
            elseif input.KeyCode == Config.AimbotToggleKey then
                Config.Aimbot = not Config.Aimbot
                if aimbotSwitch then
                    aimbotSwitch.SetState(Config.Aimbot)
                end
                SaveConfig()
            end
        end
        
        if input.UserInputType == Config.AimbotKey or input.KeyCode == Config.AimbotKey then
            IsAiming = true
        end
    end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
    if input.UserInputType == Config.AimbotKey or input.KeyCode == Config.AimbotKey then
        IsAiming = false
    end
end)