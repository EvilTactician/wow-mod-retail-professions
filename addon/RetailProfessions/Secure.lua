-- Opening a profession means casting its spell, which only a secure button may do. Secure
-- buttons can't be shown, hidden or moved in combat, and neither can the frames they sit in,
-- so ours belong to UIParent and lie invisibly over the drawn tabs and buttons of our windows.
-- The windows themselves stay ordinary frames that open and close at any time. The buttons
-- follow the windows out of combat and step aside when combat starts.

local RPF = RetailProfessions

local buttons = {}
-- Set from PLAYER_REGEN_DISABLED on: InCombatLockdown() is still false while that event is
-- handled, and nothing may show the buttons again until combat ends.
local combat = false

-- A clickable area that casts `spell` (a localized name) over `region` while `region` shows.
function RPF.CreateSpellButton(name)
	local b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
	b:RegisterForClicks("AnyUp")
	b:SetAttribute("type", "spell")
	b:Hide()
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(b)
	hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	hl:SetBlendMode("ADD")
	b.highlight = hl
	b:SetScript("OnEnter", function (self) if self.onEnter then self.onEnter(self) end end)
	-- Runs before the cast, so what the cast opens can already know about it.
	b:SetScript("PreClick", function (self) if self.preClick then self.preClick(self) end end)
	b:SetScript("OnLeave", function (self)
		GameTooltip:Hide()
		if self.onLeave then self.onLeave(self) end
	end)
	table.insert(buttons, b)
	return b
end

-- Points a button at a region and a spell; nil spell or region retires it. `host` is the window
-- the region belongs to: the button takes its strata and sits just above it, so anything opened
-- over the window covers the button too. `defer` leaves the RPF.SyncSpellButtons to the caller,
-- for binding many at once.
function RPF.BindSpellButton(b, region, spell, host, defer)
	b.region, b.spell, b.host = region, spell, host
	if not defer then RPF.SyncSpellButtons() end
end

-- Only what changed is set: a whole page of buttons re-placed at once was a hitch.
local function place(b)
	local region = b.region
	local scale = region:GetEffectiveScale() / UIParent:GetEffectiveScale()
	local left, top = region:GetLeft(), region:GetTop()
	if not (left and top) then return false end
	local strata = b.host and b.host:GetFrameStrata()
	if strata and strata ~= b:GetFrameStrata() then b:SetFrameStrata(strata) end
	local level = region:GetFrameLevel() + 3
	if level ~= b:GetFrameLevel() then b:SetFrameLevel(level) end
	local x, y, w, h = left * scale, top * scale, region:GetWidth() * scale, region:GetHeight() * scale
	local at = b.placed
	if not at or at[1] ~= x or at[2] ~= y then
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
	end
	if not at or at[3] ~= w or at[4] ~= h then b:SetSize(w, h) end
	b.placed = { x, y, w, h }
	return true
end

-- The window is being dragged (or was a moment ago): redrawing waits.
function RPF.Dragging()
	return (RPF.MovedAt or 0) > GetTime() - 0.3 and IsMouseButtonDown("LeftButton")
end

function RPF.SyncSpellButtons()
	if combat or InCombatLockdown() then return end
	for _, b in ipairs(buttons) do
		if b.region and b.spell and b.region:IsVisible() and place(b) then
			b:SetAttribute("spell", b.spell)
			b:Show()
		else
			b:Hide()
		end
	end
end

RPF.On("COMBAT", function (entering)
	if entering then
		-- PLAYER_REGEN_DISABLED is the last moment before the lockdown.
		combat = true
		for _, b in ipairs(buttons) do b:Hide() end
		RPF.Fire("SECURE_STATE", false)
	else
		combat = false
		RPF.SyncSpellButtons()
		RPF.Fire("SECURE_STATE", true)
	end
end)

-- A window rises above others when clicked (SetToplevel); its buttons have to rise with it.
function RPF.FollowRaises(window)
	window:HookScript("OnMouseDown", function () RPF.Debounce("secure", 0.05, RPF.SyncSpellButtons) end)
end

function RPF.InCombat()
	return combat or InCombatLockdown()
end
