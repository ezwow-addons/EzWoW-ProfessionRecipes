--===========================================================================
-- EzWoW - Profession Recipes
-- Modules/Leveling.lua : Skill-Up Planner, Auction & Vendor Prices
--===========================================================================
-- Plans the cheapest way from the current skill to a target skill. For every skill
-- point the recipe with the lowest expected cost per point wins (reagent cost divided
-- by the chance of a skill-up at that skill); runs of the same recipe become one step.
-- One shopping list covers the whole plan, less what the bags and the bank hold.
-- A reagent costs the lower of its auction price and its vendor price; an item the
-- same profession makes (bolts of cloth) is made instead when that is cheaper.
-- Auction prices: EzWoW - Tooltip's shared scan, EzWoW - Bags' market, or this
-- addon's own scan (only when neither of the two is installed); the newest wins.
local ADDON, ns = ...
local type, pairs, ipairs, tonumber, tostring, pcall = type, pairs, ipairs, tonumber, tostring, pcall
local floor, ceil, max, min, abs, huge = math.floor, math.ceil, math.max, math.min, math.abs, math.huge

local Leveling = ns.Leveling or {}
ns.Leveling = Leveling
local Prices = Leveling.Prices or {}
Leveling.Prices = Prices

local R_SPELL, R_ITEM = ns.R_SPELL or 1, ns.R_ITEM or 2
local R_ORANGE, R_YELLOW, R_GREEN, R_GREY = ns.R_ORANGE or 4, ns.R_YELLOW or 5, ns.R_GREEN or 6, ns.R_GREY or 7
local R_FLAGS, R_QTY, R_REAG = ns.R_FLAGS or 8, ns.R_QTY or 9, ns.R_REAG or 13
local F_TRAINER = ns.F_TRAINER or 2

Leveling.MAX_SKILL = 300
Leveling.TIERS = { 75, 150, 225 }          -- skill caps of apprentice, journeyman and expert training
-- professions raised by gathering (no plan; mining also rises with smelting)
Leveling.GATHERING = { [182] = true, [393] = true, [356] = true }
Leveling.MINING = 186
-- a reagent without any price still lets a step be planned (and is marked): 10 gold a unit
local UNKNOWN_UNIT = 100000
-- the recipe of the current step goes on while no other one is more than 5% cheaper
-- (near-equal recipes would otherwise take turns every few points)
local KEEP_MARGIN = 1.05

local function hasFlag(value, flag)
    value = tonumber(value) or 0
    return value % (flag + flag) >= flag
end

-----------------------------------------------------------------------------
-- Skill-up chance
-----------------------------------------------------------------------------
-- orange, yellow, green and grey skill of a recipe, kept in order (a few rows have gaps)
function Leveling.Thresholds(r)
    local o = tonumber(r[R_ORANGE]) or 0
    local y = tonumber(r[R_YELLOW]) or 0
    if y < o then y = o end
    local g = tonumber(r[R_GREEN]) or 0
    if g < y then g = y end
    local gr = tonumber(r[R_GREY]) or 0
    if gr < g then gr = g end
    return o, y, g, gr
end

-- chance of a skill point for one craft at skill s: certain while orange, then
-- falling from yellow to grey ((grey - skill) / (grey - yellow)), none when grey
function Leveling.Chance(r, s)
    local o, y, _, gr = Leveling.Thresholds(r)
    if s < o or s >= gr then return 0 end
    if s < y then return 1 end
    return (gr - s) / (gr - y)
end

function Leveling.Color(r, s)
    local o, y, g, gr = Leveling.Thresholds(r)
    if s < o then return "red" end
    if s < y then return "orange" end
    if s < g then return "yellow" end
    if s < gr then return "green" end
    return "grey"
end

