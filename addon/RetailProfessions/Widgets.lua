-- RetailProfessions widgets (from RetailAH): buttons, inputs, panes and item buttons, dressed in DragonUI's retail art
-- when DragonUI is loaded and stock Blizzard frames otherwise; the profession window's pieces
-- (skill bar, recipe card, slots) in the art of DragonUI's own professions window when it has one.

local RPF = RetailProfessions

local nameCounter = 0
local function uniqueName(base)
	nameCounter = nameCounter + 1
	return "RetailProfessions" .. base .. nameCounter
end
RPF.UniqueName = uniqueName

-----------------------------------------
-- DragonUI, if it's there and new enough to carry the helpers we borrow

-- DragonUI's nine-slice helper: DragonUI_NineSlice since DragonUI's 2026 rewrite, NineSliceUtils
-- before it.
local NineSliceUtils = _G.DragonUI_NineSlice or _G.NineSliceUtils

function RPF.Dragon()
	local D = _G.DragonUI
	if D and D._dir and D.atlasinfo and D.SafeSetAtlas and D.SkinRedButton and NineSliceUtils
			and D.CharacterPanel and D.CharacterPanel.ReskinTab then
		return D, D.CharacterPanel
	end
end

-- The art of DragonUI's own professions window (DragonUI.Professions: backdrop, skill bars,
-- list bars, recipe card and drawings) and the Forever metal frame it sits in, when this
-- DragonUI has them. The profession window uses it; everything else keeps DragonUI's plain look.
local CHROME_PIECES = { "ui-frame-metal-cornertopright", "ui-frame-metal-cornerbottomleft", "ui-frame-metal-cornerbottomright",
	"_ui-frame-metal-edgetop", "_ui-frame-metal-edgebottom", "!ui-frame-metal-edgeleft", "!ui-frame-metal-edgeright" }

function RPF.ProfArt()
	local D = RPF.Dragon()
	local P = D and D.Professions
	local Art, UI, atlas = P and P.Art, D and D.ForeverUI, D and D.ForeverAtlas
	if not (P and P.Atlas and P.Atlas["bg-crafting"] and P.Atlas["card-base"] and Art and Art.Set and Art.SetInset
			and Art.SetClipped and Art.ThreeSlice and Art.NineSlice and Art.PlaceNineSlice and Art.RankText
			and Art.CardDrawing and P.Fill and P.Fill.Create and P.Fill.Update and P.Professions
			and P.Professions.EntryForLine and UI and UI.ApplyNineSlice and atlas) then
		return nil
	end
	for _, name in ipairs(CHROME_PIECES) do
		if not atlas[name] then return nil end
	end
	return P, D
end

-- The part of an atlas piece from x0 to x1 and y0 to y1, in the piece's own units.
local function cropArt(P, tex, name, x0, x1, y0, y1)
	local info = P.Atlas[name]
	-- Sets the sheet and the shade DragonUI darkens it back with.
	P.Art.Set(tex, name)
	local l, r, t, b = info[4], info[5], info[6], info[7]
	tex:SetTexCoord(l + (r - l) * x0 / info[2], l + (r - l) * x1 / info[2],
		t + (b - t) * y0 / info[3], t + (b - t) * y1 / info[3])
end

-- Which of DragonUI's professions a skill line (its localized name) is: "Alchemy", "FirstAid"...
function RPF.ProfArtKey(skillName)
	local P = RPF.ProfArt()
	local entry = P and skillName and P.Professions.EntryForLine(skillName)
	return entry and entry.key or nil
end

local function solid(host, layer, r, g, b, a, sublevel)
	local tex = host:CreateTexture(nil, layer, nil, sublevel)
	tex:SetTexture(r, g, b, a)
	return tex
end

local function tiled(host, layer, sublevel, file)
	local tex = host:CreateTexture(nil, layer, nil, sublevel)
	tex:SetTexture(file, "REPEAT", "REPEAT")
	tex:SetHorizTile(true)
	tex:SetVertTile(true)
	return tex
