-- The profession window, laid out like retail's (and WoW Forever's): the profession's portrait
-- and a full-width skill bar with the chat link on top, the recipe list with its search and
-- filter on the left, the selected recipe on the right (Detail.lua) with Create All, the amount
-- and Create under it. A stock Blizzard dialog frame, skinned by DragonUI when it's loaded, and
-- dressed in DragonUI's own professions window art (RPF.ProfArt) when that DragonUI has it.
-- Drag it by the title bar; it remembers where it was put.

local RPF = RetailProfessions
local M = RPF.Model

local WIDTH, HEIGHT = 740, 560
local LIST_WIDTH = 276
local LIST_ROWS = 24

local frame = CreateFrame("Frame", "RetailProfessionsFrame", UIParent)
frame:SetSize(WIDTH, HEIGHT)
frame:EnableMouse(true)
frame:SetToplevel(true)
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:Hide()
table.insert(UISpecialFrames, "RetailProfessionsFrame")
RPF.frame = frame
-- DragonUI's professions window, while we live in it (Host.lua), is up.
local hostOpen = false

local function placeFrame()
	frame:ClearAllPoints()
	local p = RetailProfessionsDB and RetailProfessionsDB.position
	if p then
		frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 60, -104)
	end
end

RPF.On("RESET_POSITION", function ()
	RetailProfessionsDB.position = nil
	placeFrame()
	RPF.Fire("MOVED")
end)

local dragon, contentTop = RPF.DressWindow(frame, {
	portrait = true,
	profArt = true,
	closeName = "RetailProfessionsFrameCloseButton",
	onMoved = function ()
		local point, _, relativePoint, x, y = frame:GetPoint(1)
		RetailProfessionsDB.position = { point, relativePoint, x, y }
		RPF.Fire("MOVED")
	end,
})
local title = frame.title
-- With DragonUI's professions art, the window is laid out as DragonUI's own professions window:
-- the skill bar in the band along the top, the list in the column on the left and the recipe on
-- a card to its right.
local art = frame.profArt
local ART_LIST_LEFT, ART_LIST_WIDTH, ART_CARD_LEFT, ART_TOP = 5, 304, 311, -72
local ART_LIST_ROWS = 22

local content = CreateFrame("Frame", nil, frame)
if art then
	content:SetPoint("TOPLEFT", frame, "TOPLEFT", ART_LIST_LEFT, -36)
	content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 6)
else
	content:SetPoint("TOPLEFT", frame, "TOPLEFT", dragon and 10 or 14, contentTop)
	content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", dragon and -10 or -14, dragon and 10 or 14)
end

-----------------------------------------
-- header: the skill bar across the window, and the chat link

local header = CreateFrame("Frame", nil, content)
header:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
header:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
header:SetHeight(art and 30 or 26)

-- The stock frame has no portrait ring, so its icon sits beside the bar instead.
local profIcon = header:CreateTexture(nil, "ARTWORK")
profIcon:SetSize(22, 22)
profIcon:SetPoint("LEFT", header, "LEFT", 2, 0)
profIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
if frame.portrait then profIcon:Hide() end

local linkButton
if art then
	linkButton = RPF.CreateSquareButton(header, 23)
	art.Art.Set(linkButton.icon, "link-icon", true)
else
	linkButton = CreateFrame("Button", nil, header)
	linkButton:SetSize(28, 28)
	linkButton:SetPoint("RIGHT", header, "RIGHT", -2, 2)
	linkButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Up")
	linkButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Down")
	linkButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
