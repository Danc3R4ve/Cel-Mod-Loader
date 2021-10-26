local VERSION = "2021 - 0.4 b1"
--[[
	- 0.4
	> Added global 'Cel' for global modding
--]]

README = [[--< Cel Mod Loader >--
-- Stores data between loaded mods, and loads them on runtime
-- Able to load external mods using this structure:

	GameDirectory/ [folder where .love/.exe is located]
		Mods/
			ModExample/
				mod.lua [required]
		Game.love

-- mod.lua is a required file for every mod, but they can require their own files independently
-- and also store game sprites for added extensibility.]]

local API = {}
Cel = API
engine = {
	Version = VERSION;
	ReadVersion = function(self, compareVersion)
		--/ Reads the version of this object, port this function to use it elsewhere
		local Year, Major, Sub, Build
		local version = (compareVersion or self.Version)
		if self.Version:match"^(%d+) ?%- ?(%d*)%.(%d*) ?b(%d+)$" then
			Year, Major, Sub, Build = version:match"^(%d+) ?%- ?(%d*)%.(%d*) ?b(%d+)$"
		else
			Year, Major, Sub = version:match"^(%d+) ?%- ?(%d*)%.(%d*)$"
		end
		return {
			Year = Year;
			Major = Major;
			Sub = Sub;
			Build = Build; -- It doesn't matter. If it doesn't match, there just won't be one.
		}
	end;
	CheckIsMinimumVersion = function(self, version)
		--/ Decides based on the version of this object, port this function to use it elsewhere
		local v = self:ReadVersion()
		local comp = self:ReadVersion(version)
		if v.Build then
			if comp.Build then
				-- 2021 - 12.2 b1 vs 2021 - 13.0 b0
				local b1 = (v.Year * 1e9) + (v.Major * 1e6) + (v.Sub * 1e3) + v.Build
				local b2 = (comp.Year * 1e9) + (comp.Major * 1e6) + (comp.Sub * 1e3) + comp.Build
				return (b1 >= b2)
			else
				-- apples to oranges
				return false
			end
		else
			local b1 = (v.Year * 1e6) + (v.Major * 1e3) + v.Sub
			local b2 = (comp.Year * 1e6) + (comp.Major * 1e3) + comp.Sub
			return (b1 >= b2)
		end
	end;
	BindCelLuAPIEvent = function(self, Name, Fn)
		if not API[Name] then
			API[Name] = function(...)
				for _,Func in pairs(API.Bindings[Name] or {}) do
					Func(...)
				end
			end
		end
		if type(API[Name]) == 'function' then
			API.Bindings[Name] = API.Bindings[Name] or {}
			table.insert(API.Bindings[Name], Fn)
		end
	end;
	Mods = {};
}
API.Bindings = {}
API.engine = engine
local success
function ReadMods(path)
	if love.filesystem.isFused() then
		--/ is fused, read directly from game's program location
		local dir = path or (love.filesystem.getSourceBaseDirectory())
		success = love.filesystem.mount(dir, "ModEngine")
	else
		error("Cannot run an external mod loader when not fuse-compiled game and not emulated! Use '--fused' command line argument while testing to circumvent this error.")
	end
	local Mods = love.filesystem.getDirectoryItems("ModEngine/Mods")
	if love.filesystem.isDirectory("ModEngine/Mods") then
		if not love.filesystem.exists("ModEngine/Mods/Readme.txt") then
			local file = io.open(love.filesystem.getSourceBaseDirectory().."/Mods/Readme.txt", "w")
			if file then -- make it so readme is not required
				file:write(README)
				file:close()
			end
		end
	end
	local loaded = {}
	local versionTracker = {}
	--/ Loading
	for _,ModName in pairs(Mods) do
		if (not ModName:match"^(.+)%.(.+)$") then
			--/ Folders only
			local mod = require("ModEngine/Mods/" ..ModName.. "/mod")
			if type(mod) == 'table' then -- if it's a table, insert it like a mod
				engine.Mods[ModName] = mod
				--/ check if the version checking function is ported, if not port it
				if mod.Version and (not mod.CheckIsMinimumVersion) then mod.CheckIsMinimumVersion = engine.CheckIsMinimumVersion mod.ReadVersion = engine.ReadVersion end
				--/ if an onload function exists, immediately use it, though there won't be much use for this
				if mod.onload then mod.onload(engine) end
				table.insert(loaded, ModName)
			elseif mod==nil then -- otherwise if nothing is there, throw an error, stating that it wasn't returned as a mod
				error("Mod Load failed for mod: '" ..ModName.. "'.\n\n>> MISSING API TABLE\nmod.lua does not return a table. Please at least add 'return {}' at the end of the code to signify it's a mod.")
			else
				-- return anything other than nil to ignore the error and run it as a script instead of a mod
			end
		end
	end
	--/ Checking Dependencies
	for ModName, mod in pairs(engine.Mods) do
		local check = false -- whether we can proceed with the loading
		if mod.Dependencies then
			for i = 1, #mod.Dependencies do
				local dependent = mod.Dependencies[i]
				--/ is this dependency a string?
				if type(dependent) == 'string' then
					local ModNameDependent,Version = dependent:match"^mod: ?(.-); ?version: ?(.-)$"
					--/ is this dependency a ModName?
					if ModNameDependent and (not engine.Mods[ModNameDependent]) then
						error(string.format("Mod Load failed for mod: %s\n\n>> DEPENDENCY MISSING\nMissing depended mod: '%s'.\nPlease install this mod and restart the engine.\nInstalled Mods: " ..table.concat(Mods, ", "), ModName, ModNameDependent))
					elseif ModNameDependent and engine.Mods[ModNameDependent] and engine.Mods[ModNameDependent].CheckIsMinimumVersion and (not engine.Mods[ModNameDependent]:CheckIsMinimumVersion(Version)) then
						error(string.format("Mod Load failed for mod: %s\n\n>> VERSION MISMATCH\nDepended mod: '%s' is too old for use.\nPlease install the new version and restart the engie.\n\nMinimum version requested: %s\nVersion got: %s", ModName, ModNameDependent, Version, engine.Mods[ModNameDependent].Version))
					end

					--/ is this dependency a Cel Mod Loader version requirement?
					local EngineVersion = dependent:match"^version: ?(.-)$"
					if EngineVersion and (not engine:CheckIsMinimumVersion(EngineVersion)) then
						error(string.format("Mod Load failed for mod: %s\n\n>> VERSION MISMATCH\nCel Mod Loader version %s is too old for this mod.\nVersion requested:%s\nPlease update CelModLoader, or your mod will likely not work properly.", ModName, engine.Version, EngineVersion))
					end
				end
			end
		end
	end
	--/ Init
	for ModName, mod in pairs(engine.Mods) do
		if mod.init then mod.init(engine) end
	end
	--/ Post-init
	for ModName, mod in pairs(engine.Mods) do
		if mod.postinit then mod.postinit(engine) end
	end
end

function ReadResourcePacks(path)
	local Packs = love.filesystem.getDirectoryItems(path or "ModEngine/ResourcePacks")
	table.sort(Packs)
	for i = 1, #Packs do

	end
end

function love.directorydropped(path)
	-- detect if it is mods or a resource pack
	if path:match"Mods$" then
		ReadMods(path)
	elseif path:match"ResourcePacks$" then
		ReadResourcePacks(path)
	end
end
ReadMods()
ReadResourcePacks()

return API