end

-----------------------------------------
-- window chrome and panes

-- Without DragonUI every window is a stock Blizzard dialog frame: the dialog-box border and
-- background with the gold header plate for its title.
local DIALOG_BACKDROP = {
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true, tileSize = 32, edgeSize = 32,
	insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

-- DragonUI's professions window draws its backdrop at 665 x 570 under a 673 wide frame. The
-- list column keeps its own width; past it (under the recipe card) the backdrop stretches to
-- whatever width the window has.
local BACKDROP_SPLIT = 330

-- The crafting page of DragonUI's professions window: its backdrop under the metal frame with
-- the professions portrait corner, the title and close button where it puts them.
local function dressProfArt(frame, opts, D, CP, P, close)
	local info = P.Atlas["bg-crafting"]
	local height = math.min(info[3], frame:GetHeight() - 23)
	local left = frame:CreateTexture(nil, "BACKGROUND")
	cropArt(P, left, "bg-crafting", 0, BACKDROP_SPLIT, 0, height)
	left:SetSize(BACKDROP_SPLIT, height)
	left:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -21)
	local right = frame:CreateTexture(nil, "BACKGROUND")
	cropArt(P, right, "bg-crafting", BACKDROP_SPLIT, info[2], 0, height)
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
	right:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -4, -21 - height)

	-- On its own frame above the content, so no child panel draws over the metal.
	local chrome = CreateFrame("Frame", nil, frame)
	chrome:SetAllPoints(frame)
	chrome:SetFrameLevel(frame:GetFrameLevel() + 30)
	chrome:EnableMouse(false)
	local atlas = D.ForeverAtlas
	-- DragonUI's own window registers it under this name too.
	atlas["dragonui-professions-portraitcorner"] = atlas["dragonui-professions-portraitcorner"] or P.Atlas["portrait-corner"]
	D.ForeverUI.ApplyNineSlice(chrome, {
		corners = {
			TopLeft = { "dragonui-professions-portraitcorner", -13, 16 },
			TopRight = { "ui-frame-metal-cornertopright", 2, 16 },
			BottomLeft = { "ui-frame-metal-cornerbottomleft", -13, -8 },
			BottomRight = { "ui-frame-metal-cornerbottomright", 2, -8 },
		},
		edges = { Top = "_ui-frame-metal-edgetop", Bottom = "_ui-frame-metal-edgebottom",
			Left = "!ui-frame-metal-edgeleft", Right = "!ui-frame-metal-edgeright" },
	}, "BORDER")
	frame.chrome = chrome
	-- Under the corner's ring, which hides the edge SetPortraitToTexture leaves.
	frame.portrait = frame:CreateTexture(nil, "BORDER")
	frame.portrait:SetSize(58, 58)
	frame.portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", -4, 7)

	frame.title = chrome:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.title:SetHeight(12)
	frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 58, -5)
	frame.title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, -5)
	frame.title:SetJustifyH("CENTER")

	local exit, pressed, off, lit = atlas["redbutton-exit"], atlas["redbutton-exit-pressed"],
		atlas["redbutton-exit-disabled"], atlas["redbutton-highlight"]
	if exit and pressed and off and lit then
		local function put(setter, getter, piece, mode)
			close[setter](close, piece[1], mode)
			local tex = close[getter](close)
			if tex then tex:SetTexCoord(piece[4], piece[5], piece[6], piece[7]) end
		end
		put("SetNormalTexture", "GetNormalTexture", exit)
		put("SetPushedTexture", "GetPushedTexture", pressed)
		put("SetDisabledTexture", "GetDisabledTexture", off)
		put("SetHighlightTexture", "GetHighlightTexture", lit, "ADD")
		close:SetSize(24, 24)
		close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, 1)
	else
		close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
		if CP.ModernizeCloseButton then CP.ModernizeCloseButton(close, chrome, 1, 0) end
	end
	close:SetFrameLevel(chrome:GetFrameLevel() + 5)
	frame.profArt = P
