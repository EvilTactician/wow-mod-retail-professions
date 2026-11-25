-- Smoke test for the RetailProfessions addon outside the game: stubs just enough of the 3.3.5a
-- API (frames, skills, the trade skill window), loads the addon in .toc order and answers its
-- requests with a fake mod-retail-professions server (and mod-retail-ah's price lookups).
-- Usage (any Lua 5.3+): lua tools/addon_smoke_test.lua addon/RetailProfessions

local dir = arg[1] or "addon/RetailProfessions"
unpack = table.unpack
bit = {
	band = function (a, b) return math.floor(a) & math.floor(b) end,
	bor = function (a, b) return math.floor(a) | math.floor(b) end,
}
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strsplit(sep, text)
	local out = {}
	for part in (text .. sep):gmatch("(.-)" .. sep) do table.insert(out, part) end
	return table.unpack(out)
end

local now = 0
function GetTime() return now end
local clock = 1000
function time() clock = clock + 1 return clock end
date = os.date
function SetItemRef() end

local errors = 0
local function report(where, err)
	errors = errors + 1
	print("ERROR in " .. where .. ": " .. tostring(err))
end

-----------------------------------------
-- frames: tables with scripts; unknown methods are no-ops returning nil

local frameMeta = {}
local allFrames = {}
local function newObject(kind, name, parent)
	local o = { __kind = kind, __name = name, __scripts = {}, __shown = true, __text = "", __width = 100, __height = 20,
		__parent = parent, __enabled = true, __attrs = {} }
	setmetatable(o, frameMeta)
	if name then _G[name] = o end
	table.insert(allFrames, o)
	return o
end

local methods = {}
function methods:SetScript(event, fn) self.__scripts[event] = fn end
function methods:GetScript(event) return self.__scripts[event] end
function methods:HookScript(event, fn)
	local old = self.__scripts[event]
	self.__scripts[event] = function (...) if old then old(...) end fn(...) end
end
function methods:Show() local was = self.__shown; self.__shown = true; if not was and self.__scripts.OnShow then self.__scripts.OnShow(self) end end
function methods:Hide() local was = self.__shown; self.__shown = false; if was and self.__scripts.OnHide then self.__scripts.OnHide(self) end end
function methods:IsShown() return self.__shown end
function methods:IsVisible()
	local f = self
	while f do
		if not rawget(f, "__shown") then return false end
		f = rawget(f, "__parent")
	end
	return true
end
function methods:SetText(t) self.__text = t == nil and "" or tostring(t) end
function methods:GetText() return self.__text end
function methods:SetTexture(t) self.__texture = t end
function methods:GetTexture() return rawget(self, "__texture") end
function methods:SetChecked(c) self.__checked = c and 1 or nil end
function methods:GetChecked() return rawget(self, "__checked") end
function methods:GetWidth() return self.__width end
function methods:GetHeight() return self.__height end
function methods:SetWidth(w) self.__width = w end
function methods:SetHeight(h) self.__height = h end
function methods:SetSize(w, h) self.__width, self.__height = w, h end
function methods:GetName() return self.__name end
function methods:GetFrameLevel() return 1 end
function methods:GetObjectType() return self.__kind end
function methods:GetRegions() return end
function methods:CreateTexture() return newObject("Texture", nil, self) end
function methods:CreateFontString() return newObject("FontString", nil, self) end
function methods:Enable() self.__enabled = true end
function methods:Disable() self.__enabled = false end
function methods:IsEnabled() return self.__enabled and 1 or nil end
function methods:GetParent() return rawget(self, "__parent") end
function methods:SetParent(p) self.__parent = p end
function methods:GetEffectiveScale() return 1 end
function methods:GetLeft() return 100 end
function methods:GetTop() return 500 end
function methods:SetAttribute(k, v)
	if InCombatLockdown() and self.__kind == "Button" and self.__secure then error("SetAttribute on a secure frame in combat") end
	self.__attrs[k] = v
end
function methods:GetAttribute(k) return self.__attrs[k] end
function methods:GetPoint()
	if rawget(self, "__point") then return table.unpack(self.__point) end
	return "TOPLEFT", UIParent, "TOPLEFT", 10, -10
end
function methods:SetPoint(...) self.__point = { ... } end
frameMeta.__index = function (t, k)
	if methods[k] then return methods[k] end
	-- Unknown widget methods (capitalized) are no-ops; unset fields are nil, as in the game.
	if type(k) == "string" and k:match("^%u") then return function () end end
	return nil
end

local combat = false
function InCombatLockdown() return combat end

function CreateFrame(kind, name, parent, template)
	local f = newObject(kind, name, parent)
	if template and template:find("Secure") then f.__secure = true end
	if name and template then
		if template:find("Check") then _G[name .. "Text"] = newObject("FontString", nil, f) end
		if template:find("FauxScroll") then _G[name .. "ScrollBar"] = newObject("Slider", nil, f) end
	end
	-- Secure frames refuse Show/Hide in combat, as in the game.
	if f.__secure then
		f.Show = function (self) if combat then error("Show on a secure frame in combat") end methods.Show(self) end
		f.Hide = function (self) if combat then error("Hide on a secure frame in combat") end methods.Hide(self) end
	end
	return f
end

function FauxScrollFrame_Update(f, n, shown) if n > shown then f:Show() else f:Hide() end end
function FauxScrollFrame_GetOffset(f) return f and f.__offset or 0 end
function FauxScrollFrame_SetOffset(f, offset) f.__offset = offset end
function FauxScrollFrame_OnVerticalScroll(self, offset, h, fn) fn() end
function PlaySound() end
function IsModifiedClick() return false end
function IsShiftKeyDown() return false end
-- The cursor: an item entry while one is picked up (the gear steps drag items).
local cursor
function GetCursorInfo() if cursor then return "item", cursor, "item:" .. cursor end return nil end
function CursorHasItem() return cursor ~= nil end
function ClearCursor() cursor = nil end
local inserted
function ChatEdit_InsertLink(link) inserted = link return true end
function ChatFrame_OpenChat() end
function StaticPopup_Show(which, text) return { which = which, text = text } end
local lastMenu
function EasyMenu(items) lastMenu = items end
function CloseDropDownMenus() end
function UnitName() return "Tester" end
function UnitRace() return "Human", "Human" end
function UnitClass() return "Mage", "MAGE" end
function UnitLevel() return 70 end
function GetLocale() return "enUS" end
function SpellIsTargeting() return false end
function GetInventoryItemLink() return nil end
function GetContainerNumSlots() return 0 end
-- Bag contents by bag and slot: item entries.
local containers = {}
local itemLink
function GetContainerItemLink(bag, slot) local e = containers[bag] and containers[bag][slot] return e and itemLink(e) end
function GetItemIcon() return "Interface\\Icons\\X" end
local bindings = {}
function GetBindingAction(key) return bindings[key] or "" end
function SetBinding(key, action) bindings[key] = action end
function SaveBindings() end
function GetCurrentBindingSet() return 1 end
function GetBindingKey(action) for k, a in pairs(bindings) do if a == action then return k end end end
local closedTradeSkill, loadedClassic = 0, 0
function CloseTradeSkill() closedTradeSkill = closedTradeSkill + 1 end
function TradeSkillFrame_LoadUI() loadedClassic = loadedClassic + 1 end
function HideUIPanel(f) f:Hide() end
function AbandonSkill() end
function PickupContainerItem() end
function UseContainerItem() end
local errorsShown = {}
UIErrorsFrame = { AddMessage = function (_, text) table.insert(errorsShown, text) end }
ITEM_MIN_SKILL = "Requires %s (%d)"
function PickupInventoryItem() end
function ExpandSkillHeader() end
function CollapseSkillHeader() end

ITEM_QUALITY_COLORS = {}
for i = 0, 7 do ITEM_QUALITY_COLORS[i] = { r = 1, g = 1, b = 1, hex = "|cffffffff" } end
ACCEPT, CANCEL, CREATE, CREATE_ALL, TRADE_SKILLS = "Accept", "Cancel", "Create", "Create All", "Professions"
INVTYPE_CHEST, INVTYPE_FEET = "Chest", "Feet"
NUM_BAG_SLOTS = 4
UIParent = newObject("Frame", "UIParent")
WorldFrame = newObject("Frame", "WorldFrame")
GameTooltip = newObject("GameTooltip", "GameTooltip")
local tipLines = {}
function GameTooltip:SetOwner() tipLines = {}; self.__link = nil end
-- As the client: setting an item clears the tooltip, then says it holds an item.
function GameTooltip:SetHyperlink(link)
	tipLines = {}
	self.__link = link
	if self.__scripts.OnTooltipCleared then self.__scripts.OnTooltipCleared(self) end
	if link:find("item:") and self.__scripts.OnTooltipSetItem then self.__scripts.OnTooltipSetItem(self) end
end
function GameTooltip:GetItem() local l = rawget(self, "__link") if l and l:find("item:") then return "x", l end end
local worn = {}
function GetInventoryItemID(_, slot) return worn[slot] end
function GameTooltip:AddLine(text) table.insert(tipLines, tostring(text)) end
-- The tooltip a chat link opens, with its own lines.
ItemRefTooltip = newObject("GameTooltip", "ItemRefTooltip")
local refLines = {}
function ItemRefTooltip:GetItem() local l = rawget(self, "__link") if l then return "x", l end end
function ItemRefTooltip:AddLine(text) table.insert(refLines, tostring(text)) end
function ItemRefTooltip:SetHyperlink(link)
	refLines = {}
	self.__link = link
	if self.__scripts.OnTooltipCleared then self.__scripts.OnTooltipCleared(self) end
	if self.__scripts.OnTooltipSetItem then self.__scripts.OnTooltipSetItem(self) end
end
ShoppingTooltip1 = newObject("GameTooltip", "ShoppingTooltip1")
ShoppingTooltip2 = newObject("GameTooltip", "ShoppingTooltip2")
local compared = 0
function GameTooltip_ShowCompareItem() compared = compared + 1 end
function UnitCastingInfo() return nil end
DEFAULT_CHAT_FRAME = { AddMessage = function (_, m) print("  [chat] " .. m) end }
GameFontHighlightSmall, GameFontNormalSmall = {}, {}
StaticPopupDialogs, SlashCmdList, UISpecialFrames = {}, {}, {}

-----------------------------------------
-- the game data

local items = {
	[2589] = { "Linen Cloth", 1 }, [2320] = { "Coarse Thread", 1 }, [2996] = { "Bolt of Linen Cloth", 1 },
	[2568] = { "Brown Linen Vest", 1, "INVTYPE_CHEST" }, [4308] = { "Green Linen Bracers", 2, "INVTYPE_WRIST" },
	[4355] = { "Pattern: Green Linen Bracers", 2 }, [2321] = { "Fine Thread", 1 },
	[2447] = { "Peacebloom", 1 }, [785] = { "Mageroyal", 1 }, [39151] = { "Alabaster Pigment", 1 },
	[39334] = { "Dusky Pigment", 1 }, [43103] = { "Verdant Pigment", 2 },
	-- Profession equipment: a Tailoring tool and accessory, a Mining accessory, plain tools.
	[90800] = { "Tailor's Shears", 2 }, [90801] = { "Tailor's Thimble", 3 }, [90802] = { "Prospector's Lamp", 2 },
	[5956] = { "Blacksmith Hammer", 1 }, [6219] = { "Arclight Spanner", 1 },
}
function itemLink(id) return "|cffffffff|Hitem:" .. id .. ":0:0:0:0:0:0:0:0|h[" .. items[id][1] .. "]|h|r" end
function GetItemInfo(item)
	local id = type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)"))
	local d = id and items[id]
	if not d then return nil end
	return d[1], itemLink(id), d[2], 10, 1, "Trade Goods", "Cloth", 20, d[3] or "", "Interface\\Icons\\X", 10
end
local bags = { [2589] = 4 }
function GetItemCount(id) return bags[id] or 0 end

local spells = {
	[3908] = "Tailoring", [2259] = "Alchemy", [2575] = "Mining", [2656] = "Smelting", [2580] = "Find Minerals",
	[7620] = "Fishing", [2963] = "Bolt of Linen Cloth", [2385] = "Brown Linen Vest", [3914] = "Green Linen Bracers",
	[45357] = "Inscription", [8613] = "Skinning", [51005] = "Milling", [25229] = "Jewelcrafting", [31252] = "Prospecting",
	[2018] = "Blacksmithing", [7411] = "Enchanting", [4036] = "Engineering", [2108] = "Leatherworking",
	[2550] = "Cooking", [3273] = "First Aid", [53428] = "Runeforging",
}
local knownSpells = { Tailoring = true, Smelting = true, Mining = true, ["Find Minerals"] = true, Fishing = true }
-- Crafts take three seconds here.
local castTimes = { [2963] = 3000, [2385] = 3000, [3914] = 3000 }
local spellIcons = { [2575] = "Interface\\Icons\\Trade_Mining", [2656] = "Interface\\Icons\\Spell_Fire_FlameBlades" }
function GetSpellInfo(spell)
	if type(spell) == "number" then
		return spells[spell], nil, spellIcons[spell] or "Interface\\Icons\\S", 0, false, 0, castTimes[spell] or 0
	end
	if knownSpells[spell] then return spell, nil, "Interface\\Icons\\S" end
	return nil
end
function GetSpellLink(id) return "|Hspell:" .. id .. "|h[" .. tostring(spells[id]) .. "]|h" end

local skillLines = {
	{ "Professions", true }, { "Tailoring", false, 120, 150 }, { "Mining", false, 50, 75 },
	{ "Secondary Skills", true }, { "Fishing", false, 1, 75 },
}
function GetNumSkillLines() return #skillLines end
function GetSkillLineInfo(i)
	local s = skillLines[i]
	return s[1], s[2], true, s[3] or 0, 0, s[5] or 0, s[4] or 0, not s[2]
end

-- The trade skill window: one header and two learned recipes.
local tradeSkill = {
	{ "Cloth", "header" },
	{ "Bolt of Linen Cloth", "optimal", 2, spell = 2963, item = 2996, reagents = { { 2589, 2 } } },
	{ "Brown Linen Vest", "medium", 0, spell = 2385, item = 2568, reagents = { { 2589, 3 }, { 2320, 1 } } },
}
local selectedIndex = 0
local crafted = {}
local tradeSkillLine = { "Tailoring", 120, 150 }
function GetTradeSkillLine() return table.unpack(tradeSkillLine) end
function GetNumTradeSkills() return #tradeSkill end
function GetTradeSkillInfo(i)
	local t = tradeSkill[i]
	if not t then return nil end
	return t[1], t[2], t[3] or 0, t[2] == "header" and 1 or nil
end
function GetTradeSkillRecipeLink(i) local t = tradeSkill[i] return t.spell and ("|cffffd000|Henchant:" .. t.spell .. "|h[" .. t[1] .. "]|h|r") end
function GetTradeSkillItemLink(i) local t = tradeSkill[i] return t.item and itemLink(t.item) end
function GetTradeSkillIcon() return "Interface\\Icons\\T" end
-- A row that isn't there (a stale index) has no reagents, as in the client.
function GetTradeSkillNumReagents(i) return #((tradeSkill[i] or {}).reagents or {}) end
function GetTradeSkillReagentInfo(i, r) local rg = tradeSkill[i].reagents[r] return items[rg[1]][1], "Interface\\Icons\\R", rg[2], bags[rg[1]] or 0 end
function GetTradeSkillReagentItemLink(i, r) return itemLink(tradeSkill[i].reagents[r][1]) end
function GetTradeSkillDescription() return "" end
function GetTradeSkillTools() return end
function GetTradeSkillCooldown() return nil end
function GetTradeSkillNumMade() return 1, 1 end
function SelectTradeSkill(i) selectedIndex = i end
function GetTradeSkillSelectionIndex() return selectedIndex end
function DoTradeSkill(i, n) table.insert(crafted, { i, n }) end
function ExpandTradeSkillSubClass() end
function SetTradeSkillItemNameFilter() end
function SetTradeSkillItemLevelFilter() end
function SetTradeSkillSubClassFilter() end
function SetTradeSkillInvSlotFilter() end
function TradeSkillOnlyShowMakeable() end
function TradeSkillOnlyShowSkillUps() end
function IsTradeSkillLinked() return nil end
function GetTradeSkillListLink() return "|Htrade:3908:120:150|h[Tailoring]|h" end

-- With DRAGON=1, a DragonUI stand-in, so the skinned branches run too. DRAGON=2 adds its
-- professions window's art (DragonUI.Professions), which the profession window then wears.
-- DRAGON=3 adds its professions window's host (DragonUI.Professions.Host): we live in its window.
local DRAGON = os.getenv("DRAGON")
if DRAGON == "1" or DRAGON == "2" or DRAGON == "3" then
	DragonUI_NineSlice = { GetLayout = function () return {} end, ApplyLayout = function () end }
	DragonUI = {
		_dir = "Interface\\AddOns\\DragonUI\\Textures\\", atlasinfo = {},
		SafeSetAtlas = function () return true end, SkinRedButton = function () end,
		CharacterPanel = { ReskinTab = function () end, ModernizeCloseButton = function () end,
			SkinCheckbox = function () end,
			-- As DragonUI's: it hooks the scroll frame to move its thumb.
			ReskinScrollBar = function (scroll)
				scroll:HookScript("OnVerticalScroll", function (self) self.__thumbMoved = true end)
			end },
	}