end
linkButton:SetScript("OnClick", function ()
	local link = GetTradeSkillListLink and GetTradeSkillListLink()
	if not link then return end
	if not ChatEdit_InsertLink(link) then ChatFrame_OpenChat(link) end
end)
linkButton:SetScript("OnEnter", function (self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText("Link this profession")
	GameTooltip:AddLine("Puts a link in chat that shows everyone your recipes.", 1, 1, 1, true)
	GameTooltip:Show()
end)
linkButton:SetScript("OnLeave", function () GameTooltip:Hide() end)

-- The craft proc log (ProcLog.lua), when the server rolls Multicraft and Resourcefulness.
local logButton
if art then
	logButton = RPF.CreateSquareButton(header, 23)
	logButton.icon:SetSize(17, 17)
	logButton.icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
	logButton.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
else
	logButton = CreateFrame("Button", nil, header)
	logButton:SetSize(22, 22)
	logButton:SetPoint("RIGHT", linkButton, "LEFT", -2, -2)
	local icon = logButton:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(logButton)
	icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	logButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
end
logButton:SetScript("OnClick", function () RPF.ProcLog.Toggle() end)
logButton:SetScript("OnEnter", function (self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText("Craft procs")
	GameTooltip:AddLine("Every Multicraft, Resourcefulness and Finesse you've had, and how often they come up. Also /prof log.",
		1, 1, 1, true)
	GameTooltip:Show()
end)
logButton:SetScript("OnLeave", function () GameTooltip:Hide() end)

local skillBar, skillText
if art then
	-- DragonUI's skill bar where its window has it, the chat link and the proc log after it.
	skillBar = RPF.CreateRankBar(header)
	skillBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 110, -40)
	linkButton:SetPoint("LEFT", skillBar, "RIGHT", -2, -4)
	logButton:SetPoint("LEFT", linkButton, "RIGHT", 3, 0)
else
	-- The character window's skill bar look.
	skillBar = CreateFrame("StatusBar", nil, header)
	skillBar:SetHeight(15)
	skillBar:SetPoint("LEFT", header, "LEFT", frame.portrait and 54 or 30, 0)
	skillBar:SetPoint("RIGHT", linkButton, "LEFT", -6, -2)
	if dragon then
		skillBar:SetStatusBarTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
		skillBar:SetStatusBarColor(0.95, 0.6, 0.1)
		local bg = skillBar:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(skillBar)
		bg:SetTexture(0, 0, 0, 0.65)
		local border = CreateFrame("Frame", nil, skillBar)
		border:SetPoint("TOPLEFT", skillBar, "TOPLEFT", -4, 4)
		border:SetPoint("BOTTOMRIGHT", skillBar, "BOTTOMRIGHT", 4, -4)
		border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
		border:SetBackdropBorderColor(0.7, 0.7, 0.7, 1)
	else
		RPF.StockSkillBar(skillBar, 15)
	end
	skillText = skillBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	skillText:SetPoint("CENTER", skillBar, "CENTER", 0, 1)
end
skillBar:EnableMouse(true)
skillBar:SetScript("OnEnter", function (self)
	-- Or another addon's page's skill (Pages.lua).
	local page = RPF.Pages and RPF.Pages.Header()
	local name, rank, bonus, maxRank = M.skillName, M.baseRank, M.bonus, M.maxRank
	if page then name, rank, bonus, maxRank = page.skill, page.rank, 0, page.maxRank end
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
	GameTooltip:SetText((name or "") .. " - " .. RPF.RankTitle(maxRank))
	RPF.AddSkillLines(GameTooltip, rank, bonus, maxRank)
	GameTooltip:Show()
end)
skillBar:SetScript("OnLeave", function () GameTooltip:Hide() end)

-----------------------------------------
-- left: search, filter, list

local left
if art then
	-- The backdrop draws the column; nothing else goes under the list.
	left = CreateFrame("Frame", nil, content)
	left:SetPoint("TOPLEFT", frame, "TOPLEFT", ART_LIST_LEFT, ART_TOP)
	left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", ART_LIST_LEFT, 8)
	left:SetWidth(ART_LIST_WIDTH)
else
	left = RPF.CreateInset(content)
	left:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
	left:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
	left:SetWidth(LIST_WIDTH)
end

local search = RPF.CreateEditBox(left, LIST_WIDTH - 136)
search:SetPoint("TOPLEFT", left, "TOPLEFT", art and 13 or 14, -8)
search:SetTextInsets(16, 4, 0, 0)
-- DragonUI's professions search box: its dark field and magnifying glass.
local foreverSearch = art and RPF.SkinProfArtEditBox(search)
do
	local glass = search:CreateTexture(nil, "OVERLAY")
	if foreverSearch and RPF.Dragon().ForeverUI.SetAtlas(glass, "common-search-magnifyingglass") then
		glass:SetSize(10, 10)
		glass:SetPoint("LEFT", search, "LEFT", 1, -1)
		glass:SetVertexColor(0.6, 0.6, 0.6)
	else
		glass:SetTexture("Interface\\Minimap\\Tracking\\None")
		glass:SetSize(14, 14)
		glass:SetPoint("LEFT", search, "LEFT", 0, 0)
		glass:SetVertexColor(0.7, 0.7, 0.7)
	end
	-- Short enough for the box, and cut off at its edge whatever the font; hovering says the rest.
	local hint = search:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("LEFT", search, "LEFT", 17, 0)
	hint:SetPoint("RIGHT", search, "RIGHT", -4, 0)
	hint:SetJustifyH("LEFT")
	hint:SetWordWrap(false)
	hint:SetText(SEARCH or "Search")
	hint:SetTextColor(0.6, 0.6, 0.6)
	search.hint = hint
	search:SetScript("OnEnter", function (self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(SEARCH or "Search")
		GameTooltip:AddLine("Finds recipes by their name or by a reagent they use.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	search:SetScript("OnLeave", function () GameTooltip:Hide() end)
	-- DragonUI's skin turns the input border into a plain dark field; give the box an edge so
	-- it reads as something to type in.
	if dragon and not foreverSearch then
		local edge = CreateFrame("Frame", nil, search)
		edge:SetPoint("TOPLEFT", search, "TOPLEFT", -6, 3)
		edge:SetPoint("BOTTOMRIGHT", search, "BOTTOMRIGHT", 2, -3)
		edge:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
		edge:SetBackdropBorderColor(0.75, 0.6, 0.25, 1)
		edge:EnableMouse(false)
	end
end

-- The profit view (Profit.lua): the list ranked by what crafting and selling each recipe earns.
local profitButton
if art then
	profitButton = RPF.CreateSquareButton(left, 23)
	profitButton.icon:SetSize(17, 17)
	profitButton.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
	profitButton.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
else
	profitButton = RPF.CreateButton(left, "", 26, 22)
	profitButton:SetPoint("LEFT", search, "RIGHT", 6, 0)
	local coin = profitButton:CreateTexture(nil, "OVERLAY")
	coin:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
	coin:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	coin:SetSize(16, 16)
	coin:SetPoint("CENTER", profitButton, "CENTER", 0, 0)
end

local filterButton = art and RPF.CreateMenuButton(left, FILTER or "Filter", 89) or RPF.CreateButton(left, FILTER or "Filter", 78, 22)
if art then
	-- As DragonUI's: Filter at the column's top right, the search box filling up to it.
	filterButton:SetPoint("TOPRIGHT", left, "TOPRIGHT", -4, -5)
	profitButton:SetPoint("RIGHT", filterButton, "LEFT", -3, 0)
	search:SetPoint("RIGHT", profitButton, "LEFT", -6, 0)
else
	filterButton:SetPoint("LEFT", profitButton, "RIGHT", 4, 0)
end
if not filterButton.hasArrow then
	local arrow = filterButton:CreateTexture(nil, "OVERLAY")
	arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
	arrow:SetSize(10, 12)
	arrow:SetPoint("RIGHT", filterButton, "RIGHT", -6, 0)
end

RPF.filter = { text = "", haveMats = false, skillUp = false, slot = nil, learnableOnly = false }
RPF.selected = nil -- the selected recipe (from the model)

local list
local Rebuild

local function isTracked(r)
	return r.spell and RetailProfessionsCharDB.tracked[r.spell] ~= nil
end

list = RPF.CreateRecipeList(left, {
	rows = art and ART_LIST_ROWS or LIST_ROWS,
	onSelect = function (r)
		-- Picking a recipe hands the keyboard back to the game (C for the character window...).
		search:ClearFocus()
		RPF.Select(r)
	end,
	onToggle = function (key)
		RetailProfessionsCharDB.collapsed[key] = not RetailProfessionsCharDB.collapsed[key] or nil
		Rebuild(true)
	end,
	isSelected = function (r) return RPF.selected == r end,
	isTracked = isTracked,
	isFavorite = function (r) return RPF.IsFavorite(r.spell) end,
	onTrackToggle = function (r) RPF.ToggleTracked(r) end,
})
list:SetPoint("TOPLEFT", left, "TOPLEFT", art and 8 or 6, art and -35 or -34)
list:SetPoint("RIGHT", left, "RIGHT", art and -4 or -6, 0)
RPF.list = list

search:SetScript("OnTextChanged", function (self)
	local text = self:GetText() or ""
	if text == "" then self.hint:Show() else self.hint:Hide() end
	if text ~= RPF.filter.text then
		RPF.filter.text = text
		RPF.Debounce("search", 0.15, function () Rebuild() end)
	end
end)
search:SetScript("OnEditFocusGained", function (self) self.hint:Hide() end)
search:SetScript("OnEditFocusLost", function (self) if (self:GetText() or "") == "" then self.hint:Show() end end)

-- filter menu
local menu = CreateFrame("Frame", "RetailProfessionsFilterMenu", UIParent, "UIDropDownMenuTemplate")

local function filterMenu()
	local f = RPF.filter
	local function toggle(key)
		return function ()
			f[key] = not f[key]
			Rebuild()
		end
	end
	local refine = RPF.Refine.Active()
	local items = {
		{ text = "Filters", isTitle = true, notCheckable = true },
		{ text = "Have materials", checked = f.haveMats, keepShownOnClick = true, isNotRadio = true, func = toggle("haveMats") },
	}
	if not refine then
		table.insert(items, { text = "Has skill-up", checked = f.skillUp, keepShownOnClick = true, isNotRadio = true,
			func = toggle("skillUp") })
	end
	if M.hasServerData and not refine then
		table.insert(items, { text = "Show unlearned recipes", checked = RetailProfessionsDB.showUnlearned, keepShownOnClick = true,
			isNotRadio = true, func = function ()
				RetailProfessionsDB.showUnlearned = not RetailProfessionsDB.showUnlearned
				Rebuild()
			end })
		table.insert(items, { text = "    Only ones I can learn now", checked = f.learnableOnly, keepShownOnClick = true,
			isNotRadio = true, disabled = not RetailProfessionsDB.showUnlearned, func = toggle("learnableOnly") })
	end
	if RPF.HasReagentBank() then
		table.insert(items, { text = "Count the reagent bank", checked = RetailProfessionsDB.countBank, keepShownOnClick = true,
			isNotRadio = true, func = function ()
				RetailProfessionsDB.countBank = not RetailProfessionsDB.countBank
				Rebuild(true)
			end })
	end

	local slots = refine and {} or M.SlotsPresent()
	if #slots > 0 then
		local sub = { { text = "All slots", checked = f.slot == nil, func = function () f.slot = nil; CloseDropDownMenus(); Rebuild() end } }
		for _, slot in ipairs(slots) do
			table.insert(sub, { text = M.SlotName(slot), checked = f.slot == slot,
				func = function () f.slot = slot; CloseDropDownMenus(); Rebuild() end })
		end
		table.insert(items, { text = "Slot" .. (f.slot and (": |cffffffff" .. M.SlotName(f.slot) .. "|r") or ""),
			hasArrow = true, notCheckable = true, menuList = sub })
	end

	table.insert(items, { text = "", disabled = true, notCheckable = true })
	table.insert(items, { text = "Expand all", notCheckable = true, func = function ()
		wipe(RetailProfessionsCharDB.collapsed)
		Rebuild(true)
	end })
	table.insert(items, { text = "Collapse all", notCheckable = true, func = function ()
		local all = refine and RPF.Refine.Rows({}, {}) or M.Rows({ unlearned = RetailProfessionsDB.showUnlearned }, {})
		for _, row in ipairs(all) do
			if row.key then RetailProfessionsCharDB.collapsed[row.key] = true end
		end
		Rebuild(true)
	end })
	table.insert(items, { text = "Reset filters", notCheckable = true, func = function ()
		f.haveMats, f.skillUp, f.slot, f.learnableOnly = false, false, nil, false
		search:SetText("")
		Rebuild()
	end })
	return items
end

filterButton:SetScript("OnClick", function (self)
	EasyMenu(filterMenu(), menu, self, 0, 0, "MENU")
end)

local function profitView()
	return RetailProfessionsDB.profitView and not M.linked and not RPF.Refine.Active()
end

profitButton:SetScript("OnClick", function ()
	-- Shift-click asks for every price again.
	if profitView() and IsShiftKeyDown() then
		RPF.Profit.Fetch(RPF.Profit.ProfessionEntries(), true)
	else
		RetailProfessionsDB.profitView = not RetailProfessionsDB.profitView or nil
	end
	search:ClearFocus()
	Rebuild(true)
end)
profitButton:SetScript("OnEnter", function (self)
	local P = RPF.Profit
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText("Craft for profit")
	GameTooltip:AddLine("Ranks the recipes you know by what the item sells for on the auction house, after the house cut, "
		.. "minus what the materials cost: Craft now (you have the materials, bags and reagent bank), Buy materials "
		.. "and craft, and the rest.", 1, 1, 1, true)
	GameTooltip:AddLine("Materials are priced at the cheaper of a vendor and the lowest buyout, even the ones you have: "
		.. "crafting has to beat selling them as they are.", 0.7, 0.7, 0.7, true)
	if profitView() then
		local age = P.Age(P.ProfessionEntries())
		if P.Fetching() then
			GameTooltip:AddLine("Looking up prices...", 0.6, 0.6, 0.6)
		elseif age then
			GameTooltip:AddLine(string.format("Prices from %s ago. Shift-click to look again.", RPF.Duration(age)), 0.6, 0.6, 0.6)
		end
		GameTooltip:AddLine("Click to go back to the recipe list.", 0.5, 0.5, 0.5)
	end
	GameTooltip:Show()
end)
profitButton:SetScript("OnLeave", function () GameTooltip:Hide() end)

local function filtersActive()
	local f = RPF.filter
	if RPF.Refine.Active() then return f.haveMats end
	return f.haveMats or f.skillUp or f.slot or f.learnableOnly
end

-----------------------------------------
-- right: the recipe, its options along the bottom edge (Track Recipe and, with ReagentBankUI,
-- the two reagent bank ones), and Create All / amount / Create under it

local right
if art then
	-- DragonUI's recipe card, where its window puts it.
	right = RPF.DressCard(CreateFrame("Frame", nil, content))
	right:SetPoint("TOPLEFT", frame, "TOPLEFT", ART_CARD_LEFT, ART_TOP)
	right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 38)
else
	right = RPF.CreateInset(content)
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
	right:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 30)
end
RPF.detailPane = right

local controls = CreateFrame("Frame", nil, content)
controls:SetPoint("TOPLEFT", right, "BOTTOMLEFT", 0, art and -6 or -4)
controls:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)

-- The pieces DragonUI's professions window takes in when we live in it (Host.lua).
function RPF.HostPieces()
	return { list = left, card = right, controls = controls, log = logButton }
end

-- The Training and Profit views (Home.lua) lay themselves over these under the skill bar.
RPF.content, RPF.header, RPF.panes = content, header, { left, right, controls }

-- Another addon's page (Pages.lua) lies over them too: a list column where ours is and a card
-- where the recipe's is, down to the window's bottom (a page has no craft controls).
function RPF.NewPagePanel()
	local panel = CreateFrame("Frame", nil, content)
	panel:SetAllPoints(content)
	panel:Hide()
	local column, card
	if art then
		column = CreateFrame("Frame", nil, panel)
		column:SetPoint("TOPLEFT", frame, "TOPLEFT", ART_LIST_LEFT, ART_TOP)
		column:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", ART_LIST_LEFT, 8)
		column:SetWidth(ART_LIST_WIDTH)
		card = RPF.DressCard(CreateFrame("Frame", nil, panel))
		card:SetPoint("TOPLEFT", frame, "TOPLEFT", ART_CARD_LEFT, ART_TOP)
		card:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
	else
		column = RPF.CreateInset(panel)
		column:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
		column:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
		column:SetWidth(LIST_WIDTH)
		card = RPF.CreateInset(panel)
		card:SetPoint("TOPLEFT", column, "TOPRIGHT", 6, 0)
		card:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
	end
	panel.list, panel.card, panel.art = column, card, art and true or false
	return panel
end

local createAllButton = RPF.CreateButton(controls, CREATE_ALL or "Create All", 110, 22)
createAllButton:SetPoint("LEFT", controls, "LEFT", 0, 0)

local createButton = RPF.CreateButton(controls, CREATE or "Create", 110, 22)
createButton:SetPoint("RIGHT", controls, "RIGHT", 0, 0)

local quantity = RPF.CreateEditBox(controls, 32, true)
quantity:SetPoint("CENTER", controls, "CENTER", 0, 0)
quantity:SetJustifyH("CENTER")
quantity:SetMaxLetters(3)
quantity:SetText("1")
if art then RPF.SkinProfArtEditBox(quantity) end

local minus = CreateFrame("Button", nil, controls)
minus:SetSize(22, 22)
minus:SetPoint("RIGHT", quantity, "LEFT", -6, 0)
minus:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
minus:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
minus:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled")
minus:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

local plus = CreateFrame("Button", nil, controls)
plus:SetSize(22, 22)
plus:SetPoint("LEFT", quantity, "RIGHT", 2, 0)
plus:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
plus:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
plus:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled")
plus:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

local trackCheck = RPF.CreateCheck(right, "Track Recipe")
trackCheck:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 8, 6)
trackCheck:SetScript("OnClick", function ()
	if RPF.selected then RPF.ToggleTracked(RPF.selected) end
end)

