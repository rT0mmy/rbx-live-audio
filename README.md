# Audio

A declarative audio engine for the Roblox [Audio API](https://create.roblox.com/docs/audio).
You describe each sound once as a **patch**. You spawn **voices** from it and set their
parameters from gameplay. One render-step loop smooths the parameters and writes a property only
when its value actually changes. Buses, a voice budget and ducking are built in.

```lua
local Audio = require(ReplicatedStorage.Audio)

local Engine = Audio.Patch {
	Name = 'Engine',
	Bus = 'World',
	Priority = 5,
	Params = {
		rpm = { Default = 800, Smooth = 20, Min = 0 },
		load = { Default = 0, Smooth = 8, Min = 0, Max = 1 },
	},
	Volume = Audio.Curve('load', { { 0, 0.7 }, { 1, 1 } }),

	Audio.Emitter {
		At = 'Exhaust',
		Distance = { { 10, 1 }, { 60, 0.4 }, { 250, 0 } },

		Audio.Equalizer {
			HighGain = Audio.Curve('load', { { 0, -9 }, { 1, 0 } }),

			Audio.Crossfade {
				By = 'rpm',
				Track = true,
				Layers = {
					{ Asset = 'rbxassetid://...', At = 1000 },
					{ Asset = 'rbxassetid://...', At = 3500 },
				},
			},
		},
	},
}

local voice = Engine:Spawn({ Exhaust = attachment }, { rpm = 900 })
voice:Set('rpm', rpm)
voice:Destroy()
```

Each node's inputs are listed inside it, so a patch reads from the speakers inwards. An emitter's
slot (`At`) can be one instance or a list of them, which gives one emitter per instance.

## Setup

Voices only play on the client. Configure the mix once at startup, before anything plays, then
mount it:

```lua
Audio.Configure({
	Buses = {
		{ Name = 'Master' },
		{ Name = 'World', Parent = 'Master', Spatial = true, Voices = 24 },
		{ Name = 'Ambient', Parent = 'World', Spatial = true, Voices = 16, Duck = 'Hero' },
		{ Name = 'Hero', Parent = 'World', Spatial = true, Chain = {
			{ Class = 'AudioCompressor', Threshold = -20, Ratio = 3 },
		} },
		{ Name = 'Music', Parent = 'Master' },
		{ Name = 'UI', Parent = 'Master' },
	},
})

Audio.Mount()
Audio.SetBusVolume('Music', 0.5)
```

A bus definition takes:

| Key | Meaning |
|---|---|
| `Name` | Bus name; patches play into it with `Bus = ...` |
| `Parent` | Bus it feeds. It must be listed earlier; buses without a parent feed the master compressor |
| `Spatial` | Has its own `AudioListener` on the camera, with its own interaction group |
| `Voices` | Cap on voices sounding at once, ranked by audibility × patch `Priority`; uncapped if omitted |
| `Duck` | Name of a bus whose output pushes this one down through a sidechained compressor |
| `Chain` | Effects applied to the bus in order, as `{ Class = 'Audio...', ...properties }` |

With no `Configure` call, the mix is `Master` > `World` (spatial, 32 voices), `Music`, `UI`.
Every other setting in `src/Config.luau` can be changed through `Configure` as well. That includes
`Profiler`, a `{ Begin, End }` pair called around each frame's work (by default
`debug.profilebegin` / `debug.profileend`).

## API

**Patches:** `Audio.Patch(def)` compiles a description and errors on anything malformed.
`def` takes `Name`, `Bus`, `Priority`, `Params`, `Volume` and `OneShot`.
- `patch:Spawn(slots, params)` returns a voice you keep.
- `patch:Play(slots, params)` fires a `OneShot` patch. When it finishes it is kept built and reused
  by the next `Play` on the same slots. Nothing is built if its bus is full or the listener is
  outside the patch's distance curve.
- `patch:Preload()` loads every asset the patch uses (yields).

**Values:** `Audio.Bind(param, scale?)`, `Audio.Curve(param, points)` and
`Audio.Compute({ params }, fn)` drive any node property from parameters.

**Nodes:**
- `Audio.Emitter`, `Audio.Crossfade` (an equal-power layer grid, optionally pitch-tracked with
  `Track`) and `Audio.Send` (reuses one signal at another emitter).
- Wrappers for `Player`, `Fader`, `Equalizer`, `Filter`, `Distortion`, `PitchShifter`,
  `Compressor`, `Reverb`, `Echo`, `Chorus`, `Flanger` and `Tremolo`.
- `Audio.Node(className)` wraps any other `Audio*` class that has Input and Output pins.

**Voices:**
- `voice:Set(name, value, snap?)` and `voice:Get(name)` read and write parameters.
- `voice:Play(name)` and `voice:Stop(name)` control named players.
- `voice:Retune(name, ats, trims?)` changes a crossfade's layer points without a restart, and
  `voice:Refresh()` re-applies the voice's current values.
- `voice:Instance(name)`, `voice:Inspect()` and `voice:Destroy(fade?)`.

**Mix:** `Audio.Configure`, `Audio.Mount`, `Audio.SetBusVolume`, `Audio.GetBusVolume`, and
`Audio.Inspect()`, which returns a snapshot of buses and voices for debugging.

**Tools:** `Audio.Pitch` measures relative pitch between recordings (AudioAnalyzer spectra), and
`Audio.CrossfadeWeights` returns the weighting a crossfade gives its layers.

## Notes

- Emitters are parented to their slot, because `AudioEmitter.PositionType` errors with
  "not enabled yet".
- A held (non-OneShot) voice restarted with `voice:Play` lands on the frame you call it. Use one
  for anything that must be in time with an event, such as a gear-shift clunk. A fresh one-shot
  loads its asset on every play and can be late.
- When a voice is silent, `Play` drops any one-off you ask it for, so nothing goes off late when
  the voice comes back into earshot.

## Development

Tools are pinned in `aftman.toml`. `rojo build -o Audio.rbxm` builds the model;
`stylua src` and `selene src` format and lint it.
