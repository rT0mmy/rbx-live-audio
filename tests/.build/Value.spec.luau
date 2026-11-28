local Crossfade = require('./Audio/Crossfade')
local Test = require('./Test')
local Value = require('./Audio/Value')

local case, equal, near, errors = Test.case, Test.equal, Test.near, Test.errors

case('Sample holds its end values past either end', function()
	local points = { { 0, 1 }, { 10, 3 } }

	equal(Value.Sample(points, -5), 1)
	equal(Value.Sample(points, 50), 3)
end)

case('Sample interpolates between points', function()
	local points = { { 0, 0 }, { 10, 10 }, { 20, 0 } }

	near(Value.Sample(points, 5), 5)
	near(Value.Sample(points, 15), 5)
	near(Value.Sample(points, 10), 10)
end)

case('Sample of a single point is constant', function()
	equal(Value.Sample({ { 3, 7 } }, -100), 7)
	equal(Value.Sample({ { 3, 7 } }, 100), 7)
end)

case('Curve rejects points out of order', function()
	errors(function()
		Value.Curve('x', { { 1, 0 }, { 0, 1 } })
	end, 'ascending x')
end)

case('Eval runs Bind, Curve and Compute', function()
	local values = { 2, 5 }

	equal(Value.Eval(Value.Bind('a', 3), { 1 }, values), 6)
	near(Value.Eval(Value.Curve('a', { { 0, 0 }, { 4, 1 } }), { 1 }, values), 0.5)

	local compute = Value.Compute({ 'a', 'b' }, function(a, b)
		return a * b
	end)
	equal(Value.Eval(compute, { 1, 2 }, values), 10)
end)

case('Approach snaps at rate 0 and lands exactly on its target', function()
	equal(Value.Approach(0, 1, 0, 1 / 60), 1)

	local x = 0
	for _ = 1, 600 do
		x = Value.Approach(x, 1, 20, 1 / 60)
	end

	equal(x, 1)
end)

case('Crossfade weights are equal-power', function()
	local ats = { 1000, 3000, 6000 }

	for _, x in { 1000, 1500, 2999, 3000, 4500, 5999 } do
		local _, lower, upper = Crossfade.Weights(ats, x)
		near(lower * lower + upper * upper, 1, 1e-9, `power at {x}`)
	end
end)

case('Crossfade weights clamp to the end layers', function()
	local ats = { 1000, 3000 }

	local i, lower, upper = Crossfade.Weights(ats, 0)
	equal(i, 1)
	equal(lower, 1)
	equal(upper, 0)

	i, lower, upper = Crossfade.Weights(ats, 9000)
	equal(i, 2)
	equal(lower, 1)
	equal(upper, 0)
end)

case('Crossfade pitch tracks and clamps', function()
	near(Crossfade.Pitch(2000, 1000, 0.25, 4), 2)
	equal(Crossfade.Pitch(100000, 1000, 0.25, 4), 4)
	equal(Crossfade.Pitch(5, 0, 0.25, 4), 1)
end)

return nil
