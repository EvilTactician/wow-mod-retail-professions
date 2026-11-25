-- Craft for profit, in the spirit of TradeSkillMaster's crafting view: for every recipe you know,
-- what the item sells for on the auction house, what its reagents cost, and the difference, so
-- you can see what's worth crafting to sell, and what you can already make from your bags and
-- reagent bank.
--
-- Shared bot reference prices (KC) come from mod-retail-ah's server, which answers its K request away from the
-- auctioneer (src/RetailAHCraftPrices.cpp there). It talks under RetailAH's own prefix; our
-- request ids start with "p", so RetailAH's addon, which numbers its own, ignores the answers.
--
--   KC:<req>:<entry>,<entry>,... -> KR:<req>:<effective house cut %>:<history days>
--                                   KD rows <entry>,<lowest buyout>,<units listed>,<AH bot pays>,
--                                           <vendor price>,<vendor pays>,<units sold>,<copper sold>,<flags>,<bot reference>
-- KC does not scan auctions. An older server falls back to the original K market request.
--                                   KE:<req>

local RPF = RetailProfessions
local M = RPF.Model
local P = {}
RPF.Profit = P

local PREFIX = "RAH"
local BATCH = 30       -- entries per request: keeps the message well inside the 255-byte limit
local FRESH = 180      -- seconds a price is good for before the view asks again
local TIMEOUT = 6

local ROW_LOCKED = 1
local ROW_SOULBOUND = 2
local ROW_REFERENCE_BUYER = 8

local floor, abs = math.floor, math.abs

P.cut = 5     -- the house cut in percent, from the last answer
P.days = 14   -- how far back "sold lately" looks
-- "unknown" until the first answer, "ok" once the server answered, "missing" when it can't:
-- no mod-retail-ah, one too old for K, or RetailAH.CraftPrices = 0.
P.state = "unknown"

local prices = {}  -- entry -> { lowest, units, bot, vendor, sell, soldUnits, soldCopper, locked, soulbound, at }
local failedUntil = {} -- per-entry retry cooldown after a lost response
local asked = {}   -- entry -> true while a request for it is out
local pending = {} -- req -> { entries, rows, tries, msg }
local nextReq = 0
local catalog = true -- additive KC command; older servers fall back to K
local queue, active = {}, nil
local pump

-----------------------------------------
-- formatting

-- "1g 20s", "45s 10c", "8c": short enough for a list row.
function P.Short(copper)
	copper = floor(abs(tonumber(copper) or 0))
	local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
	if g > 0 then return string.format("%dg %02ds", g, s) end
	if s > 0 then return string.format("%ds %02dc", s, c) end
	return c .. "c"
end

-- "+1g 20s" in green, "-45s 10c" in red.
function P.Signed(copper)
	if copper >= 0 then return "|cff40ff40+" .. P.Short(copper) .. "|r" end
	return "|cffff4040-" .. P.Short(copper) .. "|r"
end

-----------------------------------------
-- talking to the server

local function send(msg)
	SendAddonMessage(PREFIX, msg, "WHISPER", UnitName("player"))
end

local function giveUp(req)
	local p = pending[req]
	if not p then return end
	pending[req] = nil
	if active == req then active = nil end
	for _, entry in ipairs(p.entries) do
		asked[entry] = nil
		failedUntil[entry] = GetTime() + FRESH
	end
	RPF.Debounce("prices", 0.1, function () RPF.Fire("PRICES") end)
	RPF.After(0.12, function () pump() end)
end

local function noServer()
	P.state = "missing"
	for req in pairs(pending) do giveUp(req) end
	wipe(prices)
	RPF.Fire("PRICES")
end

pump = function ()
	if active then return end
	local req = table.remove(queue, 1)
	while req and not pending[req] do req = table.remove(queue, 1) end
	if not req then return end
	local p = pending[req]
	if not catalog and p.catalog then
		p.catalog = false
		p.msg = p.msg:gsub("^KC:", "K:")
	end
	active = req
	send(p.msg)
	RPF.After(TIMEOUT, function ()
		if pending[req] ~= p then return end
		giveUp(req)
		if P.state ~= "ok" then noServer() end
	end)
