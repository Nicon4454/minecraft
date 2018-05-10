local regulationState = {
	NONE = "none",
	AUTO = "auto",
	PWM = "pwm",
	LOAD = "load",
	GRID = "grid"
}

function regulationState.toString(state)
	if		state == regulationState.NONE then	return "NONE"
	elseif	state == regulationState.AUTO then	return "AUTO"
	elseif	state == regulationState.PWM then	return "PWM"
	elseif	state == regulationState.LOAD then	return "LOAD"
	elseif	state == regulationState.GRID then	return "GRID"
	else										return "UNKNOWN"
	end
end

return regulationState