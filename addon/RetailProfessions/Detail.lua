-- The selected recipe, laid out like retail's: a round icon with the name, a favorite star and
-- what it requires (tools, a fire, a forge) beside it, the profession's equipment slots (Gear.lua)
-- at the top right, how likely it is to raise your skill (a bar showing where it turns yellow,
-- green and grey and where you are), the reagents with what
-- you have, what the chosen amount is still short of with a button that puts it on the auction
-- house shopping list, and for a recipe you haven't learned, where to learn it. A herb to mill
-- or ore to prospect (Refine.lua) shows what it gives instead. A faint picture of the profession
-- sits behind it all (with DragonUI's professions art, the card's drawing of it).

local RPF = RetailProfessions
local M = RPF.Model

local pane = RPF.detailPane
local PAD = 14
-- With DragonUI's professions art the pane is its recipe card, drawing included: no watermark,
-- the recipe icon in its ring (by quality) and its favorite star.
local art = RPF.frame.profArt
local OUTPUT_RINGS = { [0] = "ring-gray", [2] = "ring-green", [3] = "ring-blue", [4] = "ring-purple", [5] = "ring-orange" }
local REAGENT_TEXT_WIDTH = 320
local MAX_REAGENTS = 8
local MAX_SOURCES = 9

local function label(parent, font, r, g, b)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	fs:SetJustifyH("LEFT")
	if r then fs:SetTextColor(r, g, b) end
	return fs
end

-- How many lines of `height` fit under a region, above the options along the pane's bottom
-- edge (Frame.lua): what the pane lists there stops short of them, however much is above it.
-- `most` while the pane has no place on screen yet.
local function linesFit(region, gap, height, most)
	local top, floor = region:GetBottom(), pane:GetBottom()
	if not top or not floor then return most end
	return math.max(0, math.min(most, math.floor((top - gap - floor - RPF.DetailReserve()) / height + 0.01)))
end

-- Where a reagent comes from, at a glance: a small picture after its name.
local SOURCE_ICON = {
	craft = GetItemIcon(6219) or "Interface\\Icons\\INV_Misc_Wrench_01", -- Arclight Spanner
	drop = GetItemIcon(4240) or "Interface\\Icons\\INV_Misc_Bag_10",     -- Woolen Bag
	vendor = "Interface\\Icons\\INV_Misc_Coin_01",
}
local BADGE = 14

local function itemTooltip(owner, link)
	if not link then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink(link)
	RPF.ShowItemTooltip(owner)
end

local function linkOrNothing(link)
	if link and IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(link) return true end
	return false
end

-----------------------------------------
-- top: icon, name, what it makes

-- The profession's picture, very faint, behind the recipe.
local watermark = pane:CreateTexture(nil, "BACKGROUND", nil, 2)
watermark:SetSize(170, 170)
watermark:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -30, 40)
watermark:SetDesaturated(true)
watermark:SetAlpha(0.07)

-- Round icon with a glow in the item's quality colour.
local icon = CreateFrame("Button", nil, pane)
icon:SetSize(46, 46)
icon:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -PAD)
icon.texture = icon:CreateTexture(nil, "ARTWORK")
icon.texture:SetAllPoints(icon)
icon.glow = icon:CreateTexture(nil, "OVERLAY")
icon.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
icon.glow:SetBlendMode("ADD")
icon.glow:SetSize(84, 84)
icon.glow:SetPoint("CENTER", icon, "CENTER")
if art then
	icon.glow:Hide()
	icon.ring = icon:CreateTexture(nil, "OVERLAY")
	icon.ring:SetPoint("CENTER", icon, "CENTER")
end
icon:SetScript("OnEnter", function (self)
	itemTooltip(self, self.link)
	if RPF.selected then
		RPF.AddSkillUpLines(GameTooltip, RPF.selected)
		RPF.ShowItemTooltip(self)
	end
end)
icon:SetScript("OnLeave", RPF.HideItemTooltip)
icon:SetScript("OnClick", function (self) linkOrNothing(self.link) end)

local nameText = label(pane, "GameFontNormalLarge")
nameText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -4)

-- Favorites go to the top of the list.
local star = CreateFrame("Button", nil, pane)
star:SetSize(16, 16)
star:SetPoint("LEFT", nameText, "RIGHT", 6, 0)
star.texture = star:CreateTexture(nil, "ARTWORK")
star.texture:SetAllPoints(star)
star.texture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
-- DragonUI's star is 20 x 18.
if art then star:SetSize(20, 18) end
star:SetScript("OnClick", function ()
	local r = RPF.selected
	if r and r.spell then RPF.ToggleFavorite(r.spell) end
end)
star:SetScript("OnEnter", function (self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(RPF.selected and RPF.IsFavorite(RPF.selected.spell) and "Remove from favorites" or "Add to favorites")
	GameTooltip:Show()
end)
star:SetScript("OnLeave", function () GameTooltip:Hide() end)

-- The open profession's tool and accessory slots (Gear.lua), level with the name: they're the
-- profession's, so they stay whatever recipe is picked, or none.
local gearStrip = RPF.Gear.CreateStrip(pane, 26, 4)
gearStrip:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -PAD, -10)
RPF.gearStrip = gearStrip

-- A long name stops short of the slots, the star after it.
nameText:SetWordWrap(false)
local function fitName()
	nameText:SetWidth(0)
	if not gearStrip:IsShown() then return end
	local room = (pane:GetWidth() or 0) - PAD - 46 - 12 - 26 - gearStrip:GetWidth() - PAD
	if room > 80 and (nameText:GetStringWidth() or 0) > room then nameText:SetWidth(room) end
end

local subText = label(pane, "GameFontHighlightSmall")
subText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -5)
subText:SetPoint("RIGHT", pane, "RIGHT", -PAD, 0)

-- Multicraft, Resourcefulness and the cast time at your skill (Model.lua); hover for what they are.
local perkLine = CreateFrame("Button", nil, pane)
perkLine:SetHeight(14)
perkLine:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -10)
perkLine:SetPoint("RIGHT", pane, "RIGHT", -PAD, 0)
perkLine.text = label(perkLine, "GameFontHighlightSmall")
perkLine.text:SetAllPoints(perkLine)
perkLine:SetScript("OnEnter", function (self)
	local perks, p = self.perks, RPF.perks
	if not (perks and p) then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText("Knowing a recipe well")
	GameTooltip:AddLine("Nothing while a recipe is orange, more from where it turns yellow to where it turns grey, "
		.. "and the most from then on.", 1, 1, 1, true)
	if perks.multicraft then
		GameTooltip:AddLine(string.format("|cffffd200Multicraft|r  a chance that a craft makes a second batch (%d%% to %d%%).",
			p.multicraftMin, p.multicraftMax), 0.8, 0.8, 0.8, true)
	end
	if perks.resourceful then
		GameTooltip:AddLine(string.format("|cffffd200Resourcefulness|r  a chance (%d%% to %d%%) to get %d%% of the "
			.. "reagents back, on average.", p.resourcefulMin, p.resourcefulMax, p.refund), 0.8, 0.8, 0.8, true)
	end
	if perks.speed then
		GameTooltip:AddLine(string.format("|cffffd200Cast|r  %d%% to %d%% faster.", p.speedMin, p.speedMax), 0.8, 0.8, 0.8, true)
	end
	-- What the profession's equipment adds on top (Gear.lua).
	local gear = perks.gear
	if gear then
		local parts = {}
		if gear.multicraft then table.insert(parts, "Multicraft +" .. gear.multicraft .. "%") end
		if gear.resourcefulness then table.insert(parts, "Resourcefulness +" .. gear.resourcefulness .. "%") end
		if gear.speed then table.insert(parts, "Cast " .. gear.speed .. "% faster") end
		GameTooltip:AddLine("Your " .. (M.skillName or "") .. " equipment: " .. table.concat(parts, ", ") .. ", included above.",
			0.31, 0.76, 0.97, true)
	end
	GameTooltip:Show()
end)
perkLine:SetScript("OnLeave", function () GameTooltip:Hide() end)

local description = label(pane, "GameFontHighlightSmall", 0.8, 0.8, 0.8)
description:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -10)
description:SetPoint("RIGHT", pane, "RIGHT", -PAD, 0)

