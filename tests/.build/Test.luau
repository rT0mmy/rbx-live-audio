--// A small test harness: Test.case runs a function and records whether it errored

local Test = {}

Test.Passed = 0
Test.Failed = {} :: { string }

local suite = ''

function Test.suite(name: string)
	suite = name
	print(`\n{name}`)
end

function Test.case(name: string, fn: () -> ())
	local ok, issue = pcall(fn)

	if ok then
		Test.Passed += 1
		print(`  ok    {name}`)
	else
		table.insert(Test.Failed, `{suite} > {name}: {issue}`)
		print(`  FAIL  {name}\n        {issue}`)
	end
end

function Test.equal(actual: any, expected: any, label: string?)
	if actual ~= expected then error(`{label or 'value'}: expected {tostring(expected)}, got {tostring(actual)}`, 2) end
end

function Test.near(actual: number, expected: number, tolerance: number?, label: string?)
	if math.abs(actual - expected) > (tolerance or 1e-6) then
		error(`{label or 'value'}: expected about {expected}, got {actual}`, 2)
	end
end

function Test.truthy(value: any, label: string?)
	if not value then error(`{label or 'condition'} did not hold`, 2) end
end

--// Errors unless fn errors with a message containing `pattern` (plain text)
function Test.errors(fn: () -> (), pattern: string)
	local ok, issue = pcall(fn)

	if ok then error(`expected an error containing '{pattern}'`, 2) end
	if not string.find(tostring(issue), pattern, 1, true) then
		error(`expected an error containing '{pattern}', got: {issue}`, 2)
	end
end

return Test
