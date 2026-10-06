--!strict
--!native

local Config = require(`./Config`)
local Node = require(`./Node`)
local Value = require(`./Value`)

local Patch = {}

export type Param = {
	Name: string,
	Default: number,
	Smooth: number, -- per second toward a new target; 0 snaps
	Min: number,
	Max: number,
}

export type Plan = {
	Kind: 'Node' | 'Emitter' | 'Crossfade' | 'Gate' | 'Send',
	Class: string?,
	Name: string?,
	Static: { [string]: any },
	Inputs: { number }, -- plans whose output plays into this one

	Play: boolean?, -- AudioPlayer: a constant play state; nil when bound or left to the default

	At: string?, -- Emitter
	Distance: { [number]: number }?, -- Emitter, as SetDistanceAttenuation takes it
	Angle: { [number]: number }?,

	By: number?, -- Crossfade: param index
	Track: boolean?,
	Layers: { Node.Layer }?,
	Ats: { number }?, -- Crossfade: each layer's At, for the weighting

	Target: string?, -- Send: the name it carries
	Source: number?, -- Send: that node's plan, resolved once the patch is compiled
}

--// A property worked out from parameters. Target is a property name, or one of:
--//   @Play       an AudioPlayer's play state
--//   @Crossfade  every layer of a crossfade at once
--//   @Volume     the patch's own volume, on its gates
export type Binding = {
	Plan: number, -- 0 for @Volume
	Target: string,
	Spec: Value.Spec?,
	Indices: { number },

	Speed: Value.Spec?, -- @Crossfade
	SpeedIndices: { number }?,
	Volume: Value.Spec?,
	VolumeIndices: { number }?,
}

export type Compiled = {
	Name: string,
	Bus: string,
	Priority: number,
	OneShot: boolean,

	Params: { Param },
	ParamIndex: { [string]: number },

	Plans: { Plan },
	Gates: { number }, -- one per top-level node; the voice's volume and fades live on these
	BusGates: { number }, -- the gates that play straight into the bus rather than an emitter
	Bindings: { Binding },
	ByParam: { { number } }, -- [param index] = bindings that read it
	Volume: number, -- the patch's constant volume when it is not bound

	Spatial: boolean,
	Assets: { string },
}

local busByName: { [string]: any } = {}

for _, bus in Config.Buses do
	busByName[bus.Name] = bus
end

--[[
	A curve of { {x, y}, ... } as the dictionary the emitter API takes

	@param points Points?
	@return {[number]: number}?
--]]
local function dictionary(points: Value.Points?): { [number]: number }?
	if not points then return nil end

	local out = {}
	for _, point in points do
		out[point[1]] = point[2]
	end

	return out
end

