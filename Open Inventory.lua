local uis = game:GetService("UserInputService")
local vim = game:GetService("VirtualInputManager")
local guiService = game:GetService("GuiService")
local player = game.Players.LocalPlayer
local mouse = player:GetMouse()

local hotkey = Enum.KeyCode.Tab -- ปุ่มที่ใช้กดใช้งาน
local saveFileName = "BlockSpin_Inventory_Macro.txt" -- ชื่อไฟล์ที่จะถูกเซฟไว้ในโฟลเดอร์ workspace ของตัวรันสคริปต์

local menuPath = nil
local itemsPath = nil
local isSetupMode = false

-- 1. ฟังก์ชันดึง Path ถาวร (เจาะทะลุการซ่อนชื่อ)
local function getRelativePath(obj)
    local path = ""
    local current = obj
    while current and current ~= player.PlayerGui and current ~= game do
        if path == "" then
            path = current.Name
        else
            path = current.Name .. "\\" .. path
        end
        current = current.Parent
    end
    return path
end

-- 2. ฟังก์ชันหา Object จาก Path แบบ Real-time (กันเกมรีเซ็ต UI)
local function getObjFromRelativePath(path)
    if not path or path == "" then return nil end
    local parts = string.split(path, "\\")
    local current = player:WaitForChild("PlayerGui", 3)
    if not current then return nil end
    
    for i = 1, #parts do
        if current then
            current = current:FindFirstChild(parts[i])
        else
            return nil
        end
    end
    return current
end

-- 3. ฟังก์ชันคลิก
local function clickTarget(targetGui)
    if not targetGui then return end
    local absPos = targetGui.AbsolutePosition
    local absSize = targetGui.AbsoluteSize
    local inset, _ = guiService:GetGuiInset()
    local clickX = absPos.X + (absSize.X / 2)
    local clickY = absPos.Y + (absSize.Y / 2) + inset.Y

    vim:SendMouseButtonEvent(clickX, clickY, 0, true, game, 1)
    task.wait(0.05)
    vim:SendMouseButtonEvent(clickX, clickY, 0, false, game, 1)
end

-- 4. ระบบโหลดไฟล์เซฟ (รันครั้งต่อไปไม่ต้องตั้งค่าใหม่)
local function loadConfig()
    if isfile and readfile and isfile(saveFileName) then
        local data = readfile(saveFileName)
        local paths = string.split(data, "\n")
        if #paths >= 2 then
            menuPath = paths[1]
            itemsPath = paths[2]
            if getObjFromRelativePath(menuPath) then
                return true
            end
        end
    end
    return false
end

-- 5. ระบบเซฟไฟล์ลงเครื่อง (ทำแค่ครั้งแรกครั้งเดียว)
local function saveConfig(mGui, iGui)
    if writefile then
        menuPath = getRelativePath(mGui)
        itemsPath = getRelativePath(iGui)
        local data = menuPath .. "\n" .. itemsPath
        writefile(saveFileName, data)
        print("💾 [สำเร็จ] ระบบจำตำแหน่งปุ่มและเซฟไฟล์ลงเครื่องแล้ว! เข้าเกมครั้งหน้าใช้งานปุ่ม Tab ได้ทันที")
    else
        print("⚠️ ตัวรันสคริปต์ของคุณไม่รองรับการเซฟไฟล์ (writefile)")
    end
end

-- ฟังก์ชันหาปุ่มด้วยเมาส์
local function getGuiUnderMouse()
    local guis = player.PlayerGui:GetGuiObjectsAtPosition(mouse.X, mouse.Y)
    if #guis > 0 then
        for _, gui in ipairs(guis) do
            if gui:IsA("GuiButton") then return gui end
        end
        for _, gui in ipairs(guis) do
            local parent = gui:FindFirstAncestorWhichIsA("GuiButton")
            if parent then return parent end
        end
        return guis[1]
    end
    return nil
end

-- =====================================
-- เริ่มการทำงานของสคริปต์
-- =====================================
if loadConfig() then
    print("✅ โหลดข้อมูลจากไฟล์สำเร็จ! สคริปต์พร้อมใช้งาน กดปุ่ม Tab เพื่อเปิด/ปิดกระเป๋าได้เลย")
else
    isSetupMode = true
    print("=============================")
    print("⚠️ คุณเพิ่งรันครั้งแรก! (ต้องสอนสคริปต์ 1 ครั้งถ้วน):")
    print("1. เอาเมาส์ชี้ 'ปุ่ม 4 สี' แล้วกดเลข 8")
    print("2. เปิดเมนูออก เอาเมาส์ชี้ 'ปุ่ม Items' แล้วกดเลข 9")
    print("=============================")
end

local tempMenuGui = nil

uis.InputBegan:Connect(function(input, gameProcessed)
    -- โหมดตั้งค่า (ทำงานแค่ครั้งแรกที่ไม่มีไฟล์เซฟ)
    if isSetupMode then
        if input.KeyCode == Enum.KeyCode.Eight then
            tempMenuGui = getGuiUnderMouse()
            if tempMenuGui then print("✅ ล็อคเป้า 'ปุ่ม 4 สี' สำเร็จ!") end
        elseif input.KeyCode == Enum.KeyCode.Nine then
            local tempItemsGui = getGuiUnderMouse()
            if tempItemsGui then
                print("✅ ล็อคเป้า 'ปุ่ม Items' สำเร็จ!")
                if tempMenuGui then
                    saveConfig(tempMenuGui, tempItemsGui)
                    isSetupMode = false
                    print("🎉 ตั้งค่าเสร็จสิ้น! ตอนนี้กด Tab เปิด/ปิดกระเป๋าได้เลยครับ")
                end
            end
        end
    end

    -- โหมดใช้งานจริง (ทำงานทุกครั้งที่กด Tab)
    if input.KeyCode == hotkey and (not gameProcessed or input.KeyCode == Enum.KeyCode.Tab) then
        if not isSetupMode and menuPath and itemsPath then
            local currentMenu = getObjFromRelativePath(menuPath)
            local currentItems = getObjFromRelativePath(itemsPath)
            
            if currentMenu and currentItems then
                clickTarget(currentMenu)
                task.wait(0.15)
                clickTarget(currentItems)
            else
                print("❌ หาปุ่มไม่เจอ (เกมอาจจะบัคให้ลองรันสคริปต์ใหม่)")
            end
        end
    end
end)