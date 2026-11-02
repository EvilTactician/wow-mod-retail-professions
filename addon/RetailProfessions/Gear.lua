-- Profession equipment (docs/profession-gear.md): every profession has a tool slot and two
-- accessory slots, each for one kind of accessory (HELLO_GEAR_TYPED; Fishing: a rod slot and a
-- lure slot), kept on the server (for the whole account with HELLO_GEAR_ACCOUNT), whose items
-- give skill and Multicraft,
-- Resourcefulness and crafting speed (or Finesse, Perception and Deftness for gathering), and
-- count as the tools recipes need. With HELLO_GEAR this keeps what the gear items give (the
-- catalog), what sits in the slots and the tools each recipe needs, asks the server to put
-- items on and take them off, names gear items in item tooltips, puts a gear item on when it's
-- right-clicked in the bags, and makes the slot buttons the profession window (Detail.lua), the
-- professions book (Book.lua) and the Equipment tab (Home.lua) show.

local RPF = RetailProfessions
local G = {}
RPF.Gear = G

-- How many slots each skill line has: slot 0 is the tool, the rest accessories. Fishing's
-- first slot is for a rod, on a server with HELLO_GEAR_GATHER (G.SlotCount). With
-- HELLO_GEAR_TYPED Cooking has a third slot and Fishing a lure slot.
G.SLOTS = {
	[171] = 3, [164] = 3, [333] = 3, [202] = 3, [182] = 3, [773] = 3, [755] = 3, [165] = 3, [186] = 3,
	[393] = 3, [197] = 3, [185] = 2, [356] = 1,
}
G.TYPED_SLOTS = { [185] = 3, [356] = 2 }
G.FISHING = 356
G.LURE = 1 -- Fishing's second slot: a stack of lures
-- The gathering tools a slot takes as well: Mining and Skinning need them, from a slot or the bags.
G.GATHER_TOOL = { [186] = "Mining Pick", [393] = "Skinning Knife" }

-- What each accessory slot takes (HELLO_GEAR_TYPED): the kind of item, the same in both tiers.
G.KINDS = {
	[171] = { "Gloves", "Apron" }, [164] = { "Whetstone Kit", "Apron" }, [333] = { "Hood", "Focusing Lens" },
	[202] = { "Headgear", "Gloves" }, [182] = { "Gloves", "Satchel" }, [773] = { "Scroll Case", "Robe" },
	[755] = { "Loupe", "Gem Pouch" }, [165] = { "Mallet", "Gloves" }, [186] = { "Headlamp", "Satchel" },
	[393] = { "Gloves", "Pack" }, [197] = { "Needles", "Apron" }, [185] = { "Hat", "Apron" },
}

-- A skill line's slots on this realm, nil for none.
function G.SlotCount(skill)
	if skill == G.FISHING and not RPF.Has(RPF.HELLO_GEAR_GATHER) then return nil end
	if skill and RPF.Has(RPF.HELLO_GEAR_TYPED) and G.TYPED_SLOTS[skill] then return G.TYPED_SLOTS[skill] end
	return skill and G.SLOTS[skill]
end

-- What an accessory slot takes ("Gloves"), nil for the tool slot or a server without kinds.
function G.KindName(skill, slot)
	if not (slot and slot > 0 and RPF.Has(RPF.HELLO_GEAR_TYPED)) then return nil end
	if skill == G.FISHING then return slot == G.LURE and "Lures" or nil end
	return G.KINDS[skill] and G.KINDS[skill][slot]
end

-- Whether the slots are the whole account's.
function G.AccountWide()
	return RPF.Has(RPF.HELLO_GEAR_ACCOUNT)
end
G.TOOL = 0
G.ANY = 9 -- "the first free slot that fits" in an equip request

-- What the gathering stats work on, per profession (G.StatText).
local GATHERED = {
	[182] = { item = "herb", rare = "Rare finds in an herb", cast = "Gathering herbs" },
	[186] = { item = "ore or stone", rare = "Gems and other rare finds in a vein", cast = "Mining" },
	[393] = { item = "leather or hide", rare = "Scales and other rare finds on a corpse", cast = "Skinning" },
}
local GATHERED_ANY = { item = "gathered item", rare = "Rare finds when gathering", cast = "Gathering" }

