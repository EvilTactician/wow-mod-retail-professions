-- Training, Profit and Equipment: the tabs at the top of the column on the right, in the spirit
-- of TradeSkillMaster's crafting overview. They look across every profession the character has,
-- not just the open one:
--
--   * Training: your professions with their skill bars, and next to them what to do: what to
--     make next for skill (the leveling guide's recipe, Guides.lua, else the best skill-up you
--     know), recipes waiting at the trainer, the next rank to train, cooldowns that are ready,
--     tracked recipes you now have the materials for, and herbs or ore to mill or prospect,
--   * Profit: every recipe you know that makes money at today's auction prices (Profit.lua),
--     sortable by profit, by what your materials make in all, by how many you can make and by
--     how well it sells,
--   * Equipment: a card for every profession you know that takes gear (Gear.lua), gathering ones
--     and Fishing too, with its slots and what they give. Only on a realm with HELLO_GEAR.
--
-- The client only lists the recipes of the profession that's open, so each visit to a profession
-- leaves a note of the recipes you know (and their cooldowns) per character; the server's recipe
-- list (RPF.RecipeList) fills in the reagents and skill-up thresholds of the others. A profession
-- not opened since this addon came along says so instead.
--
-- Clicking a line opens its recipe. In another profession that means casting the spell that
-- opens it, so those lines carry a secure button (Secure.lua) and the recipe is picked once the
-- window has switched.

local RPF = RetailProfessions
local M = RPF.Model
local P = RPF.Profit
local R = RPF.Refine
local H = {}
RPF.Home = H

local floor = math.floor

local PROF_WIDTH = 220
local PROF_ROWS, PROF_HEIGHT = 12, 32
local TODO_ROWS, TODO_HEIGHT = 11, 36
local CRAFT_ROWS, CRAFT_HEIGHT = 20, 18
-- Equipment's cards: two to a row, each a profession's slots.
local CARD_ROWS, CARD_HEIGHT, CARD_GAP = 6, 60, 6

-- The views, as their tabs, pages and titles show them. `gear`: only while the realm has
-- profession equipment.
H.VIEWS = {
	training = { title = "Training", icon = "Interface\\Icons\\INV_Misc_Book_09",
		tip = "What to do next: skill-ups, the leveling guide, the trainer and cooldowns, across every profession." },
	profit = { title = "Profit", icon = "Interface\\Icons\\INV_Misc_Coin_02",
		tip = "Your most profitable crafts at today's auction prices, across every profession." },
	equipment = { title = "Equipment", icon = "Interface\\Icons\\Ability_Repair", gear = true,
		tip = "Your profession tools and accessories, gathering and Fishing included: what's on and what it gives." },
}
H.ORDER = { "training", "profit", "equipment" }
local HOME_ICON = H.VIEWS.training.icon

-- Whether a view has a tab on this realm.
function H.Shown(key)
	local view = H.VIEWS[key or ""]
	return view and (not view.gear or RPF.Gear.Enabled()) or false
end

-- The level each rank's trainer asks for (Journeyman ... Grand Master).
local TRAIN_LEVEL = { [150] = 10, [225] = 20, [300] = 35, [375] = 50, [450] = 65 }

-- "training", "profit", "equipment" or nil (the recipes).
H.view = nil

-- The view the window shows, or nil: your own professions only, not someone's linked one.
function H.Active()
	return H.view and RPF.WindowOpen() and not M.linked and H.view or nil
end

-- A view's key (true: Training), or false for the recipes.
function H.SetActive(view)
	if view == true then view = "training" end
	view = H.Shown(view) and view or nil
	if H.view == view then return end
	H.view = view
	RPF.Fire("VIEW")
end

function H.Title()
	local view = H.Active()
	return view and H.VIEWS[view].title or nil
end

local function isOpen(skill)
	return RPF.IsOpen() and M.skill == skill and not M.linked
end

local function charDB()
	local db = RetailProfessionsCharDB
	db.homeLearned = db.homeLearned or {}
	db.homeCooldowns = db.homeCooldowns or {}
	return db
end

-----------------------------------------
-- what each profession knows, kept from the last visit

-- After every read of the open profession: its learned recipes, and when the ones on cooldown
-- come off it. A cooldown that's over stays as "ready" until the next craft sets it again.
local function snapshot()
	if M.linked or not M.skill or not RPF.IsOpen() then return end
	local db = charDB()
	local set = {}
	for _, r in ipairs(M.recipes) do
		if r.spell then set[r.spell] = true end
	end
	db.homeLearned[M.skill] = set
	local now = time()
	for _, r in ipairs(M.recipes) do
		local index = r.spell and GetTradeSkillCooldown and M.IndexOf(r)
		local left = index and GetTradeSkillCooldown(index)
		if left and left > 0 then db.homeCooldowns[r.spell] = { at = now + floor(left), skill = M.skill } end
	end
	-- Unlearned (a respec of a profession) or gone: no reminder.
	for spell, cd in pairs(db.homeCooldowns) do
		if cd.skill == M.skill and not set[spell] then db.homeCooldowns[spell] = nil end
	end
end

RPF.On("SCANNED", function () RPF.Debounce("home-snapshot", 0.3, snapshot) end)
RPF.On("COOLDOWN", function () RPF.Debounce("home-snapshot", 0.3, snapshot) end)

local built = {} -- skill -> { set, list, recipes }

-- A recipe of a profession that isn't open, shaped like the model's, from the server's list.
local function fromList(skill, spell, info, learned)
	local name, _, icon = GetSpellInfo(spell)
	local isEnchant = info.targetsItem
	if isEnchant == nil then isEnchant = info.item == 0 and (skill == 333 or skill == 776) end
	local r = {
		spell = spell, name = name or ("#" .. spell), learned = learned, skill = skill, item = info.item,
		icon = (info.item > 0 and RPF.ItemIcon(info.item)) or icon, isEnchant = isEnchant, reagents = {},
		madeMin = info.madeMin, madeMax = info.madeMax, reqSkill = info.reqSkill, sources = info.sources,
		yellow = info.yellow, green = info.green, grey = info.grey, perks = info.perks,
	}
	for _, rg in ipairs(info.reagents) do table.insert(r.reagents, { id = rg.id, n = rg.n }) end
	return r
end

-- The recipes you know in a profession, shaped like the model's: the model's own while it's
-- open, otherwise rebuilt from the note of the last visit and the server's list. nil when the
-- profession hasn't been opened yet, or its list is still on its way (RECIPES fires then).
function H.RecipesOf(skill)
	if isOpen(skill) then return M.recipes end
	local set = charDB().homeLearned[skill]
	if not set then return nil end
	local list = RPF.RecipeList(skill)
	if not list then return nil end
	local cached = built[skill]
	if cached and cached.set == set and cached.list == list then return cached.recipes end
	local recipes = {}
	for spell in pairs(set) do
		local info = list[spell]
		if info then table.insert(recipes, fromList(skill, spell, info, true)) end
	end
	table.sort(recipes, function (a, b) return a.name < b.name end)
	built[skill] = { set = set, list = list, recipes = recipes }
	return recipes
end

local function knows(skill, spell)
	if isOpen(skill) then
		local r = M.bySpell[spell]
		return r and r.learned or false
	end
	local set = charDB().homeLearned[skill]
	return set and set[spell] or false
end

-- Recipes of a profession you don't know yet, from the server's list.
local function unlearnedOf(skill)
	if isOpen(skill) then return M.unlearned end
	local set = charDB().homeLearned[skill]
	local list = set and RPF.RecipeList(skill)
	if not list then return {} end
	local out = {}
	for spell, info in pairs(list) do
		if not set[spell] then
			local name = GetSpellInfo(spell)
			if name then
				table.insert(out, { spell = spell, name = name, reqSkill = info.reqSkill, sources = info.sources })
			end
		end
	end
	return out
end