end

-- Dresses a window and gives it a title (frame.title), a close button (frame.closeButton) and a
-- title bar to drag it by. DragonUI's metal frame on rock when DragonUI is loaded, otherwise the
-- stock dialog frame. opts = { portrait = round portrait top-left (frame.portrait, DragonUI only;
-- set it with RPF.SetPortrait), profArt = the art of DragonUI's professions window when it has
-- it (frame.profArt is set then; the portrait comes with it), closeName = global name for the
-- close button, onMoved = fn }. Returns true with DragonUI, and the y offset content starts at.
function RPF.DressWindow(frame, opts)
	opts = opts or {}
	local D, CP = RPF.Dragon()
	local close = CreateFrame("Button", opts.closeName, frame, "UIPanelCloseButton")
	frame.closeButton = close
	local P = opts.profArt and RPF.ProfArt()

	if P then
		dressProfArt(frame, opts, D, CP, P, close)
	elseif D then
		local rock = tiled(frame, "BACKGROUND", -8, D._dir .. "UI\\ui-background-rock")
		rock:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -21)
		rock:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)

		local streaks = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
		if D:SafeSetAtlas(streaks, "_UI-Frame-TopTileStreaks") then
			streaks:SetHorizTile(true)
			streaks:SetHeight(43)
			streaks:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -21)
			streaks:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -21)
		else
			streaks:Hide()
		end

		-- On its own frame above the content, so no child panel draws over the metal.
		local chrome = CreateFrame("Frame", nil, frame)
		chrome:SetAllPoints(frame)
		chrome:SetFrameLevel(frame:GetFrameLevel() + 30)
		chrome:EnableMouse(false)
		local layout = opts.portrait and NineSliceUtils.GetLayout("PortraitFrameTemplate")
			or NineSliceUtils.GetLayout("NoPortraitFrameTemplate") or NineSliceUtils.GetLayout("PortraitFrameTemplate")
		NineSliceUtils.ApplyLayout(chrome, layout)
		frame.chrome = chrome
		if opts.portrait then
			-- Where DragonUI's spellbook puts its portrait, under the frame's ring.
			frame.portrait = chrome:CreateTexture(nil, "ARTWORK")
			frame.portrait:SetSize(58, 58)
			frame.portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", -2, 6)
		end

		frame.title = chrome:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		frame.title:SetPoint("TOP", frame, "TOP", 0, -5)
		close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
		if CP.ModernizeCloseButton then
			CP.ModernizeCloseButton(close, chrome, 1, 0)
			close:SetFrameLevel(chrome:GetFrameLevel() + 5)
		end
	else
		frame:SetBackdrop(DIALOG_BACKDROP)
		frame.chrome = frame
		local header = frame:CreateTexture(nil, "ARTWORK")
		header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
		header:SetSize(320, 64)
		header:SetPoint("TOP", frame, "TOP", 0, 12)
		frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		frame.title:SetPoint("TOP", header, "TOP", 0, -14)
		close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
	end

	local dragBar = CreateFrame("Frame", nil, frame)
	dragBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, D and 0 or 12)
	dragBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, 0)
	dragBar:SetHeight(D and 24 or 36)
	dragBar:EnableMouse(true)
	dragBar:RegisterForDrag("LeftButton")
	dragBar:SetScript("OnDragStart", function ()
		RPF.MovedAt = math.huge -- until let go (RPF.Dragging)
		frame:StartMoving()
	end)
	dragBar:SetScript("OnDragStop", function ()
		RPF.MovedAt = GetTime()
		frame:StopMovingOrSizing()
		if opts.onMoved then opts.onMoved() end
	end)

	return D and true or false, D and -28 or -32
end

-- A round picture of an icon, as portraits and retail's recipe icons are drawn.
function RPF.SetPortrait(texture, path)
	if not texture then return end
	if path and SetPortraitToTexture then
		texture:SetTexCoord(0, 1, 0, 1)
		SetPortraitToTexture(texture, path)
	else
		texture:SetTexture(path)
	end
