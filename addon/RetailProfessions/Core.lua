-- RetailProfessions core: saved settings, the profession table, the server protocol, item and
-- reagent-bank helpers, and the hand-over from the Blizzard trade skill window.

RetailProfessions = RetailProfessions or {}
local RPF = RetailProfessions

RPF.PREFIX = "RPR"
RPF.PROTOCOL = 1

-- Capability bits in the server's HELLO answer (see src/RetailProfessions.h).
RPF.HELLO_RECIPES = 1   -- L and W: every recipe of a profession, and where to learn one
RPF.HELLO_MAP_PINS = 2  -- M: a map flag on a trainer or vendor
RPF.HELLO_REFINE = 4    -- Y and X: what herbs and ore give, and milling or prospecting them
RPF.HELLO_PERKS = 8     -- crafts can make a second batch, give reagents back and cast faster
RPF.HELLO_GUIDE = 16    -- W rows carry a note and tooltip details; M pins drops, objects and quest givers
RPF.HELLO_GEAR = 32     -- profession equipment: GC, G, GQ, GU and GT (Gear.lua)
RPF.HELLO_GEAR_GATHER = 64 -- picks and knives slot as tools; Fishing has a rod slot
RPF.HELLO_GEAR_TYPED = 128 -- each accessory slot takes one kind; Cooking has 3 slots, Fishing a lure slot
RPF.HELLO_GEAR_ACCOUNT = 256 -- this character's slots are the account's
RPF.HELLO_RANKS = 512   -- K: where a profession's next rank is taught (gathering and Fishing too)

-- What a craft of a recipe can get on top (the perks field of an L row).
RPF.PERK_MULTICRAFT = 1
RPF.PERK_RESOURCEFUL = 2
RPF.PERK_SPEED = 4

-- Where a recipe can be learned (the src field of an L row).
RPF.SRC_TRAINER = 1
RPF.SRC_ITEM = 2       -- a recipe item, from a vendor, a drop, a quest or a chest
RPF.SRC_QUEST = 4      -- a quest teaches the spell itself
RPF.SRC_DISCOVERY = 8
RPF.SRC_AUTO = 16      -- learned with the profession or at a skill level
RPF.SRC_NPC = 32       -- someone or something in the world teaches it when asked

local floor = math.floor

-----------------------------------------
-- tiny event bus, so the window parts can react to each other without knowing about each other

local listeners = {}

function RPF.On(event, fn)
	listeners[event] = listeners[event] or {}
	table.insert(listeners[event], fn)
end

function RPF.Fire(event, ...)
	local list = listeners[event]
	if not list then return end
	for i = 1, #list do list[i](...) end
end

-----------------------------------------
-- timers (3.3.5a has no C_Timer)

local timerFrame = CreateFrame("Frame")
local timers = {}
local debounced = {}

function RPF.After(delay, fn)
	table.insert(timers, { at = GetTime() + delay, fn = fn })
	timerFrame:Show()
end

-- Runs fn once, `delay` seconds after the last call with the same key.
function RPF.Debounce(key, delay, fn)
	debounced[key] = { at = GetTime() + delay, fn = fn }
	timerFrame:Show()
end

timerFrame:SetScript("OnUpdate", function (self)
	local now = GetTime()
	local i = 1
	while i <= #timers do
		if timers[i].at <= now then
			local t = table.remove(timers, i)
			t.fn()
		else
			i = i + 1
		end
	end
	-- Taken out first and run after: a callback may debounce something new, and adding keys to
	-- a table while pairs walks it is an error.
	local due = {}
	for key, entry in pairs(debounced) do
		if entry.at <= now then table.insert(due, key) end
	end
	for _, key in ipairs(due) do
		local entry = debounced[key]
		-- An earlier callback may have pushed this one back.
		if entry and entry.at <= now then
			debounced[key] = nil
			entry.fn()
		end
	end
	if #timers == 0 and not next(debounced) then self:Hide() end
end)

-----------------------------------------
-- formatting

local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"
local SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t"
local COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t"

function RPF.Money(copper)
	copper = floor(tonumber(copper) or 0)
	local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
	local parts = {}
	if g > 0 then table.insert(parts, g .. GOLD) end
	if s > 0 then table.insert(parts, s .. SILVER) end
	if c > 0 or #parts == 0 then table.insert(parts, c .. COPPER) end
	return table.concat(parts, " ")
end

function RPF.Duration(seconds)
	seconds = floor(tonumber(seconds) or 0)
	if seconds >= 86400 then
		return string.format("%dd %dh", floor(seconds / 86400), floor(seconds / 3600) % 24)
	elseif seconds >= 3600 then
		return string.format("%dh %dm", floor(seconds / 3600), floor(seconds / 60) % 60)
	elseif seconds >= 60 then
		return string.format("%dm", floor(seconds / 60))
	end
	return string.format("%ds", seconds)
end

function RPF.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff4fc3f7Professions:|r " .. msg)
end

function RPF.QualityColor(quality)
	local c = ITEM_QUALITY_COLORS[quality or 1] or ITEM_QUALITY_COLORS[1]
	return c.r, c.g, c.b, c.hex
end

-----------------------------------------
-- professions

