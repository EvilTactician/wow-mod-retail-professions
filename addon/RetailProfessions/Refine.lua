-- Milling and Prospecting in the profession window. The game only offers them as a spell cast on
-- one stack, with a loot window after every five. Here each herb or ore is a row like a recipe:
-- what it gives (from the server), how many times you can do it, and Mill All. The server does
-- the work, one cast's time per five, and puts the results in your bags; moving, fighting or
-- closing the window stops it.
--
-- A row is shaped like a learned recipe (name, reagents = five of the herb), so the list, the
-- recipe pane, the amount and the reagent bank treat it as one. It has no spell and no trade
-- skill index: `refine` (the kind) and `key` mark it.

local RPF = RetailProfessions
local M = RPF.Model
local R = {}
RPF.Refine = R

local UNITS = 5

R.KINDS = {
	M = { code = "M", spell = 51005, skill = 773, name = "Milling", verb = "Mill", all = "Mill All", did = "Milled",
		ready = "Herbs you can mill", rest = "Other herbs", none = "No herbs here can be milled yet." },
	P = { code = "P", spell = 31252, skill = 755, name = "Prospecting", verb = "Prospect", all = "Prospect All",
		did = "Prospected", ready = "Ore you can prospect", rest = "Other ore", none = "No ore here can be prospected yet." },
}

R.view = nil -- the kind code the window shows instead of recipes
R.job = nil  -- { req, kind, recipe, total, done, gained = { [item] = n }, order = { item }, lastAt }

function R.Kind(code)
	return code and R.KINDS[code] or nil
end

-- The kind, when the realm does it and the player knows the spell.
function R.Known(code)
	local kind = R.KINDS[code]
	if not (kind and RPF.Has(RPF.HELLO_REFINE)) then return nil end
	local name, _, icon = GetSpellInfo(kind.spell)
	if not name then return nil end
	kind.name, kind.texture = name, icon or kind.texture
	-- By name, GetSpellInfo only answers for spells you know.
	return GetSpellInfo(name) and kind or nil
end

-- The kind the window is showing: its profession has to be the open one, and your own.
function R.Active()
	local kind = R.view and R.Known(R.view)
	if kind and M.skill == kind.skill and not M.linked then return kind end
	return nil
end

-- True while the profession a kind belongs to is the one in the window.
function R.IsOpen(kind)
	return RPF.IsOpen() and M.skill == kind.skill and not M.linked
end

-- The herb or ore to select when the view's rows are in (a reagent's source): its key.
R.want = nil

-- item: the herb or ore to land on, or nil for the first.
function R.SetView(code, item)
	R.want = code and item and (code .. ":" .. item) or nil
	if R.view == code then
		if R.want then RPF.Fire("VIEW") end
		return
	end
	R.view = code
	RPF.selected = nil
	RPF.Fire("VIEW")
end

-- A click that opens the profession should land on this view: the window takes it when it opens.
local pending, pendingItem, pendingAt
function R.Pend(code, item)
	pending, pendingItem, pendingAt = code, item, GetTime()
end

RPF.On("SHOW", function ()
	local code = pending and GetTime() - pendingAt < 2 and pending or nil
	R.want = code and pendingItem and (code .. ":" .. pendingItem) or nil
	pending, pendingItem = nil, nil
	if R.view ~= code then
		R.view = code
		RPF.selected = nil
	end
	RPF.Fire("VIEW")
end)

-----------------------------------------
-- what each herb or ore gives, asked once per login

local sources = {}  -- kind code -> { recipe }, or false when the server refused
local byKey = {}
local asked = {}

-- Y rows: "S,item,required skill,name" and then "R,item,result,min,max,chance x100" for each
-- thing it can give, likeliest first.
local function build(code, rows)
	local list, byItem = {}, {}
	for _, row in ipairs(rows) do
		local item = tonumber(row[2])
		if row[1] == "S" and item then
			local r = {
				refine = code, key = code .. ":" .. item, source = item, learned = true, isEnchant = false,
				name = RPF.Unescape(tostring(row[4] or ("Item #" .. item))), reqSkill = tonumber(row[3]) or 0,
				reagents = { { id = item, n = UNITS } }, results = {},
			}
			r.reagents[1].name = r.name
			byItem[item] = r
			byKey[r.key] = r
			table.insert(list, r)
		elseif row[1] == "R" and byItem[item] then
			table.insert(byItem[item].results, { id = tonumber(row[3]) or 0, min = tonumber(row[4]) or 1,
				max = tonumber(row[5]) or 1, chance = tonumber(row[6]) or 0 })
		end
	end
	table.sort(list, function (a, b)
		if a.reqSkill ~= b.reqSkill then return a.reqSkill < b.reqSkill end
		return a.name < b.name
	end)
	return list