-- The professions with a window, as the tabs show them, and (second) the professions column's:
-- those, Archaeology, whose window is ArchaeologyUI's, and Herbalism, Skinning and Fishing, which
-- have none (their skill and next rank still show). Kept until skills change or a profession
-- opens: reading them opens and folds the Skills headers.
local professionCache, columnCache
local function professions()
	if professionCache then return professionCache, columnCache end
	local out, column = {}, {}
	if not RetailProfessionsDB then return out, column end
	for _, known in ipairs(RPF.KnownProfessions()) do
		local p = known.profession
		if p.openName and GetSpellInfo(p.openName) then
			table.insert(out, known)
			table.insert(column, known)
		elseif p.archaeology or not p.open then
			table.insert(column, known)
		end
	end
	professionCache, columnCache = out, column
	return out, column
end
RPF.On("SKILLS", function () professionCache = nil end)
RPF.On("SHOW", function () professionCache = nil end)
RPF.On("TRADE_SKILL_UPDATE", function () professionCache = nil end)

local function unitsOf(entry)
	return (GetItemCount(entry) or 0) + (RetailProfessionsDB.countBank and RPF.BankCount(entry) or 0)
end

-----------------------------------------
-- the numbers

-- Every recipe you know that makes money, priced, and the items to ask prices for.
local function crafts(profs)
	local rows, entries, seen = {}, {}, {}
	for _, known in ipairs(profs) do
		local skill = known.profession.id
		for _, r in ipairs(H.RecipesOf(skill) or {}) do
			if not r.isEnchant and r.item and r.item > 0 then
				P.EntriesOf(r, entries, seen)
				local a = P.state == "ok" and P.Of(r)
				if a and a.costKnown and a.profit > 0 then
					local n = math.max(0, P.CanMake(r))
					local price = P.Get(r.item)
					table.insert(rows, { recipe = r, skill = skill, profession = known.profession, a = a, have = n,
						total = a.profit * n, sold = price and not price.locked and price.soldUnits or 0 })
				end
			end
		end
	end
	P.Fetch(entries)
	return rows, entries
end

local SORTS = {
	profit = function (x, y) return x.a.profit > y.a.profit end,
	total = function (x, y) return x.total > y.total end,
	have = function (x, y) return x.have > y.have end,
	sold = function (x, y) return x.sold > y.sold end,
}

local function sortCrafts(rows)
	local key = RetailProfessionsDB.homeSort or "profit"
	local by = SORTS[key] or SORTS.profit
	table.sort(rows, function (x, y)
		if by(x, y) then return true end
		if by(y, x) then return false end
		if x.a.profit ~= y.a.profit then return x.a.profit > y.a.profit end
		return x.recipe.name < y.recipe.name
	end)
end

local function hex(c)
	return string.format("|cff%02x%02x%02x", floor(c[1] * 255), floor(c[2] * 255), floor(c[3] * 255))
end

-- How likely a craft at this skill is to raise it, and the colour the recipe has there.
local FALLBACK_CHANCE = { optimal = 100, medium = 50, easy = 25, trivial = 0 }
local function skillUp(r, rank)
	local chance = RPF.SkillUpChance(rank, r.yellow, r.grey)
	local difficulty
	if r.grey and r.grey > 0 then
		difficulty = rank < r.yellow and "optimal" or rank < r.green and "medium" or rank < r.grey and "easy" or "trivial"
	else
		difficulty = r.difficulty
		chance = chance or FALLBACK_CHANCE[difficulty or ""]
	end
	return chance or 0, difficulty or "trivial"
end

-- The recipe to craft for the next point: one you can make now, the likeliest, the cheapest.
local function bestSkillUp(recipes, rank)
	local best
	for _, r in ipairs(recipes) do
		if not r.refine then
			local chance, difficulty = skillUp(r, rank)
			if chance > 0 then
				local a = P.state == "ok" and P.Of(r) or nil
				local c = { recipe = r, chance = chance, difficulty = difficulty, have = math.max(0, P.CanMake(r)),
					cost = a and a.costKnown and a.cost or nil }
				local better = not best
				if best then
					if (c.have > 0) ~= (best.have > 0) then
						better = c.have > 0
					elseif c.chance ~= best.chance then
						better = c.chance > best.chance
					elseif (c.cost ~= nil) ~= (best.cost ~= nil) then
						better = c.cost ~= nil
					elseif c.cost and c.cost ~= best.cost then
						better = c.cost < best.cost
					else
						better = r.name < best.recipe.name
					end
				end
				if better then best = c end
			end
		end
	end
	return best
end

-----------------------------------------
-- the leveling guide: wow-professions.com's route (Guides.lua), step by step

-- The step `rank` is on, by index: the last one that starts at or below it. Past the end: nil.
local function stepAt(route, rank)
	local at
	for i, step in ipairs(route) do
		if step[1] <= rank then at = i else break end
	end
	if at == #route and rank >= route[at][2] then return nil end
	return at
end

-- A step lasts until the next one starts, when that's later than the guide's own end.
local function stepEnd(route, i)
	local nextStep = route[i + 1]
	return math.max(route[i][2], nextStep and nextStep[1] or 0)
end

-- The crafts of `count` (what the whole step takes) still to make from `rank`.
local function craftsLeft(route, i, rank, count)
	local from, to = route[i][1], stepEnd(route, i)
	if to <= from then return count end
	return math.max(1, math.min(count, math.ceil(count * (to - rank) / (to - from))))
end

-- A recipe on the route, known or not. nil when the realm's list doesn't have it.
local function routeRecipe(skill, spell, byKnown)
	if isOpen(skill) then return M.bySpell[spell] end
	if byKnown[spell] then return byKnown[spell] end
	local list = RPF.RecipeList(skill)
	local info = list and list[spell]
	return info and fromList(skill, spell, info, false) or nil
end

-- Whether making it now can raise the skill: known, or learnable at this skill, and not grey.
-- An era's cap hides the recipes above it, as the recipe list and the trainer line do.
local function raisesSkill(r, rank)
	if not r or r.refine then return false end
	local need = r.reqSkill or 0
	if not r.learned and need > rank then return false end
	if RPF.skillCap and need > RPF.skillCap then return false end
	return (skillUp(r, rank)) > 0
end

-- A recipe on its cooldown (research, transmutes) can't be made now: the open profession says
-- for itself, the others from the note of the last visit.
local function coolingDown(skill, r)
	if isOpen(skill) then return (r.cooldown or 0) > 0 end
	local cd = r.spell and charDB().homeCooldowns[r.spell]
	return cd and cd.at > time() or false
end

