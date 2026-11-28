--// The mix every spec runs against, configured and mounted once

local Audio = require('./Audio')
local Mock = require('./Audio/Mock')

Audio.Configure({
	Buses = {
		{ Name = 'Master' },
		{ Name = 'World', Parent = 'Master', Spatial = true, Voices = 2 },
		{ Name = 'Ambient', Parent = 'World', Spatial = true, Duck = 'UI' },
		{ Name = 'UI', Parent = 'Master' },
	},
	Profiler = {
		Begin = function() end,
		End = function() end,
	},
})

Audio.Mount()

local Setup = {}

--// Runs the mixer for n frames at 60 fps
function Setup.frames(count: number)
	for _ = 1, count do
		(Mock.Step :: (number) -> ())(1 / 60)
	end
end

return Setup
