local addonName, ns = ...

-- ----------------------------------------------------------------------------
-- MAIN FRAME SETUP
-- ----------------------------------------------------------------------------
local MLT = CreateFrame("Frame", "MLT_MainFrame", UIParent, "BackdropTemplate")
_G["MLT_MainFrame"] = MLT
tinsert(UISpecialFrames, "MLT_MainFrame")

-- ----------------------------------------------------------------------------
-- CACHED GLOBALS
-- ----------------------------------------------------------------------------
local C_Item = C_Item
local C_QuestLog = C_QuestLog
local C_Map = C_Map
local C_SuperTrack = C_SuperTrack
local C_TradeSkillUI = C_TradeSkillUI
local C_Spell = C_Spell
local C_UnitAura = C_UnitAura
local C_DateAndTime = C_DateAndTime
local GetItemInfo = GetItemInfo
local HandleModifiedItemClick = HandleModifiedItemClick
local GetProfessions = GetProfessions
local GetProfessionInfo = GetProfessionInfo
local math_floor = math.floor
local string_format = string.format
local lastCDOnTaxing = 0

-- ----------------------------------------------------------------------------
-- CONSTANTS & DATABASE
-- ----------------------------------------------------------------------------
local SKINNING_ID = 393
local BUTTON_SIZE = 32
local ROW_HEIGHT = 50
local PADDING = 10

-- Buff & Action IDs
local BUFF_RELAXED = 1269152
local BUFF_TAXING = 1223388

local ITEM_FOR_RELAXED = 242299   -- Item ID (Sanguithorn Tea)
local SPELL_FOR_TAXING = 1223388  -- Spell ID (Sharpen Your Knife)

-- Updated Lure Data
local LURE_DATA = {
    {
        name = "Eversong (Ghostclaw)",
        itemID = 238652, recipeID = 1225943, questID = 88545, uiMapID = 2395,
        x = 0.4195, y = 0.8005,
        auraID = 1239058,
        mats = { { id = 238371, req = 8 }, { id = 238366, req = 8 } }
    },
    {
        name = "Zul'Aman (Silverscale)",
        itemID = 238653, recipeID = 1225944, questID = 88526, uiMapID = 2437,
        x = 0.4769, y = 0.5325,
        auraID = 1239120,
        mats = { { id = 238382, req = 8 } }
    },
    {
        name = "Harandar (Lumenfin)",
        itemID = 238654, recipeID = 1225945, questID = 88531, uiMapID = 2413,
        x = 0.6628, y = 0.4791,
        auraID = 1239121,
        mats = { { id = 238375, req = 8 }, { id = 238374, req = 8 } }
    },
    {
        name = "Voidstorm (Umbrafang)",
        itemID = 238655, recipeID = 1225946, questID = 88532, uiMapID = 2405,
        x = 0.5460, y = 0.6580,
        auraID = 1239122,
        mats = { { id = 238373, req = 4 } }
    },
    {
        name = "Grand Beast (Netherscythe)",
        itemID = 238656, recipeID = 1225948, questID = 88524, uiMapID = 2405,
        x = 0.4325, y = 0.8275,
        auraID = 1239151,
        mats = { { id = 238380, req = 4 } }
    }
}

-- ----------------------------------------------------------------------------
-- HELPER FUNCTIONS
-- ----------------------------------------------------------------------------
-- Checks if the current character has the Skinning profession
local function HasSkinningProfession()
    local prof1, prof2 = GetProfessions()
    for _, prof in pairs({prof1, prof2}) do
        if prof then
            local _, _, _, _, _, _, skillLine = GetProfessionInfo(prof)
            if skillLine == SKINNING_ID then
                return true
            end
        end
    end
    return false
end

-- UNIVERSAL AURA SCANNER
local function PlayerHasAura(targetSpellID)
    if not targetSpellID then return false end
    local found = false
    
    local function CheckAura(...)
        local arg1 = ...
        local spellID
        if type(arg1) == "table" then
            spellID = arg1.spellId
        else
            spellID = select(10, ...)
        end
        
        if spellID == targetSpellID then
            found = true
        end
    end

    pcall(function()
        AuraUtil.ForEachAura("player", "HELPFUL", nil, CheckAura)
        if not found then
            AuraUtil.ForEachAura("player", "HARMFUL", nil, CheckAura)
        end
    end)
    
    return found
end

