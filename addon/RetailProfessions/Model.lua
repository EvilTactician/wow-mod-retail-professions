-- The open profession as data: the client's learned recipes (read once per update with every
-- stock filter cleared and every header expanded, so trade skill indexes stay valid), merged
-- with the server's list of every recipe the profession has, which adds skill-up thresholds,
-- slots and the recipes not learned yet.

local RPF = RetailProfessions
local M = {}
RPF.Model = M

local floor = math.floor

M.recipes = {}   -- learned recipes, in the client's order
M.bySpell = {}   -- spell id -> recipe, learned and unlearned
M.unlearned = {} -- recipes from the server the player doesn't know
M.headers = {}   -- { name, recipes } in the client's order

-- Slot names for the server's inventory types; the strings are the client's own.
local INVTYPES = {
	[1] = "INVTYPE_HEAD", [2] = "INVTYPE_NECK", [3] = "INVTYPE_SHOULDER", [4] = "INVTYPE_BODY",
	[5] = "INVTYPE_CHEST", [6] = "INVTYPE_WAIST", [7] = "INVTYPE_LEGS", [8] = "INVTYPE_FEET",
	[9] = "INVTYPE_WRIST", [10] = "INVTYPE_HAND", [11] = "INVTYPE_FINGER", [12] = "INVTYPE_TRINKET",
	[13] = "INVTYPE_WEAPON", [14] = "INVTYPE_SHIELD", [15] = "INVTYPE_RANGED", [16] = "INVTYPE_CLOAK",
	[17] = "INVTYPE_2HWEAPON", [18] = "INVTYPE_BAG", [19] = "INVTYPE_TABARD", [20] = "INVTYPE_CHEST",
	[21] = "INVTYPE_WEAPONMAINHAND", [22] = "INVTYPE_WEAPONOFFHAND", [23] = "INVTYPE_HOLDABLE",
	[24] = "INVTYPE_AMMO", [25] = "INVTYPE_THROWN", [26] = "INVTYPE_RANGEDRIGHT", [27] = "INVTYPE_QUIVER",
	[28] = "INVTYPE_RELIC", [29] = "RPF_ANY_WEAPON",
}
-- Enchants make no item: the server names the slot from the equipment the spell asks for, with
-- a type of its own for the ones that go on any weapon. A server that doesn't send it yet
-- leaves Enchanting's names to say it ("Enchant Bracer - Minor Health").
local SLOT_NAMES = { RPF_ANY_WEAPON = ENCHSLOT_WEAPON or "Weapon" }
local ENCHANT_NAME_SLOTS = {
	["Bracer"] = "INVTYPE_WRIST", ["Bracers"] = "INVTYPE_WRIST", ["Chest"] = "INVTYPE_CHEST",
	["Cloak"] = "INVTYPE_CLOAK", ["Gloves"] = "INVTYPE_HAND", ["Boots"] = "INVTYPE_FEET",
	["Ring"] = "INVTYPE_FINGER", ["Shield"] = "INVTYPE_SHIELD", ["Weapon"] = "RPF_ANY_WEAPON",
	["2H Weapon"] = "INVTYPE_2HWEAPON", ["Staff"] = "INVTYPE_2HWEAPON",
}
-- Slots in paper-doll order for the filter menu.
M.SLOT_ORDER = { "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CLOAK", "INVTYPE_CHEST",
	"INVTYPE_BODY", "INVTYPE_TABARD", "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_WAIST", "INVTYPE_LEGS",
	"INVTYPE_FEET", "INVTYPE_FINGER", "INVTYPE_TRINKET", "RPF_ANY_WEAPON", "INVTYPE_WEAPON", "INVTYPE_2HWEAPON",
	"INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND", "INVTYPE_SHIELD", "INVTYPE_HOLDABLE", "INVTYPE_RANGED",
	"INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN", "INVTYPE_RELIC", "INVTYPE_AMMO", "INVTYPE_QUIVER", "INVTYPE_BAG" }