end
if DRAGON == "2" or DRAGON == "3" then
	local function piece(w, h) return { "Interface\\AddOns\\DragonUI\\Textures\\Professions\\Sheet", w, h, 0, 1, 0, 1 } end
	local atlas = setmetatable({ ["bg-crafting"] = piece(665, 570), ["card-base"] = piece(360, 484),
		["carddraw-Tailoring"] = piece(280, 255), ["carddraw-Mining"] = piece(280, 255) },
		{ __index = function (_, name) return piece(20, 20) end })
	DragonUI.Professions = {
		Atlas = atlas,
		Art = {
			Set = function (tex, name, useSize)
				local info = atlas[name]
				tex.__art = name
				if useSize then tex:SetSize(info[2], info[3]) end
				return info
			end,
			SetInset = function (tex, name) tex.__art = name end,
			SetClipped = function (tex, name, w, h) tex.__art = name tex:SetSize(w, h) end,
			ThreeSlice = function (parent, layer)
				return parent:CreateTexture(nil, layer), parent:CreateTexture(nil, layer), parent:CreateTexture(nil, layer)
			end,
			NineSlice = function (parent, layer)
				local pieces = {}
				for i = 1, 9 do if i ~= 5 then pieces[i] = parent:CreateTexture(nil, layer) end end
				return pieces
			end,
			PlaceNineSlice = function () end,
			RankText = function (parent)
				return { SetCenter = function () end, Set = function (self, prefix, max) self.full = prefix .. "/" .. max end }
			end,
			CardDrawing = function (key)
				local name = key and ("carddraw-" .. key)
				return name and rawget(atlas, name) and name or nil
			end,
		},
		Fill = {
			Create = function (parent) return CreateFrame("Frame", nil, parent) end,
			Update = function (fx, key, ratio, isFull) fx.key, fx.ratio, fx.isFull = key, ratio, isFull end,
		},
		-- Skill lines are the professions' names here, without spaces for the key.
		Professions = { EntryForLine = function (line) return { key = (line:gsub(" ", "")) } end },
	}
	DragonUI.ForeverAtlas = setmetatable({}, { __index = function () return piece(20, 20) end })
	DragonUI.ForeverUI = {
		ApplyNineSlice = function () return {} end,
		SkinEditBox = function (box) box.__forever = true end,
		SetAtlas = function () return true end,
		Fonts = { HighlightMedium = {} },
	}
end
function SetPortraitToTexture(tex, path) tex.__portrait = path end

-- DragonUI's professions host, as far as we use it: the window (TradeSkillFrame) is opened and
-- closed by the steps, as UIParent and DragonUI would.
local Host
if DRAGON == "3" then
	Host = { VERSION = 1, pages = {}, tabs = {}, page = "crafting", overviewToggles = 0, collectors = {} }
	DragonUI.Professions.Host = Host
	TradeSkillFrame = CreateFrame("Frame", "TradeSkillFrame", UIParent)
	TradeSkillFrame:Hide()
	Host.craft = CreateFrame("Frame", nil, TradeSkillFrame)
	function Host.Enabled() return true end
	-- Like DragonUI, the pieces go in once its window is built (Blizzard's trade skill UI loads
	-- on demand), which can be long after Register.
	function Host.Build()
		Host.built = true
		local p = Host.provider
		if not p or Host.applied then return end
		Host.applied = true
		Host.regions = { list = p.list(Host.craft), card = p.card(Host.craft), controls = p.controls(Host.craft),
			header = p.header(Host.craft) }
		for _, page in pairs(Host.pages) do page.frame = page.spec.build(TradeSkillFrame) end
	end
	function Host.Register(p)
		Host.provider = p
		if Host.built then Host.Build() end
		return true
	end
	function Host.Unregister(p)
		if Host.provider == p then Host.provider = nil; Host.applied = false; Host.pages = {}; Host.tabs = {} end
	end
	function Host.RefreshHeader() Host.headerRefreshes = (Host.headerRefreshes or 0) + 1 end
	function Host.AddPage(key, spec) Host.pages[key] = { spec = spec } end
	function Host.AddTab(spec)
		for i, tab in ipairs(Host.tabs) do if tab.key == spec.key then Host.tabs[i] = spec return end end
		table.insert(Host.tabs, spec)
	end
	function Host.Page() return Host.page end
	function Host.SetPage(key)
		Host.page = key
		for k, page in pairs(Host.pages) do if page.frame then if k == key then page.frame:Show() else page.frame:Hide() end end end
		if Host.provider then Host.provider.onPage(key) end
	end
	function Host.RefreshTabs() Host.tabRefreshes = (Host.tabRefreshes or 0) + 1 end
	function Host.TrackerEnabled() return true end
	function Host.AddTrackerCollector(fn) table.insert(Host.collectors, fn) return true end
	function Host.RefreshTracker() end
	function Host.HighlightBlock() end
	function Host.ClickBlock() end
	function Host.NewCatcherId() return 500 end
	Host.Catchers = { Bind = function () return true end, ArmFor = function () end }
	function Host.ToggleOverview() Host.overviewToggles = Host.overviewToggles + 1 end
	function Host.Blocks()
		local blocks = {}
		for _, fn in ipairs(Host.collectors) do fn(blocks) end
		return blocks
	end
	-- What a profession opening and the window closing do.
	function Host.Open()
		Host.Build()
		TradeSkillFrame:Show()
		Host.SetPage("crafting")
		Host.provider.onShow()
	end
	function Host.Close()
		TradeSkillFrame:Hide()
		Host.provider.onHide()
	end
end

-- ReagentBankUI, as far as we use it.
local provider, withdrawn
ReagentBankUI = {
	banked = { [2589] = 30 },
	GetCachedBankItemCount = function (self, id) return self.banked[id] or 0 end,
	RegisterRecipeProvider = function (_, p) provider = p return true end,
	RequestBankSnapshot = function () end,
	NotifyRecipeProviderChanged = function () end,
	-- Like the real one: Withdraw Needed fetches for ReagentBankUI's own "Crafts" count.
	prepareCount = 1,
	SetTradeSkillPrepareCount = function (self, n) self.prepareCount = n end,
	WithdrawNeededForSelectedRecipe = function (self)
		local name, reagents = provider.GetRecipe()
		withdrawn = { name = name, count = self.prepareCount, reagents = reagents }
	end,
	GetTradeSkillControlsHost = function () return provider and provider.frame end,
	-- The auction house shopping list: what the provider's recipe and amount are short of.
	shopping = {},
	GetShoppingListMap = function (self) return self.shopping end,
	AddShoppingListRows = function (self, rows)
		for _, row in ipairs(rows) do self.shopping[row.itemEntry] = (self.shopping[row.itemEntry] or 0) + row.amount end
	end,
	-- What the bank holds isn't known until its snapshot arrives.
	snapshot = true,
	HasFreshBankSnapshot = function (self) return self.snapshot end,
	HandleBankSnapshotResponse = function (self) self.snapshot = true end,
	leftovers = false,
	GetAutoDepositLeftovers = function (self) return self.leftovers end,
	SetAutoDepositLeftovers = function (self, on) self.leftovers = on and true or false end,
}
-- A ReagentBankUI that still has its profession sidebar docks it on our window.
local bankPanel
function ReagentBankUI:DockTradeSkillPanel()
	bankPanel = bankPanel or CreateFrame("Frame")
	bankPanel.__point = { "TOPLEFT", self:GetTradeSkillControlsHost(), "TOPRIGHT", -33, -12 }
	self.tradeSkillPanel = bankPanel
	bankPanel:Show()
end
-- Blizzard_TrainerUI is load-on-demand: it loads in the trainer step below.
function IsAddOnLoaded() return false end
function hooksecurefunc(t, name, fn)
	if type(t) == "string" then t, name, fn = _G, t, name end
	local orig = t[name]
	t[name] = function (...) local r = orig(...) fn(...) return r end
end

-----------------------------------------
-- events and the fake server

