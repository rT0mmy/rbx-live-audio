--!strict
local Mock = require('./Mock'); local game, workspace, Instance, Enum, typeof, Vector3, CFrame = Mock.game, Mock.workspace, Mock.Instance, Mock.Enum, Mock.typeof, Mock.Vector3, Mock.CFrame

--// The library's public types, re-exported from the package: Audio.Voice, Audio.Patch and the rest

local Nodes = require(`./Node`)
local Value = require(`./Value`)

--// What an emitter sits on: an instance it follows, or a point it is given an attachment for
export type Slot = Instance | Vector3 | CFrame

--// Each a Slot or a list of them. Kept loose, as the type solver will not fit a table literal of
--// one kind to that union.
export type Slots = { [string]: any }

export type Params = { [string]: number }

export type ParamDef = number | {
	Default: number?,
	Smooth: number?, -- per second toward a new target; 0 snaps
	Min: number?,
	Max: number?,
}

export type Spec = Value.Spec
export type Points = Value.Points
export type Node = Nodes.Desc

--// A patch definition: these keys, plus its top-level nodes in the array part
export type PatchDef = { [any]: any }

export type BusDef = {
	Name: string,
	Parent: string?,
	Spatial: boolean?,
	Voices: number?,
	Duck: string?,
	Chain: { { [string]: any } }?,
}

export type Options = {
	Buses: { BusDef }?,
	Master: { [string]: number }?,
	Duck: { [string]: number }?,
	BudgetPeriod: number?,
	Stickiness: number?,
	Inaudible: number?,
	FadeIn: number?,
	FadeOut: number?,
	Release: number?,
	LayerSilence: number?,
	LayerHold: number?,
	MinPitch: number?,
	MaxPitch: number?,
	WriteTolerance: number?,
	OneShotTimeout: number?,
	SpareVoices: number?,
	FolderName: string?,
	GroupPrefix: string?,
	Profiler: { Begin: (label: string) -> (), End: () -> () }?,
}

export type VoiceInspection = {
	Name: string,
	Bus: string,
	Real: boolean,
	Sounding: boolean,
	Dying: boolean,
	Volume: number,
	Params: Params,
}

export type BusInspection = {
	Name: string,
	Volume: number,
	Voices: number,
	Sounding: number,
	Cap: number?,
}

export type Inspection = {
	Buses: { BusInspection },
	Voices: { VoiceInspection },
}

export type Voice = {
	--// False once it has ended, and for a one-shot that was never built
	Alive: boolean,

	Set: (self: Voice, name: string, value: number, snap: boolean?) -> (),
	SetMany: (self: Voice, values: Params, snap: boolean?) -> (),
	Get: (self: Voice, name: string) -> number,
	Play: (self: Voice, name: string) -> (),
	Stop: (self: Voice, name: string) -> (),
	Move: (self: Voice, slot: string, at: Vector3 | CFrame | { Vector3 | CFrame }) -> (),
	Retune: (self: Voice, name: string, ats: { number }, trims: { number }?) -> (),
	Refresh: (self: Voice) -> (),
	Instance: (self: Voice, name: string) -> Instance,
	Inspect: (self: Voice) -> VoiceInspection,
	Destroy: (self: Voice, fade: number?) -> (),
}

export type Patch = {
	Name: string,
	Bus: string,
	Priority: number,
	OneShot: boolean,
	Assets: { string },

	Spawn: (self: Patch, slots: Slots?, params: Params?) -> Voice,
	Play: (self: Patch, slots: Slots?, params: Params?) -> Voice,
	Preload: (self: Patch) -> (),
}

return {}