end

local function request(entries)
	nextReq = nextReq + 1
	local req = "p" .. nextReq
	local msg = (catalog and "KC:" or "K:") .. req .. ":" .. table.concat(entries, ",")
	local p = { entries = entries, rows = {}, tries = 0, msg = msg, catalog = catalog }
	pending[req] = p
	for _, entry in ipairs(entries) do asked[entry] = true end
	table.insert(queue, req)
	pump()
end

local function store(p, now)
	local seen = {}
	for _, row in ipairs(p.rows) do
		local entry = tonumber(row[1])
		if entry then
			local flags = tonumber(row[9]) or 0
			prices[entry] = {
				lowest = tonumber(row[2]) or 0, units = tonumber(row[3]) or 0, bot = tonumber(row[4]) or 0,
				vendor = tonumber(row[5]) or 0, sell = tonumber(row[6]) or 0,
				soldUnits = tonumber(row[7]) or 0, soldCopper = tonumber(row[8]) or 0,
				locked = bit.band(flags, ROW_LOCKED) ~= 0, soulbound = bit.band(flags, ROW_SOULBOUND) ~= 0,
				quote = tonumber(row[10]) or 0, catalog = p.catalog,
				referenceBuyer = bit.band(flags, ROW_REFERENCE_BUYER) ~= 0,
				botNet = tonumber(row[11]),
				at = now,
			}
			seen[entry] = true
		end
	end
	-- Entries the server skipped (no such item) aren't asked again until they'd be stale.
	for _, entry in ipairs(p.entries) do
		asked[entry] = nil
		failedUntil[entry] = nil
		if not seen[entry] then prices[entry] = { none = true, at = now } end
	end
end

local function onMessage(message)
	local code, req, rest = message:match("^([^:]+):([^:]*):?(.*)$")
	if code == "OFF" then
		-- mod-retail-ah is turned off.
		if next(pending) then noServer() end
		return
	end
	local p = req and pending[req]
	if not p then return end

	if code == "ERR" then
		if rest == "unknown" and p.catalog then
			-- Older server: retain the existing live-auction service without a hard dependency.
			catalog = false
			p.catalog = false
			p.msg = p.msg:gsub("^KC:", "K:")
			send(p.msg)
			return
		end
		if rest == "busy" and p.tries < 5 then
			p.tries = p.tries + 1
			RPF.After(0.25 * p.tries, function () if pending[req] == p then send(p.msg) end end)
			return
		end
		giveUp(req)
		-- "far" is an older server wanting an auctioneer for every request; "unknown" one
		-- without K, or with RetailAH.CraftPrices = 0.
		if rest == "far" or rest == "unknown" then noServer() end
		return
	elseif code == "KR" then
		local cut, days = rest:match("^([%d%.]+):?(%d*)")
		P.cut = tonumber(cut) or P.cut
		P.days = tonumber(days) or P.days
	elseif code == "KD" then
		for row in rest:gmatch("[^;]+") do
			local values = {}
			for value in row:gmatch("[^,]+") do table.insert(values, value) end
			table.insert(p.rows, values)
		end
	elseif code == "KE" then
		pending[req] = nil
		active = nil
		RPF.After(0.12, function () pump() end)
		P.state = "ok"
		store(p, GetTime())
		RPF.Debounce("prices", 0.1, function () RPF.Fire("PRICES") end)
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent", function (self, event, prefix, message, _, sender)
	if prefix == PREFIX and sender == UnitName("player") then onMessage(message) end
end)

-- Asks for every entry that has no price yet or an old one. `force` asks again for all of
-- them, and tries once more on a realm that didn't answer before.
function P.Fetch(entries, force)
	if P.state == "missing" then
		if not force then return end
		P.state = "unknown"
	end
	local now, batch = GetTime(), {}
	for _, entry in ipairs(entries) do
		local p = prices[entry]
		if not asked[entry] and (force or not failedUntil[entry] or now >= failedUntil[entry])
			and (force or not p or now - p.at > FRESH) then
			table.insert(batch, entry)
			if #batch == BATCH or #table.concat(batch, ",") > 215 then
				request(batch)
				batch = {}
			end
		end
	end
	if #batch > 0 then request(batch) end