local empty = label(pane, "GameFontDisable")
empty:SetPoint("CENTER", pane, "CENTER")
empty:SetText("Pick a recipe on the left.")

-- Where the reagents start: under the description.
local reagentAnchor = CreateFrame("Frame", nil, pane)
reagentAnchor:SetSize(1, 1)

-----------------------------------------
-- reagents: two columns of icon, name and have/need

local reagentTitle = label(pane, "GameFontNormalSmall")
reagentTitle:SetText((SPELL_REAGENTS or "Reagents:"):gsub("%s+$", ""))
reagentTitle:SetPoint("TOPLEFT", reagentAnchor, "TOPLEFT", 0, 0)

-- One column: icon, then "have/need Name", and what the reagent bank holds.
local reagentSlots = {}
for i = 1, MAX_REAGENTS do
	local slot = RPF.CreateItemButton(pane, 30)
	slot:SetPoint("TOPLEFT", reagentTitle, "BOTTOMLEFT", 0, -6 - (i - 1) * 34)
	slot.name = label(pane, "GameFontHighlightSmall")
	slot.name:SetPoint("LEFT", slot, "RIGHT", 8, 0)
	slot.name:SetWidth(REAGENT_TEXT_WIDTH)
	slot.have = slot.name -- one line holds both
	-- Where it comes from: a small picture after the name. Hovering it tells every source,
	-- clicking it does what clicking the reagent does.
	local badge = CreateFrame("Button", nil, pane)
	badge:SetSize(BADGE, BADGE)
	badge.icon = badge:CreateTexture(nil, "OVERLAY")
	badge.icon:SetAllPoints(badge)
	badge.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	-- owner: the secure button over it when the click opens another profession.
	badge:SetScript("OnEnter", function (self, owner)
		GameTooltip:SetOwner(type(owner) == "table" and owner or self, "ANCHOR_RIGHT")
		RPF.ReagentBadgeTooltip(GameTooltip, slot)
		GameTooltip:Show()
	end)
	badge:SetScript("OnLeave", function () GameTooltip:Hide() end)
	badge:SetScript("OnClick", function ()
		if linkOrNothing(slot.link) then return end
		RPF.ReagentSourceAct(slot.source, slot.itemName)
	end)
	badge:Hide()
	slot.badge = badge
	-- owner: the secure button over the slot when another profession makes the reagent.
	slot:SetScript("OnEnter", function (self, owner)
		-- From the slot itself the second argument is the client's "motion" flag, not a frame.
		itemTooltip(type(owner) == "table" and owner or self, self.link)
		if self.link and self.source then
			RPF.ReagentSourceLines(GameTooltip, self.source)
			GameTooltip:Show()
		end
	end)
	slot:SetScript("OnLeave", RPF.HideItemTooltip)
	-- As on retail: a reagent this profession makes opens its recipe, and a click does what its
	-- source offers (the nearest vendor on the map, where to gather it). One another profession
	-- makes opens that one through the secure button over the slot; this only runs in combat then.
	slot:SetScript("OnClick", function (self)
		if linkOrNothing(self.link) then return end
		RPF.ReagentSourceAct(self.source, self.itemName)
	end)
	slot.Hide2 = function (self)
		self:Hide()
		self.name:Hide()
		self.badge:Hide()
		self.other, self.source, self.sources = nil, nil, nil
	end
	slot.Show2 = function (self) self:Show(); self.name:Show() end
	reagentSlots[i] = slot
end

local noReagents = label(pane, "GameFontDisableSmall")
noReagents:SetPoint("TOPLEFT", reagentTitle, "BOTTOMLEFT", 0, -6)
noReagents:SetText("No reagents.")

-- The recipe of this profession that makes an item, a learned one first.
local function recipeMaking(id)
	if not id then return nil end
	local found
	for spell, r in pairs(M.bySpell) do
		if r.item == id then
			if r.learned then return spell end
			found = found or spell
		end
	end
	return found
end

-- A recipe you know in another profession you've opened before (Home.lua keeps what each
-- knows) that makes an item: { skill, spell, name }.
local function otherRecipeMaking(id)
	if not id or not RPF.Home then return nil end
	for skill in pairs(RetailProfessionsCharDB.homeLearned or {}) do
		local p = skill ~= M.skill and RPF.Profession(skill)
		-- Still known: the spell that opens it resolves by name only then.
		if p and p.openName and GetSpellInfo(p.openName) then
			for _, r in ipairs(RPF.Home.RecipesOf(skill) or {}) do
				if r.item == id then return { skill = skill, spell = r.spell, name = p.localName } end
			end
		end
	end
	return nil
end

-- Opening another profession is a cast: a secure button over the slot, made when first needed
-- (Secure.lua loads after this file). The lines under "Get the reagents" take one the same way.
local function bindOther(slot)
	local p = slot.other and RPF.Profession(slot.other.skill)
	if p then
		if not slot.button then
			local b = RPF.CreateSpellButton(nil)
			b:SetAttribute("shift-type1", "none") -- shift-click links the reagent instead
			b.onEnter = function (self) slot:GetScript("OnEnter")(slot, self) end
			b.preClick = function ()
				if linkOrNothing(slot.link) or not slot.other then return end
				RPF.Home.Pend({ skill = slot.other.skill, spell = slot.other.spell, code = slot.other.code,
					item = slot.other.item })
			end
			slot.button = b
		end
		RPF.BindSpellButton(slot.button, slot, p.openName, RPF.Window(), true)
	elseif slot.button then
		RPF.BindSpellButton(slot.button, nil, nil, nil, true)
	end
end

local function drawReagents(r)
	local shown = 0
	-- The pane is narrower in DragonUI's window (Host.lua); the names stay inside it.
	-- The badge (where it comes from) goes after the name.
	local nameWidth = math.min(REAGENT_TEXT_WIDTH, math.max(120, (pane:GetWidth() or 0) - 2 * PAD - 38 - BADGE - 6))
	for i, slot in ipairs(reagentSlots) do
		slot.name:SetWidth(nameWidth)
		local rg = r.reagents[i]
		if rg then
			shown = i
			local info = rg.id and RPF.Item(rg.id)
			local link = rg.link or (info and info.link) or (rg.id and ("item:" .. rg.id))
			slot.link = link
			slot.makes = recipeMaking(rg.id)
			slot.craftOther = not slot.makes and not M.linked and otherRecipeMaking(rg.id) or nil
			slot:SetItem(rg.texture or (info and info.texture) or RPF.ItemIcon(rg.id), info and info.quality)
			local reagentName = M.ReagentName(rg) or ("Item #" .. tostring(rg.id or "?"))
			local bags = rg.id and GetItemCount(rg.id) or 0
			local bank = rg.id and RPF.BankCount(rg.id) or 0
			local text
			if bags >= rg.n then
				text = string.format("|cffffffff%d/%d|r", bags, rg.n)
			elseif bags + bank >= rg.n and RetailProfessionsDB.countBank then
				text = string.format("|cffffd200%d/%d|r", bags, rg.n)
			else
				text = string.format("|cffff4040%d/%d|r", bags, rg.n)
			end
			text = text .. " " .. reagentName
			if bank > 0 then text = text .. string.format("  |cff4fc3f7+%d in bank|r", bank) end
			slot.name:SetText(text)
			slot.itemName = reagentName
			slot.badge:ClearAllPoints()
			slot.badge:SetPoint("LEFT", slot.name, "LEFT", math.min(slot.name:GetStringWidth() or 0, nameWidth) + 6, 0)
			slot:Show2()
		else
			slot:Hide2()
		end
	end
	if shown == 0 then noReagents:Show() else noReagents:Hide() end
	return math.max(1, shown)
end

-----------------------------------------
-- shopping list: what the amount in the window is short of, bags and reagent bank together,
-- and a button that puts it on ReagentBankUI's auction house shopping list. Recipes you haven't
-- learned yet have one too, so the materials can be bought before the recipe.

local SHOP_BUTTON_WIDTH = 150

local shopRow = CreateFrame("Frame", nil, pane)
shopRow:SetHeight(22)

local shopButton = RPF.CreateButton(shopRow, "Add to Shopping List", SHOP_BUTTON_WIDTH, 22)
shopButton:SetPoint("TOPLEFT", shopRow, "TOPLEFT", 0, 0)