-- What a gear item gives besides skill, in percentage points, in tooltip order. text says what
-- it does in plain words: retail's names alone mean nothing on this client.
G.STATS = {
	{ key = "multicraft", label = "Multicraft",
		text = function (n) return string.format("%d%% more chance that a craft makes a second batch.", n) end },
	{ key = "resourcefulness", label = "Resourcefulness",
		text = function (n) return string.format("%d%% more chance to get some of the reagents back.", n) end },
	{ key = "speed", label = "Crafting Speed",
		text = function (n) return string.format("Crafting takes %d%% less time.", n) end },
	{ key = "finesse", label = "Finesse",
		text = function (n, g) return string.format("%d%% chance of one extra %s each time you loot one.", n, g.item) end },
	{ key = "perception", label = "Perception",
		text = function (n, g) return string.format("%s are %d%% more likely to drop.", g.rare, n) end },
	{ key = "deftness", label = "Deftness",
		text = function (n, g) return string.format("%s takes %d%% less time.", g.cast, n) end },
}

-- "Finesse: 4% chance of one extra herb each time you loot one."
function G.StatText(stat, value, skill)
	return string.format("%s: %s", stat.label, stat.text(value, GATHERED[skill] or GATHERED_ANY))
end

-- catalog: gear item -> { skill, kind (0 tool, else an accessory: with HELLO_GEAR_TYPED the
-- slot it goes in), skillBonus, the stats, reqSkill, reqRank }; slots: skill -> slot -> { entry,
-- guid, count }; totals: skill -> what its slots give. An
-- item in a slot that isn't in the catalog is a plain tool: it gives nothing but counts as a tool.
RPF.gear = { catalog = {}, slots = {}, totals = {} }

local serial = 0   -- one per HELLO: answers to an older one are dropped
local off = false  -- the server said gear is turned off

function G.Enabled()
	return RPF.Has(RPF.HELLO_GEAR) and not off
end

-----------------------------------------
-- errors: what the server's refusals mean, in the red error line at the top of the screen

local ERRORS = {
	off = "Profession equipment is turned off on this realm.",
	loading = "Your profession equipment is still loading. Try again in a moment.",
	combat = "You can't change profession equipment in combat.",
	casting = "You can't change profession equipment while casting.",
	trade = "You can't change profession equipment while trading.",
	bot = "Bots can't use profession equipment.",
	noitem = "That item isn't in your bags any more.",
	notgear = "That isn't equipment or a tool for this profession.",
	unlearned = "You don't know that profession.",
	rank = "Your skill in that profession is too low for this item.",
	slot = "That doesn't go in that slot: each slot takes its own kind of equipment.",
	dup = "That item is already in another slot of this profession.",
	full = "The lure slot holds a full stack of that lure already.",
	soulbound = "Soulbound items can't go in your account's slots.",
	bags = "Your bags are full: make room to take it off.",
	empty = "There's nothing in that slot.",
	busy = "The server is busy. Try again in a moment.",
	-- Ours, not the server's.
	frombags = "Drag profession equipment from your bags.",
}

function G.ErrorText(err)
	return ERRORS[err or ""] or ("Couldn't change your profession equipment" .. (err and (" (" .. err .. ")") or "") .. ".")
end

function G.ShowError(err)
	local text = G.ErrorText(err)
	if UIErrorsFrame then UIErrorsFrame:AddMessage(text, 1, 0.1, 0.1, 1) else RPF.Print(text) end
end

-----------------------------------------
-- the catalog and the slots

local function num(v) return tonumber(v) or 0 end

local function sumTotals()
	local gear, totals = RPF.gear, {}
	for skill, slots in pairs(gear.slots) do
		local t = { skillBonus = 0 }
		for _, s in ipairs(G.STATS) do t[s.key] = 0 end
		for _, s in pairs(slots) do
			-- Another profession's gear slotted as a plain tool gives nothing, as on the server.
			local c = gear.catalog[s.entry]
			if c and c.skill == skill then
				t.skillBonus = t.skillBonus + c.skillBonus
				for _, stat in ipairs(G.STATS) do t[stat.key] = t[stat.key] + c[stat.key] end
			end
		end
		totals[skill] = t
	end
	gear.totals = totals