-- With ReagentBankUI: craft straight from the reagent bank. Create takes what the bags lack
-- out of the bank first (ReagentBankUI's Withdraw Needed), then crafts once it has arrived.
local bankCheck = RPF.CreateCheck(right, "Use reagent bank")
bankCheck:SetPoint("LEFT", trackCheck.label, "RIGHT", 14, 0)
bankCheck:SetScript("OnClick", function (self)
	RetailProfessionsDB.autoWithdraw = self:GetChecked() and true or false
	RPF.Fire("BAGS")
end)
bankCheck:SetScript("OnEnter", function (self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText("Use reagent bank")
	GameTooltip:AddLine("Create and Create All take whatever your bags are missing out of the reagent bank, then craft.", 1, 1, 1, true)
	GameTooltip:Show()
end)
bankCheck:SetScript("OnLeave", function () GameTooltip:Hide() end)

local function bankWithdrawAvailable()
	local RB = _G.ReagentBankUI
	return RB and RB.WithdrawNeededForSelectedRecipe and RPF.HasReagentBank() and true or false
end

local function usingBank()
	return bankWithdrawAvailable() and RetailProfessionsDB.autoWithdraw ~= false
end

-- What came out of the bank and wasn't used goes back when the window closes. The setting is
-- ReagentBankUI's own (/rbank autodeposit flips it too).
local leftoversCheck = RPF.CreateCheck(right, "Deposit leftovers")
leftoversCheck:SetPoint("LEFT", bankCheck.label, "RIGHT", 14, 0)
leftoversCheck:SetScript("OnClick", function (self)
	RPF.SetDepositLeftovers(self:GetChecked())
end)
leftoversCheck:SetScript("OnEnter", function (self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText("Deposit leftovers")
	GameTooltip:AddLine("When you close this window, reagents that came out of the reagent bank for a craft and "
		.. "weren't used go back into it. What was in your bags before stays there.", 1, 1, 1, true)
	if not usingBank() then
		GameTooltip:AddLine("Needs Use reagent bank.", 1, 0.25, 0.25)
	end
	GameTooltip:Show()
end)
leftoversCheck:SetScript("OnLeave", function () GameTooltip:Hide() end)

-- Enchants: the item to put them on, picked once instead of after every cast. It sits at the
-- bottom right of the recipe pane, above the options.
local target = RPF.CreateItemButton(right, 28)
target:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -10, 34)
target:RegisterForClicks("LeftButtonUp", "RightButtonUp")
target.label = right:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
target.label:SetPoint("RIGHT", target, "LEFT", -6, 0)
target.label:SetText("Enchant:")
do
	local bg = target:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("TOPLEFT", target, "TOPLEFT", -2, 2)
	bg:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 2, -2)
	bg:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
	bg:SetTexCoord(0.15, 0.85, 0.15, 0.85)
end
RPF.enchantTarget = nil -- { id = item id, bag, slot } or { id, inv }

-- A line of feedback above the options, clear of the Enchant slot.
local status = right:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
status:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 12, 32)
status:SetPoint("RIGHT", right, "RIGHT", -110, 0)
status:SetJustifyH("LEFT")
status:SetJustifyV("BOTTOM")
status:SetHeight(28)

