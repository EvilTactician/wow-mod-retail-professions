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
	slot:SetScript("OnEnter", function (self)
		itemTooltip(self, self.link)
		if self.makes and self.link then
			GameTooltip:AddLine("Click: the recipe that makes it", 0.25, 1, 0.25)
			GameTooltip:Show()
		end
	end)
	slot:SetScript("OnLeave", RPF.HideItemTooltip)
	-- As on retail: a reagent this profession makes opens its recipe.
	slot:SetScript("OnClick", function (self)
		if not linkOrNothing(self.link) and self.makes then RPF.SelectSpell(self.makes) end
	end)
	slot.Hide2 = function (self) self:Hide(); self.name:Hide() end
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

local function drawReagents(r)
	local shown = 0
	-- The pane is narrower in DragonUI's window (Host.lua); the names stay inside it.
	local nameWidth = math.min(REAGENT_TEXT_WIDTH, math.max(120, (pane:GetWidth() or 0) - 2 * PAD - 38))
	for i, slot in ipairs(reagentSlots) do
		slot.name:SetWidth(nameWidth)
		local rg = r.reagents[i]
		if rg then
			shown = i
			local info = rg.id and RPF.Item(rg.id)
			local link = rg.link or (info and info.link) or (rg.id and ("item:" .. rg.id))
			slot.link = link
			slot.makes = recipeMaking(rg.id)
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

-- More reagents than this are counted, not named, so the line stays short.
local SHOP_NAMES = 3

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

	local names, cost, priced = {}, 0, true
	for i, part in ipairs(short) do
		if i <= SHOP_NAMES then
			table.insert(names, part.amount .. " " .. (M.ReagentName(part.rg) or ("Item #" .. part.rg.id)))
		end
		local unit = RPF.Profit.BuyCost(part.rg.id)
		if unit then cost = cost + unit * part.amount else priced = false end
	end
	local text = string.format("|cffffd200Short for %d|r  %s", count, table.concat(names, ", "))
	if #short > SHOP_NAMES then text = text .. " and " .. (#short - SHOP_NAMES) .. " more" end
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

-- Each reagent: amount, price and where that price comes from.
local function materialsTip(a)
	return function (tip)
		tip:SetText("Materials per craft")
		for _, part in ipairs(a.parts) do
			local name = M.ReagentName(part.rg) or ("Item #" .. tostring(part.rg.id or "?"))
			local right = part.unit and (RPF.Profit.Short(part.unit * part.rg.n) .. " |cff9d9d9d(" .. RPF.Profit.HowBuy(part.how) .. ")|r")
				or "|cffff4040no price|r"
			tip:AddDoubleLine(part.rg.n .. " x " .. name, right, 1, 1, 1, 1, 1, 1)
		end
		tip:AddLine("Materials you have count at their price too: crafting has to beat selling them.", 0.6, 0.6, 0.6, true)
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
	local market = P.MarketText(r.item)
	if market ~= "" then sells = sells .. "  |cff9d9d9d- " .. market .. "|r" end
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
		tip:AddLine(string.format("Counted after the %d%% house cut, except the vendor price.", P.cut), 0.6, 0.6, 0.6, true)
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
		if not src then return end
		local who = (src.kind == "Q" or src.kind == "R") and (src.c ~= "" and src.c or src.name) or src.name
		RPF.ShowOnMap(src.kind, src.id, function (where, err)
			if where then
				RPF.Status(who .. ": " .. where .. ". Marked on your map when it's on this continent.")
			else
				RPF.Status("Couldn't find " .. who .. " where you can reach it.", true)
			end
		end)
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
	end
	return src.name
end

-- What hovering a line shows: the line itself, then the server's details.
local TIP_TITLE = {
	A = "Learned automatically", T = "Trainer", N = "Taught by", G = "Learned from", V = "Vendor", D = "Drop",
	P = "Pickpocket", K = "Skinning", X = "World drop", O = "Found in", C = "Inside", Q = "Quest", R = "Quest reward",
	S = "Discovery", L = "Not open to you yet",
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
		if recipeItem > 0 then
			local info = RPF.Item(recipeItem)
			recipeItemButton.link = info and info.link or ("item:" .. recipeItem)
			recipeItemButton.text:SetText(GOLD .. "Recipe item|r  " .. (info and info.link or ("item " .. recipeItem))
				.. recipeItemMarket(recipeItem))
			recipeItemButton:Show()
		else
			recipeItemButton.text:SetText("")
			recipeItemButton:Show()
		end
		recipeItemButton:SetHeight(recipeItem > 0 and 16 or 1)

		-- More than fit: the last line sums up the rest, and its tooltip lists them.
		local rows = result.rows
		local n = 0
		for i, src in ipairs(rows) do
			n = n + 1
			local row = sourceRows[n]
			if n == MAX_SOURCES and #rows > MAX_SOURCES then
				local rest = {}
				for j = i, #rows do table.insert(rest, rows[j]) end
				row.source = nil
				row.text:SetText(string.format("%sAnd %d more sources (hover to see them)|r", DIM, #rest))
				row.tip = function (tip)
					tip:SetText("More sources")
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

local parts = { icon, nameText, star, subText, description, reagentTitle, watermark }

local function showParts(on)
	for _, p in ipairs(parts) do if on then p:Show() else p:Hide() end end
	if not on then
		noReagents:Hide()
		for _, slot in ipairs(reagentSlots) do slot:Hide2() end
		shopRow:Hide()
		hideSources()
		hidePrices()
		hideResults()
		perkLine:Hide()
	end
end

local function draw(r)
	gearStrip:SetSkill(not M.linked and M.skill or nil)
	if not r then
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
	local below = drawShopping(r, #r.reagents > 0 and reagentSlots[rows] or noReagents)
	below = drawPrices(r, below)
	if r.refine then drawResults(r, below) else hideResults() end
	if r.learned then
		hideSources()
	else
		drawSources(r, below)
	end
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
RPF.On("HIDDEN", function () whereToken = whereToken + 1 end)

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