end

-- GD rows: skill, slot, entry, item guid, count. The whole state each time.
local function setSlots(rows)
	local slots = {}
	for _, r in ipairs(rows) do
		local skill, slot, entry = tonumber(r[1]), tonumber(r[2]), tonumber(r[3])
		if skill and slot and entry and entry > 0 then
			slots[skill] = slots[skill] or {}
			slots[skill][slot] = { entry = entry, guid = tonumber(r[4]) or r[4], count = tonumber(r[5]) or 1 }
		end
	end
	RPF.gear.slots = slots
	sumTotals()
	RPF.Fire("GEAR")
end

-- GCD rows: entry, skill, kind, skill bonus, multicraft, resourcefulness, speed, finesse,
-- perception, deftness, required skill line, required rank.
local function setCatalog(rows)
	local catalog = {}
	for _, r in ipairs(rows) do
		local entry = tonumber(r[1])
		if entry then
			catalog[entry] = { skill = num(r[2]), kind = num(r[3]), skillBonus = num(r[4]), multicraft = num(r[5]),
				resourcefulness = num(r[6]), speed = num(r[7]), finesse = num(r[8]), perception = num(r[9]),
				deftness = num(r[10]), reqSkill = num(r[11]), reqRank = num(r[12]) }
		end
	end
	RPF.gear.catalog = catalog
	sumTotals()
	RPF.Fire("GEAR")
end

local function refused(err)
	if err == "off" then
		off = true
		RPF.Fire("GEAR")
	end
end

local function loadCatalog()
	local mine = serial
	RPF.Request("GC", nil, function (result, err)
		if mine ~= serial then return end
		if result then setCatalog(result.rows) else refused(err) end
	end)
end

-- Right after login the server may not have read the slots yet: ask again a few times.
local function loadSlots(tries)
	local mine = serial
	RPF.Request("G", nil, function (result, err)
		if mine ~= serial then return end
		if result then
			setSlots(result.rows)
		elseif err == "loading" and (tries or 0) < 5 then
			RPF.After(2, function () if mine == serial then loadSlots((tries or 0) + 1) end end)
		else
			refused(err)
		end
	end)
end

-- What the server says unasked after every change (equip, unequip, a profession unlearned).
RPF.On("GEAR_PUSH", function (rows) setSlots(rows) end)

-- What a profession's slots give: { skillBonus, multicraft, ... }, or nil when they're empty.
function G.Totals(skill)
	return skill and RPF.gear.totals[skill] or nil
end

-- "+10 skill, Multicraft +5%": what a profession's slots give together, nil for nothing.
function G.TotalsText(skill)
	local t = G.Totals(skill)
	if not t then return nil end
	local parts = {}
	if t.skillBonus > 0 then table.insert(parts, "+" .. t.skillBonus .. " skill") end
	for _, s in ipairs(G.STATS) do
		if t[s.key] > 0 then table.insert(parts, string.format("%s +%d%%", s.label, t[s.key])) end
	end
	return #parts > 0 and table.concat(parts, ", ") or nil
end

function G.Slotted(skill, slot)
	local slots = skill and RPF.gear.slots[skill]
	return slots and slots[slot] or nil
end

-----------------------------------------
-- asking for changes

function G.Equip(bag, bagSlot, skill, slot)
	if not G.Enabled() then return end
	if RPF.InCombat() then G.ShowError("combat") return end
	RPF.Request("GQ", { tostring(bag), tostring(bagSlot), tostring(skill or 0), tostring(slot or G.ANY) },
		function (result, err) if not result then G.ShowError(err) end end)
end

function G.Unequip(skill, slot)
	if not G.Enabled() then return end
	if RPF.InCombat() then G.ShowError("combat") return end
	RPF.Request("GU", { tostring(skill), tostring(slot) }, function (result, err) if not result then G.ShowError(err) end end)
end

-----------------------------------------
-- the tools recipes need: the client patch takes them out of Spell.dbc, so the client can't
-- tell them any more; the server's list replaces GetTradeSkillTools. Asked once per profession
-- and HELLO.

local tools, toolWaiting, toolFailed = {}, {}, {}