local statusToken = 0
function RPF.Status(text, isError)
	statusToken = statusToken + 1
	local mine = statusToken
	status:SetText(text or "")
	if isError then status:SetTextColor(1, 0.25, 0.25) else status:SetTextColor(1, 0.82, 0) end
	RPF.After(8, function () if mine == statusToken then status:SetText("") end end)
end

-- In DragonUI's window (Host.lua) the card is its own, narrower one: no card art of ours, and the
-- reagent bank options go on a row above Track Recipe, the feedback line over them.
function RPF.HostLayout(on)
	if right.SetCardArtShown then right:SetCardArtShown(not on) end
	bankCheck:ClearAllPoints()
	status:ClearAllPoints()
	if on then
		bankCheck:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 8, 28)
		status:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 12, 54)
	else
		bankCheck:SetPoint("LEFT", trackCheck.label, "RIGHT", 14, 0)
		status:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 12, 32)
	end
	status:SetPoint("RIGHT", right, "RIGHT", -110, 0)
end

local function getQuantity()
	return math.max(1, math.min(999, tonumber(quantity:GetText()) or 1))
end

-- A ReagentBankUI that still has its sidebar keeps its own "Crafts" count and withdraws for
-- that, not for ours, so the two are kept equal: ours goes to it on every change, and it sets
-- ours through the provider. Later ones read the amount from this window.
local fromBank = false
local function pushToBank(n)
	local RB = _G.ReagentBankUI
	if fromBank or not (RB and RB.SetTradeSkillPrepareCount) then return end
	pcall(RB.SetTradeSkillPrepareCount, RB, n, false)
end

local function setQuantity(n)
	n = math.max(1, math.min(999, math.floor(tonumber(n) or 1)))
	local changed = quantity:GetText() ~= tostring(n)
	quantity:SetText(tostring(n))
	pushToBank(n)
	if changed then RPF.Fire("QUANTITY", n) end
end
RPF.GetQuantity, RPF.SetQuantity = getQuantity, setQuantity

local function setQuantityFromBank(n)
	fromBank = true
	setQuantity(n)
	fromBank = false
end

plus:SetScript("OnClick", function () setQuantity(getQuantity() + (IsShiftKeyDown() and 10 or 1)) end)
minus:SetScript("OnClick", function () setQuantity(getQuantity() - (IsShiftKeyDown() and 10 or 1)) end)
quantity:SetScript("OnEditFocusLost", function () setQuantity(getQuantity()) end)
quantity:SetScript("OnTextChanged", function (self, userInput)
	local n = tonumber(self:GetText())
	if userInput and n and n > 0 then
		pushToBank(math.min(999, math.floor(n)))
		RPF.Fire("QUANTITY", n)
	end
end)

-- The search box and the amount only take the keyboard when clicked: InputBoxTemplate's boxes
-- grab focus by default, and clicking anywhere else in the window lets go of it.
local function releaseKeyboard()
	search:ClearFocus()
	quantity:ClearFocus()
end
search:ClearFocus()
quantity:ClearFocus()
frame:HookScript("OnMouseDown", releaseKeyboard)
left:EnableMouse(true)
left:SetScript("OnMouseDown", releaseKeyboard)
right:EnableMouse(true)
right:SetScript("OnMouseDown", releaseKeyboard)

-----------------------------------------
-- enchant target