function M.SlotName(slot)
	return slot and (SLOT_NAMES[slot] or _G[slot] or slot:gsub("^INVTYPE_", "")) or nil
end

-- How likely a craft is to raise the skill, as the stock window colours it, or as it would
-- colour an unlearned recipe at the player's skill.
M.DIFFICULTY_COLOR = {
	optimal = { 1, 0.5, 0.25 },
	medium = { 1, 1, 0 },
	easy = { 0.25, 0.75, 0.25 },
	trivial = { 0.5, 0.5, 0.5 },
}
M.ARROWS = { optimal = 3, medium = 2, easy = 1, trivial = 0 }

function M.DifficultyAt(recipe, skill)
	-- The client's colour is the truth for what the player knows.
	if recipe.learned and M.DIFFICULTY_COLOR[recipe.difficulty or ""] then return recipe.difficulty end
	if not (recipe.grey and recipe.grey > 0) then return recipe.difficulty end
	if skill >= recipe.grey then return "trivial" end
	if skill >= recipe.green then return "easy" end
	if skill >= recipe.yellow then return "medium" end
	return "optimal"
end

local function hex(c)
	return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end

local DIFFICULTY_TEXT = {
	optimal = "Guaranteed skill-up", medium = "Likely skill-up", easy = "Unlikely skill-up", trivial = "No skill-up",
}

-- The skill-up lines of a recipe's tooltip: the chance this craft raises the skill (as the
-- server works it out, with how many points a skill-up gives) and where the recipe turns
-- yellow, green and grey. For a recipe not learned yet, the skill it needs first.
function RPF.AddSkillUpLines(tip, r)
	-- Herbs and ore (Refine.lua) aren't recipes: no colour, no thresholds.
	if r.refine then return end
	local rank = M.baseRank or M.rank or 0
	local C = M.DIFFICULTY_COLOR
	tip:AddLine(" ")
	if not r.learned then
		local need = r.reqSkill or 0
		tip:AddLine(string.format("Not learned. Needs %s %d (you have %d).", M.skillName or "skill", need, rank),
			1, need > rank and 0.3 or 0.82, need > rank and 0.3 or 0, true)
	end
	local difficulty = M.DifficultyAt(r, rank) or "trivial"
	local chance = not M.linked and r.grey and r.grey > 0 and RPF.SkillUpChance(rank, r.yellow, r.grey)
	if chance and r.learned then
		if chance > 0 then
			local gain = (RPF.skillGain or 1) > 1 and string.format(" |cffb0b0b0(+%d skill)|r", RPF.skillGain) or ""
			tip:AddLine(string.format("Skill-up chance: %s%d%%|r%s", hex(C[difficulty] or C.easy), chance, gain), 1, 1, 1)
		else
			tip:AddLine("No more skill-ups from this recipe.", 0.6, 0.6, 0.6)
		end
	elseif r.learned then
		local c = C[difficulty] or C.trivial
		tip:AddLine(DIFFICULTY_TEXT[difficulty] or "", c[1], c[2], c[3])
	end
	if r.grey and r.grey > 0 then
		tip:AddLine(string.format("Turns %syellow %d|r, %sgreen %d|r, %sgrey %d|r",
			hex(C.medium), r.yellow, hex(C.easy), r.green, hex(C.trivial), r.grey), 0.8, 0.8, 0.8)
	end
	local perks = M.PerksOf(r)
	if perks then tip:AddLine(M.PerksText(perks, true), 0.8, 0.8, 0.8) end
end

-----------------------------------------
-- what knowing a recipe well gives: a chance at a second batch (Multicraft), a chance to get
-- reagents back (Resourcefulness) and a shorter cast. Nothing while the recipe is orange, more
-- from where it turns yellow to where it turns grey, and the most from then on. The server
-- rolls; this is the same sum, for showing.

local MIN_CAST = 0.25
-- The server's caps on mastery and profession equipment together (Gear.lua).
local PERK_CAP = 100
local SPEED_CAP = 90