local function GetTotalItemCount(itemID)
    local success, count = pcall(C_Item.GetItemCount, itemID, true, false, true, true)
    return success and count or 0
end

local function GetCraftableCount(recipeID)
    local success, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    if not success or type(schematic) ~= "table" then return 0 end

    local minCrafts = 9999
    if schematic.reagentSlotSchematics then
        for _, slot in ipairs(schematic.reagentSlotSchematics) do
            local required = slot.quantityRequired
            local available = 0
            if slot.reagents then
                for _, reagent in ipairs(slot.reagents) do
                    available = available + GetTotalItemCount(reagent.itemID)
                end
            end
            if required > 0 then
                local craftsForThisSlot = math_floor(available / required)
                if craftsForThisSlot < minCrafts then
                    minCrafts = craftsForThisSlot
                end
            end
        end
    end
    return (minCrafts == 9999) and 0 or minCrafts
end

local function SetMapWaypoint(uiMapID, x, y, name)
    local point = UiMapPoint.CreateFromCoordinates(uiMapID, x, y)
    C_Map.SetUserWaypoint(point)
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    print(string_format("|cFF00FFFF[MLT]|r Waypoint set for %s!", name))
end

local function CreateFlatBorder(frame)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    frame:SetBackdropBorderColor(0, 0, 0, 1)
end

-- cooldown on spells
local function GetSpellCooldownLeft(spellID)
    -- cannot access this while infight
    if not UnitAffectingCombat("player") then
        local cd = C_Spell.GetSpellCooldown(spellID)
        if not cd or not cd.startTime or not cd.duration then
            lastCDOnTaxing = 0
        else
            lastCDOnTaxing = math.max(0, (cd.startTime + cd.duration) - GetTime())
        end
    end
    return lastCDOnTaxing
    
end

-- glow button turn on and off
local function DoButtonGlow(hButton, doGlow)
    if not doGlow then
        hButton.activeGlow:Hide()
    else
        hButton.activeGlow:Show()
    end
end

-- glow button creation
local function CreateButtonGlow(hButton, doGlow)
    hButton.activeGlow = hButton:CreateTexture(nil, "OVERLAY")
    hButton.activeGlow:SetPoint("TOPLEFT", -4, 4)
    hButton.activeGlow:SetPoint("BOTTOMRIGHT", 4, -4)
    hButton.activeGlow:SetTexture("Interface\\Buttons\\checkbuttonhilight")
    hButton.activeGlow:SetBlendMode("ADD")
    hButton.activeGlow:SetVertexColor(1, 1, 1)
    hButton.activeGlow:SetAlpha(0.6)
    DoButtonGlow(hButton)
end

local function CreateButtonCD(hButton)
    hButton.cooldownText = hButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hButton.cooldownText:SetFontObject(GameFontHighlightMed2Outline)
    hButton.cooldownText:SetPoint("CENTER", hButton, "CENTER", 0, 0)
    hButton.cooldownText:SetText("")
    hButton.cooldownText:SetTextColor(1, 1, 1, 1)
end

local function SetButtonCD(hButton, seconds)
    local text = ""
    if seconds and seconds > 0 then
        local fmt, value = SecondsToTimeAbbrev(seconds)
        text = format(fmt, value)
    end
    hButton.cooldownText:SetText(text)
end

local function SetButtonCount(hButton, cnt)
    hButton.count:SetText(cnt > 0 and cnt or "0")
end

local function SetUnavailableTextColor(hButton)
    hButton:SetTextColor(1, 0, 0)
end

local function SetAvailableTextColor(hButton)
    hButton:SetTextColor(0, 1, 0)
end

local function SetTextColorByAvailability(hButton, avail)
    if avail then
        SetAvailableTextColor(hButton)
    else
        SetUnavailableTextColor(hButton)
    end
end

-- ----------------------------------------------------------------------------
-- UI BUILDER
-- ----------------------------------------------------------------------------

-- return true if made visible, otherwise false
function MLT:ToggleVisibility()
    if not UnitAffectingCombat("player") then
        if self:IsShown() then
            self:Hide()
        else
            -- Ensure it has a position
            self:ClearAllPoints()
            if MLT_CharData.detached and MLT_CharData.point then
                self:SetPoint(MLT_CharData.point, UIParent, MLT_CharData.relativePoint, MLT_CharData.x, MLT_CharData.y)
            elseif ProfessionsFrame and ProfessionsFrame:IsShown() then
                self:SetPoint("BOTTOMLEFT", ProfessionsFrame, "BOTTOMRIGHT", 5, 0)
            else
                -- Default to center if forced open without profession frame and not detached
                self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
            self:Show()
            self:UpdateData()
        end
    end
    return self:IsShown()
