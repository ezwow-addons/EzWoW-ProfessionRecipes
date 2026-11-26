--===========================================================================
-- EzWoW - Profession Recipes
-- Modules/RecipeStatus.lua : Recipe Item Tooltip Status & Known Recipes per Character
--===========================================================================
-- Recipe item tooltips (GameTooltip and ItemRefTooltip only) get one status line:
-- learned / can learn (skill N) / skill too low, plus which of your other characters
-- already know the recipe. Learned recipes are saved per character whenever a
-- profession window of your own is read.
local ADDON, ns = ...
-- every EzWoW line on the game's tooltips can be turned off at once (Game Menu >
-- Options > AddOns > EzWoW - Data Sharing; Libs/EzWoWShare TooltipLinesOn)
local function ezTipsOn()
    local share = _G.EzWoW_Share
    if type(share) ~= "table" or type(share.TooltipLinesOn) ~= "function" then return true end
    local ok, on = pcall(share.TooltipLinesOn)
    return not ok or on ~= false
end
local type, pairs, ipairs, tonumber, tostring, pcall = type, pairs, ipairs, tonumber, tostring, pcall

local RecipeStatus = ns.RecipeStatus or {}
ns.RecipeStatus = RecipeStatus
local L = ns.L
local R_SPELL, R_ORANGE, R_NAME_KO, R_NAME_EN = ns.R_SPELL, ns.R_ORANGE, ns.R_NAME_KO, ns.R_NAME_EN

local RECIPE_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Recipe) or 9
-- recipe item subclass -> profession skill line
local SUBCLASS_SKILL = { [1] = 165, [2] = 197, [3] = 202, [4] = 164, [5] = 185, [6] = 171, [7] = 129, [8] = 333, [9] = 356 }

local function isSecret(v) return issecretvalue and issecretvalue(v) or false end

-----------------------------------------------------------------------------
-- Saved data: ns.DB.known[charKey] = { class, realm, name, profs = { [skillLine] = { rank, spells = { [spellID] = true } } } }
-----------------------------------------------------------------------------
-- The server's name. GetRealmName() has come back empty on this server since the
-- evening of 2026-11-21, which gave this character a second, empty record ("Name-")
-- and put the server's name after every character in the tooltip. The name last
-- seen for this server (the number in the player GUID), the one EzWoW - Bags keeps
-- for this character, or the one on this character's own record is used then.
local function plainText(value)
    if type(value) ~= "string" or value == "" or isSecret(value) then return nil end
    return value
end
local function serverOf(guid)
    if type(guid) ~= "string" or isSecret(guid) then return nil end
    return guid:match("^Player%-(%d+)%-")
end
local realmName
function RecipeStatus.realmName()
    local live = plainText(GetRealmName and GetRealmName())
    local guid = UnitGUID and UnitGUID("player")
    local id = serverOf(guid)
    if live then
        if id and ns.DB then
            ns.DB.realmNames = type(ns.DB.realmNames) == "table" and ns.DB.realmNames or {}
            ns.DB.realmNames[id] = live
        end
        return live
    end
    if realmName then return realmName end
    local found
    if id and ns.DB and type(ns.DB.realmNames) == "table" then found = plainText(ns.DB.realmNames[id]) end
    local bags = type(EzWoW_BagsDB) == "table" and EzWoW_BagsDB or nil
    if not found and id and bags and type(bags.realmNames) == "table" then found = plainText(bags.realmNames[id]) end
    if not found and bags and type(bags.characters) == "table" and guid then
        for _, char in pairs(bags.characters) do
            if type(char) == "table" and char.guid == guid and plainText(char.realm) then found = char.realm; break end
        end
    end
    if not found and ns.DB and type(ns.DB.known) == "table" then
        local name = UnitName and UnitName("player")
        for _, rec in pairs(ns.DB.known) do
            if type(rec) == "table" and plainText(rec.realm) and ((guid and rec.guid == guid) or (not rec.guid and rec.name == name)) then
                found = rec.realm; break
            end
        end
    end
    found = found or plainText(GetNormalizedRealmName and GetNormalizedRealmName())
    if found then realmName = found end
    return found or ""
