--// Just enough of the engine for the library to run under Lune. The test runner puts this beside
--// the built sources and hands each of them these globals in place of Roblox's own.

local roblox = require('@lune/roblox')

local Mock = {}

Mock.Vector3 = roblox.Vector3
Mock.CFrame = roblox.CFrame

--// Instances made, and property writes, so far; for checking work is reused rather than redone
Mock.Created = 0
Mock.Writes = 0

local function signal()
	local listeners = {}

	return {
		Connect = function(_, fn)
			listeners[fn] = true

			return {
				Disconnect = function()
					listeners[fn] = nil
				end,
			}
		end,

		Fire = function(_, ...)
			for fn in listeners do
				fn(...)
			end
		end,
	}
end

local Instance = {}

local ISA = {
	Part = { BasePart = true, PVInstance = true },
	Model = { PVInstance = true },
}

Instance.__index = function(self, key)
	local value = rawget(self, 'Properties')[key]
	if value ~= nil then return value end

	return Instance[key]
end

Instance.__newindex = function(self, key, value)
	Mock.Writes += 1
	rawget(self, 'Properties')[key] = value
end

function Instance.IsA(self, class: string): boolean
	return self.ClassName == class or (ISA[self.ClassName] and ISA[self.ClassName][class]) == true
end

function Instance.Play(self)
	self.IsPlaying = true
end

function Instance.Stop(self)
	self.IsPlaying = false
end

function Instance.Destroy(self)
	if self.Destroyed then return end

	self.Destroyed = true
	self.Destroying:Fire()
end

function Instance.SetDistanceAttenuation() end
function Instance.SetAngleAttenuation() end

--// Tests set Audibility on an emitter to move it in or out of earshot
function Instance.GetAudibilityFor(self): number
	return self.Audibility or 1
end

function Instance.GetPropertyChangedSignal()
	return signal()
end

Mock.Instance = {
	new = function(class: string)
		Mock.Created += 1

		return setmetatable({
			Properties = {
				ClassName = class,
				Name = class,
				Destroying = signal(),
				Ended = signal(),
				Looping = false,
				Volume = 1,
				Position = roblox.Vector3.zero,
				CFrame = roblox.CFrame.new(),
			},
		}, Instance)
	end,
}

function Mock.typeof(value: any): string
	if getmetatable(value) == Instance then return 'Instance' end

	return typeof(value)
end

--// The render-step callback the mixer binds, for tests to drive frames with
Mock.Step = nil :: ((deltaTime: number) -> ())?

local services = {
	RunService = {
		IsClient = function()
			return true
		end,
		BindToRenderStep = function(_, _, _, fn)
			Mock.Step = fn
		end,
	},
	SoundService = Mock.Instance.new('SoundService'),
	ContentProvider = {
		PreloadAsync = function() end,
	},
}

Mock.game = {
	GetService = function(_, name: string)
		return services[name]
	end,
}

Mock.workspace = Mock.Instance.new('Workspace')
Mock.workspace.Terrain = Mock.Instance.new('Terrain')
Mock.workspace.CurrentCamera = Mock.Instance.new('Camera')

Mock.Enum = { RenderPriority = { Last = { Value = 2000 } } }

return Mock
