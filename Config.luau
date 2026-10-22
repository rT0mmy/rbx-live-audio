--!strict

local Config = {}

--// The mix
Config.Buses = {
	{ Name = 'Master' },

	{ Name = 'World', Parent = 'Master', Spatial = true, Voices = 24 },
	{ Name = 'Ambient', Parent = 'World', Spatial = true, Voices = 16, Duck = 'Hero' },

	{ Name = 'Vehicles', Parent = 'World' },

	{ Name = 'Engine', Parent = 'Vehicles' },
	{ Name = 'EngineLoop', Parent = 'Engine', Spatial = true, Voices = 8, Duck = 'Hero' },
	{ Name = 'EngineTransient', Parent = 'Engine', Spatial = true, Voices = 16, Duck = 'Hero' },

	--// Pops and anti-lag bangs. Uncapped: each car holds an idle voice per exhaust, ready to fire
	{ Name = 'Afterfire', Parent = 'Engine', Spatial = true, Duck = 'Hero' },

	--// The clients car (Hero)
	{
		Name = 'Hero',
		Parent = 'Engine',
		Spatial = true,
		Chain = {
			{
				Class = 'AudioEqualizer',
				LowGain = 2.5,
				MidGain = 0,
				HighGain = 1,
				MidRange = NumberRange.new(220, 4500),
			},
			{ Class = 'AudioCompressor', Threshold = -20, Ratio = 3, Attack = 0.008, Release = 0.12, MakeupGain = 1 },
		} :: { any },
	},

	{ Name = 'Tyres', Parent = 'Vehicles', Spatial = true, Voices = 8 },
	{ Name = 'Brakes', Parent = 'Vehicles', Spatial = true, Voices = 6 },

	{ Name = 'Impacts', Parent = 'Vehicles', Spatial = true },
	{ Name = 'Road', Parent = 'Vehicles', Spatial = true, Voices = 4 },
	{ Name = 'Wind', Parent = 'Vehicles', Spatial = true, Voices = 2 },
	{ Name = 'Horn', Parent = 'Vehicles', Spatial = true, Voices = 6 },
	{ Name = 'Siren', Parent = 'Vehicles', Spatial = true, Voices = 4 },

	{ Name = 'Music', Parent = 'Master' },
	{ Name = 'UI', Parent = 'Master' },

	{ Name = 'Debug', Parent = 'Master' },
}

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

return Config
