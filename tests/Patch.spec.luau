require('./Setup')

local Audio = require('./Audio')
local Test = require('./Test')

local case, equal, truthy, errors = Test.case, Test.equal, Test.truthy, Test.errors

local function player(name: string?)
	return Audio.Player({ Name = name, Asset = 'rbxassetid://1' })
end

case('compiles on a bus given to Configure', function()
	local patch = Audio.Patch({ Name = 'Pad', Bus = 'Ambient', player() })
	equal(patch.Bus, 'Ambient')
end)

case('rejects a bus the configured mix does not have', function()
	errors(function()
		Audio.Patch({ Name = 'Lost', Bus = 'Music', player() })
	end, "Bus 'Music' is not in Audio Config.Buses")
end)

case('rejects an Emitter on a bus that is not Spatial', function()
	errors(function()
		Audio.Patch({ Bus = 'UI', Audio.Emitter({ At = 'Here', player() }) })
	end, 'is not Spatial')
end)

case('rejects a Send to its own ancestor', function()
	errors(function()
		Audio.Patch({
			Name = 'Loop',
			Bus = 'UI',
			Audio.Fader({ Name = 'Top', Audio.Fader({ Audio.Send('Top'), player() }) }),
		})
	end, "a Send feeds 'Top' its own output")
end)

case('rejects a pair of Sends that feed each other', function()
	errors(function()
		Audio.Patch({
			Name = 'Pair',
			Bus = 'UI',
			Audio.Fader({ Name = 'A', Audio.Send('B'), player() }),
			Audio.Fader({ Name = 'B', Audio.Send('A'), player() }),
		})
	end, 'its own output')
end)

case('accepts an aux Send into a second chain', function()
	local patch = Audio.Patch({
		Name = 'Aux',
		Bus = 'UI',
		Audio.Fader({ Name = 'Dry', player('Source') }),
		Audio.Reverb({ Name = 'Wet', Audio.Send('Source') }),
	})

	equal(#patch.Gates, 2)
end)

case('rejects a Send to a name that is not there', function()
	errors(function()
		Audio.Patch({ Bus = 'UI', Audio.Fader({ Audio.Send('Nobody'), player() }) })
	end, 'names no node')
end)

case('rejects a OneShot holding a Crossfade', function()
	errors(function()
		Audio.Patch({
			Bus = 'UI',
			OneShot = true,
			Params = { x = 0 },
			Audio.Crossfade({ By = 'x', Layers = { { Asset = 'a', At = 1 } } }),
		})
	end, 'cannot hold a Crossfade')
end)

case('clamps defaults and indexes params by sorted name', function()
	local patch = Audio.Patch({
		Bus = 'UI',
		Params = { zeta = 1, alpha = { Default = 5, Max = 2 } },
		player(),
	}) :: any

	equal(patch.ParamIndex.alpha, 1)
	equal(patch.ParamIndex.zeta, 2)
	equal(patch.Params[1].Default, 2)
end)

case('works out the reach of its distance curves', function()
	local patch = Audio.Patch({
		Bus = 'World',
		Audio.Emitter({ At = 'Here', Distance = { { 10, 1 }, { 60, 0 }, { 200, 0 } }, player() }),
	}) :: any

	equal(patch.Reach, 60)
	equal(#patch.Emitters, 1)
end)

case('has no reach when a curve never falls to 0', function()
	local patch = Audio.Patch({
		Bus = 'World',
		Audio.Emitter({ At = 'Here', Distance = { { 10, 1 }, { 60, 0.2 } }, player() }),
	}) :: any

	equal(patch.Reach, math.huge)
end)

case('lists the assets it needs for Preload', function()
	local patch = Audio.Patch({
		Bus = 'UI',
		Params = { x = 0 },
		player(),
		Audio.Crossfade({ By = 'x', Layers = { { Asset = 'b', At = 1 }, { Asset = 'c', At = 2 } } }),
	})

	truthy(table.find(patch.Assets, 'rbxassetid://1') and table.find(patch.Assets, 'c'), 'assets listed')
end)

return nil