end

-- The stock options panels' box (OptionsBoxTemplate), filled so a list reads on the dialog.
local OPTIONS_BOX = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 5, right = 5, top = 5, bottom = 5 },
}

-- A recessed pane: retail's InsetFrameTemplate under DragonUI, the options box otherwise.
function RPF.CreateInset(parent)
	local pane = CreateFrame("Frame", nil, parent)
	local D = RPF.Dragon()
	if D then
		local bg = tiled(pane, "BACKGROUND", -5, D._dir .. "UI\\ui-background-marble")
		bg:SetAllPoints(pane)
		NineSliceUtils.ApplyLayout(pane, NineSliceUtils.GetLayout("InsetFrameTemplate"))
	else
		pane:SetBackdrop(OPTIONS_BOX)
		pane:SetBackdropColor(0.1, 0.1, 0.1, 1)
		pane:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
	end
	return pane
end

-- The character window's skill bar (SkillStatusBarTemplate) on a StatusBar `height` tall: its
-- fill and faint backing in the trade skill window's rank bar colours, and its border, cut in
-- three so the ends keep their shape however wide the bar is.
local SKILL_BORDER = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-BarBorder"

function RPF.StockSkillBar(bar, height)
	bar:SetStatusBarTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
	bar:SetStatusBarColor(0, 0, 1, 0.5)
	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(bar)
	bg:SetTexture(1, 1, 1, 0.2)
	bg:SetVertexColor(0, 0, 0.75, 0.5)
	-- The template's border is 281 x 32 round a 271 x 15 bar, 5 out at each end.
	local k = height / 15
	local border = CreateFrame("Frame", nil, bar)
	border:SetPoint("LEFT", bar, "LEFT", -5 * k, 0)
	border:SetPoint("RIGHT", bar, "RIGHT", 5 * k, 0)
	border:SetHeight(32 * k)
	local capW = 17.5 * k
	local function piece(l, r)
		local t = border:CreateTexture(nil, "ARTWORK")
		t:SetTexture(SKILL_BORDER)
		t:SetTexCoord(l, r, 0, 1)
		return t
	end
	local left = piece(0, 0.0625)
	left:SetPoint("TOPLEFT", border, "TOPLEFT")
	left:SetPoint("BOTTOMLEFT", border, "BOTTOMLEFT")
	left:SetWidth(capW)
	local right = piece(0.9375, 1)
	right:SetPoint("TOPRIGHT", border, "TOPRIGHT")
	right:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT")
	right:SetWidth(capW)
	local middle = piece(0.0625, 0.9375)
	middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
	middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
	bar.border = border
	return bar
end

-- A skill bar as the character window's Skills tab draws one, its rank written inside (bar.Caption):
-- DragonUI's own row bar (99 x 13, green, gold once capped; bar:SetShade; bar.fixedWidth) where
-- DragonUI has it, else the stock skill bar 15 tall, as wide as it's anchored.
local SHADE_CAPPED, SHADE_TRAINING = { 1.0, 0.94, 0.1 }, { 0.2, 0.85, 0.2 }

function RPF.SkillTabBar(parent)
	local _, CP = RPF.Dragon()
	local bar
	if CP and CP.BuildRowBar then
		bar = CP.BuildRowBar(parent, parent, "RIGHT", 0, {
			width = 99, height = 13,
			fill = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar",
			frame = "Interface\\PaperDollInfoFrame\\UI-Character-ReputationBar",
			capWidth = 60, frameHeight = 15,
		})
		bar:ClearAllPoints()
		bar.fixedWidth = true
		function bar:SetShade(capped)
			local c = capped and SHADE_CAPPED or SHADE_TRAINING
			self:SetStatusBarColor(c[1], c[2], c[3])
		end
	else
		bar = RPF.StockSkillBar(CreateFrame("StatusBar", nil, parent), 15)
		bar:SetHeight(15)
		bar.Caption = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		bar.Caption:SetPoint("CENTER", bar, "CENTER", 0, 1)
		function bar:SetShade() end
	end
	return bar