end

-- The rows of a kind, or nil while they're on their way (YIELDS fires then).
function R.Sources(code)
	if sources[code] ~= nil then return sources[code] or nil end
	if not RPF.Has(RPF.HELLO_REFINE) or asked[code] then return nil end
	asked[code] = true
	RPF.Request("Y", { code }, function (result, err)
		asked[code] = nil
		sources[code] = result and build(code, result.rows) or false
		RPF.Fire("YIELDS", code)
	end)
	return nil
end

function R.ByKey(key)
	return key and byKey[key] or nil
end

-- A new HELLO (login, or the realm came back): what it gives may have changed.
RPF.On("READY", function ()
	for code in pairs(sources) do
		if not sources[code] then sources[code] = nil end
	end
end)

-----------------------------------------
-- rows for the list

function R.Icon(r)
	return RPF.ItemIcon(r.source) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

function R.SkillTooLow(r)
	return (r.reqSkill or 0) > (M.rank or 0)
end

-- How many times a row can be done now: from the bags, and with the reagent bank's units.
function R.CanDo(r)
	if R.SkillTooLow(r) then return 0, 0 end
	return M.Craftable(r)
end

local function resultName(res)
	local info = RPF.Item(res.id)
	return info and info.name or nil
end

local function matches(r, text)
	if not text then return true end
	if r.name:lower():find(text, 1, true) then return true end
	for _, res in ipairs(r.results) do
		local name = resultName(res)
		if name and name:lower():find(text, 1, true) then return true end
	end
	return false
end

