--[[ DEBUGGING
local component = require "component"
local computer = require "computer"
--]]

-- ABBREVIATABLES
local huge = math.huge
local ticks = computer.uptime

-- SIGNAL QUEUE AND REALTIME YIELD
local busy = false
local sigqueue = setmetatable({head = 1, tail = 0}, {__len = function (queue) return queue.tail -queue.head + 1 end})
local function push_sig(sig)
	sigqueue.tail = sigqueue.tail + 1
	sigqueue[sigqueue.tail] = sig
end
local function pop_sig()
	local head, tail = sigqueue.head, sigqueue.tail
	if head > tail then return nil end
	local sig = sigqueue[head]
	sigqueue[head], sigqueue.head = nil, head + 1
	if head == tail then sigqueue.head, sigqueue.tail = 1, 0 end
	return sig
end
local function yield_rt(timeout)
	local sig = {computer.pullSignal(timeout or 0)}
	if #sig > 0 and not (busy and sig[1] == "redstone_changed") then push_sig(sig) end
end

-- REDWIRE DRIVER
local nullvec = setmetatable({}, {__index = function () return 0 end})
local m_strseg = {
	__len = function (seg)
		return #seg.data * 2
	end,
	__index = function (seg, idx)
		local chr = seg.data:byte(math.ceil(idx/2)) or 0x00
		if idx%2 == 0 then chr = bit32.rshift(chr, 4) else chr = bit32.band(chr, 0xF) end
		return chr
	end,
	__newindex = function (seg, idx, val)
		local val, stridx = bit32.band(val, 0xF), math.ceil(idx/2)
		local chr = string.byte(seg.data, stridx) or 0x00
		if idx%2 == 0 then chr = bit32.bor(bit32.band(chr, 0xF), bit32.lshift(val, 4)) else chr = bit32.bor(bit32.band(chr, 0xF0), val) end
		seg.data = seg.data:sub(1, stridx-1) .. string.char(chr) .. seg.data:sub(stridx+1)
	end
}
local function rdwr_strseg(rdwr, init)
	return setmetatable({bsize = #rdwr.data, data = init or ""}, m_strseg)
end
local function rdwr_read(rdwr, buffer, offset)
	local tmp, I = rdwr.dvc.getBundledInput(rdwr.side)
	if buffer ~= nil then offset = offset or 1 for I = 1, #rdwr.data do buffer[offset+I-1] = tmp[rdwr.data[I]] end end
	return tmp[rdwr.ctrl]
end
local function rdwr_write(rdwr, control, data, offset)
	offset, data = offset or 0, data or nullvec
	local tmp, I = {[rdwr.ctrl] = control}
	for I = 1, #rdwr.data do tmp[rdwr.data[I]] = data[offset+I-1] end
	rdwr.dvc.setBundledOutput(rdwr.side, tmp)
end
local function rdwr_open(dvc, side, control, ...)
	local rdwr = {dvc = dvc, side = side, ctrl = control, data = {...}, rcvbuf = huge, sndbuf = huge, rcvto = huge, sndto = huge}
	rdwr_write(rdwr, 0)
	return 0, rdwr
end
local function rdwr_snd(rdwr, data, timeout)
	rdwr_write(rdwr, 0)
	timeout, data = timeout or rdwr.sndto, rdwr_strseg(rdwr, data)
	local sendlen, ctrl, wait, I = math.min(#data, rdwr.sndbuf), rdwr_read(rdwr), ticks()
	if ctrl ~= 0 then return -2 end
	rdwr_write(rdwr, 1)
	while true do
		yield_rt()
		ctrl = rdwr_read(rdwr)
		if ctrl == 2 then break
		elseif ctrl == 1 and ticks() - wait >= timeout then return -10
		elseif ctrl ~= 1 then return -3, ctrl end
	end
	local bsize = #rdwr.data
	for I = 1, sendlen, bsize do
		rdwr_write(rdwr, 4+(I%2), data, I)
		if I%10 == 0 then yield_rt() end
	end
	rdwr_write(rdwr, 6)
	rdwr_write(rdwr, 0)
	return sendlen
end
local function rdwr_rcv(rdwr, timeout, maxlen)
	rdwr_write(rdwr, 0)
	timeout, maxlen = timeout or rdwr.rcvto, maxlen or rdwr.rcvbuf
	local ctrl, wait, buffer, I = rdwr_read(rdwr), ticks(), rdwr_strseg(rdwr), 1
	if ctrl ~= 0 and ctrl ~= 1 then return -2 end
	while true do
		if ctrl == 1 then rdwr_write(rdwr, 2) ctrl = 2 break
		elseif ctrl == 0 and ticks() - wait >= timeout then return -10
		elseif ctrl ~= 0 then return -3, ctrl end
		ctrl = rdwr_read(rdwr)
		yield_rt()
	end
	while true do
		ctrl = rdwr_read(rdwr, buffer, (I-1)*buffer.bsize + 1)
		if ctrl == 4+(I%2) then I = I + 1
		elseif (ctrl == 4) or (ctrl == 5) then
		elseif ctrl == 6 then break
		elseif ctrl ~= -2 then return -3, ctrl end
		if I%10 == 0 then yield_rt() end
	end
	buffer.data = buffer.data:sub(1, math.ceil(I*buffer.bsize/2)-1)
	return #buffer.data, buffer.data
end

-- DEVICE INTERACTION
local function comp_proxy(typefilter)
	return component.proxy(component.list(typefilter)())
end

-- AWARENESS
local eeprom = comp_proxy("eeprom")
local config = eeprom.getData()
local params, param = {}
for param in config:gmatch("([^;]*);") do table.insert(params, param) end

-- CONFIGURATION
-- MODEM_PORT;TRUST_PREFIX;RS_SIDE;CONTROL_CHANNEL;BANDWITH;DATA_CHANNEL*BANDWITH
local modem_port, modem_trust = tonumber(params[1]), params[2]
local rs_side, rs_ch_ctrl, rs_bw, rs_ch_data = tonumber(params[3]), tonumber(params[4]), tonumber(params[5]), {}
local I
for I = 1, rs_bw do rs_ch_data[I] = tonumber(params[5+I]) end

-- INITIALIZATION
local _, rdwr = rdwr_open(comp_proxy("redstone"), rs_side, rs_ch_ctrl, rs_bw, table.unpack(rs_ch_data))
local modem = comp_proxy("modem")
modem.open(modem_port)

-- MAIN LOOP
while true do
	local sig, code, data = pop_sig()
	while sig == nil do
		yield_rt(0.1)
		sig = pop_sig()
	end
	
	if sig[1] == "redstone_changed" and sig[3] == rs_side and not busy then
		busy = true
		code, data = rdwr_rcv(rdwr, 0.5)
		rdwr_write(rdwr, 0)
		busy = false
		
		if code > 0 then
			modem.broadcast(modem_port, data)
		end
	elseif sig[1] == "modem_message" and sig[3]:sub(1, #modem_trust) == modem_trust and sig[4] == modem_port then
		push_sig({"relay", sig[6]})
	elseif sig[1] == "relay" and not busy then
		busy = true
		code, _ = rdwr_snd(rdwr, sig[2], 1)
		rdwr_write(rdwr, 0)
		busy = false
		
		if code < 0 then push_sig(sig) end
	end
end