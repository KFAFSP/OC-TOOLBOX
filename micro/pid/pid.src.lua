-- MATH HELPERS
function clamp(min_inc, value, max_inc)
	return math.max(math.min(value, max_inc), min_inc)
end

-- PID CONTROLLER
function pid_create(p, i, d, min_out, max_out)
	p, i, d, min_out, max_out = p or 1, i or 0, d or 0, min_out or -math.huge, max_out or math.huge
	return {p = p, i = i, d = d, auto = false, mino = min_out, maxo = max_out, set = 0, out = 0, last = 0, int = 0}
end
function pid_update(pid, input, delta_t)
	if pid.auto == false then return pid.out end
	local err, errDiff = pid.set - input, (input + pid.last) / delta_t
	pid.int = clamp(pid.mino, pid.int + (err * delta_t * pid.i), pid.maxo)
	pid.out = clamp(pid.mino, pid.p * err + pid.int - pid.d * errDiff, pid.maxo)
	return pid.out
end

