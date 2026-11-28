--!nonstrict
--!native
local Mock = require('./Mock'); local game, workspace, Instance, Enum, typeof, Vector3, CFrame = Mock.game, Mock.workspace, Mock.Instance, Mock.Enum, Mock.typeof, Mock.Vector3, Mock.CFrame

local Config = require(`./Config`)
local Crossfade = require(`./Crossfade`)
local Mixer = require(`./Mixer`)
local Value = require(`./Value`)

local Voice = {}
Voice.__index = Voice

--[[
	Whether a new value is far enough from the last one written to be worth writing

	@param last any
	@param value any
	@return boolean
--]]
local function changed(last: any, value: any): boolean
	if type(last) == 'number' and type(value) == 'number' then
		--// Zero is written exactly, so a faded-out property really is silent
		if value == 0 then return last ~= 0 end

		return math.abs(value - last) > Config.WriteTolerance * math.max(1, math.abs(last))
	end

	return last ~= value
end

--[[
	A bound value as a play state

	@param value any
	@return boolean
--]]
local function truthy(value: any): boolean
	if type(value) == 'number' then return value > 0.5 end

	return value == true
end

--[[
	Sets a plan's constant properties on its instance, naming the patch if one is wrong

	@param instance Instance
	@param plan Plan
	@param patchName string
	@return nil
--]]
local function applyStatic(instance: Instance, plan, patchName: string)
	for key, value in plan.Static do
		local ok, issue = pcall(function()
			(instance :: any)[key] = value
		end)

		if not ok then error(`Audio.Patch '{patchName}' - {plan.Class}.{key}: {issue}`, 0) end
	end
end

--[[
	Whether a slot entry is a point in the world rather than an instance

	@param at any
	@return boolean
--]]
local function isPoint(at: any): boolean
	local kind = typeof(at)

	return kind == 'Vector3' or kind == 'CFrame'
end

--[[
	A slot as a list of entries, whether it was given as one or many

	@param slot any
	@return any
--]]
local function listOf(slot: any): any
	if typeof(slot) == 'Instance' or isPoint(slot) then return { slot } end

	return slot
end