end

local playerKey
function RecipeStatus.playerKey()
    if playerKey then return playerKey end
    local name = UnitName and UnitName("player")
    if type(name) ~= "string" or name == "" or isSecret(name) then return nil end
    local realm = RecipeStatus.realmName()
    playerKey = name .. "-" .. realm
    -- what was saved under the empty server name goes back to this record
    local db = RecipeStatus.knownDB()
    local empty = name .. "-"
    if db and realm ~= "" and type(db[empty]) == "table" then
        RecipeStatus.mergeRecord(db, empty, playerKey)
    end
    return playerKey
end

-- Joins the record under `fromKey` into the one under `toKey`: every known recipe,
-- the higher skill, the later check.
function RecipeStatus.mergeRecord(db, fromKey, toKey)
    local from = db[fromKey]
    if type(from) ~= "table" or fromKey == toKey then return end
    local to = db[toKey]
    if type(to) ~= "table" then
        db[toKey], db[fromKey] = from, nil
        from.realm = nil
        return
    end
    for field, value in pairs(from) do
        if field ~= "profs" and field ~= "realm" and to[field] == nil then to[field] = value end
    end
    to.profs = type(to.profs) == "table" and to.profs or {}
    for skillLine, prof in pairs(type(from.profs) == "table" and from.profs or {}) do
        local mine = to.profs[skillLine]
        if type(mine) ~= "table" then
            to.profs[skillLine] = prof
        elseif type(prof) == "table" then
            mine.spells = type(mine.spells) == "table" and mine.spells or {}
            for spellID, known in pairs(type(prof.spells) == "table" and prof.spells or {}) do
                if known then mine.spells[spellID] = known end
            end
            if (tonumber(prof.rank) or 0) > (tonumber(mine.rank) or 0) then mine.rank = prof.rank end
            if (tonumber(prof.time) or 0) > (tonumber(mine.time) or 0) then mine.time = prof.time end
        end
    end
    db[fromKey] = nil
end

function RecipeStatus.knownDB()
    if not ns.DB then return nil end
    if type(ns.DB.known) ~= "table" then ns.DB.known = {} end
    return ns.DB.known
end

function RecipeStatus.myRecord()
    local db, key = RecipeStatus.knownDB(), RecipeStatus.playerKey()
    if not db or not key then return nil end
    local rec = db[key]
    if type(rec) ~= "table" then rec = {}; db[key] = rec end
    rec.name = UnitName and UnitName("player") or rec.name
    rec.realm = plainText(RecipeStatus.realmName()) or rec.realm
    local guid = UnitGUID and UnitGUID("player")
    if type(guid) == "string" and not isSecret(guid) then rec.guid = guid end
    -- second UnitName value is the surname on this client (shown, never part of the key)
    if UnitName then
        local _, surname = UnitName("player")
        if type(surname) == "string" and surname ~= "" and not isSecret(surname) and surname ~= rec.realm then
            rec.surname = surname
        end
    end
    if UnitClass then local _, class = UnitClass("player"); rec.class = class or rec.class end
    if type(rec.profs) ~= "table" then rec.profs = {} end
    return rec
end

-- Current skill per profession (GetProfessions covers the trade skills on this client).
function RecipeStatus.currentRanks()
    local ranks = {}
    if GetProfessions and GetProfessionInfo then
        local okList, p1, p2, arch, fish, cook, aid = pcall(GetProfessions)
        if okList then
            for _, index in pairs({ p1, p2, arch, fish, cook, aid }) do
                local ok, _, _, rank, _, _, _, skillLine = pcall(GetProfessionInfo, index)
                if ok and type(skillLine) == "number" and type(rank) == "number" then ranks[skillLine] = rank end
            end
        end
    end
    if C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetSkillLineInfo then
        local okCount, count = pcall(C_SkillInfo.GetNumSkillLines)
        if okCount and type(count) == "number" then
            for i = 1, count do
                local ok, info = pcall(C_SkillInfo.GetSkillLineInfo, i)
                if ok and type(info) == "table" and info.skillID and info.rank and ns.Data[info.skillID] then
                    ranks[info.skillID] = ranks[info.skillID] or info.rank
                end
            end
        end
    end
    return ranks
