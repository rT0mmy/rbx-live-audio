--!strict
--!native

local Crossfade = {}

const HALF_PI = math.pi / 2

--[[
	Which two layers sound at `x`, and how loud each is

	@param ats {number} -- each layer's position along the parameter, ascending
	@param x number
	@return number, number, number -- the lower layer's index, its weight, and the weight of the layer above it
--]]
function Crossfade.Weights(ats: { number }, x: number): (number, number, number)
	local count = #ats

	if count == 0 then return 0, 0, 0 end
	if x <= ats[1] then return 1, 1, 0 end
	if x >= ats[count] then return count, 1, 0 end

	for i = 1, count - 1 do
		local upper = ats[i + 1]

		if x < upper then
			local lower = ats[i]
			local t = (x - lower) / (upper - lower)

			return i, math.cos(t * HALF_PI), math.sin(t * HALF_PI)
		end
	end

	return count, 1, 0
end

--[[
	The playback speed that puts a layer recorded at `at` on pitch for `x`

	@param x number
	@param at number
	@param min number
	@param max number
	@return number
--]]
function Crossfade.Pitch(x: number, at: number, min: number, max: number): number
	if at <= 0 then return 1 end

	return math.clamp(x / at, min, max)
end

return Crossfade
