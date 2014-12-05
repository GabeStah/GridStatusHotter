--[[--------------------------------------------------------------------
	GridStatusHotter.lua
----------------------------------------------------------------------]]

local _, GridStatusHotter = ...

local 	_G, _ = 
		_G, _
local 	table, 	tinsert, 		tremove, 		tContains, wipe, sort, date, time, random = 
		table, 	table.insert, 	table.remove, 	tContains, wipe, sort, date, time, random
local 	math, tostring, string, strjoin, 		strlower, 		strsplit, 		strsub, 	strtrim, 		strupper, 		floor, 		tonumber, format = 
		math, tostring, string, string.join, 	string.lower, 	string.split, 	string.sub, string.trim, 	string.upper, 	math.floor, tonumber, string.format
local 	select, pairs, print, next, type, unpack = 
		select, pairs, print, next, type, unpack
local 	loadstring, assert, error = 
		loadstring, assert, error

if not GridStatusHotter.L then GridStatusHotter.L = { } end

local L = setmetatable(GridStatusHotter.L, {
	__index = function(t, k)
		t[k] = k
		return k
	end
})

local GridRoster = Grid:GetModule("GridRoster")
local GridStatusHotter = Grid:GetModule("GridStatus"):NewModule("GridStatusHotter", "AceTimer-3.0")

GridStatusHotter.menuName = L["Hotter"];
GridStatusHotter.defaultDB = {}

GridStatusHotter.data = {}
GridStatusHotter.updateTimer = nil

local UPDATE_FREQUENCY = 0.1

--[[
TODO: Add "duration threshold" option.  Show duration by default if duration is less than threshold duration, otherwise hide duration
]]
local TRACKED_SPELLS = {
	[774] = { class = 'DRUID', name = L['Rejuvenation'], },
	[8936] = { class = 'DRUID', name = L['Regrowth'], },
	[33763] = {
		class = 'DRUID',	
		defaultOptions = {
			colorByStack = true,
			threshold2 = 8,
			threshold3 = 1,
		},
		name = L['Lifebloom'],		
	},
	[48438] = { class = 'DRUID', name = L['Wild Growth'], },
	[115175] = {
		class = 'MONK',	
		defaultOptions = {
			threshold2 = 5,
			threshold3 = 1,
		},
		name = L['Soothing Mist'],
	},
	[155777] = {
		class = 'DRUID',	
		defaultOptions = {
			threshold2 = 5,
			threshold3 = 1,
		},
		name = L['Rejuvenation (Germination)'],
	},
	[116849] = {
		class = 'MONK',	
		defaultOptions = {
			threshold2 = 8,
			threshold3 = 4,
		},
		name = L['Life Cocoon'],
	},
	[119611] = {
		class = 'MONK',
		defaultOptions = {
			stackOffset = -1,
			stacks = true,
		},		
		name = L['Renewing Mist'],
	},	
	[124081] = {
		class = 'MONK',
		defaultOptions = {
			threshold2 = 6,
			threshold3 = 3,
		},
		name = L['Zen Sphere'],
	},	
	[132120] = {
		class = 'MONK',	
		defaultOptions = {
			threshold2 = 3,
			threshold3 = 1,
		},
		name = L['Enveloping Mist'],		
	},	
	[20925] = { class = 'PALADIN', name = L['Sacred Shield'], },	
	[53563] = { class = 'PALADIN', name = L['Beacon of Light'], },
	[114163] = { class = 'PALADIN', name = L['Eternal Flame'], },
	[17] = { class = 'PRIEST', name = L['Power Word: Shield'], },
	[139] = { class = 'PRIEST', name = L['Renew'], },
	[6788] = { class = 'PRIEST', name = L['Weakened Soul'], },
	[41635] = { class = 'PRIEST', name = L['Prayer of Mending'], },
	[77613] = { class = 'PRIEST', name = L['Grace'], },
	[88682] = { class = 'PRIEST', name = L['Holy Word Aspire'], },
	[974] = { 
		defaultOptions = {
			stacks = true,
		},
		class = 'SHAMAN',
		name = L['Earth Shield'], 
	},
	[51945] = { class = 'SHAMAN', name = L['Earthliving'], },
	[61295] = { 
		class = 'SHAMAN', name = L['Riptide'], 
	},
}

local DEFAULT_STATUS_OPTIONS = {
	stacks = false,
	colorByStack = false,
	decimal = false,
	durationThreshold = 30,
	enable = true,
	priority = 99,
	range = false,
	threshold2 = 10,
	threshold3 = 5,
	color = { r = 0, g = 1, b = 0, a = 1 },
	color2 = { r = 1, g = 1, b = 0, a = 1 },
	color3 = { r = 1, g = 0, b = 0, a = 1 },
}	

local MAX_AURA_COUNT = 40
local ACTIVE_SPELLS = {};

function GridStatusHotter:CreateDefaultOptions()
	for ID,v in pairs(TRACKED_SPELLS) do
		local name = self:GetStatusID(ID)
		GridStatusHotter.defaultDB[name] = self:GetDefaultOptions(ID)
	end