function M.Mastery(r)
	local rank = M.rank or 0
	local yellow, grey = r.yellow or 0, r.grey or 0
	if rank >= grey then return 1 end
	if rank <= yellow or grey <= yellow then return 0 end
	return (rank - yellow) / (grey - yellow)
end

-- { multicraft = %, resourceful = %, speed = %, castTime = seconds } with only what the recipe
-- can get, or nil when it gets nothing (or isn't yours to craft). The profession's equipment adds
-- its points on top (out.gear: what it added); its skill is in M.rank already.
function M.PerksOf(r)
	local p = RPF.perks
	local bits = r.perks or 0
	if not (p and r.learned and not M.linked and not r.refine and bits > 0) then return nil end
	local mastery = M.Mastery(r)
	local function at(low, high) return low + (high - low) * mastery end
	local out = { mastery = mastery }
	local gear = RPF.Gear.Totals(M.skill)
	local added = {}
	local function plus(key, value, cap)
		local extra = gear and gear[key] or 0
		if extra > 0 then added[key] = extra end
		return math.min(cap, value + extra)
	end
	if bit.band(bits, RPF.PERK_MULTICRAFT) ~= 0 then out.multicraft = plus("multicraft", at(p.multicraftMin, p.multicraftMax), PERK_CAP) end
	if bit.band(bits, RPF.PERK_RESOURCEFUL) ~= 0 then
		out.resourceful = plus("resourcefulness", at(p.resourcefulMin, p.resourcefulMax), PERK_CAP)
	end
	if bit.band(bits, RPF.PERK_SPEED) ~= 0 then
		out.speed = plus("speed", at(p.speedMin, p.speedMax), SPEED_CAP)
		local castTime = r.spell and select(7, GetSpellInfo(r.spell))
		if castTime and castTime > 0 then
			out.castTime = math.max(MIN_CAST, castTime / 1000 * (100 - out.speed) / 100)
		end
	end
	if next(added) then out.gear = added end
	return out
end

local function whole(pct)
	return math.floor(pct + 0.5)
end

-- "Multicraft 18%   Resourcefulness 12%   Cast 1.2 sec"; `plain` leaves the gold out.
function M.PerksText(perks, plain)
	local gold, off = plain and "" or "|cffffd200", plain and "" or "|r"
	local parts = {}
	if perks.multicraft then table.insert(parts, string.format("%sMulticraft%s %d%%", gold, off, whole(perks.multicraft))) end
	if perks.resourceful then table.insert(parts, string.format("%sResourcefulness%s %d%%", gold, off, whole(perks.resourceful))) end
	if perks.castTime then
		table.insert(parts, string.format("%sCast%s %.1f sec", gold, off, perks.castTime))
	elseif perks.speed then
		table.insert(parts, string.format("%sCast%s %d%% faster", gold, off, whole(perks.speed)))
	end
	return table.concat(parts, plain and ", " or "   ")
end

-----------------------------------------
-- reading the client

local scanning = false
local expandTries = 0

-- Clears every stock filter, so the client lists every learned recipe and the indexes we keep
-- are the ones DoTradeSkill expects. A call that changes something fires TRADE_SKILL_FILTER_UPDATE.
local lastReset = -10
function M.ResetClientFilters()
	expandTries = 0
	lastReset = GetTime()
	if SetTradeSkillItemNameFilter then SetTradeSkillItemNameFilter("") end
	if SetTradeSkillItemLevelFilter then SetTradeSkillItemLevelFilter(0, 0) end
	if SetTradeSkillSubClassFilter then SetTradeSkillSubClassFilter(0, 1, 1) end
	if SetTradeSkillInvSlotFilter then SetTradeSkillInvSlotFilter(0, 1, 1) end
	if TradeSkillOnlyShowMakeable then TradeSkillOnlyShowMakeable(false) end
	if TradeSkillOnlyShowSkillUps then TradeSkillOnlyShowSkillUps(false) end
	if ExpandTradeSkillSubClass then ExpandTradeSkillSubClass(0) end
end

local function readReagents(index)
	local reagents = {}
	for r = 1, (GetTradeSkillNumReagents(index) or 0) do
		local name, texture, need = GetTradeSkillReagentInfo(index, r)
		local link = GetTradeSkillReagentItemLink(index, r)
		table.insert(reagents, { name = name, texture = texture, n = need or 1, link = link,
			id = RPF.ItemIdFromLink(link) })
	end
	return reagents
end

local function attachServerData(recipe, info)
	recipe.reqSkill = info.reqSkill
	recipe.trainSkill, recipe.trainLevel = info.trainSkill, info.trainLevel
	recipe.yellow, recipe.green, recipe.grey = info.yellow, info.green, info.grey
	recipe.sources = info.sources
	recipe.recipeItem = info.recipeItem
	recipe.slot = INVTYPES[info.invType]
	recipe.quality = info.quality
	recipe.madeMin, recipe.madeMax = info.madeMin, info.madeMax
	recipe.perks = info.perks
	if info.targetsItem ~= nil then recipe.isEnchant = info.targetsItem end
	if not recipe.item or recipe.item == 0 then recipe.item = info.item end
	-- The client names reagents it hasn't cached as nil; the server always knows the ids.
	if #recipe.reagents == 0 and #info.reagents > 0 then
		for _, rg in ipairs(info.reagents) do table.insert(recipe.reagents, { id = rg.id, n = rg.n }) end
	else
		for i, rg in ipairs(recipe.reagents) do
			if not rg.id and info.reagents[i] then rg.id = info.reagents[i].id end
		end
	end
end

-- The open profession's skill from the Skills tab: M.baseRank as trained, M.bonus what
-- equipment, racials and lures add, M.rank the two together. The core rolls skill-ups and
-- trainers check on the base; perks and gathering go by the sum. Someone else's linked
-- profession only has GetTradeSkillLine's number (rank), less its racial (RPF.RacialBonus).
-- Returns whether any of it changed.
function M.ReadRank(rank)
	local base, bonus = (rank or 0) - (M.racial or 0), M.racial or 0
	if not M.linked and M.profession then
		for _, k in ipairs(RPF.KnownProfessions()) do
			if k.profession == M.profession then base, bonus = k.baseRank, k.rank - k.baseRank end
		end
	end
	local changed = base ~= M.baseRank or bonus ~= M.bonus
	M.baseRank, M.bonus, M.rank = base, bonus, base + bonus
	return changed
end

-- Rebuilds the model from the client's list; returns false while the list isn't ready.
function M.Scan()
	if scanning then return false end
	local name, rank, maxRank = GetTradeSkillLine()
	if not name or name == "UNKNOWN" then return false end

	local count = GetNumTradeSkills() or 0
	-- A collapsed header hides its recipes from the indexes: expand and wait for the update.
	for i = 1, count do
		local _, kind, _, isExpanded = GetTradeSkillInfo(i)
		if kind == "header" and not isExpanded and expandTries < 3 then
			expandTries = expandTries + 1
			ExpandTradeSkillSubClass(0)
			return false
		end
	end

	scanning = true
	M.count = count
	M.racial = RPF.RacialBonus(maxRank)
	M.skillName, M.maxRank = name, (maxRank or 0) - M.racial
	M.profession = RPF.ProfessionByName(name)
	M.skill = M.profession and M.profession.id or nil
	local linked, linkedName = false, nil
	if IsTradeSkillLinked then linked, linkedName = IsTradeSkillLinked() end
	M.linked, M.linkedName = linked and true or false, linkedName
	M.ReadRank(rank)

	local recipes, bySpell, headers = {}, {}, {}
	local header
	for i = 1, count do
		local rname, kind, numAvailable, _, altVerb = GetTradeSkillInfo(i)
		if kind == "header" then
			header = { name = rname, recipes = {} }
			table.insert(headers, header)
		elseif rname then
			if not header then
				header = { name = OTHER or "Other", recipes = {} }
				table.insert(headers, header)
			end
			local recipeLink = GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i) or nil
			local itemLink = GetTradeSkillItemLink(i)
			local recipe = {
				index = i, name = rname, difficulty = kind, numAvailable = numAvailable or 0, altVerb = altVerb,
				spell = RPF.SpellIdFromLink(recipeLink), recipeLink = recipeLink, itemLink = itemLink,
				item = RPF.ItemIdFromLink(itemLink), icon = GetTradeSkillIcon(i), learned = true,
				header = header.name, reagents = readReagents(i),
			}
			-- Cast on an item (enchants): makes nothing, and its link is the spell. Plenty of other
			-- recipes make no item either (research, discoveries), so without the server's word
			-- only Enchanting's and Runeforging's count.
			local makesNothing = not (itemLink and itemLink:find("item:"))
			recipe.isEnchant = makesNothing and (M.skill == 333 or M.skill == 776) or false
			table.insert(recipes, recipe)
			table.insert(header.recipes, recipe)
			if recipe.spell then bySpell[recipe.spell] = recipe end
		end
	end

	-- The server's list adds what the client can't tell.
	local unlearned = {}
	local list = M.skill and RPF.RecipeList(M.skill) or nil
	if list then
		for spell, info in pairs(list) do
			local recipe = bySpell[spell]
			if recipe then
				attachServerData(recipe, info)
			elseif not M.linked then
				local sname, _, sicon = GetSpellInfo(spell)
				if sname then
					local r = {
						spell = spell, name = sname, learned = false, numAvailable = 0, reagents = {},
						item = info.item, icon = (info.item > 0 and RPF.ItemIcon(info.item)) or sicon,
						isEnchant = info.item == 0 and (M.skill == 333 or M.skill == 776),
					}
					attachServerData(r, info)
					table.insert(unlearned, r)
					bySpell[spell] = r
				end
			end
		end
		table.sort(unlearned, function (a, b)
			if a.reqSkill ~= b.reqSkill then return a.reqSkill < b.reqSkill end
			return a.name < b.name
		end)
	end

	-- Slots the client knows for learned items the server didn't describe.
	for _, r in ipairs(recipes) do
		if not r.slot and r.item then
			local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(r.item)
			if equipLoc and equipLoc ~= "" then r.slot = equipLoc == "INVTYPE_ROBE" and "INVTYPE_CHEST" or equipLoc end
		end
	end

	for _, group in ipairs({ recipes, unlearned }) do
		for _, r in ipairs(group) do
			if not r.slot and r.isEnchant then r.slot = ENCHANT_NAME_SLOTS[r.name:match("^Enchant (.-) %- ") or ""] end
		end
	end

	M.recipes, M.bySpell, M.headers, M.unlearned = recipes, bySpell, headers, unlearned
	M.hasServerData = list ~= nil
	scanning = false
	if not M.linked then RPF.Fire("SCANNED") end
	return true
