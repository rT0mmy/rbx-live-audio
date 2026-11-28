local Setup = require('./Setup')

local Audio = require('./Audio')
local Mixer = require('./Audio/Mixer')
local Mock = require('./Audio/Mock')
local Test = require('./Test')
local Voice = require('./Audio/Voice')

local case, equal, near, truthy, errors = Test.case, Test.equal, Test.near, Test.truthy, Test.errors
local frames = Setup.frames
local Vector3, CFrame = Mock.Vector3, Mock.CFrame

--// Counts voice steps, to see which voices the mixer still works on
local steps = 0
local step = Voice._Step

Voice._Step = function(self, ...)
	steps += 1
	return step(self, ...)
end

local function stepsOver(count: number): number
	steps = 0
	frames(count)

	return steps
end

local Hum = Audio.Patch({
	Name = 'Hum',
	Bus = 'UI',
	Params = { x = { Default = 0, Smooth = 20 }, y = { Default = 0, Smooth = 0 } },
	Audio.Fader({ Name = 'Level', Volume = Audio.Bind('x'), Audio.Player({ Asset = 'hum', Looping = true }) }),
})

local Car = Audio.Patch({
	Name = 'Car',
	Bus = 'World',
	Audio.Player({ Asset = 'car', Looping = true }),
})

local Shot = Audio.Patch({
	Name = 'Shot',
	Bus = 'World',
	OneShot = true,
	Audio.Emitter({
		At = 'Muzzle',
		Distance = { { 10, 1 }, { 100, 0 } },
		Audio.Player({ Name = 'Bang', Asset = 'bang' }),
	}),
})

local world = Mixer.Bus('World')

Test.case('a settled voice is not stepped, and Set wakes it', function()
	local voice = Hum:Spawn()
	frames(3)
	equal(stepsOver(10), 0, 'steps while settled')

	voice:Set('x', 1)
	equal(stepsOver(1), 1, 'steps after Set')

	frames(120)
	near((voice:Instance('Level') :: any).Volume, 1, 1e-3, 'fader volume')
	equal(stepsOver(5), 0, 'steps once settled again')

	voice:Set('x', 1)
	equal(stepsOver(1), 0, 'steps after Set to the same target')

	voice:Destroy(0)
end)

case('SetMany sets each parameter', function()
	local voice = Hum:Spawn()

	voice:SetMany({ x = 0.5, y = 3 }, true)
	equal(voice:Get('x'), 0.5)
	equal(voice:Get('y'), 3)

	errors(function()
		voice:SetMany({ nope = 1 })
	end, "has no param 'nope'")

	voice:Destroy(0)
end)

case('Destroy fades out, then tears down', function()
	local voice = Hum:Spawn()

	voice:Destroy(0.1)
	truthy(voice.Alive, 'alive mid-fade')

	frames(30)
	equal(voice.Alive, false, 'alive after the fade')
end)

case('a bus keeps to its cap and counts what sounds', function()
	local a, b, c = Car:Spawn() :: any, Car:Spawn() :: any, Car:Spawn() :: any

	truthy(a.Real and b.Real and not c.Real, 'first two get a place')
	equal(world.Sounding, 2)
	equal(Mixer.HasRoom(world), false)

	a:Destroy(0.2)
	equal(world.Sounding, 1, 'a dying voice gives its place up at once')

	frames(7)
	truthy(c.Real, 'the budget fills the place')
	equal(world.Sounding, 2)

	frames(30)
	b:Destroy(0)
	c:Destroy(0)
	equal(world.Sounding, 0)
end)

case('an inaudible voice loses its place and gets it back', function()
	local voice = Car:Spawn() :: any
	local emitter = Mock.Instance.new('AudioEmitter')
	voice.Emitters = { emitter }

	emitter.Audibility = 0
	frames(7)
	equal(voice.Real, false)
	equal(world.Sounding, 0)

	emitter.Audibility = 1
	frames(7)
	equal(voice.Real, true)

	frames(30)
	equal(stepsOver(3), 0, 'settled after its fade-in')

	voice:Destroy(0)
end)

case('a point slot gets an attachment on Terrain', function()
	local voice = Shot:Play({ Muzzle = Vector3.new(5, 0, 0) }) :: any
	local attachment = next(voice.Owned)

	truthy(attachment, 'attachment made')
	equal(attachment.Parent, Mock.workspace.Terrain)
	equal(attachment.Position, Vector3.new(5, 0, 0))

	voice:Destroy(0)
end)

