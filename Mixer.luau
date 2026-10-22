--!nonstrict
--!native

--// The audio bus graph
--//
--//   voice gates ─┬─> [emitter] ··· bus listener (on the camera) ─┐
--//                └──────────────────────────────────────────────┴─> bus input
--//   bus input -> [its Chain] -> [its duck compressor] -> bus fader -> parent ... Master
--//   Master -> compressor -> device output
--//
--// A bus that Ducks under another has a compressor whose sidechain hears that bus: when it is
--// loud, this one is pushed down.

local RunService = game:GetService('RunService')
local SoundService = game:GetService('SoundService')

local Config = require(`./Config`)
local Profiler = require(`@game/ReplicatedStorage/Modules/Shared/Profiler`)

local Mixer = {}

export type Bus = {
	Name: string,
	Fader: AudioFader,
	Input: Instance, -- where voices and the listener play in: the first of its chain, or its fader
	Ducker: AudioCompressor?, -- on a bus that ducks under another
	DuckBy: string?,
	Listener: AudioListener?, -- spatial buses only
	Group: string?, -- spatial buses only
	Spatial: boolean,
	Cap: number?,
	Volume: number,
	Voices: { [any]: boolean },
}

local mounted = false
local root: Folder
local voiceFolder: Folder
local buses: { [string]: Bus } = {}
local voices: { [any]: boolean } = {}

--// Volumes asked for before the mixer was mounted
local pendingVolumes: { [string]: number } = {}

local budgetClock = 0
local ranked = {}
local scores = {}

--[[
	Connects one node's output to another's input

	@param source Instance
	@param target Instance
	@param parent Instance -- where the wire lives; it goes when this does
	@param pin string? -- the target pin; Input by default
	@return Wire
--]]
function Mixer.Wire(source: Instance, target: Instance, parent: Instance, pin: string?): Wire
	local wire = Instance.new('Wire')
	wire.SourceInstance = source
	wire.TargetInstance = target
	if pin then wire.TargetName = pin end
	wire.Parent = parent

	return wire
end

--[[
	Re-ranks every bus and tells each voice whether it sounds

	@return nil
--]]
local function budget()
	for _, bus in buses do
		local count = 0

		for voice in bus.Voices do
			if voice.Dying then continue end

			local audibility = if bus.Spatial then voice:_Audibility(bus.Listener) else 1
			local score = if audibility < Config.Inaudible then 0 else audibility * voice.Patch.Priority

			if voice.Real then
				score *= Config.Stickiness
			end

			count += 1
			ranked[count] = voice
			scores[voice] = score
		end

		if count == 0 then continue end

		table.sort(ranked, function(a, b)
			return scores[a] > scores[b]
		end)

		local cap = bus.Cap or math.huge

		for i = 1, count do
			local voice = ranked[i]
			voice:_SetReal(scores[voice] > 0 and i <= cap)
		end

		table.clear(ranked)
		table.clear(scores)
	end
end

--[[
	@param deltaTime number
	@return nil
--]]
local function step(deltaTime: number)
	Profiler.Begin('Audio')

	local now = os.clock()

	budgetClock += deltaTime
	if budgetClock >= Config.BudgetPeriod then
		budgetClock = 0
		budget()
	end

	--// A voice that tears itself down removes its own key, which is safe mid-traversal
	for voice in voices do
		voice:_Step(deltaTime, now)
	end

	Profiler.End()
end

--[[
	Keeps every bus listener on whatever camera is current

	@return nil
--]]
local function followCamera()
	local camera = workspace.CurrentCamera
	if not camera then return end

	for _, bus in buses do
		if bus.Listener then bus.Listener.Parent = camera end
	end
end