-- Where an item with this link is: equipped or in the bags.
local function findItem(link)
	for slot = 1, 19 do
		if GetInventoryItemLink("player", slot) == link then return { id = RPF.ItemIdFromLink(link), inv = slot } end
	end
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, GetContainerNumSlots(bag) do
			if GetContainerItemLink(bag, slot) == link then return { id = RPF.ItemIdFromLink(link), bag = bag, slot = slot } end
		end
	end
	return nil
end

-- The target's current link, or nil once that slot holds something else. Enchanting changes an
-- item's link, so the target is kept by place and item id, not by link.
local function targetLink(t)
	if not t then return nil end
	local link
	if t.inv then link = GetInventoryItemLink("player", t.inv) else link = GetContainerItemLink(t.bag, t.slot) end
	if link and RPF.ItemIdFromLink(link) == t.id then return link end
	return nil
end

local function refreshTarget()
	local link = targetLink(RPF.enchantTarget)
	if not link then RPF.enchantTarget = nil end
	if link then
		local _, _, quality, _, _, _, _, _, _, texture = GetItemInfo(link)
		target:SetItem(texture, quality)
	else
		target:SetItem(nil)
	end
end

local function takeCursorItem()
	local kind, _, link = GetCursorInfo()
	if kind ~= "item" or not link then return false end
	ClearCursor()
	local found = findItem(link)
	if found then
		RPF.enchantTarget = found
		refreshTarget()
	end
	return true
end