-- Its width is set outright (in drawShopping), so its wrapped height is known as soon as the
-- text is set and the row can make room for it.
local shopText = label(shopRow, "GameFontHighlightSmall")
shopText:SetPoint("TOPLEFT", shopButton, "TOPRIGHT", 8, -1)
shopText:SetJustifyV("TOP")

-- What the bags and the reagent bank are short of, named in the line's tooltip.
local shopShort, shopCount = {}, 1

local function shortEntries(short)
	local entries = {}
	for _, part in ipairs(short) do table.insert(entries, part.rg.id) end
	return entries
end

local function onListTotal(short)
	local total = 0
	for _, part in ipairs(short) do total = total + RPF.OnShoppingList(part.rg.id) end
	return total
end

-- Draws under `anchor` and returns what comes next should hang from.
local function drawShopping(r, anchor)
	local count = RPF.GetQuantity()
	local short = not r.refine and not M.linked and RPF.HasShoppingList() and RPF.ShortFor(r, count) or {}
	if #short == 0 then
		shopRow:Hide()
		return anchor
	end

	shopShort, shopCount = short, count
	local cost, priced = 0, true
	for _, part in ipairs(short) do
		local unit = RPF.Profit.BuyCost(part.rg.id)
		if unit then cost = cost + unit * part.amount else priced = false end
	end
	local text = string.format("|cffffd200Short for %d|r", count)
	if RPF.Profit.state ~= "missing" then
		RPF.Profit.Fetch(shortEntries(short))
		if priced then text = text .. " |cff9d9d9d- about " .. RPF.Profit.Short(cost) .. "|r" end
	end
	local listed = onListTotal(short)
	if listed > 0 then text = text .. string.format("  |cff4fc3f7%d on the list|r", listed) end
	local room = (pane:GetWidth() or 0) - 2 * PAD - SHOP_BUTTON_WIDTH - 8
	shopText:SetWidth(room > 100 and room or 240)
	shopText:SetText(text)

	shopRow:ClearAllPoints()
	shopRow:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
	shopRow:SetPoint("RIGHT", pane, "RIGHT", -PAD, 0)
	shopRow:SetHeight(math.max(22, (shopText:GetStringHeight() or 0) + 2))
	shopRow:Show()
	return shopRow
end

