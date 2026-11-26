--!nonstrict
--!native

--// Declarative audio on the Audio API
--//
--//   local Engine = Audio.Patch {
--//       Name = 'Engine',
--//       Bus = 'Engine',
--//       Priority = 5,
--//       Params = {
--//           rpm = { Default = 800, Smooth = 20, Min = 0 },
--//           load = { Default = 0, Smooth = 8, Min = 0, Max = 1 },
--//       },
--//       Volume = Audio.Curve('load', { { 0, 0.7 }, { 1, 1 } }),
--//
--//       Audio.Emitter {
--//           At = 'Exhaust',
--//           Distance = { { 10, 1 }, { 60, 0.4 }, { 250, 0 } },
--//
--//           Audio.Equalizer {
--//               HighGain = Audio.Curve('load', { { 0, -9 }, { 1, 0 } }),
--//
--//               Audio.Crossfade {
--//                   By = 'rpm',
--//                   Track = true,
--//                   Layers = {
--//                       { Asset = 'rbxassetid://...', At = 1000 },
--//                       { Asset = 'rbxassetid://...', At = 3500 },
--//                   },
--//               },
--//           },
--//       },
--//   }
--//
--//   local voice = Engine:Spawn({ Exhaust = attachment }, { rpm = 900 })
--//   voice:Set('rpm', state.RPM)
--//   voice:Destroy()
--//
--// Inputs are listed inside their parent, so a patch reads from the speakers inwards. A slot an
--// emitter sits on can be one instance or a list, which gives one emitter per instance.

local ContentProvider = game:GetService('ContentProvider')

local Crossfade = require(`@self/Crossfade`)
local Mixer = require(`@self/Mixer`)
local Node = require(`@self/Node`)
local Patch = require(`@self/Patch`)
local Pitch = require(`@self/Pitch`)
local Types = require(`@self/Types`)
local Value = require(`@self/Value`)
local Voice = require(`@self/Voice`)

export type Slot = Types.Slot
export type Slots = Types.Slots
export type Params = Types.Params
export type ParamDef = Types.ParamDef
export type Spec = Types.Spec
export type Points = Types.Points
export type Node = Types.Node
export type PatchDef = Types.PatchDef
export type BusDef = Types.BusDef
export type Options = Types.Options
export type Inspection = Types.Inspection
export type VoiceInspection = Types.VoiceInspection
export type BusInspection = Types.BusInspection
export type Voice = Types.Voice
export type Patch = Types.Patch

local Audio = {}

--// ---------------------------------------------------------------- Patches

local PatchClass = {}
PatchClass.__index = PatchClass

--[[
	Describes a sound. Errors here, at definition, for anything malformed.

	@param def PatchDef
	@return Patch
--]]
function Audio.Patch(def: PatchDef): Patch
	return setmetatable(Patch.Compile(def), PatchClass) :: any
end

--[[
	Makes a live voice from the patch

	@param slots Slots? -- what each emitter sits on, by its At name: instances, Vector3s or CFrames
	@param params Params? -- starting values
	@return Voice
--]]
function PatchClass:Spawn(slots: Slots?, params: Params?): Voice
	return Voice.new(self, slots, params)
end

--[[
	Fires a OneShot patch and forgets it. When it ends it is kept built and reused by a later Play on
	the same slots, so a returned voice is only good for cutting short until it ends. Nothing is built
	when its bus is full or the listener is past its distance curve's reach.

	@param slots Slots?
	@param params Params?
	@return Voice
--]]
function PatchClass:Play(slots: Slots?, params: Params?): Voice
	assert(self.OneShot, `Audio.Patch '{self.Name}' - Play is for OneShot patches; use Spawn and keep the voice`)

	return Voice.Fire(self, slots, params)
end

--[[
	Loads every asset the patch uses. Yields.

	@return nil
--]]
function PatchClass:Preload()
	if #self.Assets > 0 then ContentProvider:PreloadAsync(self.Assets) end
end

--// ---------------------------------------------------------------- Values

Audio.Bind = Value.Bind
Audio.Curve = Value.Curve
Audio.Compute = Value.Compute

--// ---------------------------------------------------------------- Nodes

Audio.Emitter = Node.Emitter
Audio.Crossfade = Node.Crossfade
Audio.Send = Node.Send

Audio.Player = Node.Of('AudioPlayer')
Audio.Fader = Node.Of('AudioFader')
Audio.Equalizer = Node.Of('AudioEqualizer')
Audio.Filter = Node.Of('AudioFilter')
Audio.Distortion = Node.Of('AudioDistortion')
Audio.PitchShifter = Node.Of('AudioPitchShifter')
Audio.Compressor = Node.Of('AudioCompressor')
Audio.Reverb = Node.Of('AudioReverb')
Audio.Echo = Node.Of('AudioEcho')
Audio.Chorus = Node.Of('AudioChorus')
Audio.Flanger = Node.Of('AudioFlanger')
Audio.Tremolo = Node.Of('AudioTremolo')

--// Any other Audio* class with Input and Output pins
Audio.Node = Node.Of

--// ---------------------------------------------------------------- Mix

Audio.Configure = Mixer.Configure :: (options: Options) -> ()
Audio.Mount = Mixer.Mount :: () -> ()
Audio.SetBusVolume = Mixer.SetVolume :: (name: string, volume: number) -> ()
Audio.GetBusVolume = Mixer.GetVolume :: (name: string) -> number
Audio.Inspect = Mixer.Inspect :: () -> Inspection

--// Tools: relative pitch between recordings, and the weighting a crossfade gives its layers
Audio.Pitch = Pitch
Audio.CrossfadeWeights = Crossfade.Weights

return Audio