end

-- The client's list no longer matches what we read: clear the filters again (once a second at
-- most, should something keep setting them) and read it again.
function M.Resync()
	if not RPF.active then return end
	if GetTime() - lastReset >= 1 then M.ResetClientFilters() end
	RPF.Debounce("tradeskill", 0.05, function () RPF.Fire("TRADE_SKILL_UPDATE") end)
end

-- TRADE_SKILL_FILTER_UPDATE: a filter changed the client's list, ours or another window's (the
-- stock window re-applies its Have Materials box on every open, DragonUI's filter sets it, a
-- search box sets the name). A narrower list than the one we read is someone else's filter.
function M.FilterChanged()
	if not RPF.active then return end
	if not M.linked and GetTradeSkillLine() == M.skillName and (GetNumTradeSkills() or 0) < (M.count or 0) then
		M.Resync()
	else
		RPF.Fire("TRADE_SKILL_UPDATE")
	end
end

-----------------------------------------
-- counts

-- How many times the player can craft a recipe: from the bags (what Create All can use) and
-- with the reagent bank's units added.
function M.Craftable(recipe)
	if #recipe.reagents == 0 then
		return recipe.learned and recipe.numAvailable or 0, recipe.learned and recipe.numAvailable or 0
	end
	local fromBags, withBank = math.huge, math.huge
	for _, rg in ipairs(recipe.reagents) do
		if not rg.id then
			-- An uncached reagent: trust the client's own count.
			return recipe.numAvailable or 0, recipe.numAvailable or 0
		end
		local bags = GetItemCount(rg.id) or 0
		local bank = RPF.BankCount(rg.id)
		fromBags = math.min(fromBags, floor(bags / rg.n))
		withBank = math.min(withBank, floor((bags + bank) / rg.n))
	end
	if recipe.learned then fromBags = math.min(fromBags, recipe.numAvailable or fromBags) end
	return fromBags, withBank
