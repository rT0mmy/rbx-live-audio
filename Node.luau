--!strict
--!native

local Value = require(`./Value`)

local Node = {}

export type Desc = {
	Kind: 'Node' | 'Emitter' | 'Crossfade' | 'Send',
	Name: string?,
	Children: { Desc },
	Props: { [string]: any },

	Class: string?, -- Node

	Play: any?, -- Node, AudioPlayer only: boolean or Value spec

	At: string?, -- Emitter: the slot it sits on
	Distance: Value.Points?, -- Emitter: volume over studs
	Angle: Value.Points?, -- Emitter: volume over degrees off its LookVector

	By: string?, -- Crossfade: the parameter it is laid out along
	Track: boolean?, -- Crossfade: pitch each layer by By / its At
	Layers: { Layer }?, -- Crossfade, ascending At
	Speed: any?, -- Crossfade: extra playback speed on every layer
	Volume: any?, -- Crossfade: extra volume on every layer

	Target: string?, -- Send: the named node whose output it carries
}

export type Layer = {
	Asset: string,
	At: number,
	Volume: number,
}

--// Keys a node reads itself rather than passing to its instance
const RESERVED = { Name = true, Play = true }
const EMITTER_RESERVED = { Name = true, At = true, Distance = true, Angle = true }

--[[
	Whether something is a node description

	@param value any
	@return boolean
--]]
function Node.Is(value: any): boolean
	if type(value) ~= 'table' then return false end

	local kind = value.Kind

	return kind == 'Node' or kind == 'Emitter' or kind == 'Crossfade' or kind == 'Send'
end

--[[
	Splits a definition into its properties and its children

	@param where string -- for error messages
	@param def {[any]: any}
	@param reserved {[string]: boolean}
	@return {[string]: any}, {Desc}
--]]
local function split(where: string, def: { [any]: any }, reserved: { [string]: boolean }): ({ [string]: any }, { Desc })
	assert(type(def) == 'table', `{where} - expects a table`)

	local props = {}
	local children = {}

	for key, value in def do
		if type(key) == 'number' then continue end

		assert(type(key) == 'string', `{where} - property keys must be strings`)

		if not reserved[key] then props[key] = value end
	end

	for i, child in ipairs(def) do
		assert(Node.Is(child), `{where} - input {i} is not a node`)
		children[i] = child
	end

	return props, children
end

--[[
	A curve given as { {x, y}, ... }, checked

	@param where string
	@param points any
	@return Points?
--]]
local function points(where: string, value: any): Value.Points?
	if value == nil then return nil end

	--// Reuse Curve's checks; the param name is only for the message
	return Value.Curve(where, value).Points :: Value.Points
end

--[[
	A node that becomes an instance of `class`

	@param class string -- an Audio* class that has an Input pin, an Output pin, or both
	@return (def) -> Desc
--]]
function Node.Of(class: string): ({ [any]: any }) -> Desc
	return function(def)
		local where = `Audio.{string.gsub(class, '^Audio', '')}`
		local props, children = split(where, def, RESERVED)

		if class == 'AudioPlayer' then assert(#children == 0, `{where} - a player has no inputs`) end

		return {
			Kind = 'Node',
			Class = class,
			Name = def.Name,
			Props = props,
			Children = children,
			Play = def.Play,
		}
	end
end

--[[
	Puts what plays into it out into the world. It sits on a slot named at spawn - an Attachment,
	part or model - and a patch can only have emitters at its top level.

	@param def {[any]: any} -- At = slot name; Distance and Angle as { {x, volume}, ... }
	@return Desc
--]]
function Node.Emitter(def: { [any]: any }): Desc
	local props, children = split('Audio.Emitter', def, EMITTER_RESERVED)

	assert(type(def.At) == 'string', 'Audio.Emitter - At must name a slot')
	assert(#children > 0, 'Audio.Emitter - needs something to emit')

	return {
		Kind = 'Emitter',
		Name = def.Name,
		Props = props,
		Children = children,
		At = def.At,
		Distance = points('Audio.Emitter Distance', def.Distance),
		Angle = points('Audio.Emitter Angle', def.Angle),
	}
end

--[[
	Recordings laid out along a parameter; see Crossfade.luau. Each layer is
	{ Asset = id, At = where along By it was recorded, Volume = trim (default 1) }.

	@param def {[any]: any}
	@return Desc
--]]
function Node.Crossfade(def: { [any]: any }): Desc
	assert(type(def) == 'table', 'Audio.Crossfade - expects a table')
	assert(type(def.By) == 'string', 'Audio.Crossfade - By must name a parameter')
	assert(type(def.Layers) == 'table' and #def.Layers > 0, 'Audio.Crossfade - needs at least one layer')
	assert(#def == 0, 'Audio.Crossfade - takes no inputs; its layers are its sources')

	local layers = {}

	for i, layer in def.Layers do
		assert(type(layer.Asset) == 'string', `Audio.Crossfade - layer {i} needs an Asset`)
		assert(type(layer.At) == 'number', `Audio.Crossfade - layer {i} needs a numeric At`)

		layers[i] = { Asset = layer.Asset, At = layer.At, Volume = layer.Volume or 1 }
	end

	table.sort(layers, function(a, b)
		return a.At < b.At
	end)

	for i = 2, #layers do
		assert(layers[i].At > layers[i - 1].At, 'Audio.Crossfade - two layers share an At')
	end

	return {
		Kind = 'Crossfade',
		Name = def.Name,
		Props = {},
		Children = {},
		By = def.By,
		Track = def.Track == true,
		Layers = layers,
		Speed = def.Speed,
		Volume = def.Volume,
	}
end

--[[
	The output of a named node elsewhere in the same patch, played into this parent too - an aux
	send. One signal can then feed two chains, say an exhaust and an intake each with its own tone,
	without a second set of players.

	@param name string -- the Name of a node or crossfade in the patch, not inside this one's parent
	@return Desc
--]]
function Node.Send(name: string): Desc
	assert(type(name) == 'string', 'Audio.Send - needs the name of a node')

	return { Kind = 'Send', Name = nil, Children = {}, Props = {}, Target = name }
end

return Node