-- GTD rows: "T,<key>,<name>,<entry>/<entry>..." a tool and the items that are it, then
-- "S,<spell>,<key>[/<key>]" what a recipe needs.
local function buildTools(rows)
	local defs, spells = {}, {}
	for _, r in ipairs(rows) do
		if r[1] == "T" and r[2] then
			local entries = {}
			for e in tostring(r[4] or ""):gmatch("%d+") do table.insert(entries, tonumber(e)) end
			defs[tostring(r[2])] = { key = tostring(r[2]), name = RPF.Unescape(tostring(r[3] or "-")), entries = entries }
		elseif r[1] == "S" then
			local spell = tonumber(r[2])
			if spell then
				local keys = {}
				for key in tostring(r[3] or ""):gmatch("[^/]+") do table.insert(keys, key) end
				spells[spell] = keys
			end
		end
	end
	return { defs = defs, spells = spells }
end

-- A profession's tools, or nil while they're on their way (GEAR_TOOLS fires then) or when the
-- server has none to give. callback(tools, err) runs once they're known.
function G.Tools(skill, callback)
	if not skill then return nil end
	local cached = tools[skill]
	if cached then
		if callback then callback(cached) end
		return cached
	end
	if toolFailed[skill] or not G.Enabled() then
		if callback then callback(nil, toolFailed[skill] or "off") end
		return nil
	end
	if toolWaiting[skill] then
		if callback then table.insert(toolWaiting[skill], callback) end
		return nil
	end
	toolWaiting[skill] = { callback }
	local mine = serial
	RPF.Request("GT", { tostring(skill) }, function (result, err)
		if mine ~= serial then return end
		local waiting = toolWaiting[skill] or {}
		toolWaiting[skill] = nil
		if result then
			tools[skill] = buildTools(result.rows)
		elseif err ~= "busy" then
			-- Kept, so redraws don't ask again; the next HELLO does.
			toolFailed[skill] = err or "none"
		end
		for _, fn in ipairs(waiting) do fn(tools[skill], err) end
		RPF.Fire("GEAR_TOOLS", skill)
	end)
	return nil
end

-- Whether the player has one of a tool's items: in the bags (or worn), or in a slot of the profession.
function G.HasTool(entries, skill)
	local slotted = skill and RPF.gear.slots[skill] or {}
	for _, e in ipairs(entries or {}) do
		if (GetItemCount(e) or 0) > 0 then return true end
		for _, s in pairs(slotted) do
			if s.entry == e then return true end
		end
	end
	return false
end

-- The tools a recipe needs, as Model.Details keeps them: { name, has, entries, key, skill }; nil
-- while the profession's list isn't known.
function G.RecipeTools(skill, spell)
	local t = skill and tools[skill]
	if not t then return nil end
	local out = {}
	for _, key in ipairs(spell and t.spells[spell] or {}) do
		local def = t.defs[key]
		if def then
			local name = def.name
			if name == "" then
				local info = def.entries[1] and RPF.Item(def.entries[1])
				name = info and info.name or key
			end
			table.insert(out, { name = name, entries = def.entries, key = key, skill = skill,
				has = G.HasTool(def.entries, skill) })
		end
	end
	return out
end

RPF.On("READY", function ()
	serial = serial + 1
	off = false
	tools, toolWaiting, toolFailed = {}, {}, {}
	if not RPF.Has(RPF.HELLO_GEAR) then
		RPF.gear.catalog, RPF.gear.slots, RPF.gear.totals = {}, {}, {}
		RPF.Fire("GEAR")
		return
	end
	loadCatalog()
	loadSlots()
end)

-----------------------------------------
-- the player's skill without gear (what a gear item's requirement is checked against), and the
-- professions that take gear; kept until skills change, as reading them opens the Skills headers

local skillCache, gearProfessions

local function readSkills()
	if skillCache then return end
	-- Not before login: the professions' names aren't known yet.
	if not (RetailProfessionsDB and RPF.Profession(197) and RPF.Profession(197).localName) then return end
	skillCache, gearProfessions = {}, {}
	for _, known in ipairs(RPF.KnownProfessions()) do
		skillCache[known.profession.id] = known
		if G.SlotCount(known.profession.id) then table.insert(gearProfessions, known) end
	end
end