end

function GridStatusHotter:GetActiveSpellData(spellID)
	for ID,v in pairs(ACTIVE_SPELLS) do
		if ID == spellID then return v end
	end
	return nil
end

function GridStatusHotter:GetDefaultOptions(spellID)
	if not TRACKED_SPELLS[spellID] then return end
	local options = {};
	for i,v in pairs(DEFAULT_STATUS_OPTIONS) do options[i] = v end
	if TRACKED_SPELLS[spellID].defaultOptions then
		for i,v in pairs(TRACKED_SPELLS[spellID].defaultOptions) do
			options[i] = v
		end
	end
	return options
end

function GridStatusHotter:GetOption(spellID, key)
	local name = self:GetStatusID(spellID)
	if not self.db.profile[name] then return end
	if key == 'threshold2' then
		return {
			type = "range",
			name = L["Threshold 2"],
			desc = L['Seconds remaining to activate "Color 2".'],
			max = 30,
			min = 1,
			step = .5,
			get = function ()
				return GridStatusHotter.db.profile[name][key]
			end,
			set = function (_, v)
				GridStatusHotter.db.profile[name][key] = v
			end,
		}		
	elseif key == 'color2' then
		return {
			type = "color",
			name = L["Color 2"],
			desc = L['Color when time remaining is less than or equal to "Threshold 2" seconds.'],
			hasAlpha = true,
			get = function ()
				local color = GridStatusHotter.db.profile[name][key]
				return color.r, color.g, color.b, color.a
			end,
			set = function (_, r, g, b, a)
				local color = GridStatusHotter.db.profile[name][key]
				color.r = r
				color.g = g
				color.b = b
				color.a = a or 1
			end,
		}
	elseif key == 'threshold3' then
		return {
			type = "range",
			name = L["Threshold 3"],
			desc = L['Seconds remaining to activate "Color 3".'],
			max = 30,
			min = 1,
			step = .5,
			get = function ()
				return GridStatusHotter.db.profile[name][key]
			end,
			set = function (_, v)
				GridStatusHotter.db.profile[name][key] = v
			end,
		}		
	elseif key == 'color3' then
		return {
			type = "color",
			name = L["Color 3"],
			desc = L['Color when time remaining is less than or equal to "Threshold 3" seconds.'],
			hasAlpha = true,
			get = function ()
				local color = GridStatusHotter.db.profile[name][key]
				return color.r, color.g, color.b, color.a
			end,
			set = function (_, r, g, b, a)
				local color = GridStatusHotter.db.profile[name][key]
				color.r = r
				color.g = g
				color.b = b
				color.a = a or 1
			end,
		}	
	elseif key == 'stacks' then
		return {
			type = "toggle",
			name = L["Show Stacks"],
			desc = L["Enable to display the number of stacks of the aura if applicable."],
			get = function () return GridStatusHotter.db.profile[name][key] end,
			set = function (_, arg)
				GridStatusHotter.db.profile[name][key] = arg
			end,
		}
	elseif key == 'colorByStack' then
		return {
			type = "toggle",
			name = L["Color by Stack"],
			desc = L["Enable colorization to match stack count instead of duration threshold."],
			get = function () return GridStatusHotter.db.profile[name][key] end,
			set = function (_, arg)
				GridStatusHotter.db.profile[name][key] = arg
			end,
		}
	elseif key == 'decimal' then
		return {
			type = "toggle",
			name = L["Show decimals"],
			desc = L["Check, if you want to see one decimal place (i.e. 7.1)"],
			get = function () return GridStatusHotter.db.profile[name][key] end,
			set = function (_, arg)
				GridStatusHotter.db.profile[name][key] = arg
			end,
		}
	elseif key == 'durationThreshold' then
		return {
			type = "range",
			name = L["Duration Threshold"],
			desc = L['Durations that exceed this threshold (in seconds) will be hidden until the duration threshold is met.'],
			max = 600,
			min = 0,
			step = 0.5,
			get = function ()
				return GridStatusHotter.db.profile[name][key]
			end,
			set = function (_, v)
				GridStatusHotter.db.profile[name][key] = v
			end,
		}	
	end
end

function GridStatusHotter:GetOptions(spellID)
	local data = TRACKED_SPELLS[spellID]
	if not data then return end
	local options = {}
	for i,v in pairs(DEFAULT_STATUS_OPTIONS) do
		local opt = self:GetOption(spellID, i)
		options[i] = opt
	end
	return options
end

function GridStatusHotter:GetStatusID(spellID)
	return ('%s%s'):format(strlower(gsub(TRACKED_SPELLS[spellID].name, ' ', '')), tostring(spellID))
end

function GridStatusHotter:Grid_UnitJoined(guid, unitID)
	self:UpdateUnit(guid, unitID)
end

function GridStatusHotter:OnEnable()
	self.updateTimer = self:ScheduleRepeatingTimer('UpdateAllUnits', UPDATE_FREQUENCY)
	--self.memoryTimer = self:ScheduleRepeatingTimer('GetMemoryUsage', 5)