end

-- A category heading as the recipe list draws one (RecipeList.lua), for other addons' pages
-- (Pages.lua): DragonUI's header bar with its professions art, retail's gold-edged band with
-- DragonUI, the plain gold heading otherwise. h.label on the left, h.note on the right.
function RPF.CreateListHeader(parent, text)
	local h = CreateFrame("Frame", nil, parent)
	h:SetHeight(25)
	local P = RPF.ProfArt()
	local D = RPF.Dragon()
	local font = GameFontNormal
	if P then
		P.Art.ThreeSlice(h, "BACKGROUND", "header", 8)
		font = D.ForeverUI.Fonts and D.ForeverUI.Fonts.HighlightMedium or font
	elseif D then
		solid(h, "BACKGROUND", 0.2, 0.14, 0.04, 0.9):SetAllPoints(h)
		for _, edge in ipairs({ "TOP", "BOTTOM" }) do
			local rule = solid(h, "BORDER", 1, 0.82, 0, 0.55)
			rule:SetHeight(1)
			rule:SetPoint(edge .. "LEFT", h, edge .. "LEFT")
			rule:SetPoint(edge .. "RIGHT", h, edge .. "RIGHT")
		end
	end
	h.label = h:CreateFontString(nil, "ARTWORK")
	h.label:SetFontObject(font)
	h.label:SetPoint("LEFT", h, "LEFT", P and 8 or 6, 0)
	h.label:SetTextColor(1, 0.82, 0)
	h.label:SetText(text or "")
	h.note = h:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	h.note:SetPoint("RIGHT", h, "RIGHT", -8, 0)
	h.note:SetJustifyH("RIGHT")
	return h
end

-- DragonUI's profession skill bar (needs RPF.ProfArt): its frame round the profession's own
-- fill, which plays when the skill moves. bar:SetRank(name, rank, maxRank, key, bonus).
local RANK_BAR_W, RANK_FILL_W = 453, 441

function RPF.CreateRankBar(parent)
	local P = RPF.ProfArt()
	local Art = P.Art
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetSize(RANK_BAR_W, 18)
	local bg = bar:CreateTexture(nil, "BACKGROUND")
	Art.Set(bg, "rankbar-bg", true)
	bg:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
	bar.fx = P.Fill.Create(bar, RANK_BAR_W, 0, 18)
	bar.fx:SetPoint("TOPLEFT", bar, "TOPLEFT", 5, -3)
	-- The border and the rank go on a frame over the fill's.
	local top = CreateFrame("Frame", nil, bar)
	top:SetAllPoints(bar)
	top:SetFrameLevel(bar.fx:GetFrameLevel() + 1)
	local border = top:CreateTexture(nil, "ARTWORK")
	Art.Set(border, "rankbar-border", true)
	border:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
	bar.rank = Art.RankText(top)
	bar.rank:SetCenter(bar, "TOPLEFT", 5 + RANK_FILL_W / 2, -12)

	function bar:SetRank(name, rank, maxRank, key, bonus)
		rank, maxRank = rank or 0, maxRank or 0
		local ratio = maxRank > 0 and math.min(rank / maxRank, 1) or 0
		P.Fill.Update(self.fx, key, ratio, maxRank > 0 and rank >= maxRank)
		self.rank:Set(string.format("%s %d%s", name or "", rank, RPF.BonusText(bonus)), maxRank)
	end
	return bar
end

-- DragonUI's recipe card (needs RPF.ProfArt) on a pane: the parchment, the profession's drawing
-- in its bottom right corner and the inside frame round it all. pane:SetCardArt(key, icon) picks
-- the drawing; a profession without one gets its icon, toned like the drawings, in its place.
local CARD_INSET = 4

