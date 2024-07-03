--!nocheck
--!optimize 2
--!native

local FREE_THREADS = {}

local function runCallback(callback, thread, ...)
	callback(...)
	table.insert(FREE_THREADS, thread)
end

local function yielder()
	while true do
		runCallback(coroutine.yield())
	end
end

local function shouldTrackConnections(self)
	return self.is(self.OnConnectionsChanged) == true and type(self.TotalConnections) == "number"
end

local Connection = {}
Connection.__index = Connection

local function disconnect(self)
	if not self.Connected then
		return
	end
	self.Connected = false

	local next = self._next
	local prev = self._prev

	if next then
		next._prev = prev
	end
	if prev then
		prev._next = next
	end

	local signal = self._signal
	if signal._head == self then
		signal._head = next
	end

	if shouldTrackConnections(signal) then
		signal.TotalConnections -= 1
		signal.OnConnectionsChanged:Fire(-1)
	end
end

local function reconnect(self)
	if self.Connected then
		return
	end
	self.Connected = true

	local signal = self._signal
	local head = signal._head
	if head then
		head._prev = self
	end
	signal._head = self

	self._next = head
	self._prev = false

	if shouldTrackConnections(signal) then
		signal.TotalConnections += 1
		signal.OnConnectionsChanged:Fire(1)
	end
end

Connection.Destroy = disconnect
Connection.Disconnect = disconnect
Connection.Reconnect = reconnect

local Signal = {}
Signal.__index = Signal

local rbxConnect, rbxDisconnect
do
	if task then
		local bindable = Instance.new("BindableEvent")
		rbxConnect = bindable.Event.Connect
		rbxDisconnect = bindable.Event:Connect(function() end).Disconnect
		bindable:Destroy()
	end
end

local function connect(self, fn, ...)
	local head = self._head
	local cn = setmetatable({
		Connected = true,
		_signal = self,
		_fn = fn,
		_varargs = if not ... then false else { ... },
		_next = head,
		_prev = false,
	}, Connection)

	if head then
		head._prev = cn
	end
	self._head = cn

	if shouldTrackConnections(self) then
		self.TotalConnections += 1
		self.OnConnectionsChanged:Fire(1)
	end

	return cn
end

local function once(self, fn, ...)
	local cn
	cn = connect(self, function(...)
		disconnect(cn)
		fn(...)
	end, ...)
	return cn
end

local wait = if task
	then function(self)
		local thread = coroutine.running()
		local cn
		cn = connect(self, function(...)
			disconnect(cn)
			task.spawn(thread, ...)
		end)
		return coroutine.yield()
	end
	else function(self)
		local thread = coroutine.running()
		local cn
		cn = connect(self, function(...)
			disconnect(cn)
			local passed, message = coroutine.resume(thread, ...)
			if not passed then
				error(message, 0)
			end
		end)
		return coroutine.yield()
	end

local fire = if task
	then function(self, ...)
		local cn = self._head
		while cn do
			local thread
			local freeThreadsAmount = #FREE_THREADS
			if freeThreadsAmount > 0 then
				thread = FREE_THREADS[freeThreadsAmount]
				FREE_THREADS[freeThreadsAmount] = nil
			else
				thread = coroutine.create(yielder)
				coroutine.resume(thread)
			end

			if not cn._varargs then
				task.spawn(thread, cn._fn, thread, ...)
			else
				local args = cn._varargs
				local len = #args
				local count = len
				for _, value in { ... } do
					count += 1
					args[count] = value
				end

				task.spawn(thread, cn._fn, thread, table.unpack(args))

				for i = count, len + 1, -1 do
					args[i] = nil
				end
			end

			cn = cn._next
		end
	end
	else function(self, ...)
		local cn = self._head
		while cn do
			local thread
			local freeThreadsAmount = #FREE_THREADS
			if freeThreadsAmount > 0 then
				thread = FREE_THREADS[freeThreadsAmount]
				FREE_THREADS[freeThreadsAmount] = nil
			else
				thread = coroutine.create(yielder)
				coroutine.resume(thread)
			end

			if not cn._varargs then
				local passed, message = coroutine.resume(thread, cn._fn, thread, ...)
				if not passed then
					print(string.format("%s\nstacktrace:\n%s", message, debug.traceback()))
				end
			else
				local args = cn._varargs
				local len = #args
				local count = len
				for _, value in { ... } do
					count += 1
					args[count] = value
				end

				local passed, message = coroutine.resume(thread, cn._fn, thread, table.unpack(args))
				if not passed then
					print(string.format("%s\nstacktrace:\n%s", message, debug.traceback()))
				end

				for i = count, len + 1, -1 do
					args[i] = nil
				end
			end

			cn = cn._next
		end
	end

local function disconnectAll(self)
	local cn = self._head
	while cn do
		disconnect(cn)
		cn = cn._next
	end

	if shouldTrackConnections(self) then
		self.OnConnectionsChanged:Fire(-self.TotalConnections)
		self.TotalConnections = 0
	end
end

local function destroy(self)
	disconnectAll(self)
	local cn = self.RBXScriptConnection
	if cn then
		rbxDisconnect(cn)
		self.RBXScriptConnection = nil
	end

	if shouldTrackConnections(self) then
		self.OnConnectionsChanged:Destroy()
		self.OnConnectionsChanged = nil
	end
end

function Signal.is(object)
	return type(object) == "table" and getmetatable(object) == Signal
end

function Signal.new(trackConnections)
	local self = setmetatable({ _head = false }, Signal)

	if type(trackConnections) == "boolean" and trackConnections then
		self.TotalConnections = 0
		self.OnConnectionsChanged = Signal.new(false)
	end

	return self
end

function Signal.wrap(signal, trackConnections)
	local wrapper = Signal.new(trackConnections)

	wrapper.RBXScriptConnection = rbxConnect(signal, function(...)
		fire(wrapper, ...)
	end)

	return wrapper
end

Signal.Connect = connect
Signal.Once = once
Signal.Wait = wait
Signal.Fire = fire
Signal.DisconnectAll = disconnectAll
Signal.Destroy = destroy

return {
	["Signal"] = { ["is"] = Signal.is, ["new"] = Signal.new, ["wrap"] = Signal.wrap },
}