case('a CFrame slot sets the attachment CFrame', function()
	local at = CFrame.new(1, 2, 3)
	local voice = Shot:Spawn({ Muzzle = at }) :: any

	equal(next(voice.Owned).CFrame, at)

	voice:Destroy(0)
end)

case('a spare one-shot is reused at a new point without new instances', function()
	local first = Shot:Play({ Muzzle = Vector3.new(1, 0, 0) }) :: any
	local player = first:Instance('Bang') :: any
	player.Ended:Fire()

	equal(first.Alive, false, 'ended')
	equal(first.Parked, true, 'kept as a spare')
	equal(stepsOver(3), 0, 'a spare is not stepped')

	local before = Mock.Created
	local second = Shot:Play({ Muzzle = Vector3.new(0, 0, 9) }) :: any

	equal(second, first, 'same voice')
	equal(Mock.Created, before, 'instances made')
	equal(next(second.Owned).Position, Vector3.new(0, 0, 9), 'moved')
	equal(second.Real, true)

	second:Destroy(0)
end)

case('a one-shot on an instance is not reused on a point', function()
	local attachment = Mock.Instance.new('Attachment')
	local first = Shot:Play({ Muzzle = attachment }) :: any
	first:Destroy(0)

	local second = Shot:Play({ Muzzle = Vector3.zero }) :: any
	truthy(second ~= first, 'a different voice')

	second:Destroy(0)
end)

case('a one-shot past its reach is never built', function()
	local before = Mock.Created
	local voice = Shot:Play({ Muzzle = Vector3.new(500, 0, 0) })

	equal(voice.Alive, false)
	equal(Mock.Created, before, 'instances made')
end)

case('Move moves a point slot', function()
	local voice = Shot:Spawn({ Muzzle = { Vector3.zero, Vector3.one } }) :: any

	voice:Move('Muzzle', { Vector3.new(1, 1, 1), Vector3.new(2, 2, 2) })

	local positions = {}
	for _, at in voice.Slots[voice.Patch.Emitters[1]] do
		table.insert(positions, at.Position)
	end

	equal(positions[1], Vector3.new(1, 1, 1))
	equal(positions[2], Vector3.new(2, 2, 2))

	errors(function()
		voice:Move('Muzzle', Vector3.zero)
	end, 'needs 2 point(s)')

	voice:Destroy(0)
end)

case('Move refuses a slot on an instance', function()
	local voice = Shot:Spawn({ Muzzle = Mock.Instance.new('Attachment') })

	errors(function()
		voice:Move('Muzzle', Vector3.zero)
	end, 'was not spawned on points')

	voice:Destroy(0)
end)

case('destroying a voice destroys its own attachments; parking one keeps them', function()
	local Idle = Audio.Patch({
		Name = 'Idle',
		Bus = 'World',
		Audio.Emitter({ At = 'Here', Audio.Player({ Asset = 'idle', Looping = true }) }),
	})

	local held = Idle:Spawn({ Here = Vector3.zero }) :: any
	local attachment = next(held.Owned)

	held:Destroy(0)
	equal(attachment.Destroyed, true, 'held voice attachment destroyed')

	local shot = Shot:Spawn({ Muzzle = Vector3.zero }) :: any
	attachment = next(shot.Owned)

	shot:Destroy(0)
	equal(shot.Parked, true, 'one-shot parked')
	equal(attachment.Destroyed, nil, 'spare keeps its attachment')
end)

case('a voice woken from inside a step is stepped next frame', function()
	local other = Hum:Spawn()
	frames(3)

	local Poker = Audio.Patch({
		Name = 'Poker',
		Bus = 'UI',
		Params = { y = { Default = 0, Smooth = 5 } },
		Audio.Fader({
			Volume = Audio.Compute({ 'y' }, function(y)
				other:Set('x', y)
				return 1
			end),
			Audio.Player({ Asset = 'p', Looping = true }),
		}),
	})

	local poker = Poker:Spawn()
	frames(3)
	poker:Set('y', 0.5)
	frames(60)

	truthy(other:Get('x') > 0.4, 'woken voice moved')

	poker:Destroy(0)
	other:Destroy(0)
end)

return nil
