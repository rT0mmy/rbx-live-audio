--!strict
--!native
local Mock = require('./Mock'); local game, workspace, Instance, Enum, typeof, Vector3, CFrame = Mock.game, Mock.workspace, Mock.Instance, Mock.Enum, Mock.typeof, Mock.Vector3, Mock.CFrame

local Value = {}

export type Points = { { number } }

export type Spec = {
	Kind: 'Bind' | 'Curve' | 'Compute',
	Params: { string },
	Scale: number?, -- Bind
	Points: Points?, -- Curve, ascending x
	Fn: ((...number) -> any)?, -- Compute
}

local KINDS = { Bind = true, Curve = true, Compute = true }

--[[
	Whether something is a spec rather than a constant

	@param value any
	@return boolean
--]]
function Value.Is(value: any): boolean
	return type(value) == 'table' and KINDS[value.Kind] == true
end

--[[
	A parameter's value as it is, optionally scaled

	@param param string
	@param scale number?
	@return Spec
--]]
function Value.Bind(param: string, scale: number?): Spec
	assert(type(param) == 'string', 'Audio.Bind - param must be a string')

	return { Kind = 'Bind', Params = { param }, Scale = scale }
end

--[[
	A parameter mapped through a piecewise-linear curve. Past either end the curve holds its end
	value, so a curve never extrapolates into something the sound was not tuned for.

	@param param string
	@param points Points -- { {x, y}, ... } in ascending x
	@return Spec
--]]
function Value.Curve(param: string, points: Points): Spec
	assert(type(param) == 'string', 'Audio.Curve - param must be a string')
	assert(type(points) == 'table' and #points >= 1, `Audio.Curve('{param}') - needs at least one point`)

	for i, point in points do
		assert(
			type(point[1]) == 'number' and type(point[2]) == 'number',
			`Audio.Curve('{param}') - point {i} must be a pair of numbers`
		)

		if i > 1 then assert(point[1] > points[i - 1][1], `Audio.Curve('{param}') - points must be in ascending x`) end
	end

	return { Kind = 'Curve', Params = { param }, Points = points }
end

--[[
	Anything else: a function of one or more parameters, given in the order listed. Use it for
	products of curves and the odd case a curve cannot draw; it runs whenever any of them moves.

	@param params {string}
	@param fn (...number) -> any
	@return Spec
--]]
function Value.Compute(params: { string }, fn: (...number) -> any): Spec
	assert(type(params) == 'table' and #params >= 1, 'Audio.Compute - needs at least one param')
	assert(type(fn) == 'function', 'Audio.Compute - needs a function')

	return { Kind = 'Compute', Params = params, Fn = fn }
end

--[[
	Samples a piecewise-linear curve

	@param points Points
	@param x number
	@return number
--]]
function Value.Sample(points: Points, x: number): number
	local count = #points
	local first = points[1]

	if x <= first[1] or count == 1 then return first[2] end

	local last = points[count]
	if x >= last[1] then return last[2] end

	--// Curves are a handful of points; a linear walk beats a binary search at this size
	for i = 2, count do
		local upper = points[i]

		if x <= upper[1] then
			local lower = points[i - 1]
			local t = (x - lower[1]) / (upper[1] - lower[1])

			return lower[2] + (upper[2] - lower[2]) * t
		end
	end

	return last[2]
end

--[[
	Evaluates a spec against a voice's parameter values

	@param spec Spec
	@param indices {number} -- the spec's Params, resolved to the voice's slots
	@param values {number}
	@return any
--]]
function Value.Eval(spec: Spec, indices: { number }, values: { number }): any
	local kind = spec.Kind

	if kind == 'Bind' then return values[indices[1]] * (spec.Scale or 1) end
	if kind == 'Curve' then return Value.Sample(spec.Points :: Points, values[indices[1]]) end

	local fn = spec.Fn :: (...number) -> any
	local count = #indices

	if count == 1 then return fn(values[indices[1]]) end
	if count == 2 then return fn(values[indices[1]], values[indices[2]]) end
	if count == 3 then return fn(values[indices[1]], values[indices[2]], values[indices[3]]) end

	local args = table.create(count)
	for i = 1, count do
		args[i] = values[indices[i]]
	end

	return fn(table.unpack(args, 1, count))
end

--[[
	Frame-rate independent approach toward a target

	@param current number
	@param target number
	@param rate number -- per second; 0 or less snaps
	@param deltaTime number
	@return number
--]]
function Value.Approach(current: number, target: number, rate: number, deltaTime: number): number
	if rate <= 0 then return target end

	local next = current + (target - current) * (1 - math.exp(-rate * deltaTime))
	if math.abs(target - next) <= 1e-4 * math.max(1, math.abs(target)) then return target end

	return next
end

return Value