-- id = skill line; nameSpell = a spell with the profession's (localized) name, used to match
-- the names the client hands out; open = the spell that opens its window; extra = a second
-- action for the book (gathering tracking, fishing); refine = the Milling or Prospecting that
-- goes with it (Refine.lua); iconSpell = a spell whose icon, when the client has it, is used
-- instead of icon.
--
-- Archaeology (the mod-archaeology module) has no trade skill window: its window is the
-- ArchaeologyUI addon's research window (a page of DragonUI's professions window with DragonUI),
-- and its action is that addon's Survey. It only shows with ArchaeologyUI loaded.
RPF.PROFESSIONS = {
	{ id = 171, nameSpell = 2259, open = 2259, icon = "Trade_Alchemy" },
	{ id = 164, nameSpell = 2018, open = 2018, icon = "Trade_BlackSmithing" },
	{ id = 333, nameSpell = 7411, open = 7411, icon = "Trade_Engraving" },
	{ id = 202, nameSpell = 4036, open = 4036, icon = "Trade_Engineering" },
	{ id = 773, nameSpell = 45357, open = 45357, icon = "INV_Inscription_Tradeskill01", refine = "M" },
	{ id = 755, nameSpell = 25229, open = 25229, icon = "INV_Misc_Gem_01", refine = "P" },
	{ id = 165, nameSpell = 2108, open = 2108, icon = "Trade_LeatherWorking" },
	{ id = 197, nameSpell = 3908, open = 3908, icon = "Trade_Tailoring" },
	{ id = 186, nameSpell = 2575, open = 2656, extra = 2580, icon = "Trade_Mining" },
	-- Herbalism's spell is "Herb Gathering", so its name can't come from a spell.
	{ id = 182, name = "Herbalism", extra = 2383, icon = "Trade_Herbalism" },
	{ id = 393, nameSpell = 8613, icon = "INV_Misc_Pelt_Wolf_01" },
	{ id = 185, nameSpell = 2550, open = 2550, icon = "INV_Misc_Food_15", secondary = true },
	{ id = 129, nameSpell = 3273, open = 3273, icon = "Spell_Holy_SealOfSacrifice", secondary = true },
	{ id = 356, nameSpell = 7620, extra = 7620, icon = "Trade_Fishing", secondary = true },
	-- 90500 is Apprentice Archaeology in the realm's client patch; without it the name stands.
	{ id = 794, nameSpell = 90500, name = "Archaeology", iconSpell = 90500, icon = "INV_Misc_Shovel_01",
		secondary = true, archaeology = true },
	{ id = 776, nameSpell = 53428, open = 53428, icon = "Spell_DeathKnight_FrozenRuneWeapon", class = true },
}

local byId, byName = {}, {}

local function professionName(p)
	if p.nameSpell then
		local name = GetSpellInfo(p.nameSpell)
		if name then return name end
	end
	return p.name
end

local function indexProfessions()
	byId, byName = {}, {}
	for _, p in ipairs(RPF.PROFESSIONS) do
		p.localName = professionName(p) or p.name or tostring(p.id)
		p.openName = p.open and GetSpellInfo(p.open) or nil
		p.extraName = p.extra and GetSpellInfo(p.extra) or nil
		local spellIcon = p.iconSpell and select(3, GetSpellInfo(p.iconSpell))
		p.texture = spellIcon or ("Interface\\Icons\\" .. p.icon)
		-- What its window's tab shows: the spell that opens it (Mining's is Smelting).
		p.openTexture = p.open and select(3, GetSpellInfo(p.open)) or p.texture
		byId[p.id] = p
		byName[p.localName:lower()] = p
	end
end
RPF.IndexProfessions = indexProfessions

function RPF.Profession(id)
	return byId[id]
end

-- The profession a localized skill name (GetTradeSkillLine, GetSkillLineInfo) belongs to.
function RPF.ProfessionByName(name)
	if not name then return nil end
	return byName[name:lower()]
end

-- The ArchaeologyUI addon, when it's loaded and new enough to open its window and survey.
function RPF.ArchaeologyUI()
	local A = _G.ArchaeologyUI
	if type(A) == "table" and A.ToggleWindow and A.SurveyButtonClick then return A end
	return nil
end

-- Archaeology's window: ArchaeologyUI's research window, or its page in DragonUI's window or ours (Pages.lua).
function RPF.OpenArchaeology()
	local A = RPF.ArchaeologyUI()
	if not A then return end
	-- Open stays open; an older ArchaeologyUI only toggles.
	if A.OpenWindow then A.OpenWindow() else A.ToggleWindow() end
end

-- Apprentice ... Grand Master, from the skill cap the player's rank gives.
local RANKS = { { 75, "Apprentice" }, { 150, "Journeyman" }, { 225, "Expert" }, { 300, "Artisan" },
	{ 375, "Master" }, { 450, "Grand Master" } }