-- The pure skill in a profession (nil when not known).
function G.SkillOf(skill)
	readSkills()
	local known = skillCache and skillCache[skill]
	return known and known.baseRank or nil
end

-- The professions you know that take gear, as RPF.KnownProfessions lists them.
function G.Known()
	readSkills()
	return gearProfessions or {}
end

RPF.On("SKILLS", function () skillCache, gearProfessions = nil, nil end)
-- Which professions take gear depends on what the server has too (Fishing's rod slot).
RPF.On("READY", function () skillCache, gearProfessions = nil, nil end)

-----------------------------------------
-- item tooltips: what a gear item is and gives

local function professionName(skill)
	local p = RPF.Profession(skill)
	return p and (p.localName or p.name) or ("Skill " .. tostring(skill))
end
G.ProfessionName = professionName

-- The client's own "Requires Engineering (150)" line, when the item shows one.
local function findLine(tip, text)
	local name = tip.GetName and tip:GetName()
	if not name or not tip.NumLines then return nil end
	for i = 1, (tip:NumLines() or 0) do
		local fs = _G[name .. "TextLeft" .. i]
		if fs and fs:GetText() == text then return fs end
	end
	return nil
end

-- Lines are added once per item shown: OnTooltipSetItem can come again for the same one.
local done = {}

local function addGearLines(tip)
	if done[tip] then return end
	local _, link = tip:GetItem()
	local entry = RPF.ItemIdFromLink(link)
	local c = entry and RPF.gear.catalog[entry]
	if not c then return end
	done[tip] = true
	local pname = professionName(c.skill)
	local kind = G.KindName(c.skill, c.kind)
	tip:AddLine(pname .. (c.kind == 0 and " Tool" or " Accessory") .. (kind and (": " .. kind) or ""), 1, 0.82, 0)
	if c.skillBonus > 0 then tip:AddLine(string.format("+%d %s Skill", c.skillBonus, pname), 0.1, 1, 0.1) end
	for _, s in ipairs(G.STATS) do
		if c[s.key] > 0 then tip:AddLine("Equip: " .. G.StatText(s, c[s.key], c.skill), 0.1, 1, 0.1, true) end
	end
	if c.reqRank > 0 then
		local reqSkill = c.reqSkill > 0 and c.reqSkill or c.skill
		-- Gear doesn't count towards it, so the client may show its own line white when it's not met.
		local low = (G.SkillOf(reqSkill) or 0) < c.reqRank
		local text = string.format(ITEM_MIN_SKILL or "Requires %s (%d)", professionName(reqSkill), c.reqRank)
		local own = findLine(tip, text)
		if own then
			if low then own:SetTextColor(1, 0.13, 0.13) end
		elseif low then
			tip:AddLine(text, 1, 0.13, 0.13)
		end
	end
	tip:Show()
end

local function hookTooltip(tip)
	if not (tip and tip.HookScript) then return end
	tip:HookScript("OnTooltipSetItem", addGearLines)
	tip:HookScript("OnTooltipCleared", function (self) done[self] = nil end)
end
hookTooltip(GameTooltip)
hookTooltip(ItemRefTooltip)

-----------------------------------------
-- the bags: right-click a gear item to put it on, and which bag item is on the cursor

-- Right-click means something else while one of these is open (sell, deposit, trade, attach).
local BUSY_FRAMES = { "MerchantFrame", "BankFrame", "GuildBankFrame", "TradeFrame", "MailFrame", "AuctionFrame" }

local function busy()
	for _, name in ipairs(BUSY_FRAMES) do
		local f = _G[name]
		if f and f.IsShown and f:IsShown() then return true end
	end
	return false
end

local function bagEntry(bag, slot)
	return RPF.ItemIdFromLink(GetContainerItemLink(bag, slot))
end

-- Gear items have no use and can't be worn, so a right-click does nothing else. Plain tools are
-- left alone: some are weapons or trinkets, which a right-click equips.
hooksecurefunc("UseContainerItem", function (bag, slot)
	bag, slot = tonumber(bag), tonumber(slot)
	if not (bag and slot) or bag < 0 or bag > NUM_BAG_SLOTS then return end
	if not G.Enabled() or RPF.InCombat() or busy() then return end
	local entry = bagEntry(bag, slot)
	if entry and RPF.gear.catalog[entry] then G.Equip(bag, slot, 0, G.ANY) end
end)

local picked -- { bag, slot, entry }: the bag item last picked up, for dropping on a slot

hooksecurefunc("PickupContainerItem", function (bag, slot)
	picked = nil
	if not (CursorHasItem and CursorHasItem()) then return end
	local entry = bagEntry(bag, slot)
	if entry then picked = { bag = bag, slot = slot, entry = entry } end
end)

-- Where the item on the cursor came from, when that was a bag of the player's (not the bank).
local function cursorBagItem()
	local kind, id = GetCursorInfo()
	local p = picked
	if kind ~= "item" or not p or p.entry ~= id then return nil end
	if p.bag < 0 or p.bag > NUM_BAG_SLOTS or bagEntry(p.bag, p.slot) ~= id then return nil end
	return p
end

-----------------------------------------
-- slot buttons: a strip of a profession's slots, used wherever its gear is shown

local strips = {}
local DOLL = "Interface\\PaperDoll\\UI-PaperDoll-Slot-"
local EMPTY = { [0] = DOLL .. "MainHand", DOLL .. "Trinket" }
-- An empty accessory slot shows what goes in it.
local KIND_EMPTY = {
	Gloves = "Hands", Apron = "Chest", Robe = "Chest", Hood = "Head", Headgear = "Head", Headlamp = "Head",
	Hat = "Head", Loupe = "Head", Satchel = "Bag", Pack = "Bag", ["Gem Pouch"] = "Bag", ["Scroll Case"] = "Bag",
	Lures = "Ammo",
}

local function emptyTexture(skill, slot)
	local kind = G.KindName(skill, slot)
	if kind and KIND_EMPTY[kind] then return DOLL .. KIND_EMPTY[kind] end
	return EMPTY[slot] or EMPTY[1]
end

local function refreshButton(b)
	local s = G.Slotted(b.skill, b.slot)
	b.entry = s and s.entry or nil
	if b.entry then
		local info = RPF.Item(b.entry)
		b:SetItem((info and info.texture) or RPF.ItemIcon(b.entry) or "Interface\\Icons\\INV_Misc_QuestionMark", info and info.quality, s.count)
		b.icon:SetAlpha(1)
	else
		b:SetItem(emptyTexture(b.skill, b.slot))
		b.icon:SetAlpha(0.75)
	end
end

-- The item on the cursor goes in the slot; true when there was one.
local function dropOn(b)
	if not (CursorHasItem and CursorHasItem()) then return false end
	local item = cursorBagItem()
	ClearCursor()
	if item then G.Equip(item.bag, item.slot, b.skill, b.slot) else G.ShowError("frombags") end
	return true
end

local function slotEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	local pname = professionName(self.skill)
	local kind = G.KindName(self.skill, self.slot)
	if self.entry then
		-- The tooltip hook above adds what a gear item gives.
		GameTooltip:SetHyperlink("item:" .. self.entry)
		if self.skill == G.FISHING and self.slot == G.LURE then
			GameTooltip:AddLine("Your lures: when you cast Fishing with no lure on your rod, one goes on it from here.", 1, 0.82, 0, true)
		elseif self.skill == G.FISHING then
			GameTooltip:AddLine("Your rod: you fish with it from here, and lures and lines go on it.", 1, 0.82, 0, true)
		elseif not RPF.gear.catalog[self.entry] then
			GameTooltip:AddLine(G.GATHER_TOOL[self.skill] and pname .. " tool: it counts as carried, without taking bag space."
				or pname .. " tool: it counts for the recipes that need it.", 1, 0.82, 0, true)
		end
		GameTooltip:AddLine("Right-click to put it back in your bags.", 0.5, 0.5, 0.5)
	elseif self.skill == G.FISHING and self.slot == G.LURE then
		GameTooltip:SetText("Lure slot")
		GameTooltip:AddLine("Drag a stack of lures here. When you cast Fishing with no lure on your rod, one goes on "
			.. "it from this slot.", 1, 1, 1, true)
	elseif self.skill == G.FISHING then
		GameTooltip:SetText("Fishing rod slot")
		GameTooltip:AddLine("Drag a fishing pole here. You fish with it from this slot, keeping your weapon on, "
			.. "and lures and lines go on it.", 1, 1, 1, true)
	else
		GameTooltip:SetText(self.slot == G.TOOL and "Tool slot" or (kind and (kind .. " slot")) or "Accessory slot")
		if kind then
			GameTooltip:AddLine(string.format("Drag %s accessory here: %s.", pname, kind:lower()), 1, 1, 1, true)
		else
			GameTooltip:AddLine(string.format(self.slot == G.TOOL and "Drag a %s tool here." or "Drag a %s accessory here.", pname),
				1, 1, 1, true)
		end
		GameTooltip:AddLine("A tool a recipe needs (a second one, say) fits in any slot and counts from there. "
			.. "Right-click profession equipment in your bags to put it on.", 0.7, 0.7, 0.7, true)
		if G.GATHER_TOOL[self.skill] and RPF.Has(RPF.HELLO_GEAR_GATHER) then
			GameTooltip:AddLine(string.format("A %s goes in any slot too: it counts as carried.", G.GATHER_TOOL[self.skill]),
				0.7, 0.7, 0.7, true)
		end
	end
	local t = G.TotalsText(self.skill) and G.Totals(self.skill)
	if t then
		GameTooltip:AddLine("Your " .. pname .. " equipment:", 0.31, 0.76, 0.97)
		if t.skillBonus > 0 then GameTooltip:AddLine(string.format("+%d %s Skill", t.skillBonus, pname), 0.31, 0.76, 0.97) end
		for _, s in ipairs(G.STATS) do
			if t[s.key] > 0 then GameTooltip:AddLine(G.StatText(s, t[s.key], self.skill), 0.31, 0.76, 0.97, true) end
		end
	end
	if G.AccountWide() then GameTooltip:AddLine("Shared by every character on your account.", 0.5, 0.5, 0.5, true) end
	RPF.ShowItemTooltip(self)
end

local function slotButton(parent, size)
	local b = RPF.CreateItemButton(parent, size)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	-- What an empty slot sits on, as the Enchant slot has.
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 2)
	bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
	bg:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
	bg:SetTexCoord(0.15, 0.85, 0.15, 0.85)
	b:SetScript("OnReceiveDrag", dropOn)
	b:SetScript("OnClick", function (self, button)
		if dropOn(self) then return end
		if not self.entry then return end
		if button == "RightButton" then
			G.Unequip(self.skill, self.slot)
		elseif IsModifiedClick("CHATLINK") then
			local info = RPF.Item(self.entry)
			if info and info.link then ChatEdit_InsertLink(info.link) end
		end
	end)
	b:SetScript("OnEnter", slotEnter)
	b:SetScript("OnLeave", RPF.HideItemTooltip)
	return b