local outbox = {}
function SendAddonMessage(prefix, msg, channel)
	assert((prefix == "RPR" or prefix == "RAH") and channel == "WHISPER", "bad addon message")
	assert(#prefix + 1 + #msg <= 254, "addon message too long")
	table.insert(outbox, { prefix, msg })
end

local eventFrames = {}
function methods:RegisterEvent(e) eventFrames[e] = eventFrames[e] or {}; table.insert(eventFrames[e], self) end
function methods:UnregisterEvent() end
local function fire(event, ...)
	for _, f in ipairs(eventFrames[event] or {}) do
		local ok, err = pcall(f.__scripts.OnEvent, f, event, ...)
		if not ok then report(event, err) end
	end
end

local function reply(msg) fire("CHAT_MSG_ADDON", "RPR", msg, "WHISPER", "Tester") end

-- mod-retail-ah's K: per item lowest buyout, units, AH bot pays, vendor price, vendor pays,
-- units sold, copper sold, flags.
local ahPrices = {
	[2589] = "10,200,8,0,1,100,1200,0", [2320] = "0,0,0,10,2,0,0,0", [2996] = "60,20,40,0,10,0,0,0",
	[2568] = "300,3,150,0,70,5,1400,0", [4308] = "0,0,0,0,50,0,0,2", [2321] = "0,0,0,30,5,0,0,0",
}
local rahSent, rahDown = {}, false
local function serveAH(msg)
	local cmd, req, rest = msg:match("^([^:]+):([^:]*):?(.*)$")
	table.insert(rahSent, msg)
	print("  RAH -> " .. msg)
	if rahDown then return end
	if cmd == "KC" then
		fire("CHAT_MSG_ADDON", "RAH", "ERR:" .. req .. ":unknown", "WHISPER", "Tester")
		return
	end
	assert(cmd == "K", "unexpected RAH request " .. msg)
	local rows = {}
	for entry in rest:gmatch("%d+") do
		if ahPrices[tonumber(entry)] then table.insert(rows, entry .. "," .. ahPrices[tonumber(entry)]) end
	end
	fire("CHAT_MSG_ADDON", "RAH", "KR:" .. req .. ":5:14", "WHISPER", "Tester")
	fire("CHAT_MSG_ADDON", "RAH", "KD:" .. req .. ":" .. table.concat(rows, ";"), "WHISPER", "Tester")
	fire("CHAT_MSG_ADDON", "RAH", "KE:" .. req, "WHISPER", "Tester")
end

-- Profession equipment on the fake server: the HELLO flags (63 adds HELLO_GEAR), the slots as
-- { skill, slot, entry, guid }, and a refusal for the next equip.
local helloFlags = 31
local gearSlots = { { 197, 0, 90800, 5001 } }
local gearRefuse
local nextGuid = 6000
local function gearRows()
	local rows = {}
	for _, g in ipairs(gearSlots) do table.insert(rows, table.concat(g, ",")) end
	return table.concat(rows, ";")
end
local function serveGear(cmd, req, msg)
	if cmd == "GC" then
		-- entry, skill, kind, skill bonus, multicraft, resourcefulness, speed, finesse, perception,
		-- deftness, required skill line and rank.
		reply("GCD:" .. req .. ":90800,197,0,10,5,3,10,0,0,0,197,100;90801,197,1,0,90,0,50,0,0,0,197,100")
		reply("GCD:" .. req .. ":90802,186,1,5,0,0,0,4,6,10,186,200")
		reply("GCE:" .. req .. ":3")
	elseif cmd == "G" then
		if #gearSlots > 0 then reply("GD:" .. req .. ":" .. gearRows()) end
		reply("GE:" .. req .. ":" .. #gearSlots)
	elseif cmd == "GT" then
		if msg:match("^GT:[^:]*:197$") then
			reply("GTD:" .. req .. ":T,i5956,Blacksmith Hammer,5956;T,c14,Arclight Spanner,6219/90801")
			reply("GTD:" .. req .. ":S,2963,i5956;S,2385,c14")
			reply("GTE:" .. req .. ":4")
		else
			reply("GTE:" .. req .. ":0")
		end
	elseif cmd == "GQ" then
		local bag, bagSlot, skill, slot = msg:match("^GQ:[^:]*:(%d+):(%d+):(%d+):(%d+)$")
		bag, bagSlot, skill, slot = tonumber(bag), tonumber(bagSlot), tonumber(skill), tonumber(slot)
		local entry = containers[bag] and containers[bag][bagSlot]
		if gearRefuse or not entry then
			reply("ERR:" .. req .. ":" .. (gearRefuse or "noitem"))
			gearRefuse = nil
			return
		end
		if skill == 0 then skill = entry == 90802 and 186 or 197 end
		if slot == 9 then slot = 1 end
		containers[bag][bagSlot] = nil
		nextGuid = nextGuid + 1
		table.insert(gearSlots, { skill, slot, entry, nextGuid })
		reply("GQ:" .. req .. ":ok:" .. skill .. ":" .. slot)
		reply("GD:0:" .. gearRows())
		reply("GE:0:" .. #gearSlots)
	elseif cmd == "GU" then
		local skill, slot = msg:match("^GU:[^:]*:(%d+):(%d+)$")
		for i, g in ipairs(gearSlots) do
			if g[1] == tonumber(skill) and g[2] == tonumber(slot) then table.remove(gearSlots, i) break end
		end
		reply("GU:" .. req .. ":ok")
		if #gearSlots > 0 then reply("GD:0:" .. gearRows()) end
		reply("GE:0:" .. #gearSlots)
	end
end

local sent = {}
local millJob -- the request id of the milling job the fake server is running
local function serve(msg)
	local cmd, req = msg:match("^([^:]+):([^:]*)")
	table.insert(sent, msg)
	print("  -> " .. msg)
	-- Flags: recipes, map pins, milling, perks. Perks: multicraft 0-25%, resourcefulness 0-20%
	-- giving 30% back, casts 0-50% faster.
	if cmd == "HELLO" then reply("HELLO:" .. req .. ":1:" .. helloFlags .. ":777:300:100:0:3:0:25:0:20:30:0:50")
	elseif cmd == "GC" or cmd == "G" or cmd == "GT" or cmd == "GQ" or cmd == "GU" then serveGear(cmd, req, msg)
	elseif cmd == "Y" then
		-- Peacebloom, Mageroyal (a second pigment one time in four) and a herb past the skill.
		reply("YR:" .. req .. ":M:3")
		reply("YD:" .. req .. ":S,2447,1,Peacebloom;R,2447,39151,2,4,10000;S,785,50,Mageroyal;R,785,39334,2,3,10000")
		reply("YD:" .. req .. ":R,785,43103,1,3,2500;S,36901,325,Goldclover;R,36901,39343,2,4,10000")
		reply("YE:" .. req)
	elseif cmd == "X" then
		local item, count = msg:match("^X:[^:]*:M:(%d+):(%d+)$")
		assert(item, "bad X request " .. msg)
		millJob = req
		reply("X:" .. req .. ":ok:" .. count .. ":1000")
	elseif cmd == "XS" then
		if millJob then reply("XE:" .. millJob .. ":1:4:stopped") end
		millJob = nil
		reply("XS:" .. req .. ":ok")
	elseif cmd == "L" then
		reply("LR:" .. req .. ":197:3:0")
		-- The bolt stacks, so it can multicraft (perks 7); the vest can't (6).
		reply("LD:" .. req .. ":2963,1,25,50,2996,1,1,1,2589*2,0,1,0,0,7;2385,10,45,70,2568,1,1,1,2589*3/2320*1,5,1,0,0,6")
		reply("LD:" .. req .. ":3914,130,155,175,4308,1,1,2,2996*2/2321*1,9,2,4355")
		reply("LE:" .. req)
	elseif cmd == "W" then
		reply("WR:" .. req .. ":3914:4355")
		-- Old-style rows (7 fields) and guide rows (a note and tooltip details), more than fit.
		reply("WD:" .. req .. ":V,1474,Rann Flamespinner,Elwynn Forest,100,1,Friendly with Stormwind;D,100,Gruff Swiftbite,Elwynn%2C Forest,550,10-11,-;X,0,-,-,1234,10-20,-")
		reply("WD:" .. req .. ":N,8696,Henry Stern,Razorfen Downs,0,0,-,-,Talk to them to learn the recipe%0ANeeds Tailoring 125"
			.. ";Q,862,Dig Rat Stew,The Barrens,30,25,Grub,daily,Quest giver: Grub - The Barrens%0ALevel 30 quest%2C from level 25"
			.. ";X,0,-,-,40,80-83,Ulduar,trash,From 40 kinds of creatures%2C level 80-83%0AMostly in Ulduar")
		reply("WD:" .. req .. ":D,6,Kobold Vermin,Elwynn Forest,1200,2-3,-,rare,Level 2-3%0AA rare spawn"
			.. ";V,1475,Token Seller,Dalaran,0,0,-,3 Dalaran Cooking Award,Costs 3 Dalaran Cooking Award"
			.. ";C,44113,Small Spice Bag,-,1500,0,-,Reward from the daily quest Sewer Stew (Dalaran),Reward from the daily quest Sewer Stew (Dalaran)%0ALocked: open it with Lockpicking"
			.. ";P,0,12 kinds of creatures%2C level 20-35,-,0,0,-,-,Pickpocketed from 12 kinds of creatures"
			.. ";O,2843,Battered Chest,Westfall,500,0,-,-,In 5%25 of them"
			.. ";L,0,Outland,-,3,0,-,-,-")
		reply("WE:" .. req)
	elseif cmd == "M" then reply("M:" .. req .. ":ok:Elwynn Forest (44%2C 65)")
	else print("  !! unknown command " .. cmd) end
end

local function tick(seconds)
	for _ = 1, math.ceil(seconds / 0.05) do
		now = now + 0.05
		for _, f in ipairs(allFrames) do
			if f.__shown and f.__scripts.OnUpdate then
				local ok, err = pcall(f.__scripts.OnUpdate, f, 0.05)
				if not ok then report("OnUpdate", err) end
			end
		end
		while #outbox > 0 do
			local m = table.remove(outbox, 1)
			if m[1] == "RAH" then serveAH(m[2]) else serve(m[2]) end
		end
	end
end

local function step(name, fn)
	print("== " .. name)
	local ok, err = xpcall(fn, debug.traceback)
	if not ok then errors = errors + 1; print("ERROR: " .. err) end
	tick(0.5)
end

for line in io.lines(dir .. "/RetailProfessions.toc") do
	if line:match("%.lua$") then
		local chunk, err = loadfile(dir .. "/" .. line)
		if not chunk then report("load " .. line, err) else
			local ok, e = pcall(chunk, "RetailProfessions", {})
			if not ok then report("run " .. line, e) end
		end
	end
end

local RPF = RetailProfessions
local M = RPF.Model
local function find(pred)
	for _, f in ipairs(allFrames) do if pred(f) then return f end end
end
local function buttonWithText(text)
	return find(function (f) return f.__kind == "Button" and f.__text == text end)
end
-- Money as text: coin icons back to g/s/c, colours dropped.
local function money(text)
	text = tostring(text or ""):gsub("|T[^|]-UI%-(%a+)Icon[^|]*|t", function (coin)
		return coin == "Gold" and "g" or coin == "Silver" and "s" or "c"
	end)
	return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function textShown(pattern)
	return find(function (f) return f.__kind == "FontString" and f.__text:find(pattern) and f:IsVisible() end)
end

step("login, hello", function ()
	fire("ADDON_LOADED", "RetailProfessions")
	fire("PLAYER_LOGIN")
	tick(4)
	assert(RPF.serverReady, "no HELLO answer")
	assert(RPF.skillCap == 300 and RPF.skillGain == 3, "HELLO fields not read")
	assert(bindings.K == "RETAILPROFESSIONS_BOOK", "K was not bound to the book")
	if DRAGON == "3" then
		assert(RPF.hosting and Host.provider, "DragonUI's window didn't take us in")
		assert(not Host.regions, "pieces placed before DragonUI's window was built")
	else
		assert(provider and provider.frame == RetailProfessionsFrame, "not registered with ReagentBankUI")
	end
end)

-- In DragonUI's window: its own steps, then done.
if DRAGON == "3" then
	step("hosted: the Overview with no profession open", function ()
		Host.Build()
		TradeSkillFrame:Show()
		Host.provider.onShow()
		tick(0.5)
		assert(RPF.WindowOpen() and not RPF.IsOpen() and not RPF.active, "a profession counts as open")
		assert(provider and provider.frame:GetParent() == TradeSkillFrame and not provider.frame:IsShown(),
			"ReagentBankUI would take us for the open window")
		Host.SetPage("retailprofessions-training")
		assert(RPF.Home.Active() == "training", "Training doesn't open from the Overview")
		assert(not RPF.Refine.IsOpen(RPF.Refine.Kind("M")), "Inscription counts as open")
		Host.SetPage("crafting")
		TradeSkillFrame:Hide()
		Host.provider.onHide()
	end)

	step("hosted: our pieces are in DragonUI's window", function ()
		local pieces = RPF.HostPieces()
		assert(Host.regions.list == pieces.list and Host.regions.card == pieces.card
			and Host.regions.controls == pieces.controls, "the list, card and controls aren't DragonUI's to place")
		assert(pieces.list:GetParent() == Host.craft and pieces.card:GetParent() == Host.craft, "not moved into its window")
		assert(Host.pages["retailprofessions-training"] and Host.pages["retailprofessions-profit"],
			"no Training or Profit page")
		local keys = {}
		for _, tab in ipairs(Host.tabs) do keys[tab.key] = tab end
		assert(keys["retailprofessions-training"] and keys["retailprofessions-profit"]
			and keys["retailprofessions-refine-M"] and keys["retailprofessions-refine-P"],
			"Training, Profit, Milling and Prospecting tabs missing")
		assert(Host.provider.overview() == "retailprofessions-training", "Training doesn't stand in for the Overview")
	end)

	step("hosted: a profession opens in DragonUI's window, unlearned recipes and all", function ()
		Host.Open()
		fire("TRADE_SKILL_SHOW")
		tick(0.5)
		assert(not RetailProfessionsFrame:IsShown(), "our own window opened too")
		assert(RPF.IsOpen() and RPF.active, "not open")
		assert(#M.recipes == 2 and #M.unlearned == 1, "recipes: " .. #M.recipes .. ", unlearned " .. #M.unlearned)
		assert(textShown("Unlearned: Journeyman"), "unlearned group header not shown in DragonUI's window")
		assert(Host.provider.title() == "Tailoring", "title: " .. tostring(Host.provider.title()))
		assert(provider.frame:IsShown(), "ReagentBankUI doesn't see us while a profession is open")
		assert((Host.tabRefreshes or 0) > 0 and (Host.headerRefreshes or 0) > 0,
			"tabs and title not read again after the scan")
	end)

	step("hosted: profession equipment on DragonUI's card and its Equipment page", function ()
		helloFlags = 63
		RPF.SayHello()
		tick(1)
		RPF.Select(M.bySpell[2963])
		local strip = RPF.gearStrip
		assert(strip:GetParent() == RPF.HostPieces().card and strip:IsVisible() and strip.buttons[1].entry == 90800,
			"no slots on the card in DragonUI's window")
		Host.SetPage("retailprofessions-equipment")
		tick(0.3)
		assert(RPF.Home.Active() == "equipment", "DragonUI's Equipment page didn't open Equipment")
		local shown = 0
		for _, row in ipairs(RPF.Home.rows.cards) do
			for _, card in ipairs(row) do if card:IsVisible() then shown = shown + 1 end end
		end
		assert(shown == 2, "Equipment's cards in DragonUI's window: " .. shown)
		Host.SetPage("crafting")
		helloFlags = 31
		RPF.SayHello()
		tick(1)
		assert(not strip:IsShown(), "slots stayed without HELLO_GEAR")
	end)

	step("hosted: create and create all", function ()
		RetailProfessionsDB.autoWithdraw = false
		RPF.Select(M.bySpell[2963])
		buttonWithText("Create").__scripts.OnClick()
		assert(crafted[#crafted][1] == 2 and crafted[#crafted][2] == 1, "Create did the wrong thing")
		local name = provider.GetRecipe()
		assert(name == "Bolt of Linen Cloth", "ReagentBankUI reads the wrong recipe")
	end)

	step("hosted: Training and Profit are pages of DragonUI's window", function ()
		local panels = RPF.Home.panels
		Host.SetPage("retailprofessions-training")
		assert(RPF.Home.Active() == "training" and panels.training:IsVisible(), "Training not shown")
		assert(not panels.profit:IsVisible(), "Profit shows under Training")
		Host.SetPage("retailprofessions-profit")
		assert(RPF.Home.Active() == "profit" and panels.profit:IsVisible(), "Profit not shown")
		assert(not panels.training:IsVisible(), "Training shows under Profit")
		assert(Host.provider.title() == "Profit", "title: " .. tostring(Host.provider.title()))
		RPF.Home.SetActive("training")
		assert(Host.page == "retailprofessions-training", "Training didn't switch the page: " .. Host.page)
		RPF.Home.SetActive(false)
		assert(Host.page == "crafting", "leaving Training didn't go back to the recipes: " .. Host.page)
	end)

	step("hosted: K opens DragonUI's Overview", function ()
		RPF.ToggleBook()
		assert(Host.overviewToggles == 1, "the Overview didn't open")
		assert(not RetailProfessionsBook:IsShown(), "our book opened")
	end)

	step("hosted: tracked recipes go in DragonUI's objective tracker", function ()
		RPF.ToggleTracked(M.bySpell[2385])
		tick(0.5)
		local blocks = Host.Blocks()
		assert(#blocks == 1 and blocks[1].title:find(M.bySpell[2385].name, 1, true) and #blocks[1].lines >= 1,
			"tracker block: " .. #blocks)
		assert(not RetailProfessionsTracker:IsShown(), "our tracker shows as well")
		RPF.ToggleTracked(M.bySpell[2385])
		assert(#Host.Blocks() == 0, "untracking didn't remove it")
	end)

	step("hosted: closing DragonUI's window ends the visit", function ()
		Host.Close()
		fire("TRADE_SKILL_CLOSE")
		tick(0.5)
		assert(not RPF.IsOpen() and not RPF.active, "still open")
		assert(not provider.frame:IsShown(), "ReagentBankUI still sees us")
	end)

	step("hosted: /prof classic gives DragonUI's own page, /prof retail takes it back", function ()
		SlashCmdList.RETAILPROFESSIONS("classic")
		assert(not RPF.hosting and RPF.hostClassic and not Host.provider, "classic didn't hand the window back")
		assert(not provider.frame:IsShown(), "ReagentBankUI would use us on DragonUI's own page")
		TradeSkillFrame:Show()
		fire("TRADE_SKILL_SHOW")
		tick(0.5)
		assert(not RetailProfessionsFrame:IsShown(), "our window opened on classic")
		TradeSkillFrame:Hide()
		SlashCmdList.RETAILPROFESSIONS("retail")
		assert(RPF.hosting and Host.provider, "retail didn't take the window again")
	end)

	print(errors == 0 and "smoke test passed" or (errors .. " error(s)"))
	os.exit(errors == 0 and 0 or 1)
end

step("skill-up chance follows the core's straight line", function ()
	assert(RPF.SkillUpChance(40, 45, 70) == 100, "orange")
	assert(RPF.SkillUpChance(57, 45, 70) == 52, "midway: " .. tostring(RPF.SkillUpChance(57, 45, 70)))
	assert(RPF.SkillUpChance(70, 45, 70) == 0, "grey")
end)

step("open tailoring", function ()
	fire("TRADE_SKILL_SHOW")
	tick(0.5)
	assert(RetailProfessionsFrame:IsShown(), "window not shown")
	assert(#M.recipes == 2, "learned recipes: " .. #M.recipes)
	assert(M.hasServerData, "server list not merged")
	assert(#M.unlearned == 1 and M.unlearned[1].spell == 3914, "unlearned recipe missing")
	local vest = M.bySpell[2385]
	assert(vest.yellow == 45 and vest.slot == "INVTYPE_CHEST", "server data not attached")
	assert(RPF.selected, "nothing selected")
	assert(textShown("Unlearned: Journeyman"), "unlearned group header missing")
	-- Two profession tabs: Tailoring and Mining (Smelting); Fishing has no window.
	local tabs = 0
	for i = 1, 10 do local b = _G["RetailProfessionsTab" .. i] if b and b.__shown then tabs = tabs + 1 end end
	assert(tabs == 2, "tabs shown: " .. tabs)
	assert(RetailProfessionsTab1:GetAttribute("spell") == "Tailoring", "tab spell")
end)

step("a skill bonus shows next to the skill", function ()
	-- +15 Tailoring from equipment: the Skills tab's modifier.
	skillLines[2][5] = 15
	fire("SKILL_LINES_CHANGED")
	tick(0.5)
	assert(M.baseRank == 120 and M.bonus == 15 and M.rank == 135,
		"rank: " .. tostring(M.baseRank) .. " + " .. tostring(M.bonus) .. " = " .. tostring(M.rank))
	assert(RPF.SkillRankText(120, 15, 150) == "120 (|cff20ff20+15|r)/150", RPF.SkillRankText(120, 15, 150))
	if not DRAGON then assert(textShown("^Tailoring 120 %(.*%+15.*%)/150$"), "skill bar doesn't show the bonus") end
	skillLines[2][5] = nil
	fire("SKILL_LINES_CHANGED")
	tick(0.5)
	assert(M.bonus == 0 and M.rank == 120, "bonus didn't go")
	if not DRAGON then assert(textShown("^Tailoring 120/150$"), "skill bar still shows a bonus") end
end)

step("a racial bonus comes out of the rank and the max", function ()
	-- A +15 racial is in the Skills tab's rank and max (135/165); equipment adds 15 more.
	skillLines[2][3], skillLines[2][4], skillLines[2][5] = 135, 165, 15
	tradeSkillLine[2], tradeSkillLine[3] = 135, 165
	fire("TRADE_SKILL_UPDATE")
	fire("SKILL_LINES_CHANGED")
	tick(0.5)
	assert(M.baseRank == 120 and M.bonus == 30 and M.rank == 150 and M.maxRank == 150,
		"rank: " .. tostring(M.baseRank) .. " + " .. tostring(M.bonus) .. " = " .. tostring(M.rank) .. " / " .. tostring(M.maxRank))
	for _, k in ipairs(RPF.KnownProfessions()) do
		if k.profession == M.profession then
			assert(k.baseRank == 120 and k.rank == 150 and k.maxRank == 150, "known: " .. k.baseRank .. "/" .. k.maxRank)
		end
	end
	if not DRAGON then assert(textShown("^Tailoring 120 %(.*%+30.*%)/150$"), "skill bar doesn't show the racial") end
	skillLines[2][3], skillLines[2][4], skillLines[2][5] = 120, 150, nil
	tradeSkillLine[2], tradeSkillLine[3] = 120, 150
	fire("TRADE_SKILL_UPDATE")
	fire("SKILL_LINES_CHANGED")
	tick(0.5)
	assert(M.bonus == 0 and M.maxRank == 150, "racial didn't go")
end)

if DRAGON == "2" then
	step("DragonUI's professions art: skill bar, card drawing, list bars", function ()
		assert(RetailProfessionsFrame.profArt, "the window didn't take DragonUI's professions art")
		local bar = find(function (f) return rawget(f, "fx") and rawget(f, "SetRank") end)
		assert(bar and bar.fx.key == "Tailoring", "skill bar fill: " .. tostring(bar and bar.fx.key))
		assert(bar.fx.ratio == M.rank / M.maxRank and not bar.fx.isFull, "skill bar ratio: " .. tostring(bar.fx.ratio))
		assert(bar.rank.full == "Tailoring " .. M.rank .. "/" .. M.maxRank, "rank text: " .. tostring(bar.rank.full))
		local drawing = find(function (f) return rawget(f, "__art") == "carddraw-Tailoring" end)
		assert(drawing and drawing:IsVisible(), "the card's drawing isn't shown")
		local header = find(function (f)
			return f.__kind == "Button" and rawget(f, "headerArt") and f:IsVisible() and f.row and f.row.header
		end)
		assert(header and header.headerArt[1].__shown and header.toggle.__shown, "no category bar in DragonUI's art")
		local recipe = find(function (f)
			return f.__kind == "Button" and rawget(f, "headerArt") and f:IsVisible() and f.row and f.row.recipe
		end)
		assert(recipe and not recipe.headerArt[1].__shown, "a recipe row shows the category bar")
		assert(find(function (f) return rawget(f, "__forever") end), "the search box isn't DragonUI's")
	end)
end

step("the list is cached for the next visit", function ()
	local key
	for k in pairs(RetailProfessionsDB.lists) do key = k end
	assert(key and key:find("^777:197:"), "list not saved: " .. tostring(key))
end)

step("search finds reagents too", function ()
	RPF.filter.text = "coarse"
	RPF.Rebuild(true)
	local names = {}
	for _, row in ipairs(RPF.list.rows) do if row.recipe then table.insert(names, row.recipe.name) end end
	assert(#names == 1 and names[1] == "Brown Linen Vest", "search by reagent: " .. table.concat(names, ", "))
	RPF.filter.text = ""
end)

step("search lists name matches before reagent matches", function ()
	-- Two groups, the first holding only a recipe made from the bolt: the bolt itself and its
	-- group come first.
	local saved = M.headers
	local bolt, vest = M.bySpell[2963], M.bySpell[2385]
	local robe = { name = "Linen Robe", spell = 1, reagents = { { id = 2996, n = 2, name = "Bolt of Linen Cloth" } } }
	M.headers = {
		{ name = "Cloth", recipes = { robe, vest } },
		{ name = "Materials", recipes = { bolt } },
	}
	local rows = M.Rows({ text = "bolt of linen" }, {})
	M.headers = saved
	local seen = {}
	for _, row in ipairs(rows) do table.insert(seen, row.header or row.recipe.name) end
	assert(table.concat(seen, ", ") == "Materials, Bolt of Linen Cloth, Cloth, Linen Robe",
		"search order: " .. table.concat(seen, ", "))

	-- Inside one group too; without a search the client's order stands.
	M.headers = { { name = "Cloth", recipes = { robe, bolt } } }
	rows = M.Rows({ text = "linen cloth" }, {})
	M.headers = saved
	assert(rows[2].recipe == bolt and rows[3].recipe == robe, "name match not first in its group")
	rows = M.Rows({}, {})
	assert(rows[1].header == "Cloth", "unsearched order changed")
end)

step("have materials counts the reagent bank", function ()
	RPF.filter.haveMats = true
	RPF.Rebuild(true)
	local names = {}
	for _, row in ipairs(RPF.list.rows) do if row.recipe then names[row.recipe.name] = true end end
	assert(names["Bolt of Linen Cloth"] and not names["Brown Linen Vest"], "have-materials filter wrong")
	local bagsOnly, withBank = M.Craftable(M.bySpell[2963])
	assert(bagsOnly == 2 and withBank == 17, "craftable: " .. bagsOnly .. "/" .. withBank)
	RPF.filter.haveMats = false
	RPF.Rebuild(true)
end)

step("slot filter", function ()
	RPF.filter.slot = "INVTYPE_CHEST"
	RPF.Rebuild(true)
	local count = 0
	for _, row in ipairs(RPF.list.rows) do if row.recipe then count = count + 1 end end
	assert(count == 1, "slot filter rows: " .. count)
	RPF.filter.slot = nil
	RPF.Rebuild(true)
	EasyMenu(nil) -- reset
	RetailProfessionsFilterMenu = RetailProfessionsFilterMenu
end)

step("create and create all", function ()
	RetailProfessionsDB.autoWithdraw = false
	RPF.Select(M.bySpell[2963])
	buttonWithText("Create").__scripts.OnClick()
	assert(crafted[#crafted][1] == 2 and crafted[#crafted][2] == 1, "Create did the wrong thing")
	local all = find(function (f) return f.__kind == "Button" and f.__text:find("^Create All") end)
	all.__scripts.OnClick()
	assert(crafted[#crafted][2] == 2, "Create All count: " .. tostring(crafted[#crafted][2]))
	local name, list = provider.GetRecipe()
	assert(name == "Bolt of Linen Cloth" and list[1].itemEntry == 2589 and list[1].requiredPerCraft == 2, "provider recipe")
end)

-- The stock window's Have Materials (Blizzard re-applies its hidden checkbox on every open, and
-- DragonUI's filter clicks it) narrows the client's list after our scan, and the client says so
-- with TRADE_SKILL_FILTER_UPDATE only. The Vest's old index then reads no row at all.
step("another window's filter doesn't empty a recipe's reagents", function ()
	local full
	function TradeSkillOnlyShowMakeable(on)
		if on and not full then
			full = {}
			for i, t in ipairs(tradeSkill) do full[i] = t end
			for i = #tradeSkill, 1, -1 do
				if tradeSkill[i][2] ~= "header" and (tradeSkill[i][3] or 0) == 0 then table.remove(tradeSkill, i) end
			end
			fire("TRADE_SKILL_FILTER_UPDATE")
		elseif not on and full then
			for i = 1, math.max(#full, #tradeSkill) do tradeSkill[i] = full[i] end
			full = nil
			fire("TRADE_SKILL_FILTER_UPDATE")
		end
	end
	local vest = M.bySpell[2385]
	assert(#vest.reagents == 2, "the vest's reagents before: " .. #vest.reagents)

	-- The filter event alone puts the whole list back.
	TradeSkillOnlyShowMakeable(true)
	tick(1.5)
	assert(GetNumTradeSkills() == 3 and #M.recipes == 2, "after the filter event: client " .. GetNumTradeSkills()
		.. " rows, model " .. #M.recipes .. " recipes")

	-- Selected before that event is handled: the old index reads no row.
	vest = M.bySpell[2385]
	TradeSkillOnlyShowMakeable(true)
	RPF.Select(vest)
	assert(#vest.reagents == 2, "selecting the vest emptied its reagents: " .. #vest.reagents)
	assert(not textShown("No reagents"), "the recipe pane says No reagents")
	tick(0.5)
	assert(GetNumTradeSkills() == 3, "the client's list stayed filtered: " .. GetNumTradeSkills())
	vest = M.bySpell[2385]
	RPF.Select(vest)
	assert(vest.index == 3 and #vest.reagents == 2, "the vest after the rescan: index " .. tostring(vest.index)
		.. ", reagents " .. #vest.reagents)

	-- The trade skill gone under the window (closed, or another one's list): nothing to read, and
	-- the recipe keeps what it had.
	local saved = {}
	for i, t in ipairs(tradeSkill) do saved[i] = t; tradeSkill[i] = nil end
	RPF.Select(M.bySpell[2963])
	local bolt = M.bySpell[2963]
	assert(#bolt.reagents == 1 and bolt.reagents[1].id == 2589, "the bolt lost its reagents with no list behind it")
	for i, t in ipairs(saved) do tradeSkill[i] = t end
	tick(0.5)
	function TradeSkillOnlyShowMakeable() end
end)

step("the amount counts down as the crafts finish", function ()
	RPF.Select(M.bySpell[2963])
	local create = buttonWithText("Create")
	local function bolt(event) fire(event or "UNIT_SPELLCAST_SUCCEEDED", "player", "Bolt of Linen Cloth") end
	RPF.SetQuantity(3)
	create.__scripts.OnClick()
	assert(crafted[#crafted][2] == 3, "Create count: " .. tostring(crafted[#crafted][2]))
	bolt()
	assert(RPF.GetQuantity() == 2, "after one craft: " .. RPF.GetQuantity())
	-- Someone else's cast and another spell don't count.
	fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "Bolt of Linen Cloth")
	fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Fireball")
	assert(RPF.GetQuantity() == 2, "counted a cast that wasn't ours: " .. RPF.GetQuantity())
	-- Interrupted: the amount is what's left, and Create makes only that.
	bolt("UNIT_SPELLCAST_INTERRUPTED")
	bolt()
	assert(RPF.GetQuantity() == 2, "counted after the interrupt: " .. RPF.GetQuantity())
	create.__scripts.OnClick()
	assert(crafted[#crafted][2] == 2, "Create after the interrupt: " .. tostring(crafted[#crafted][2]))
	bolt(); bolt()
	assert(RPF.GetQuantity() == 1, "after the last craft: " .. RPF.GetQuantity())
	-- Create again mid-batch: the game refuses it under the same name while the batch goes on.
	RPF.SetQuantity(4)
	create.__scripts.OnClick()
	bolt()
	UnitCastingInfo = function () return "Bolt of Linen Cloth" end
	create.__scripts.OnClick()
	bolt("UNIT_SPELLCAST_FAILED")
	UnitCastingInfo = function () return nil end
	bolt()
	assert(RPF.GetQuantity() == 2, "a refused second Create stopped the count: " .. RPF.GetQuantity())
	-- Another recipe picked mid-batch keeps its amount; back on this one, what's left.
	local other = M.bySpell[2385]
	assert(other and other.learned, "no second learned recipe")
	RPF.Select(other)
	bolt()
	assert(RPF.GetQuantity() == 2, "counted down on another recipe: " .. RPF.GetQuantity())
	bolt()
	RPF.Select(M.bySpell[2963])
	assert(RPF.GetQuantity() == 1, "back on the recipe: " .. RPF.GetQuantity())
	-- A cast that never starts (fails inside DoTradeSkill) leaves nothing to count.
	RPF.SetQuantity(3)
	local realDo = DoTradeSkill
	DoTradeSkill = function (i, n) realDo(i, n); bolt("UNIT_SPELLCAST_FAILED") end
	create.__scripts.OnClick()
	DoTradeSkill = realDo
	bolt()
	assert(RPF.GetQuantity() == 3, "counted a cast after a failed start: " .. RPF.GetQuantity())
	-- An amount typed while crafting is the player's: it isn't counted down.
	RPF.SetQuantity(4)
	create.__scripts.OnClick()
	RPF.SetQuantity(9)
	bolt()
	assert(RPF.GetQuantity() == 9, "typed amount changed: " .. RPF.GetQuantity())
	bolt("UNIT_SPELLCAST_INTERRUPTED")
	RPF.SetQuantity(1)
end)

step("unlearned recipe: where to learn, map pin", function ()
	RPF.Select(M.bySpell[3914])
	tick(0.5)
	assert(textShown("Rann Flamespinner"), "vendor source not shown")
	assert(textShown("World drop"), "world drop not shown")
	assert(textShown("Friendly with Stormwind"), "reputation not shown")
	local map = find(function (f) return f.__kind == "Button" and f.__text == "Map" and f:IsVisible() end)
	map.__scripts.OnClick(map)
	tick(0.5)
	assert(textShown("Elwynn Forest %(44, 65%)"), "map answer not shown")
	assert(textShown("Not learned %- needs 130"), "skill requirement not shown")
end)

step("sources read like a guide: notes on the line, details on hover, the rest folded", function ()
	assert(textShown("Taught by|r  Henry Stern"), "scripted teacher not shown")
	assert(textShown("World drop|r from trash in Ulduar"), "raid trash world drop not named")
	assert(textShown("%(daily%)"), "quest note not shown")
	assert(textShown("And %d+ more sources"), "overflow line not shown")
	local function rowWith(pattern)
		return find(function (f)
			return f.__kind == "Button" and rawget(f, "text") and f.text.__text:find(pattern) and f:IsVisible()
		end)
	end
	local quest = rowWith("Dig Rat Stew")
	assert(quest, "quest row not shown")
	quest.__scripts.OnEnter(quest)
	local text = table.concat(tipLines, "\n")
	assert(text:find("Quest giver: Grub"), "quest details not in the tooltip: " .. text)
	assert(quest.map:IsShown(), "no map pin for a quest giver")
	local more = rowWith("And %d+ more sources")
	more.__scripts.OnEnter(more)
	text = table.concat(tipLines, "\n")
	assert(text:find("Small Spice Bag") and text:find("Outland, once it opens"), "folded sources not listed: " .. text)
	assert(text:find("3 Dalaran Cooking Award") or rowWith("Token Seller"), "token price lost")
	assert(not more.map:IsShown(), "map pin on the folded line")
end)

step("where-to-learn is asked once, however often the recipe redraws", function ()
	local before = 0
	for _, m in ipairs(sent) do if m:match("^W:") then before = before + 1 end end
	for _ = 1, 3 do fire("BAG_UPDATE"); tick(0.5) end
	RPF.Select(M.bySpell[3914])
	tick(0.5)
	local after = 0
	for _, m in ipairs(sent) do if m:match("^W:") then after = after + 1 end end
	assert(before == 1 and after == 1, "W sent " .. before .. " then " .. after .. " times")
end)

step("favorites go to the top", function ()
	RPF.ToggleFavorite(2385)
	tick(0.2)
	local first = RPF.list.rows[1]
	assert(first.header == "Favorites" and RPF.list.rows[2].recipe.spell == 2385, "favorites group missing")
	RPF.ToggleFavorite(2385)
	tick(0.2)
	assert(RPF.list.rows[1].header ~= "Favorites", "favorites group stayed")
end)

step("skill-up odds live in the tooltip", function ()
	local vest = M.bySpell[2385]
	RPF.AddSkillUpLines(GameTooltip, vest)
	local text = table.concat(tipLines, "\n")
	-- Skill 120 is past the vest's grey (70).
	assert(text:find("No more skill%-ups"), "no skill-up line: " .. text)
	assert(text:find("yellow 45") and text:find("grey 70"), "no thresholds: " .. text)
end)

step("hovering a recipe compares with equipped gear only while Shift is held", function ()
	local row = find(function (f)
		return f.__kind == "Button" and rawget(f, "row") and rawget(f, "row").recipe and rawget(f, "row").recipe.item
	end)
	assert(row, "no recipe row")
	local before = compared
	row.__scripts.OnEnter(row)
	assert(compared == before, "compared without Shift")
	-- Pressing Shift while hovering compares right away.
	local isModified, isOwned, isShown = IsModifiedClick, GameTooltip.IsOwned, GameTooltip.IsShown
	IsModifiedClick = function () return true end
	GameTooltip.IsOwned = function (tip, owner) return owner == row end
	GameTooltip.IsShown = function () return true end
	fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
	assert(compared == before + 1, "no comparison when Shift went down")
	row.__scripts.OnEnter(row)
	assert(compared == before + 2, "no comparison on hover with Shift held")
	IsModifiedClick, GameTooltip.IsOwned, GameTooltip.IsShown = isModified, isOwned, isShown
	-- Once the mouse has left, Shift does nothing.
	row.__scripts.OnLeave(row)
	IsModifiedClick = function () return true end
	fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
	IsModifiedClick = isModified
	assert(compared == before + 2, "compared with nothing hovered")
	-- Worn gear the client hasn't cached: no compare (the 3.3.5 client crashes) until it arrives.
	worn[16] = 99999
	IsModifiedClick = function () return true end
	GameTooltip.IsOwned = function (tip, owner) return owner == row end
	GameTooltip.IsShown = function () return true end
	row.__scripts.OnEnter(row)
	assert(compared == before + 2, "compared against worn gear the client hasn't cached")
	items[99999] = { "Worn Blade", 2, "INVTYPE_WEAPON" }
	tick(0.5)
	assert(compared == before + 3, "no compare once the worn gear was cached")
	IsModifiedClick, GameTooltip.IsOwned, GameTooltip.IsShown = isModified, isOwned, isShown
	row.__scripts.OnLeave(row)
	worn[16], items[99999] = nil, nil
end)

step("use reagent bank: withdraw, then craft when it arrives", function ()
	RetailProfessionsDB.autoWithdraw = true
	RPF.Select(M.bySpell[2963])
	RPF.SetQuantity(5)
	local before = #crafted
	buttonWithText("Create").__scripts.OnClick()
	assert(withdrawn and withdrawn.count == 5 and withdrawn.name == "Bolt of Linen Cloth", "no withdraw for 5")
	assert(#crafted == before, "crafted before the reagents arrived")
	bags[2589] = 10
	fire("BAG_UPDATE")
	tick(0.5)
	assert(#crafted == before + 1 and crafted[#crafted][2] == 5, "didn't craft 5 after the withdraw")
	local all = find(function (f) return f.__kind == "Button" and f.__text:find("^Create All") end)
	assert(all.__text == "Create All [20]", "Create All doesn't count the bank: " .. all.__text)
	bags[2589] = 4
end)

step("track a recipe", function ()
	RPF.ToggleTracked(M.bySpell[2385])
	assert(RetailProfessionsTracker:IsShown(), "tracker hidden")
	assert(textShown("Brown Linen Vest"), "tracked recipe missing")
	assert(textShown("Coarse Thread"), "tracked reagent missing")
	bags[2320] = 1
	fire("BAG_UPDATE")
	tick(0.5)
end)

step("professions book", function ()
	RPF.ToggleBook()
	assert(RetailProfessionsBook:IsShown(), "book hidden")
	assert(textShown("120 / 150"), "tailoring row missing")
	assert(textShown("Secondary Skills"), "secondary section missing")
	assert(buttonWithText("Find Minerals"), "mining's action missing")
end)

step("combat hides the secure buttons first, then they come back", function ()
	fire("PLAYER_REGEN_DISABLED")
	combat = true
	assert(not RetailProfessionsTab1.__shown, "tab button still shown in combat")
	RPF.ToggleBook()
	RPF.ToggleBook()
	combat = false
	fire("PLAYER_REGEN_ENABLED")
	assert(RetailProfessionsTab1.__shown, "tab button not back after combat")
end)

step("archaeology: ArchaeologyUI's skill is a book row and a Training row that open its window", function ()
	local toggled, surveyed = 0, 0
	ArchaeologyUI = { skill = 60, maxSkill = 75,
		OpenWindow = function () toggled = toggled + 1 end, ToggleWindow = function () error("toggled the research window") end,
		SurveyButtonClick = function () surveyed = surveyed + 1 end }
	RPF.Fire("SKILLS")
	tick(0.5)
	if not RetailProfessionsBook:IsShown() then RPF.ToggleBook() end
	assert(textShown("^Archaeology$") and textShown("60 / 75"), "no Archaeology row in the book")
	local surveyButton = buttonWithText("Survey")
	assert(surveyButton and surveyButton:IsVisible(), "no Survey button")
	surveyButton.__scripts.OnClick(surveyButton)
	assert(surveyed == 1, "Survey didn't survey")
	local open = surveyButton:GetParent().open
	assert(open:IsVisible() and open.__scripts.OnClick, "Archaeology's Open doesn't take the click")
	open.__scripts.OnClick(open)
	assert(toggled == 1 and not RetailProfessionsBook:IsShown(), "Open didn't open the research window")
	assert(not surveyButton:GetParent().unlearn:IsShown(), "Archaeology can be unlearned from the book")

	RPF.Home.SetActive(true)
	tick(0.3)
	local row
	for _, r in ipairs(RPF.Home.rows.profs) do
		if r.known and r.known.profession.id == 794 then row = r end
	end
	assert(row and row:IsShown() and row.rank.__text == "60/75", "no Archaeology row on Training")
	assert(not row.button.__shown, "the Archaeology row casts something")
	row.__scripts.OnClick(row)
	assert(toggled == 2, "the Training row didn't open the research window")
	RPF.Home.SetActive(false)

	-- With the client patch it is a skill line too: one row, still not unlearnable.
	table.insert(skillLines, { "Archaeology", false, 60, 75 })
	RPF.Fire("SKILLS")
	local rows = 0
	for _, k in ipairs(RPF.KnownProfessions()) do
		if k.profession.id == 794 then
			rows = rows + 1
			assert(not k.abandonable, "the Archaeology skill line can be unlearned")
		end
	end
	assert(rows == 1, "Archaeology listed " .. rows .. " times")
	table.remove(skillLines)

	ArchaeologyUI = nil
	RPF.Fire("SKILLS")
	tick(0.5)
	RPF.ToggleBook()
	assert(not textShown("^Archaeology$"), "Archaeology stays without ArchaeologyUI")
	RPF.ToggleBook()
end)

step("an older ReagentBankUI's sidebar stays away: the window has its controls", function ()
	ReagentBankUI:DockTradeSkillPanel()
	assert(not bankPanel:IsShown(), "an older ReagentBankUI's sidebar wasn't hidden")
end)

step("deposit leftovers is ReagentBankUI's setting", function ()
	RetailProfessionsDB.autoWithdraw = true
	RPF.Select(M.bySpell[2963])
	local check = find(function (f) return f.__kind == "FontString" and f.__text == "Deposit leftovers" end):GetParent()
	assert(check:IsVisible() and check:IsEnabled() and not check:GetChecked(), "leftovers check not offered, or ticked")
	check:SetChecked(true)
	check.__scripts.OnClick(check)
	assert(ReagentBankUI.leftovers == true, "the tick didn't reach ReagentBankUI")
	-- Nothing comes out of the bank without Use reagent bank, so there are no leftovers either.
	RetailProfessionsDB.autoWithdraw = false
	RPF.UpdateControls()
	assert(check:GetChecked() and not check:IsEnabled(), "leftovers check not greyed without Use reagent bank")
	RetailProfessionsDB.autoWithdraw = true
	ReagentBankUI.leftovers = false
	RPF.UpdateControls()
end)

step("what the amount is short of goes on the shopping list, once", function ()
	-- Bolt of Linen Cloth: 2 Linen Cloth each; 4 in the bags, 30 in the bank.
	RPF.Select(M.bySpell[2963])
	RPF.SetQuantity(17)
	local add = buttonWithText("Add to Shopping List")
	assert(not add:IsVisible(), "shopping row shown with nothing short")
	RPF.SetQuantity(20)
	assert(add:IsVisible() and add:IsEnabled(), "shopping row not shown for 20")
	assert(textShown("Short for 20|r"), "wrong shortfall")
	-- Lowest buyout 10c each.
	assert(textShown("about|r 60|TInterface"), "no price on the shortfall")
	-- Not while the bank's counts are unknown: all 30 in it would look missing.
	ReagentBankUI.snapshot = false
	add.__scripts.OnClick(add)
	assert(not ReagentBankUI.shopping[2589], "added without knowing what the bank holds")
	ReagentBankUI:HandleBankSnapshotResponse()
	add.__scripts.OnClick(add)
	assert(ReagentBankUI.shopping[2589] == 6, "not on the list: " .. tostring(ReagentBankUI.shopping[2589]))
	assert(textShown("6 on the list"), "row doesn't show it's on the list")
	-- Asking again adds nothing; a bigger amount adds the difference; Shift adds it all on top.
	add.__scripts.OnClick(add)
	assert(ReagentBankUI.shopping[2589] == 6, "a second click doubled it")
	RPF.SetQuantity(21)
	assert(textShown("Short for 21|r"), "row didn't follow the amount")
	add.__scripts.OnClick(add)
	assert(ReagentBankUI.shopping[2589] == 8, "the difference wasn't added: " .. tostring(ReagentBankUI.shopping[2589]))
	IsShiftKeyDown = function () return true end
	add.__scripts.OnClick(add)
	IsShiftKeyDown = function () return false end
	assert(ReagentBankUI.shopping[2589] == 16, "Shift didn't add on top: " .. tostring(ReagentBankUI.shopping[2589]))
	ReagentBankUI.shopping = {}
	RPF.SetQuantity(1)
end)

step("unlearned recipe: its materials go on the shopping list too", function ()
	-- Green Linen Bracers, not learned: 2 Bolt of Linen Cloth and 1 Fine Thread each.
	RPF.Select(M.bySpell[3914])
	assert(not M.bySpell[3914].learned, "the bracers are learned")
	RPF.SetQuantity(3)
	assert(RPF.GetQuantity() == 3, "no amount on an unlearned recipe")
	local add = buttonWithText("Add to Shopping List")
	assert(add:IsVisible() and add:IsEnabled(), "no shopping row on an unlearned recipe")
	assert(textShown("Short for 3|r"), "wrong shortfall")
	add.__scripts.OnClick(add)
	assert(ReagentBankUI.shopping[2321] == 3, "thread: " .. tostring(ReagentBankUI.shopping[2321]))
	assert(ReagentBankUI.shopping[2996] == 6, "bolts: " .. tostring(ReagentBankUI.shopping[2996]))
	ReagentBankUI.shopping = {}
	RPF.SetQuantity(1)
end)

step("shift-click Enchant answers the replace-enchant question", function ()
	RetailProfessionsDB.autoWithdraw = false
	local r = M.bySpell[2963]
	RPF.Select(r)
	r.isEnchant = true
	local replaced, hidden, shown = 0, 0, 0
	function ReplaceEnchant() replaced = replaced + 1 end
	function BindEnchant() end
	local oldHide, oldShow = StaticPopup_Hide, StaticPopup_Show
	StaticPopup_Hide = function () hidden = hidden + 1 end
	StaticPopup_Show = function (...) shown = shown + 1 return oldShow(...) end
	local oldLink, oldTargeting, oldShift = GetContainerItemLink, SpellIsTargeting, IsShiftKeyDown
	GetContainerItemLink = function (bag, slot) if bag == 0 and slot == 1 then return itemLink(2589) end end
	SpellIsTargeting = function () return true end
	RPF.enchantTarget = { id = 2589, bag = 0, slot = 1 }

	-- A plain click leaves the question to the player.
	buttonWithText("Create").__scripts.OnClick()
	fire("REPLACE_ENCHANT", "Old", "New")
	assert(replaced == 0, "answered without Shift")

	IsShiftKeyDown = function () return true end
	buttonWithText("Create").__scripts.OnClick()
	fire("REPLACE_ENCHANT", "Old", "New")
	assert(replaced == 1 and hidden >= 1, "Shift-click didn't answer it")
	UnitCastingInfo = function () return "Enchant" end
	tick(1)
	assert(shown == 0, "popup came back although the cast started")

	r.isEnchant = false
	RPF.enchantTarget = nil
	GetContainerItemLink, SpellIsTargeting, IsShiftKeyDown = oldLink, oldTargeting, oldShift
	StaticPopup_Hide, StaticPopup_Show = oldHide, oldShow
	UnitCastingInfo = function () return nil end
end)

step("the amount follows ReagentBankUI's Crafts box both ways", function ()
	RPF.SetQuantity(7)
	assert(ReagentBankUI.prepareCount == 7, "our amount didn't reach ReagentBankUI")
	provider.SetRepeatCount(3)
	assert(RPF.GetQuantity() == 3, "ReagentBankUI's count didn't reach us")
	assert(ReagentBankUI.prepareCount == 7 or ReagentBankUI.prepareCount == 3, "loop")
end)

step("craft for profit: ranked by auction prices", function ()
	local thread = bags[2320]
	bags[2320] = nil
	RetailProfessionsDB.profitView = true
	RPF.Rebuild(true)
	tick(0.5)
	assert(#rahSent >= 1 and rahSent[#rahSent]:find("^K:p%d+:"), "no price request")
	assert(RPF.Profit.state == "ok", "prices not taken: " .. RPF.Profit.state)
	local rows = RPF.list.rows
	-- Bolt: sells 60 -5% = 57, x1.25 for 25% Multicraft = 71; the two linen are in the bags, so
	-- they count at what selling them brings (10 -5% = 9 each) = 18, less 1 Resourcefulness: +54c.
	-- The bags make 2.
	assert(rows[1].header == "Craft now" and rows[2].recipe.spell == 2963, "craft-now group: " .. tostring(rows[1].header))
	assert(money(rows[2].right) == "54c", "bolt profit: " .. money(rows[2].right))
	-- Vest: 300 -5% = 285, three linen from the bags 27 + coarse thread from a vendor 10 = 37, less 2
	-- Resourcefulness = 35; no thread in the bags.
	assert(rows[3].header == "Buy materials and craft" and rows[4].recipe.spell == 2385, "buy group: " .. tostring(rows[3].header))
	assert(money(rows[4].right) == "2s 50c", "vest profit: " .. money(rows[4].right))
	RPF.Select(M.bySpell[2385])
	tick(0.2)
	assert(textShown("Sells for"), "price block missing")
	-- The market line is in the Sells for tooltip now, keeping the line short.
	assert(RPF.Profit.MarketText(2568) == "3 listed, 5 sold in 14 days", "market line missing")
	-- The Profit line's tooltip shows the sum behind it.
	local tipLines = {}
	local tip = {
		AddLine = function (_, text) table.insert(tipLines, text) end,
		AddDoubleLine = function (_, left, right) table.insert(tipLines, left .. " = " .. right) end,
	}
	RPF.Profit.AddProfitLines(tip, M.bySpell[2385], RPF.Profit.Of(M.bySpell[2385]), function () return "fish" end)
	local tipText = table.concat(tipLines, "\n")
	assert(tipText:find("Profit per craft", 1, true) and tipText:find("5% auction cut", 1, true)
		and tipText:find("Resourcefulness 20%", 1, true), "profit tooltip: " .. tipText)
	assert(textShown("Profit"), "profit line missing")
	local a = RPF.Profit.Of(M.bySpell[2385])
	assert(a.parts[2].how == "vendor" and a.cost == 35, "thread should come from the vendor")
	-- A reagent you can craft yourself counts at the cheaper of buying it (bolts at 60) and crafting
	-- it from what's in the bags (two linen worth 18, making 1.25 bolts).
	local robe = RPF.Profit.Of({ name = "Robe", item = 2568, reagents = { { id = 2996, n = 1 } } })
	assert(robe.parts[1].buyHow == "made" and robe.parts[1].cost < 60, "the bolt wasn't priced as crafted: "
		.. tostring(robe.parts[1].buyHow) .. " " .. tostring(robe.parts[1].cost))
	-- The unlearned bracers bind on pickup: worth their vendor price only.
	RPF.Profit.Fetch({ 4308 })
	tick(0.2)
	local value, how = RPF.Profit.SellValue(4308)
	assert(value == 50 and how == "vendor", "soulbound item valued at " .. tostring(value) .. " " .. tostring(how))
	-- Fresh prices aren't asked for again on every redraw.
	local before = #rahSent
	for _ = 1, 3 do fire("BAG_UPDATE"); tick(0.5) end
	assert(#rahSent == before, "prices asked again: " .. (#rahSent - before))
	-- With a thread in the bags the vest moves up to Craft now, ahead of the bolt.
	bags[2320] = 1
	fire("BAG_UPDATE")
	tick(0.5)
	assert(RPF.list.rows[2].recipe.spell == 2385 and RPF.list.rows[3].recipe.spell == 2963, "vest not in Craft now")
	bags[2320] = thread
end)

step("craft for profit without mod-retail-ah", function ()
	rahDown = true
	-- As on first contact: a realm that answered once isn't given up on for one lost request.
	RPF.Profit.state = "unknown"
	RPF.Profit.Fetch(RPF.Profit.ProfessionEntries(), true)
	tick(7)
	assert(RPF.Profit.state == "missing", "no-server state: " .. RPF.Profit.state)
	RPF.Rebuild(true)
	tick(0.2)
	assert(textShown("needs mod%-retail%-ah"), "no-server note missing")
	rahDown = false
	RetailProfessionsDB.profitView = nil
	RPF.Rebuild(true)
end)

step("the search box doesn't keep the keyboard", function ()
	local search = find(function (f) return f.__kind == "EditBox" and rawget(f, "hint") end)
	local cleared = 0
	search.ClearFocus = function () cleared = cleared + 1 end
	RetailProfessionsFrame.__scripts.OnShow(RetailProfessionsFrame)
	assert(cleared >= 1, "opening the window left the search focused")
	local before = cleared
	local row
	for _, f in ipairs(allFrames) do
		if f.__kind == "Button" and rawget(f, "row") and f.row.recipe then row = f break end
	end
	row.__scripts.OnClick(row, "LeftButton")
	assert(cleared > before, "clicking a recipe left the search focused")
end)

step("a recipe that makes no item isn't an enchant outside Enchanting", function ()
	assert(RPF.RecipeList(197)[2963].targetsItem == false, "server's item-target flag not read")
	-- Like Minor Inscription Research: no item to make, cast on nothing.
	local old = GetTradeSkillItemLink
	GetTradeSkillItemLink = function (i) if i == 2 then return "|cffffd000|Henchant:2963|h[Bolt]|h|r" end return old(i) end
	RPF.ForgetRecipeLists()
	RPF.Rebuild()
	tick(0.2)
	local r = M.bySpell[2963]
	assert(not r.isEnchant, "a no-item Tailoring recipe was taken for an enchant")
	RPF.Select(r)
	local all = find(function (f) return f.__kind == "Button" and f.__text:find("^Create All") end)
	assert(not all.__text:find("%[0%]"), "Create All still says 0: " .. all.__text)
	GetTradeSkillItemLink = old
	RPF.Rebuild()
end)

step("enchants filter by the slot they go on", function ()
	local info = RPF.RecipeList(197)[2963]
	local oldInfo, oldLink = GetTradeSkillInfo, GetTradeSkillItemLink
	GetTradeSkillInfo = function (i)
		if i == 2 then return "Enchant Bracer - Minor Health", "optimal", 2 end
		return oldInfo(i)
	end
	GetTradeSkillItemLink = function (i) if i == 2 then return nil end return oldLink(i) end
	info.targetsItem = true
	-- A server that doesn't name the slot: the enchant's name does.
	RPF.Rebuild()
	assert(M.bySpell[2963].slot == "INVTYPE_WRIST", "slot from the name: " .. tostring(M.bySpell[2963].slot))
	-- The server's word wins: this one goes on any weapon.
	info.invType = 29
	RPF.Rebuild()
	local slot = M.bySpell[2963].slot
	assert(M.SlotName(slot) == "Weapon", "any-weapon slot: " .. tostring(slot))
	local present = false
	for _, s in ipairs(M.SlotsPresent()) do if s == slot then present = true end end
	assert(present, "the filter menu doesn't offer the weapon slot")
	RPF.filter.slot = slot
	RPF.Rebuild(true)
	local count = 0
	for _, row in ipairs(RPF.list.rows) do if row.recipe then count = count + 1 end end
	assert(count == 1, "enchant slot filter rows: " .. count)
	RPF.filter.slot = nil
	info.targetsItem, info.invType = false, 0
	GetTradeSkillInfo, GetTradeSkillItemLink = oldInfo, oldLink
	RPF.Rebuild()
end)

-----------------------------------------
-- Training and Profit: what to do next and the most profitable crafts, across every profession

local function homeTexts()
	local out = {}
	for _, row in ipairs(RPF.Home.rows.todo) do
		if row.item then table.insert(out, row.item.text) end
	end
	return out
end
local function homeHas(pattern)
	for _, t in ipairs(homeTexts()) do if t:find(pattern) then return t end end
	return nil
end

local function viewTab(name)
	return find(function (f) return f.__kind == "Button" and rawget(f, "button") == _G["RetailProfessions" .. name .. "Tab"] end)
end

step("home: the Training and Profit tabs, the professions and the most profitable crafts", function ()
	local tab, profitTab = viewTab("Training"), viewTab("Profit")
	assert(tab and tab:IsShown(), "no Training tab")
	assert(profitTab and profitTab:IsShown(), "no Profit tab")
	-- A cooldown seen on this visit is remembered; the scan before the tab is clicked takes it.
	local oldCooldown = GetTradeSkillCooldown
	GetTradeSkillCooldown = function (i) if i == 2 then return 3600 end return nil end
	RPF.Rebuild()
	tick(0.5)
	GetTradeSkillCooldown = oldCooldown
	local cd = RetailProfessionsCharDB.homeCooldowns[2963]
	assert(cd and cd.skill == 197, "the bolt's cooldown wasn't noted")
	assert(RetailProfessionsCharDB.homeLearned[197][2385], "Tailoring's recipes weren't noted")

	tab.__scripts.OnClick(tab)
	tick(0.3)
	local panels = RPF.Home.panels
	assert(RPF.Home.Active() == "training" and panels.training:IsShown(), "Training isn't showing")
	assert(not panels.profit:IsShown(), "Profit shows under Training")
	assert(not RPF.list:IsVisible(), "the recipe list still shows under Training")
	assert(RetailProfessionsFrame.title.__text == "Training", "title: " .. RetailProfessionsFrame.title.__text)
	assert(tab.checked:IsShown() and not profitTab.checked:IsShown(), "the Training tab isn't the lit one")
	assert(not RetailProfessionsTab1.__shown, "the open profession's tab still casts")

	-- Professions: Tailoring (open, lit) and Mining.
	local prof1 = RPF.Home.rows.profs[1]
	assert(prof1.known.profession.id == 197 and prof1.rank.__text == "120/150", "first profession: " .. tostring(prof1.rank.__text))
	assert(prof1.lit:IsShown(), "the open profession isn't lit")
	assert(RPF.Home.rows.profs[2].known.profession.id == 186, "no Mining row")
	assert(RetailProfessionsHomeProf2:GetAttribute("spell") == "Smelting", "the Mining row doesn't open Smelting")

	profitTab.__scripts.OnClick(profitTab)
	tick(0.3)
	assert(RPF.Home.Active() == "profit" and panels.profit:IsShown() and not panels.training:IsShown(), "Profit isn't showing")
	assert(RetailProfessionsFrame.title.__text == "Profit", "title: " .. RetailProfessionsFrame.title.__text)
	assert(profitTab.checked:IsShown() and not tab.checked:IsShown(), "the Profit tab isn't the lit one")
	assert(not RetailProfessionsHomeProf2.__shown, "a Training line casts under Profit")

	-- The last test left the realm without prices: Refresh asks again.
	buttonWithText("Refresh").__scripts.OnClick()
	tick(0.5)
	assert(RPF.Profit.state == "ok", "no prices after Refresh: " .. RPF.Profit.state)
	local row1 = RPF.Home.rows.crafts[1]
	local row2 = RPF.Home.rows.crafts[2]
	-- Vest +2s 57c a craft (the thread is in the bags now: worth 2c sold), bolt +54c.
	assert(row1.entry and row1.entry.recipe.spell == 2385, "first craft: " .. tostring(row1.entry and row1.entry.recipe.name))
	assert(money(row1.cells.profit.__text) == "2s 57c", "vest profit: " .. money(row1.cells.profit.__text))
	assert(row2.entry and row2.entry.recipe.spell == 2963, "second craft")
	assert(textShown("Estimated craft options"), "no summary of what the bags make")

	-- Sorted by what can be made: the bolt (bags make 2) comes first unless the vest's thread is there.
	local have1 = row1.entry.have
	find(function (f) return f.__kind == "Button" and rawget(f, "col") and f.col.key == "have" end).__scripts.OnClick()
	tick(0.3)
	assert(RetailProfessionsDB.homeSort == "have", "sort not kept")
	assert(RPF.Home.rows.crafts[1].entry.have >= RPF.Home.rows.crafts[2].entry.have, "not sorted by Have")
	RetailProfessionsDB.homeSort = nil
	assert(have1 ~= nil)

	-- A taller pane (DragonUI's window) gets rows to its bottom; those past the list stay empty.
	local scroll, rows = RPF.Home.scrolls.crafts, RPF.Home.rows.crafts
	scroll:SetHeight(26 * 18)
	scroll.__scripts.OnSizeChanged(scroll)
	assert(#rows == 26, "the rows don't fill a taller pane: " .. #rows)
	assert(rows[1].entry and not rows[26]:IsShown(), "the taller list isn't drawn")
	-- Scrolling still reaches DragonUI's hook: the thumb moves with the list.
	scroll.__scripts.OnVerticalScroll(scroll, 0)
	assert(not DragonUI or rawget(scroll, "__thumbMoved"), "DragonUI's thumb doesn't follow the list")
	assert(rows[1].entry, "the list emptied on a scroll")
	tab.__scripts.OnClick(tab)
	tick(0.3)
end)

step("home: to do", function ()
	local texts = table.concat(homeTexts(), " | ")
	print("  to do: " .. texts)
	-- The bolt's cooldown ran out.
	RetailProfessionsCharDB.homeCooldowns[2963].at = 0
	RPF.Home.Refresh()
	assert(homeHas("^Bolt of Linen Cloth is ready$"), "no ready cooldown: " .. table.concat(homeTexts(), " | "))
	-- Mining 50/75: Journeyman at the trainer; never opened here, so open it once.
	assert(homeHas("^Train Journeyman Mining$"), "no train line")
	assert(homeHas("^Open Mining once$"), "no open-once line")
	-- Tailoring 120: both recipes are grey and the bracers come from a pattern, not the trainer.
	assert(homeHas("^No Tailoring skill%-ups left$"), "no skill-up line")
	-- What earns most is on the Profit tab now.
	assert(not homeHas("^Craft "), "a craft-for-gold line on Training")
	local row = RPF.Home.rows.todo[1]
	assert(not row.button.__shown, "a Tailoring line casts while Tailoring is open")
	-- Mining's lines cast Smelting; the cast's click leaves the recipe to pick.
	local mining
	for _, r in ipairs(RPF.Home.rows.todo) do
		if r.item and r.item.text == "Open Mining once" then mining = r.button end
	end
	assert(mining.__shown and mining:GetAttribute("spell") == "Smelting", "the Mining line doesn't cast Smelting")
	-- Clicking the ready cooldown leaves Home on the recipe.
	assert(row.item.text == "Bolt of Linen Cloth is ready", "first line: " .. row.item.text)
	row.__scripts.OnClick(row)
	tick(0.3)
	assert(not RPF.Home.Active() and RPF.list:IsVisible(), "still on Home")
	assert(RPF.selected and RPF.selected.spell == 2963, "the bolt isn't selected")
	RetailProfessionsCharDB.homeCooldowns[2963] = nil
end)

step("home: a line in another profession picks its recipe once that opens", function ()
	RPF.Home.SetActive(true)
	tick(0.2)
	-- As the secure button's PreClick does, then the cast opens the profession.
	RPF.Home.Pend({ skill = 197, spell = 2385 })
	fire("TRADE_SKILL_SHOW")
	tick(0.5)
	assert(not RPF.Home.Active(), "the profession opened on Home")
	assert(RPF.selected and RPF.selected.spell == 2385, "the vest isn't selected: " .. tostring(RPF.selected and RPF.selected.name))
	-- And the open profession's tab goes back from Home to its recipes.
	RPF.Home.SetActive(true)
	tick(0.2)
	local tailoring = find(function (f) return f.__kind == "Button" and rawget(f, "button") == RetailProfessionsTab1 end)
	tailoring.__scripts.OnClick(tailoring)
	tick(0.2)
	assert(not RPF.Home.Active(), "the profession tab didn't leave Home")
end)

step("home: the leveling guide's recipe, its route and its shopping", function ()
	local routes = RPF.Guides.routes
	local saved = routes[197]
	-- Tailoring 120: the step 100-130 wants the vest (grey by now) or the bracers (learnable from
	-- 110 here), the next one anything green.
	routes[197] = {
		{ 100, 130, any = true, { 20, 2385 }, { 20, 3914 } },
		{ 130, 150, count = 5, prefix = "Green", hint = "anything green" },
	}
	local info, bracers = RPF.RecipeList(197)[3914], M.bySpell[3914]
	local savedReq = bracers.reqSkill
	info.reqSkill, bracers.reqSkill = 110, 110
	RPF.Home.SetActive(true)
	tick(0.2)
	RPF.Home.Refresh()
	-- 20 crafts for the step's 30 points, 10 points left: 7.
	local line = homeHas("^Level Tailoring: 7 Green Linen Bracers$")
	assert(line, "no guide line: " .. table.concat(homeTexts(), " | "))
	assert(not homeHas("^No Tailoring skill%-ups left$"), "the guide line didn't take the skill-up line's place")
	local row
	for _, r in ipairs(RPF.Home.rows.todo) do
		if r.item and r.item.text == line then row = r end
	end
	assert(row.item.sub:find("^Guide 100%-130: learn it from "), "sub: " .. row.item.sub)
	-- The tooltip shows the route from here.
	row.__scripts.OnEnter(row)
	local tip = table.concat(tipLines, "\n")
	assert(tip:find("Leveling guide from wow%-professions%.com"), "no route in the tooltip: " .. tip)
	assert(tip:find("100%-130  20 Brown Linen Vest or 20 Green Linen Bracers"), "this step: " .. tip)
	assert(tip:find("130%-150  5 of anything green"), "next step: " .. tip)
	-- Shift-click: the materials for those 7 go on the shopping list, and Home stays.
	IsShiftKeyDown = function () return true end
	row.__scripts.OnClick(row)
	IsShiftKeyDown = function () return false end
	assert(ReagentBankUI.shopping[2321] == 7, "thread for 7: " .. tostring(ReagentBankUI.shopping[2321]))
	assert(RPF.Home.Active(), "shift-click left Home")
	ReagentBankUI.shopping = {}
	-- A click opens the recipe with the amount the step still needs.
	row.__scripts.OnClick(row)
	tick(0.3)
	assert(RPF.selected and RPF.selected.spell == 3914, "the bracers aren't selected")
	assert(RPF.GetQuantity() == 7, "amount: " .. RPF.GetQuantity())
	RPF.SetQuantity(1)
	RPF.Home.SetActive(true)
	tick(0.2)
	-- Made now for later: what's in the bags counts.
	routes[197] = { { 100, 130, seq = true, { 9, 3914 } } }
	bags[4308] = 4
	RPF.Home.Refresh()
	assert(homeHas("^Level Tailoring: 5 Green Linen Bracers$"), "seq count: " .. table.concat(homeTexts(), " | "))
	bags[4308] = 9
	RPF.Home.Refresh()
	assert(not homeHas("^Level Tailoring:"), "a finished seq step still shows: " .. table.concat(homeTexts(), " | "))
	bags[4308] = nil
	-- On its cooldown, or above the era's cap: no guide line.
	bracers.cooldown = 3600
	RPF.Home.Refresh()
	assert(not homeHas("^Level Tailoring:"), "a recipe on its cooldown is suggested")
	bracers.cooldown = nil
	local cap = RPF.skillCap
	RPF.skillCap = 100
	RPF.Home.Refresh()
	assert(not homeHas("^Level Tailoring:"), "a recipe above the era's cap is suggested")
	RPF.skillCap = cap
	routes[197], info.reqSkill, bracers.reqSkill = saved, savedReq, savedReq
	RPF.Home.SetActive(false)
	tick(0.2)
end)

step("home: the shipped routes name only recipes that make sense", function ()
	-- Every step starts where the one before it did or later, and ends after it starts.
	for skill, route in pairs(RPF.Guides.routes) do
		assert(RPF.Guides.URL:format(route.slug):find("^https://"), "no page for " .. skill)
		local last = 0
		for i, step in ipairs(route) do
			assert(step[1] >= last and step[2] > step[1], skill .. " step " .. i)
			assert(step.count or #step >= 3, skill .. " step " .. i .. " names nothing")
			for e = 3, #step do assert(step[e][1] > 0 and step[e][2] > 0, skill .. " step " .. i) end
			last = step[1]
		end
	end
end)

-----------------------------------------
-- Multicraft, Resourcefulness and crafting speed: skill-based, rolled by the server

step("archaeology: its tab opens ArchaeologyUI's page in this window, the tabs staying", function ()
	local line = tradeSkillLine
	if not RetailProfessionsFrame:IsShown() then
		tradeSkillLine = { "Tailoring", 120, 150 }
		fire("TRADE_SKILL_SHOW")
		tick(0.5)
	end
	local Pages = RetailProfessions.Pages
	local built, shown = 0, 0
	local A = { skill = 60, maxSkill = 75, SurveyButtonClick = function () end,
		OpenWindow = function () Pages.Open("archaeology") end,
		ToggleWindow = function () Pages.Toggle("archaeology") end }
	ArchaeologyUI = A
	Pages.Add("archaeology", { title = "Archaeology", icon = "Interface\\Icons\\INV_Misc_Shovel_01",
		skill = function () return "Archaeology", A.skill, A.maxSkill end,
		build = function (panel)
			built = built + 1
			panel.races = panel.Header(panel.list, "Races")
		end,
		onShow = function () shown = shown + 1 end })
	RPF.Fire("SKILLS")
	tick(0.5)
	local function tabOf(id)
		return find(function (f) return f.__kind == "Button" and rawget(f, "profession") and f.profession.id == id end)
	end
	local tab, own = tabOf(794), tabOf(M.skill)
	local title = RetailProfessionsFrame.title
	local ownTitle = title.__text
	assert(tab and tab:IsShown() and tab.onClick, "no Archaeology tab")
	local closed = closedTradeSkill
	tab.__scripts.OnClick(tab)
	tick(0.2)
	assert(RetailProfessionsFrame:IsShown() and closedTradeSkill == closed, "the window went for the research view")
	assert(Pages.Shown("archaeology") and built == 1 and shown == 1, "no Archaeology page")
	for _, pane in ipairs(RPF.panes) do assert(not pane:IsShown(), "the recipes show under the page") end
	assert(title.__text == "Archaeology", "title: " .. title.__text)
	assert(tab.checked:IsShown() and not own.checked:IsShown(), "Archaeology's tab isn't the lit one")
	assert(RPF.IsOpen() and viewTab("Training"):IsShown(), "the profession behind the page went")

	-- The open profession's tab goes back to its recipes.
	assert(own.onClick, "the open profession's tab casts instead of going back")
	own.__scripts.OnClick(own)
	tick(0.2)
	assert(not Pages.Current() and RPF.panes[1]:IsShown(), "not back on the recipes")
	assert(title.__text == ownTitle and own.checked:IsShown(), "the profession's header didn't come back")
	-- So do Training and another profession opening.
	tab.__scripts.OnClick(tab)
	RPF.Home.SetActive("training")
	tick(0.2)
	assert(not Pages.Current() and RPF.Home.Active() == "training" and not RPF.panes[1]:IsShown(), "Training under the page")
	RPF.Home.SetActive(false)
	tab.__scripts.OnClick(tab)
	fire("TRADE_SKILL_SHOW")
	tick(0.5)
	assert(not Pages.Current() and RPF.panes[1]:IsShown(), "a profession opened under the page")

	-- /arch with the window closed: it opens on the page with no profession behind it.
	RetailProfessionsFrame:Hide()
	fire("TRADE_SKILL_CLOSE")
	tick(0.2)
	A.OpenWindow()
	tick(0.2)
	assert(RetailProfessionsFrame:IsShown() and Pages.Shown("archaeology") and not RPF.IsOpen(), "/arch didn't open the page")
	assert(not viewTab("Training"):IsShown(), "Training with no profession open")
	assert(tab.checked:IsShown() and not own.checked:IsShown() and own.button.__shown, "the profession's tab doesn't cast")
	A.ToggleWindow()
	assert(not RetailProfessionsFrame:IsShown() and not Pages.Current(), "toggling didn't close the window")
	assert(RPF.panes[1]:IsShown(), "the recipes stay hidden for next time")

	ArchaeologyUI = nil
	RPF.Fire("SKILLS")
	tradeSkillLine = line
	fire("TRADE_SKILL_SHOW")
	tick(0.5)
end)

step("perks: a grey recipe gets the most, and only what it can", function ()
	RPF.Select(M.bySpell[2963])
	-- Tailoring 120, the bolt went grey at 50.
	local perks = M.PerksOf(M.bySpell[2963])
	assert(perks and perks.multicraft == 25 and perks.resourceful == 20 and perks.castTime == 1.5,
		"bolt perks: " .. tostring(perks and perks.multicraft) .. " / " .. tostring(perks and perks.castTime))
	assert(textShown("Multicraft|r 25%%.*Resourcefulness|r 20%%.*Cast|r 1%.5 sec"), "perk line missing")
	-- The vest doesn't stack: no Multicraft.
	RPF.Select(M.bySpell[2385])
	assert(M.PerksOf(M.bySpell[2385]).multicraft == nil, "Multicraft on a vest")
	assert(textShown("^|cffffd200Resourcefulness|r 20%%"), "the vest's perk line: no Multicraft expected")
	-- An unlearned recipe has nothing to show yet.
	assert(M.PerksOf(M.bySpell[3914]) == nil, "perks on an unlearned recipe")
end)

step("perks: they follow skill between yellow and grey", function ()
	local function recipe(yellow, grey) return { learned = true, spell = 2963, perks = 7, yellow = yellow, grey = grey } end
	local orange = M.PerksOf(recipe(125, 150))
	assert(orange.multicraft == 0 and orange.resourceful == 0 and orange.castTime == 3, "an orange recipe got something")
	local halfway = M.PerksOf(recipe(110, 130))
	assert(halfway.multicraft == 12.5 and halfway.resourceful == 10 and halfway.castTime == 2.25,
		"halfway: " .. halfway.multicraft .. " / " .. halfway.castTime)
	assert(M.PerksText(halfway, true) == "Multicraft 13%, Resourcefulness 10%, Cast 2.3 sec"
		or M.PerksText(halfway, true) == "Multicraft 13%, Resourcefulness 10%, Cast 2.2 sec", M.PerksText(halfway, true))
	RPF.AddSkillUpLines(GameTooltip, M.bySpell[2963])
	assert(table.concat(tipLines, "\n"):find("Multicraft 25%%"), "the tooltip doesn't mention the perks")
end)

step("perks: a proc says so", function ()
	reply("PK:0:2963:M:2996*1")
	assert(textShown("Multicraft! 1 Bolt of Linen Cloth more"), "no Multicraft line")
	-- Both from one craft: the line keeps both.
	reply("PK:0:2963:R:2589*1/2320*1")
	assert(textShown("Multicraft! .*Resourcefulness! You got back 1 Linen Cloth, 1 Coarse Thread"), "no Resourcefulness line")
end)

step("perks: procs go to MSBT and the proc log counts them", function ()
	local L = RPF.ProcLog
	local msbt = {}
	MikSBT = { DISPLAYTYPE_NOTIFICATION = "Notification", DisplayMessage = function (...) table.insert(msbt, { ... }) end }
	-- From a clean log (the earlier steps' crafts and procs aside), create two bolts: each
	-- finished cast is a craft that could get either.
	L.Clear()
	DoTradeSkill(2, 2)
	fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Bolt of Linen Cloth")
	reply("PK:0:2963:M:2996*2")
	assert(msbt[1] and msbt[1][1] == "Multicraft! +2 Bolt of Linen Cloth" and msbt[1][2] == "Notification"
		and msbt[1][4] == 255, "MSBT message: " .. tostring(msbt[1] and msbt[1][1]))
	RetailProfessionsDB.procText = false
	reply("PK:0:2963:R:2589*1")
	assert(#msbt == 1, "scrolling text still shown when turned off")
	RetailProfessionsDB.procText = nil
	MikSBT = nil
	fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Bolt of Linen Cloth")
	-- Past the two asked for, someone else's cast, another spell: none are crafts.
	fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Bolt of Linen Cloth")
	fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "Bolt of Linen Cloth")
	fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Fireball")
	local s = L.Session()
	assert(s.M.procs == 1 and s.M.items == 2 and s.R.procs == 1 and s.R.items == 1,
		"session counts: " .. s.M.procs .. "/" .. s.M.items .. " " .. s.R.procs .. "/" .. s.R.items)
	assert(s.M.crafts == 2 and s.R.crafts == 2 and s.M.rated == 1 and s.R.rated == 1,
		"crafts " .. s.M.crafts .. ", rated " .. s.M.rated)
	assert(L.Total().M.procs == 1 and #L.Entries() == 2, "not saved per character")
	-- A proc no counted craft explains (a macro, the window closed before the list came) stays out
	-- of the rate.
	tick(4)
	reply("PK:0:2963:M:2996*1")
	assert(s.M.procs == 2 and s.M.rated == 1, "a stray proc went into the rate")
	-- An interrupted Create All counts no more.
	DoTradeSkill(2, 5)
	fire("UNIT_SPELLCAST_INTERRUPTED", "player", "Bolt of Linen Cloth")
	fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Bolt of Linen Cloth")
	assert(s.M.crafts == 2, "counted after an interrupt")
	SlashCmdList.RETAILPROFESSIONS("log")
	assert(L.frame:IsShown(), "/prof log didn't open the log")
	assert(textShown("Multicraft:|r 2 procs, 50%% of 2 crafts, %+3 items"), "no session summary")
	assert(textShown("Resourcefulness:|r 1 proc, 50%% of 2 crafts, 1 reagent back"), "no Resourcefulness summary")
	assert(L.EntryText(L.Entries()[1]):find("Multicraft|r Bolt of Linen Cloth: %+2x "), L.EntryText(L.Entries()[1]))
	-- One more while it's open goes on the end.
	reply("PK:0:2963:M:2996*1")
	assert(#L.Entries() == 4 and textShown("Multicraft:|r 3 procs"), "the open log didn't take the new proc")
	L.Clear()
	assert(#L.Entries() == 0 and L.Session().M.procs == 0, "Clear kept something")
	assert(textShown("No procs yet"), "no empty text after Clear")
	SlashCmdList.RETAILPROFESSIONS("log")
	assert(not L.frame:IsShown(), "/prof log didn't close the log")
end)

-----------------------------------------
-- Milling: a tab of its own, the herbs as rows, and the server doing the work

local function sentCount(pattern)
	local n = 0
	for _, m in ipairs(sent) do if m:match(pattern) then n = n + 1 end end
	return n
end
local function rowNames()
	local names = {}
	for _, row in ipairs(RPF.list.rows) do table.insert(names, row.header and ("[" .. row.header .. "]") or row.recipe.name) end
	return table.concat(names, ", ")
end
local createButton = buttonWithText("Create")
local createAllButton = find(function (f) return f.__kind == "Button" and f.__text:find("^Create All") end)

step("milling: no tab without the spell", function ()
	assert(not RetailProfessionsRefineTabM.__shown, "a Milling tab for a tailor")
end)

step("milling: its tab opens Inscription on your herbs", function ()
	table.insert(skillLines, 3, { "Inscription", false, 100, 150 })
	knownSpells.Inscription, knownSpells.Milling = true, true
	bags[2447] = 23
	fire("SKILL_LINES_CHANGED")
	tick(0.5)
	local tab = RetailProfessionsRefineTabM
	assert(tab.__shown and tab:GetAttribute("spell") == "Inscription", "Milling tab doesn't open Inscription")
	assert(not RetailProfessionsRefineTabP.__shown, "a Prospecting tab without the spell")

	-- The click: the tab says what it wants, the cast opens the profession.
	tab.__scripts.PreClick(tab)
	tradeSkillLine = { "Inscription", 100, 150 }
	fire("TRADE_SKILL_SHOW")
	tick(0.5)
	assert(RPF.Refine.Active() == RPF.Refine.Kind("M"), "the window isn't on Milling")
	assert(sentCount("^Y:%d+:M$") == 1, "what herbs give wasn't asked once")
	assert(rowNames() == "[Herbs you can mill], Peacebloom, [Other herbs], Mageroyal, Goldclover", "rows: " .. rowNames())
	assert(RPF.selected and RPF.selected.name == "Peacebloom", "the first herb isn't selected")
	assert(createButton.__text == "Mill" and createButton:IsEnabled(), "Mill button: " .. createButton.__text)
	-- 23 in the bags: four times five.
	assert(createAllButton.__text == "Mill All [4]", "Mill All: " .. createAllButton.__text)
	assert(textShown("Mill 5 gives:") and textShown("2%-4 .*Alabaster Pigment.*100%%"), "what it gives isn't shown")
	assert(not tab.__shown, "with Inscription open the Milling tab still casts")
end)

step("milling: a herb past your skill, and search by what it gives", function ()
	RPF.Select(RPF.Refine.ByKey("M:36901"))
	assert(not createButton:IsEnabled() and not createAllButton:IsEnabled(), "Goldclover can be milled at skill 100")
	assert(textShown("Requires:.*Inscription 325"), "the skill it needs isn't shown")
	RPF.filter.text = "verdant"
	RPF.Rebuild(true)
	assert(rowNames() == "[Other herbs], Mageroyal", "search by pigment: " .. rowNames())
	RPF.filter.text = ""
	RPF.filter.haveMats = true
	RPF.Rebuild(true)
	assert(rowNames() == "[Herbs you can mill], Peacebloom", "have-materials: " .. rowNames())
	RPF.filter.haveMats = false
	RPF.Rebuild(true)
end)

step("milling: Mill All runs on the server and Stop ends it", function ()
	RetailProfessionsDB.autoWithdraw = false
	RPF.Select(RPF.Refine.ByKey("M:2447"))
	local before = #crafted
	createAllButton.__scripts.OnClick()
	tick(0.2)
	assert(sent[#sent]:match("^X:%d+:M:2447:4$"), "no job for 4 casts: " .. sent[#sent])
	assert(#crafted == before, "a trade skill was cast for milling")
	assert(RPF.Refine.job and RPF.Refine.job.total == 4, "no job running")
	assert(createButton.__text == "Stop" and createButton:IsEnabled(), "no Stop button: " .. createButton.__text)
	assert(not createAllButton:IsEnabled(), "Mill All still enabled during a job")

	reply("XP:" .. millJob .. ":1:4:39151*3")
	bags[2447] = 18
	fire("BAG_UPDATE")
	tick(0.5)
	assert(textShown("Milling Peacebloom: 1 of 4"), "no progress line")
	assert(RPF.GetQuantity() == 3, "Mill All didn't count down: " .. RPF.GetQuantity())

	createButton.__scripts.OnClick()
	tick(0.2)
	assert(sent[#sent]:match("^XS:"), "Stop didn't reach the server")
	assert(not RPF.Refine.job, "the job didn't end")
	assert(textShown("Milled 5 x Peacebloom: 3 Alabaster Pigment"), "no summary")
	assert(RPF.GetQuantity() == 3, "the amount left after Stop: " .. RPF.GetQuantity())
	assert(createButton.__text == "Mill" and createAllButton.__text == "Mill All [3]", "buttons after the job: "
		.. createButton.__text .. " / " .. createAllButton.__text)
end)

step("milling: herbs come out of the reagent bank first", function ()
	RetailProfessionsDB.autoWithdraw = true
	ReagentBankUI.banked[785] = 12
	RPF.Rebuild(true)
	assert(rowNames():find("Herbs you can mill%], Peacebloom, Mageroyal"), "banked herbs don't count: " .. rowNames())
	RPF.Select(RPF.Refine.ByKey("M:785"))
	assert(createAllButton.__text == "Mill All [2]", "Mill All with the bank: " .. createAllButton.__text)
	local before = sentCount("^X:")
	withdrawn = nil
	createAllButton.__scripts.OnClick()
	assert(withdrawn and withdrawn.name == "Mageroyal" and withdrawn.count == 2
		and withdrawn.reagents[1].itemEntry == 785 and withdrawn.reagents[1].requiredPerCraft == 5, "no withdraw of 10 Mageroyal")
	assert(sentCount("^X:") == before, "milled before the herbs arrived")
	bags[785] = 10
	fire("BAG_UPDATE")
	tick(0.5)
	assert(sent[#sent]:match("^X:%d+:M:785:2$"), "didn't mill after the withdraw: " .. sent[#sent])
	reply("XP:" .. millJob .. ":2:2:39334*5/43103*1")
	reply("XE:" .. millJob .. ":2:2:done")
	millJob = nil
	bags[785] = nil
	fire("BAG_UPDATE")
	tick(0.5)
	assert(textShown("Milled 10 x Mageroyal: 5 Dusky Pigment, 1 Verdant Pigment"), "no summary of both pigments")
	ReagentBankUI.banked[785] = nil
	RetailProfessionsDB.autoWithdraw = false
end)

step("milling: a refusal says why", function ()
	RPF.Select(RPF.Refine.ByKey("M:2447"))
	createButton.__scripts.OnClick()
	-- The fake server answers ok; turn that one answer into a refusal.
	local msg = table.remove(outbox, 1)
	table.insert(sent, msg[2])
	reply("ERR:" .. msg[2]:match("^X:(%d+)") .. ":combat")
	tick(0.2)
	assert(not RPF.Refine.job and textShown("you're in combat"), "refusal not shown")
	assert(createButton.__text == "Mill" and createButton:IsEnabled(), "Mill button dead after a refusal")
end)

step("milling: the profession's tab goes back to its recipes, the book has a Milling button", function ()
	local tab
	for i = 1, 10 do
		local b = _G["RetailProfessionsTab" .. i]
		if b and not b.__shown then
			-- The one tab that isn't a cast any more: Inscription's, while its herbs are showing.
			tab = find(function (f) return f.__kind == "Button" and rawget(f, "button") == b and rawget(f, "onClick") end)
			if tab then break end
		end
	end
	assert(tab and tab.profession.id == 773, "Inscription's tab doesn't take the click")
	tab.__scripts.OnClick(tab)
	tick(0.2)
	assert(not RPF.Refine.Active(), "still on Milling")
	assert(not rowNames():find("Herbs you can mill"), "the herbs stayed in the list: " .. rowNames())
	assert(createButton.__text == "Create", "Create button: " .. createButton.__text)
	-- And the Milling tab, with Inscription open, switches without a cast.
	local millTab = find(function (f) return f.__kind == "Button" and rawget(f, "code") == "M" end)
	assert(millTab.onClick, "the Milling tab doesn't take the click")
	millTab.__scripts.OnClick(millTab)
	tick(0.2)
	assert(RPF.Refine.Active(), "the Milling tab didn't switch")

	RPF.ToggleBook()
	local button = buttonWithText("Milling")
	assert(button and button:IsVisible(), "no Milling button in the book")
	button.__scripts.OnClick(button)
	assert(not RetailProfessionsBook:IsShown() and RPF.Refine.Active(), "the book's Milling button")
end)

step("milling: closing the window stops the job; the next profession opens on recipes", function ()
	RPF.Select(RPF.Refine.ByKey("M:2447"))
	createButton.__scripts.OnClick()
	tick(0.2)
	assert(RPF.Refine.job, "no job to stop")
	RetailProfessionsFrame:Hide()
	tick(0.2)
	assert(sent[#sent]:match("^XS:") and not RPF.Refine.job, "closing didn't stop the job")
	fire("TRADE_SKILL_CLOSE")

	tradeSkillLine = { "Tailoring", 120, 150 }
	fire("TRADE_SKILL_SHOW")
	tick(0.5)
	assert(RetailProfessionsFrame:IsShown() and not RPF.Refine.Active(), "Tailoring opened on herbs")
	assert(M.skill == 197 and #M.recipes == 2, "Tailoring's recipes are gone")
	bags[2447] = nil
end)

-- The tabs down the right edge: at full size while they fit, smaller when a character knows
-- every profession, and never past the bottom of the window.
step("tabs: a full column stays inside the window", function ()
	local function column()
		local out = {}
		for _, name in ipairs({ "Training", "Profit" }) do
			local view = viewTab(name)
			if view.__shown then table.insert(out, view) end
		end
		for i = 1, 12 do
			local b = _G["RetailProfessionsTab" .. i]
			if b and b.__shown then table.insert(out, b.region) end
		end
		for _, b in ipairs({ RetailProfessionsRefineTabM, RetailProfessionsRefineTabP }) do
			if b.__shown then table.insert(out, b.region) end
		end
		return out
	end
	-- DragonUI's professions tabs are bigger.
	local full = DRAGON == "2" and 50 or 32
	local few = column()
	assert(#few == 6, "tabs before: " .. #few)
	assert(few[1]:GetHeight() == full, "a short column's tabs aren't full size: " .. few[1]:GetHeight())

	local extra = { "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Jewelcrafting", "Leatherworking",
		"Cooking", "First Aid", "Runeforging" }
	for _, name in ipairs(extra) do
		table.insert(skillLines, 2, { name, false, 300, 300 })
		knownSpells[name] = true
	end
	knownSpells.Prospecting = true
	fire("SKILL_LINES_CHANGED")
	tick(0.5)

	local all = column()
	assert(#all == 16, "tabs with every profession: " .. #all)
	local mining = find(function (f) return rawget(f, "profession") and f.profession.id == 186 and rawget(f, "icon") end)
	assert(mining and mining.icon:GetTexture() == "Interface\\Icons\\Spell_Fire_FlameBlades",
		"Mining's tab doesn't show Smelting: " .. tostring(mining and mining.icon:GetTexture()))
	local size = all[1]:GetHeight()
	assert(size < full and size >= 14, "a full column's tabs didn't shrink: " .. size)
	local last
	for i, tab in ipairs(all) do
		local top = -tab.__point[5]
		assert(tab:GetHeight() == size and tab:GetWidth() == size, "tab " .. i .. " has its own size")
		assert(not last or top >= last + size, "tab " .. i .. " lies over the one above")
		last = top
	end
	assert(last + size <= RetailProfessionsFrame:GetHeight(), "the column runs past the window: " .. (last + size))

	for _, name in ipairs(extra) do
		table.remove(skillLines, 2)
		knownSpells[name] = nil
	end
	knownSpells.Prospecting = nil
	fire("SKILL_LINES_CHANGED")
	tick(0.5)
	assert(#column() == 6 and column()[1]:GetHeight() == full, "the tabs didn't grow back")
end)

-----------------------------------------
-- Profession equipment: slots kept on the server (HELLO_GEAR)

local function countOf(lines, text)
	local n = 0
	for _, line in ipairs(lines) do if line == text then n = n + 1 end end
	return n
end
local function bookRow(skill)
	return find(function (f) return rawget(f, "gear") and rawget(f, "known") and f.known.profession.id == skill and f:IsVisible() end)
end

step("gear: no strip without HELLO_GEAR", function ()
	RPF.Select(M.bySpell[2963])
	assert(not RPF.Gear.Enabled() and not RPF.gearStrip:IsShown(), "gear slots on a realm without them")
	assert(sentCount("^GC:") == 0 and sentCount("^G:") == 0 and sentCount("^GT:") == 0, "asked for gear without HELLO_GEAR")
end)

step("gear: HELLO_GEAR loads the catalog and the slots, once", function ()
	helloFlags = 63
	RPF.SayHello()
	tick(1)
	assert(RPF.HELLO_GEAR == 0x20 and RPF.Gear.Enabled(), "HELLO_GEAR not read")
	assert(sentCount("^GC:") == 1 and sentCount("^G:") == 1, "catalog and slots asked " .. sentCount("^GC:") .. "/" .. sentCount("^G:"))
	local c = RPF.gear.catalog
	assert(c[90800] and c[90800].kind == 0 and c[90800].skillBonus == 10 and c[90800].multicraft == 5 and c[90800].reqRank == 100,
		"tool row not read")
	assert(c[90802] and c[90802].skill == 186 and c[90802].finesse == 4 and c[90802].deftness == 10, "mining row not read")
	assert(RPF.gear.slots[197][0].entry == 90800 and RPF.gear.slots[197][0].guid == 5001, "slot not read")
	local t = RPF.gear.totals[197]
	assert(t.skillBonus == 10 and t.multicraft == 5 and t.resourcefulness == 3 and t.speed == 10, "totals not summed")
	-- The strip on the recipe card: the open profession's three slots, the tool in the first.
	local strip = RPF.gearStrip
	assert(strip:IsVisible() and strip.skill == 197, "no strip on the card")
	assert(strip.buttons[1].entry == 90800 and strip.buttons[1]:IsShown(), "the tool isn't in its slot")
	assert(not strip.buttons[2].entry and strip.buttons[3]:IsShown(), "accessory slots wrong")
	-- An empty slot says what goes there.
	strip.buttons[2].__scripts.OnEnter(strip.buttons[2])
	assert(GameTooltip.__text == "Accessory slot" and table.concat(tipLines, "\n"):find("Drag a Tailoring accessory here"),
		"empty slot tooltip: " .. tostring(GameTooltip.__text))
	strip.buttons[1].__scripts.OnEnter(strip.buttons[1])
	assert(countOf(tipLines, "Tailoring Tool") == 1 and table.concat(tipLines, "\n"):find("Right%-click to put it back"),
		"filled slot tooltip: " .. table.concat(tipLines, " | "))
	RPF.HideItemTooltip()
	-- Cooking has two.
	strip:SetSkill(185)
	assert(strip.buttons[2]:IsShown() and not strip.buttons[3]:IsShown(), "Cooking doesn't have two slots")
	strip:SetSkill(356)
	assert(not strip:IsShown(), "Fishing has slots")
	strip:SetSkill(M.skill)
end)

step("gear: tooltips name gear items, once", function ()
	GameTooltip:SetOwner(UIParent)
	GameTooltip:SetHyperlink("item:90800")
	local text = table.concat(tipLines, "\n")
	for _, want in ipairs({ "Tailoring Tool", "+10 Tailoring Skill",
		"Equip: Multicraft: 5% more chance that a craft makes a second batch.",
		"Equip: Resourcefulness: 3% more chance to get some of the reagents back.",
		"Equip: Crafting Speed: Crafting takes 10% less time." }) do
		assert(countOf(tipLines, want) == 1, "missing " .. want .. ": " .. text)
	end
	assert(not text:find("Requires"), "Tailoring 120 meets 100")
	assert(not text:find("Finesse"), "a stat at 0 shown")
	-- The tooltip saying again it holds the item adds nothing.
	GameTooltip.__scripts.OnTooltipSetItem(GameTooltip)
	assert(countOf(tipLines, "Tailoring Tool") == 1, "lines added twice")
	-- Mining 50 is short of the lamp's 200; a chat link's tooltip has them too.
	ItemRefTooltip:SetHyperlink("item:90802")
	local ref = table.concat(refLines, "\n")
	for _, want in ipairs({ "Mining Accessory", "+5 Mining Skill",
		"Equip: Finesse: 4% chance of one extra ore or stone each time you loot one.",
		"Equip: Perception: Gems and other rare finds in a vein are 6% more likely to drop.",
		"Equip: Deftness: Mining takes 10% less time.", "Requires Mining (200)" }) do
		assert(countOf(refLines, want) == 1, "missing " .. want .. ": " .. ref)
	end
	GameTooltip:SetHyperlink("item:2589")
	assert(#tipLines == 0, "lines on an item that isn't gear: " .. table.concat(tipLines, " | "))
end)

step("gear: perk odds add the profession's equipment, capped", function ()
	RPF.Select(M.bySpell[2963])
	-- The grey bolt: 25 / 20 / 50 from mastery, the shears add 5 / 3 / 10.
	local perks = M.PerksOf(M.bySpell[2963])
	assert(perks.multicraft == 30 and perks.resourceful == 23 and perks.speed == 60 and math.abs(perks.castTime - 1.2) < 1e-9,
		"with the tool: " .. perks.multicraft .. " / " .. perks.resourceful .. " / " .. perks.speed)
	assert(perks.gear and perks.gear.multicraft == 5 and perks.gear.speed == 10, "what the gear added isn't kept")
	assert(textShown("Multicraft|r 30%%.*Resourcefulness|r 23%%.*Cast|r 1%.2 sec"), "the perk line doesn't count the gear")
	-- An unasked push replaces the slots: the thimble (Multicraft 90, speed 50) goes on.
	reply("GD:0:197,0,90800,5001;197,1,90801,5002")
	reply("GE:0:2")
	tick(0.3)
	assert(RPF.gear.slots[197][1].entry == 90801 and RPF.gearStrip.buttons[2].entry == 90801, "the push wasn't taken")
	perks = M.PerksOf(M.bySpell[2963])
	assert(perks.multicraft == 100 and perks.resourceful == 23, "Multicraft not capped at 100: " .. perks.multicraft)
	assert(perks.speed == 90 and math.abs(perks.castTime - 0.3) < 1e-9, "speed not capped at 90: " .. perks.speed)
	assert(textShown("Multicraft|r 100%%"), "the open recipe didn't redraw")
end)

step("gear: the tools a recipe needs come from the server", function ()
	RPF.Select(M.bySpell[2963])
	tick(0.3)
	RPF.Select(M.bySpell[2963])
	tick(0.3)
	assert(sentCount("^GT:[^:]*:197$") == 1, "tools asked " .. sentCount("^GT:") .. " times")
	local tools = M.bySpell[2963].tools
	assert(#tools == 1 and tools[1].name == "Blacksmith Hammer" and not tools[1].has, "bolt tools")
	assert(textShown("Requires:|r |cffff2020Blacksmith Hammer"), "a missing tool isn't red")
	bags[5956] = 1
	fire("BAG_UPDATE")
	tick(0.5)
	assert(textShown("Requires:|r |cffffffffBlacksmith Hammer"), "the hammer in the bags doesn't count")
	bags[5956] = nil
	-- The vest's spanner: the thimble in a slot stands in for it.
	RPF.Select(M.bySpell[2385])
	assert(textShown("Requires:|r |cffffffffArclight Spanner"), "a slotted tool doesn't count")
	reply("GD:0:197,0,90800,5001")
	reply("GE:0:1")
	tick(0.3)
	assert(textShown("Requires:|r |cffff2020Arclight Spanner"), "taking the thimble off didn't redraw the tools")
end)

step("gear: drag from the bags onto a slot, right-click to take it off", function ()
	RPF.ToggleBook()
	assert(RetailProfessionsBook:GetWidth() == 500, "the book didn't make room for the slots")
	local row = bookRow(186)
	assert(row and row.gear:IsShown() and row.gear.skill == 186, "no Mining slots in the book")
	assert(not bookRow(356) or not bookRow(356).gear:IsShown(), "Fishing slots in the book")
	containers[0] = { [3] = 90802 }
	cursor = 90802
	PickupContainerItem(0, 3)
	local slot = row.gear.buttons[2]
	slot.__scripts.OnReceiveDrag(slot)
	tick(0.3)
	assert(sentCount("^GQ:%d+:0:3:186:1$") == 1, "drop sent: " .. sent[#sent])
	assert(cursor == nil, "the cursor kept the item")
	assert(RPF.gear.slots[186][1].entry == 90802 and slot.entry == 90802, "the lamp isn't in the slot")
	-- Right-click takes it off.
	slot.__scripts.OnClick(slot, "RightButton")
	tick(0.3)
	assert(sentCount("^GU:%d+:186:1$") == 1 and not RPF.gear.slots[186], "right-click didn't take it off")
	-- Something not from the bags (here: not what was picked up) isn't sent.
	local before = #sent
	cursor = 90800
	slot.__scripts.OnClick(slot, "LeftButton")
	tick(0.3)
	assert(#sent == before and errorsShown[#errorsShown] == "Drag profession equipment from your bags.", "a cursor item not from the bags")
	RPF.ToggleBook()
end)

step("gear: right-click a gear item in the bags puts it on", function ()
	containers[0] = { [4] = 90802, [5] = 5956 }
	-- Not while selling, nor in combat, nor a plain tool (a weapon would be equipped).
	CreateFrame("Frame", "MerchantFrame")
	UseContainerItem(0, 4)
	MerchantFrame:Hide()
	combat = true
	UseContainerItem(0, 4)
	combat = false
	UseContainerItem(0, 5)
	tick(0.3)
	assert(sentCount("^GQ:%d+:0:[45]:") == 0, "right-click sent at the wrong time")
	UseContainerItem(0, 4)
	tick(0.3)
	assert(sentCount("^GQ:%d+:0:4:0:9$") == 1, "right-click didn't ask for the first free slot")
	assert(RPF.gear.slots[186] and RPF.gear.slots[186][1].entry == 90802, "the lamp didn't go on")
	MerchantFrame = nil
end)

step("gear: a refusal says why", function ()
	containers[0] = { [6] = 90802 }
	gearRefuse = "rank"
	UseContainerItem(0, 6)
	tick(0.3)
	assert(errorsShown[#errorsShown] == "Your skill in that profession is too low for this item.", "rank: " .. tostring(errorsShown[#errorsShown]))
	gearRefuse = "weird"
	UseContainerItem(0, 6)
	tick(0.3)
	assert(errorsShown[#errorsShown] == "Couldn't change your profession equipment (weird).", "unknown: " .. tostring(errorsShown[#errorsShown]))
	for code in ("off loading combat casting trade bot noitem notgear unlearned rank slot dup bags empty busy"):gmatch("%a+") do
		assert(not RPF.Gear.ErrorText(code):find("Couldn't"), "no text for " .. code)
	end
end)

step("gear: the Equipment tab has a card per profession that takes gear", function ()
	RPF.Home.SetActive("training")
	tick(0.3)
	assert(not textShown("^Equipment$"), "Training still has an Equipment section")
	RPF.Home.SetActive("equipment")
	tick(0.3)
	assert(RPF.Home.Active() == "equipment", "Equipment didn't open")
	local function cards()
		local skills = {}
		for _, row in ipairs(RPF.Home.rows.cards) do
			for _, card in ipairs(row) do
				if card:IsVisible() then skills[card.gear.skill] = card end
			end
		end
		return skills
	end
	local skills = cards()
	assert(skills[197] and skills[186] and skills[186].gear.buttons[2].entry == 90802, "Equipment's cards")
	assert(skills[197].bar.Caption.__text == "120/150", "a card's rank")
	assert(not skills[356], "a Fishing card without HELLO_GEAR_GATHER")
	assert(textShown("^Profession Equipment$"), "no Equipment heading")

	-- With the rod slot, Fishing gets a card of its own.
	helloFlags = 127
	RPF.SayHello()
	tick(1)
	RPF.Home.SetActive("equipment")
	tick(0.3)
	skills = cards()
	assert(skills[356] and skills[356].gear.buttons[1]:IsShown() and not skills[356].gear.buttons[2]:IsShown(),
		"no Fishing card with its one rod slot")

	-- A character with every profession: Training's list scrolls, and Equipment's cards too.
	local added = { "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism", "Jewelcrafting",
		"Leatherworking", "Skinning", "Cooking", "First Aid", "Runeforging", "Archaeology" }
	ArchaeologyUI = { skill = 60, maxSkill = 75, OpenWindow = function () end, ToggleWindow = function () end,
		SurveyButtonClick = function () end }
	for _, name in ipairs(added) do
		table.insert(skillLines, { name, false, 10, 75 })
		if name ~= "Herbalism" and name ~= "Skinning" then knownSpells[name] = true end
	end
	RPF.Fire("SKILLS")
	tick(0.5)
	assert(#RPF.KnownProfessions() > 12, "only " .. #RPF.KnownProfessions() .. " professions")
	skills = cards()
	RPF.Home.SetActive("equipment")
	tick(0.3)
	local cardScroll = RPF.Home.scrolls.cards
	assert(cardScroll:IsShown(), "Equipment's cards don't scroll with " .. #RPF.Gear.Known())
	local carded = {}
	for offset = 0, #RPF.Gear.Known() do
		FauxScrollFrame_SetOffset(cardScroll, offset)
		RPF.Home.Refresh()
		for skill in pairs(cards()) do carded[skill] = true end
	end
	FauxScrollFrame_SetOffset(cardScroll, 0)
	assert(carded[393] and carded[182] and carded[356] and carded[185], "no Skinning, Herbalism, Fishing or Cooking card")
	RPF.Home.SetActive("training")
	tick(0.3)
	local scroll = RPF.Home.scrolls.profs
	assert(scroll:IsShown(), "Training's professions don't scroll with " .. #RPF.KnownProfessions())
	local seen = {}
	for offset = 0, #RPF.KnownProfessions() do
		FauxScrollFrame_SetOffset(scroll, offset)
		RPF.Home.Refresh()
		for _, row in ipairs(RPF.Home.rows.profs) do
			if row:IsShown() and row.known then seen[row.known.profession.id] = true end
		end
	end
	-- Gathering ones and Fishing have no window, so no line: their slots are on Equipment.
	assert(seen[171] and seen[185] and seen[129] and seen[186] and seen[197] and seen[794] and seen[776],
		"a profession never shows in Training")
	FauxScrollFrame_SetOffset(scroll, 0)
	for _, name in ipairs(added) do
		table.remove(skillLines)
		knownSpells[name] = nil
	end
	ArchaeologyUI = nil
	RPF.Fire("SKILLS")
	helloFlags = 63
	RPF.SayHello()
	tick(1)
	RPF.Home.SetActive(false)
	tick(0.3)
end)

step("gear: each accessory slot takes one kind, Fishing has a lure slot, the slots are the account's", function ()
	helloFlags = 511
	gearSlots = { { 197, 0, 90800, 5001 }, { 356, 1, 6529, 5002, 18 } }
	RPF.SayHello()
	tick(1)
	local G = RPF.Gear
	assert(G.SlotCount(185) == 3 and G.SlotCount(356) == 2 and G.SlotCount(197) == 3, "slot counts")
	assert(G.KindName(185, 1) == "Hat" and G.KindName(185, 2) == "Apron" and G.KindName(356, 1) == "Lures"
		and G.KindName(197, 0) == nil, "slot kinds")
	assert(G.AccountWide(), "HELLO_GEAR_ACCOUNT not read")
	assert(RPF.gear.slots[356][1].count == 18, "the lure count isn't read")
	local strip = RPF.gearStrip
	strip:SetSkill(185)
	assert(strip.buttons[3]:IsShown(), "Cooking has no third slot")
	strip.buttons[2].__scripts.OnEnter(strip.buttons[2])
	assert(GameTooltip.__text == "Hat slot", "a kind's slot tooltip: " .. tostring(GameTooltip.__text))
	assert(table.concat(tipLines, "\n"):find("Shared by every character on your account"), "no account line")
	RPF.HideItemTooltip()
	strip:SetSkill(356)
	local lure = strip.buttons[2]
	assert(lure:IsShown() and lure.entry == 6529 and tostring(lure.count.__text) == "18", "the lure slot")
	lure.__scripts.OnEnter(lure)
	assert(table.concat(tipLines, "\n"):find("one goes on it from here"), "lure slot tooltip: " .. table.concat(tipLines, " | "))
	RPF.HideItemTooltip()
	GameTooltip:SetOwner(UIParent)
	GameTooltip:SetHyperlink("item:90801")
	assert(countOf(tipLines, "Tailoring Accessory: Needles") == 1, "accessory kind in the tooltip: " .. table.concat(tipLines, " | "))
	GameTooltip:Hide()
	strip:SetSkill(M.skill)
	gearSlots = { { 197, 0, 90800, 5001 } }
	helloFlags = 63
	RPF.SayHello()
	tick(1)
end)

step("gear: Finesse procs go in the proc log", function ()
	local L = RPF.ProcLog
	L.Clear()
	reply("PG:0:182:F:2447*2")
	local s = L.Session()
	assert(s.F.procs == 1 and s.F.items == 2 and s.M.procs == 0, "finesse not counted")
	local e = L.Entries()[#L.Entries()]
	assert(e and e.kind == "F" and L.EntryText(e):find("Finesse|r Herbalism: %+2x "), e and L.EntryText(e))
	assert(L.Describe("F", "2447*2") == "Finesse! +2 Peacebloom", L.Describe("F", "2447*2"))
	SlashCmdList.RETAILPROFESSIONS("log")
	assert(textShown("Finesse:|r 1 proc, %+2 items"), "no Finesse summary")
	SlashCmdList.RETAILPROFESSIONS("log")
	L.Clear()
end)

step("gear: a realm without it hides the slots again", function ()
	helloFlags = 31
	RPF.SayHello()
	tick(1)
	assert(not RPF.Gear.Enabled() and not RPF.gearStrip:IsShown() and next(RPF.gear.catalog) == nil, "gear stayed")
	assert(not RPF.Home.Shown("equipment"), "the Equipment tab stays without gear")
	RPF.Home.SetActive("equipment")
	assert(RPF.Home.view ~= "equipment", "Equipment opens without gear")
	RPF.Select(M.bySpell[2963])
	assert(M.PerksOf(M.bySpell[2963]).multicraft == 25, "gear still counted in the perk odds")
end)

step("closing the window closes the trade skill", function ()
	local before = closedTradeSkill
	RPF.enchantTarget = { id = 2589, bag = 0, slot = 1 }
	local search = find(function (f) return f.__kind == "EditBox" and rawget(f, "hint") end)
	search:SetText("linen")
	RPF.filter.text = "linen"
	RetailProfessionsFrame:Hide()
	assert(RPF.enchantTarget == nil, "the Enchant slot kept its item after closing")
	assert(search:GetText() == "" and RPF.filter.text == "", "the search kept its text after closing")
	assert(closedTradeSkill == before + 1, "CloseTradeSkill not called")
	fire("TRADE_SKILL_CLOSE")
end)

step("classic switch", function ()
	SlashCmdList.RETAILPROFESSIONS("classic")
	fire("TRADE_SKILL_SHOW")
	assert(loadedClassic > 0 and not RetailProfessionsFrame:IsShown(), "classic window not used")
	SlashCmdList.RETAILPROFESSIONS("retail")
	fire("TRADE_SKILL_CLOSE")
end)

-- A stripped stock trainer: the client moves its selection to the first learnable service before
-- every TRAINER_UPDATE, and the stock handler reselects that and scrolls up to it.
step("trainer keeps the picked recipe through a skill-up", function ()
	local services = {}
	for i = 1, 30 do table.insert(services, { "Recipe " .. i, "Apprentice", i % 3 == 0 and "unavailable" or "available" }) end
	local selection = 1
	function GetNumTrainerServices() return #services end
	function GetTrainerServiceInfo(i) local s = services[i]; if s then return s[1], s[2], s[3] end end
	function GetTrainerSelectionIndex() return selection end
	CLASS_TRAINER_SKILL_HEIGHT, CLASS_TRAINER_SKILLS_DISPLAYED = 16, 11
	CreateFrame("Frame", "ClassTrainerFrame")
	local bar = CreateFrame("Slider", "ClassTrainerListScrollFrameScrollBar")
	bar.value = 0
	function bar:GetValue() return self.value end
	function bar:SetValue(v) self.value = v end
	function ClassTrainer_SetSelection(id) ClassTrainerFrame.selectedService = id; selection = id end
	function ClassTrainerFrame_Update() end
	ClassTrainerFrame:SetScript("OnEvent", function (self, event)
		if event == "TRAINER_UPDATE" then
			ClassTrainer_SetSelection(GetTrainerSelectionIndex())
			bar:SetValue((GetTrainerSelectionIndex() - 1) * CLASS_TRAINER_SKILL_HEIGHT)
		end
	end)
	ClassTrainerFrame:RegisterEvent("TRAINER_UPDATE")
	fire("ADDON_LOADED", "Blizzard_TrainerUI")

	bar:SetValue(10 * CLASS_TRAINER_SKILL_HEIGHT)
	ClassTrainer_SetSelection(14)
	selection = 1  -- skill-up
	fire("TRAINER_UPDATE")
	assert(selection == 14 and ClassTrainerFrame.selectedService == 14, "selection jumped to " .. selection)
	assert(bar:GetValue() == 10 * CLASS_TRAINER_SKILL_HEIGHT, "list scrolled to " .. bar:GetValue())

	table.remove(services, 14)  -- trained: it moves to "used", which the default filter hides
	selection = 1
	fire("TRAINER_UPDATE")
	assert(selection == 1, "a trained recipe should leave the stock selection alone")

	ClassTrainer_SetSelection(20)
	services[20][3] = "used"  -- trained with the "used" filter on
	selection = 1
	fire("TRAINER_UPDATE")
	assert(selection == 1, "a just-trained recipe should not be reselected")

	ClassTrainer_SetSelection(25)
	ClassTrainerFrame:Hide()
	ClassTrainerFrame:Show()
	selection = 1
	fire("TRAINER_UPDATE")
	assert(selection == 1, "a closed trainer kept its pick")
end)

print(errors == 0 and "smoke test passed" or (errors .. " error(s)"))
os.exit(errors == 0 and 0 or 1)