-- The line names what's missing and what buying it costs.
shopRow:EnableMouse(true)
shopRow:SetScript("OnEnter", function (self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText(string.format("Short for %d", shopCount))
	local total, priced = 0, true
	for _, part in ipairs(shopShort) do
		local unit, how = RPF.Profit.BuyCost(part.rg.id)
		local name = part.amount .. " x " .. (M.ReagentName(part.rg) or ("Item #" .. part.rg.id))
		if unit then
			total = total + unit * part.amount
			GameTooltip:AddDoubleLine(name, RPF.Profit.Short(math.floor(unit * part.amount))
				.. " |cff9d9d9d(" .. RPF.Profit.HowBuy(how) .. ")|r", 1, 1, 1, 1, 1, 1)
		else
			priced = false
			GameTooltip:AddDoubleLine(name, "|cffff4040no price|r", 1, 1, 1, 1, 1, 1)
		end
	end
	if #shopShort > 1 then
		GameTooltip:AddDoubleLine("Total", priced and RPF.Profit.Short(math.floor(total)) or "?", 1, 0.82, 0, 1, 1, 1)
	end
	GameTooltip:Show()
end)
shopRow:SetScript("OnLeave", function () GameTooltip:Hide() end)

shopButton:SetScript("OnEnter", function (self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText("Add to Shopping List")
	GameTooltip:AddLine("Puts what your bags and reagent bank are short of, for the amount below, on your shopping "
		.. "list. The auction house's Buy tab opens on that list and counts down as you buy.", 1, 1, 1, true)
	GameTooltip:AddLine("Only what isn't on the list yet is added. Shift-click adds all of it on top, for another "
		.. "recipe that needs the same reagent.", 0.7, 0.7, 0.7, true)
	local r = RPF.selected
	if r and not r.learned then
		GameTooltip:AddLine("You don't know this recipe yet: the materials can wait in your bags until you learn it.",
			0.7, 0.7, 0.7, true)
	end
	GameTooltip:Show()
end)
shopButton:SetScript("OnLeave", function () GameTooltip:Hide() end)

-----------------------------------------
-- auction house: what it sells for, what the materials cost, the profit (Profit.lua)

local priceTitle = label(pane, "GameFontNormalSmall")
priceTitle:SetText("Auction house:")

local priceLines = {}
for i = 1, 3 do
	local line = CreateFrame("Button", nil, pane)
	line:SetHeight(15)
	line:SetPoint("TOPLEFT", i == 1 and priceTitle or priceLines[i - 1], "BOTTOMLEFT", 0, i == 1 and -4 or 0)
	line:SetPoint("RIGHT", pane, "RIGHT", -PAD, 0)
	line.text = label(line, "GameFontHighlightSmall")
	line.text:SetAllPoints(line)
	line:SetScript("OnEnter", function (self)
		if not self.tip then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		self.tip(GameTooltip)
		GameTooltip:Show()
	end)
	line:SetScript("OnLeave", function () GameTooltip:Hide() end)
	priceLines[i] = line
end

local function hidePrices()
	priceTitle:Hide()
	for _, line in ipairs(priceLines) do line:Hide() end
end

-- How you could gather a reagent yourself ("mine or prospect"), from its sources once the
-- reagent badges have looked them up; nil when you can't (set further down).
local gatherableBy

-- Each reagent: amount, price and where that price comes from.
local function materialsTip(a)
	return function (tip)
		tip:SetText("Materials per craft")
		for _, part in ipairs(a.parts) do
			local name = M.ReagentName(part.rg) or ("Item #" .. tostring(part.rg.id or "?"))
			local right = part.known and (RPF.Profit.Short(math.floor(part.cost)) .. " |cff9d9d9d(" .. RPF.Profit.HowBuy(part.how) .. ")|r")
				or "|cffff4040no price|r"
			tip:AddDoubleLine(part.rg.n .. " x " .. name, right, 1, 1, 1, 1, 1, 1)
		end
		if a.saving > 0 then
			tip:AddDoubleLine(string.format("Resourcefulness %d%%", math.floor((a.resourceful or 0) + 0.5)),
				"-" .. RPF.Profit.Short(a.saving), 1, 1, 1, 0.25, 1, 0.25)
		end
		tip:AddLine("Materials you have count at what selling them would bring: crafting has to beat that. "
			.. "Ones you can craft yourself count at the cheaper of buying and crafting them.", 0.6, 0.6, 0.6, true)
	end
end

-- Draws under `anchor` and returns what comes next should hang from.
local function drawPrices(r, anchor)
	local P = RPF.Profit
	if r.isEnchant or not r.item or r.item == 0 or P.state == "missing" or M.linked then
		hidePrices()
		return anchor
	end
	P.Fetch(P.EntriesOf(r))
	priceTitle:ClearAllPoints()
	priceTitle:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
	priceTitle:Show()
	for _, line in ipairs(priceLines) do line:Hide(); line.tip = nil end

	local a = P.Of(r)
	if not a then
		priceLines[1].text:SetText(P.Get(r.item) and "|cff9d9d9dNo price: it can't be sold on the auction house or to a vendor.|r"
			or "|cff9d9d9dLooking up prices...|r")
		priceLines[1]:Show()
		return priceLines[1]
	end

	local sells = string.format("|cffffd200Sells for|r  %s each |cff9d9d9d(%s)|r", P.Short(a.unitValue), P.HowSell(a.valueHow))
	if a.made ~= 1 then sells = sells .. string.format("  x%s", a.made % 1 == 0 and tostring(a.made) or string.format("%.1f", a.made)) end
	priceLines[1].text:SetText(sells)
	priceLines[1].tip = function (tip)
		local p = P.Get(r.item)
		tip:SetText("Sells for")
		if p and p.soulbound then tip:AddLine("Binds when picked up: only a vendor buys it.", 1, 1, 1, true) end
		if p and p.lowest > 0 then tip:AddDoubleLine("Lowest buyout", P.Short(p.lowest), 1, 1, 1, 1, 1, 1) end
		if p and p.bot > 0 then tip:AddDoubleLine("The AH bot pays", P.Short(p.bot), 1, 1, 1, 1, 1, 1) end
		if p and p.soldUnits > 0 then
			tip:AddDoubleLine(string.format("Sold lately (%d days)", P.days), P.Short(math.floor(p.soldCopper / p.soldUnits)) .. " avg", 1, 1, 1, 1, 1, 1)
		end
		if p and p.sell > 0 then tip:AddDoubleLine("A vendor pays", P.Short(p.sell), 1, 1, 1, 1, 1, 1) end
		local market = P.MarketText(r.item)
		if market ~= "" then tip:AddLine(market, 1, 1, 1, true) end
		tip:AddLine(string.format("Counted after the %s%% house cut, except the vendor price.", P.CutText()), 0.6, 0.6, 0.6, true)
		for _, note in ipairs(P.SellNotes(r.item)) do tip:AddLine(note, 0.6, 0.6, 0.6, true) end
	end
	priceLines[1]:Show()

	priceLines[2].text:SetText("|cffffd200Materials|r  " .. (a.costKnown and P.Short(a.cost) or "|cffff4040?|r")
		.. (a.costKnown and "" or " |cff9d9d9d(something has no price)|r") .. " |cff9d9d9dper craft|r")
	priceLines[2].tip = materialsTip(a)
	priceLines[2]:Show()

	if a.costKnown then
		local text = "|cffffd200Profit|r  " .. P.Signed(a.profit) .. " |cff9d9d9dper craft|r"
		local n = r.learned and P.CanMake(r) or 0
		if n > 1 and a.profit > 0 then text = text .. string.format("  |cff9d9d9d- %s for the %d you can make|r", P.Signed(a.profit * n), n) end
		priceLines[3].text:SetText(text)
		priceLines[3].tip = function (tip)
			tip:SetText("How the profit adds up")
			P.AddProfitLines(tip, r, a, gatherableBy)
		end
		priceLines[3]:Show()
		return priceLines[3]
	end
	return priceLines[2]
end

-----------------------------------------
-- what a herb gives when milled, or ore when prospected: likeliest first, in two columns when
-- there's a lot (ore gives a dozen gems)

local MAX_RESULTS = 20
local RESULT_HEIGHT = 18
local RESULT_COLUMN = 212
local ONE_COLUMN = 8

local resultTitle = label(pane, "GameFontNormalSmall")

local resultRows = {}
for i = 1, MAX_RESULTS do
	local row = CreateFrame("Button", nil, pane)
	row:SetSize(RESULT_COLUMN - 8, RESULT_HEIGHT)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(14, 14)
	row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	row.text = label(row, "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.text:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.text:SetWordWrap(false)
	row:SetScript("OnEnter", function (self) itemTooltip(self, self.link) end)
	row:SetScript("OnLeave", RPF.HideItemTooltip)
	row:SetScript("OnClick", function (self) linkOrNothing(self.link) end)
	resultRows[i] = row
end

local resultMore = label(pane, "GameFontDisableSmall")

local function hideResults()
	resultTitle:Hide()
	resultMore:Hide()
	for _, row in ipairs(resultRows) do row:Hide() end
end

local function drawResults(r, anchor)
	local kind = RPF.Refine.Kind(r.refine)
	resultTitle:ClearAllPoints()
	resultTitle:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
	resultTitle:SetText(string.format("%s 5 gives:", kind.verb))
	resultTitle:Show()

	local n = math.min(#r.results, MAX_RESULTS)
	local perColumn = n > ONE_COLUMN and math.ceil(n / 2) or n
	for i, row in ipairs(resultRows) do
		local res = r.results[i]
		if res and i <= n then
			local info = RPF.Item(res.id)
			local _, _, _, hex = RPF.QualityColor(info and info.quality or 1)
			row.link = info and info.link or ("item:" .. res.id)
			row.icon:SetTexture((info and info.texture) or RPF.ItemIcon(res.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
			row.text:SetText(string.format("%s %s%s|r |cff9d9d9d- %s|r", RPF.Refine.CountText(res), hex,
				info and info.name or ("Item #" .. res.id), RPF.Refine.ChanceText(res)))
			local column, line = i > perColumn and 1 or 0, (i - 1) % math.max(1, perColumn)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", resultTitle, "BOTTOMLEFT", column * RESULT_COLUMN, -6 - line * RESULT_HEIGHT)
			row:Show()
		else
			row:Hide()
		end
	end

	if #r.results > n then
		resultMore:ClearAllPoints()
		resultMore:SetPoint("TOPLEFT", resultTitle, "BOTTOMLEFT", 0, -8 - perColumn * RESULT_HEIGHT)
		resultMore:SetText(string.format("and %d rarer ones", #r.results - n))
		resultMore:Show()
	else
		resultMore:Hide()
	end
end

-----------------------------------------
-- where to learn it

local sourceTitle = label(pane, "GameFontNormalSmall")
sourceTitle:SetText("Learn it from:")

local recipeItemButton = CreateFrame("Button", nil, pane)
recipeItemButton:SetHeight(16)
recipeItemButton:SetPoint("TOPLEFT", sourceTitle, "BOTTOMLEFT", 0, -6)
recipeItemButton:SetPoint("RIGHT", pane, "RIGHT", -PAD, 0)
recipeItemButton.text = label(recipeItemButton, "GameFontHighlightSmall")
recipeItemButton.text:SetAllPoints(recipeItemButton)
recipeItemButton:SetScript("OnEnter", function (self) itemTooltip(self, self.link) end)
recipeItemButton:SetScript("OnLeave", RPF.HideItemTooltip)
recipeItemButton:SetScript("OnClick", function (self) linkOrNothing(self.link) end)

-- Kinds the server can flag on the map: friendly ones always, the rest with HELLO_GUIDE.
local PIN_ALWAYS = { T = true, V = true }
local PIN_GUIDE = { N = true, G = true, D = true, P = true, K = true, O = true, Q = true, R = true }

local function canPin(src)
	if not RPF.Has(RPF.HELLO_MAP_PINS) or (src.id or 0) == 0 then return false end
	-- A quest's pin goes on its giver; without one known there's nothing to flag.
	if (src.kind == "Q" or src.kind == "R") and (src.c or "") == "" then return false end
	return PIN_ALWAYS[src.kind] or (PIN_GUIDE[src.kind] and RPF.Has(RPF.HELLO_GUIDE)) or false
end

-- Flags a source on the world map and says where it is.
local function pinSource(src)
	local who = (src.kind == "Q" or src.kind == "R") and (src.c ~= "" and src.c or src.name) or src.name
	RPF.ShowOnMap(src.kind, src.id, function (where, err)
		if where then
			RPF.Status(who .. ": " .. where .. ". Marked on your map when it's on this continent.")
		else
			RPF.Status("Couldn't find " .. who .. " where you can reach it.", true)
		end
	end)
end

-- Each line says the essentials; hovering it shows the rest (who gives a quest, what a vendor
-- wants, where a bag comes from).
local sourceRows = {}
for i = 1, MAX_SOURCES do
	local row = CreateFrame("Button", nil, pane)
	row:SetHeight(18)
	row:SetPoint("TOPLEFT", recipeItemButton, "BOTTOMLEFT", 0, -2 - (i - 1) * 18)
	row:SetPoint("RIGHT", pane, "RIGHT", -PAD, 0)
	row.text = label(row, "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.map = RPF.CreateButton(row, "Map", 44, 18)
	row.map:SetPoint("RIGHT", row, "RIGHT", 0, 0)
	row.text:SetPoint("RIGHT", row.map, "LEFT", -6, 0)
	row.text:SetWordWrap(false)
	row.map:SetScript("OnClick", function (self)
		local src = self:GetParent().source
		if src then pinSource(src) end
	end)
	row:SetScript("OnEnter", function (self)
		if self.tip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			self.tip(GameTooltip)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function () GameTooltip:Hide() end)
	sourceRows[i] = row
end

local sourceNote = label(pane, "GameFontDisableSmall")
sourceNote:SetPoint("TOPLEFT", recipeItemButton, "BOTTOMLEFT", 0, -2)
sourceNote:SetPoint("RIGHT", pane, "RIGHT", -PAD, 0)

local GOLD = "|cffffd200"
local GREY = "|cffb0b0b0"
local DIM = "|cff9d9d9d"

local function chanceText(x100)
	x100 = tonumber(x100) or 0
	if x100 <= 0 then return "" end
	local pct = x100 / 100
	return string.format(" - %s%%", pct >= 10 and string.format("%d", math.floor(pct)) or string.format("%.1f", pct))
end

local function where(src)
	return src.zone ~= "" and (" - " .. GREY .. src.zone .. "|r") or ""
end

-- The server's few words for the line: a token price, a holiday, "rare", "daily".
local function noted(src)
	local note = src.note or ""
	if note == "" then return "" end
	return " |cffff8040(" .. note .. ")|r"
end

-- "World drop in Ulduar", "World drop, level 40-50 (Eastern Kingdoms, Kalimdor)".
local function worldDropText(src)
	local places = src.c or ""
	if src.note == "trash" and places ~= "" then
		return string.format("%sWorld drop|r from trash in %s %s(level %s)|r", GOLD, places, GREY, tostring(src.b))
	end
	local text = string.format("%sWorld drop|r from %s creatures, level %s", GOLD, tostring(src.a), tostring(src.b))
	if places ~= "" then text = text .. " " .. GREY .. "(" .. places .. ")|r" end
	return text
end

local function sourceText(src, r)
	local k = src.kind
	if k == "A" then
		local at = tonumber(src.a) or 0
		return at <= 1 and (GOLD .. "Learned|r with the profession") or string.format("%sLearned|r automatically at skill %d", GOLD, at)
	elseif k == "T" then
		local text = string.format("%sTrainer|r  %s%s - %s", GOLD, src.name, where(src), RPF.Money(src.a))
		local skill = tonumber(src.b) or 0
		if skill > (M.baseRank or M.rank or 0) then text = text .. string.format(" |cffff4040(at %d)|r", skill) end
		return text .. noted(src)
	elseif k == "N" then
		return string.format("%sTaught by|r  %s%s", GOLD, src.name, where(src)) .. noted(src)
	elseif k == "G" then
		return string.format("%sLearned from|r  %s%s", GOLD, src.name, where(src)) .. noted(src)
	elseif k == "V" then
		local text = string.format("%sVendor|r  %s%s", GOLD, src.name, where(src))
		if (tonumber(src.a) or 0) > 0 then text = text .. " - " .. RPF.Money(src.a) end
		text = text .. noted(src)
		if tostring(src.b) == "1" then text = text .. " " .. GREY .. "(limited)|r" end
		if src.c and src.c ~= "" then text = text .. " |cffff8040" .. src.c .. "|r" end
		return text
	elseif k == "D" then
		return string.format("%sDrop|r  %s %s(level %s)|r%s%s", GOLD, src.name, GREY, tostring(src.b), where(src), chanceText(src.a)) .. noted(src)
	elseif k == "P" or k == "K" then
		local verb = k == "P" and "Pickpocket" or "Skinning"
		if src.id == 0 then return string.format("%s%s|r  %s", GOLD, verb, src.name) end
		return string.format("%s%s|r  %s %s(level %s)|r%s%s", GOLD, verb, src.name, GREY, tostring(src.b), where(src), chanceText(src.a))
	elseif k == "X" then
		return worldDropText(src)
	elseif k == "O" then
		return string.format("%sFound in|r  %s%s%s", GOLD, src.name, where(src), chanceText(src.a))
	elseif k == "C" then
		local text = string.format("%sInside|r  %s%s", GOLD, src.name, chanceText(src.a))
		if (src.note or "") ~= "" then text = text .. " " .. GREY .. "- " .. src.note .. "|r" end
		return text
	elseif k == "Q" or k == "R" then
		return string.format("%s%s|r  %s %s(level %s)|r%s", GOLD, k == "Q" and "Quest" or "Quest reward", src.name,
			GREY, tostring(src.a), where(src)) .. noted(src)
	elseif k == "S" then
		local from = src.name ~= "" and ("while making " .. src.name) or ("from " .. (M.skillName or "") .. " research")
		return string.format("%sDiscovery|r %s at skill %s%s", GOLD, from, tostring(src.b), chanceText(src.a))
	elseif k == "L" then
		local n = tonumber(src.a) or 0
		return string.format("%sAnd %d more in %s, once it opens to you|r", DIM, n, src.name)
	-- A reagent's (RPF.WhereToGet):
	elseif k == "B" then
		return string.format("%sCrafted|r  with %s", GOLD, src.name)
	elseif k == "H" then
		local text = string.format("%sGathered|r  %s%s", GOLD, src.name, where(src))
		if (tonumber(src.a) or 0) > 1 then text = text .. string.format(" %s(skill %s)|r", GREY, tostring(src.a)) end
		return text
	elseif k == "F" then
		return string.format("%sFished|r  in %s%s", GOLD, (src.c or "") ~= "" and src.c or src.name, chanceText(src.a))
	elseif k == "E" then
		return GOLD .. "Disenchanted|r  from equipment"
	elseif k == "M" or k == "J" then
		return string.format("%s%s|r  from %s%s", GOLD, k == "M" and "Milled" or "Prospected", src.name, chanceText(src.a))
	end
	return src.name
end

-- What hovering a line shows: the line itself, then the server's details.
local TIP_TITLE = {
	A = "Learned automatically", T = "Trainer", N = "Taught by", G = "Learned from", V = "Vendor", D = "Drop",
	P = "Pickpocket", K = "Skinning", X = "World drop", O = "Found in", C = "Inside", Q = "Quest", R = "Quest reward",
	S = "Discovery", L = "Not open to you yet",
	B = "Crafted", H = "Gathered", F = "Fished", E = "Disenchanted", M = "Milled", J = "Prospected",
}

local function sourceTip(src)
	return function (tip)
		local title = TIP_TITLE[src.kind] or ""
		local name = src.name ~= "" and src.name or nil
		if src.kind == "X" or src.kind == "L" or src.kind == "S" or (src.kind == "P" or src.kind == "K") and src.id == 0 then
			name = nil
		end
		tip:SetText(name and (title .. ": " .. name) or title)
		if src.zone ~= "" then tip:AddLine(src.zone, 0.7, 0.7, 0.7) end
		local any = false
		for line in (src.details or ""):gmatch("[^\n]+") do
			tip:AddLine(line, 1, 1, 1, true)
			any = true
		end
		if src.kind == "L" then
			tip:AddLine("Those sources are on a continent your progression hasn't reached.", 1, 1, 1, true)
		elseif src.kind == "S" then
			tip:AddLine("Each craft has a small chance to teach it, once your skill is high enough.", 1, 1, 1, true)
		elseif not any and src.kind == "X" then
			tip:AddLine("Any of those creatures can drop it, and it may turn up on the auction house.", 1, 1, 1, true)
		end
		if canPin(src) then tip:AddLine("Map: mark it on your world map.", 0.6, 0.6, 0.6) end
	end
end

-- "on the auction house from 12g" for a recipe item that can be traded, when prices are known.
local function recipeItemMarket(recipeItem)
	local P = RPF.Profit
	if not P or P.state == "missing" or M.linked then return "" end
	P.Fetch({ recipeItem })
	local p = P.Get(recipeItem)
	if not p then return "" end
	if p.soulbound then return " " .. DIM .. "(binds when picked up)|r" end
	if p.lowest > 0 then
		return string.format(" %s- on the auction house from|r %s", DIM, P.Short(p.lowest))
	end
	return ""
end

local whereToken = 0

local function hideSources()
	sourceTitle:Hide()
	recipeItemButton:Hide()
	sourceNote:Hide()
	for _, row in ipairs(sourceRows) do row:Hide() end
end

local function drawSources(r, anchor)
	sourceTitle:ClearAllPoints()
	sourceTitle:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
	sourceTitle:Show()
	for _, row in ipairs(sourceRows) do row:Hide() end
	recipeItemButton:Hide()

	-- The lines there's room for under the title, the recipe item's included; a recipe with
	-- many reagents leaves few, and the last one then stands for the rest.
	local room = linesFit(sourceTitle, 6, 18, MAX_SOURCES + 1)
	if room < 1 then
		hideSources()
		return
	end

	if not RPF.Has(RPF.HELLO_RECIPES) then
		sourceNote:SetText("This realm doesn't say where recipes come from.")
		sourceNote:Show()
		return
	end
	sourceNote:SetText("Looking it up...")
	sourceNote:Show()

	whereToken = whereToken + 1
	local mine = whereToken
	RPF.WhereToLearn(r.spell, function (result, err)
		if mine ~= whereToken or RPF.selected ~= r then return end
		if not result then
			sourceNote:SetText(err == "busy" and "The server is busy; pick the recipe again." or "No source known.")
			return
		end
		local recipeItem = result.recipeItem or 0
		local rows = result.rows
		-- With room for one line only, the recipe item goes in its tooltip with the rest.
		local itemText
		if recipeItem > 0 then
			local info = RPF.Item(recipeItem)
			recipeItemButton.link = info and info.link or ("item:" .. recipeItem)
			itemText = GOLD .. "Recipe item|r  " .. (info and info.link or ("item " .. recipeItem)) .. recipeItemMarket(recipeItem)
		end
		local showItem = itemText and (room >= 2 or #rows == 0)
		recipeItemButton.text:SetText(showItem and itemText or "")
		recipeItemButton:Show()
		recipeItemButton:SetHeight(showItem and 16 or 1)
		local fit = math.min(MAX_SOURCES, room - (showItem and 1 or 0))

		-- More than fit: the last line sums up the rest, and its tooltip lists them.
		local n = 0
		for i, src in ipairs(rows) do
			n = n + 1
			local row = sourceRows[n]
			if n > fit then
				n = n - 1
				break
			end
			if n == fit and (#rows > fit or (itemText and not showItem)) then
				local rest = {}
				for j = i, #rows do table.insert(rest, rows[j]) end
				row.source = nil
				row.text:SetText(string.format("%sAnd %d more sources (hover to see them)|r", DIM, #rest))
				row.tip = function (tip)
					tip:SetText("More sources")
					if itemText and not showItem then tip:AddLine(itemText, 1, 1, 1) end
					for _, more in ipairs(rest) do tip:AddLine(sourceText(more, r), 1, 1, 1) end
				end
				row.map:Hide()
				row:Show()
				break
			end
			row.source = src
			row.text:SetText(sourceText(src, r))
			row.tip = sourceTip(src)
			if canPin(src) then row.map:Show() else row.map:Hide() end
			row:Show()
		end
		if n == 0 then
			sourceNote:SetText("Nothing teaches this where you can reach it yet.")
		else
			sourceNote:Hide()
		end
	end)
end

-----------------------------------------
-- where the reagents come from (RPF.WhereToGet): a badge after each reagent's name, and under
-- a recipe you know, in the room "Learn it from" would take, a line per reagent. One source
-- each, the easiest: you craft it, a vendor sells it, you gather it, it drops, someone else's
-- profession. The tooltip has the rest.

local GATHER = { H = true, F = true, K = true, E = true, M = true, J = true }
local GATHER_SKILL = { F = 356, K = 393, E = 333, M = 773, J = 755 }
local GATHER_ICON = { E = "Interface\\Icons\\INV_Enchant_Disenchant" }
local REFINE_CODE = { M = "M", J = "P" }

local function gatherSkill(src)
	return src.kind == "H" and tonumber(src.b) or GATHER_SKILL[src.kind]
end

-- By name, GetSpellInfo only answers for spells you know: the one that opens the profession,
-- or a gathering profession's own (Find Herbs, Fishing, Skinning).
local function knows(skill)
	local p = skill and RPF.Profession(skill)
	local name = p and (p.openName or p.extraName or p.localName)
	return name and GetSpellInfo(name) ~= nil or false
end

local function gatherIcon(src)
	if src.kind == "M" or src.kind == "J" then
		local kind = RPF.Refine.Kind(REFINE_CODE[src.kind])
		local icon = kind and select(3, GetSpellInfo(kind.spell))
		if icon then return icon end
	end
	local p = RPF.Profession(gatherSkill(src) or 0)
	return GATHER_ICON[src.kind] or (p and p.texture) or SOURCE_ICON.drop
end

-- "Drops from Defias Looter (level 13-14) - Westfall - 32%".
local function dropLine(src)
	if src.kind == "O" then
		return string.format("Found in %s%s%s", src.name, where(src), chanceText(src.a))
	elseif src.kind == "C" then
		return string.format("Found inside %s%s", src.name, chanceText(src.a))
	elseif src.kind == "X" then
		local text = string.format("Drops from many creatures, level %s", tostring(src.b))
		if (src.c or "") ~= "" then text = text .. ", mostly " .. (src.note == "trash" and "in " or "on ") .. src.c end
		return text
	end
	return string.format("Drops from %s %s(level %s)|r%s%s", src.name, GREY, tostring(src.b), where(src), chanceText(src.a))
end

-- "prospect or mine", "Mining or Jewelcrafting".
local function either(words)
	if #words < 2 then return words[1] or "" end
	return table.concat(words, ", ", 1, #words - 1) .. " or " .. words[#words]
end

local function gatherVerb(src)
	if src.kind == "H" then
		local skill = tonumber(src.b)
		return skill == 182 and "pick" or skill == 186 and "mine" or "fish"
	end
	return ({ F = "fish", K = "skin", E = "disenchant", M = "mill", J = "prospect" })[src.kind]
end

-- Only from sources already looked up (the badges ask for the selected recipe's reagents), so
-- a tooltip never sends a request.
gatherableBy = function (item)
	local rows = RPF.CachedWhereToGet and RPF.CachedWhereToGet(item)
	if not rows then return nil end
	local verbs, seen = {}, {}
	for _, src in ipairs(rows) do
		local skill = GATHER[src.kind] and gatherSkill(src)
		local verb = skill and knows(skill) and gatherVerb(src)
		if verb and not seen[verb] then
			seen[verb] = true
			table.insert(verbs, verb)
		end
	end
	return #verbs > 0 and table.concat(verbs, " or ") or nil
end

-- A drop worth sending someone after when a profession also gives the reagent: 15%.
local GOOD_DROP = 1500

-- The one source a reagent is shown with: { icon, dim, text } and what a click does (spell: a
-- recipe here; other: a profession to open, through a secure button; refine: Milling or
-- Prospecting here; pin: a source to flag on the map; tell: sources to say where to gather).
-- The easiest first: you craft it; a vendor with all you want of it; you gather it (every
-- way you can: a gem is prospected and mined); a vendor with a few in stock; a drop, unless
-- it's a rare one and a profession gives it; a vendor for tokens or on a holiday; someone
-- else's profession.
local function classify(slot, rows, waiting)
	local function first(kinds, test)
		for _, src in ipairs(rows or {}) do
			if kinds[src.kind] and (not test or test(src)) then return src end
		end
		return nil
	end
	local made = slot.makes and M.bySpell[slot.makes]
	if made and made.learned then
		return { icon = SOURCE_ICON.craft, text = "You can craft this yourself.", spell = slot.makes }
	elseif slot.craftOther then
		return { icon = SOURCE_ICON.craft, text = "You can craft this yourself.", other = slot.craftOther }
	elseif waiting then
		return { text = DIM .. "Looking it up...|r", waiting = true }
	elseif not rows then
		-- The realm doesn't say: only what the recipes themselves show.
		return made and { icon = SOURCE_ICON.craft, dim = true, text = "You haven't learned to craft this yet.", spell = slot.makes }
			or nil
	end

	-- Every way to gather it, one per profession: yours, and the others'.
	local mine, theirs, seen = {}, {}, {}
	for _, src in ipairs(rows) do
		local skill = GATHER[src.kind] and gatherSkill(src)
		if skill and not seen[skill] then
			seen[skill] = true
			table.insert(knows(skill) and mine or theirs, src)
		end
	end
	local function professions(list, into)
		for _, src in ipairs(list) do
			local p = RPF.Profession(gatherSkill(src) or 0)
			if p then table.insert(into, p.localName) end
		end
		return into
	end
	-- After a vendor or a drop: the other ways, yours and other people's professions.
	local function also()
		local parts = {}
		if #mine > 0 then
			local verbs = {}
			for _, src in ipairs(mine) do table.insert(verbs, gatherVerb(src)) end
			table.insert(parts, "You can also " .. either(verbs) .. " this yourself.")
		end
		local names = {}
		for _, src in ipairs(rows) do
			if src.kind == "B" then table.insert(names, src.name) end
		end
		professions(theirs, names)
		if #names > 0 then
			table.insert(parts, "Also from someone with " .. either(names) .. " or the Auction House.")
		end
		return #parts > 0 and (". " .. table.concat(parts, " ")) or ""
	end

	local function vendorLine(v, extra)
		return { icon = SOURCE_ICON.vendor, text = "Buy from " .. v.name .. where(v) .. (extra or "") .. also(), pin = v }
	end
	local V = { V = true }
	local plain = first(V, function (v) return (tonumber(v.b) or 0) == 0 and (v.note or "") == "" end)
	if plain then return vendorLine(plain) end
	if #mine > 0 then
		local verbs = {}
		for _, src in ipairs(mine) do table.insert(verbs, gatherVerb(src)) end
		local text = "You can " .. either(verbs) .. " this yourself."
		if #theirs > 0 then text = text .. " Also from " .. either(professions(theirs, {})) .. "." end
		local lead = mine[1]
		local s = { icon = gatherIcon(lead), text = text, tell = mine }
		local code = REFINE_CODE[lead.kind]
		if code and RPF.Refine.Known(code) then
			local skill = gatherSkill(lead)
			-- Lands on the herb or ore that gives it.
			if M.skill == skill and not M.linked then
				s.refine, s.refineItem = code, lead.id
			else
				local p = RPF.Profession(skill)
				s.other = { skill = skill, code = code, item = lead.id, name = p and p.localName or "" }
			end
		end
		return s
	end

	local limited = first(V, function (v) return (v.note or "") == "" end)
	if limited then return vendorLine(limited, GREY .. " (limited stock)|r") end

	local by = first({ B = true })
	local profession = made or by or #theirs > 0
	local function dropSource(drop)
		return { icon = SOURCE_ICON.drop, text = dropLine(drop) .. also(), pin = (drop.kind == "D" or drop.kind == "O") and drop or nil }
	end
	local good = first({ D = true }, function (d) return (tonumber(d.a) or 0) >= GOOD_DROP end)
	local drop = good or (not profession and (first({ D = true }) or first({ O = true }) or first({ X = true }) or first({ C = true })))
	if drop then return dropSource(drop) end

	local special = first(V)
	if special then return vendorLine(special, GREY .. " (" .. special.note .. ")|r") end

	if made then
		return { icon = SOURCE_ICON.craft, dim = true, text = "You haven't learned to craft this yet.", spell = slot.makes }
	end
	if by or #theirs > 0 then
		local names = {}
		for _, src in ipairs(rows) do
			if src.kind == "B" then table.insert(names, src.name) end
		end
		professions(theirs, names)
		return { icon = by and SOURCE_ICON.craft or gatherIcon(theirs[1]), dim = true,
			text = "Get this from someone with " .. either(names) .. " or buy from the Auction House." }
	end
	if first({ L = true }) then return { text = "Nowhere you can reach yet; try the Auction House." } end
	return { text = "Source unknown." }
end

-- Where to gather it, every way you can: said in the window and kept in chat.
local function tellGather(sources, name)
	for n, src in ipairs(sources) do
		local zones = (src.c or "") ~= "" and src.c or nil
		local p = RPF.Profession(gatherSkill(src) or 0)
		local skill = p and p.localName or ""
		local text
		if src.kind == "H" then
			text = string.format("%s: %s it from %s%s.", name, gatherVerb(src), src.name ~= "" and src.name or "its nodes",
				zones and (", most of all in " .. zones) or "")
			if (tonumber(src.a) or 0) > 1 then text = text .. string.format(" Needs %s %s.", skill, tostring(src.a)) end
		elseif src.kind == "F" then
			text = string.format("%s: fish for it in %s.", name, zones or src.name)
		elseif src.kind == "K" then
			text = string.format("%s: skin it from %s%s.", name, src.name, src.id ~= 0 and src.zone ~= "" and (" in " .. src.zone) or "")
		elseif src.kind == "E" then
			text = name .. ": disenchant equipment for it."
		else
			text = string.format("%s: %s %s for it.", name, src.kind == "M" and "mill" or "prospect", src.name)
		end
		if n == 1 then RPF.Status(text) end
		RPF.Print(text)
	end
end

function RPF.ReagentSourceAct(s, name)
	if not s then return end
	if s.spell then
		RPF.SelectSpell(s.spell)
	elseif s.refine then
		RPF.Refine.SetView(s.refine, s.refineItem)
	elseif s.other then
		UIErrorsFrame:AddMessage("Professions can't be opened in combat.", 1, 0.1, 0.1)
	elseif s.pin then
		-- A node is an object to the map.
		local src = s.pin
		if canPin(src) then pinSource(src) else RPF.Status((name or "It") .. ": " .. s.text) end
	elseif s.tell then
		tellGather(s.tell, name or "It")
	end
end

-- Under a reagent's own tooltip and its badge's: the source it's shown with, then (more) the
-- badge's list of every source, and what a click does.
function RPF.ReagentSourceLines(tip, s, more)
	if not s or s.waiting or not s.text then return end
	tip:AddLine(" ")
	tip:AddLine(s.text, 1, 0.82, 0, true)
	if more then more(tip) end
	local hint
	if s.spell then
		hint = "Click: the recipe that makes it"
	elseif s.other then
		hint = s.other.code and ("Click: open " .. s.other.name) or ("Click: the recipe that makes it (" .. s.other.name .. ")")
	elseif s.refine then
		hint = "Click: the herbs or ore that give it"
	elseif s.pin then
		hint = canPin(s.pin) and "Click: mark it on your world map" or nil
	elseif s.tell then
		hint = "Click: where to get it (in chat)"
	end
	if hint then tip:AddLine(hint, 0.25, 1, 0.25) end
end

-- A badge's tooltip: the reagent, the line it's shown with, every source the realm knows (of
-- the creatures that drop it, the likeliest three) and what a click does.
function RPF.ReagentBadgeTooltip(tip, slot)
	tip:SetText(slot.itemName or "")
	RPF.ReagentSourceLines(tip, slot.source, function (t)
		local drops, gap = 0, true
		for _, src in ipairs(slot.sources or {}) do
			if src.kind == "D" then drops = drops + 1 end
			if src.kind ~= "D" or drops <= 3 then
				if gap then t:AddLine(" ") gap = false end
				t:AddLine(sourceText(src), 1, 1, 1)
			end
		end
	end)
end

-- One line under the reagents of a recipe you know, pointing at the badges.
local getHint = label(pane, "GameFontNormalSmall")
getHint:SetText("For more details, hover the small icons.")
getHint:Hide()

local function drawHint(r, anchor)
	local show = r.learned and not r.refine and not M.linked and #r.reagents > 0 and RPF.Has(RPF.HELLO_REAGENTS)
	if not show then
		getHint:Hide()
		return anchor
	end
	getHint:ClearAllPoints()
	getHint:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
	getHint:Show()
	return getHint
end

local getToken = 0

local function hideBadges()
	getToken = getToken + 1
	for _, slot in ipairs(reagentSlots) do
		slot.badge.other = nil
		slot.badge:Hide()
		bindOther(slot.badge)
	end
end

local function hideGet()
	getHint:Hide()
	hideBadges()
end

-- The badges, as each reagent's sources come in (the hint line is drawHint's).
local function drawGet(r)
	hideBadges()
	local mine = getToken
	local count = (r.refine or M.linked) and 0 or math.min(#r.reagents, MAX_REAGENTS)

	local function apply(i, rows, waiting)
		local slot = reagentSlots[i]
		local s = classify(slot, rows, waiting)
		slot.source, slot.sources = s, rows
		slot.other = s and s.other or nil
		bindOther(slot)
		local badge = slot.badge
		badge.link, badge.other = slot.link, slot.other
		if s and s.icon then
			badge.icon:SetTexture(s.icon)
			badge.icon:SetDesaturated(s.dim and true or false)
			badge.icon:SetAlpha(s.dim and 0.7 or 1)
			badge:Show()
		else
			badge.other = nil
			badge:Hide()
		end
		bindOther(badge)
	end

	for i = 1, #reagentSlots do
		local slot = reagentSlots[i]
		slot.other = nil
		if i > count then
			slot.source, slot.sources = nil, nil
			bindOther(slot)
		end
	end
	for i = 1, count do
		local rg = r.reagents[i]
		apply(i, nil, RPF.Has(RPF.HELLO_REAGENTS) and rg.id ~= nil)
		if rg.id then
			RPF.WhereToGet(rg.id, function (result)
				if mine ~= getToken or RPF.selected ~= r then return end
				apply(i, result and result.rows or (RPF.Has(RPF.HELLO_REAGENTS) and {} or nil), false)
				RPF.SyncSpellButtons()
			end)
		end
	end
	RPF.SyncSpellButtons()
end

-----------------------------------------

local parts = { icon, nameText, star, subText, description, reagentTitle, watermark }

local function showParts(on)
	for _, p in ipairs(parts) do if on then p:Show() else p:Hide() end end
	if not on then
		noReagents:Hide()
		for _, slot in ipairs(reagentSlots) do slot:Hide2() bindOther(slot) end
		hideGet()
		RPF.SyncSpellButtons()
		shopRow:Hide()
		hideSources()
		hidePrices()
		hideResults()
		perkLine:Hide()
	end
end

local settling = false -- drawing again to measure, not for a change
local lastDrawn

local function draw(r)
	gearStrip:SetSkill(not M.linked and M.skill or nil)
	if not r then
		lastDrawn = nil
		showParts(false)
		empty:Show()
		return
	end
	empty:Hide()
	showParts(true)

	-- What it makes; for a herb to mill or ore to prospect, the herb or ore itself.
	local itemLink = r.itemLink and r.itemLink:find("item:") and r.itemLink or nil
	local shown = r.refine and r.source or r.item
	local info = shown and shown > 0 and RPF.Item(shown)
	icon.link = itemLink or (info and info.link) or (r.spell and GetSpellLink and GetSpellLink(r.spell)) or r.recipeLink
	RPF.SetPortrait(icon.texture, (info and info.texture) or r.icon or (r.refine and RPF.Refine.Icon(r))
		or "Interface\\Icons\\INV_Misc_QuestionMark")
	local quality = info and info.quality or r.quality or 1
	if art then
		-- DragonUI's rings: the bronze one sits round a 45 icon at 64, the quality ones round a
		-- 43 at 68; an enchant (no item) gets the grey one.
		local ring = OUTPUT_RINGS[r.isEnchant and 0 or quality]
		art.Art.Set(icon.ring, ring or "ring-frame")
		local size = icon:GetWidth() * (ring and 68 / 43 or 64 / 45)
		icon.ring:SetSize(size, size)
	elseif quality >= 2 and not r.isEnchant then
		local qr, qg, qb = RPF.QualityColor(quality)
		icon.glow:SetVertexColor(qr, qg, qb)
		icon.glow:Show()
	else
		icon.glow:Hide()
	end
	local _, _, _, hex = RPF.QualityColor(quality)
	nameText:SetText((r.isEnchant and "|cffffffff" or hex) .. r.name .. "|r")
	fitName()
	if art then
		art.Art.Set(star.texture, RPF.IsFavorite(r.spell) and "favorite" or "favorite-off")
	else
		star.texture:SetDesaturated(not RPF.IsFavorite(r.spell))
		star.texture:SetAlpha(RPF.IsFavorite(r.spell) and 1 or 0.45)
	end
	-- Favorites are kept by spell; a herb or ore has none.
	if r.refine then star:Hide() end
	local p = M.profession
	watermark:SetTexture(not art and p and p.texture or nil)

	-- Under the name: what it needs (red when you don't have it), else what it makes.
	local sub
	if r.refine then
		sub = string.format("|cffffd200Requires:|r %s%s %d|r", RPF.Refine.SkillTooLow(r) and "|cffff2020" or "|cffffffff",
			M.skillName or "", r.reqSkill or 0)
	elseif r.tools and #r.tools > 0 then
		local names = {}
		for _, t in ipairs(r.tools) do table.insert(names, (M.ToolHas(t) and "|cffffffff" or "|cffff2020") .. t.name .. "|r") end
		sub = "|cffffd200Requires:|r " .. table.concat(names, ", ")
	elseif r.isEnchant then
		sub = "Enchants an item"
	elseif not (r.item and r.item > 0) then
		sub = ""
	else
		local lo, hi = r.madeMin or 1, r.madeMax or 1
		sub = lo == hi and ("Makes " .. lo) or string.format("Makes %d-%d", lo, hi)
	end
	if r.cooldown and r.cooldown > 0 then
		sub = sub .. "   |cffff4040Cooldown: " .. RPF.Duration(r.cooldown) .. "|r"
	end
	if not r.learned then
		local need = r.reqSkill or 0
		sub = sub .. string.format("   %sNot learned - needs %d|r", need > (M.baseRank or M.rank or 0) and "|cffff4040" or "|cffffd200", need)
	end
	subText:SetText(sub)
	description:SetText(r.description or "")

	local perks = M.PerksOf(r)
	perkLine.perks = perks
	if perks then
		perkLine.text:SetText(M.PerksText(perks))
		perkLine:Show()
		description:SetPoint("TOPLEFT", perkLine, "BOTTOMLEFT", 0, -8)
	else
		perkLine:Hide()
		description:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -10)
	end

	reagentAnchor:ClearAllPoints()
	reagentAnchor:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, (r.description or "") ~= "" and -12 or 0)

	local rows = drawReagents(r)
	local below = drawHint(r, #r.reagents > 0 and reagentSlots[rows] or noReagents)
	below = drawShopping(r, below)
	below = drawPrices(r, below)
	if r.refine then drawResults(r, below) else hideResults() end
	-- Where to learn it fills the room that's left, and how many lines fit is measured: what was
	-- placed just now (after another recipe, or another profession's) only has its place on
	-- screen a moment later. A new recipe's list waits for that rather than show too many.
	local fresh = r ~= lastDrawn
	lastDrawn = r
	if r.learned or (fresh and not settling) then
		hideSources()
	else
		drawSources(r, below)
	end
	drawGet(r)
	if not settling then
		RPF.Debounce("detail-fit", 0.05, function () RPF.DetailRefit(r, true) end)
	end
end

function RPF.DetailRefit(r, again)
	if RPF.selected ~= r or not pane:IsVisible() then return end
	settling = true
	draw(r)
	settling = false
	if again then RPF.After(0.3, function () RPF.DetailRefit(r, false) end) end
end

shopButton:SetScript("OnClick", function ()
	local r = RPF.selected
	if not r or r.refine or M.linked then return end
	-- Without the bank's counts everything in it would look missing.
	if not RPF.BankCountsKnown() then
		RPF.RequestBankSnapshot()
		RPF.Status("Still checking what your reagent bank holds. Try again in a moment.", true)
		return
	end
	local added = RPF.AddToShoppingList(r, RPF.GetQuantity(), IsShiftKeyDown())
	if added > 0 then
		RPF.Status("On your shopping list: the auction house's Buy tab opens on it.")
	else
		RPF.Status("That's already on your shopping list. Shift-click adds it again on top.")
	end
	draw(r)
end)

RPF.On("SELECTED", draw)
-- The shopping line follows the amount.
RPF.On("QUANTITY", function ()
	local r = RPF.selected
	if r and RPF.IsOpen() then draw(r) end
end)
RPF.On("HIDDEN", function ()
	whereToken = whereToken + 1
	getToken = getToken + 1
end)

-- A craft made a second batch or gave reagents back: say so in the window, or in chat when
-- it's closed (a craft from a macro). Both can come from one craft; the line keeps both.
local lastProc, lastProcAt = nil, 0
RPF.On("PERK", function (spell, kind, list)
	local names = {}
	for entry, n in (list or ""):gmatch("(%d+)%*(%d+)") do
		local info = RPF.Item(tonumber(entry))
		table.insert(names, n .. " " .. (info and info.name or ("item " .. entry)))
	end
	if #names == 0 then return end
	local text = kind == "M" and ("Multicraft! " .. table.concat(names, ", ") .. " more.")
		or ("Resourcefulness! You got back " .. table.concat(names, ", ") .. ".")
	if not RPF.IsOpen() then
		RPF.Print(text)
		return
	end
	if lastProc and GetTime() - lastProcAt < 0.5 then text = lastProc .. " " .. text end
	lastProc, lastProcAt = text, GetTime()
	RPF.Status(text)
end)
