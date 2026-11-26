--// Runs the specs under Lune: `lune run tests/run` from the repository root.
--//
--// The sources are copied into tests/.build first, with two changes: `const` becomes `local`, for
--// Lune's older Luau, and each file is handed the engine globals from Mock.luau.

local fs = require('@lune/fs')
local process = require('@lune/process')

local BUILD = 'tests/.build'
local SPECS = { 'Value', 'Patch', 'Voice' }

local GLOBALS = 'game, workspace, Instance, Enum, typeof, Vector3, CFrame'

--[[
	A source file as the build runs it

	@param source string
	@param mock string -- how this file requires Mock.luau
	@return string
--]]
local function adapt(source: string, mock: string): string
	local lines = string.split(source, '\n')
	local header = 0

	--// The header goes after the --! directives, which only count at the very top
	while lines[header + 1] and string.match(lines[header + 1], '^%-%-!') do
		header += 1
	end

	for i, line in lines do
		lines[i] = string.gsub(line, '^const ', 'local ')
	end

	local globals = string.gsub(GLOBALS, '(%w+)', 'Mock.%1')
	table.insert(lines, header + 1, `local Mock = require('{mock}'); local {GLOBALS} = {globals}`)

	return table.concat(lines, '\n')
end

if fs.isDir(BUILD) then fs.removeDir(BUILD) end
fs.writeDir(`{BUILD}/Audio`)

for _, entry in fs.readDir('src') do
	if not string.match(entry, '%.luau$') then continue end

	--// An init file reaches its siblings through @self rather than ./
	local mock = if entry == 'init.luau' then '@self/Mock' else './Mock'
	fs.writeFile(`{BUILD}/Audio/{entry}`, adapt(fs.readFile(`src/{entry}`), mock))
end

fs.writeFile(`{BUILD}/Audio/Mock.luau`, fs.readFile('tests/Mock.luau'))

for _, name in { 'Test', 'Setup' } do
	fs.writeFile(`{BUILD}/{name}.luau`, fs.readFile(`tests/{name}.luau`))
end

for _, name in SPECS do
	fs.writeFile(`{BUILD}/{name}.spec.luau`, fs.readFile(`tests/{name}.spec.luau`))
end

local Test = require('./.build/Test')

for _, name in SPECS do
	Test.suite(name)

	local ok, issue = pcall(require, `./.build/{name}.spec`)
	if not ok then table.insert(Test.Failed, `{name}: failed to load: {issue}`) end
end

print(`\n{Test.Passed} passed, {#Test.Failed} failed`)

for _, failure in Test.Failed do
	print(`  {failure}`)
end

process.exit(if #Test.Failed == 0 then 0 else 1)
