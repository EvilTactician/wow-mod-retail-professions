-- With DragonUI's professions window, this addon lives in it instead of opening its own: DragonUI
-- keeps the window (its art, rank bar, profession tabs and Overview), and our recipe list, the
-- recipe card, the craft controls and the proc log button go where its own would be. Training
-- and Profit are pages of it, Milling and Prospecting are side tabs, tracked recipes go in its objective
-- tracker. Training stands in for its Overview: that tab goes, and the window opens on Training
-- where it would open on the Overview (micro button, the professions book on K). Without DragonUI
-- (or with one that can't host) the window of our own is used as before. /prof classic shows
-- DragonUI's own crafting page instead.

local RPF = RetailProfessions
local M = RPF.Model

-- Training and Profit (Home.lua), a page each.
local PAGE_PREFIX = "retailprofessions-"
local function pageOf(view) return view and (PAGE_PREFIX .. view) or nil end
local function viewOf(page)
	local view = type(page) == "string" and page:sub(1, #PAGE_PREFIX) == PAGE_PREFIX and page:sub(#PAGE_PREFIX + 1)
	return view and RPF.Home.VIEWS[view] and view or nil
end

-- DragonUI's host (DragonUI.Professions.Host), when this DragonUI has one.
local function api()
	local D = _G.DragonUI
	local P = D and D.Professions
	local H = P and P.Host
	if H and (H.VERSION or 0) >= 1 and H.Enabled and H.Register then return H end
	return nil
end

-- DragonUI's window, when it has the professions (with us in it, or on /prof classic).
function RPF.HostAPI()
	return (RPF.hosting or RPF.hostClassic) and api() or nil
end

-- The window the player sees; secure buttons over it take its strata.
function RPF.Window()
	if RPF.hosting and TradeSkillFrame then return TradeSkillFrame end
	return RPF.frame
end

-----------------------------------------
-- what goes into DragonUI's window

local pieces, logHolder, bankFrame
local provider = {}

-- ReagentBankUI uses the recipe provider whose frame shows. Ours shows only while a profession
-- is open in DragonUI's window with us in it, so /prof classic and the Overview leave its own
-- handling of the stock window alone.
local function syncBank()
	if not bankFrame then return end
	if RPF.hosting and RPF.IsOpen() then bankFrame:Show() else bankFrame:Hide() end
end

-- Our secure buttons (Training's and Profit's lines) lie over the window by screen position: they follow it when
-- it moves among the other panels or is scaled.
local function followWindow()
	RPF.Debounce("host-secure", 0.05, RPF.SyncSpellButtons)
end

function provider.list(parent)
	pieces.list:SetParent(parent)
	return pieces.list
end

function provider.card(parent)
	pieces.card:SetParent(parent)
	RPF.HostLayout(true)
	-- DragonUI's window is built by now.
	if not bankFrame and TradeSkillFrame then
		bankFrame = CreateFrame("Frame", nil, TradeSkillFrame)
		bankFrame:Hide()
		RPF.RegisterBankProvider(bankFrame)
		-- Our secure buttons rise with the window when it's clicked.
		RPF.FollowRaises(TradeSkillFrame)
	end
	return pieces.card
end

function provider.controls(parent)
	pieces.controls:SetParent(parent)
	return pieces.controls
end

function provider.header(parent)
	logHolder = logHolder or CreateFrame("Frame")
	logHolder:SetParent(parent)
	logHolder:SetSize(23, 23)
	pieces.log:SetParent(logHolder)
	pieces.log:ClearAllPoints()
	pieces.log:SetPoint("LEFT", logHolder, "LEFT", 0, 0)
	return logHolder
end

-- Milling, Prospecting or someone's linked profession; Blizzard's title otherwise.
function provider.title()
	return M.skillName and RPF.TitleText() or nil
end

function provider.onShow()
	RPF.HostOpened()
	syncBank()
end

function provider.onHide()
	RPF.HostClosed()
	syncBank()
end

provider.onScale = followWindow

function provider.onPage(page)
	-- Opening, DragonUI turns to its first page (Training, from the micro button or K) before
	-- onShow: the window is open by then, or Training would read it as shut and go to the recipes.
	if TradeSkillFrame and TradeSkillFrame:IsShown() then RPF.HostOpened() end
	local view = viewOf(page)
	if RPF.Home.view ~= view then RPF.Home.SetActive(view or false) end
	-- Training's lines carry secure buttons: off another addon's page (Archaeology's), they go.
	followWindow()
end

-- The open profession's own tab: back to its recipes.
function provider.onCraftingTab()
	RPF.Home.SetActive(false)
	RPF.Refine.SetView(nil)
end

-- Training or Profit on, or (nil) back to the recipes (Home.lua).
function RPF.ShowHostPage(view)
	local H = api()
	if not H then return end
	local page = pageOf(view)
	if page then
		if H.Page() ~= page then H.SetPage(page) end
	elseif viewOf(H.Page()) then
		H.SetPage("crafting")
	end
end

-- How many professions you know, read when they change: the tabs ask while DragonUI rebuilds
-- them, and reading the skill lines then would set off another rebuild.
local knownCount = 0
local function countKnown()
	local n = #RPF.KnownProfessions()
	local changed = n ~= knownCount
	knownCount = n
	return changed
end

-- Training and Profit have tabs: you know a profession and aren't looking at someone's link.
local function viewsShown() return not M.linked and knownCount > 0 end

-- Training stands in for DragonUI's Overview while its tab shows (DragonUI 2.8+ asks).
function provider.overview()
	return viewsShown() and pageOf("training") or nil
end

local holders = {}
local function addViews(H)
	for _, key in ipairs(RPF.Home.ORDER) do
		local view, page = RPF.Home.VIEWS[key], pageOf(key)
		H.AddPage(page, {
			title = view.title,
			portrait = view.icon,
			build = function (parent)
				local holder = holders[key]
				if not holder then
					holder = CreateFrame("Frame", nil, parent)
					holders[key] = holder
					-- The lines carry secure buttons placed by screen position. The window moves
					-- when another panel opens beside it; while the page shows, they follow.
					local lastLeft, lastTop
					holder:SetScript("OnUpdate", function ()
						local left, top = TradeSkillFrame:GetLeft(), TradeSkillFrame:GetTop()
						if left ~= lastLeft or top ~= lastTop then
							lastLeft, lastTop = left, top
							followWindow()
						end
					end)
					local panel = RPF.Home.panels[key]
					panel:SetParent(holder)
					panel:ClearAllPoints()
					panel:SetPoint("TOPLEFT", holder, "TOPLEFT", 10, -40)
					panel:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -10, 10)
				end
				holder:SetParent(parent)
				return holder
			end,
		})
		H.AddTab({
			key = page, label = view.title, icon = view.icon, after = "overview", page = page,
			shown = function () return viewsShown() and RPF.Home.Shown(key) end,
		})
	end
end

-- The spell that opens the profession a herb or ore kind belongs to, when you know it.
local function openSpell(kind)
	local p = kind and RPF.Profession(kind.skill)
	return p and p.openName and GetSpellInfo(p.openName) and p.openName or nil
end

local function addRefineTabs(H)
	for _, code in ipairs({ "M", "P" }) do
		H.AddTab({
			key = "retailprofessions-refine-" .. code, after = "professions",
			label = function () local kind = RPF.Refine.Known(code) return kind and kind.name or "" end,
			icon = function () local kind = RPF.Refine.Known(code) return kind and kind.texture end,
			shown = function () return openSpell(RPF.Refine.Known(code)) ~= nil end,
			-- Another profession is open: cast this one's, on its herbs or ore.
			spell = function ()
				local kind = RPF.Refine.Known(code)
				if not kind or RPF.Refine.IsOpen(kind) then return nil end
				return openSpell(kind)
			end,
			onDown = function () RPF.Refine.Pend(code) end,
			onClick = function ()
				-- No cast was bound: the profession is open, or combat kept the tab from binding one.
				local kind = RPF.Refine.Known(code)
				if not (kind and RPF.Refine.IsOpen(kind)) then
					if RPF.InCombat() then
						UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT or "You can't do that in combat.", 1, 0.1, 0.1, 1)
					end
					return
				end
				RPF.Home.SetActive(false)
				RPF.Refine.SetView(code)
				-- From the Overview too.
				if H.Page() ~= "crafting" then H.SetPage("crafting") end
			end,
			selected = function (page)
				return page == "crafting" and RPF.Refine.Active() ~= nil and RPF.Refine.Active() == RPF.Refine.Kind(code)
			end,
		})
	end
end

-----------------------------------------
-- tracked recipes in DragonUI's objective tracker

local catcherIds = {}

local function trackedEntry(block)
	return RetailProfessionsCharDB and RetailProfessionsCharDB.tracked[block.ref]
end

local function trackedMenu(block)
	local spell = block.ref
	local entry = trackedEntry(block)
	if not entry then return {} end
	local items = {}
	for _, n in ipairs({ 1, 2, 3, 5, 10, 20 }) do
		local mark = (entry.count or 1) == n and "|cffffd200>|r " or "    "
		table.insert(items, { text = mark .. "Make " .. n, func = function ()
			entry.count = n
			RPF.Fire("TRACKED")
		end })
	end
	table.insert(items, { text = OBJECTIVES_STOP_TRACKING or "Stop tracking", func = function ()
		RetailProfessionsCharDB.tracked[spell] = nil
		RPF.Fire("TRACKED")
	end })
	return items
end

-- With its profession open a click shows the recipe; otherwise the catcher below casts the
-- profession first and the recipe is picked once it has opened (Home's pending pick).
local function onBlockClick(block, button)
	local spell = block.ref
	if IsModifiedClick("CHATLINK") and GetSpellLink then
		ChatEdit_InsertLink(GetSpellLink(spell))
	elseif RPF.IsOpen() and RPF.SelectSpell(spell) then
		RPF.Home.SetActive(false)
		-- From the Overview too.
		local H = api()
		if H and H.Page() ~= "crafting" then H.SetPage("crafting") end
	elseif RPF.InCombat() then
		UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT or "You can't do that in combat.", 1, 0.1, 0.1, 1)
	end
end

local function onBlockEnter(block)
	local H = api()
	local entry = trackedEntry(block)
	local p = entry and RPF.Profession(entry.skill)
	local spell = p and p.openName
	if not (H and spell) or RPF.InCombat() or (RPF.IsOpen() and M.skill == entry.skill and not M.linked) then return end
	local id = catcherIds[block]
	if not id then
		id = H.NewCatcherId()
		catcherIds[block] = id
	end
	H.Catchers.Bind(id, block, spell, {
		onEnter = function () H.HighlightBlock(block, true) end,
		onLeave = function () H.HighlightBlock(block, false) end,
		onDown = function (_, button)
			if button == "LeftButton" and not IsModifiedClick("CHATLINK") then
				RPF.Home.Pend({ skill = entry.skill, spell = block.ref })
			end
		end,
		onUp = function (_, button)
			if button == "RightButton" or IsModifiedClick("CHATLINK") then H.ClickBlock(block, button) end
		end,
	}, { ["shift-type1"] = "none" })
	H.Catchers.ArmFor(block)
end

local function collect(blocks)
	if not (RPF.hosting and RetailProfessionsCharDB) then return end
	for _, t in ipairs(RPF.TrackedList()) do
		local entry = t.entry
		local want = entry.count or 1
		local lines = {}
		for _, rg in ipairs(entry.reagents or {}) do
			local need = rg.n * want
			local have, bags, bank = RPF.HaveCount(rg.id)
			local info = rg.id and RPF.Item(rg.id)
			local name = (info and info.name) or rg.name or ("Item #" .. tostring(rg.id))
			table.insert(lines, { text = RPF.TrackedHaveText(have, bags, bank, need) .. " " .. name })
		end
		table.insert(blocks, { kind = "recipe", title = entry.name .. (want > 1 and (" x" .. want) or ""),
			icon = entry.icon, lines = lines, ref = t.spell, menu = trackedMenu,
			onClick = onBlockClick, onEnter = onBlockEnter })
	end
end

-- Whether tracked recipes go in DragonUI's tracker (its quest tracker module is on).
function RPF.HostTracksRecipes()
	local H = RPF.hosting and api()
	return H and H.TrackerEnabled() and RPF.hostTracker or false
end

function RPF.RefreshHostTracker()
	local H = api()
	if H then H.RefreshTracker() end
end

-----------------------------------------
-- starting and stopping

-- At login (Core.lua) and on /prof retail: true when DragonUI's window has the professions,
-- with us in it or (on /prof classic) without.
function RPF.StartHosting()
	local H = api()
	if not (H and H.Enabled()) then return false end
	if RetailProfessionsDB.classic then
		RPF.hostClassic = true
		return true
	end
	RPF.hostClassic = nil
	RPF.hosting = true
	pieces = pieces or RPF.HostPieces()
	addViews(H)
	addRefineTabs(H)
	if RPF.hostTracker == nil then RPF.hostTracker = H.AddTrackerCollector(collect) and true or false end
	H.Register(provider)
	countKnown()
	-- Switched back while the window is open: fill it now, a profession's recipes if one is open
	-- (the window may show DragonUI's Overview with none).
	if TradeSkillFrame and TradeSkillFrame:IsShown() then
		RPF.HostOpened()
		local line = GetTradeSkillLine()
		if line and line ~= "UNKNOWN" then
			RPF.active = true
			RPF.Fire("SHOW")
		end
	end
	syncBank()
	RPF.Fire("TRACKED")
	return true
end

-- /prof classic: DragonUI's own crafting page.
function RPF.StopHosting()
	local H = api()
	if not (RPF.hosting and H) then return end
	RPF.HostClosed()
	RPF.hosting = false
	RPF.hostClassic = true
	syncBank()
	H.Unregister(provider)
	RPF.HostLayout(false)
	RPF.Fire("TRACKED")
	H.RefreshTracker()
end

-- The tabs and the title follow what the window shows and the profession in it, read after our
-- scan (DragonUI's own refresh comes before it), and the professions you know.
local function refreshHost()
	local H = RPF.hosting and api()
	if not H then return end
	H.RefreshTabs()
	if H.RefreshHeader then H.RefreshHeader() end
end

local shownSkill, shownLinked
RPF.On("VIEW", refreshHost)
RPF.On("READY", refreshHost)
RPF.On("REBUILT", function ()
	if M.skill == shownSkill and M.linked == shownLinked then return end
	shownSkill, shownLinked = M.skill, M.linked
	refreshHost()
end)
RPF.On("SHOW", syncBank)
RPF.On("HIDDEN", function ()
	shownSkill, shownLinked = nil, nil
	syncBank()
end)
RPF.On("SKILLS", function ()
	if RPF.hosting and countKnown() then refreshHost() end
end)
-- The Equipment tab comes and goes with the realm's profession gear.
local gearShown
RPF.On("GEAR", function ()
	local shown = RPF.Home.Shown("equipment")
	if shown == gearShown then return end
	gearShown = shown
	refreshHost()
end)