--[[
	@param def {[any]: any}
	@return Compiled
--]]
function Patch.Compile(def: { [any]: any }): Compiled
	assert(type(def) == 'table', 'Audio.Patch - expects a table')

	local name = if type(def.Name) == 'string' then def.Name else 'Patch'
	local where = `Audio.Patch '{name}'`

	local bus = busByName[def.Bus]
	assert(bus, `{where} - Bus '{tostring(def.Bus)}' is not in Audio Config.Buses`)

	--// ---------------------------------------------------------------- Parameters

	local params: { Param } = {}
	local paramIndex: { [string]: number } = {}
	local names = {}

	for key in def.Params or {} do
		assert(type(key) == 'string', `{where} - parameter names must be strings`)
		table.insert(names, key)
	end

	--// Sorted, so a parameter's index is the same for every compile of the same patch
	table.sort(names)

	for i, key in names do
		local raw = def.Params[key]
		local entry = if type(raw) == 'number' then { Default = raw } else raw

		assert(type(entry) == 'table', `{where} - parameter '{key}' must be a number or a table`)

		local min = entry.Min or -math.huge
		local max = entry.Max or math.huge

		params[i] = {
			Name = key,
			Default = math.clamp(entry.Default or 0, min, max),
			Smooth = entry.Smooth or 0,
			Min = min,
			Max = max,
		}
		paramIndex[key] = i
	end

	local function resolve(spec: Value.Spec): { number }
		local indices = {}

		for i, param in spec.Params do
			local index = paramIndex[param]
			assert(index, `{where} - '{param}' is not one of the patch's Params`)
			indices[i] = index
		end

		return indices
	end

	--// ---------------------------------------------------------------- Plans

	local plans: { Plan } = {}
	local bindings: { Binding } = {}
	local assets: { string } = {}
	local hasCrossfade = false

	local function bind(plan: number, target: string, spec: Value.Spec)
		table.insert(bindings, { Plan = plan, Target = target, Spec = spec, Indices = resolve(spec) })
	end

	local sends: { number } = {}

	local function compile(desc: Node.Desc): number
		assert(desc.Kind ~= 'Emitter', `{where} - an Emitter can only sit at the top of a patch`)

		local index = #plans + 1
		local plan: Plan = {
			Kind = desc.Kind,
			Class = desc.Class,
			Name = desc.Name,
			Static = {},
			Inputs = {},
		}
		plans[index] = plan

		if desc.Kind == 'Send' then
			plan.Target = desc.Target
			table.insert(sends, index)

			return index
		end

		if desc.Kind == 'Crossfade' then
			hasCrossfade = true

			local by = paramIndex[desc.By :: string]
			assert(by, `{where} - Crossfade By '{tostring(desc.By)}' is not one of the patch's Params`)

			plan.By = by
			plan.Track = desc.Track
			plan.Layers = desc.Layers
			local ats = {}

			for i, layer in desc.Layers :: { Node.Layer } do
				table.insert(assets, layer.Asset)
				ats[i] = layer.At
			end

			plan.Ats = ats

			--// The binding fires for any of its params; the layer maths reads the rest directly
			local indices = { by }
			local binding: Binding = { Plan = index, Target = '@Crossfade', Indices = indices }

			for _, key in { 'Speed', 'Volume' } do
				local value = (desc :: any)[key]

				if Value.Is(value) then
					local resolved = resolve(value :: Value.Spec)

					for _, i in resolved do
						table.insert(indices, i)
					end

					if key == 'Speed' then
						binding.Speed = value
						binding.SpeedIndices = resolved
					else
						binding.Volume = value
						binding.VolumeIndices = resolved
					end
				elseif value ~= nil then
					plan.Static[key] = value
				end
			end

			table.insert(bindings, binding)

			return index
		end

		for key, value in desc.Props do
			if Value.Is(value) then
				bind(index, key, value)
			else
				plan.Static[key] = value
			end
		end

		if desc.Class == 'AudioPlayer' then
			local asset = plan.Static.Asset or plan.Static.AssetId
			if type(asset) == 'string' then table.insert(assets, asset) end

			if Value.Is(desc.Play) then
				bind(index, '@Play', desc.Play :: Value.Spec)
			elseif desc.Play ~= nil then
				plan.Play = desc.Play == true
			end
		end

		for _, child in desc.Children do
			table.insert(plan.Inputs, compile(child))
		end

		return index
	end

	--// Each top-level node gets a gate: a fader the voice owns, carrying the patch's volume and
	--// every fade. Under an emitter it sits just inside it; otherwise just before the bus.
	local gates = {}
	local busGates = {}
	local spatial = false

	local function gate(): (number, Plan)
		local index = #plans + 1
		local plan: Plan = { Kind = 'Gate', Class = 'AudioFader', Static = {}, Inputs = {} }

		plans[index] = plan
		table.insert(gates, index)

		return index, plan
	end

	for i, desc in ipairs(def) do
		assert(Node.Is(desc), `{where} - top-level entry {i} is not a node`)

		if desc.Kind == 'Emitter' then
			assert(bus.Spatial, `{where} - has an Emitter but bus '{bus.Name}' is not Spatial`)
			spatial = true

			local emitterIndex = #plans + 1
			local emitter: Plan = {
				Kind = 'Emitter',
				Class = 'AudioEmitter',
				Name = desc.Name,
				Static = {},
				Inputs = {},
				At = desc.At,
				Distance = dictionary(desc.Distance),
				Angle = dictionary(desc.Angle),
			}
			plans[emitterIndex] = emitter

			for key, value in desc.Props do
				if Value.Is(value) then
					bind(emitterIndex, key, value)
				else
					emitter.Static[key] = value
				end
			end

			local gateIndex, gatePlan = gate()
			emitter.Inputs = { gateIndex }

			for _, child in desc.Children do
				table.insert(gatePlan.Inputs, compile(child))
			end
		else
			local gateIndex, gatePlan = gate()
			gatePlan.Inputs = { compile(desc) }

			table.insert(busGates, gateIndex)
		end
	end

	assert(#gates > 0, `{where} - has nothing in it`)

	--// Each send to the node it names
	for _, index in sends do
		local plan = plans[index]
		local source

		for other, candidate in plans do
			if candidate.Name == plan.Target and (candidate.Kind == 'Node' or candidate.Kind == 'Crossfade') then
				assert(source == nil, `{where} - Send '{plan.Target}' names more than one node`)
				source = other
			end
		end

		assert(source, `{where} - Send '{tostring(plan.Target)}' names no node in the patch`)
		plan.Source = source
	end

	local oneShot = def.OneShot == true
	assert(not (oneShot and hasCrossfade), `{where} - a OneShot cannot hold a Crossfade; its layers never end`)

	local volume = 1

	if Value.Is(def.Volume) then
		bind(0, '@Volume', def.Volume)
	elseif def.Volume ~= nil then
		assert(type(def.Volume) == 'number', `{where} - Volume must be a number or a Value`)
		volume = def.Volume
	end

	--// ---------------------------------------------------------------- Index

	local byParam = table.create(#params)
	for i = 1, #params do
		byParam[i] = {}
	end

	for bindingIndex, binding in bindings do
		local seen = {}

		for _, index in binding.Indices do
			if seen[index] then continue end
			seen[index] = true

			table.insert(byParam[index], bindingIndex)
		end
	end

	return {
		Name = name,
		Bus = bus.Name,
		Priority = def.Priority or 1,
		OneShot = oneShot,

		Params = params,
		ParamIndex = paramIndex,

		Plans = plans,
		Gates = gates,
		BusGates = busGates,
		Bindings = bindings,
		ByParam = byParam,
		Volume = volume,

		Spatial = spatial,
		Assets = assets,
	}
end

return Patch
