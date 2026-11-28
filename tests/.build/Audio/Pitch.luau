--!strict
--!native
local Mock = require('./Mock'); local game, workspace, Instance, Enum, typeof, Vector3, CFrame = Mock.game, Mock.workspace, Mock.Instance, Mock.Enum, Mock.typeof, Mock.Vector3, Mock.CFrame

--// Helper utility for analyzing spectral pitch of sounds

local Pitch = {}

export type Options = {
	MinHz: number?, -- lowest frequency compared; default 40
	MaxHz: number?, -- highest; default 5000
	Steps: number?, -- points per octave; default 96, an eighth of a semitone
	Range: number?, -- how far either side of the guess to look, as a ratio; default 1.25
	Whiten: number?, -- octaves the broad shape is averaged over; default 1/3
}

--[[
	A spectrum sampled at a frequency, linearly between bins

	@param spectrum {number}
	@param binHz number
	@param hz number
	@return number
--]]
local function at(spectrum: { number }, binHz: number, hz: number): number
	local position = hz / binHz + 1
	local lower = math.floor(position)
	local count = #spectrum

	if lower >= count then return spectrum[count] end
	if lower < 1 then return spectrum[1] end

	local t = position - lower

	return spectrum[lower] * (1 - t) + spectrum[lower + 1] * t
end

--[[
	A spectrum on a log-frequency grid, whitened and normalised to zero mean and unit variance

	@param spectrum {number}
	@param binHz number
	@param minHz number
	@param points number
	@param steps number
	@param window number -- points either side the broad shape is averaged over
	@return {number}
--]]
local function prepare(
	spectrum: { number },
	binHz: number,
	minHz: number,
	points: number,
	steps: number,
	window: number
): { number }
	local logs = table.create(points, 0)

	for i = 1, points do
		local hz = minHz * 2 ^ ((i - 1) / steps)
		logs[i] = math.log(at(spectrum, binHz, hz) + 1e-9)
	end

	--// Subtract a running mean, so what is left is the harmonic detail
	local white = table.create(points, 0)
	local sum = 0
	local lo, hi = 1, 0

	for i = 1, points do
		local wantLo, wantHi = math.max(1, i - window), math.min(points, i + window)

		while hi < wantHi do
			hi += 1
			sum += logs[hi]
		end
		while lo < wantLo do
			sum -= logs[lo]
			lo += 1
		end

		white[i] = logs[i] - sum / (hi - lo + 1)
	end

	local mean = 0
	for i = 1, points do
		mean += white[i]
	end
	mean /= points

	local variance = 0
	for i = 1, points do
		white[i] -= mean
		variance += white[i] * white[i]
	end

	local deviation = math.sqrt(variance / points)
	if deviation < 1e-12 then return white end

	for i = 1, points do
		white[i] /= deviation
	end

	return white
end

--[[
	How well B lines up with A when shifted up by `shift` points

	@param a {number}
	@param b {number}
	@param shift number
	@return number -- normalised correlation, -1..1
--]]
local function correlate(a: { number }, b: { number }, shift: number): number
	local points = #a
	local first = math.max(1, 1 - shift)
	local last = math.min(points, points - shift)

	if last - first < 8 then return -1 end

	local sum, aa, bb = 0, 0, 0

	for i = first, last do
		local x, y = a[i], b[i + shift]
		sum += x * y
		aa += x * x
		bb += y * y
	end

	if aa <= 0 or bb <= 0 then return -1 end

	return sum / math.sqrt(aa * bb)
end

--[[
	The ratio of B's pitch to A's

	@param a {number} -- averaged spectrum, bins evenly spaced from 0 Hz
	@param b {number} -- the same, same bin spacing
	@param binHz number -- Hz between bins
	@param guess number -- the ratio expected, B over A
	@param options Options?
	@return number, number -- the ratio, and how well the two lined up there (0..1; above ~0.5 is a clear match)
--]]
function Pitch.Ratio(a: { number }, b: { number }, binHz: number, guess: number, options: Options?): (number, number)
	local opts: Options = options or {}
	local minHz = opts.MinHz or 40
	local maxHz = math.min(opts.MaxHz or 5000, binHz * (math.min(#a, #b) - 2))
	local steps = opts.Steps or 96
	local range = opts.Range or 1.25
	local window = math.max(2, math.floor(steps * (opts.Whiten or 1 / 3) + 0.5))

	assert(guess > 0, 'Pitch.Ratio - guess must be positive')
	assert(maxHz > minHz * 2, 'Pitch.Ratio - spectra too short for the band asked for')

	local points = math.floor(math.log(maxHz / minHz, 2) * steps) + 1
	local pa = prepare(a, binHz, minHz, points, steps, window)
	local pb = prepare(b, binHz, minHz, points, steps, window)

	--// B higher by ratio r puts its harmonics log2(r) octaves up, so A's peak i is B's i + shift
	local centre = math.log(guess, 2) * steps
	local reach = math.log(range, 2) * steps
	local from, to = math.floor(centre - reach), math.ceil(centre + reach)

	local bestShift, bestScore = from, -math.huge
	local scores = {}

	for shift = from, to do
		local score = correlate(pa, pb, shift)
		scores[shift] = score

		if score > bestScore then
			bestShift, bestScore = shift, score
		end
	end

	--// Parabola through the peak and its neighbours, for a shift finer than one point
	local offset = 0
	local before, after = scores[bestShift - 1], scores[bestShift + 1]

	if before and after then
		local curvature = before - 2 * bestScore + after
		if curvature < 0 then offset = math.clamp(0.5 * (before - after) / curvature, -0.5, 0.5) end
	end

	return 2 ^ ((bestShift + offset) / steps), math.max(bestScore, 0)
end

--[[
	Accumulates spectra frame by frame and averages them

	@return {Add: (spectrum: {number}) -> (), Average: () -> {number}, Frames: () -> number}
--]]
function Pitch.Accumulator()
	local sum: { number } = {}
	local frames = 0

	return {
		Add = function(spectrum: { number })
			if #spectrum == 0 then return end

			for i, value in spectrum do
				sum[i] = (sum[i] or 0) + value
			end

			frames += 1
		end,

		Average = function(): { number }
			local out = table.create(#sum, 0)
			if frames == 0 then return out end

			for i, value in sum do
				out[i] = value / frames
			end

			return out
		end,

		Frames = function(): number
			return frames
		end,
	}
end

return Pitch