end

local rows = {}

function MLT:SetupUI()
    if self.isSetup then return end
    self.isSetup = true

    self:SetSize(460, (#LURE_DATA * ROW_HEIGHT) + 120)
    self:SetFrameStrata("HIGH")
    self:SetMovable(true)
    self:EnableMouse(true)
    self:RegisterForDrag("LeftButton")
    
    CreateFlatBorder(self)

    -- MAIN TITLE
    local title = self:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -10)
    title:SetText("Midnight Lure Tracker")

    -- COLUMN HEADERS
    local lblCraft = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lblCraft:SetPoint("TOPLEFT", self, "TOPLEFT", 22, -35)
    lblCraft:SetText("Craft")

    local lblUse = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lblUse:SetPoint("TOPLEFT", self, "TOPLEFT", 67, -35)
    lblUse:SetText("Use")

    for i, data in ipairs(LURE_DATA) do
        local yOffset = -50 - ((i - 1) * ROW_HEIGHT)
        local row = CreateFrame("Frame", nil, self)
        row:SetSize(440, ROW_HEIGHT)
        row:SetPoint("TOP", self, "TOP", 0, yOffset)

        -- 1. CRAFT ICON BUTTON
        local craftBtn = CreateFrame("Button", nil, row, "SecureActionButtonTemplate, BackdropTemplate")
        craftBtn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
        craftBtn:SetPoint("LEFT", PADDING, 0)
        CreateFlatBorder(craftBtn)
        
        craftBtn:RegisterForClicks("LeftButtonUp")
        craftBtn:SetAttribute("type", "macro")
        
        local spellInfo = C_Spell.GetSpellInfo(data.recipeID)
        local spellName = spellInfo and spellInfo.name or ""
        
        craftBtn:SetAttribute("macrotext1", "/run C_TradeSkillUI.OpenTradeSkill(" .. SKINNING_ID .. ")\n/run C_TradeSkillUI.CraftRecipe(" .. data.recipeID .. ")")
        craftBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        craftBtn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
        
        local craftIcon = craftBtn:CreateTexture(nil, "ARTWORK")
        craftIcon:SetPoint("TOPLEFT", 1, -1)
        craftIcon:SetPoint("BOTTOMRIGHT", -1, 1)
        if spellInfo then craftIcon:SetTexture(spellInfo.iconID) end
        craftIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        craftBtn.icon = craftIcon

        craftBtn.count = craftBtn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        craftBtn.count:SetPoint("BOTTOMRIGHT", -2, 2)
        SetUnavailableTextColor(craftBtn.count)
        
        craftBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(data.recipeID)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cFF00FF00Click:|r Craft Lure", 1, 1, 1)
            GameTooltip:Show()
        end)
        craftBtn:SetScript("OnLeave", GameTooltip_Hide)
        CreateButtonGlow(craftBtn)

        -- 2. LURE ICON BUTTON
        local lureBtn = CreateFrame("Button", nil, row, "SecureActionButtonTemplate, BackdropTemplate")
        lureBtn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
        lureBtn:SetPoint("LEFT", craftBtn, "RIGHT", PADDING, 0)
        CreateFlatBorder(lureBtn)
        
        lureBtn:RegisterForClicks("LeftButtonUp")
        lureBtn:SetAttribute("type", "macro")
        lureBtn:SetAttribute("macrotext1", "/use [@player] item:" .. data.itemID)
        
        lureBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        lureBtn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
        
        local lureIcon = lureBtn:CreateTexture(nil, "ARTWORK")
        lureIcon:SetPoint("TOPLEFT", 1, -1)
        lureIcon:SetPoint("BOTTOMRIGHT", -1, 1)
        lureIcon:SetTexture(C_Item.GetItemIconByID(data.itemID))
        lureIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        lureBtn.icon = lureIcon

        lureBtn.count = lureBtn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        lureBtn.count:SetPoint("BOTTOMRIGHT", -2, 2)
        
        lureBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(data.itemID)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cFF00FF00Click:|r Drop Lure", 1, 1, 1)
            GameTooltip:Show()
        end)
        lureBtn:SetScript("OnLeave", GameTooltip_Hide)
        CreateButtonGlow(lureBtn)

        -- 3. NAME & STATUS TEXT
        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("TOPLEFT", lureBtn, "TOPRIGHT", PADDING, -1)
        nameText:SetText(data.name)

        local statusText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        statusText:SetPoint("BOTTOMLEFT", lureBtn, "BOTTOMRIGHT", PADDING, 1)

        -- Secure Hover Area for Alt Tracker
        local altHoverArea = CreateFrame("Frame", nil, row)
        altHoverArea:SetSize(160, 35)
        altHoverArea:SetPoint("LEFT", lureBtn, "RIGHT", PADDING, 0)
        altHoverArea:EnableMouse(true)
        altHoverArea:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Alt Tracker Status", 1, 1, 1)
            GameTooltip:AddLine("Lure: " .. data.name, 0.8, 0.8, 0.8)
            GameTooltip:AddLine(" ")
            
            if type(MLT_Data) == "table" and type(MLT_Data.alts) == "table" then
                local currentTime = GetServerTime()
                local hasData = false
                for fullCharName, charData in pairs(MLT_Data.alts) do
                    local isReset = charData.resetTime and (currentTime >= charData.resetTime)
                    local kills = isReset and 0 or (charData[data.questID] or 0)
                    local color = (kills == 1) and "|cFFFF0000[Skinned]|r" or "|cFF00FF00[Ready]|r"

                    local cdText = ""
                    if kills == 1 then
                        local fmt, value = SecondsToTimeAbbrev(charData.resetTime - currentTime)
                        cdText = " CD:".. format(fmt, value)
                        color = color .. cdText
                    end

                    GameTooltip:AddDoubleLine(fullCharName, color)
                    hasData = true
                end
                if not hasData then
                    GameTooltip:AddLine("No alts saved yet.", 0.5, 0.5, 0.5)
                end
            else
                GameTooltip:AddLine("No data yet. Relog to save.", 1, 0, 0)
            end
            GameTooltip:Show()
        end)
        altHoverArea:SetScript("OnLeave", GameTooltip_Hide)

        -- 4. MARK BUTTON
        local markBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        markBtn:SetSize(50, 24)
        markBtn:SetPoint("RIGHT", -PADDING, 0)
        markBtn:SetText("Mark")
        markBtn:SetScript("OnClick", function()
            SetMapWaypoint(data.uiMapID, data.x, data.y, data.name)
        end)

        -- 5. MATERIALS DISPLAY
        local matBtns = {}
        for m, mat in ipairs(data.mats) do
            local matBg = CreateFrame("Frame", nil, row, "BackdropTemplate")
            matBg:SetSize(28, 28)
            matBg:SetPoint("RIGHT", markBtn, "LEFT", -PADDING - ((m-1) * 45), 2)
            CreateFlatBorder(matBg)

            -- Interactive material button
            local matBtn = CreateFrame("Button", nil, matBg)
            matBtn:SetPoint("TOPLEFT", 1, -1)
            matBtn:SetPoint("BOTTOMRIGHT", -1, 1)
            matBtn:RegisterForClicks("LeftButtonUp")
            
            -- Support Shift + Click for Chat Link / AH
            matBtn:SetScript("OnClick", function()
                if IsShiftKeyDown() then
                    local _, link = GetItemInfo(mat.id)
                    if link then HandleModifiedItemClick(link) end
                end
            end)
            
            local tex = matBtn:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints()
            tex:SetTexture(C_Item.GetItemIconByID(mat.id))
            tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            matBtn.icon = tex
            
            matBtn.text = matBtn:CreateFontString(nil, "OVERLAY", "SystemFont_Outline_Small")
            matBtn.text:SetPoint("TOP", matBg, "BOTTOM", 0, -2)

            matBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetItemByID(mat.id)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cFF00FFFFShift + Click:|r Link to Chat / AH", 1, 1, 1)
                GameTooltip:Show()
            end)
            matBtn:SetScript("OnLeave", GameTooltip_Hide)

            matBtns[m] = { btn = matBtn, id = mat.id, req = mat.req }
        end

        rows[i] = {
            data = data,
            craftBtn = craftBtn,
            lureBtn = lureBtn,
            statusText = statusText,
            matBtns = matBtns
        }
    end

    -- ------------------------------------------------------------------------
    -- BOTTOM ACTION BAR (BUFF SHORTCUTS)
    -- ------------------------------------------------------------------------
    local divider = self:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.3, 0.3, 0.3, 1)
    divider:SetSize(440, 1)
    divider:SetPoint("BOTTOM", self, "BOTTOM", 0, 45)

    -- Relaxed Button (Sanguithorn Tea)
    self.relaxedBtn = CreateFrame("Button", nil, self, "SecureActionButtonTemplate, BackdropTemplate")
    self.relaxedBtn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    self.relaxedBtn:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", PADDING, PADDING)

    CreateFlatBorder(self.relaxedBtn)
    self.relaxedBtn:SetAttribute("type", "macro")
    self.relaxedBtn:SetAttribute("macrotext1", "/use item:" .. ITEM_FOR_RELAXED)
    
    local relTex = self.relaxedBtn:CreateTexture(nil, "ARTWORK")
    relTex:SetAllPoints()
    relTex:SetTexture(C_Item.GetItemIconByID(ITEM_FOR_RELAXED))
    relTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    self.relaxedBtn.icon = relTex 
    
    local relText = self.relaxedBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    relText:SetPoint("LEFT", self.relaxedBtn, "RIGHT", 5, 0)
    self.relaxedBtn.text = relText

    self.relaxedBtn.count = self.relaxedBtn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    self.relaxedBtn.count:SetPoint("BOTTOMRIGHT", -2, 2)
    SetUnavailableTextColor(self.relaxedBtn.count)

    local relaxedCount = GetTotalItemCount(ITEM_FOR_RELAXED)
    self.relaxedBtn.count:SetText(relaxedCount > 0 and relaxedCount or "0")
    self.relaxedBtn.icon:SetDesaturated(relaxedCount == 0)

    CreateButtonGlow(self.relaxedBtn)
    DoButtonGlow(self.relaxedBtn)

    -- Shift+Click to link Sanguithorn Tea
    self.relaxedBtn:HookScript("OnClick", function(self)
        if IsShiftKeyDown() then
            local _, link = GetItemInfo(ITEM_FOR_RELAXED)
            if link then HandleModifiedItemClick(link) end
        end
    end)

    self.relaxedBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(ITEM_FOR_RELAXED)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cFF00FFFFShift + Click:|r Link to Chat / AH", 1, 1, 1)
        GameTooltip:Show()
    end)
    self.relaxedBtn:SetScript("OnLeave", GameTooltip_Hide)

    -- Taxing Button (Sharpen Your Knife)
    self.taxingBtn = CreateFrame("Button", nil, self, "SecureActionButtonTemplate, BackdropTemplate")
    self.taxingBtn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    self.taxingBtn:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -120, PADDING)
    CreateFlatBorder(self.taxingBtn)
    self.taxingBtn:SetAttribute("type", "macro")

    CreateButtonGlow(self.taxingBtn)
    CreateButtonCD(self.taxingBtn)
    
    local taxingSpellInfo = C_Spell.GetSpellInfo(SPELL_FOR_TAXING)
    local taxingSpellName = taxingSpellInfo and taxingSpellInfo.name or ""
    self.taxingBtn:SetAttribute("macrotext1", "/cast " .. taxingSpellName)
    
    local taxTex = self.taxingBtn:CreateTexture(nil, "ARTWORK")
    taxTex:SetAllPoints()
    if taxingSpellInfo then taxTex:SetTexture(taxingSpellInfo.iconID) end
    taxTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    self.taxingBtn.icon = taxTex 

    local taxText = self.taxingBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    taxText:SetPoint("LEFT", self.taxingBtn, "RIGHT", 5, 0)
    self.taxingBtn.text = taxText

    self.taxingBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(SPELL_FOR_TAXING)
        GameTooltip:Show()
    end)
    self.taxingBtn:SetScript("OnLeave", GameTooltip_Hide)

    self:SetScript("OnDragStart", function(s) s:StartMoving() end)
    self:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        local p, _, rp, x, y = s:GetPoint()
        MLT_CharData.detached = true
        MLT_CharData.point, MLT_CharData.relativePoint, MLT_CharData.x, MLT_CharData.y = p, rp, x, y
    end)