end

function P.Fetching()
	return next(pending) ~= nil
end

-- Seconds since the oldest of these prices arrived; nil when one is missing.
function P.Age(entries)
	local now, oldest = GetTime(), 0
	for _, entry in ipairs(entries) do
		local p = prices[entry]
		if not p then return nil end
		oldest = math.max(oldest, now - p.at)
	end
	return oldest
end

-- A learned recipe of the open profession that makes an item, for pricing a reagent you can
-- make yourself. Rebuilt whenever the recipe list is.
local makers, makersOf = {}, nil
local function makerOf(id)
	if M.linked or not id then return nil end
	if makersOf ~= M.recipes then
		makers, makersOf = {}, M.recipes
		for _, r in ipairs(M.recipes) do
			if r.learned and not r.isEnchant and not r.refine and r.item and r.item > 0 and #r.reagents > 0
				and not makers[r.item] then
				makers[r.item] = r
			end
		end
	end
	return makers[id]
end
P.MakerOf = makerOf

-- The items a recipe involves: what it makes, its reagents and, for reagents you can make
-- yourself, theirs.
function P.EntriesOf(r, into, seen)
	into, seen = into or {}, seen or {}
	local function add(id)
		if id and id > 0 and not seen[id] then
			seen[id] = true
			table.insert(into, id)
		end
	end
	add(r.item)
	for _, rg in ipairs(r.reagents) do
		add(rg.id)
		local sub = makerOf(rg.id)
		if sub and sub ~= r then
			for _, srg in ipairs(sub.reagents) do add(srg.id) end
		end
	end
	return into
end

-- Every item of the open profession's learned recipes.
function P.ProfessionEntries()
	local entries, seen = {}, {}
	for _, r in ipairs(M.recipes) do
		if not r.isEnchant then P.EntriesOf(r, entries, seen) end
	end
	return entries
end

-----------------------------------------
-- prices

function P.Get(entry)
	local p = prices[entry]
	return p and not p.none and p or nil
end

local function averageSold(p)
	return p.soldUnits > 0 and floor(p.soldCopper / p.soldUnits) or nil
end

-- The cheapest reference cost: vendor, shared bot quote or live lowest buyout. Without either, what it sold
-- for lately. nil when nothing says; how = "vendor", "auction" or "sold".
function P.BuyCost(entry)
	local p = P.Get(entry)
	if not p then return nil end
	local best, how
	if p.vendor > 0 then best, how = p.vendor, "vendor" end
	if p.quote > 0 and not p.locked and not p.soulbound and (not best or p.quote < best) then
		best, how = p.quote, "catalog"
	end
	if p.lowest > 0 and (not best or p.lowest < best) then best, how = p.lowest, "auction" end
	if not best and not p.locked then
		local avg = averageSold(p)
		if avg then best, how = avg, "sold" end
	end
	return best, how
end

-- Authoritative BiS buyer items use the actual offer; others use estimated proceeds after the house cut: shared bot reference, or matching the lowest buyout (or, with nothing
-- listed, what it sold for lately), what the AH bot pays when that's more (it buys every time it
-- looks), or a vendor's price when that's more still. how = "auction", "sold", "bot" or "vendor";
-- gross is the price before the house cut.
function P.SellValue(entry)
	local p = P.Get(entry)
	if not p then return nil end
	local keep = 1 - (P.cut or 5) / 100
	local best, how, gross
	if not (p.soulbound or p.locked) then
		if p.referenceBuyer then
			if p.bot > 0 then best, how, gross = p.botNet or (p.bot - floor(p.bot * ((P.cut or 5) / 100))), "bot", p.bot end
		elseif p.quote > 0 then
			best, how, gross = floor(p.quote * keep), "catalog", p.quote
		elseif p.lowest > 0 then
			best, how, gross = floor(p.lowest * keep), "auction", p.lowest
		elseif averageSold(p) then
			best, how, gross = floor(averageSold(p) * keep), "sold", averageSold(p)
		end
		local bot = floor(p.bot * keep)
		if not p.referenceBuyer and bot > 0 and (not best or bot > best) then best, how, gross = bot, "bot", p.bot end
	end
	local sell = p.sell > 0 and p.sell or select(11, GetItemInfo(entry)) or 0
	if sell > 0 and (not best or sell > best) then best, how, gross = sell, "vendor", sell end
	return best, how, gross