end

function RecipeStatus.saveRanks()
    local rec = RecipeStatus.myRecord()
    if not rec then return end
    local ranks = RecipeStatus.currentRanks()
    for skillLine, rank in pairs(ranks) do
        local prof = rec.profs[skillLine]
        if type(prof) ~= "table" then prof = { spells = {} }; rec.profs[skillLine] = prof end
        prof.rank = rank
    end
    -- a profession that was dropped is removed (only when the list could be read)
    if next(ranks) ~= nil then
        for skillLine in pairs(rec.profs) do
            if ranks[skillLine] == nil then rec.profs[skillLine] = nil end
        end
    end
end

-- Called with the learned recipe spell IDs of the profession window that is open.
function RecipeStatus.saveLearned(skillLine, learned, rank)
    if type(skillLine) ~= "number" or type(learned) ~= "table" then return end
    local rec = RecipeStatus.myRecord()
    if not rec then return end
    local spells = {}
    for spellID, isKnown in pairs(learned) do
        if isKnown and type(spellID) == "number" then spells[spellID] = true end
    end
    if next(spells) == nil then return end
    local prof = rec.profs[skillLine]
    if type(prof) ~= "table" then prof = {}; rec.profs[skillLine] = prof end
    prof.spells = spells
    if type(rank) == "number" then prof.rank = rank end
    prof.time = time and time() or nil
end

-- Reads the open profession window (never another player's or a linked one).
function RecipeStatus.readOpenProfession()
    if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo) then return end
    for _, check in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsNPCCrafting", "IsRuneforging" }) do
        local fn = C_TradeSkillUI[check]
        if type(fn) == "function" then
            local ok, result = pcall(fn)
            if ok and result then return end
        end
    end
    local browser = ns.RecipeBrowserWindow
    if not (browser and browser.resolveCurrentTradeSkillLine) then return end
    local skillLine, rank = browser.resolveCurrentTradeSkillLine()
    if not skillLine then return end
    local okIDs, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
    if not okIDs or type(ids) ~= "table" then return end
    local learned = {}
    for _, recipeID in ipairs(ids) do
        local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if ok and type(info) == "table" and info.learned then learned[recipeID] = true end
    end
    RecipeStatus.saveLearned(skillLine, learned, rank)
end

-----------------------------------------------------------------------------
-- Recipe item -> recipe row (by localized name, cached per item)
-----------------------------------------------------------------------------
local nameMaps = {}
local itemCache = {}
-- the cached rows belong to the old recipe table once the shared data (EzWoW-Data) is used
if ns.RecipeCatalogIndex and ns.RecipeCatalogIndex.onDataChanged then
    ns.RecipeCatalogIndex.onDataChanged(function() wipe(nameMaps); wipe(itemCache) end)
end