-----------------------------------------------------------------------------
-- Planner (no game API: everything comes in through opts)
--   opts.from, opts.to   current and target skill
--   opts.maxRank         skill cap of the training the character has (nil: not learned)
--   opts.usable(r)       "learned" | "trainer" | "other" (a recipe to obtain: vendor / drop) | nil;
--                        "other" ones are only used where nothing learned or taught gives skill
--   opts.price(item)     unit price in copper and its source ("ah" | "vendor"), or nil
--   opts.owned(item)     count in the bags and the bank
-- returns { steps, make, buy, total, unknown, byAuction, byVendor, saved, totalCrafts }
--   steps: { recipe, kind, from, to, expected, crafts, chance, cost, unknown, color,
--            segments = { { color, from, to } } (where it turns yellow / green), reuse }
--          or { train = true, at } (train the next rank there) or { gap = true, from, to }
--   make:  { item, need, have, crafts, recipe, kind, steps } items made instead of bought
--   buy:   { item, need, have, buy, unit, source, cost, steps } (steps: the steps that use it)
-----------------------------------------------------------------------------
function Leveling.BuildPlan(recipes, opts)
    local from = floor(tonumber(opts.from) or 1)
    local to = floor(tonumber(opts.to) or 0)
    local usableKind = opts.usable or function() return nil end
    local priceOf = opts.price or function() return nil end
    local ownedOf = opts.owned or function() return 0 end
    local plan = { from = from, to = to, steps = {}, make = {}, buy = {}, total = 0, unknown = {},
                   byAuction = 0, byVendor = 0, saved = 0, totalCrafts = 0 }
    if to <= from then return plan end

    -- recipes the plan may use, and the one that makes each item (lowest skill)
    local candidates, producers = {}, {}
    for _, r in ipairs(recipes or {}) do
        local kind = usableKind(r)
        if kind then
            candidates[#candidates + 1] = { r = r, kind = kind }
            local item = tonumber(r[R_ITEM]) or 0
            -- intermediates are only made with recipes the character has or a trainer teaches
            if item > 0 and kind ~= "other" then
                local old = producers[item]
                if not old or (tonumber(r[R_ORANGE]) or 0) < (tonumber(old.r[R_ORANGE]) or 0) then
                    producers[item] = { r = r, kind = kind }
                end
            end
        end
    end

    local buyMemo = {}
    local function buyUnit(item)
        local m = buyMemo[item]
        if m == nil then
            local u, src = priceOf(item)
            u = tonumber(u)
            m = { u = (u and u > 0) and u or nil, src = src }
            buyMemo[item] = m
        end
        return m.u, m.src
    end
    -- one item made by this profession, its own reagents bought (false: a price is missing)
    local makeMemo = {}
    local function makeUnit(item)
        local m = makeMemo[item]
        if m == nil then
            m = false
            local p = producers[item]
            if p then
                local sum = 0
                for _, re in ipairs(p.r[R_REAG] or {}) do
                    local u = buyUnit(re[1])
                    if not u then sum = nil break end
                    sum = sum + u * re[2]
                end
                if sum then m = { u = sum / max(1, tonumber(p.r[R_QTY]) or 1), p = p } end
            end
            makeMemo[item] = m
        end
        return m or nil
    end
    -- cheapest way to one item at skill s: buy it, or make it once the skill allows
    local function unitCost(item, s)
        local u, src = buyUnit(item)
        local mk = makeUnit(item)
        if mk and s >= (tonumber(mk.p.r[R_ORANGE]) or 0) and (not u or mk.u < u) then return mk.u, "make", mk end
        return u, src
    end
    local function recipeCost(r, s)
        local sum, unknown = 0, false
        for _, re in ipairs(r[R_REAG] or {}) do
            local u = unitCost(re[1], s)
            if not u then u, unknown = UNKNOWN_UNIT, true end
            sum = sum + u * re[2]
        end
        return sum, unknown
    end

    -- the next training rank is due at these skills
    local trainAt = {}
    for _, t in ipairs(Leveling.TIERS) do
        if t >= from and t < to and (not opts.maxRank or t >= opts.maxRank) then trainAt[t] = true end
    end

    local steps, cur = plan.steps, nil
    for s = from, to - 1 do
        if trainAt[s] then
            steps[#steps + 1] = { train = true, at = s }
            cur = nil
        end
        local best, bestPer, bestP, bestUnknown, bestKind
        local keep
        -- first the recipes learned or taught; recipes to obtain only where those give nothing
        local pass = 1
        while pass <= 2 do
        for _, c in ipairs(candidates) do
            local p = (c.kind == "other") == (pass == 2) and Leveling.Chance(c.r, s) or 0
            if p > 0 then
                local cost, unknown = recipeCost(c.r, s)
                local per = cost / p
                if cur and cur.recipe == c.r then keep = { per = per, p = p, unknown = unknown, kind = c.kind } end
                local better = not best or per < bestPer - 0.001
                if not better and abs(per - bestPer) <= 0.001 then
                    -- a tie: a recipe already learned, then the surer one
                    if c.kind == "learned" and bestKind ~= "learned" then
                        better = true
                    elseif c.kind == bestKind and p > bestP then
                        better = true
                    end
                end
                if better then best, bestPer, bestP, bestUnknown, bestKind = c.r, per, p, unknown, c.kind end
            end
        end
        if best then break end
        pass = pass + 1
        end
        if keep and best ~= cur.recipe and keep.per <= bestPer * KEEP_MARGIN then
            best, bestPer, bestP, bestUnknown, bestKind = cur.recipe, keep.per, keep.p, keep.unknown, keep.kind
        end
        if not best then
            if cur and cur.gap then
                cur.to = s + 1
            else
                cur = { gap = true, from = s, to = s + 1 }
                steps[#steps + 1] = cur
            end
        elseif cur and cur.recipe == best then
            cur.to = s + 1
            cur.expected = cur.expected + 1 / bestP
            cur.cost = cur.cost + bestPer
            cur.unknown = cur.unknown or bestUnknown
            cur.lastChance = bestP
            local color = Leveling.Color(best, s)
            local seg = cur.segments[#cur.segments]
            if seg.color ~= color then cur.segments[#cur.segments + 1] = { color = color, from = s } end
        else
            local color = Leveling.Color(best, s)
            cur = { recipe = best, kind = bestKind, from = s, to = s + 1, expected = 1 / bestP, chance = bestP,
                    lastChance = bestP, cost = bestPer, unknown = bestUnknown, color = color,
                    segments = { { color = color, from = s } } }
            steps[#steps + 1] = cur
        end
    end
    for _, st in ipairs(steps) do
        for i, seg in ipairs(st.segments or {}) do
            local nextSeg = st.segments[i + 1]
            seg.to = nextSeg and nextSeg.from or st.to
        end
    end

    -- reagents of every step, in order: what an earlier step made (bolts of cloth) is
    -- used first; an item is made (not bought) where that was the cheaper way
    local need, makeNeed, makeBy = {}, {}, {}
    local needOrder, makeOrder = {}, {}
    local produced, usedBy = {}, {}
    local function add(map, order, item, qty)
        if not map[item] then order[#order + 1] = item end
        map[item] = (map[item] or 0) + qty
    end
    local function use(item, st)
        local list = usedBy[item]
        if not list then list = {} usedBy[item] = list end
        if list[#list] ~= st then list[#list + 1] = st end
    end
    for _, st in ipairs(steps) do
        if st.recipe then
            st.crafts = max(1, ceil(st.expected - 1e-6))
            plan.totalCrafts = plan.totalCrafts + st.crafts
            for _, re in ipairs(st.recipe[R_REAG] or {}) do
                local item, qty = re[1], re[2] * st.crafts
                use(item, st)
                local reuse = min(produced[item] or 0, qty)
                if reuse > 0 then
                    produced[item] = produced[item] - reuse
                    qty = qty - reuse
                    st.reuse = st.reuse or {}
                    st.reuse[item] = (st.reuse[item] or 0) + reuse
                end
                if qty > 0 then
                    local _, how, mk = unitCost(item, st.from)
                    if how == "make" then
                        add(makeNeed, makeOrder, item, qty)
                        makeBy[item] = mk.p
                    else
                        add(need, needOrder, item, qty)
                    end
                end
            end
            local product = tonumber(st.recipe[R_ITEM]) or 0
            if product > 0 then
                produced[product] = (produced[product] or 0) + st.crafts * max(1, tonumber(st.recipe[R_QTY]) or 1)
            end
        end
    end
    -- bags and bank are used first; one count shared by both lists
    local ownedLeft = {}
    local function takeOwned(item, qty)
        if ownedLeft[item] == nil then ownedLeft[item] = max(0, floor(tonumber(ownedOf(item)) or 0)) end
        local used = min(ownedLeft[item], qty)
        ownedLeft[item] = ownedLeft[item] - used
        return used
    end
    for _, item in ipairs(makeOrder) do
        local qty, p = makeNeed[item], makeBy[item]
        local have = takeOwned(item, qty)
        local crafts = ceil((qty - have) / max(1, tonumber(p.r[R_QTY]) or 1))
        local row = { item = item, need = qty, have = have, crafts = crafts, recipe = p.r, kind = p.kind, steps = usedBy[item] }
        plan.make[#plan.make + 1] = row
        plan.totalCrafts = plan.totalCrafts + crafts
        for _, re in ipairs(p.r[R_REAG] or {}) do
            if crafts > 0 then
                add(need, needOrder, re[1], re[2] * crafts)
                usedBy[re[1]] = usedBy[re[1]] or {}
                usedBy[re[1]].made = usedBy[re[1]].made or {}
                usedBy[re[1]].made[#usedBy[re[1]].made + 1] = row
            end
        end
    end
    for _, item in ipairs(needOrder) do
        local qty = need[item]
        local have = takeOwned(item, qty)
        local buy = qty - have
        local u, src = buyUnit(item)
        local row = { item = item, need = qty, have = have, buy = buy, unit = u, source = src, steps = usedBy[item] }
        if u then
            row.cost = buy * u
            plan.total = plan.total + row.cost
            plan.saved = plan.saved + have * u
            if src == "vendor" then plan.byVendor = plan.byVendor + row.cost else plan.byAuction = plan.byAuction + row.cost end
        elseif buy > 0 then
            plan.unknown[#plan.unknown + 1] = item
        end
        plan.buy[#plan.buy + 1] = row
    end
    -- what costs most first; nothing left to buy last
    table.sort(plan.buy, function(a, b)
        if (a.buy > 0) ~= (b.buy > 0) then return a.buy > 0 end
        local ac, bc = a.cost or huge, b.cost or huge
        if ac ~= bc then return ac > bc end
        return a.item < b.item
    end)
    return plan
end

-----------------------------------------------------------------------------
-- Game side: skill, learned recipes, usable recipes, owned counts
-----------------------------------------------------------------------------
-- current skill and the cap of the training the character has (nil: not learned)
function Leveling.SkillOf(skillLine)
    if GetProfessions and GetProfessionInfo then
        local okList, p1, p2, arch, fish, cook, aid = pcall(GetProfessions)
        if okList then
            for _, index in pairs({ p1, p2, arch, fish, cook, aid }) do
                local ok, _, _, rank, maxRank, _, _, line = pcall(GetProfessionInfo, index)
                if ok and line == skillLine and type(rank) == "number" then
                    return rank, type(maxRank) == "number" and maxRank or nil
                end
            end
        end
    end
    local ranks = ns.RecipeStatus and ns.RecipeStatus.currentRanks and ns.RecipeStatus.currentRanks()
    if ranks and type(ranks[skillLine]) == "number" then return ranks[skillLine], nil end
    return nil
end

-- recipes this character knows: saved whenever the profession window was read,
-- and read now when that profession's window is open
function Leveling.LearnedSet(skillLine)
    local set = {}
    local rec = ns.RecipeStatus and ns.RecipeStatus.myRecord and ns.RecipeStatus.myRecord()
    local prof = rec and type(rec.profs) == "table" and rec.profs[skillLine]
    if type(prof) == "table" and type(prof.spells) == "table" then
        for id in pairs(prof.spells) do set[id] = true end
    end
    local browser = ns.RecipeBrowserWindow
    if C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and browser and browser.resolveCurrentTradeSkillLine then
        local openLine = browser.resolveCurrentTradeSkillLine()
        if openLine == skillLine then
            local ok, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
            if ok and type(ids) == "table" then
                for _, id in ipairs(ids) do
                    local ok2, info = pcall(C_TradeSkillUI.GetRecipeInfo, id)
                    if ok2 and type(info) == "table" and info.learned then set[id] = true end
                end
            end
        end
    end
    return set
end

-- includeOther: recipes from vendors / drops fill the skills nothing else covers
function Leveling.UsableFn(learned, includeTrainer, includeOther)
    return function(r)
        if ns.IsOtherFaction and ns.IsOtherFaction(r) then return nil end
        local id = r[R_SPELL]
        if learned[id] then return "learned" end
        if IsPlayerSpell then
            local ok, known = pcall(IsPlayerSpell, id)
            if ok and known then return "learned" end
        end
        local taught = hasFlag(r[R_FLAGS], F_TRAINER)
        if includeTrainer and taught then return "trainer" end
        -- a recipe with no known way to learn it is no step of a plan (UI/RecipeBrowser availability)
        local avail = ns.RecipeAvailability and ns.RecipeAvailability(r)
        if avail then return nil end
        if includeOther and not taught then return "other" end
        return nil
    end
end

function Leveling.Owned(item)
    local fn = ns.QueryItemCountSafe or (C_Item and C_Item.GetItemCount) or GetItemCount
    if not fn then return 0 end
    local ok, n = pcall(fn, item, true)
    return ok and tonumber(n) or 0
end

-- every reagent item of every profession (what the own auction scan keeps)
local reagentSet
function Leveling.ReagentSet()
    if reagentSet then return reagentSet end
    reagentSet = {}
    for _, prof in pairs(ns.Data or {}) do
        for _, r in ipairs(prof.recipes or {}) do
            for _, re in ipairs(r[R_REAG] or {}) do reagentSet[re[1]] = true end
            local item = tonumber(r[R_ITEM]) or 0
            if item > 0 then reagentSet[item] = true end
        end
    end
    return reagentSet
end
if ns.RecipeCatalogIndex and ns.RecipeCatalogIndex.onDataChanged then
    ns.RecipeCatalogIndex.onDataChanged(function() reagentSet = nil end)
end

-----------------------------------------------------------------------------
-- Prices
-----------------------------------------------------------------------------
-- the same market key as EzWoW - Bags (server name, also when the game gives it empty)
local function marketKey()
    local realm = ns.RecipeStatus and ns.RecipeStatus.realmName and ns.RecipeStatus.realmName()
    if type(realm) ~= "string" then realm = GetRealmName and GetRealmName() or "?" end
    local faction = UnitFactionGroup and UnitFactionGroup("player") or "Unknown"
    local key = tostring(realm) .. ":" .. tostring(faction or "Unknown")
    -- prices this addon saved while the server name was empty
    local own = ns.DB and type(ns.DB.ahPrices) == "table" and ns.DB.ahPrices
    local emptyKey = ":" .. tostring(faction or "Unknown")
    if own and realm ~= "" and type(own[emptyKey]) == "table" then
        local old, new = own[key], own[emptyKey]
        if type(old) ~= "table" or (tonumber(new.t) or 0) >= (tonumber(old.t) or 0) then own[key] = new end
        own[emptyKey] = nil
    end
    return key
end

local function addonLoaded(name)
    local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if not loaded then return false end
    local ok, on = pcall(loaded, name)
    return ok and on and true or false
end
function Prices.TooltipScans()
    return addonLoaded("EzWoW-Tooltip") and type(_G.EzWoW_Tooltip) == "table"
        and type(_G.EzWoW_Tooltip.BeginAuctionHousePriceScan) == "function"
end

-- lowest auction unit price, its time and where it came from (newest source wins)
function Prices.Auction(item)
    local best, at, from
    local function offer(u, t, src)
        u, t = tonumber(u), tonumber(t) or 0
        if u and u > 0 and (not best or t > at) then best, at, from = u, t, src end
    end
    local tdb = _G.EzWoW_TooltipDB
    if type(tdb) == "table" and type(tdb.auctionPrices) == "table" then
        local times = type(tdb.auctionTimes) == "table" and tdb.auctionTimes or {}
        offer(tdb.auctionPrices[item] or tdb.auctionPrices[tostring(item)], times[item] or times[tostring(item)], "tooltip")
    end
    local bdb = _G.EzWoW_BagsDB
    local market = type(bdb) == "table" and type(bdb.markets) == "table" and bdb.markets[marketKey()]
    local entry = type(market) == "table" and type(market.items) == "table" and market.items[item]
    if type(entry) == "table" then offer(entry.unit, entry.time, "bags") end
    local own = ns.DB and type(ns.DB.ahPrices) == "table" and ns.DB.ahPrices[marketKey()]
    if type(own) == "table" and type(own.items) == "table" then offer(own.items[item], own.t, "own") end
    return best, at, from
end

function Prices.Vendor(item)
    local v = ns.VendorPrices and ns.VendorPrices[item]
    if v == nil then
        local tip = _G.EzWoW_Tooltip
        v = type(tip) == "table" and type(tip.BuyPriceDB) == "table" and tip.BuyPriceDB[item] or nil
    end
    if type(v) == "table" then return (tonumber(v[1]) or 0) / max(1, tonumber(v[2]) or 1) end
    v = tonumber(v)
    return (v and v > 0) and v or nil
end

-- the planner's price: the lower of auction and vendor
function Prices.Unit(item)
    local ah, vendor = Prices.Auction(item), Prices.Vendor(item)
    if vendor and (not ah or vendor <= ah) then return vendor, "vendor" end
    if ah then return ah, "ah" end
    return nil
end

-- newest scan time and which addon made it (nil: no auction prices yet)
function Prices.Status()
    local at, src = 0, nil
    local tdb = _G.EzWoW_TooltipDB
    if type(tdb) == "table" and tonumber(tdb.auctionLastScan) and tonumber(tdb.auctionLastScan) > at then
        at, src = tonumber(tdb.auctionLastScan), "tooltip"
    end
    local bdb = _G.EzWoW_BagsDB
    local market = type(bdb) == "table" and type(bdb.markets) == "table" and bdb.markets[marketKey()]
    if type(market) == "table" and tonumber(market.updatedTime) and tonumber(market.updatedTime) > at then
        at, src = tonumber(market.updatedTime), "bags"
    end
    local own = ns.DB and type(ns.DB.ahPrices) == "table" and ns.DB.ahPrices[marketKey()]
    if type(own) == "table" and tonumber(own.t) and tonumber(own.t) > at then at, src = tonumber(own.t), "own" end
    if at <= 0 then return nil end
    return at, src
end

-----------------------------------------------------------------------------
-- Own auction scan (only without EzWoW - Tooltip): one full list from the
-- server (at most every 15 minutes), lowest buyout per reagent kept
-----------------------------------------------------------------------------
local scan = { busy = false, open = false, listeners = {} }
Prices.scan = scan

function Prices.OnChanged(fn) scan.listeners[#scan.listeners + 1] = fn end
local function changed()
    for _, fn in ipairs(scan.listeners) do pcall(fn) end
end
Prices.NotifyChanged = changed

function Prices.AuctionOpen()
    if scan.open then return true end
    return (_G.AuctionHouseFrame and _G.AuctionHouseFrame:IsShown()) and true or false
end

local reader = CreateFrame("Frame")
reader:Hide()
local function finish(found)
    reader:Hide()
    scan.busy, scan.waiting = false, nil
    if found and next(found) and ns.DB then
        ns.DB.ahPrices = type(ns.DB.ahPrices) == "table" and ns.DB.ahPrices or {}
        local count = 0
        for _ in pairs(found) do count = count + 1 end
        ns.DB.ahPrices[marketKey()] = { t = (GetServerTime and GetServerTime()) or time(), items = found }
        scan.lastCount = count
    end
    changed()
end

reader:SetScript("OnUpdate", function(self)
    local api = C_AuctionHouse
    local wanted, found = Leveling.ReagentSet(), scan.found
    local last = min(scan.index + 800, scan.total) - 1
    for i = scan.index, last do
        local ok, _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = pcall(api.GetReplicateItemInfo, i)
        itemID, count, buyout = tonumber(itemID), tonumber(count) or 0, tonumber(buyout) or 0
        if ok and itemID and wanted[itemID] and buyout > 0 then
            local unit = max(1, floor(buyout / max(1, count)))
            if not found[itemID] or unit < found[itemID] then found[itemID] = unit end
        end
    end
    scan.index = last + 1
    if scan.index >= scan.total then finish(found) end
end)

local function readList()
    scan.waiting = nil
    local api = C_AuctionHouse
    local ok, total = pcall(api.GetNumReplicateItems)
    total = ok and tonumber(total) or 0
    if total <= 0 then finish(nil) return end
    scan.index, scan.total, scan.found = 0, total, {}
    reader:Show()
end

-- "tooltip": EzWoW - Tooltip was asked to scan; "own": scanning here; nil + reason
function Prices.Scan()
    if not Prices.AuctionOpen() then return nil, "closed" end
    if Prices.TooltipScans() then
        pcall(_G.EzWoW_Tooltip.BeginAuctionHousePriceScan, _G.EzWoW_Tooltip, false)
        return "tooltip"
    end
    local api = C_AuctionHouse
    if not (api and api.ReplicateItems and api.GetNumReplicateItems and api.GetReplicateItemInfo) then return nil, "noapi" end
    if scan.busy then return "own" end
    scan.busy = true
    local now = (GetServerTime and GetServerTime()) or time()
    local okCount, cached = pcall(api.GetNumReplicateItems)
    -- a list asked for in the last 15 minutes (by any addon) is still there
    if okCount and (tonumber(cached) or 0) > 0 and now - (scan.requestedAt or 0) < 900 then
        readList()
        return "own"
    end
    local tries = 0
    local function request()
        if not Prices.AuctionOpen() then scan.busy = false return end
        local ready = true
        if api.IsThrottledMessageSystemReady then
            local ok, r = pcall(api.IsThrottledMessageSystemReady)
            ready = not ok or r ~= false
        end
        if not ready and tries < 20 then
            tries = tries + 1
            C_Timer.After(0.5, request)
            return
        end
        scan.requestedAt, scan.waiting = now, true
        pcall(api.ReplicateItems)
        -- the list event may not come (another addon asked first): read after a while anyway
        C_Timer.After(4, function() if scan.waiting then readList() end end)
    end
    request()
    return "own"
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "REPLICATE_ITEM_LIST_UPDATE" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
    if event == "AUCTION_HOUSE_SHOW" then
        scan.open = true
        -- without EzWoW - Tooltip, prices are read once the leveling planner was used
        if not Prices.TooltipScans() and ns.DB and ns.DB.levelUsed then
            local now = (GetServerTime and GetServerTime()) or time()
            local own = type(ns.DB.ahPrices) == "table" and ns.DB.ahPrices[marketKey()]
            if not (type(own) == "table" and now - (tonumber(own.t) or 0) < 900) then
                C_Timer.After(1, function() Prices.Scan() end)
            end
        end
        -- EzWoW - Tooltip scans on its own: look again once it had time
        for _, delay in ipairs({ 6, 15, 30 }) do C_Timer.After(delay, changed) end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        scan.open = false
        if scan.busy and not reader:IsShown() then scan.busy, scan.waiting = false, nil end
        changed()
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        if scan.waiting then readList() end
    end
end)