function RPF.DressCard(pane)
	local P = RPF.ProfArt()
	local Art = P.Art
	local base = pane:CreateTexture(nil, "BACKGROUND")
	Art.SetInset(base, "card-base", CARD_INSET)
	base:ClearAllPoints()
	base:SetPoint("TOPLEFT", pane, "TOPLEFT", CARD_INSET, -CARD_INSET)
	base:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -CARD_INSET, CARD_INSET)
	local drawing = pane:CreateTexture(nil, "BORDER")
	drawing:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -CARD_INSET, CARD_INSET)
	drawing:Hide()
	local icon = pane:CreateTexture(nil, "BORDER")
	icon:SetSize(96, 96)
	icon:SetPoint("CENTER", pane, "BOTTOM", 0, 136)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetDesaturated(true)
	icon:SetVertexColor(0.85, 0.7, 0.5)
	icon:SetAlpha(0.35)
	icon:Hide()
	local frame = Art.NineSlice(pane, "ARTWORK", "insideframe", 53)
	Art.PlaceNineSlice(frame, pane, 53)
	local hidden = false

	-- DragonUI's own window draws the card when the pane goes into it (Host.lua).
	function pane:SetCardArtShown(on)
		hidden = not on
		for _, t in pairs(frame) do if on then t:Show() else t:Hide() end end
		if on then base:Show() else base:Hide() end
		if not on then
			drawing:Hide()
			icon:Hide()
		end
	end

	function pane:SetCardArt(key, iconPath)
		if hidden then return end
		local name = Art.CardDrawing(key)
		if name then
			-- Cut where the parchment ends, as DragonUI does.
			local info = P.Atlas[name]
			Art.SetClipped(drawing, name, info[2] - CARD_INSET, info[3] - CARD_INSET)
			drawing:Show()
		else
			drawing:Hide()
		end
		if not name and iconPath then
			icon:SetTexture(iconPath)
			icon:Show()
		else
			icon:Hide()
		end
	end
	return pane
end

-- A FauxScrollFrame's bar: DragonUI's thin one, or the stock one.
function RPF.SkinScrollBar(scroll, scrollName)
	local bar = _G[scrollName .. "ScrollBar"]
	if not bar then return end
	local _, CP = RPF.Dragon()
	if CP and CP.ReskinScrollBar then
		pcall(CP.ReskinScrollBar, scroll, scroll, -7, 18, -7, true)
	end
	-- Otherwise the stock scroll bar stays as it is.
end

-----------------------------------------
-- controls

function RPF.SetEnabled(control, enabled)
	if enabled then control:Enable() else control:Disable() end
end

function RPF.CreateButton(parent, text, width, height)
	local btn = CreateFrame("Button", uniqueName("Button"), parent, "UIPanelButtonTemplate")
	btn:SetSize(width or 100, height or 22)
	btn:SetText(text or "")
	local D = RPF.Dragon()
	if D then D.SkinRedButton(btn) end
	return btn
end

-- A button that opens a menu or switches a view, like the Filter button of DragonUI's
-- professions window: the dark rounded button with its own hover and pressed art. Without that
-- art, a button like any other. LockHighlight shows it switched on.
function RPF.CreateMenuButton(parent, text, width)
	local D = RPF.ProfArt() and RPF.Dragon()
	if D then
		local btn = CreateFrame("Button", uniqueName("MenuButton"), parent)
		-- The art is drawn 4 past the button on every side; here the button takes it all.
		btn:SetSize(width + 8, 26)
		local states = {}
		for _, s in ipairs({ { "SetNormalTexture", "" }, { "SetPushedTexture", "-pressed" }, { "SetHighlightTexture", "-hover" } }) do
			local tex = btn:CreateTexture(nil, "BACKGROUND")
			if not D:SafeSetAtlas(tex, "common-dropdown-b-button" .. s[2]) then
				states = nil
				break
			end
			btn[s[1]](btn, tex)
			tex:ClearAllPoints()
			tex:SetAllPoints(btn)
			table.insert(states, tex)
		end
		if states then
			local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			label:SetPoint("CENTER", btn, "CENTER", 0, 0)
			btn:SetFontString(label)
			btn:SetPushedTextOffset(1, -1)
			btn:SetText(text or "")
			-- The art has the arrow.
			btn.hasArrow = true
			return btn
		end
		btn:Hide()
	end
	return RPF.CreateButton(parent, text, width, 22)