--[[
	The entries an emitter sits on: instances, and points it will be given attachments for

	@param slots {[string]: Slot | {Slot}}?
	@param name string
	@param patchName string
	@return {Instance | Vector3 | CFrame}
--]]
local function slotOf(slots, name: string, patchName: string): { any }
	local slot = slots and slots[name]
	assert(slot, `Audio.Patch '{patchName}' - spawned without slot '{name}'`)

	local list = listOf(slot)
	assert(type(list) == 'table' and #list > 0, `Audio.Patch '{patchName}' - slot '{name}' is empty`)

	--// An emitter under anything else has no position and is silently never heard
	for _, at in list do
		assert(
			isPoint(at)
				or (typeof(at) == 'Instance' and (at:IsA('Attachment') or at:IsA('PVInstance') or at:IsA('Camera'))),
			`Audio.Patch '{patchName}' - slot '{name}' must be an Attachment, part, model, camera, Vector3 or CFrame`
		)
	end

	--// A copy, as points in it are swapped for the attachments made for them
	return table.clone(list)
end

--[[
	Puts an attachment the voice owns at a point. It lives on Terrain, which sits at the origin, so
	its local placement is its world one.

	@param attachment Attachment
	@param at Vector3 | CFrame
	@return nil
--]]
local function place(attachment: Attachment, at: any)
	if typeof(at) == 'CFrame' then
		attachment.CFrame = at
	else
		attachment.Position = at
	end
end

--[[
	Where a slot entry is, for judging whether a one-shot on it could be heard

	@param at Instance | Vector3 | CFrame
	@return Vector3? -- nil for a camera, which is always in earshot
--]]
local function positionOf(at: any): Vector3?
	local kind = typeof(at)

	if kind == 'Vector3' then return at end
	if kind == 'CFrame' then return at.Position end
	if at:IsA('Attachment') then return at.WorldPosition end
	if at:IsA('BasePart') then return at.Position end
	if at:IsA('Model') then return at:GetPivot().Position end

	return nil
end

--[[
	Whether every emitter of a patch would sit past its distance curve's reach from the listener

	@param patch Compiled
	@param slots {[string]: Instance | {Instance}}?
	@return boolean -- false when unsure, so a malformed slot still reaches Voice.new and its asserts
--]]
local function outOfReach(patch, slots): boolean
	if patch.Reach == math.huge or not slots then return false end

	local camera = workspace.CurrentCamera
	if not camera then return false end

	local listener = camera.CFrame.Position
	local reach = patch.Reach

	local function far(at: any): boolean
		if typeof(at) ~= 'Instance' and not isPoint(at) then return false end

		local position = positionOf(at)

		return position ~= nil and (position - listener).Magnitude > reach
	end

	for _, index in patch.Emitters do
		local list = listOf(slots[patch.Plans[index].At])
		if type(list) ~= 'table' or #list == 0 then return false end

		for _, at in list do
			if not far(at) then return false end
		end
	end

	return true
end

--[[
	A voice that never sounds, handed back for a one-shot that had no chance of being heard. Every
	method on it does nothing.

	@param patch Compiled
	@param bus Bus
	@return Voice
--]]
function Voice.Dead(patch, bus)
	local values = table.create(#patch.Params, 0)

	for i, param in patch.Params do
		values[i] = param.Default
	end

	return setmetatable({
		Patch = patch,
		Bus = bus,
		Alive = false,
		Dying = false,
		Real = false,
		Sounding = false,
		Values = values,
		Nodes = {},
		Named = {},
		Players = {},
		PatchVolume = 0,
		Envelope = 0,
	}, Voice)
end

--[[
	Fires a OneShot patch: a finished voice of it on the same slots if one is spare, a new one if not,
	or a dead one when its bus is full or the listener is out of its reach. Use Patch:Play rather than
	calling this.

	@param patch Compiled
	@param slots {[string]: Instance | {Instance}}?
	@param params {[string]: number}?
	@return Voice
--]]
function Voice.Fire(patch, slots, params)
	local bus = Mixer.Bus(patch.Bus)

	if not Mixer.HasRoom(bus) or outOfReach(patch, slots) then return Voice.Dead(patch, bus) end

	local spare = patch.Spare

	for i = #spare, 1, -1 do
		local voice = spare[i]

		if voice:_SitsOn(slots) then
			table.remove(spare, i)
			voice:_Place(slots)
			voice:_Revive(params)

			return voice
		end
	end

	return Voice.new(patch, slots, params)
end

--[[
	Builds a voice. Use Patch:Spawn rather than calling this.

	@param patch Compiled
	@param slots {[string]: Instance | {Instance}}? -- what each emitter sits on
	@param params {[string]: number}? -- starting values; anything left out takes its default
	@return Voice
--]]
function Voice.new(patch, slots, params)
	local bus = Mixer.Bus(patch.Bus)
	local paramCount = #patch.Params
	local bindingCount = #patch.Bindings

	local self = setmetatable({
		Patch = patch,
		Bus = bus,

		Alive = true,
		Dying = false,
		Parked = false, -- a finished one-shot kept in its patch's Spare
		SlotGone = false, -- something it sits on was destroyed, so it can never be reused
		Real = false, -- the mixer has given it a place
		Counted = false, -- counted in its bus's Sounding; kept by Mixer.Recount
		Sounding = false, -- its players are running; stays true through a fade-out

		Values = table.create(paramCount, 0),
		Targets = table.create(paramCount, 0),
		Dirty = table.create(paramCount, false),
		AnyDirty = false,

		Nodes = table.create(#patch.Plans), -- [plan] = Instance, {AudioEmitter}, or a crossfade's state
		Last = table.create(bindingCount), -- [binding] = the value last written
		Stamp = table.create(bindingCount, 0),
		Frame = 0,

		Players = {}, -- [plan] = whether that AudioPlayer should be playing
		StartWants = {}, -- [plan] = Players as built, for reviving a spare one-shot
		Named = {}, -- [name] = plan, for Play, Stop and Instance
		Crossfades = {}, -- plans
		Emitters = {},
		Slots = {}, -- [emitter plan] = the instances its emitters sit on
		Owned = {}, -- [Attachment] = true for each it made to stand at a point
		Waiting = false, -- a crossfade layer has gone quiet and is due to stop

		PatchVolume = patch.Volume,
		Envelope = 0,
		EnvelopeTarget = 0,
		FadeRate = 0,
		GateDirty = true,

		Remaining = 0, -- OneShot: players still to finish
		StartRemaining = 0,
		Deadline = math.huge,

		Connections = {},
		Folder = nil,
	}, Voice)

	local folder = Instance.new('Folder')
	folder.Name = patch.Name
	self.Folder = folder

	self:_Build(slots, folder)
	self:_Wire(folder)

	self.StartRemaining = self.Remaining
	self:_Reset(params)

	folder.Parent = Mixer.VoiceFolder()

	self:_Begin()

	return self
end

--[[
	Puts every parameter at its starting value and writes every binding once, so the graph starts
	where its parameters are

	@param params {[string]: number}?
	@return nil
--]]
function Voice._Reset(self, params)
	local now = os.clock()

	for i, param in self.Patch.Params do
		local start = params and params[param.Name]
		local value = if type(start) == 'number' then math.clamp(start, param.Min, param.Max) else param.Default

		self.Values[i] = value
		self.Targets[i] = value
		self.Dirty[i] = false
	end

	self.AnyDirty = false

	for index in self.Patch.Bindings do
		self:_Apply(index, now)
	end
end

--[[
	Asks the mixer for a place and starts sounding if it gets one

	@return nil
--]]
function Voice._Begin(self)
	if Mixer.Add(self) then
		self.Real = true
		Mixer.Recount(self)
		self.Envelope = 1
		self.EnvelopeTarget = 1
		self:_Start(os.clock())

		if self.Alive then self:_WriteGates() end
	elseif self.Patch.OneShot then
		self:_Teardown()
	end
end

--[[
	Whether a spare voice can be revived on these slots without reparenting anything: the same
	instances, or points where it has attachments of its own, which only have to move

	@param slots {[string]: Slot | {Slot}}?
	@return boolean
--]]
function Voice._SitsOn(self, slots): boolean
	for index, list in self.Slots do
		local given = listOf(slots and slots[self.Patch.Plans[index].At])
		if type(given) ~= 'table' or #given ~= #list then return false end

		for i, at in given do
			if self.Owned[list[i]] then
				if not isPoint(at) then return false end
			elseif list[i] ~= at then
				return false
			end
		end
	end

	return true
end

--[[
	Moves the attachments the voice made for points to where these slots put them

	@param slots {[string]: Slot | {Slot}}?
	@return nil
--]]
function Voice._Place(self, slots)
	for index, list in self.Slots do
		local given = listOf(slots[self.Patch.Plans[index].At])

		for i, attachment in list do
			if self.Owned[attachment] then place(attachment, given[i]) end
		end
	end
end

--[[
	Brings a spare one-shot back as if it were new; its instances still hold what they were last
	written, so only the properties that differ are written again

	@param params {[string]: number}?
	@return nil
--]]
function Voice._Revive(self, params)
	self.Parked = false
	self.Alive = true
	self.Dying = false
	self.Real = false
	self.Sounding = false

	for index, want in self.StartWants do
		self.Players[index] = want

		--// A player cut short, or run to its end, does not start from the top again on its own
		self.Nodes[index].TimePosition = 0
	end

	self.Remaining = self.StartRemaining
	self.Deadline = math.huge
	self.Waiting = false

	self.PatchVolume = self.Patch.Volume
	self.Envelope = 0
	self.EnvelopeTarget = 0
	self.FadeRate = 0
	self.GateDirty = true

	self:_Reset(params)
	self:_Begin()
end

--[[
	Creates an instance for every plan

	@param slots {[string]: Instance | {Instance}}?
	@param folder Folder
	@return nil
--]]
function Voice._Build(self, slots, folder: Folder)
	local patch = self.Patch

	for index, plan in patch.Plans do
		if plan.Kind == 'Emitter' then
			local emitters = {}
			local list = slotOf(slots, plan.At, patch.Name)

			--// A point gets an attachment of the voice's own, so its emitter has something to sit on
			for i, at in list do
				if not isPoint(at) then continue end

				local attachment = Instance.new('Attachment')
				attachment.Name = `{patch.Name}_{plan.At}`
				place(attachment, at)
				attachment.Parent = workspace.Terrain

				self.Owned[attachment] = true
				list[i] = attachment
			end

			self.Slots[index] = list

			for _, at in list do
				local emitter = Instance.new('AudioEmitter')
				emitter.Name = plan.Name or plan.At
				emitter.AudioInteractionGroup = self.Bus.Group

				if plan.Distance then emitter:SetDistanceAttenuation(plan.Distance) end
				if plan.Angle then emitter:SetAngleAttenuation(plan.Angle) end

				applyStatic(emitter, plan, patch.Name)

				emitter.Parent = at

				table.insert(emitters, emitter)
				table.insert(self.Emitters, emitter)

				if not self.Owned[at] then
					table.insert(
						self.Connections,
						at.Destroying:Connect(function()
							self:_LoseSlot()
						end)
					)
				end
			end

			self.Nodes[index] = emitters
		elseif plan.Kind == 'Send' then
			--// No instance of its own: its parent wires straight to the node it names
			self.Nodes[index] = false
		elseif plan.Kind == 'Crossfade' then
			local state = { Players = {}, Playing = {}, Loud = {}, Gain = {}, Speed = {}, QuietSince = {} }

			for j, layer in plan.Layers do
				local player = Instance.new('AudioPlayer')
				player.Name = `{plan.Name or 'Crossfade'}_{layer.At}`
				player.Asset = layer.Asset
				player.Looping = true
				player.Volume = 0
				player.Parent = folder

				state.Players[j] = player
				state.Playing[j] = false
				state.Loud[j] = false
				state.Gain[j] = 0
			end

			self.Nodes[index] = state
			table.insert(self.Crossfades, index)

			if plan.Name then self.Named[plan.Name] = index end
		else
			local instance = Instance.new(plan.Class)
			if plan.Name then instance.Name = plan.Name end

			applyStatic(instance, plan, patch.Name)

			if plan.Kind == 'Gate' then instance.Volume = 0 end

			instance.Parent = folder
			self.Nodes[index] = instance

			if plan.Name then self.Named[plan.Name] = index end

			if plan.Class == 'AudioPlayer' then self:_AdoptPlayer(index, plan, instance) end
		end
	end
end

--[[
	Works out whether a plain player starts with the voice, and follows it to its end

	@param index number
	@param plan Plan
	@param player AudioPlayer
	@return nil
--]]
function Voice._AdoptPlayer(self, index: number, plan, player: AudioPlayer)
	local oneShot = self.Patch.OneShot
	local want = if plan.Play ~= nil then plan.Play else (player.Looping or oneShot)

	self.Players[index] = want
	self.StartWants[index] = want

	if player.Looping then return end

	if oneShot and want then
		self.Remaining += 1
	end

	table.insert(
		self.Connections,
		player.Ended:Connect(function()
			if not self.Alive then return end

			if oneShot then
				--// Counted once per run: a revived voice must not be finished by a late end from its last one
				if not self.Players[index] then return end
				self.Players[index] = false

				self.Remaining -= 1
				if self.Remaining <= 0 then self:Destroy(0) end
			else
				--// Finished, so a later return from virtual does not replay it
				self.Players[index] = false
			end
		end)
	)
end

--[[
	The outputs a plan offers its parent: its instance, or a crossfade's layers

	@param index number
	@return {Instance}
--]]
function Voice._Outputs(self, index: number): { Instance }
	local plan = self.Patch.Plans[index]
	local node = self.Nodes[index]

	if plan.Kind == 'Crossfade' then return node.Players end
	if plan.Kind == 'Emitter' then return {} end
	if plan.Kind == 'Send' then return self:_Outputs(plan.Source) end

	return { node }
end

--[[
	@param folder Folder
	@return nil
--]]
function Voice._Wire(self, folder: Folder)
	local patch = self.Patch

	for index, plan in patch.Plans do
		if plan.Kind == 'Send' then continue end

		local targets = if plan.Kind == 'Emitter' then self.Nodes[index] else { self.Nodes[index] }

		for _, input in plan.Inputs do
			for _, source in self:_Outputs(input) do
				for _, target in targets do
					Mixer.Wire(source, target, folder)
				end
			end
		end
	end

	for _, gate in patch.BusGates do
		Mixer.Wire(self.Nodes[gate], self.Bus.Input, folder)
	end
end

--[[
	Evaluates one binding and writes what it changes

	@param index number
	@param now number
	@return nil
--]]
function Voice._Apply(self, index: number, now: number)
	local binding = self.Patch.Bindings[index]
	local target = binding.Target

	if target == '@Crossfade' then
		self:_Crossfade(binding, now)
		return
	end

	local value = Value.Eval(binding.Spec, binding.Indices, self.Values)

	if target == '@Volume' then
		if value ~= self.PatchVolume then
			self.PatchVolume = value
			self.GateDirty = true
		end

		return
	end

	if target == '@Play' then
		self:_Want(binding.Plan, truthy(value))
		return
	end

	if not changed(self.Last[index], value) then return end
	self.Last[index] = value

	local node = self.Nodes[binding.Plan]

	if typeof(node) == 'Instance' then
		node[target] = value
	else
		for _, emitter in node do
			emitter[target] = value
		end
	end
end

--[[
	Re-weights a crossfade's layers for where its parameter is now

	@param binding Binding
	@param now number
	@return nil
--]]
function Voice._Crossfade(self, binding, now: number)
	local plan = self.Patch.Plans[binding.Plan]
	local state = self.Nodes[binding.Plan]
	local values = self.Values

	local x = values[plan.By]
	local speed = if binding.Speed
		then Value.Eval(binding.Speed, binding.SpeedIndices, values)
		else plan.Static.Speed or 1
	local volume = if binding.Volume
		then Value.Eval(binding.Volume, binding.VolumeIndices, values)
		else plan.Static.Volume or 1

	--// A voice that was retuned carries its own layer positions
	local ats = state.Ats or plan.Ats
	local lower, lowerWeight, upperWeight = Crossfade.Weights(ats, x)

	for j, layer in plan.Layers do
		local weight = if j == lower then lowerWeight elseif j == lower + 1 then upperWeight else 0
		local player = state.Players[j]
		local trim = if state.Trims then state.Trims[j] else layer.Volume
		local gain = weight * trim * volume

		if changed(state.Gain[j], gain) then
			player.Volume = gain
			state.Gain[j] = gain
		end

		--// By what reaches the output, so a crossfade turned right down stops its players too
		local loud = gain > Config.LayerSilence
		state.Loud[j] = loud

		if loud then
			local pitch = speed
			if plan.Track then
				pitch *= Crossfade.Pitch(x, ats[j], Config.MinPitch, Config.MaxPitch)
			end

			if changed(state.Speed[j], pitch) then
				player.PlaybackSpeed = pitch
				state.Speed[j] = pitch
			end

			state.QuietSince[j] = nil

			if self.Sounding and not state.Playing[j] then
				player:Play()
				state.Playing[j] = true
			end
		elseif state.Playing[j] and not state.QuietSince[j] then
			state.QuietSince[j] = now
			self.Waiting = true
		end
	end
end

--[[
	Stops crossfade layers that have been quiet for long enough

	@param now number
	@return nil
--]]
function Voice._StopQuietLayers(self, now: number)
	local waiting = false

	for _, index in self.Crossfades do
		local state = self.Nodes[index]

		for j, since in state.QuietSince do
			if now - since >= Config.LayerHold then
				state.Players[j]:Stop()
				state.Playing[j] = false
				state.QuietSince[j] = nil
			else
				waiting = true
			end
		end
	end

	self.Waiting = waiting
end

--[[
	Starts or stops a plain player

	@param index number
	@param want boolean
	@return nil
--]]
function Voice._Want(self, index: number, want: boolean)
	if self.Players[index] == want then return end
	self.Players[index] = want

	if not self.Sounding then return end

	local player = self.Nodes[index]

	if want then
		if not player.Looping then player.TimePosition = 0 end
		player:Play()
	else
		player:Stop()
	end
end

--[[
	Starts every player that should be running

	@param now number
	@return nil
--]]
function Voice._Start(self, now: number)
	if self.Sounding then return end
	self.Sounding = true

	for index, want in self.Players do
		if want then self.Nodes[index]:Play() end
	end

	for _, index in self.Crossfades do
		local state = self.Nodes[index]

		for j, player in state.Players do
			if state.Loud[j] then
				player:Play()
				state.Playing[j] = true
			end
		end
	end

	if self.Patch.OneShot then
		if self.Remaining <= 0 then
			self:Destroy(0)
			return
		end

		self.Deadline = now + Config.OneShotTimeout
	end
end

--[[
	Stops every player, keeping where each loop was

	@return nil
--]]
function Voice._Silence(self)
	if not self.Sounding then return end
	self.Sounding = false

	for index in self.Players do
		local player = self.Nodes[index]
		player:Stop()

		if not player.Looping then self.Players[index] = false end
	end

	for _, index in self.Crossfades do
		local state = self.Nodes[index]

		for j, player in state.Players do
			if state.Playing[j] then player:Stop() end
			state.Playing[j] = false
		end

		table.clear(state.QuietSince)
	end

	self.Waiting = false
end

--[[
	@return nil
--]]
function Voice._WriteGates(self)
	self.GateDirty = false

	local volume = math.clamp(self.PatchVolume * self.Envelope, 0, 3)

	for _, gate in self.Patch.Gates do
		self.Nodes[gate].Volume = volume
	end
end

--[[
	The mixer granting or taking away a place

	@param real boolean
	@return nil
--]]
function Voice._SetReal(self, real: boolean)
	if real == self.Real or self.Dying then return end
	self.Real = real

	Mixer.Recount(self)
	Mixer.Wake(self)

	if real then
		self:_Start(os.clock())
		self.EnvelopeTarget = 1
		self.FadeRate = 1 / Config.FadeIn
	elseif self.Patch.OneShot then
		self:Destroy(Config.FadeOut)
	else
		self.EnvelopeTarget = 0
		self.FadeRate = 1 / Config.FadeOut
	end
end

--[[
	How audible the voice is to a listener: its loudest emitter, 1 with none

	@param listener AudioListener?
	@return number
--]]
function Voice._Audibility(self, listener: AudioListener?): number
	if #self.Emitters == 0 or not listener then return 1 end

	local best = 0

	for _, emitter in self.Emitters do
		local audibility = emitter:GetAudibilityFor(listener)
		if audibility > best then best = audibility end
	end

	return best
end

--[[
	One frame

	@param deltaTime number
	@param now number
	@return nil
--]]
function Voice._Step(self, deltaTime: number, now: number)
	local patch = self.Patch
	local params = patch.Params
	local values, targets, dirty = self.Values, self.Targets, self.Dirty
	local anyDirty = self.AnyDirty

	local moving = false

	for i, param in params do
		local current, target = values[i], targets[i]

		if current ~= target then
			local next = Value.Approach(current, target, param.Smooth, deltaTime)

			values[i] = next
			dirty[i] = true
			anyDirty = true

			if next ~= target then moving = true end
		end
	end

	if anyDirty then
		local frame = self.Frame + 1
		local stamp = self.Stamp
		local byParam = patch.ByParam

		self.Frame = frame
		self.AnyDirty = false

		for i = 1, #params do
			if not dirty[i] then continue end
			dirty[i] = false

			for _, binding in byParam[i] do
				if stamp[binding] == frame then continue end
				stamp[binding] = frame

				self:_Apply(binding, now)
			end
		end
	end

	local envelope, goal = self.Envelope, self.EnvelopeTarget

	if envelope ~= goal then
		local delta = self.FadeRate * deltaTime

		envelope = if envelope < goal then math.min(goal, envelope + delta) else math.max(goal, envelope - delta)

		self.Envelope = envelope
		self.GateDirty = true

		if envelope == 0 then
			if self.Dying then
				self:_Teardown()
				return
			end

			self:_Silence()
		end
	end

	if self.GateDirty then self:_WriteGates() end
	if self.Waiting then self:_StopQuietLayers(now) end

	if now >= self.Deadline then
		self:Destroy(0)
		return
	end

	--// Settled: nothing changes until a Set, a fade or the mixer wakes it
	if not moving and not self.Waiting and self.Envelope == self.EnvelopeTarget and self.Deadline == math.huge then
		Mixer.Sleep(self)
	end
end

--[[
	Drops the voice from the mix. A one-shot is kept built as a spare for its patch's next Play;
	anything else has everything it made destroyed.

	@return nil
--]]
function Voice._Teardown(self)
	if not self.Alive then return end

	self.Alive = false
	self.Sounding = false
	Mixer.Remove(self)

	if self.Patch.OneShot and not self.SlotGone then
		self:_Park()
	else
		self:_Free()
	end
end

--[[
	Stops a finished one-shot and puts it in its patch's Spare, destroying the oldest spare if that is full

	@return nil
--]]
function Voice._Park(self)
	for index, want in self.Players do
		if want then self.Nodes[index]:Stop() end
		self.Players[index] = false
	end

	self.Parked = true

	local spare = self.Patch.Spare

	if #spare >= Config.SpareVoices then
		local oldest = table.remove(spare, 1)
		oldest.Parked = false
		oldest:_Free()
	end

	table.insert(spare, self)
end

--[[
	Destroys everything the voice made

	@return nil
--]]
function Voice._Free(self)
	for _, connection in self.Connections do
		connection:Disconnect()
	end

	table.clear(self.Connections)

	for _, emitter in self.Emitters do
		emitter:Destroy()
	end

	for attachment in self.Owned do
		attachment:Destroy()
	end

	self.Folder:Destroy()
end

--[[
	Something an emitter sits on is being destroyed: the voice ends for good, spare or not

	@return nil
--]]
function Voice._LoseSlot(self)
	self.SlotGone = true

	if not self.Parked then
		self:Destroy(0)
		return
	end

	local spare = self.Patch.Spare
	local index = table.find(spare, self)
	if index then table.remove(spare, index) end

	self.Parked = false
	self:_Free()
end

--// ---------------------------------------------------------------- Public

--[[
	Moves a parameter. It glides there at the patch's Smooth rate unless told to snap.

	@param name string
	@param value number
	@param snap boolean? -- jump straight there, for a step like a gear change
	@return nil
--]]
function Voice.Set(self, name: string, value: number, snap: boolean?)
	if not self.Alive then return end

	local index = self.Patch.ParamIndex[name]
	assert(index, `Audio.Patch '{self.Patch.Name}' - has no param '{name}'`)

	local param = self.Patch.Params[index]
	value = math.clamp(value, param.Min, param.Max)

	if self.Targets[index] == value and not snap then return end
	self.Targets[index] = value

	if (snap or param.Smooth <= 0) and self.Values[index] ~= value then
		self.Values[index] = value
		self.Dirty[index] = true
		self.AnyDirty = true
	end

	Mixer.Wake(self)
end

--[[
	Moves several parameters at once, as Set does each

	@param values {[string]: number}
	@param snap boolean?
	@return nil
--]]
function Voice.SetMany(self, values: { [string]: number }, snap: boolean?)
	for name, value in values do
		self:Set(name, value, snap)
	end
end

--[[
	Moves a slot that was given as a point - a sound that follows a projectile, say - without a
	restart. Only points move this way; a slot on an instance follows that instance already.

	@param slot string -- the emitter's At name
	@param at Vector3 | CFrame | {Vector3 | CFrame} -- one per point it was spawned with
	@return nil
--]]
function Voice.Move(self, slot: string, at: any)
	if not self.Alive then return end

	local given = listOf(at)
	local found = false

	for index, list in self.Slots do
		if self.Patch.Plans[index].At ~= slot then continue end
		found = true

		assert(
			type(given) == 'table' and #given == #list,
			`Audio.Patch '{self.Patch.Name}' - slot '{slot}' needs {#list} point(s)`
		)

		for i, attachment in list do
			assert(
				self.Owned[attachment] and isPoint(given[i]),
				`Audio.Patch '{self.Patch.Name}' - slot '{slot}' was not spawned on points`
			)

			place(attachment, given[i])
		end
	end

	assert(found, `Audio.Patch '{self.Patch.Name}' - has no slot '{slot}'`)
end

--[[
	A parameter's current, smoothed value

	@param name string
	@return number
--]]
function Voice.Get(self, name: string): number
	local index = self.Patch.ParamIndex[name]
	assert(index, `Audio.Patch '{self.Patch.Name}' - has no param '{name}'`)

	return self.Values[index]
end

--[[
	Starts a named player: a loop that comes and goes, or a sound fired from inside a longer one.
	A player that is not looping restarts from the top.

	@param name string
	@return nil
--]]
function Voice.Play(self, name: string)
	if not self.Alive then return end

	local index = self.Named[name]
	assert(index and self.Players[index] ~= nil, `Audio.Patch '{self.Patch.Name}' - has no player named '{name}'`)

	local looping = self.Nodes[index].Looping

	if not looping and not self.Sounding then return end

	--// Re-asking for a finished one-off has to start it again
	if self.Players[index] and not looping then self.Players[index] = false end

	self:_Want(index, true)
end

--[[
	@param name string
	@return nil
--]]
function Voice.Stop(self, name: string)
	if not self.Alive then return end

	local index = self.Named[name]
	assert(index and self.Players[index] ~= nil, `Audio.Patch '{self.Patch.Name}' - has no player named '{name}'`)

	self:_Want(index, false)
end

--[[
	Moves a named crossfade's layers along its parameter, and optionally sets each layer's volume,
	on this voice only, without restarting anything. For tuning a patch by ear while it plays - a
	volume of 0 takes a layer out entirely.

	@param name string
	@param ats {number} -- a position per layer, in the order the layers were given, ascending
	@param trims {number}? -- a volume per layer, in place of each layer's own Volume
	@return nil
--]]
function Voice.Retune(self, name: string, ats: { number }, trims: { number }?)
	if not self.Alive then return end

	local index = self.Named[name]
	local plan = index and self.Patch.Plans[index]
	assert(plan and plan.Kind == 'Crossfade', `Audio.Patch '{self.Patch.Name}' - has no crossfade named '{name}'`)
	assert(#ats == #plan.Layers, `Audio.Patch '{self.Patch.Name}' - '{name}' has {#plan.Layers} layers`)

	for i = 2, #ats do
		assert(ats[i] > ats[i - 1], `Audio.Patch '{self.Patch.Name}' - '{name}' positions must ascend`)
	end

	if trims then assert(#trims == #ats, `Audio.Patch '{self.Patch.Name}' - '{name}' needs a volume per layer`) end

	local state = self.Nodes[index]
	state.Ats = table.clone(ats)
	state.Trims = if trims then table.clone(trims) else nil

	for bindingIndex, binding in self.Patch.Bindings do
		if binding.Plan == index then self:_Apply(bindingIndex, os.clock()) end
	end

	Mixer.Wake(self)
end

--[[
	Re-evaluates every binding now. For when something a Compute reads outside the voice's params
	has changed - a sound switched off, a value retuned - and the params themselves have not moved.

	@return nil
--]]
function Voice.Refresh(self)
	if not self.Alive then return end

	local now = os.clock()

	for index in self.Patch.Bindings do
		self:_Apply(index, now)
	end

	Mixer.Wake(self)
end

--[[
	A named node's instance, for wiring something of your own off it - an analyzer, a meter

	@param name string
	@return Instance
--]]
function Voice.Instance(self, name: string): Instance
	local index = self.Named[name]
	assert(index, `Audio.Patch '{self.Patch.Name}' - has no node named '{name}'`)

	return self.Nodes[index]
end

--[[
	Fades the voice out and destroys it

	@param fade number? -- seconds; Config.Release by default, 0 cuts it dead
	@return nil
--]]
function Voice.Destroy(self, fade: number?)
	if not self.Alive or self.Dying then return end
	self.Dying = true

	Mixer.Recount(self)

	local seconds = fade or Config.Release

	if seconds <= 0 or not self.Sounding or self.Envelope <= 0 then
		self:_Teardown()
		return
	end

	self.EnvelopeTarget = 0
	self.FadeRate = 1 / seconds

	Mixer.Wake(self)
end

--[[
	What the voice is doing, for debugging

	@return {[string]: any}
--]]
function Voice.Inspect(self)
	local params = {}

	for i, param in self.Patch.Params do
		params[param.Name] = self.Values[i]
	end

	return {
		Name = self.Patch.Name,
		Bus = self.Bus.Name,
		Real = self.Real,
		Sounding = self.Sounding,
		Dying = self.Dying,
		Volume = self.PatchVolume * self.Envelope,
		Params = params,
	}
end

return Voice
