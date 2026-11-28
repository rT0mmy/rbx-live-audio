--!strict

local Config = {}

--// The mix, parents before children. A game swaps in its own with Audio.Configure({ Buses = ... })
--// before anything plays.
Config.Buses = {
	{ Name = 'Master' },
	{ Name = 'World', Parent = 'Master', Spatial = true, Voices = 32 },
	{ Name = 'Music', Parent = 'Master' },
	{ Name = 'UI', Parent = 'Master' },
} :: { { [string]: any } }

Config.Master = {
	Threshold = -6, -- dB
	Ratio = 4,
	Attack = 0.005, -- seconds
	Release = 0.25,
	MakeupGain = 0,
}

--// The compressor on a bus that Ducks under another
Config.Duck = {
	Threshold = -22,
	Ratio = 2.5,
	Attack = 0.04,
	Release = 0.35,
	MakeupGain = 0,
}

--// Seconds between re-ranking which voices sound
Config.BudgetPeriod = 0.1

--// A sounding voice's score is multiplied by this when ranking
Config.Stickiness = 1.2

--// Audibility (0..1, from distance and angle) below which a voice is not worth a place at all
Config.Inaudible = 0.001

--// Seconds to fade a voice in when it wins a place, and out when it loses one
Config.FadeIn = 0.08
Config.FadeOut = 0.15

--// Seconds Voice:Destroy fades over when not told otherwise
Config.Release = 0.2

--// A crossfade layer quieter than this stops playing once it has stayed quiet for LayerHold
--// seconds
Config.LayerSilence = 0.001
Config.LayerHold = 0.3

--// Playback speed a tracking crossfade will stretch a layer to, either way
Config.MinPitch = 0.25
Config.MaxPitch = 4

--// A property is only written when its new value differs from the last by more than this
Config.WriteTolerance = 1e-3

--// Seconds a one-shot may run before it is reclaimed, in case its end is never reported
Config.OneShotTimeout = 30

--// Finished one-shot voices each patch keeps built, so playing it again needs no new instances
Config.SpareVoices = 4

Config.FolderName = '_Audio'
Config.GroupPrefix = 'Audio/'

--// Brackets the mixer's work each frame; a game can hand in its own pair through Audio.Configure
Config.Profiler = {
	Begin = debug.profilebegin :: (label: string) -> (),
	End = debug.profileend :: () -> (),
}

return Config