target:SetScript("OnReceiveDrag", takeCursorItem)
target:SetScript("OnClick", function (self, button)
	if button == "RightButton" then
		RPF.enchantTarget = nil
		refreshTarget()
	elseif not takeCursorItem() then
		RPF.Status("Drop an item here to enchant it, or leave it empty to pick one after casting.")
	end
end)
target:SetScript("OnEnter", function (self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	local link = targetLink(RPF.enchantTarget)
	if link then
		GameTooltip:SetHyperlink(link)
		GameTooltip:AddLine("Right-click to clear.", 0.5, 0.5, 0.5)
	else
		GameTooltip:SetText("Item to enchant")
		GameTooltip:AddLine("Drop an item from your bags or character window here.", 1, 1, 1, true)
		GameTooltip:AddLine("Without one you pick the item after casting, as usual.", 0.7, 0.7, 0.7, true)
	end
	GameTooltip:Show()
end)
target:SetScript("OnLeave", function () GameTooltip:Hide() end)

-----------------------------------------
-- crafting

local pendingCraft -- { key, count, untilTime }: waiting for reagents from the bank
local countdown -- { key, name, left, shown }: what Create started, counted down in the amount box

-- What tells one row from another: a recipe's spell, or a herb's or ore's key (Refine.lua).
local function keyOf(r)
	return r and (r.spell or r.key) or nil
end

-- The trade skill can end while the window stays up (a trade or inspect window, another profession;
-- DragonUI's window outlives it): the client then reads UNKNOWN, and nothing can be cast until it's
-- opened again. Create does that then, through a secure button over it (casting takes one).
local function sessionClosed()
	local line = GetTradeSkillLine()
	return not RPF.active or not line or line == "UNKNOWN"
end

local function sayReopen()
	RPF.Status((M.skillName or "The profession") .. " closed behind this window. Press Reopen, or open it from your spellbook.", true)
end

-- Made when first needed: Secure.lua loads after this file.
local reopenButton

local function updateControls()
	local r = RPF.selected
	local learned = r and r.learned and not M.linked
	-- A herb to mill or ore to prospect: the server does those, and one job runs at a time.
	local refine = learned and r.refine and RPF.Refine.Kind(r.refine) or nil
	local job = RPF.Refine.job or RPF.Refine.starting
	local bags, withBank = 0, 0
	if learned then bags, withBank = M.Craftable(r) end
	if refine and (RPF.Refine.SkillTooLow(r) or job) then bags, withBank = 0, 0 end
	-- With the bank in use, what the bank holds counts as if it were in the bags.
	if usingBank() then bags = math.max(bags, withBank) end
	if pendingCraft then bags = 0 end
	local onCooldown = learned and r.cooldown and r.cooldown > 0
	local enchant = learned and r.isEnchant

	-- While a job runs, the button on its herbs and ore stops it.
	local running = refine and RPF.Refine.job and true or false
	RPF.SetEnabled(createButton, (learned and bags > 0 and not onCooldown) or running)
	RPF.SetEnabled(createAllButton, learned and bags > 0 and not onCooldown and not enchant)
	-- An unlearned recipe takes an amount too: its materials can go on the shopping list.
	local amount = r and not M.linked and not enchant and not (refine and job)
	RPF.SetEnabled(plus, amount)
	RPF.SetEnabled(minus, amount)
	if enchant then setQuantity(1) end
	if running then
		createButton:SetText("Stop")
	else
		createButton:SetText(refine and refine.verb or r and r.learned and r.altVerb or CREATE or "Create")
	end
	createAllButton:SetText((refine and refine.all or CREATE_ALL or "Create All") .. " [" .. (enchant and 0 or bags) .. "]")

	if enchant then
		target:Show(); target.label:Show()
		refreshTarget()
	else
		target:Hide(); target.label:Hide()
	end
	if M.linked then
		trackCheck:Hide()
		minus:Hide(); plus:Hide(); quantity:Hide(); createButton:Hide(); createAllButton:Hide()
	else
		-- The tracker follows recipes; a herb isn't one.
		if refine then trackCheck:Hide() else trackCheck:Show() end
		minus:Show(); plus:Show(); quantity:Show(); createButton:Show(); createAllButton:Show()
	end
	if bankWithdrawAvailable() and not M.linked then
		bankCheck:Show()
		bankCheck:SetChecked(RetailProfessionsDB.autoWithdraw ~= false)
		leftoversCheck:Show()
		leftoversCheck:SetChecked(RPF.DepositLeftovers())
		RPF.SetEnabled(leftoversCheck, usingBank())
		leftoversCheck.label:SetAlpha(usingBank() and 1 or 0.5)
	else
		bankCheck:Hide()
		leftoversCheck:Hide()
	end
	trackCheck:SetChecked(r and isTracked(r))
	RPF.SetEnabled(trackCheck, r ~= nil)

	local p = learned and not refine and sessionClosed() and RPF.Profession(M.skill)
	if p and p.openName then
		createButton:SetText("Reopen")
		RPF.SetEnabled(createButton, true)
		reopenButton = reopenButton or RPF.CreateSpellButton(nil)
		RPF.BindSpellButton(reopenButton, createButton, p.openName, RPF.Window())
	elseif reopenButton then
		RPF.BindSpellButton(reopenButton, nil, nil)
	end
end
RPF.UpdateControls = updateControls

-- Whether the bags hold every reagent for `count` crafts.
local function bagsCover(r, count)
	for _, rg in ipairs(r.reagents) do
		if rg.id and (GetItemCount(rg.id) or 0) < rg.n * count then return false end
	end
	return true
end

local craftNow

-- Shift-click Enchant with an item in the Enchant slot: the game's "replace the enchant?" and
-- "this binds the item to you" questions for that one cast are answered yes. They come as the
-- REPLACE_ENCHANT and BIND_ENCHANT events, which UIParent turns into popups.
local confirmUntil = 0

local confirmEvents = CreateFrame("Frame")
confirmEvents:RegisterEvent("REPLACE_ENCHANT")
confirmEvents:RegisterEvent("BIND_ENCHANT")
confirmEvents:SetScript("OnEvent", function (self, event, ...)
	if GetTime() > confirmUntil then return end
	confirmUntil = 0
	local popup = event
	local a1, a2 = ...
	if event == "REPLACE_ENCHANT" then ReplaceEnchant() else BindEnchant() end
	-- UIParent may show its popup after us; close it either way.
	StaticPopup_Hide(popup)
	RPF.After(0, function () StaticPopup_Hide(popup) end)
	-- Should the game want a real click for the answer, the cast won't have started: put the
	-- question back so it can be answered by hand.
	RPF.After(0.5, function ()
		if not UnitCastingInfo("player") and not SpellIsTargeting() then
			StaticPopup_Show(popup, a1, a2)
		end
	end)
end)

local function craft(count, noConfirm)
	local r = RPF.selected
	if not (r and r.learned) then return end
	if not r.refine and sessionClosed() then
		sayReopen()
		updateControls()
		return
	end
	if r.isEnchant then count = 1 end
	-- Short in the bags but the bank has it: fetch it first, craft when it lands.
	if usingBank() and not bagsCover(r, count) then
		local _, withBank = M.Craftable(r)
		if withBank >= count then
			setQuantity(count)
			-- Withdraw Needed fetches for ReagentBankUI's own count; make sure it's this one.
			if _G.ReagentBankUI.SetTradeSkillPrepareCount then
				pcall(_G.ReagentBankUI.SetTradeSkillPrepareCount, _G.ReagentBankUI, count, false)
			end
			local ok = pcall(_G.ReagentBankUI.WithdrawNeededForSelectedRecipe, _G.ReagentBankUI)
			if ok then
				pendingCraft = { key = keyOf(r), count = count, untilTime = GetTime() + 10, noConfirm = noConfirm }
				RPF.Status("Taking the reagents out of the reagent bank...")
				updateControls()
				RPF.After(10.1, function ()
					if pendingCraft and pendingCraft.untilTime <= GetTime() then
						pendingCraft = nil
						RPF.Status("The reagents didn't arrive from the bank. Is there room in your bags?", true)
						updateControls()
					end
				end)
				return
			end
		end
	end
	craftNow(r, count, noConfirm)
end

craftNow = function (r, count, noConfirm)
	if r.refine then
		RPF.Refine.Start(r, count)
		quantity:ClearFocus()
		return
	end
	if sessionClosed() then
		sayReopen()
		return
	end
	local index = M.IndexOf(r)
	if not index then
		RPF.Status("That recipe moved in the list; try again.", true)
		M.Resync()
		return
	end
	if r.isEnchant then
		local t = targetLink(RPF.enchantTarget) and RPF.enchantTarget or nil
		DoTradeSkill(index, 1)
		if t and SpellIsTargeting() then
			if noConfirm then confirmUntil = GetTime() + 3 end
			if t.inv then PickupInventoryItem(t.inv) else PickupContainerItem(t.bag, t.slot) end
		end
		return
	end
	-- Set first: a cast that can't start fails inside DoTradeSkill, and that ends it.
	RPF.StartCountdown(keyOf(r), (GetTradeSkillInfo(index)), count)
	DoTradeSkill(index, count)
	-- Typing a number and pressing Create straight away leaves the box focused.
	quantity:ClearFocus()
end

-- The amount counts down as the casts finish, so after an interruption Create makes only
-- what's still to do, while that recipe stays selected. An amount the player typed, or picking
-- another recipe, ends it.
local function showCountdown()
	local c = countdown
	if not c then return end
	if getQuantity() ~= c.shown then
		countdown = nil
		return
	end
	if keyOf(RPF.selected) == c.key then
		c.shown = math.max(1, c.left)
		setQuantity(c.shown)
	end
end

-- name: the cast to count (nil when the counts come from elsewhere, as for Milling);
-- count: what the box holds for it.
function RPF.StartCountdown(key, name, count)
	countdown = { key = key, name = name, left = count, shown = count }
end

-- Milling and Prospecting: the server says how many casts are left.
function RPF.CountdownLeft(key, left)
	if not (countdown and countdown.key == key) then return end
	countdown.left = left
	showCountdown()
end

RPF.On("CAST", function (event, spellName)
	local c = countdown
	if not (c and c.name and spellName == c.name) then return end
	if event ~= "UNIT_SPELLCAST_SUCCEEDED" then
		-- Create again mid-batch fails with "another action is in progress" under the same
		-- name while the batch goes on (3.3.5 events carry no cast id).
		if UnitCastingInfo("player") == c.name then return end
		countdown = nil
		return
	end
	if c.left <= 0 then return end
	c.left = c.left - 1
	showCountdown()
end)

createButton:SetScript("OnClick", function ()
	if RPF.Refine.job and RPF.selected and RPF.selected.refine then RPF.Refine.Stop() return end
	craft(getQuantity(), IsShiftKeyDown())
end)
createButton:SetScript("OnEnter", function (self)
	local r = RPF.selected
	if not (r and r.isEnchant and r.learned) then return end
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText(self:GetText())
	GameTooltip:AddLine("Shift-click with an item in the Enchant slot to skip the \"replace enchant\" and \"bind to you\" questions.", 1, 1, 1, true)
	GameTooltip:Show()
end)
createButton:SetScript("OnLeave", function () GameTooltip:Hide() end)
createAllButton:SetScript("OnClick", function ()
	local r = RPF.selected
	if not r then return end
	local bags, withBank = M.Craftable(r)
	if usingBank() then bags = math.max(bags, withBank) end
	if r.refine and (RPF.Refine.SkillTooLow(r) or RPF.Refine.job) then return end
	if bags > 0 then
		setQuantity(bags)
		craft(bags)
	end
end)

-----------------------------------------
-- selection and rebuilding

function RPF.Select(r, reveal)
	-- Another recipe starts at one: only the player (the amount, Create All) makes it more.
	if keyOf(r) ~= keyOf(RPF.selected) then
		countdown = nil
		setQuantity(1)
	end
	RPF.selected = r
	if r and r.learned and r.index and not M.linked then
		local index = M.IndexOf(r)
		if index and SelectTradeSkill then SelectTradeSkill(index) end
	end
	if r then M.Details(r) end
	-- Still on the recipe that was crafting: what it still has to make.
	showCountdown()
	RPF.Fire("SELECTED", r)
	updateControls()
	if reveal then list:Reveal(r) else list:Refresh() end
end

-- The window's title: Training or Profit, Milling or Prospecting, someone's linked profession,
-- or the profession.
function RPF.TitleText()
	local refine = RPF.Refine.Active()
	return RPF.Home.Title() or refine and refine.name
		or M.linked and ((M.linkedName or "") .. " - " .. (M.skillName or "")) or (M.skillName or "Professions")
end

-- Another addon's page (Pages.lua): its title and icon, its skill on the bar (none, no bar),
-- and none of the profession's buttons.
local function pageHeader(page)
	local icon = page.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
	if frame.portrait then RPF.SetPortrait(frame.portrait, icon) else profIcon:SetTexture(icon) end
	title:SetText(page.title or "")
	linkButton:Hide()
	logButton:Hide()
	if not page.rank then
		skillBar:Hide()
	elseif art then
		skillBar:Show()
		skillBar:SetRank(page.skill, page.rank, page.maxRank, page.art)
	else
		skillBar:Show()
		skillBar:SetPoint("RIGHT", header, "RIGHT", -2, 0)
		skillBar:SetMinMaxValues(0, math.max(1, page.maxRank or 1))
		skillBar:SetValue(page.rank)
		skillText:SetText(string.format("%s %d/%d", page.skill or "", page.rank, page.maxRank or 0))
	end
end

local function updateHeader()
	local page = RPF.Pages and RPF.Pages.Header()
	if page then
		pageHeader(page)
		return
	end
	local p = M.profession
	local texture = p and p.texture or (GetTradeSkillTexture and GetTradeSkillTexture()) or "Interface\\Icons\\INV_Misc_QuestionMark"
	if frame.portrait then RPF.SetPortrait(frame.portrait, texture) else profIcon:SetTexture(texture) end
	-- Someone else's linked profession: their name in the title.
	local refine = RPF.Refine.Active()
	title:SetText(RPF.TitleText())
	if art then
		local key = RPF.ProfArtKey(M.skillName)
		-- Runeforging has no rank to show, as in DragonUI.
		if key == "Runeforging" then
			skillBar:Hide()
		else
			skillBar:Show()
			skillBar:SetRank(M.skillName, M.baseRank, M.maxRank, key, M.bonus)
		end
		right:SetCardArt(key, texture)
	else
		skillBar:Show()
		skillBar:SetMinMaxValues(0, math.max(1, M.maxRank or 1))
		skillBar:SetValue(M.baseRank or 0)
		skillText:SetText((M.skillName or "") .. " " .. RPF.SkillRankText(M.baseRank, M.bonus, M.maxRank))
	end
	if M.linked then linkButton:Hide() else linkButton:Show() end
	local showLog = RPF.perks and not M.linked
	if showLog then logButton:Show() else logButton:Hide() end
	if not art then skillBar:SetPoint("RIGHT", showLog and logButton or linkButton, "LEFT", -6, showLog and 0 or -2) end
	if M.linked or refine then profitButton:Hide() else profitButton:Show() end
	if profitView() then profitButton:LockHighlight() else profitButton:UnlockHighlight() end
	filterButton:SetText(filtersActive() and ("|cff4fc3f7" .. (FILTER or "Filter") .. "|r") or (FILTER or "Filter"))
end

-- Reads the client again (unless only the view changed) and redraws.
Rebuild = function (viewOnly)
	if not RPF.IsOpen() then return end
	if not viewOnly and not M.Scan() then return end
	local f = RPF.filter
	local state = { text = f.text, haveMats = f.haveMats, skillUp = f.skillUp, slot = f.slot,
		unlearned = RetailProfessionsDB.showUnlearned and not M.linked, learnableOnly = f.learnableOnly,
		favorites = not M.linked and RetailProfessionsCharDB.favorites or nil }
	local refine = RPF.Refine.Active()
	local rows
	if refine then
		rows = RPF.Refine.Rows(state, RetailProfessionsCharDB.collapsed)
	elseif profitView() then
		RPF.Profit.Fetch(RPF.Profit.ProfessionEntries())
		rows = RPF.Profit.Rows(state, RetailProfessionsCharDB.collapsed)
	else
		rows = M.Rows(state, RetailProfessionsCharDB.collapsed)
	end
	if refine then
		list:SetEmptyText(RPF.Refine.EmptyText(filtersActive() or f.text ~= ""))
	elseif profitView() and #rows == 0 and not ((filtersActive() or f.text ~= "") and RPF.Profit.state == "ok") then
		list:SetEmptyText(RPF.Profit.EmptyText())
	elseif M.skill and not M.hasServerData and RPF.Has(RPF.HELLO_RECIPES) then
		list:SetEmptyText("Loading recipes...")
	else
		list:SetEmptyText((filtersActive() or f.text ~= "") and "No recipes match. Clear the search or filters." or "No recipes.")
	end
	list:SetRows(rows, true)
	updateHeader()

	-- Keep the selection when the recipe still exists (it's a new table after a scan).
	local selected
	if refine then
		selected = RPF.selected and RPF.selected.refine == refine.code and RPF.Refine.ByKey(RPF.selected.key) or nil
	else
		selected = RPF.selected and RPF.selected.spell and M.bySpell[RPF.selected.spell]
	end
	if not selected and not refine and RPF.selected and RPF.selected.learned then
		for _, r in ipairs(M.recipes) do if r.name == RPF.selected.name then selected = r break end end
	end
	if not selected and not refine then
		local index = GetTradeSkillSelectionIndex and GetTradeSkillSelectionIndex() or 0
		for _, r in ipairs(M.recipes) do if r.index == index then selected = r break end end
	end
	if not selected then
		for _, row in ipairs(rows) do if row.recipe then selected = row.recipe break end end
	end
	RPF.Select(selected, RPF.selected == nil)
	RPF.Fire("REBUILT")
end
RPF.Rebuild = Rebuild

-- Selects a recipe by spell id (the tracker does this).
function RPF.SelectSpell(spell)
	local r = M.bySpell[spell]
	if not r then return false end
	-- Recipes, not herbs or ore.
	RPF.Refine.SetView(nil)
	if not r.learned then RetailProfessionsDB.showUnlearned = true end
	RetailProfessionsCharDB.collapsed["h:" .. (r.header or "")] = nil
	RPF.filter.text = ""
	search:SetText("")
	Rebuild(true)
	RPF.Select(M.bySpell[spell], true)
	return true
end

-----------------------------------------
-- events

RPF.On("SHOW", function ()
	if RPF.hosting then
		-- DragonUI's window is already up (Host.lua calls RPF.HostOpened from its OnShow).
		if not hostOpen then RPF.HostOpened() end
	elseif not frame:IsShown() then
		RPF.selected = nil
		frame:Show()
	end
	M.ResetClientFilters()
	RPF.RequestBankSnapshot()
	RPF.Debounce("tradeskill", 0.05, function () RPF.Fire("TRADE_SKILL_UPDATE") end)
	-- Reopened under a window that stayed up: Create goes back to crafting.
	updateControls()
end)

RPF.On("CLOSE", function ()
	-- Another addon's page (Pages.lua) has no need of the trade skill: it stays.
	if not RPF.hosting and frame:IsShown() and not RPF.Pages.Current() then frame:Hide() end
	-- DragonUI's window outlives the trade skill: a craft waiting on the bank can't happen now.
	if RPF.hosting and hostOpen then
		if pendingCraft then
			pendingCraft = nil
			sayReopen()
		end
		updateControls()
	end
end)

-- On another addon's page its header; back from one, the profession's.
RPF.On("PAGE", function ()
	if RPF.Pages.Current() then updateHeader() else Rebuild(true) end
end)

RPF.On("TRADE_SKILL_UPDATE", function () Rebuild() end)
RPF.On("RECIPES", function (skill) if skill == M.skill then Rebuild() end end)
RPF.On("READY", function () if RPF.IsOpen() then Rebuild() end end)
RPF.On("BAGS", function ()
	if not RPF.IsOpen() then return end
	-- The bank's reagents arrived: craft. If the game wants a click for that, say so.
	local p = pendingCraft
	if p and RPF.selected and keyOf(RPF.selected) == p.key and bagsCover(RPF.selected, p.count) then
		pendingCraft = nil
		local r = RPF.selected
		craftNow(r, p.count, p.noConfirm)
		-- Milling and prospecting need no cast from here: the server answers either way.
		if not r.refine then
			RPF.After(0.6, function ()
				if not UnitCastingInfo("player") and RPF.selected == r and bagsCover(r, p.count) then
					RPF.Status("The reagents are in your bags. Press " .. (r.altVerb or CREATE or "Create") .. ".")
				end
			end)
		end
	elseif p and RPF.selected and keyOf(RPF.selected) ~= p.key then
		pendingCraft = nil
	end
	-- What's craftable decides the groups of the profit view and of the herbs and ore.
	if profitView() or RPF.Refine.Active() then Rebuild(true) else list:Refresh() end
	if RPF.selected then RPF.Fire("SELECTED", RPF.selected) end
	updateControls()
end)
RPF.On("COOLDOWN", function ()
	if RPF.IsOpen() and RPF.selected then
		M.Details(RPF.selected)
		RPF.Fire("SELECTED", RPF.selected)
		updateControls()
	end
end)
-- Profession equipment went on or came off (Gear.lua): the perk odds and the tools the recipe
-- needs follow.
RPF.On("GEAR", function ()
	if RPF.IsOpen() and RPF.selected then RPF.Fire("SELECTED", RPF.selected) end
end)
-- Equipment, a racial or a lure changed the skill bonus: the bar and the perk odds follow.
RPF.On("SKILLS", function ()
	if not (RPF.IsOpen() and M.skillName) or not M.ReadRank((select(2, GetTradeSkillLine()))) then return end
	updateHeader()
	if RPF.selected then RPF.Fire("SELECTED", RPF.selected) end
end)
-- The server's word on what the open profession's recipes need (Gear.lua) arrived.
RPF.On("GEAR_TOOLS", function (skill)
	if RPF.IsOpen() and RPF.selected and skill == M.skill then
		M.Details(RPF.selected)
		RPF.Fire("SELECTED", RPF.selected)
	end
end)
RPF.On("ITEM_INFO", function ()
	if RPF.IsOpen() then
		list:Refresh()
		if RPF.selected then RPF.Fire("SELECTED", RPF.selected) end
	end
end)
RPF.On("FAVORITES", function () Rebuild(true) end)
-- Recipes or herbs and ore: the view changed, or what herbs and ore give arrived.
RPF.On("VIEW", function () Rebuild(true) end)
RPF.On("YIELDS", function () if RPF.Refine.Active() then Rebuild(true) end end)
RPF.On("REFINE", function () if RPF.IsOpen() then updateControls() end end)
RPF.On("PRICES", function ()
	if not RPF.IsOpen() then return end
	-- A rebuild redraws the selected recipe too.
	if profitView() then
		Rebuild(true)
	elseif RPF.selected then
		RPF.Fire("SELECTED", RPF.selected)
	end
end)
RPF.On("TRACKED", function ()
	if RPF.IsOpen() then
		list:Refresh()
		updateControls()
	end
end)

-- Whether a profession is open in the window: ours, or DragonUI's with us in it (Host.lua).
function RPF.IsOpen()
	if RPF.hosting then return hostOpen and RPF.active and true or false end
	return frame:IsShown() and RPF.active and true or false
end

-- Whether the window is up at all: DragonUI's opens on its Overview without a profession, ours
-- on another addon's page (Pages.lua).
function RPF.WindowOpen()
	if RPF.hosting then return hostOpen end
	return frame:IsShown() and true or false
end

-- What a visit starts and ends with, in either window.
local function opened()
	releaseKeyboard()
	status:SetText("")
end

local function closed()
	-- The item picked to enchant and the search are for this visit only.
	RPF.enchantTarget = nil
	RPF.filter.text = ""
	search:SetText("")
	search:ClearFocus()
	RPF.Fire("HIDDEN")
end

-- DragonUI's window showing and hiding (Host.lua); it closes the trade skill itself.
function RPF.HostOpened()
	if hostOpen then return end
	hostOpen = true
	RPF.selected = nil
	opened()
	RPF.Fire("MOVED")
end

function RPF.HostClosed()
	if not hostOpen then return end
	hostOpen = false
	RPF.active = false
	closed()
end

frame:SetScript("OnShow", function ()
	PlaySound("igCharacterInfoOpen")
	opened()
	placeFrame()
	RPF.Fire("MOVED")
end)

frame:SetScript("OnHide", function ()
	PlaySound("igCharacterInfoClose")
	closed()
	-- Closing the window ends the trade skill session, unless we're handing over to the classic window.
	if RPF.active and not RPF.IsSwitchingToClassic() then
		RPF.active = false
		CloseTradeSkill()
	end
end)

-----------------------------------------
-- ReagentBankUI: it reads the selected recipe and the amount from this window

-- `window`: the frame whose showing tells ReagentBankUI we're the one in use; ours, or
-- DragonUI's TradeSkillFrame when we live in it (Host.lua calls this once it's built).
function RPF.RegisterBankProvider(window)
	local RB = _G.ReagentBankUI
	if not (RB and RB.RegisterRecipeProvider) then return end
	RB:RegisterRecipeProvider({
		name = "RetailProfessions",
		frame = window,
		GetRecipe = function ()
			local r = RPF.selected
			if not r then return nil, "Select a recipe first." end
			local reagents = {}
			for _, rg in ipairs(r.reagents) do
				if rg.id then
					table.insert(reagents, { itemEntry = rg.id, name = M.ReagentName(rg), requiredPerCraft = rg.n })
				end
			end
			return r.name, reagents
		end,
		GetRepeatCount = getQuantity,
		SetRepeatCount = setQuantityFromBank,
	})
end

RPF.On("LOGIN", function ()
	if not RPF.hosting then RPF.RegisterBankProvider(frame) end
end)

-- What the bank holds arrives a moment after the window opens, and nothing else says so: the
-- reagent counts, Create All and the shopping line are drawn again when it does.
RPF.On("LOGIN", function ()
	local RB = _G.ReagentBankUI
	if not (RB and RB.HandleBankSnapshotResponse and hooksecurefunc) then return end
	hooksecurefunc(RB, "HandleBankSnapshotResponse", function ()
		if RPF.IsOpen() then RPF.Debounce("bank-snapshot", 0.05, function () RPF.Fire("BAGS") end) end
	end)
end)

-- Tell ReagentBankUI the selection changed.
RPF.On("SELECTED", function ()
	local RB = _G.ReagentBankUI
	if RB and RB.NotifyRecipeProviderChanged and RPF.IsOpen() then pcall(RB.NotifyRecipeProviderChanged, RB) end
end)