-- A step that names no recipe: the ones it describes (a name start, or a reagent they use).
local function describes(step, r)
	if step.prefix and r.name:sub(1, #step.prefix) == step.prefix then return true end
	for _, rg in ipairs(step.reagents and r.reagents or {}) do
		for _, id in ipairs(step.reagents) do
			if rg.id == id then return true end
		end
	end
	return false
end

-- The recipe a step has you make at this skill, and how many. "One of these": the first you know
-- and have the materials for, else the first you know, else the guide's favourite. "In this
-- order": the first whose crafts aren't in your bags yet (they're made now to be used later), for
-- what's still missing. Recipes on their cooldown wait.
local function fromStep(route, i, skill, rank, byKnown)
	local step = route[i]
	if step.count then
		local pool = {}
		for _, r in ipairs(H.RecipesOf(skill) or {}) do
			if r.learned and not r.refine and describes(step, r) then table.insert(pool, r) end
		end
		local best = bestSkillUp(pool, rank)
		if best then return best.recipe, craftsLeft(route, i, rank, step.count) end
		return nil
	end
	local first, known, ready
	for e = 3, #step do
		local count, spell = step[e][1], step[e][2]
		local r = routeRecipe(skill, spell, byKnown)
		local n = count
		if step.seq and r and r.item and r.item > 0 then
			n = count - floor(unitsOf(r.item) / math.max(1, r.madeMin or 1))
		end
		if n > 0 and raisesSkill(r, rank) and not coolingDown(skill, r) then
			local c = { recipe = r, count = step.seq and n or craftsLeft(route, i, rank, count) }
			first = first or c
			if r.learned then
				known = known or c
				if P.CanMake(r) > 0 then ready = ready or c end
			end
			if step.seq then break end
		end
	end
	local c = ready or known or first
	if c then return c.recipe, c.count end
	return nil
end

-- What the guide has you make next: from the step the skill is on, or the next one or two when
-- that step has nothing left to give (its recipes went grey, or this realm doesn't have them).
-- A step that only describes what to make (no recipe of it known yet) comes back on its own.
local function guideFor(skill, rank)
	local route = RPF.Guides and RPF.Guides.routes[skill]
	local i = route and stepAt(route, rank)
	if not i then return nil end
	local byKnown = {}
	for _, r in ipairs(H.RecipesOf(skill) or {}) do
		if r.spell then byKnown[r.spell] = r end
	end
	for j = i, math.min(i + 2, #route) do
		local r, count = fromStep(route, j, skill, rank, byKnown)
		if r then return { route = route, index = j, recipe = r, count = count, skill = skill } end
	end
	if route[i].hint then return { route = route, index = i, skill = skill } end
	return nil
end

-- How to learn a recipe, in a word or two (the recipe pane has the whole story).
local LEARN_FROM = {
	{ RPF.SRC_TRAINER, "a trainer" }, { RPF.SRC_ITEM, "a recipe item" }, { RPF.SRC_QUEST, "a quest" },
	{ RPF.SRC_NPC, "someone in the world" }, { RPF.SRC_DISCOVERY, "a discovery" },
}
local function learnFrom(sources)
	for _, s in ipairs(LEARN_FROM) do
		if bit.band(sources or 0, s[1]) ~= 0 then return s[2] end
	end
	return nil
end

local function guideLine(g, p, rank)
	local r, step = g.recipe, g.route[g.index]
	local sub = string.format("Guide %d-%d", step[1], step[2])
	if step.hint then sub = sub .. " (" .. step.hint .. ")" end
	if r.learned then
		local chance, difficulty = skillUp(r, rank)
		local color = M.DIFFICULTY_COLOR[difficulty] or M.DIFFICULTY_COLOR.easy
		sub = sub .. string.format(": %s%d%%|r per craft", hex(color), chance)
		local have = math.max(0, P.CanMake(r))
		if have > 0 then sub = sub .. string.format(", you can make %d", have) end
	else
		local from = learnFrom(r.sources)
		sub = sub .. ": learn it" .. (from and (" from " .. from) or " first")
	end
	return { icon = r.icon or p.texture, text = string.format("Level %s: %d %s", p.localName, g.count, r.name),
		sub = sub, action = { skill = g.skill, spell = r.spell, count = g.count }, guide = g }
end

-- One step as a line: "25 Elixir of Healing Power", "15 Volatile Healing Potion or 2 more".
local GUIDE_OPTIONS = 2
local function stepText(step)
	if step.count then return string.format("%d of %s", step.count, step.hint) end
	local names = {}
	for e = 3, #step do
		if step.any and #names == GUIDE_OPTIONS then
			table.insert(names, string.format("%d more", #step - e + 1))
			break
		end
		table.insert(names, step[e][1] .. " " .. (GetSpellInfo(step[e][2]) or ("#" .. step[e][2])))
	end
	return table.concat(names, step.any and " or " or ", then ")
end

-- The route from here on, under a guide line's tooltip.
local GUIDE_AHEAD = 6
local function guideTip(g)
	local route = g.route
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Leveling guide from " .. RPF.Guides.SITE, 1, 0.82, 0)
	for i = g.index, math.min(#route, g.index + GUIDE_AHEAD - 1) do
		local step = route[i]
		local c = i == g.index and 1 or 0.65
		GameTooltip:AddLine(string.format("%d-%d  %s", step[1], step[2], stepText(step)), c, c, c, true)
	end
	local r = g.recipe
	if r and #r.reagents > 0 and RPF.HasShoppingList() then
		-- In a profession that isn't open the click still casts its spell, so it opens too.
		local also = isOpen(g.skill) and "" or " (and opens the profession)"
		GameTooltip:AddLine(string.format("Shift-click to put the materials for %d on your shopping list%s.", g.count, also),
			0.5, 0.5, 0.5, true)
	end
end

-- Shift-click on a guide line: what its crafts are short of goes on the shopping list.
function H.Shop(g)
	local r = g and g.recipe
	if not r then return end
	if not RPF.HasShoppingList() then
		RPF.Status("The shopping list comes with the reagent bank (ReagentBankUI).", true)
		return
	end
	-- Without the bank's counts everything in it would look missing.
	if not RPF.BankCountsKnown() then
		RPF.RequestBankSnapshot()
		RPF.Status("Still checking what your reagent bank holds. Try again in a moment.", true)
		return
	end
	if RPF.AddToShoppingList(r, g.count) > 0 then
		RPF.Status(string.format("The materials for %d %s are on your shopping list.", g.count, r.name))
	else
		RPF.Status("You have those materials, or they're on your shopping list already.")
	end
end

-- Several cooldown recipes that share one timer (every transmute) come off it together: one line.
local function readyCooldowns(add, byId)
	local now, groups, order = time(), {}, {}
	for spell, cd in pairs(charDB().homeCooldowns) do
		-- The open profession says for itself: a craft a moment ago may not be noted yet.
		local recipe = isOpen(cd.skill) and M.bySpell[spell]
		local index = recipe and recipe.learned and GetTradeSkillCooldown and M.IndexOf(recipe)
		local left = index and GetTradeSkillCooldown(index)
		if left and left > 0 then cd.at = now + floor(left) end
		if cd.at <= now and byId[cd.skill] and knows(cd.skill, spell) then
			local key = cd.skill .. ":" .. floor(cd.at / 120)
			if not groups[key] then
				groups[key] = { skill = cd.skill, list = {} }
				table.insert(order, key)
			end
			local name, _, icon = GetSpellInfo(spell)
			table.insert(groups[key].list, { spell = spell, name = name or ("#" .. spell), icon = icon })
		end
	end
	table.sort(order)
	for _, key in ipairs(order) do
		local g = groups[key]
		table.sort(g.list, function (a, b) return a.name < b.name end)
		local first = g.list[1]
		local prefix = first.name:match("^(.-):")
		for _, e in ipairs(g.list) do
			if prefix and e.name:match("^(.-):") ~= prefix then prefix = nil end
		end
		local text
		if #g.list == 1 then
			text = first.name .. " is ready"
		elseif prefix then
			text = prefix .. " is ready"
		else
			text = string.format("%s and %d more are ready", first.name, #g.list - 1)
		end
		local p = byId[g.skill].profession
		local recipe = isOpen(g.skill) and M.bySpell[first.spell]
		add({ icon = (recipe and recipe.icon) or first.icon or p.texture, text = text,
			sub = p.localName .. " cooldown is over.", action = { skill = g.skill, spell = first.spell } })
	end
end

local function trackedReady(add, byId)
	for spell, t in pairs(RetailProfessionsCharDB.tracked) do
		if t.skill and byId[t.skill] and t.reagents and #t.reagents > 0 and knows(t.skill, spell) then
			local can = math.huge
			for _, rg in ipairs(t.reagents) do can = math.min(can, floor(unitsOf(rg.id) / math.max(1, rg.n))) end
			local want = t.count or 1
			if can >= want then
				add({ icon = t.icon or byId[t.skill].profession.texture, text = "Craft " .. (t.name or "?"),
					sub = string.format("Tracked: you have the materials for %d.", want),
					action = { skill = t.skill, spell = spell } })
			end
		end
	end
end

-- Where a rank is taught, as lines for the Training line and its tooltip, nearest first:
-- { text, pin = { kind, id, name } }. nil while the server's answer is on its way (or it can't
-- say), {} when nothing teaches it. An answer that comes later redraws Training.
local function sourceText(src, book)
	local at = src.zone ~= "" and ", " .. src.zone or ""
	if src.kind == "T" then return src.name .. " (trainer)" .. at end
	if src.kind == "V" then return (book or "Its book") .. " from " .. src.name .. at end
	if src.kind == "Q" or src.kind == "R" then
		return "Quest: " .. src.name .. ((src.c or "") ~= "" and " from " .. src.c or "") .. at
	end
	return src.name .. at
end

local RANK_SOURCES = { T = true, V = true, N = true, G = true, Q = true, R = true }
local function rankSources(skill, rank)
	local result, now = nil, true
	RPF.WhereToTrain(skill, rank, function (r, err)
		result = r or false
		if not now and (r or err ~= "busy") then RPF.Debounce("home", 0.1, H.Refresh) end
	end)
	now = false
	if not result then return nil end
	local info = RPF.Item(result.recipeItem)
	local lines, far = {}, {}
	for _, src in ipairs(result.rows) do
		if RANK_SOURCES[src.kind] then
			table.insert(lines, { text = sourceText(src, info and info.name), pin = { src.kind, src.id, src.name } })
		elseif src.kind == "L" then
			table.insert(far, { text = src.name .. ", where you can't go yet" })
		end
	end
	for _, line in ipairs(far) do table.insert(lines, line) end
	return lines
end

local function todoFor(add, known)
	local p = known.profession
	local skill, rank, maxRank = p.id, known.rank, known.maxRank
	local cap = math.min(RPF.skillCap or 450, 450)

	-- The next rank: trainers teach it from 25 points short of the cap. Runeforging has none.
	local nextCap = maxRank + 75
	local level = TRAIN_LEVEL[nextCap]
	if level and not p.class and maxRank < cap and known.baseRank >= maxRank - 25 then
		-- Where: the server names the trainer, book or quest (some ranks have only one of them).
		local where = rankSources(skill, nextCap / 75)
		local first = where and where[1]
		local sub
		if first then
			sub = first.text .. ((UnitLevel("player") or 0) < level and string.format(", from level %d", level) or "")
				.. string.format(". You're at %d/%d.", known.baseRank, maxRank)
		elseif (UnitLevel("player") or 0) < level then
			sub = string.format("From level %d, at a %s trainer. You're at %d/%d.", level, p.localName, known.baseRank, maxRank)
		else
			sub = string.format("At a %s trainer. You're at %d/%d.", p.localName, known.baseRank, maxRank)
		end
		add({ icon = p.texture, text = string.format("Train %s %s", RPF.RankTitle(nextCap), p.localName), sub = sub,
			where = where, action = first and first.pin and { pin = first.pin } or { skill = skill } })
	end
	-- Herbalism, Skinning and Fishing: no window, so no recipes; only their next rank.
	if not p.open then return end

	local recipes = H.RecipesOf(skill)
	if not recipes then
		if not charDB().homeLearned[skill] then
			add({ icon = p.texture, text = "Open " .. p.localName .. " once",
				sub = "So Training and Profit know its recipes.", action = { skill = skill } })
		end
		return
	end

	-- Recipes a trainer would teach you now.
	local learnable = {}
	for _, r in ipairs(unlearnedOf(skill)) do
		if bit.band(r.sources or 0, RPF.SRC_TRAINER) ~= 0 and (r.reqSkill or 0) <= rank
				and (not RPF.skillCap or (r.reqSkill or 0) <= RPF.skillCap) then
			table.insert(learnable, r)
		end
	end
	if #learnable > 0 then
		table.sort(learnable, function (a, b)
			if a.reqSkill ~= b.reqSkill then return a.reqSkill > b.reqSkill end
			return a.name < b.name
		end)
		local names = {}
		for i = 1, math.min(2, #learnable) do names[i] = learnable[i].name end
		add({ icon = "Interface\\Icons\\INV_Misc_Book_11",
			text = string.format("%d new %s recipe%s to train", #learnable, p.localName, #learnable == 1 and "" or "s"),
			sub = table.concat(names, ", ") .. (#learnable > 2 and ", ..." or ""),
			action = { skill = skill, spell = learnable[1].spell } })
	end

	-- What to craft for the next skill point: the leveling guide's recipe when it has one here,
	-- else the likeliest skill-up you know. Until the guide's recipe is learned, both show.
	if known.baseRank < maxRank then
		-- The core rolls skill-ups on the skill without bonuses; trainers count them.
		local g = guideFor(skill, known.baseRank)
		local guided = g and g.recipe
		local best = not (guided and guided.learned) and bestSkillUp(recipes, known.baseRank)
		if guided then add(guideLine(g, p, known.baseRank)) end
		if best then
			local color = M.DIFFICULTY_COLOR[best.difficulty] or M.DIFFICULTY_COLOR.easy
			local sub = string.format("%s%d%%|r chance per craft", hex(color), best.chance)
			if best.have > 0 then
				sub = sub .. string.format(", you can make %d", best.have)
			elseif best.cost then
				sub = sub .. ", materials " .. P.Short(best.cost)
			else
				sub = sub .. ", get the materials"
			end
			-- A guide step that only describes what to make, with none of it known: its route still
			-- shows in the tooltip.
			add({ icon = best.recipe.icon or p.texture, text = string.format("Skill up %s: %s", p.localName, best.recipe.name),
				sub = sub, action = { skill = skill, spell = best.recipe.spell }, guide = not guided and g or nil })
		elseif not guided and #learnable == 0 then
			add({ icon = p.texture, text = "No " .. p.localName .. " skill-ups left",
				sub = "Every recipe you know is grey: learn new ones from a trainer, a vendor or a drop.",
				action = { skill = skill } })
		end
	end

	-- Herbs to mill, ore to prospect.
	local kind = p.refine and R.Known(p.refine)
	local sources = kind and R.Sources(p.refine)
	if sources then
		local units, casts = 0, 0
		for _, r in ipairs(sources) do
			if (r.reqSkill or 0) <= rank then
				local n = unitsOf(r.source)
				units = units + n
				casts = casts + floor(n / 5)
			end
		end
		if casts > 0 then
			local noun = p.refine == "M" and "herbs" or "ore"
			add({ icon = kind.texture or p.texture, text = string.format("%s your %s", kind.verb, noun),
				sub = string.format("%d %s, enough to %s %d time%s.", units, noun, kind.verb:lower(), casts, casts == 1 and "" or "s"),
				action = { skill = skill, code = p.refine } })
		end
	end
end

local function todo(profs, column)
	local items = {}
	local function add(item) table.insert(items, item) end
	local byId = {}
	for _, known in ipairs(profs) do byId[known.profession.id] = known end

	readyCooldowns(add, byId)
	trackedReady(add, byId)
	for _, known in ipairs(profs) do todoFor(add, known) end
	-- Herbalism, Skinning and Fishing: only the column has them.
	for _, known in ipairs(column or {}) do
		if not (known.profession.open or known.profession.archaeology) then todoFor(add, known) end
	end
	return items
end

-----------------------------------------
-- the panels: under the skill bar, in place of the list and the recipe, one per view

local function newPanel()
	local panel = CreateFrame("Frame", nil, RPF.content)
	panel:SetPoint("TOPLEFT", RPF.header, "BOTTOMLEFT", 0, -6)
	panel:SetPoint("BOTTOMRIGHT", RPF.content, "BOTTOMRIGHT", 0, 0)
	panel:Hide()
	return panel
end

local trainingPanel, profitPanel, equipmentPanel = newPanel(), newPanel(), newPanel()
H.panels = { training = trainingPanel, profit = profitPanel, equipment = equipmentPanel }

local function showPanel(view)
	-- In DragonUI's window each view is one of its pages (Host.lua).
	if RPF.hosting then
		RPF.ShowHostPage(view)
	else
		for _, pane in ipairs(RPF.panes) do
			if view then pane:Hide() else pane:Show() end
		end
	end
	for key, panel in pairs(H.panels) do
		if key == view then panel:Show() else panel:Hide() end
	end
end

-- A line that does something: itself when its profession is open, through a secure button
-- that casts the profession's spell when it isn't. The caller syncs the buttons once it's done.
local function bindAction(region, action)
	region.action = action
	local p = action and RPF.Profession(action.skill)
	if action and p and p.openName and not isOpen(action.skill) then
		region.button.preClick = function ()
			if IsShiftKeyDown() and region.item and region.item.guide then H.Shop(region.item.guide) end
			H.Pend(action)
		end
		RPF.BindSpellButton(region.button, region, p.openName, RPF.Window(), true)
	else
		region.button.preClick = nil
		RPF.BindSpellButton(region.button, nil, nil, nil, true)
	end
end

-- Picks the recipe; a line from the leveling guide also sets the amount to what its step still
-- needs (an enchant you know stays at one: it goes on one item at a time).
local function openRecipe(action)
	if not RPF.SelectSpell(action.spell) then return end
	local r = RPF.selected
	if action.count and r and not (r.learned and r.isEnchant) then RPF.SetQuantity(action.count) end
end

function H.Run(action)
	if not action then return end
	-- Where a rank is taught: a flag on the map, as the recipe card's sources do.
	if action.pin then
		local kind, id, name = action.pin[1], action.pin[2], action.pin[3]
		RPF.ShowOnMap(kind, id, function (where)
			if where then
				RPF.Print(name .. ": " .. where .. ". Marked on your map when it's on this continent.")
			else
				RPF.Print("Couldn't find " .. name .. " where you can reach it.")
			end
		end)
		return
	end
	local p = RPF.Profession(action.skill)
	if p and p.archaeology then
		RPF.OpenArchaeology()
		return
	end
	if not isOpen(action.skill) then
		if RPF.InCombat() then
			UIErrorsFrame:AddMessage("Professions can't be opened in combat.", 1, 0.1, 0.1)
		end
		return
	end
	H.SetActive(false)
	if action.code then
		R.SetView(action.code)
	elseif action.spell then
		openRecipe(action)
	else
		R.SetView(nil)
	end
end

local function withSecure(region, name, onEnter)
	region:SetScript("OnEnter", function (self) onEnter(self, self) end)
	region:SetScript("OnLeave", RPF.HideItemTooltip)
	region:SetScript("OnClick", function (self)
		if IsShiftKeyDown() and self.item and self.item.guide and self.item.guide.recipe then
			H.Shop(self.item.guide)
			return
		end
		if IsModifiedClick("CHATLINK") and self.link then
			ChatEdit_InsertLink(self.link)
			return
		end
		H.Run(self.action)
	end)
	region.button = RPF.CreateSpellButton(name)
	region.button.onEnter = function (b) onEnter(region, b) end
end

local function rowHighlight(row)
	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	hl:SetBlendMode("ADD")
	hl:SetVertexColor(1, 1, 1, 0.35)
	hl:SetAllPoints(row)
end

local function clickHint(action)
	if not action then return end
	if action.pin then
		GameTooltip:AddLine("Click to mark it on your map.", 0.5, 0.5, 0.5)
		return
	end
	local p = RPF.Profession(action.skill)
	if isOpen(action.skill) then
		GameTooltip:AddLine(action.spell and "Click to open the recipe." or "Click to go there.", 0.5, 0.5, 0.5)
	elseif p and (p.openName or p.archaeology) then
		GameTooltip:AddLine("Click to open " .. p.localName .. ".", 0.5, 0.5, 0.5)
	end
end

-- How many rows a list shows: as many as its scroll frame has room for (DragonUI's window is
-- taller than ours, and the list runs to its bottom), never fewer than `minimum`. Rows are made
-- as the pane grows, but not in combat: their secure buttons can't be shown then.
local function fitRows(scroll, rows, minimum, height, make)
	local fit = math.max(minimum, math.floor((scroll:GetHeight() or 0) / height))
	if not RPF.InCombat() then
		for i = #rows + 1, fit do rows[i] = make(i) end
	end
	return math.min(fit, #rows)
end

local function paneTitle(pane, text)
	local t = pane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	t:SetPoint("TOPLEFT", pane, "TOPLEFT", 10, -9)
	t:SetText(text)
	return t
end

-----------------------------------------
-- Training: your professions on the left, what to do next on the right

local profPane = RPF.CreateInset(trainingPanel)
profPane:SetPoint("TOPLEFT", trainingPanel, "TOPLEFT", 0, 0)
profPane:SetPoint("BOTTOMLEFT", trainingPanel, "BOTTOMLEFT", 0, 0)
profPane:SetWidth(PROF_WIDTH)
paneTitle(profPane, "Professions")

local function profEnter(row, owner)
	local known = row.known
	if not known then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(known.profession.localName .. " - " .. RPF.RankTitle(known.maxRank))
	RPF.AddSkillLines(GameTooltip, known.baseRank, known.rank - known.baseRank, known.maxRank)
	clickHint(row.action)
	GameTooltip:Show()
end

local profRows = {}
local profList = {}
local profScrollName = RPF.UniqueName("HomeProfScroll")
local profScroll = CreateFrame("ScrollFrame", profScrollName, profPane, "FauxScrollFrameTemplate")
profScroll:SetPoint("TOPLEFT", profPane, "TOPLEFT", 4, -28)
profScroll:SetPoint("BOTTOMRIGHT", profPane, "BOTTOMRIGHT", -26, 6)
local drawProfs
-- Before the bar is skinned, as the list of next steps does.
profScroll:SetScript("OnVerticalScroll", function (self, offset)
	FauxScrollFrame_OnVerticalScroll(self, offset, PROF_HEIGHT, function ()
		drawProfs(profList)
		RPF.SyncSpellButtons()
	end)
end)
RPF.SkinScrollBar(profScroll, profScrollName)

local function profRow(i)
	local row = CreateFrame("Button", nil, profPane)
	row:SetHeight(PROF_HEIGHT)
	row:SetPoint("TOPLEFT", profPane, "TOPLEFT", 6, -28 - (i - 1) * PROF_HEIGHT)
	row:SetPoint("RIGHT", profPane, "RIGHT", -6, 0)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(24, 24)
	row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.rank:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -3)
	row.rank:SetJustifyH("RIGHT")
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, 0)
	row.name:SetPoint("RIGHT", row.rank, "LEFT", -4, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.bar = CreateFrame("StatusBar", nil, row)
	row.bar:SetHeight(7)
	row.bar:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 1)
	row.bar:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	if RPF.Dragon() then
		row.bar:SetStatusBarTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
		row.bar:SetStatusBarColor(0.95, 0.6, 0.1)
		local bg = row.bar:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(row.bar)
		bg:SetTexture(0, 0, 0, 0.65)
	else
		RPF.StockSkillBar(row.bar, 7)
	end
	-- The open profession's row stays lit.
	row.lit = row:CreateTexture(nil, "BACKGROUND")
	row.lit:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	row.lit:SetBlendMode("ADD")
	row.lit:SetVertexColor(1, 0.82, 0, 0.3)
	row.lit:SetAllPoints(row)
	rowHighlight(row)
	withSecure(row, "RetailProfessionsHomeProf" .. i, profEnter)
	row:Hide()
	return row
end
for i = 1, PROF_ROWS do profRows[i] = profRow(i) end

-- Every profession you know, scrolling when they don't all fit (a character can know them all).
function drawProfs(profs)
	profList = profs
	local shown = fitRows(profScroll, profRows, PROF_ROWS, PROF_HEIGHT, profRow)
	FauxScrollFrame_Update(profScroll, #profs, shown, PROF_HEIGHT)
	local offset = FauxScrollFrame_GetOffset(profScroll)
	local scrolling = #profs > shown
	for i, row in ipairs(profRows) do
		local known = i <= shown and profs[offset + i] or nil
		row.known = known
		if scrolling then
			row:SetPoint("RIGHT", profScroll, "RIGHT", 0, 0)
		else
			row:SetPoint("RIGHT", profPane, "RIGHT", -6, 0)
		end
		if known then
			local p = known.profession
			row.icon:SetTexture(p.texture)
			row.name:SetText(p.localName)
			row.rank:SetText(RPF.SkillRankText(known.baseRank, known.rank - known.baseRank, known.maxRank))
			row.bar:SetMinMaxValues(0, math.max(1, known.maxRank))
			row.bar:SetValue(known.baseRank)
			if isOpen(p.id) then row.lit:Show() else row.lit:Hide() end
			row:Show()
			bindAction(row, (p.openName or p.archaeology) and { skill = p.id } or nil)
		else
			row:Hide()
			bindAction(row, nil)
		end
	end
end

local todoPane = RPF.CreateInset(trainingPanel)
todoPane:SetPoint("TOPLEFT", profPane, "TOPRIGHT", 6, 0)
todoPane:SetPoint("BOTTOMRIGHT", trainingPanel, "BOTTOMRIGHT", 0, 0)
paneTitle(todoPane, "Next steps")

local todoItems = {}
local todoScrollName = RPF.UniqueName("HomeTodoScroll")
local todoScroll = CreateFrame("ScrollFrame", todoScrollName, todoPane, "FauxScrollFrameTemplate")
todoScroll:SetPoint("TOPLEFT", todoPane, "TOPLEFT", 4, -28)
todoScroll:SetPoint("BOTTOMRIGHT", todoPane, "BOTTOMRIGHT", -26, 6)
local drawTodo
-- Before the bar is skinned: DragonUI hooks this script to move its thumb, and a SetScript
-- after that threw the hook away (the list scrolled, the thumb stayed at the top).
todoScroll:SetScript("OnVerticalScroll", function (self, offset)
	FauxScrollFrame_OnVerticalScroll(self, offset, TODO_HEIGHT, function ()
		drawTodo()
		RPF.SyncSpellButtons()
	end)
end)
RPF.SkinScrollBar(todoScroll, todoScrollName)

local todoEmpty = todoPane:CreateFontString(nil, "OVERLAY", "GameFontDisable")
todoEmpty:SetPoint("TOP", todoPane, "TOP", 0, -60)
todoEmpty:SetWidth(300)

local function todoEnter(row, owner)
	local item = row.item
	if not item then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(item.text, 1, 1, 1, true)
	GameTooltip:AddLine(item.sub, 0.8, 0.8, 0.8, true)
	if item.where and #item.where > 1 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Also taught by:", 1, 0.82, 0)
		for i = 2, math.min(#item.where, 8) do GameTooltip:AddLine(item.where[i].text, 1, 1, 1, true) end
	end
	if item.guide then guideTip(item.guide) end
	clickHint(item.action)
	GameTooltip:Show()
end

local todoRows = {}
local function todoRow(i)
	local row = CreateFrame("Button", nil, todoPane)
	row:SetHeight(TODO_HEIGHT)
	row:SetPoint("TOPLEFT", todoPane, "TOPLEFT", 6, -28 - (i - 1) * TODO_HEIGHT)
	row:SetPoint("RIGHT", todoScroll, "RIGHT", 0, 0)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(26, 26)
	row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.text:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
	row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 1)
	row.sub:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.sub:SetJustifyH("LEFT")
	row.sub:SetWordWrap(false)
	rowHighlight(row)
	withSecure(row, "RetailProfessionsHomeTodo" .. i, todoEnter)
	return row
end
for i = 1, TODO_ROWS do todoRows[i] = todoRow(i) end

function drawTodo()
	local shown = fitRows(todoScroll, todoRows, TODO_ROWS, TODO_HEIGHT, todoRow)
	FauxScrollFrame_Update(todoScroll, #todoItems, shown, TODO_HEIGHT)
	local offset = FauxScrollFrame_GetOffset(todoScroll)
	for i, row in ipairs(todoRows) do
		local item = i <= shown and todoItems[offset + i] or nil
		row.item = item
		if item then
			row.icon:SetTexture(item.icon or HOME_ICON)
			row.text:SetText(item.text)
			row.sub:SetText(item.sub or "")
			row:Show()
		else
			row:Hide()
		end
		bindAction(row, item and item.action)
	end
	if #todoItems == 0 then
		todoEmpty:SetText("Nothing to do right now.")
		todoEmpty:Show()
	else
		todoEmpty:Hide()
	end
end

todoScroll:HookScript("OnSizeChanged", function ()
	if trainingPanel:IsVisible() then
		drawTodo()
		RPF.SyncSpellButtons()
	end
end)

-----------------------------------------
-- Profit: the most profitable crafts, the whole width

local craftPane = RPF.CreateInset(profitPanel)
craftPane:SetPoint("TOPLEFT", profitPanel, "TOPLEFT", 0, 0)
craftPane:SetPoint("BOTTOMRIGHT", profitPanel, "BOTTOMRIGHT", 0, 0)
paneTitle(craftPane, "Most profitable crafts")

local craftRows = {}
local lastEntries = {}
local refreshSoon

local refreshButton = RPF.CreateButton(craftPane, "Refresh", 70, 20)
refreshButton:SetPoint("TOPRIGHT", craftPane, "TOPRIGHT", -8, -5)
refreshButton:SetScript("OnClick", function ()
	P.Fetch(lastEntries, true)
	refreshSoon()
end)
refreshButton:SetScript("OnEnter", function (self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText("Refresh prices")
	GameTooltip:AddLine("Refreshes shared bot reference prices for the items your recipes make and use.", 1, 1, 1, true)
	GameTooltip:Show()
end)
refreshButton:SetScript("OnLeave", function () GameTooltip:Hide() end)

local canMakeCheck = RPF.CreateCheck(craftPane, "Can make now")
canMakeCheck:SetPoint("RIGHT", refreshButton, "LEFT", -86, 0)
canMakeCheck:SetScript("OnClick", function (self)
	RetailProfessionsDB.homeCanMake = self:GetChecked() and true or nil
	refreshSoon()
end)
canMakeCheck:SetScript("OnEnter", function (self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText("Can make now")
	GameTooltip:AddLine("Only the recipes your bags (and reagent bank, when it's counted) have the materials for.", 1, 1, 1, true)
	GameTooltip:Show()
end)
canMakeCheck:SetScript("OnLeave", function () GameTooltip:Hide() end)

-- Columns, from the right edge of a row: { key, label, right offset, width, tooltip }.
local COLUMNS = {
	{ key = "profit", label = "Profit", right = -4, width = 64, tip = "Profit per craft, after the house cut." },
	{ key = "total", label = "In all", right = -80, width = 70,
		tip = "What crafting everything your materials make would earn." },
	{ key = "have", label = "Have", right = -162, width = 40, tip = "How many you can make from what you have." },
	{ key = "sold", label = "Sold", right = -214, width = 40,
		tip = "How many sold on the auction house lately: a quick seller beats a big number that sits." },
}
local NAME_RIGHT = -262

local craftScrollName = RPF.UniqueName("HomeCraftScroll")
local craftScroll = CreateFrame("ScrollFrame", craftScrollName, craftPane, "FauxScrollFrameTemplate")
craftScroll:SetPoint("TOPLEFT", craftPane, "TOPLEFT", 4, -50)
craftScroll:SetPoint("BOTTOMRIGHT", craftPane, "BOTTOMRIGHT", -26, 28)
local drawCrafts
-- Before the bar is skinned, as the Training list's.
craftScroll:SetScript("OnVerticalScroll", function (self, offset)
	FauxScrollFrame_OnVerticalScroll(self, offset, CRAFT_HEIGHT, function ()
		drawCrafts()
		RPF.SyncSpellButtons()
	end)
end)
RPF.SkinScrollBar(craftScroll, craftScrollName)

local columnBar = CreateFrame("Frame", nil, craftPane)
columnBar:SetHeight(16)
columnBar:SetPoint("TOPLEFT", craftPane, "TOPLEFT", 6, -32)
columnBar:SetPoint("RIGHT", craftScroll, "RIGHT", 0, 0)
do
	local name = columnBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	name:SetPoint("LEFT", columnBar, "LEFT", 38, 0)
	name:SetText("Recipe")
end

local headers = {}
for _, col in ipairs(COLUMNS) do
	local b = CreateFrame("Button", nil, columnBar)
	b:SetSize(col.width, 16)
	b:SetPoint("RIGHT", columnBar, "RIGHT", col.right, 0)
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.text:SetAllPoints(b)
	b.text:SetJustifyH("RIGHT")
	b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	b:SetScript("OnClick", function ()
		RetailProfessionsDB.homeSort = col.key
		refreshSoon()
	end)
	b:SetScript("OnEnter", function (self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(col.label)
		GameTooltip:AddLine(col.tip, 1, 1, 1, true)
		GameTooltip:AddLine("Click to sort by it.", 0.5, 0.5, 0.5)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function () GameTooltip:Hide() end)
	b.col = col
	table.insert(headers, b)
end

local summary = craftPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
summary:SetPoint("BOTTOMLEFT", craftPane, "BOTTOMLEFT", 10, 10)
summary:SetPoint("RIGHT", craftPane, "RIGHT", -10, 0)
summary:SetJustifyH("LEFT")
summary:SetWordWrap(false)

local craftEmpty = craftPane:CreateFontString(nil, "OVERLAY", "GameFontDisable")
craftEmpty:SetPoint("TOP", craftPane, "TOP", 0, -80)
craftEmpty:SetWidth(360)

local function craftEnter(row, owner)
	local e = row.entry
	if not e then return end
	local r = e.recipe
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink("item:" .. r.item)
	P.AddTooltipLines(GameTooltip, r)
	GameTooltip:AddLine(e.profession.localName, 0.6, 0.6, 0.6)
	clickHint(row.action)
	RPF.ShowItemTooltip(owner)
end

local craftButtons = {}
local function craftRow(i)
	local row = CreateFrame("Button", nil, craftPane)
	row:SetHeight(CRAFT_HEIGHT)
	row:SetPoint("TOPLEFT", craftPane, "TOPLEFT", 6, -50 - (i - 1) * CRAFT_HEIGHT)
	row:SetPoint("RIGHT", craftScroll, "RIGHT", 0, 0)
	row.prof = row:CreateTexture(nil, "ARTWORK")
	row.prof:SetSize(14, 14)
	row.prof:SetPoint("LEFT", row, "LEFT", 2, 0)
	row.prof:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)
	row.icon:SetPoint("LEFT", row, "LEFT", 19, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", row, "LEFT", 38, 0)
	row.name:SetPoint("RIGHT", row, "RIGHT", NAME_RIGHT, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.cells = {}
	for _, col in ipairs(COLUMNS) do
		local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		cell:SetSize(col.width, CRAFT_HEIGHT)
		cell:SetPoint("RIGHT", row, "RIGHT", col.right, 0)
		cell:SetJustifyH("RIGHT")
		row.cells[col.key] = cell
	end
	rowHighlight(row)
	withSecure(row, "RetailProfessionsHomeCraft" .. i, craftEnter)
	return row
end
for i = 1, CRAFT_ROWS do craftButtons[i] = craftRow(i) end

function drawCrafts()
	local shown = fitRows(craftScroll, craftButtons, CRAFT_ROWS, CRAFT_HEIGHT, craftRow)
	FauxScrollFrame_Update(craftScroll, #craftRows, shown, CRAFT_HEIGHT)
	local offset = FauxScrollFrame_GetOffset(craftScroll)
	for i, row in ipairs(craftButtons) do
		local e = i <= shown and craftRows[offset + i] or nil
		row.entry = e
		if e then
			local r = e.recipe
			row.prof:SetTexture(e.profession.texture)
			row.icon:SetTexture(r.icon or RPF.ItemIcon(r.item) or "Interface\\Icons\\INV_Misc_QuestionMark")
			local info = RPF.Item(r.item)
			local name = info and info.name or r.name
			if info and info.quality then
				local cr, cg, cb = RPF.QualityColor(info.quality)
				row.name:SetTextColor(cr, cg, cb)
			else
				row.name:SetTextColor(1, 1, 1)
			end
			row.name:SetText(name)
			row.link = info and info.link or nil
			row.cells.profit:SetText(P.Signed(e.a.profit))
			row.cells.total:SetText(e.have > 0 and P.Signed(e.total) or "|cff9d9d9d-|r")
			row.cells.have:SetText(e.have > 0 and tostring(e.have) or "|cff9d9d9d0|r")
			row.cells.sold:SetText(e.sold > 0 and tostring(e.sold) or "|cff9d9d9d-|r")
			row:Show()
		else
			row.link = nil
			row:Hide()
		end
		bindAction(row, e and { skill = e.skill, spell = e.recipe.spell })
	end
	local sort = RetailProfessionsDB.homeSort or "profit"
	for _, b in ipairs(headers) do
		b.text:SetText(b.col.key == sort and ("|cffffffff" .. b.col.label .. "|r") or b.col.label)
	end
end

craftScroll:HookScript("OnSizeChanged", function ()
	if profitPanel:IsVisible() then
		drawCrafts()
		RPF.SyncSpellButtons()
	end
end)

-----------------------------------------
-- drawing it all

local function priceText(entries, earn, count)
	if P.state == "missing" then
		return "No auction prices on this realm: profits need mod-retail-ah's server with RetailAH.CraftPrices on."
	end
	if P.state ~= "ok" or P.Fetching() then return "Looking up auction prices..." end
	local age = P.Age(entries)
	local when = age and string.format("Prices from %s ago.", RPF.Duration(age)) or ""
	if count > 0 then
		return string.format("Estimated craft options: %s across %d recipe%s; recipes may share materials. %s", P.Signed(earn), count, count == 1 and "" or "s", when)
	end
	return when
end

local function refreshProfit(rows, entries)
	local earn, count = 0, 0
	for _, row in ipairs(rows) do
		if row.have > 0 then
			earn = earn + row.total
			count = count + 1
		end
	end
	local shown = rows
	if RetailProfessionsDB.homeCanMake then
		shown = {}
		for _, row in ipairs(rows) do if row.have > 0 then table.insert(shown, row) end end
	end
	sortCrafts(shown)
	craftRows = shown
	drawCrafts()
	canMakeCheck:SetChecked(RetailProfessionsDB.homeCanMake and true or false)
	-- Nothing to price: no profession opened yet, or their recipes are on their way.
	summary:SetText(#entries > 0 and priceText(entries, earn, count) or "")
	if #craftRows == 0 then
		if #entries == 0 then
			craftEmpty:SetText("No recipes that make an item yet. Open each profession once so this tab knows its recipes.")
		elseif P.state == "ok" and not P.Fetching() then
			craftEmpty:SetText(RetailProfessionsDB.homeCanMake and "Nothing you can make right now earns money."
				or "Nothing you know earns money at today's prices.")
		else
			craftEmpty:SetText(priceText(entries, 0, 0))
		end
		craftEmpty:Show()
	else
		craftEmpty:Hide()
	end
end

-----------------------------------------
-- Equipment: a card for every profession you know that takes gear (Gear.lua), two to a row:
-- its rank, its slots and what they give. Herbalism, Skinning and Fishing have no window of
-- their own, so this is where theirs go on.

local equipPane = RPF.CreateInset(equipmentPanel)
equipPane:SetAllPoints(equipmentPanel)
paneTitle(equipPane, "Profession Equipment")

local equipHint = equipPane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
equipHint:SetPoint("TOPRIGHT", equipPane, "TOPRIGHT", -12, -11)
equipHint:SetText("Drag gear onto a slot or right-click it in your bags. Right-click a slot to take it off.")

local equipEmpty = equipPane:CreateFontString(nil, "OVERLAY", "GameFontDisable")
equipEmpty:SetPoint("TOP", equipPane, "TOP", 0, -60)
equipEmpty:SetWidth(320)

local CARD_BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local equipList = {}
local equipScrollName = RPF.UniqueName("HomeEquipScroll")
local equipScroll = CreateFrame("ScrollFrame", equipScrollName, equipPane, "FauxScrollFrameTemplate")
equipScroll:SetPoint("TOPLEFT", equipPane, "TOPLEFT", 4, -30)
equipScroll:SetPoint("BOTTOMRIGHT", equipPane, "BOTTOMRIGHT", -26, 6)
local drawEquipment
equipScroll:SetScript("OnVerticalScroll", function (self, offset)
	FauxScrollFrame_OnVerticalScroll(self, offset, CARD_HEIGHT + CARD_GAP, function () drawEquipment() end)
end)
RPF.SkinScrollBar(equipScroll, equipScrollName)

local function equipCard(parent)
	local card = CreateFrame("Frame", nil, parent)
	card:SetHeight(CARD_HEIGHT)
	card:SetBackdrop(CARD_BACKDROP)
	card:SetBackdropColor(0, 0, 0, 0.45)
	card:SetBackdropBorderColor(0.6, 0.5, 0.3, 0.9)
	card.icon = card:CreateTexture(nil, "ARTWORK")
	card.icon:SetSize(38, 38)
	card.icon:SetPoint("LEFT", card, "LEFT", 10, 0)
	card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	card.gear = RPF.Gear.CreateStrip(card, 34, 5)
	card.gear:SetPoint("RIGHT", card, "RIGHT", -10, 0)
	-- The name over the Skills tab's bar with the rank inside it; the slots say the rest.
	card.name = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, -1)
	card.name:SetPoint("RIGHT", card.gear, "LEFT", -12, 0)
	card.name:SetJustifyH("LEFT")
	card.name:SetWordWrap(false)
	card.bar = RPF.SkillTabBar(card)
	card.bar:SetPoint("BOTTOMLEFT", card.icon, "BOTTOMRIGHT", 12, 2)
	if not card.bar.fixedWidth then card.bar:SetPoint("RIGHT", card.gear, "LEFT", -16, 0) end
	card:Hide()
	return card
end

-- A row of two cards, the left one to the middle of the pane and the right one from it.
local cardRows = {}
local function cardRow(i)
	local y = -(i - 1) * (CARD_HEIGHT + CARD_GAP)
	local row = { equipCard(equipPane), equipCard(equipPane) }
	row[1]:SetPoint("TOPLEFT", equipScroll, "TOPLEFT", 4, y)
	row[1]:SetPoint("RIGHT", equipScroll, "CENTER", -CARD_GAP / 2, 0)
	row[2]:SetPoint("TOPLEFT", equipScroll, "TOP", CARD_GAP / 2, y)
	row[2]:SetPoint("RIGHT", equipScroll, "RIGHT", -2, 0)
	return row
end
for i = 1, CARD_ROWS do cardRows[i] = cardRow(i) end

local function drawCard(card, known)
	card.known = known
	if not known then
		card.gear:SetSkill(nil)
		card:Hide()
		return
	end
	local p = known.profession
	card.icon:SetTexture(p.texture)
	card.name:SetText(p.localName)
	card.bar:SetMinMaxValues(0, math.max(1, known.maxRank))
	card.bar:SetValue(known.baseRank)
	card.bar:SetShade(known.baseRank >= known.maxRank)
	card.bar.Caption:SetText(RPF.SkillRankText(known.baseRank, known.rank - known.baseRank, known.maxRank))
	card.gear:SetSkill(p.id)
	card:Show()
end

function drawEquipment()
	equipList = RPF.Gear.Enabled() and RPF.Gear.Known() or {}
	local rows = math.ceil(#equipList / 2)
	local shown = fitRows(equipScroll, cardRows, CARD_ROWS, CARD_HEIGHT + CARD_GAP, cardRow)
	FauxScrollFrame_Update(equipScroll, rows, shown, CARD_HEIGHT + CARD_GAP)
	local offset = FauxScrollFrame_GetOffset(equipScroll)
	for i, row in ipairs(cardRows) do
		local first = (offset + i - 1) * 2 + 1
		local on = i <= shown
		drawCard(row[1], on and equipList[first] or nil)
		drawCard(row[2], on and equipList[first + 1] or nil)
	end
	if not RPF.Gear.Enabled() then
		equipEmpty:SetText("Profession equipment is turned off on this realm.")
		equipEmpty:Show()
	elseif #equipList == 0 then
		equipEmpty:SetText("You don't know a profession that takes equipment.")
		equipEmpty:Show()
	else
		equipEmpty:Hide()
	end
	equipHint:SetText(RPF.Gear.AccountWide() and "Shared by your account. Drag gear onto a slot, right-click a slot to take it off."
		or "Drag gear onto a slot or right-click it in your bags. Right-click a slot to take it off.")
end

local function refresh()
	local view = H.Active()
	if not view then return end
	local profs, column = professions()
	-- Training prices its skill-ups' materials too, so both views ask for prices.
	local rows, entries = crafts(profs)
	lastEntries = entries
	if view == "training" then
		todoItems = todo(profs, column)
		drawProfs(column)
		drawTodo()
	elseif view == "equipment" then
		drawEquipment()
	else
		refreshProfit(rows, entries)
	end
	RPF.SyncSpellButtons()
end
H.Refresh = refresh
-- For the smoke test.
H.rows = { todo = todoRows, crafts = craftButtons, profs = profRows, cards = cardRows }
H.scrolls = { todo = todoScroll, crafts = craftScroll, profs = profScroll, cards = equipScroll }

refreshSoon = function ()
	if H.Active() then RPF.Debounce("home", 0.1, refresh) end
end

-----------------------------------------
-- events

-- A click on a line in another profession: once the window has switched and read it, pick the
-- recipe. Milling and Prospecting land through the refine view's own pending (Refine.lua).
local pending
function H.Pend(action)
	pending = { action = action, at = GetTime() }
	if action.code then R.Pend(action.code) end
end

RPF.On("SHOW", function ()
	if pending and GetTime() - pending.at > 2 then pending = nil end
	-- A profession opens on its recipes.
	if H.view then
		H.view = nil
		RPF.Fire("VIEW")
	end
end)

RPF.On("REBUILT", function ()
	local p = pending
	if not p or M.linked or M.skill ~= p.action.skill then return end
	pending = nil
	if GetTime() - p.at < 5 and p.action.spell then openRecipe(p.action) end
end)

RPF.On("VIEW", function ()
	local view = H.Active()
	showPanel(view)
	if view then refresh() end
end)

for _, event in ipairs({ "PRICES", "BAGS", "RECIPES", "SKILLS", "TRACKED", "YIELDS", "ITEM_INFO", "REBUILT", "GEAR" }) do
	RPF.On(event, refreshSoon)
end

-- Profession gear turned off (an older server, or the server said so): Equipment goes back to
-- Training.
RPF.On("GEAR", function ()
	if H.view == "equipment" and not H.Shown("equipment") then H.SetActive("training") end
end)

-- The window opens on recipes next time.
RPF.On("HIDDEN", function ()
	H.view = nil
	showPanel(nil)
end)
