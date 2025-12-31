-- Required libraries
local tablet = AceLibrary("Tablet-2.0")
local dewdrop = AceLibrary("Dewdrop-2.0")

-- Addon definition
FishSwapFu = AceLibrary("AceAddon-2.0"):new("FuBarPlugin-2.0", "AceEvent-2.0", "AceDB-2.0", "AceConsole-2.0")

-- FuBar Plugin properties
FishSwapFu.hasIcon = "Interface\\Icons\\Trade_Fishing"
FishSwapFu.cannotDetachTooltip = true
FishSwapFu.hasNoColor = true

-- === HARDCODED DATABASE (from original addon) ===
local KNOWN_POLES = {
    -- Standard Vanilla Poles
    [6256] = 0, -- Fishing Pole
    [6365] = 5, -- Strong Fishing Pole
    [6366] = 15, -- Darkwood Fishing Pole
    [6367] = 20, -- Big Iron Fishing Pole
    [12225] = 3, -- Blump Family Fishing Pole
    [19022] = 25, -- Nat Pagle's Extreme Angler FC-5000
    [19970] = 35, -- Arcanite Fishing Pole
    [4598] = 0, -- Goblin Fishing Pole
    [3567] = 0, -- Dwarven Fishing Pole
    [19972] = 25, -- Nat's Lucky Fishing Pole

    -- Turtle WoW Custom Poles
    [7010] = 0, -- Driftwood Fishing Pole
    [84507] = 5 -- Barkskin Fisher
}

-- Hidden Tooltip for scanning
local scanTooltip

-----------------------------------------------------------------------
-- Addon Initialization and Lifecycle
-----------------------------------------------------------------------

function FishSwapFu:OnInitialize()
    -- Create the hidden tooltip frame once
    scanTooltip = CreateFrame("GameTooltip", "FishSwapFuScanner", nil, "GameTooltipTemplate")
    scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

    -- Register database for saved weapons
    self:RegisterDB("FishSwapFuDB", "FishSwapFuDBChr")
    self:RegisterDefaults("char", {
        mh = nil,
        oh = nil,
    })

    -- Register slash command
    self:RegisterChatCommand({ "/fishswapfu", "/fsf" }, {
        type = "execute",
        func = "ToggleFishingGear",
        desc = "Toggles between weapons and fishing pole."
    })
end

function FishSwapFu:OnEnable()
    -- Update text when inventory changes (e.g., after a swap)
    self:RegisterEvent("UNIT_INVENTORY_CHANGED", "Update")
    self:Update()
end

-----------------------------------------------------------------------
-- FuBar Plugin Methods
-----------------------------------------------------------------------

function FishSwapFu:OnClick(button)
    if button == "LeftButton" then
        self:ToggleFishingGear()
    end
end

function FishSwapFu:OnTextUpdate()
    if self:IsFishingPoleEquipped() then
        self:SetText("Pole")
    else
        self:SetText("Weapons")
    end
end

function FishSwapFu:OnTooltipUpdate()
    -- FuBarPlugin handles the title. Create a single category for content.
    local cat = tablet:AddCategory(
        'columns', 2
    )

    -- Add all lines to the single category object.
    local savedMH = self.db.char.mh
    local savedOH = self.db.char.oh

    cat:AddLine('text', "Saved MH:", 'text2', savedMH or "None")
    cat:AddLine('text', "Saved OH:", 'text2', savedOH or "None")

    -- Add a blank line to the category to create a separator.
    cat:AddLine()

    cat:AddLine('text', "Action:", 'text2', "Left-click to swap.")
    cat:AddLine('text', "Menu:", 'text2', "Right-click for options.")

    -- Use SetHint for the final line, as per the provided example.
    tablet:SetHint("Toggles between your weapon set and your fishing pole.")
end

function FishSwapFu:OnMenuRequest()
    dewdrop:AddLine(
        'text', "Clear Saved Weapons",
        'tooltipText', "Clears your saved Main Hand and Off-Hand weapon data.",
        'func', function() self:ClearSavedWeapons() end,
        'closeWhenClicked', true
    )
end

-----------------------------------------------------------------------
-- Core Logic (Ported from original addon)
-----------------------------------------------------------------------

-- Helper: Parse Item Name from Link
function FishSwapFu:GetItemNameFromLink(link)
    if not link then return nil end
    return string.gsub(link, "|c%x+|Hitem:%d+:%d+:%d+:%d+|h%[(.-)%]|h|r", "%1")
end

-- Helper: Parse Item ID from Link
function FishSwapFu:GetItemIDFromLink(link)
    if not link then return nil end
    local _, _, id = string.find(link, "item:(%d+)")
    return tonumber(id)
end

-- Helper: Find item location in bags
function FishSwapFu:FindItemInBags(itemName)
    if not itemName then return nil, nil end
    for bag = 0, 4 do
        if GetContainerNumSlots(bag) > 0 then
            for slot = 1, GetContainerNumSlots(bag) do
                local link = GetContainerItemLink(bag, slot)
                if link and self:GetItemNameFromLink(link) == itemName then
                    return bag, slot
                end
            end
        end
    end
    return nil, nil