-- state = { text, haveMats }; rows as M.Rows gives them, with `ready` on what can be done now
-- and `note` for the right-hand column.
function R.Rows(state, collapsed)
	local rows = {}
	local kind = R.Active()
	local list = kind and R.Sources(kind.code)
	if not list then return rows end

	local text = state.text and state.text ~= "" and state.text:lower() or nil
	local ready, rest = {}, {}
	for _, r in ipairs(list) do
		if matches(r, text) then
			local bags, withBank = R.CanDo(r)
			if (RetailProfessionsDB.countBank and withBank or bags) > 0 then
				table.insert(ready, r)
			elseif not state.haveMats then
				table.insert(rest, r)
			end
		end
	end

	local function add(name, key, group, isReady)
		if #group == 0 then return end
		-- A search opens every group it found something in.
		local isCollapsed = not text and collapsed[key] or false
		table.insert(rows, { header = name, key = key, count = #group, collapsed = isCollapsed })
		if isCollapsed then return end
		for _, r in ipairs(group) do
			local note = R.SkillTooLow(r) and ("|cffff4040" .. r.reqSkill .. "|r") or nil
			table.insert(rows, { recipe = r, ready = isReady, note = note })
		end
	end
	add(kind.ready, "rf:" .. kind.code .. ":1", ready, true)
	add(kind.rest, "rf:" .. kind.code .. ":2", rest, false)
	return rows
end

function R.EmptyText(filtered)
	local kind = R.Active()
	if not kind then return "" end
	local list = R.Sources(kind.code)
	if list == nil and sources[kind.code] == nil then return "Loading..." end
	if not list then return "The server didn't say what " .. kind.name:lower() .. " gives." end
	return filtered and "Nothing matches. Clear the search or filters." or kind.none
end

-- "2-4" or "1".
function R.CountText(res)
	return res.min == res.max and tostring(res.min) or (res.min .. "-" .. res.max)
end

-- "100%", "25%", "2.5%" from a chance in hundredths of a percent.
function R.ChanceText(res)
	local pct = (res.chance or 0) / 100
	if pct >= 10 or pct == math.floor(pct) then return string.format("%d%%", math.floor(pct + 0.5)) end
	return string.format("%.1f%%", pct)
end

function R.AddTooltipLines(tip, r)
	local kind = R.KINDS[r.refine]
	tip:AddLine(" ")
	tip:AddLine(string.format("%s %d at a time. Needs %s %d.", kind.verb, UNITS, M.skillName or "skill", r.reqSkill or 0),
		1, R.SkillTooLow(r) and 0.3 or 0.82, R.SkillTooLow(r) and 0.3 or 0, true)
	for i, res in ipairs(r.results) do
		if i > 8 then
			tip:AddLine(string.format("and %d more", #r.results - 8), 0.6, 0.6, 0.6)
			break
		end
		tip:AddDoubleLine(R.CountText(res) .. " " .. (resultName(res) or ("Item #" .. res.id)), R.ChanceText(res),
			1, 1, 1, 0.7, 0.7, 0.7)
	end
end

-----------------------------------------
-- the job

local WHY = {
	stopped = "Stopped.",
	moved = "Stopped: you moved.",
	combat = "Stopped: you're in combat.",
	occupied = "Stopped: you started something else.",
	dead = "Stopped.",
	full = "Your bags are full. What didn't fit is in your mailbox.",
	skill = "Your skill is too low for that.",
	spell = "You haven't learned that.",
	none = "You need 5 of them in your bags.",
	bad = "That can't be done here.",
	off = "This realm doesn't do that from the window.",
	busy = "The server is busy. Try again.",
}

local function gainedText(job)
	local parts = {}
	for i, id in ipairs(job.order) do
		if i > 4 then
			table.insert(parts, "...")
			break
		end
		local info = RPF.Item(id)
		table.insert(parts, job.gained[id] .. " " .. (info and info.name or ("item " .. id)))
	end
	return table.concat(parts, ", ")
end

local function watch(job)
	-- The end of a job could get lost (a reload, a dropped message): don't wait on it forever.
	local limit = job.castTime * 3 + 10
	RPF.After(limit, function ()
		if R.job == job and GetTime() - job.lastAt >= limit then
			R.job = nil
			RPF.Fire("REFINE")
		end
	end)
end

function R.Start(r, count)
	local kind = R.KINDS[r.refine]
	if not kind or R.job or R.starting then return end
	local token = {}
	R.starting = token
	-- A realm that stopped answering mustn't leave the button dead.
	RPF.After(6, function ()
		if R.starting == token then
			R.starting = nil
			RPF.Fire("REFINE")
		end
	end)
	local req
	req = RPF.Request("X", { kind.code, tostring(r.source), tostring(count) }, function (result, err)
		if R.starting == token then R.starting = nil end
		if not result or result[1] ~= "ok" then
			RPF.Status(WHY[err or ""] or "That didn't work.", true)
			RPF.Fire("REFINE")
			return
		end
		R.job = { req = req, kind = kind, recipe = r, total = tonumber(result[2]) or count, done = 0, gained = {},
			order = {}, castTime = (tonumber(result[3]) or 1000) / 1000, lastAt = GetTime() }
		RPF.StartCountdown(r.key, nil, count)
		RPF.Status(string.format("%s %s: 0 of %d...", kind.name, r.name, R.job.total))
		watch(R.job)
		RPF.Fire("REFINE")
	end)
end

function R.Stop()
	if R.job then RPF.Request("XS", {}) end
end

RPF.On("REFINE_PROGRESS", function (req, fields)
	local job = R.job
	if not job or job.req ~= req then return end
	job.done = tonumber(fields[1]) or job.done
	job.total = tonumber(fields[2]) or job.total
	job.lastAt = GetTime()
	for entry, n in (fields[3] or ""):gmatch("(%d+)%*(%d+)") do
		local id = tonumber(entry)
		if not job.gained[id] then table.insert(job.order, id) end
		job.gained[id] = (job.gained[id] or 0) + tonumber(n)
	end
	RPF.Status(string.format("%s %s: %d of %d...", job.kind.name, job.recipe.name, job.done, job.total))
	-- The amount counts down as the casts finish (Frame.lua), so after a stop Mill does only
	-- what's left.
	RPF.CountdownLeft(job.recipe.key, job.total - job.done)
	watch(job)
end)

RPF.On("REFINE_END", function (req, fields)
	local job = R.job
	if not job or job.req ~= req then return end
	R.job = nil
	local done, why = tonumber(fields[1]) or job.done, fields[3] or "done"
	-- Running out is how Mill All ends when the last stack came up short.
	local text = (why ~= "done" and not (why == "none" and done > 0)) and WHY[why] or nil
	if done > 0 then
		local summary = string.format("%s %d x %s: %s.", job.kind.did, done * UNITS, job.recipe.name, gainedText(job))
		text = text and (text .. " " .. summary) or summary
	end
	RPF.Status(text or WHY.stopped, why == "full" or why == "skill" or why == "spell")
	RPF.Fire("REFINE")
end)

-- Closing the window ends it, as walking away would.
RPF.On("HIDDEN", function () R.Stop() end)