end

-- A small square button for an icon (needs RPF.ProfArt), as DragonUI's professions window
-- draws its chat link button. btn.icon is the icon, centred.
function RPF.CreateSquareButton(parent, size)
	local P = RPF.ProfArt()
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(size, size)
	for _, s in ipairs({ { "SetNormalTexture", "link-normal" }, { "SetPushedTexture", "link-pressed" },
			{ "SetHighlightTexture", "link-hover" } }) do
		local tex = btn:CreateTexture(nil, "BACKGROUND")
		P.Art.Set(tex, s[2])
		btn[s[1]](btn, tex)
		tex:ClearAllPoints()
		tex:SetAllPoints(btn)
	end
	-- The highlight layer draws over everything, the icon too: added on top, it only lights the
	-- square instead of hiding the icon.
	local lit = btn:GetHighlightTexture()
	if lit then
		lit:SetBlendMode("ADD")
		lit:SetAlpha(0.4)
	end
	-- The button draws its state textures on ARTWORK; the icon goes over them.
	btn.icon = btn:CreateTexture(nil, "OVERLAY")
	btn.icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
	return btn
end

-- An edit box in DragonUI's professions style (its dark field with the Forever edge) when the
-- art is there; returns whether it was.
function RPF.SkinProfArtEditBox(eb)
	local D = RPF.ProfArt() and RPF.Dragon()
	if not (D and D.ForeverUI.SkinEditBox) then return false end
	local insets = { eb:GetTextInsets() }
	if not pcall(D.ForeverUI.SkinEditBox, eb, { height = 20 }) then return false end
	-- It sets its own insets; ours make room for what sits in the box.
	if insets[1] then eb:SetTextInsets(unpack(insets)) end
	return true
end

local function skinInput(eb)
	local D = RPF.Dragon()
	if not D then return end
	local regions = { eb:GetRegions() }
	for i = 1, #regions do
		local r = regions[i]
		if r:GetObjectType() == "Texture" then
			local path = r:GetTexture()
			if type(path) == "string" and path:lower():find("common%-input%-border") then
				r:SetTexture(0, 0, 0, 0.55)
			end
		end
	end
end

function RPF.CreateEditBox(parent, width, numeric)
	local eb = CreateFrame("EditBox", uniqueName("EditBox"), parent, "InputBoxTemplate")
	eb:SetSize(width or 120, 20)
	-- InputBoxTemplate's boxes take the keyboard as soon as they exist; ours only when clicked.
	eb:SetAutoFocus(false)
	eb:ClearFocus()
	if numeric then eb:SetNumeric(true) end
	eb:SetScript("OnEscapePressed", function (self) self:ClearFocus() end)
	eb:SetScript("OnEnterPressed", function (self) self:ClearFocus() end)
	skinInput(eb)
	return eb
end

function RPF.CreateCheck(parent, label)
	local name = uniqueName("Check")
	local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	local text = _G[name .. "Text"]
	text:SetText(label or "")
	text:SetFontObject(GameFontHighlightSmall)
	cb.label = text
	local _, CP = RPF.Dragon()
	if CP and CP.SkinCheckbox then CP.SkinCheckbox(cb) end
	return cb
end

-- Shows the item tooltip that was just filled in. Holding Shift puts what you have equipped in
-- that slot beside it, as elsewhere in the game.
local tipOwner

local function hideCompare()
	ShoppingTooltip1:Hide()
	ShoppingTooltip2:Hide()
	if ShoppingTooltip3 then ShoppingTooltip3:Hide() end
end