end

function M.ReagentName(rg)
	if rg.name then return rg.name end
	local info = rg.id and RPF.Item(rg.id)
	return info and info.name or nil
end

-----------------------------------------
-- filtering into display rows

-- Whether a recipe passes the search and the filters in `state` (see M.Rows).
function M.Matcher(state)
	local text = state.text and state.text ~= "" and state.text:lower() or nil
	local rank = M.baseRank or M.rank or 0
	return function (r)
		if state.slot and r.slot ~= state.slot then return false end
		if state.skillUp and M.DifficultyAt(r, rank) == "trivial" then return false end
		if state.haveMats then
			local bags, bank = M.Craftable(r)
			if (RetailProfessionsDB.countBank and bank or bags) <= 0 then return false end
		end
		if text then
			if r.name:lower():find(text, 1, true) then return true end
			for _, rg in ipairs(r.reagents) do
				local n = M.ReagentName(rg)
				if n and n:lower():find(text, 1, true) then return true end
			end
			return false
		end
		return true
	end
end

-- state = { text, haveMats, skillUp, slot, unlearned, learnableOnly, favorites = { [spell] = true } }
-- rows = { { header = name, key, count, collapsed } | { recipe = r } }
function M.Rows(state, collapsed)
	local text = state.text and state.text ~= "" and state.text:lower() or nil
	local rank = M.baseRank or M.rank or 0
	local matches = M.Matcher(state)

	-- A search lists the recipes it found by name before the ones it found by a reagent
	-- ("bolt of runecloth" puts the bolt above everything sewn from it), and the groups holding
	-- a name match before the rest. Otherwise the client's order stands.
	local named = {}
	local groups = {}
	local function addGroup(name, key, list, extra)
		local shown, byName, byReagent = {}, {}, {}
		for _, r in ipairs(list) do
			if matches(r) then
				if text and r.name:lower():find(text, 1, true) then
					table.insert(byName, r)
				else
					table.insert(byReagent, r)
				end
			end
		end
		for _, r in ipairs(byName) do table.insert(shown, r) end
		for _, r in ipairs(byReagent) do table.insert(shown, r) end
		if #shown == 0 then return end
		local group = { name = name, key = key, list = shown, extra = extra }
		table.insert(groups, group)
		named[group] = #byName > 0
	end

	if state.favorites then
		local favorites = {}
		for _, r in ipairs(M.recipes) do if state.favorites[r.spell] then table.insert(favorites, r) end end
		for _, r in ipairs(M.unlearned) do if state.favorites[r.spell] then table.insert(favorites, r) end end
		addGroup(FAVORITES or "Favorites", "fav", favorites)
	end

	for _, h in ipairs(M.headers) do
		addGroup(h.name, "h:" .. h.name, h.recipes)
	end

	if state.unlearned and #M.unlearned > 0 then
		-- Grouped by the skill tier they need, past the player's reach last.
		local cap = RPF.skillCap
		local tiers, order = {}, {}
		for _, r in ipairs(M.unlearned) do
			if not cap or r.reqSkill <= cap then
				if not state.learnableOnly or r.reqSkill <= rank then
					local low, title = RPF.TierOf(r.reqSkill)
					if not tiers[low] then
						tiers[low] = { title = title, list = {} }
						table.insert(order, low)
					end
					table.insert(tiers[low].list, r)
				end
			end
		end
		table.sort(order)
		for _, low in ipairs(order) do
			local t = tiers[low]
			addGroup("Unlearned: " .. t.title, "u:" .. low, t.list, string.format("%d-%d", math.max(1, low), low + 75))
		end
	end

	local order = {}
	if text then
		for _, g in ipairs(groups) do if named[g] then table.insert(order, g) end end
		for _, g in ipairs(groups) do if not named[g] then table.insert(order, g) end end
	else
		order = groups
	end
	local rows = {}
	for _, g in ipairs(order) do
		-- A search opens every group it found something in.
		local isCollapsed = not text and collapsed[g.key] or false
		table.insert(rows, { header = g.name, key = g.key, count = #g.list, collapsed = isCollapsed, extra = g.extra })
		if not isCollapsed then
			for _, r in ipairs(g.list) do table.insert(rows, { recipe = r }) end
		end
	end
	return rows
end

-- Slots that occur among the recipes, for the filter menu.
function M.SlotsPresent()
	local seen = {}
	for _, r in ipairs(M.recipes) do if r.slot then seen[r.slot] = true end end
	for _, r in ipairs(M.unlearned) do if r.slot then seen[r.slot] = true end end
	local out = {}
	for _, slot in ipairs(M.SLOT_ORDER) do if seen[slot] then table.insert(out, slot) end end
	return out
end

-----------------------------------------
-- details of a learned recipe, read when it's selected

function M.Details(recipe)
	if not recipe.learned or not recipe.index then return recipe end
	-- Read only from the recipe's own row. With the client's list changed under us (another
	-- window's filter, the trade skill closed behind the window) the old index is another row or
	-- none, and what it reads would replace the recipe's reagents with nothing until a /reload.
	local i = M.IndexOf(recipe)
	if not i then
		M.Resync()
		return recipe
	end
	recipe.description = GetTradeSkillDescription and GetTradeSkillDescription(i) or nil
	recipe.tools = {}
	-- With profession equipment the client's tool fields are emptied (docs/profession-gear.md):
	-- the server's list says what a recipe needs; the client's until it has come.
	local fromServer = RPF.Gear.Enabled() and M.skill and RPF.Gear.Tools(M.skill) and RPF.Gear.RecipeTools(M.skill, recipe.spell)
	if fromServer then
		recipe.tools = fromServer
	elseif GetTradeSkillTools then
		local t = { GetTradeSkillTools(i) }
		for k = 1, #t, 2 do table.insert(recipe.tools, { name = t[k], has = t[k + 1] and true or false }) end
	end
	recipe.cooldown = GetTradeSkillCooldown and GetTradeSkillCooldown(i) or nil
	local minMade, maxMade = GetTradeSkillNumMade(i)
	recipe.madeMin, recipe.madeMax = minMade or recipe.madeMin or 1, maxMade or recipe.madeMax or 1
	-- None read keeps what the scan and the server's list gave.
	local reagents = readReagents(i)
	if #reagents > 0 then recipe.reagents = reagents end
	local info = M.skill and RPF.RecipeList(M.skill)
	info = info and recipe.spell and info[recipe.spell]
	if info then
		for k, rg in ipairs(recipe.reagents) do
			if not rg.id and info.reagents[k] then rg.id = info.reagents[k].id end
		end
	end
	return recipe
end

-- Whether the player has a tool a recipe needs, as of now: one from the server's list counts
-- from the bags and the profession's slots, and bags change after the recipe was read.
function M.ToolHas(t)
	if t.entries then return RPF.Gear.HasTool(t.entries, t.skill) end
	return t.has
end

-- The client index of a learned recipe, checked against its name: another addon may have
-- changed the stock list since we read it.
function M.IndexOf(recipe)
	if not recipe.learned then return nil end
	local i = recipe.index
	if i and GetTradeSkillInfo(i) == recipe.name then return i end
	for k = 1, GetNumTradeSkills() or 0 do
		local name, kind = GetTradeSkillInfo(k)
		if kind ~= "header" and name == recipe.name then
			recipe.index = k
			return k
		end
	end
	return nil
end