end

-- Reagents in stock, shared by every line of one craft (and the crafts under it), so the same
-- Bronze Bar isn't counted twice. A trial copy is merged back only when its route is taken.
local function newStock(parent)
	return setmetatable({}, { __index = parent })
end

-- Counts asked within one frame (a whole list rebuild) are asked of the game once.
local haveCache, haveAt = {}, nil
local function haveCount(id)
	local now = GetTime()
	if haveAt ~= now then wipe(haveCache); haveAt = now end
	local n = haveCache[id]
	if not n then
		n = RPF.HaveCount(id)
		haveCache[id] = n
	end
	return n
end

local function take(stock, id, n)
	local left = stock[id]
	if left == nil then left = haveCount(id) end
	local used = math.min(left, n)
	stock[id] = left - used
	return used
end

local function merge(stock, trial)
	for id, left in pairs(trial) do stock[id] = left end
end

-- Multicraft and Resourcefulness of a recipe you craft yourself: (output factor, cost factor).
local function perkFactors(r)
	local perks = M.PerksOf and M.PerksOf(r)
	if not perks then return 1, 1, nil end
	local refund = RPF.perks and RPF.perks.refund or 0
	local mc, rf = perks.multicraft or 0, perks.resourceful or 0
	return 1 + mc / 100, 1 - (rf / 100) * (refund / 100), perks
end

local priceReagent

-- What one unit of an item costs to make with a learned recipe (one level down only), or nil.
local function makeUnit(id, n, stock, depth)
	local sub = depth == 0 and makerOf(id)
	if not sub then return nil end
	local yield = ((sub.madeMin or 1) + (sub.madeMax or sub.madeMin or 1)) / 2
	local outFactor, costFactor = perkFactors(sub)
	yield = yield * outFactor
	local crafts = math.ceil(n / yield)
	local trial = newStock(stock)
	local cost = 0
	for _, rg in ipairs(sub.reagents) do
		if not rg.id then return nil end
		local part = priceReagent(rg.id, rg.n * crafts, trial, depth + 1)
		if not part.known then return nil end
		cost = cost + part.cost
	end
	return cost * costFactor / (crafts * yield), trial, sub
end

-- One reagent line: units in stock at what selling them would bring (crafting has to beat
-- that), the rest at the cheaper of buying them and making them yourself.
-- { id, n, have, missing, haveUnit, buyUnit, buyHow, made (the recipe, when made), cost, known,
--   gain (copper more profit if you gathered the missing ones yourself) }
priceReagent = function (id, n, stock, depth)
	local part = { id = id, n = n, cost = 0, known = true, gain = 0 }
	part.have = take(stock, id, n)
	part.missing = n - part.have
	local sellUnit = P.SellValue(id)
	if part.have > 0 then
		if sellUnit then part.haveUnit = sellUnit
		elseif P.Get(id) then part.haveUnit = 0 -- nobody buys it: it costs nothing to use
		else part.known = false end
		part.cost = part.cost + (part.haveUnit or 0) * part.have
	end
	if part.missing > 0 then
		local buy, how = P.BuyCost(id)
		local make, trial, sub = makeUnit(id, part.missing, stock, depth)
		if make and (not buy or make < buy) then
			merge(stock, trial)
			part.buyUnit, part.buyHow, part.made = make, "made", sub
		elseif buy then
			part.buyUnit, part.buyHow = buy, how
			if sellUnit and buy > sellUnit then part.gain = (buy - sellUnit) * part.missing end
		else
			part.known = false
		end
		part.cost = part.cost + (part.buyUnit or 0) * part.missing
	end
	return part