local function normalize(text)
    if type(text) ~= "string" or text == "" then return nil end
    return (text:lower():gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

function RecipeStatus.nameMap(skillLine)
    local map = nameMaps[skillLine]
    if map then return map end
    map = {}
    local data = ns.Data[skillLine]
    for _, r in ipairs(data and data.recipes or {}) do
        local spellName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(r[R_SPELL])
        for _, text in ipairs({ spellName, r[R_NAME_KO], r[R_NAME_EN] }) do
            local key = normalize(text)
            if key and map[key] == nil then map[key] = r end
        end
    end
    nameMaps[skillLine] = map
    return map
end

function RecipeStatus.findRecipe(itemID, itemName)
    local cached = itemCache[itemID]
    if cached ~= nil then return cached or nil end
    if type(itemName) ~= "string" or itemName == "" then return nil end
    local okInfo, _, _, _, _, _, classID, subClassID = pcall(C_Item.GetItemInfoInstant, itemID)
    if not okInfo or classID ~= RECIPE_CLASS then itemCache[itemID] = false; return nil end
    -- (byte patterns: the full-width colon is looked for on its own)
    local bare = itemName:match("^[^:]+:%s*(.+)$") or itemName:match("：%s*(.+)$") or itemName
    local candidates = {}
    local skillLine = SUBCLASS_SKILL[subClassID]
    if skillLine and ns.Data[skillLine] then candidates[1] = skillLine
    else for line in pairs(ns.Data) do candidates[#candidates + 1] = line end end
    for _, line in ipairs(candidates) do
        local map = RecipeStatus.nameMap(line)
        local r = map[normalize(bare)] or map[normalize(itemName)]
        if r then
            local found = { row = r, skillLine = line }
            itemCache[itemID] = found
            return found
        end
    end
    itemCache[itemID] = false
    return nil
end

-----------------------------------------------------------------------------
-- Tooltip
-----------------------------------------------------------------------------
local CLASS_COLORS = _G.RAID_CLASS_COLORS

local function charLabel(rec, key)
    local label = rec.name or key
    if rec.name and type(rec.surname) == "string" and rec.surname ~= "" then
        local consts = Constants and Constants.CharacterNameSeparatorConsts
        local sep = consts and consts.CHARACTERNAME_SURNAME_SEPARATOR
        label = rec.name .. ((type(sep) == "string" and sep ~= "" and not isSecret(sep)) and sep or " ") .. rec.surname
    end
    if plainText(rec.realm) and rec.realm ~= RecipeStatus.realmName() then label = label .. "-" .. rec.realm end
    local color = CLASS_COLORS and rec.class and CLASS_COLORS[rec.class]
    if color and color.colorStr then return "|c" .. color.colorStr .. label .. "|r" end
    return label
end

function RecipeStatus.addLines(tooltip, itemID, itemName)
    local found = RecipeStatus.findRecipe(itemID, itemName)
    if not found then return end
    local r, skillLine = found.row, found.skillLine
    local spellID, need = r[R_SPELL], r[R_ORANGE] or 0
    local mine = RecipeStatus.myRecord()
    local myProf = mine and mine.profs[skillLine]
    local known = myProf and type(myProf.spells) == "table" and myProf.spells[spellID]
    if not known and IsPlayerSpell then
        local ok, result = pcall(IsPlayerSpell, spellID)
        known = ok and result and true or false
    end
    if known then
        tooltip:AddLine(L.recipeLearned, 0.25, 0.85, 0.35)
    else
        local rank = RecipeStatus.currentRanks()[skillLine]
        if rank == nil then
            local prof = ns.PROF_BY_ID and ns.PROF_BY_ID[skillLine]
            local profName = prof and ns.GetLocalizedProfessionName(prof) or "?"
            tooltip:AddLine(L.recipeNoProf:format(profName, need), 0.65, 0.65, 0.65)
        elseif rank >= need then
            tooltip:AddLine(L.recipeCanLearn:format(need), 1, 0.82, 0)
        else
            tooltip:AddLine(L.recipeLowSkill:format(need, rank), 1, 0.3, 0.3)
        end
    end
    local db, me = RecipeStatus.knownDB(), RecipeStatus.playerKey()
    local names = {}
    for key, rec in pairs(db or {}) do
        if key ~= me and type(rec) == "table" and type(rec.profs) == "table" then
            local prof = rec.profs[skillLine]
            if type(prof) == "table" and type(prof.spells) == "table" and prof.spells[spellID] then
                names[#names + 1] = charLabel(rec, key)
            end
        end
    end
    if #names > 0 then
        table.sort(names)
        tooltip:AddLine(L.recipeKnownBy:format(table.concat(names, ", ")), 0.65, 0.73, 0.78, true)
    end
    if ns.NoteTooltipLines then ns.NoteTooltipLines(tooltip) end
end

local function tooltipItem(tooltip, data)
    local itemID = data and data.id
    local link = data and data.hyperlink
    if type(itemID) ~= "number" or isSecret(itemID) then
        itemID = nil
        if TooltipUtil and TooltipUtil.GetDisplayedItem then
            local ok, _, shownLink, shownID = pcall(TooltipUtil.GetDisplayedItem, tooltip)
            if ok then itemID, link = shownID, shownLink end
        end
        if type(itemID) ~= "number" and type(link) == "string" and not isSecret(link) then
            itemID = tonumber(link:match("item:(%d+)"))
        end
    end
    if type(itemID) ~= "number" then return nil end
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
    if (type(name) ~= "string" or isSecret(name)) and type(link) == "string" and not isSecret(link) then
        name = link:match("|h%[(.-)%]|h")
    end
    if type(name) ~= "string" or isSecret(name) then return nil end
    return itemID, name
end

-- EzWoW-Tooltip asks this before adding its own learned/not-learned mark on a recipe item,
-- so only this (more detailed) status line shows.
function ns.CoversRecipeStatus(tooltip, itemID)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return false end
    if type(itemID) ~= "number" or isSecret(itemID) then return false end
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
    if type(name) ~= "string" or isSecret(name) then return false end
    local ok, found = pcall(RecipeStatus.findRecipe, itemID, name)
    return ok and found ~= nil
end

-- item already handled per tooltip; kept in our own table (fields written on the
-- game's tooltip frames would taint them)
local shownItem = setmetatable({}, { __mode = "k" })

function RecipeStatus.onItemTooltip(tooltip, data)
    if not ezTipsOn() then return end
    pcall(function()
        if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
        if tooltip.IsForbidden and tooltip:IsForbidden() then return end
        local itemID, name = tooltipItem(tooltip, data)
        if not itemID or shownItem[tooltip] == itemID then return end
        shownItem[tooltip] = itemID
        RecipeStatus.addLines(tooltip, itemID, name)
        -- what the item costs to make (Modules/Leveling.lua)
        local craft = ns.Leveling and ns.Leveling.CraftCost
        if craft and craft.AddLine then craft.AddLine(tooltip, itemID) end
    end)
    -- last item hook of this addon: one attribution line under everything it added
    if (tooltip == GameTooltip or tooltip == ItemRefTooltip) and ns.FlushTooltipTag then
        pcall(ns.FlushTooltipTag, tooltip)
    end
end

local function clearMark(tooltip) shownItem[tooltip] = nil end
for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
    if tooltip and tooltip.HookScript then pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", clearMark) end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, RecipeStatus.onItemTooltip)
elseif GameTooltip and GameTooltip.HookScript then
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", function(tt) RecipeStatus.onItemTooltip(tt, nil) end)
    if ItemRefTooltip and ItemRefTooltip.HookScript then
        pcall(ItemRefTooltip.HookScript, ItemRefTooltip, "OnTooltipSetItem", function(tt) RecipeStatus.onItemTooltip(tt, nil) end)
    end
end

-----------------------------------------------------------------------------
-- Events
-----------------------------------------------------------------------------
local readPending = false
local function scheduleRead()
    if readPending or not (C_Timer and C_Timer.After) then return end
    readPending = true
    C_Timer.After(1, function()
        readPending = false
        pcall(RecipeStatus.readOpenProfession)
    end)
end

local eventFrame = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "SKILL_LINES_CHANGED", "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "NEW_RECIPE_LEARNED" }) do
    pcall(eventFrame.RegisterEvent, eventFrame, event)
end
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" or event == "SKILL_LINES_CHANGED" then
        pcall(RecipeStatus.saveRanks)
    else
        scheduleRead()
    end
end)

ns.SaveLearnedRecipes = RecipeStatus.saveLearned