end

function MLT:UpdateData()
    if not self.isSetup then return end

    local pName = UnitName("player") or "Unknown"
    local pRealm = GetRealmName() or "Unknown"
    local playerName = pName .. "-" .. pRealm

    if type(MLT_Data) ~= "table" then MLT_Data = {} end
    if type(MLT_Data.alts) ~= "table" then MLT_Data.alts = {} end
    
    -- Save character data ONLY if they have the Skinning profession
    local hasSkinning = HasSkinningProfession()
    
    if hasSkinning then
        if type(MLT_Data.alts[playerName]) ~= "table" then MLT_Data.alts[playerName] = {} end
        local success, resetSeconds = pcall(C_DateAndTime.GetSecondsUntilDailyReset)
        local timeToReset = success and resetSeconds or 86400
        MLT_Data.alts[playerName].resetTime = GetServerTime() + timeToReset
    end

    for i, row in ipairs(rows) do
        local craftable = GetCraftableCount(row.data.recipeID)
        row.craftBtn.count:SetText(craftable > 0 and craftable or "0")
        row.craftBtn.icon:SetDesaturated(craftable == 0)
        

        local lureCount = GetTotalItemCount(row.data.itemID)
        row.lureBtn.count:SetText(lureCount > 0 and lureCount or "0")
        row.lureBtn.icon:SetDesaturated(lureCount == 0)

        DoButtonGlow(row.craftBtn, craftable and craftable > 0 and lureCount == 0)
        SetTextColorByAvailability(row.craftBtn.count, craftable and craftable > 0)

        local isDead = false
        pcall(function() isDead = C_QuestLog.IsQuestFlaggedCompleted(row.data.questID) end)
        
        -- Update character quest state only if they are a Skinner
        if hasSkinning then
            MLT_Data.alts[playerName][row.data.questID] = isDead and 1 or 0
        end

        DoButtonGlow(row.lureBtn, lureCount and lureCount > 0 and PlayerHasAura(row.data.auraID) and not isDead)
        SetTextColorByAvailability(row.lureBtn.count, lureCount and lureCount > 0)
        
        local statusTextStr = isDead and "Daily: |cFFFF0000Skinned|r" or "Daily: |cFF00FF00Ready|r"
        local cdText = ""
        if isDead then
            local fmt, value = SecondsToTimeAbbrev(MLT_Data.alts[playerName].resetTime - GetServerTime())
            cdText = " CD:".. format(fmt, value)
        end
        row.statusText:SetText(statusTextStr .. cdText .. " |cFF888888[Alts]|r")

        for _, matData in ipairs(row.matBtns) do
            local current = GetTotalItemCount(matData.id)
            local color = (current >= matData.req) and "|cFF00FF00" or "|cFFFF0000"
            matData.btn.text:SetText(color .. current .. "|r/" .. matData.req)
            matData.btn.icon:SetDesaturated(current < matData.req)
        end
    end
    
    -- Bottom Buttons Logic
    local hasRelaxed = PlayerHasAura(BUFF_RELAXED)
    local hasTaxing = PlayerHasAura(BUFF_TAXING)
    local relaxedCount = GetTotalItemCount(ITEM_FOR_RELAXED)

    SetButtonCount(self.relaxedBtn, relaxedCount)
    DoButtonGlow(self.relaxedBtn, relaxedCount > 0 and hasRelaxed ~= true)
    SetTextColorByAvailability(self.relaxedBtn.count, relaxedCount and relaxedCount > 0)

    if self.relaxedBtn and self.relaxedBtn.icon and self.relaxedBtn.text then 
        self.relaxedBtn.icon:SetDesaturated(not hasRelaxed) 
        if hasRelaxed then
            self.relaxedBtn.text:SetText("Relaxed: |cFF00FF00Active|r")
        else
            self.relaxedBtn.text:SetText("Relaxed: |cFFFF0000Inactive|r")
        end
    end
    
    local cdOnTaxing = GetSpellCooldownLeft(BUFF_TAXING)
    SetButtonCD(self.taxingBtn, cdOnTaxing)
    DoButtonGlow(self.taxingBtn, cdOnTaxing == 0)
    
    if self.taxingBtn and self.taxingBtn.icon and self.taxingBtn.text then 
        self.taxingBtn.icon:SetDesaturated(not hasTaxing) 
        if hasTaxing then
            self.taxingBtn.text:SetText("Taxing: |cFF00FF00Active|r")
        else
            self.taxingBtn.text:SetText("Taxing: |cFFFF0000Inactive|r")
        end
    end

    --disable button if have relaxed buff
    if not UnitAffectingCombat("player") then
        --disable button if have relaxed buff
        if hasRelaxed and self.relaxedBtn:IsEnabled() then
            self.relaxedBtn:Disable()
        else
            self.relaxedBtn:Enable()
        end

        --disable button if taxing not usable
        if cdOnTaxing > 0 and self.taxingBtn:IsEnabled() then
            self.taxingBtn:Disable()
        else
            self.taxingBtn:Enable()
        end
    end