--[[
	Builds the bus graph and starts the loop. Safe to call more than once.

	@return nil
--]]
function Mixer.Mount()
	if mounted then return end
	assert(RunService:IsClient(), 'Audio - voices can only play on the client')

	mounted = true

	root = Instance.new('Folder')
	root.Name = Config.FolderName

	local mix = Instance.new('Folder')
	mix.Name = 'Mix'
	mix.Parent = root

	voiceFolder = Instance.new('Folder')
	voiceFolder.Name = 'Voices'
	voiceFolder.Parent = root

	local device = Instance.new('AudioDeviceOutput')
	device.Name = 'Output'
	device.Parent = mix

	local compressor = Instance.new('AudioCompressor')
	compressor.Name = 'MasterCompressor'
	for key, value in Config.Master do
		compressor[key] = value
	end
	compressor.Parent = mix

	Mixer.Wire(compressor, device, mix)

	for _, def in Config.Buses do
		local parent = def.Parent and buses[def.Parent]
		assert(
			def.Parent == nil or parent,
			`Audio Config - bus '{def.Name}' is listed before its parent '{def.Parent}'`
		)

		local volume = pendingVolumes[def.Name] or 1

		local fader = Instance.new('AudioFader')
		fader.Name = def.Name
		fader.Volume = math.clamp(volume, 0, 3)
		fader.Parent = mix

		Mixer.Wire(fader, if parent then parent.Input else compressor, mix)

		--// The bus's own processing, in order, then its duck, then its fader
		local stages = {}

		for i, stage in def.Chain or {} do
			local instance = Instance.new(stage.Class)
			instance.Name = `{def.Name}_{i}_{stage.Class}`

			for key, value in stage do
				if key ~= 'Class' then (instance :: any)[key] = value end
			end

			instance.Parent = mix
			table.insert(stages, instance)
		end

		local ducker

		if def.Duck then
			ducker = Instance.new('AudioCompressor')
			ducker.Name = `{def.Name}_Duck`

			for key, value in Config.Duck do
				(ducker :: any)[key] = value
			end

			ducker.Parent = mix
			table.insert(stages, ducker)
		end

		for i = 1, #stages - 1 do
			Mixer.Wire(stages[i], stages[i + 1], mix)
		end

		if #stages > 0 then Mixer.Wire(stages[#stages], fader, mix) end

		local bus: Bus = {
			Name = def.Name,
			Fader = fader,
			Input = stages[1] or fader,
			Ducker = ducker,
			DuckBy = def.Duck,
			Spatial = def.Spatial == true,
			Cap = def.Voices,
			Volume = volume,
			Voices = {},
		}

		if bus.Spatial then
			bus.Group = Config.GroupPrefix .. def.Name

			local listener = Instance.new('AudioListener')
			listener.Name = `Listener_{def.Name}`
			listener.AudioInteractionGroup = bus.Group

			Mixer.Wire(listener, bus.Input, mix)

			bus.Listener = listener
		end

		buses[def.Name] = bus
	end

	--// Ducking, once every bus exists: the ducking bus's output drives the compressor's sidechain
	for _, bus in buses do
		if not bus.Ducker then continue end

		local by = buses[bus.DuckBy]
		assert(by, `Audio Config - bus '{bus.Name}' ducks under '{bus.DuckBy}', which is not a bus`)

		Mixer.Wire(by.Fader, bus.Ducker, mix, 'Sidechain')
	end

	table.clear(pendingVolumes)

	root.Parent = SoundService
	followCamera()

	workspace:GetPropertyChangedSignal('CurrentCamera'):Connect(followCamera)
	RunService:BindToRenderStep('Audio', Enum.RenderPriority.Last.Value, step)
end

--[[
	@param name string
	@return Bus
--]]
function Mixer.Bus(name: string): Bus
	Mixer.Mount()

	local bus = buses[name]
	assert(bus, `Audio - no bus named '{name}'`)

	return bus
end

--[[
	@return Folder -- where voices keep their instances
--]]
function Mixer.VoiceFolder(): Folder
	Mixer.Mount()

	return voiceFolder
end

--[[
	Takes a new voice on and says whether it may sound straight away, which is whenever its bus has room

	@param voice Voice
	@return boolean
--]]
function Mixer.Add(voice): boolean
	local bus = voice.Bus

	voices[voice] = true
	bus.Voices[voice] = true

	return Mixer.HasRoom(bus)
end

--[[
	Whether one more voice may sound on a bus right now

	@param bus Bus
	@return boolean
--]]
function Mixer.HasRoom(bus: Bus): boolean
	if not bus.Cap then return true end

	local sounding = 0
	for other in bus.Voices do
		if other.Real and not other.Dying then
			sounding += 1
		end
	end

	return sounding < bus.Cap
end

--[[
	@param voice Voice
	@return nil
--]]
function Mixer.Remove(voice)
	voices[voice] = nil
	voice.Bus.Voices[voice] = nil
end

--[[
	A bus's volume, as a multiplier. Settings and snapshots both land here.

	@param name string
	@param volume number -- 0..3
	@return nil
--]]
function Mixer.SetVolume(name: string, volume: number)
	if not mounted then
		pendingVolumes[name] = volume
		return
	end

	local bus = buses[name]
	assert(bus, `Audio - no bus named '{name}'`)

	bus.Volume = volume
	bus.Fader.Volume = math.clamp(volume, 0, 3)
end

--[[
	@param name string
	@return number
--]]
function Mixer.GetVolume(name: string): number
	if not mounted then return pendingVolumes[name] or 1 end

	local bus = buses[name]
	assert(bus, `Audio - no bus named '{name}'`)

	return bus.Volume
end

--[[
	A snapshot of the mix, for debugging

	@return {Buses: {any}, Voices: {any}}
--]]
function Mixer.Inspect()
	local out = { Buses = {}, Voices = {} }

	for _, def in Config.Buses do
		local bus = buses[def.Name]
		if not bus then continue end

		local total, real = 0, 0
		for voice in bus.Voices do
			total += 1
			if voice.Real then
				real += 1
			end
		end

		table.insert(
			out.Buses,
			{ Name = bus.Name, Volume = bus.Volume, Voices = total, Sounding = real, Cap = bus.Cap }
		)
	end

	for voice in voices do
		table.insert(out.Voices, voice:Inspect())
	end

	return out
end

return Mixer