end

-- A row of a profession's slot buttons, `size` square and `gap` apart. strip:SetSkill(skill)
-- shows that profession's (hidden for one without gear, or a realm without it); it redraws
-- itself when the gear changes. Its width follows the number of slots.
function G.CreateStrip(parent, size, gap)
	local strip = CreateFrame("Frame", nil, parent)
	strip:SetSize(3 * size + 2 * gap, size)
	strip.buttons = {}
	for i = 1, 3 do
		local b = slotButton(strip, size)
		b.slot = i - 1
		b:SetPoint("LEFT", strip, "LEFT", (i - 1) * (size + gap), 0)
		strip.buttons[i] = b
	end
	function strip:SetSkill(skill)
		self.skill = skill
		self:Refresh()
	end
	function strip:Refresh()
		local n = G.SlotCount(self.skill)
		if not (n and G.Enabled()) then
			self:Hide()
			return
		end
		self:SetWidth(n * size + (n - 1) * gap)
		for i, b in ipairs(self.buttons) do
			b.skill = self.skill
			if i <= n then
				refreshButton(b)
				b:Show()
			else
				b:Hide()
			end
		end
		self:Show()
	end
	strip:Hide()
	table.insert(strips, strip)
	return strip
end

local function refreshStrips()
	for _, strip in ipairs(strips) do
		if strip.skill then strip:Refresh() end
	end
end
RPF.On("GEAR", refreshStrips)
RPF.On("ITEM_INFO", refreshStrips)