end

-- One craft of a recipe, priced: { value, cost, profit, made, unitValue, valueHow, grossUnit,
-- costKnown, parts, multicraft, resourceful, saving, gain }, or nil when it makes nothing or its
-- item has no price yet. value counts Multicraft's extra batches, cost Resourcefulness's refunds;
-- gain is how much more it would make if you gathered the missing reagents yourself.
function P.Of(r)
	if r.isEnchant or not r.item or r.item == 0 then return nil end
	local unit, how, gross = P.SellValue(r.item)
	if not unit then return nil end
	local made = ((r.madeMin or 1) + (r.madeMax or r.madeMin or 1)) / 2
	local outFactor, costFactor, perks = perkFactors(r)
	local stock = newStock(nil)
	local cost, known, parts, gain = 0, true, {}, 0
	for _, rg in ipairs(r.reagents) do
		local part
		if rg.id then
			part = priceReagent(rg.id, rg.n, stock, 0)
		else
			part = { n = rg.n, cost = 0, known = false, gain = 0, have = 0, missing = rg.n }
		end
		part.rg = rg
		part.unit = part.n > 0 and part.cost / part.n or 0
		part.how = part.missing == 0 and "yours" or part.have == 0 and part.buyHow or "mixed"
		if not part.known then known = false end
		cost = cost + part.cost
		gain = gain + part.gain
		table.insert(parts, part)
	end
	local saving = floor(cost * (1 - costFactor))
	cost = floor(cost) - saving
	local value = floor(unit * made * outFactor)
	return { value = value, cost = cost, profit = value - cost, made = made, unitValue = unit, valueHow = how,
		grossUnit = gross, costKnown = known, parts = parts, saving = saving, gain = floor(gain * costFactor),
		multicraft = perks and perks.multicraft, resourceful = perks and perks.resourceful }
end