end

-- Checks visibility and assigns position if forcing open without professions window
function MLT:UpdateVisibility(doShow)
    -- Ensure it has a position
    self:ClearAllPoints()
    if MLT_CharData.detached and MLT_CharData.point then
        self:SetPoint(MLT_CharData.point, UIParent, MLT_CharData.relativePoint, MLT_CharData.x, MLT_CharData.y)
    elseif ProfessionsFrame and ProfessionsFrame:IsShown() then
        self:SetPoint("BOTTOMLEFT", ProfessionsFrame, "BOTTOMRIGHT", 5, 0)
    else
        -- Default to center if forced open without profession frame and not detached
        self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    if doShow then
        self:Show()
    end
    self:UpdateData()
end

function MLT:CheckVisibility()
    local isSkinning = false

    -- this can only occur when opening tradeskill
    if ProfessionsFrame and ProfessionsFrame:IsShown() then
        local profInfo = C_TradeSkillUI.GetBaseProfessionInfo()
        if profInfo and profInfo.professionID == SKINNING_ID then
            self.forceShow = self:IsShown()
            isSkinning = true
        end
    end

    if self:IsShown() and not self.forceShow and not isSkinning then
        self:Hide()
        return
    end
    
    self:UpdateVisibility(isSkinning)
end

-- ----------------------------------------------------------------------------
-- EVENTS
-- ----------------------------------------------------------------------------
MLT:RegisterEvent("ADDON_LOADED")
MLT:RegisterEvent("PLAYER_LOGIN")
MLT:RegisterEvent("ZONE_CHANGED_NEW_AREA")
MLT:RegisterEvent("TRADE_SKILL_SHOW")
MLT:RegisterEvent("TRADE_SKILL_CLOSE")
MLT:RegisterEvent("QUEST_LOG_UPDATE")
MLT:RegisterEvent("BAG_UPDATE_DELAYED")
MLT:RegisterEvent("UNIT_AURA") 

