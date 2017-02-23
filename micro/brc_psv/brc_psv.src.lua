local component = require "component"
local event = require "event"
local term = require "term"
local computer = require "computer"

-- MATH HELPERS
local function clamp(min_inc, value, max_inc)
	return math.max(math.min(value, max_inc), min_inc) or min_inc
end

-- PID CONTROLLER
local function pid_create(p, i, d, min_out, max_out)
	p, i, d, min_out, max_out = p or 1, i or 0, d or 0, min_out or -math.huge, max_out or math.huge
	return {p = p, i = i, d = d, auto = false, mino = min_out, maxo = max_out, set = 0, out = 0, last = 0, int = 0}
end
local function pid_update(pid, input, delta_t)
	if pid.auto == false then return pid.out end
	local err, errDiff = pid.set - input, (input + pid.last) / math.max(0.01, delta_t)
	pid.int = clamp(pid.mino, pid.int + (err * delta_t * pid.i), pid.maxo)
	pid.out = clamp(pid.mino, pid.p * err + pid.int - pid.d * errDiff, pid.maxo)
	return pid.out
end

-- BIG REACTOR (PASSIVE) CONTROLLER
local function brpsv_create(dvc, etaMax, rEOn, rEOff, tOff)
	etaMax, rEOn, rEOff, tOff = etaMax or {theta = -1, eta = -1}, rEOn or 0.1, rEOff or 0.9, tOff or 5
	local brpsv = {dvc = dvc, conf = {etaMax = etaMax, rEOn = rEOn, rEOff = rEOff, tOff = tOff}, status = {}, pid = pid_create(-0.8,0.5,0,0,100), mode = "off"}
	if etaMax.theta == -1 then brpsv.mode = "boot" end
	brpsv.pid.auto = true
	return brpsv
end
local function brpsv_update(brpsv)
	local now = computer.uptime()
	local delta_t = (now - (brpsv.last or (now - 1)))
	brpsv.last = now
	
	local active = brpsv.dvc.getActive()
	local status = {
		theta = brpsv.dvc.getFuelTemperature(),
		eta = brpsv.dvc.getFuelReactivity(),
		E = brpsv.dvc.getEnergyStored(),
		P = brpsv.dvc.getEnergyProducedLastTick(),
	}	
	
	local capacity = brpsv.dvc.getEnergyCapacity()
	status.rE, status.dE = status.E / capacity, (status.E - (brpsv.status.E or status.E)) / (delta_t*20)
	brpsv.status = status
		
	if brpsv.mode == "none" then
		return
	elseif brpsv.mode == "off" then
		brpsv.dvc.setActive(false)
	elseif brpsv.mode == "on" then
		brpsv.dvc.setActive(true)
	elseif brpsv.mode == "boot" then
		if active then
			if status.eta > brpsv.conf.etaMax.eta then
				brpsv.conf.etaMax.theta, brpsv.conf.etaMax.eta = status.theta, status.eta
			elseif status.theta > brpsv.conf.etaMax.theta + 80 then
				brpsv.mode = "auto"
			end
		elseif status.theta < 50 then
			brpsv.dvc.setActive(true)
			brpsv.dvc.setAllControlRodLevels(70)
		end
	elseif brpsv.mode == "auto" then	
		if active then
			brpsv.pid.set = brpsv.conf.etaMax.theta
			brpsv.dvc.setAllControlRodLevels(pid_update(brpsv.pid, status.theta, delta_t))
		
			-- Turn off condition
			if status.rE > brpsv.conf.rEOff then
				brpsv.dvc.setActive(false)
			end
		else
			-- Turn on condition
			local remain
			if status.dE >= 0 then
				remain = math.huge
			else
				remain = (status.E - (brpsv.conf.rEOn * capacity)) / -status.dE / 20
			end
			if remain <= brpsv.conf.tOff then
				brpsv.dvc.setActive(true)
			end
		end
	end
end

local brpsv = brpsv_create(component.br_reactor, {eta = 420, theta = 620})
brpsv.mode = "auto"
term.clear()

while true do
	local event = {event.pull(0.1)}
	
	if event[1] == "key_down" then
		local chr = string.char(event[3])
		if chr == "q" then
			return	
		elseif chr == "t" then
			brpsv.conf.etaMax.theta = brpsv.conf.etaMax.theta + 10
		elseif chr == "g" then
			brpsv.conf.etaMax.theta = brpsv.conf.etaMax.theta - 10
		end
	end
	
	brpsv_update(brpsv)
	
	term.setCursor(1, 1)
	term.write(string.format("MODE: %s, SET: %d, OUT: %d", brpsv.mode, brpsv.pid.set, brpsv.pid.out) .. string.rep(" ", 10))
	term.setCursor(1, 2)
	term.write(string.format("TEMP: %d, ETA: %d, dE: %.2f", brpsv.status.theta, brpsv.status.eta, brpsv.status.dE) .. string.rep(" ", 10))
end