-- How many crafts the bags (and the reagent bank, when it's counted) cover.
local function canMake(r)
	local bags, withBank = M.Craftable(r)
	return RetailProfessionsDB.countBank and withBank or bags
end
P.CanMake = canMake

-----------------------------------------
-- the list: learned recipes grouped by what to do with them, best first

-- rows as M.Rows makes them, each recipe row with `right` = its profit per craft.
function P.Rows(state, collapsed)
	-- Until the first prices land, the window says so instead of listing everything as unpriced.
	if P.state ~= "ok" then return {} end
	local matches = M.Matcher(state)
	local searching = state.text and state.text ~= ""
	local groups = { now = {}, buy = {}, loss = {}, none = {} }
	for _, r in ipairs(M.recipes) do
		if not r.isEnchant and r.item and r.item > 0 and matches(r) then
			local a = P.Of(r)
			local key
			if not (a and a.costKnown) then
				key = "none"
			elseif a.profit <= 0 then
				key = "loss"
			elseif canMake(r) > 0 then
				key = "now"
			else
				key = "buy"
			end
			-- Without every material priced there's no profit to show, only a part of the cost.
			table.insert(groups[key], { recipe = r, profit = key ~= "none" and a.profit or nil })
		end
	end

	local rows = {}
	local function addGroup(name, key, list, extra)
		if #list == 0 then return end
		table.sort(list, function (x, y)
			if (x.profit or 0) ~= (y.profit or 0) then return (x.profit or 0) > (y.profit or 0) end
			return x.recipe.name < y.recipe.name
		end)
		local isCollapsed = not searching and collapsed[key] or false
		table.insert(rows, { header = name, key = key, count = #list, collapsed = isCollapsed, extra = extra })
		if not isCollapsed then
			for _, e in ipairs(list) do
				table.insert(rows, { recipe = e.recipe, right = e.profit and P.Signed(e.profit) or "|cff9d9d9d?|r" })
			end
		end
	end
	addGroup("Craft now", "p:now", groups.now, "profit / craft")
	addGroup("Buy materials and craft", "p:buy", groups.buy, "profit / craft")
	addGroup("Not worth it", "p:loss", groups.loss)
	addGroup("No price", "p:none", groups.none)
	return rows
end

function P.EmptyText()
	if P.state == "missing" then
		return "No auction prices on this realm: the profit view needs mod-retail-ah's server with RetailAH.CraftPrices on."
	end
	if P.Fetching() or P.state == "unknown" then return "Looking up auction prices..." end
	return "No recipes that make an item match."
end

-----------------------------------------
-- explaining a price

local HOW_SELL = {
	catalog = "bot reference estimate", auction = "lowest buyout", sold = "sold lately", bot = "AH bot", vendor = "vendor price",
}
local HOW_BUY = {
	catalog = "bot reference", vendor = "vendor", auction = "auction", sold = "sold lately", yours = "yours, sale value",
	made = "craft it", mixed = "some yours",
}

-- "AH bot, after 5% cut"; the cut is left out of a vendor's price, which has none.
function P.HowSell(how)
	if how == "vendor" or not HOW_SELL[how] then return HOW_SELL[how] or "" end
	return string.format("%s, after %s%% cut", HOW_SELL[how], P.CutText())
end

function P.CutText()
	local cut = P.cut or 5
	return cut % 1 == 0 and tostring(cut) or string.format("%.1f", cut)
end

function P.HowBuy(how) return HOW_BUY[how] or "" end

-- "12 listed, 34 sold in 14 days" for an item, or "" without prices.
function P.MarketText(entry)
	local p = P.Get(entry)
	if not p or p.locked then return "" end
	local parts = {}
	if p.units > 0 then table.insert(parts, p.units .. " listed") end
	if p.soldUnits > 0 then table.insert(parts, string.format("%d sold in %d days", p.soldUnits, P.days)) end
	return table.concat(parts, ", ")
end

-- Why an item sells for what it does, for tooltips: lines of grey text.
function P.SellNotes(entry)
	local p = P.Get(entry)
	local notes = {}
	if not p or p.locked then return notes end
	local _, how = P.SellValue(entry)
	if p.vendor > 0 then
		table.insert(notes, string.format("A vendor sells this for %s, so nobody pays more for it, the AH bot included.", P.Short(p.vendor)))
	end
	if p.referenceBuyer then
		if how == "bot" then
			table.insert(notes, "The AH bot buys it at this price when it next looks at the auction house.")
		else
			table.insert(notes, "The AH bot offers less than a vendor pays, or nothing.")
		end
	elseif p.catalog and how == "catalog" then
		table.insert(notes, "An estimate from the AH bot's prices: a sale isn't guaranteed.")
	end
	return notes
end

-- The whole sum behind a craft's profit, for the Profit line's tooltip. gatherable(id) says
-- how you could gather a reagent yourself ("mine"), or nil.
function P.AddProfitLines(tip, r, a, gatherable)
	local W, G = 1, 0.6
	-- A gap after the left text, so it never runs into the amount.
	local function row(left, right, ...) tip:AddDoubleLine(left .. "      ", right, ...) end
	-- A blank line before each heading, so the sections stand apart.
	local function gap() tip:AddLine(" ") end
	gap()
	row("Sells for", P.Short(floor(a.unitValue * a.made)) .. (a.made ~= 1 and string.format(" |cff9d9d9d(x%s)|r",
		a.made % 1 == 0 and tostring(a.made) or string.format("%.1f", a.made)) or ""), 1, 0.82, 0, W, W, W)
	if a.grossUnit and a.valueHow ~= "vendor" then
		row("  " .. HOW_SELL[a.valueHow], P.Short(floor(a.grossUnit * a.made)), W, W, W, W, W, W)
		row("  " .. P.CutText() .. "% auction cut", "-" .. P.Short(floor((a.grossUnit - a.unitValue) * a.made)), W, W, W, W, W, W)
	else
		row("  " .. (HOW_SELL[a.valueHow] or ""), "", W, W, W)
	end
	if a.multicraft and a.multicraft > 0 then
		row(string.format("  Multicraft %d%%", floor(a.multicraft + 0.5)),
			"+" .. P.Short(a.value - floor(a.unitValue * a.made)), W, W, W, 0.25, 1, 0.25)
	end
	gap()
	row("Materials", a.costKnown and P.Short(a.cost) or "?", 1, 0.82, 0, W, W, W)
	for _, part in ipairs(a.parts) do
		local name = M.ReagentName(part.rg) or ("Item #" .. tostring(part.rg.id or "?"))
		local how
		if not part.known then
			how = "|cffff4040no price|r"
		elseif part.missing == 0 then
			how = "yours, sale value"
		elseif part.have == 0 then
			how = HOW_BUY[part.buyHow] or ""
		else
			how = string.format("%d yours, %d %s", part.have, part.missing, part.buyHow == "made" and "to craft" or "to buy")
		end
		row(string.format("  %d %s |cff9d9d9d%s|r", part.n, name, how),
			part.known and P.Short(floor(part.cost)) or "?", W, W, W, W, W, W)
	end
	if a.saving > 0 then
		row(string.format("  Resourcefulness %d%%", floor((a.resourceful or 0) + 0.5)), "-" .. P.Short(a.saving),
			W, W, W, 0.25, 1, 0.25)
	end
	if a.costKnown then
		gap()
		row("Profit per craft", P.Signed(a.profit), 1, 0.82, 0, W, W, W)
	end
	-- Missing reagents you could gather yourself instead of buying.
	local lines, gain = {}, 0
	if a.costKnown and gatherable then
		for _, part in ipairs(a.parts) do
			local verb = part.gain > 0 and part.rg.id and gatherable(part.rg.id)
			if verb then
				table.insert(lines, { string.format("  %d %s |cff9d9d9d(%s)|r", part.missing, M.ReagentName(part.rg) or "?", verb), part.gain })
				gain = gain + part.gain
			end
		end
	end
	if #lines > 0 then
		gap()
		tip:AddLine("If you gather it yourself", 1, 0.82, 0)
		for _, line in ipairs(lines) do row(line[1], "+" .. P.Short(line[2]), W, W, W, 0.25, 1, 0.25) end
		gap()
		row("Profit if gathered", P.Signed(a.profit + gain), 1, 0.82, 0, W, W, W)
	end
	gap()
	for _, note in ipairs(P.SellNotes(r.item)) do tip:AddLine(note, G, G, G, true) end
	tip:AddLine("Materials you have count at what selling them would bring: crafting has to beat that.", G, G, G, true)
end

-- Profit lines for a recipe's tooltip.
function P.AddTooltipLines(tip, r)
	local a = P.state == "ok" and P.Of(r)
	if not a then return end
	tip:AddLine(" ")
	tip:AddDoubleLine("Sells for", P.Short(a.unitValue) .. " |cff9d9d9d(" .. P.HowSell(a.valueHow) .. ")|r", 1, 0.82, 0, 1, 1, 1)
	tip:AddDoubleLine("Materials", a.costKnown and P.Short(a.cost) or "?", 1, 0.82, 0, 1, 1, 1)
	if a.costKnown then
		tip:AddDoubleLine("Profit per craft", P.Signed(a.profit), 1, 0.82, 0, 1, 1, 1)
		local n = r.learned and canMake(r) or 0
		if n > 1 and a.profit > 0 then
			tip:AddDoubleLine(string.format("Craft all %d", n), P.Signed(a.profit * n), 1, 0.82, 0, 1, 1, 1)
		end
	end
	local market = P.MarketText(r.item)
	if market ~= "" then tip:AddLine(market, 0.6, 0.6, 0.6) end
end

RPF.On("LOGIN", function ()
	-- The losing and unpriced groups start folded; after that the player's choice stands.
	if not RetailProfessionsCharDB.profitFolded then
		RetailProfessionsCharDB.profitFolded = true
		RetailProfessionsCharDB.collapsed["p:loss"] = true
		RetailProfessionsCharDB.collapsed["p:none"] = true
	end
end)