MLT:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        if type(MLT_Data) ~= "table" then MLT_Data = {} end
        if type(MLT_Data.alts) ~= "table" then MLT_Data.alts = {} end
        if type(MLT_CharData) ~= "table" then MLT_CharData = { detached = false } end
        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        self:SetupUI()
        self:UpdateVisibility(false)

    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_CLOSE" then
        self:CheckVisibility()

    elseif event == "QUEST_LOG_UPDATE" or event == "BAG_UPDATE_DELAYED" or event == "ZONE_CHANGED_NEW_AREA" then
        self:UpdateData()

    elseif event == "UNIT_AURA" and arg1 == "player" then
        self:UpdateData()

    end    
end)

-- ----------------------------------------------------------------------------
-- SLASH COMMANDS
-- ----------------------------------------------------------------------------
SLASH_MLT1 = "/mlt"
SlashCmdList["MLT"] = function(msg)
    local cmd = msg:lower()
    
    if cmd == "reset" then
        MLT_CharData.detached = false
        MLT_CharData.point, MLT_CharData.relativePoint, MLT_CharData.x, MLT_CharData.y = nil, nil, nil, nil
        MLT.forceShow = false
        MLT:UpdateVisibility(false)
        print("|cFF00FFFF[MLT]|r Position and attachment reset.")
        
    elseif cmd == "clear" then
        MLT_Data.alts = {}
        if MLT:IsShown() then
            MLT:UpdateData()
        end
        print("|cFF00FFFF[MLT]|r Saved alts database has been cleared.")
        
    elseif cmd == "help" then
        print("|cFF00FFFF[MLT]|r Available commands:")
        print("  |cFFFFFF00/mlt|r - Toggle visibility")
        print("  |cFFFFFF00/mlt reset|r - Reset frame position to the Skinning window")
        print("  |cFFFFFF00/mlt clear|r - Wipe the saved alts database")
        print("  |cFFFFFF00/mlt help|r - Prints this message")
    else
       MLT:ToggleVisibility()
    end
end