-- The 3.3.5 client crashes (#132 at 0x00620727) when it compares against worn gear whose item
-- record isn't in its cache yet, which is common right after the cache is wiped. Anything
-- missing is asked for; ITEM_INFO compares once it has arrived.
local function compareReady()
	local _, link = GameTooltip:GetItem()
	local entry = link and tonumber(link:match("item:(%d+)"))
	local ready = not entry or RPF.Item(entry) ~= nil
	for slot = 1, 19 do
		local worn = GetInventoryItemID("player", slot)
		if worn and not RPF.Item(worn) then ready = false end
	end
	return ready
end

local function compare()
	if compareReady() then GameTooltip_ShowCompareItem() end
end

function RPF.ShowItemTooltip(owner)
	tipOwner = owner
	GameTooltip:Show()
	if IsModifiedClick("COMPAREITEMS") then compare() end
end

function RPF.HideItemTooltip()
	tipOwner = nil
	GameTooltip:Hide()
	hideCompare()
end

-- Pressing or letting go of Shift while hovering shows or hides the comparison right away.
local modifierFrame = CreateFrame("Frame")
modifierFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
modifierFrame:SetScript("OnEvent", function ()
	if not tipOwner or not GameTooltip:IsShown() or not GameTooltip:IsOwned(tipOwner) then return end
	if IsModifiedClick("COMPAREITEMS") then compare() else hideCompare() end
end)
RPF.On("ITEM_INFO", function ()
	if not tipOwner or not GameTooltip:IsShown() or not GameTooltip:IsOwned(tipOwner) then return end
	if IsModifiedClick("COMPAREITEMS") and not ShoppingTooltip1:IsShown() then compare() end
end)

-- DragonUI's professions slot frames, by quality; the bronze one for the rest. Offsets (for a
-- 36 icon) put each on the icon's edge: the quality frames carry a shadow at the bottom right.
local SLOT_FRAMES = { [2] = "slot-frame-green", [3] = "slot-frame-blue", [4] = "slot-frame-epic", [5] = "slot-frame-legendary" }

local function placeSlotFrame(P, btn, quality)
	local name = SLOT_FRAMES[quality]
	local k = btn:GetWidth() / 36
	P.Art.Set(btn.slotFrame, name or "square-frame")
	btn.slotFrame:ClearAllPoints()
	if name then
		btn.slotFrame:SetPoint("TOPLEFT", btn, "TOPLEFT", -1.5 * k, 1.5 * k)
		btn.slotFrame:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 3.5 * k, -3.5 * k)
	else
		btn.slotFrame:SetPoint("TOPLEFT", btn, "TOPLEFT", -6.5 * k, 5.5 * k)
		btn.slotFrame:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 5.5 * k, -6.5 * k)
	end
end

-- A square item button with a quality border: DragonUI's professions slot frame when it has one.
function RPF.CreateItemButton(parent, size)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(size or 37, size or 37)
	btn.icon = btn:CreateTexture(nil, "ARTWORK")
	btn.icon:SetAllPoints(btn)
	btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	local P = RPF.ProfArt()
	if P then
		btn.slotFrame = btn:CreateTexture(nil, "OVERLAY")
		placeSlotFrame(P, btn, nil)
	end
	btn.border = btn:CreateTexture(nil, "OVERLAY")
	btn.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	btn.border:SetBlendMode("ADD")
	btn.border:SetPoint("CENTER", btn, "CENTER")
	btn.border:SetSize((size or 37) * 1.8, (size or 37) * 1.8)
	btn.border:Hide()
	btn.count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	btn.count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
	local hl = btn:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(btn)
	hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	hl:SetBlendMode("ADD")

	btn.SetItem = function (self, texture, quality, count)
		self.icon:SetTexture(texture)
		if P then
			placeSlotFrame(P, self, quality)
		elseif quality and quality >= 2 then
			local r, g, b = RPF.QualityColor(quality)
			self.border:SetVertexColor(r, g, b)
			self.border:Show()
		else
			self.border:Hide()
		end
		self.count:SetText(count and count > 1 and count or "")
	end
	return btn
end