end

-- Helper: Count total free bag slots (IGNORING SPECIALTY BAGS)
function FishSwapFu:GetTotalFreeBagSlots()
    local free = 0
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        local isGeneralBag = true

        if bag > 0 and numSlots > 0 then
            local invID = ContainerIDToInventoryID(bag)
            scanTooltip:ClearLines()
            if scanTooltip:SetInventoryItem("player", invID) then
                for i = 1, 4 do
                    local left = _G["FishSwapFuScannerTextLeft" .. i]
                    local fullText = left and left:GetText() or ""
                    if string.find(fullText, "Quiver") or string.find(fullText, "Ammo Pouch") or
                       string.find(fullText, "Soul Bag") or string.find(fullText, "Herb Bag") or
                       string.find(fullText, "Enchanting Bag") or string.find(fullText, "Engineering Bag") or
                       string.find(fullText, "Mining Sack") then
                        isGeneralBag = false
                        break
                    end
                end
            end
        end

        if isGeneralBag and numSlots > 0 then
            for slot = 1, numSlots do
                if not GetContainerItemInfo(bag, slot) then
                    free = free + 1
                end
            end
        end
    end
    return free
end

-- Helper: Analyse an item to see if it is a Fishing Pole
function FishSwapFu:AnalyseItem(link)
    local id = self:GetItemIDFromLink(link)
    if id and KNOWN_POLES[id] then
        return true, KNOWN_POLES[id]
    end
    return false, 0
end

-- Helper: Is a fishing pole equipped?
function FishSwapFu:IsFishingPoleEquipped()
    local link = GetInventoryItemLink("player", 16) -- Main Hand slot
    if not link then return false end
    local id = self:GetItemIDFromLink(link)
    return id and KNOWN_POLES[id]
end

-- ACTION: Swap TO Weapons
function FishSwapFu:SwapToWeapons()
    local mhName = self.db.char.mh
    local ohName = self.db.char.oh

    if not mhName and not ohName then
        self:Print("No saved weapons found. Equip your weapons to initialize.")
        return
    end

    -- Equip Main Hand
    if mhName then
        local bag, slot = self:FindItemInBags(mhName)
        if bag and slot then
            self:Print("Equipping Main Hand: " .. mhName)
            PickupContainerItem(bag, slot)
            EquipCursorItem(16)
        else
            self:Print("Could not find Main Hand: " .. mhName)
        end
    end

    -- Equip Off Hand
    if ohName then
        local bagOH, slotOH = self:FindItemInBags(ohName)
        if bagOH and slotOH then
            self:Print("Equipping Off Hand: " .. ohName)
            PickupContainerItem(bagOH, slotOH)
            EquipCursorItem(17)
        else
            self:Print("Could not find Off Hand: " .. ohName)
        end
    end
end

-- ACTION: Swap TO Pole
function FishSwapFu:SwapToPole()
    local hasMH = GetInventoryItemLink("player", 16)
    local hasOH = GetInventoryItemLink("player", 17)
    local freeSlots = self:GetTotalFreeBagSlots()

    if hasMH and hasOH and freeSlots < 1 then
        self:Print("Swap aborted. Not enough free bag space for Off-Hand.")
        return
    end

    -- Save current gear
    self.db.char.mh = self:GetItemNameFromLink(hasMH)
    self.db.char.oh = self:GetItemNameFromLink(hasOH)
    self:Print("Weapons saved.")

    -- Find the BEST Fishing Pole
    local bestBag, bestSlot, bestBonus = nil, nil, -1
    for bag = 0, 4 do
        if GetContainerNumSlots(bag) > 0 then
            for slot = 1, GetContainerNumSlots(bag) do
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local isPole, bonus = self:AnalyseItem(link)
                    if isPole and bonus > bestBonus then
                        bestBonus, bestBag, bestSlot = bonus, bag, slot
                    end
                end
            end
        end
    end

    if bestBag and bestSlot then
        local poleName = self:GetItemNameFromLink(GetContainerItemLink(bestBag, bestSlot))
        self:Print("Equipping " .. poleName .. "...")
        PickupContainerItem(bestBag, bestSlot)
        EquipCursorItem(16)
    else
        self:Print("No Fishing Pole found in bags!")
    end
end

-- Core Logic: Decision Maker
function FishSwapFu:ToggleFishingGear()
    if CursorHasItem() then ClearCursor() end

    if self:IsFishingPoleEquipped() then
        self:SwapToWeapons()
    else
        self:SwapToPole()
    end
end

-- Menu Action: Clear saved data
function FishSwapFu:ClearSavedWeapons()
    self.db.char.mh = nil
    self.db.char.oh = nil
    self:Print("Saved weapon data has been cleared.")
    self:Update()
end