function RPF.RankTitle(maxRank)
	for _, r in ipairs(RANKS) do
		if (maxRank or 0) <= r[1] then return r[2] end
	end
	return RANKS[#RANKS][2]
end

-- A skill as the character window's Skills tab writes it: "300 (+15)/300", what equipment,
-- racials and lures add in green (a malus in red). sep stands for the slash.
function RPF.BonusText(bonus)
	if not bonus or bonus == 0 then return "" end
	return string.format(" (%s%+d|r)", bonus > 0 and "|cff20ff20" or "|cffff2020", bonus)
end

function RPF.SkillRankText(baseRank, bonus, maxRank, sep)
	return string.format("%d%s%s%d", baseRank or 0, RPF.BonusText(bonus), sep or "/", maxRank or 0)
end

-- A racial skill bonus (Tauren Herbalism, Gnome Engineering, Blood Elf Enchanting, Draenei
-- Jewelcrafting) is permanent, and the client adds it to both the rank and the max: Herbalism
-- 344/375 with Cultivation reads 359/390. Every max is a multiple of 75, so what's over it is
-- the racial, which we take back out and show with the other bonuses: 344 (+15)/375.
function RPF.RacialBonus(maxRank)
	return (maxRank or 0) % 75
end

-- A skill's lines in a tooltip: the trained skill, and with a bonus the skill it makes.
function RPF.AddSkillLines(tip, baseRank, bonus, maxRank)
	baseRank, bonus = baseRank or 0, bonus or 0
	tip:AddLine(string.format("Skill %d of %d", baseRank, maxRank or 0), 1, 1, 1)
	if bonus ~= 0 then
		tip:AddLine(string.format("%+d from equipment, racials and lures: you count as %d.", bonus, baseRank + bonus),
			bonus > 0 and 0.13 or 1, bonus > 0 and 1 or 0.13, 0.13, true)
		tip:AddLine("Skill-ups and trainers go by your skill without it.", 0.7, 0.7, 0.7, true)
	end
end

-- The skill tier a requirement falls into, for grouping unlearned recipes.
function RPF.TierOf(skill)
	for _, r in ipairs(RANKS) do
		if (skill or 0) < r[1] then return r[1] - 75, r[2] end
	end
	return 375, RANKS[#RANKS][2]
end

-- Every profession the player knows: { profession, rank, maxRank, skillIndex } in
-- primary, secondary, class order.
local ignoreSkillEventsUntil = 0

function RPF.KnownProfessions()
	-- Lines under a collapsed header (in the character window's Skills tab) aren't listed:
	-- open those headers while we read, then fold them again. That fires SKILL_LINES_CHANGED,
	-- which mustn't send us round again.
	local collapsed = {}
	for i = GetNumSkillLines(), 1, -1 do
		local name, isHeader, isExpanded = GetSkillLineInfo(i)
		if isHeader and not isExpanded then
			table.insert(collapsed, name)
			ExpandSkillHeader(i)
		end
	end
	if #collapsed > 0 then ignoreSkillEventsUntil = GetTime() + 0.5 end

	local known = {}
	for i = 1, GetNumSkillLines() do
		local name, isHeader, _, rank, _, modifier, maxRank, abandonable = GetSkillLineInfo(i)
		if not isHeader then
			local p = RPF.ProfessionByName(name)
			if p and not (p.archaeology and not RPF.ArchaeologyUI()) then
				-- Archaeology's progress lives in the module's own tables: unlearning the skill
				-- line alone would leave them behind.
				local racial = RPF.RacialBonus(maxRank)
				table.insert(known, { profession = p, rank = (rank or 0) + (modifier or 0), baseRank = (rank or 0) - racial,
					maxRank = (maxRank or 0) - racial, skillIndex = i, abandonable = abandonable and not p.archaeology })
			end
		end
	end
	-- Without the client patch (or with Archaeology.Skill.SkillLine off) Archaeology isn't a
	-- skill line: ArchaeologyUI has the skill from the server.
	local A = RPF.ArchaeologyUI()
	local arch = RPF.Profession(794)
	if A and arch and (A.skill or 0) > 0 then
		local listed = false
		for _, e in ipairs(known) do
			if e.profession == arch then listed = true end
		end
		if not listed then
			table.insert(known, { profession = arch, rank = A.skill, baseRank = A.skill, maxRank = A.maxSkill or 0,
				skillIndex = GetNumSkillLines() + 1, abandonable = false })
		end
	end
	local function order(e)
		local p = e.profession
		return (p.class and 3 or p.secondary and 2 or 1) * 1000 + e.skillIndex
	end
	table.sort(known, function (a, b) return order(a) < order(b) end)

	for i = GetNumSkillLines(), 1, -1 do
		local name, isHeader, isExpanded = GetSkillLineInfo(i)
		if isHeader and isExpanded then
			for _, c in ipairs(collapsed) do
				if c == name then CollapseSkillHeader(i) break end
			end
		end
	end
	-- skillIndex is only good while the headers are open; nothing outside keeps it.
	return known
end

-----------------------------------------
-- favorites (per character): the star beside a recipe's name puts it at the top of the list

function RPF.IsFavorite(spell)
	return spell and RetailProfessionsCharDB and RetailProfessionsCharDB.favorites[spell] and true or false
end

function RPF.ToggleFavorite(spell)
	if not spell then return end
	RetailProfessionsCharDB.favorites[spell] = not RetailProfessionsCharDB.favorites[spell] or nil
	RPF.Fire("FAVORITES")
end

-----------------------------------------
-- items

local scanTip = CreateFrame("GameTooltip", "RetailProfessionsScanTooltip", nil, "GameTooltipTemplate")
scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
local waiting = {}
local waitingCount = 0

-- GetItemInfo only answers for cached items; ask the client for the rest and poll.
function RPF.Item(entry)
	if not entry or entry == 0 then return nil end
	local name, link, quality, _, _, _, _, maxStack, equipLoc, texture = GetItemInfo(entry)
	if name then
		return { name = name, link = link, quality = quality or 1, maxStack = maxStack or 1, equipLoc = equipLoc,
			texture = texture }
	end
	local key = "item:" .. entry
	if not waiting[key] then
		waiting[key] = GetTime()
		waitingCount = waitingCount + 1
		scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
		scanTip:SetHyperlink(key)
	end
	return nil
end

function RPF.ItemIcon(entry)
	if not entry or entry == 0 then return nil end
	local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(entry)
	return texture or (GetItemIcon and GetItemIcon(entry)) or nil
end

local pollFrame = CreateFrame("Frame")
local pollElapsed = 0
pollFrame:SetScript("OnUpdate", function (self, elapsed)
	if waitingCount == 0 then return end
	pollElapsed = pollElapsed + elapsed
	if pollElapsed < 0.1 then return end
	pollElapsed = 0
	local now, arrived = GetTime(), false
	for key, since in pairs(waiting) do
		if GetItemInfo(key) then
			waiting[key] = nil
			waitingCount = waitingCount - 1
			arrived = true
		elseif now - since > 20 then
			waiting[key] = nil
			waitingCount = waitingCount - 1
		end
	end
	if arrived then RPF.Debounce("iteminfo", 0.1, function () RPF.Fire("ITEM_INFO") end) end
end)

function RPF.ItemIdFromLink(link)
	return link and tonumber(link:match("item:(%d+)")) or nil
end

-- "|Henchant:2259|h" (a recipe link) or "|Hspell:2259|h".
function RPF.SpellIdFromLink(link)
	return link and tonumber(link:match("enchant:(%d+)") or link:match("spell:(%d+)")) or nil
end

-----------------------------------------
-- reagent bank (mod-reagent-bank-account's ReagentBankUI), when it's loaded

function RPF.HasReagentBank()
	local RB = _G.ReagentBankUI
	return RB and RB.GetCachedBankItemCount and true or false
end

-- Units of an item in the reagent bank as far as ReagentBankUI knows; 0 when it doesn't.
function RPF.BankCount(entry)
	local RB = _G.ReagentBankUI
	if not (RB and RB.GetCachedBankItemCount) then return 0 end
	local ok, count = pcall(RB.GetCachedBankItemCount, RB, entry)
	return ok and tonumber(count) or 0
end

function RPF.RequestBankSnapshot()
	local RB = _G.ReagentBankUI
	if RB and RB.RequestBankSnapshot then pcall(RB.RequestBankSnapshot, RB) end
end

-- ReagentBankUI's "put unused reagents back when the profession window closes".
function RPF.DepositLeftovers()
	local RB = _G.ReagentBankUI
	if RB and RB.GetAutoDepositLeftovers then return RB:GetAutoDepositLeftovers() end
	return ReagentBankUIDB and ReagentBankUIDB.autoDepositLeftovers and true or false
end

function RPF.SetDepositLeftovers(on)
	local RB = _G.ReagentBankUI
	if RB and RB.SetAutoDepositLeftovers then
		RB:SetAutoDepositLeftovers(on)
	elseif RB and ReagentBankUIDB then
		-- A ReagentBankUI from before it had the setter.
		ReagentBankUIDB.autoDepositLeftovers = on and true or false
		if not on then RB.pendingAutoDepositLeftovers, RB.pendingAutoDepositAt = nil, nil end
	end
end

-- False while ReagentBankUI is still waiting to hear what the bank holds (counts read as 0).
function RPF.BankCountsKnown()
	local RB = _G.ReagentBankUI
	if not (RB and RB.HasFreshBankSnapshot) then return true end
	local ok, fresh = pcall(RB.HasFreshBankSnapshot, RB)
	return not ok or fresh and true or false
end

-----------------------------------------
-- the auction house shopping list (ReagentBankUI keeps it; RetailAH's Buy tab shows it)

function RPF.HasShoppingList()
	local RB = _G.ReagentBankUI
	return RB and RB.AddShoppingListRows and RB.GetShoppingListMap and true or false
end

-- Units of an item still to buy on the shopping list.
function RPF.OnShoppingList(entry)
	local RB = _G.ReagentBankUI
	if not (RB and RB.GetShoppingListMap) then return 0 end
	local ok, list = pcall(RB.GetShoppingListMap, RB)
	return ok and type(list) == "table" and tonumber(list[entry]) or 0
end

-- What `count` crafts of a recipe need beyond the bags and the reagent bank:
-- { { rg = reagent, amount = units short } }. The bank counts whether or not crafting uses it:
-- it's yours either way.
function RPF.ShortFor(r, count)
	local short = {}
	for _, rg in ipairs(r.reagents) do
		if rg.id then
			local have = (GetItemCount(rg.id) or 0) + RPF.BankCount(rg.id)
			local need = rg.n * count - have
			if need > 0 then table.insert(short, { rg = rg, amount = need }) end
		end
	end
	return short
end

-- Puts what `count` crafts of a recipe are short of on the shopping list and returns how many
-- units went on. The list adds up, so only what isn't on it yet goes on: asking twice, or again
-- while a purchase is still in the mail, doesn't double it. `onTop` adds the whole shortfall
-- anyway, for a second recipe that needs the same reagent.
function RPF.AddToShoppingList(r, count, onTop)
	local RB = _G.ReagentBankUI
	if not RPF.HasShoppingList() then return 0 end
	local rows, total = {}, 0
	for _, part in ipairs(RPF.ShortFor(r, count)) do
		local amount = onTop and part.amount or part.amount - RPF.OnShoppingList(part.rg.id)
		if amount > 0 then
			table.insert(rows, { itemEntry = part.rg.id, amount = amount })
			total = total + amount
		end
	end
	if total == 0 then return 0 end
	local ok = pcall(RB.AddShoppingListRows, RB, rows, count .. " craft(s) of " .. tostring(r.name))
	return ok and total or 0
end

-- What the player has of a reagent: bags, and the reagent bank when the setting says so.
function RPF.HaveCount(entry)
	local bags = GetItemCount(entry) or 0
	local bank = RetailProfessionsDB.countBank and RPF.BankCount(entry) or 0
	return bags + bank, bags, bank
end

-----------------------------------------
-- server protocol: "<command>:<request id>:<field>..." whispered to yourself under the RPR prefix

RPF.serverReady = false
RPF.flags = 0

local nextReq = 0
local pending = {}
local LISTS = { L = true, W = true, Y = true }
-- Profession equipment's lists (Gear.lua): the catalog, a profession's tools and the slots.
local GEAR_LISTS = { GCD = true, GCE = true, GTD = true, GTE = true, GD = true, GE = true }
local gearPush -- rows of an unasked GD:0 until its GE:0

local function send(msg)
	SendAddonMessage(RPF.PREFIX, msg, "WHISPER", UnitName("player"))
end

-- handler(result, err): result is { rows = {...}, meta = {...} } for list answers and the array
-- of fields for single ones; err is set when the server refused ("busy", "bad", "none").
function RPF.Request(cmd, fields, handler)
	nextReq = nextReq + 1
	local req = tostring(nextReq)
	local msg = cmd .. ":" .. req
	if fields and #fields > 0 then msg = msg .. ":" .. table.concat(fields, ":") end
	local p = { req = req, handler = handler, rows = {}, msg = msg, tries = 0 }
	pending[req] = p
	send(msg)
	return req
end

local function splitFields(text)
	local out = {}
	if text == nil or text == "" then return out end
	for field in (text .. ":"):gmatch("([^:]*):") do table.insert(out, field) end
	return out
end

-- The server escapes ',', ';', ':', '|' and '%' in names as %XX.
function RPF.Unescape(text)
	if type(text) ~= "string" then return text end
	if text == "-" then return "" end
	return (text:gsub("%%(%x%x)", function (h) return string.char(tonumber(h, 16)) end))
end

local function parseRows(text, into)
	for row in text:gmatch("[^;]+") do
		local values = {}
		for value in row:gmatch("[^,]+") do table.insert(values, tonumber(value) or value) end
		table.insert(into, values)
	end
end

local function finish(req, result, err)
	local p = pending[req]
	if not p then return end
	pending[req] = nil
	if p.handler then p.handler(result, err) end
end

local function onHello(fields)
	local version = tonumber(fields[1])
	if version ~= RPF.PROTOCOL then
		RPF.Print("the server speaks a different version of the profession window (" .. tostring(version)
			.. ", this addon " .. RPF.PROTOCOL .. "); unlearned recipes are off. Update the RetailProfessions addon.")
		return
	end
	RPF.serverReady = true
	RPF.flags = tonumber(fields[2]) or 0
	RPF.dataStamp = fields[3] or "0"
	local cap = tonumber(fields[4]) or 0
	RPF.skillCap = cap > 0 and cap or nil
	-- The craft skill-up chance at orange and at grey, in percent (it falls in a straight line
	-- between the yellow and grey thresholds), and how many points one skill-up gives.
	RPF.chanceOrange = tonumber(fields[5]) or 100
	RPF.chanceGrey = tonumber(fields[6]) or 0
	RPF.skillGain = tonumber(fields[7]) or 1
	-- Multicraft, Resourcefulness and crafting speed, each in percent from where a recipe is
	-- orange to where it's grey (Model.lua works a recipe's odds out from these).
	RPF.perks = nil
	if bit.band(RPF.flags, RPF.HELLO_PERKS) ~= 0 then
		RPF.perks = {
			multicraftMin = tonumber(fields[8]) or 0, multicraftMax = tonumber(fields[9]) or 0,
			resourcefulMin = tonumber(fields[10]) or 0, resourcefulMax = tonumber(fields[11]) or 0,
			refund = tonumber(fields[12]) or 0,
			speedMin = tonumber(fields[13]) or 0, speedMax = tonumber(fields[14]) or 0,
		}
	end
	RPF.Fire("READY")
end

-- The chance in percent that one craft raises the skill, as the core works it out
-- (CraftSkillGainChance): orange up to the yellow threshold, grey from the grey one, a straight
-- line in between. nil without the thresholds.
function RPF.SkillUpChance(skill, yellow, grey)
	if not (yellow and grey and grey > 0) then return nil end
	local orange, gray = RPF.chanceOrange or 100, RPF.chanceGrey or 0
	if grey <= yellow then return skill < grey and orange or gray end
	if skill <= yellow then return orange end
	if skill >= grey then return gray end
	return gray + floor((grey - skill) * (orange - gray) / (grey - yellow))
end

function RPF.Has(flag)
	return RPF.serverReady and bit.band(RPF.flags, flag) ~= 0
end

local function onAddonMessage(message)
	local code, req, rest = message:match("^([^:]+):([^:]*):?(.*)$")
	if not code then return end

	if code == "HELLO" then
		onHello(splitFields(rest))
		finish(req, splitFields(rest))
		return
	elseif code == "OFF" then
		RPF.serverReady = false
		return
	elseif code == "ERR" then
		local p = pending[req]
		if rest == "busy" and p and p.tries < 5 then
			p.tries = p.tries + 1
			RPF.After(0.2 * p.tries, function () if pending[req] == p then send(p.msg) end end)
			return
		end
		finish(req, nil, rest)
		return
	end

	-- A craft made a second batch (M) or gave reagents back (R): "<spell>:<M|R>:<item>*<n>/...".
	if code == "PK" then
		local spell, kind, list = rest:match("^(%d+):(%a):(.*)$")
		if spell then RPF.Fire("PERK", tonumber(spell), kind, list) end
		return
	end

	-- A gathering perk came up (Finesse, F): "<skill>:F:<item>*<n>".
	if code == "PG" then
		local skill, kind, list = rest:match("^(%d+):(%a):(.*)$")
		if skill then RPF.Fire("GATHER_PERK", tonumber(skill), kind, list) end
		return
	end

	-- Profession equipment's lists end with a count instead of a meta line first. The slots also
	-- come unasked, under request 0, after every change.
	if GEAR_LISTS[code] then
		local last = code:sub(-1) == "E"
		if req == "0" and (code == "GD" or code == "GE") then
			if last then
				local rows = gearPush or {}
				gearPush = nil
				RPF.Fire("GEAR_PUSH", rows)
			else
				gearPush = gearPush or {}
				parseRows(rest, gearPush)
			end
			return
		end
		local p = pending[req]
		if not p then return end
		if last then finish(req, { rows = p.rows, meta = splitFields(rest) }) else parseRows(rest, p.rows) end
		return
	end

	-- A milling or prospecting job reports on its own, under the id of the request that began it.
	if code == "XP" or code == "XE" then
		RPF.Fire(code == "XP" and "REFINE_PROGRESS" or "REFINE_END", req, splitFields(rest))
		return
	end

	local kind, part = code:sub(1, 1), code:sub(2)
	if #code == 2 and LISTS[kind] and (part == "R" or part == "D" or part == "E") then
		local p = pending[req]
		if not p then return end
		if part == "R" then
			p.meta = splitFields(rest)
		elseif part == "D" then
			parseRows(rest, p.rows)
		else
			finish(req, { rows = p.rows, meta = p.meta or {} })
		end
		return
	end

	finish(req, splitFields(rest))
end

local helloSerial = 0
function RPF.SayHello()
	helloSerial = helloSerial + 1
	local mine = helloSerial
	RPF.Request("HELLO", { tostring(RPF.PROTOCOL) })
	RPF.After(5, function ()
		if mine == helloSerial and not RPF.serverReady then
			-- Not an error: the window works without the server, just without unlearned recipes.
			RPF.Fire("NO_SERVER")
		end
	end)
end

-----------------------------------------
-- the server's recipe lists, cached per profession, race and class until its data changes

local recipeLists = {}   -- skill id -> { [spell] = info } once loaded
local listRequests = {}  -- skill id -> true while asked

local function parseReagents(text)
	local out = {}
	if type(text) ~= "string" or text == "-" then return out end
	for id, n in text:gmatch("(%d+)%*(%d+)") do
		table.insert(out, { id = tonumber(id), n = tonumber(n) })
	end
	return out
end

local function listKey(skill)
	local _, race = UnitRace("player")
	local _, class = UnitClass("player")
	return table.concat({ RPF.dataStamp or "0", skill, race or "", class or "" }, ":")
end

-- L row: spell, required skill, yellow, grey, product item, made min, made max, source bits,
-- reagents ("id*n/id*n" or "-"), product inventory type, product quality, recipe item,
-- 1 when it's cast on an item, and the perks a craft can get (both missing from older servers).
local function buildList(rows)
	local list = {}
	for _, r in ipairs(rows) do
		local spell = tonumber(r[1])
		if spell then
			local yellow, grey = tonumber(r[3]) or 0, tonumber(r[4]) or 0
			list[spell] = {
				spell = spell, reqSkill = tonumber(r[2]) or 0, yellow = yellow, grey = grey,
				green = floor((yellow + grey) / 2), item = tonumber(r[5]) or 0,
				madeMin = tonumber(r[6]) or 1, madeMax = tonumber(r[7]) or 1, sources = tonumber(r[8]) or 0,
				reagents = parseReagents(r[9]), invType = tonumber(r[10]) or 0, quality = tonumber(r[11]) or 1,
				recipeItem = tonumber(r[12]) or 0, perks = tonumber(r[14]) or 0,
			}
			-- nil from older servers: the addon falls back to its own guess.
			if r[13] ~= nil then list[spell].targetsItem = tonumber(r[13]) == 1 end
		end
	end
	return list
end

-- { [spell] = info } for a profession, or nil while it's on its way (RECIPES fires then).
function RPF.RecipeList(skill)
	if recipeLists[skill] then return recipeLists[skill] end
	if not RPF.Has(RPF.HELLO_RECIPES) then return nil end

	local key = listKey(skill)
	local saved = RetailProfessionsDB.lists[key]
	if saved then
		recipeLists[skill] = buildList(saved)
		return recipeLists[skill]
	end

	if not listRequests[skill] then
		listRequests[skill] = true
		RPF.Request("L", { tostring(skill) }, function (result, err)
			listRequests[skill] = nil
			if not result then return end
			-- A GM's list holds everything (other factions too): don't keep it for the account.
			if tostring(result.meta[3]) ~= "1" then
				-- Older stamps for this profession are dead weight.
				local suffix = ":" .. skill .. ":"
				for k in pairs(RetailProfessionsDB.lists) do
					if k:find(suffix, 1, true) and k ~= key then RetailProfessionsDB.lists[k] = nil end
				end
				RetailProfessionsDB.lists[key] = result.rows
			end
			recipeLists[skill] = buildList(result.rows)
			RPF.Fire("RECIPES", skill)
		end)
	end
	return nil
end

function RPF.ForgetRecipeLists()
	recipeLists = {}
end

-- Where a recipe is learned. handler({ recipeItem = entry, rows = { { kind, id, name, zone, a, b, c } } })
-- One request per recipe at a time, and answers (refusals too, apart from "busy") are kept, so
-- redraws on every bag change don't ask again.
local whereCache, whereFailed, whereWaiting = {}, {}, {}
-- `spell` is the cache key: a recipe's spell, or "k<skill>:<rank>" for a rank (K).
local function whereLookup(spell, cmd, fields, handler)
	if whereCache[spell] then handler(whereCache[spell]) return end
	if whereFailed[spell] then handler(nil, whereFailed[spell]) return end
	if whereWaiting[spell] then
		table.insert(whereWaiting[spell], handler)
		return
	end
	whereWaiting[spell] = { handler }
	local function deliver(result, err)
		local waiting = whereWaiting[spell] or {}
		whereWaiting[spell] = nil
		for _, h in ipairs(waiting) do h(result, err) end
	end
	RPF.Request(cmd, fields, function (result, err)
		if not result then
			if err ~= "busy" then whereFailed[spell] = err or "none" end
			deliver(nil, err)
			return
		end
		local out = { recipeItem = tonumber(result.meta[2]) or 0, rows = {} }
		for _, r in ipairs(result.rows) do
			table.insert(out.rows, { kind = r[1], id = tonumber(r[2]) or 0, name = RPF.Unescape(tostring(r[3] or "-")),
				zone = RPF.Unescape(tostring(r[4] or "-")), a = r[5], b = r[6], c = r[7] and RPF.Unescape(tostring(r[7])) or nil,
				note = RPF.Unescape(tostring(r[8] or "-")), details = RPF.Unescape(tostring(r[9] or "-")) })
		end
		whereCache[spell] = out
		deliver(out)
	end)
end

function RPF.WhereToLearn(spell, handler)
	whereLookup(spell, "W", { tostring(spell) }, handler)
end

-- Where a profession's rank (2 = Journeyman ... 6 = Grand Master) is taught: a trainer, a book
-- on a vendor or a quest, as WhereToLearn answers. Nothing without HELLO_RANKS.
function RPF.WhereToTrain(skill, rank, handler)
	if not RPF.Has(RPF.HELLO_RANKS) then
		handler(nil, "off")
		return
	end
	whereLookup("k" .. skill .. ":" .. rank, "K", { tostring(skill), tostring(rank) }, handler)
end

-- Sources change with progression (a raid kill opens vendors and closes others): ask again
-- after each loading screen, which leaving the raid brings.
function RPF.ForgetWhere()
	whereCache, whereFailed = {}, {}
end

-- Puts a flag on the world map at the nearest spawn of a source: a trainer, vendor or teacher,
-- and with HELLO_GUIDE also a creature that drops it, an object or a quest's giver.
function RPF.ShowOnMap(kind, entry, handler)
	RPF.Request("M", { kind, tostring(entry) }, function (result, err)
		if handler then handler(result and RPF.Unescape(result[2] or "") or nil, err) end
	end)
end

-----------------------------------------
-- taking over from the Blizzard window

RPF.active = false
local switchingToClassic = false

local function showClassic()
	switchingToClassic = true
	if RetailProfessionsFrame and RetailProfessionsFrame:IsShown() then RetailProfessionsFrame:Hide() end
	switchingToClassic = false
	RPF.active = false
	TradeSkillFrame_LoadUI()
	if TradeSkillFrame_Show then TradeSkillFrame_Show() end
end
RPF.ShowClassic = showClassic

function RPF.IsSwitchingToClassic()
	return switchingToClassic
end

local function onTradeSkillShow()
	-- In DragonUI's professions window (Host.lua): it opens as usual and we fill it. With /prof
	-- classic there, DragonUI's own crafting page is all there is.
	if RPF.hosting then
		RPF.active = true
		RPF.Fire("SHOW")
		return
	end
	if RPF.hostClassic then return end
	if RetailProfessionsDB.classic then
		showClassic()
		return
	end
	-- The stock window may still be up (after /prof classic and back). Its OnHide calls
	-- CloseTradeSkill, which would end the session that just opened, so hide it without that.
	if TradeSkillFrame and TradeSkillFrame:IsShown() then
		local onHide = TradeSkillFrame:GetScript("OnHide")
		TradeSkillFrame:SetScript("OnHide", nil)
		HideUIPanel(TradeSkillFrame)
		TradeSkillFrame:SetScript("OnHide", onHide)
	end
	RPF.active = true
	RPF.Fire("SHOW")
end

local function onTradeSkillClose()
	RPF.active = false
	RPF.Fire("CLOSE")
end

-----------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("TRADE_SKILL_SHOW")
events:RegisterEvent("TRADE_SKILL_CLOSE")
events:RegisterEvent("TRADE_SKILL_UPDATE")
events:RegisterEvent("TRADE_SKILL_FILTER_UPDATE")
events:RegisterEvent("CHAT_MSG_ADDON")
events:RegisterEvent("BAG_UPDATE")
events:RegisterEvent("SKILL_LINES_CHANGED")
events:RegisterEvent("LEARNED_SPELL_IN_TAB")
events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
events:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
events:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
events:RegisterEvent("UNIT_SPELLCAST_FAILED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")

events:SetScript("OnEvent", function (self, event, ...)
	if event == "ADDON_LOADED" then
		if ... == "RetailProfessions" then
			RetailProfessionsDB = RetailProfessionsDB or {}
			RetailProfessionsDB.lists = RetailProfessionsDB.lists or {}
			if RetailProfessionsDB.countBank == nil then RetailProfessionsDB.countBank = true end
			if RetailProfessionsDB.showUnlearned == nil then RetailProfessionsDB.showUnlearned = true end
			RetailProfessionsCharDB = RetailProfessionsCharDB or {}
			RetailProfessionsCharDB.tracked = RetailProfessionsCharDB.tracked or {}
			RetailProfessionsCharDB.collapsed = RetailProfessionsCharDB.collapsed or {}
			RetailProfessionsCharDB.favorites = RetailProfessionsCharDB.favorites or {}
		end
	elseif event == "PLAYER_LOGIN" then
		indexProfessions()
		-- With DragonUI's professions window we live in it (Host.lua); otherwise the stock window
		-- only opens when we hand over to it.
		if not RPF.StartHosting() then UIParent:UnregisterEvent("TRADE_SKILL_SHOW") end
		-- Archaeology's skill comes from ArchaeologyUI when it isn't a skill line.
		local A = RPF.ArchaeologyUI()
		if A and A.On then A.On("STATE", function () RPF.Fire("SKILLS") end) end
		RPF.Fire("LOGIN")
		RPF.After(3, RPF.SayHello)
	elseif event == "PLAYER_ENTERING_WORLD" then
		RPF.ForgetWhere()
	elseif event == "TRADE_SKILL_SHOW" then
		onTradeSkillShow()
	elseif event == "TRADE_SKILL_CLOSE" then
		onTradeSkillClose()
	elseif event == "TRADE_SKILL_UPDATE" then
		if RPF.active then RPF.Debounce("tradeskill", 0.05, function () RPF.Fire("TRADE_SKILL_UPDATE") end) end
	elseif event == "TRADE_SKILL_FILTER_UPDATE" then
		if RPF.active then RPF.Debounce("tradeskill", 0.05, RPF.Model.FilterChanged) end
	elseif event == "CHAT_MSG_ADDON" then
		local prefix, message, _, sender = ...
		if prefix == RPF.PREFIX and sender == UnitName("player") then onAddonMessage(message) end
	elseif event == "BAG_UPDATE" then
		RPF.Debounce("bags", 0.25, function () RPF.Fire("BAGS") end)
	elseif event == "SKILL_LINES_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then
		if event == "SKILL_LINES_CHANGED" and GetTime() < ignoreSkillEventsUntil then return end
		RPF.Debounce("skills", 0.3, function () indexProfessions(); RPF.Fire("SKILLS") end)
	elseif event == "SPELL_UPDATE_COOLDOWN" then
		if RPF.active then RPF.Debounce("cooldown", 0.2, function () RPF.Fire("COOLDOWN") end) end
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
		local unit, spellName = ...
		if unit == "player" then RPF.Fire("CAST", event, spellName) end
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- The last moment secure buttons can still be hidden.
		RPF.Fire("COMBAT", true)
	elseif event == "PLAYER_REGEN_ENABLED" then
		RPF.Fire("COMBAT", false)
	end
end)

SLASH_RETAILPROFESSIONS1 = "/retailprofessions"
SLASH_RETAILPROFESSIONS2 = "/rpf"
SLASH_RETAILPROFESSIONS3 = "/prof"
SlashCmdList.RETAILPROFESSIONS = function (msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "classic" then
		RetailProfessionsDB.classic = true
		RPF.Print("the classic profession window opens from now on. |cffffd200/prof retail|r switches back.")
		if RPF.hosting then
			RPF.StopHosting()
		elseif RPF.active then
			showClassic()
		end
	elseif msg == "retail" then
		RetailProfessionsDB.classic = nil
		RPF.Print("the new profession window opens from now on.")
		if RPF.hostClassic then RPF.StartHosting() end
	elseif msg == "reset" then
		RPF.Fire("RESET_POSITION")
		RPF.Print("window positions reset.")
	elseif msg == "tracker" then
		RPF.Fire("TRACKER_TOGGLE_LOCK")
	elseif msg == "log" or msg == "procs" then
		RPF.ProcLog.Toggle()
	elseif msg == "" or msg == "book" then
		RPF.ToggleBook()
	else
		RPF.Print("|cffffd200/prof|r opens your professions. |cffffd200/prof classic|r or |cffffd200/prof retail|r "
			.. "picks the crafting window. |cffffd200/prof log|r shows your Multicraft and Resourcefulness procs. "
			.. "|cffffd200/prof tracker|r unlocks the recipe tracker so you can move it. "
			.. "|cffffd200/prof reset|r moves the windows back.")
	end
end