end

function GridStatusHotter:GetMemoryUsage()
	UpdateAddOnMemoryUsage()
	print(('Memory: %sk'):format(math.floor(GetAddOnMemoryUsage('GridStatusHotter') + 0.5)))
end

function GridStatusHotter:OnInitialize()
	self:CreateDefaultOptions()
	self.super.OnInitialize(self)
	self:Register()
end

function GridStatusHotter:Register()
	local class = select(2, UnitClass('player'))
	for ID,v in pairs(TRACKED_SPELLS) do
		if (not v.class) or (v.class and v.class == class) then
			self:RegisterStatus(self:GetStatusID(ID), ('%s: %s'):format('Hotter', v.name), self:GetOptions(ID))
			ACTIVE_SPELLS[ID] = {}
		end
	end
end

function GridStatusHotter:Reset()
	self.super.Reset(self)

	self:Unregister()
	self:Register()
	self:UpdateAllUnits()
end

function GridStatusHotter:SetUnitAuraInfo(auraID, guid, unitID)
	local currentTime = GetTime();
	self.data.valid = false
	if not TRACKED_SPELLS[auraID] or not TRACKED_SPELLS[auraID].name then return end
	local name, count, expirationTime, unitCaster, spellID
	name, _, _, count, _, _, expirationTime, unitCaster, _, _, spellID = UnitAura(unitID, TRACKED_SPELLS[auraID].name)
	if not name then
		name, _, _, count, _, _, expirationTime, unitCaster, _, _, spellID = UnitAura(unitID, TRACKED_SPELLS[auraID].name, nil, 'HARMFUL')
	end
	if not name then return end
	if auraID == spellID and unitCaster == 'player' then
		self.data.valid = true
		self.data.timeLeft = expirationTime - currentTime;
		self.data.timeExpires = expirationTime;
		self.data.unitCaster = unitCaster;
		self.data.stacks = count;
	end
end

function GridStatusHotter:Unregister()
	local class = select(2, UnitClass('player'))
	for ID,v in pairs(TRACKED_SPELLS) do
		if (not v.class) or (v.class and v.class == class) then
			self:UnregisterStatus(self:GetStatusID(ID))	
			ACTIVE_SPELLS[ID] = nil
		end
	end	
end

function GridStatusHotter:UpdateAllUnits()
	for guid, unitid in GridRoster:IterateRoster() do
        self:UpdateUnit(guid, unitid)
	end
end

function GridStatusHotter:UpdateUnit(guid, unitID)
	-- Loop active spells
	for ID,v in pairs(ACTIVE_SPELLS) do
		GridStatusHotter:SetUnitAuraInfo(ID, guid, unitID)
		local statusName = self:GetStatusID(ID)
		if self.data.valid and self.data.timeLeft and self.db.profile[statusName].enable then
			local hotcolor = self.db.profile[statusName].color
			-- Stacks
			if self.db.profile[statusName].stackOffset then
				self.data.stacks = self.data.stacks + self.db.profile[statusName].stackOffset
			end
			if self.db.profile[statusName].colorByStack then	
				if self.data.stacks then
					if self.data.stacks == 1 then
						hotcolor = self.db.profile[statusName].color3
					elseif self.data.stacks == 2 then
						if statusName == 'lifebloom33763' then
							print('stacks', self.data.stacks)
						end						
						hotcolor = self.db.profile[statusName].color2
					elseif self.data.stacks == 3 then
						hotcolor = self.db.profile[statusName].color
					end
				end
			else
				if self.data.timeLeft <= self.db.profile[statusName].threshold2 then hotcolor = self.db.profile[statusName].color2 end
				if self.data.timeLeft <= self.db.profile[statusName].threshold3 then hotcolor = self.db.profile[statusName].color3 end
			end
			if self.data.stacks <= 0 then self.data.stacks = nil end
			local showDuration = false
			-- Check if Duration exceeds threshold
			if self.data.timeLeft <= self.db.profile[statusName].durationThreshold then showDuration = true end
			local stackString = showDuration and ('%d'):format(self.data.timeLeft) or ''
			if self.data.stacks and self.db.profile[statusName].stacks and self.db.profile[statusName].decimal then
				stackString = showDuration and ('%d-%.1f'):format(self.data.stacks, self.data.timeLeft) or ('%d'):format(self.data.stacks)
			elseif self.data.stacks and self.db.profile[statusName].stacks then
				stackString = showDuration and ('%d-%d'):format(self.data.stacks, self.data.timeLeft) or ('%d'):format(self.data.stacks)
			elseif self.db.profile[statusName].decimal then
				stackString = showDuration and ('%.1f'):format(self.data.timeLeft) or ''
			end			
			self.core:SendStatusGained(guid, statusName,
				self.db.profile[statusName].priority,
				(self.db.profile[statusName].range and (self.db.profile[statusName].maxRange or 40)),
				hotcolor,
				stackString
			)	
		else
			if self.core:GetCachedStatus(guid,statusName) then self.core:SendStatusLost(guid,statusName) end
		end
	end
end