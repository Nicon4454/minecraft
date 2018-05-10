local turbineState = {
	ERROR			= -2,
	OFFLINE			= -1,
	STARTING		= 0,
	CALIBRATING		= 1,
	KICKOFF			= 2,
	SPINUP			= 3,
	SPINUP_SLOW		= 4,
	SPINDOWN		= 5,
	SPINDOWN_FAST	= 6,
	STABLE			= 7,
	SUSPENDED		= 8
}

function turbineState.toString(state)
	if		state == turbineState.ERROR then			return "ERROR"
	elseif	state == turbineState.OFFLINE then			return "OFFLINE"
	elseif	state == turbineState.STARTING then			return "STARTING"
	elseif	state == turbineState.CALIBRATING then		return "CALIBRATING"
	elseif	state == turbineState.KICKOFF then			return "KICKOFF"
	elseif	state == turbineState.SPINUP then			return "SPINUP"
	elseif	state == turbineState.SPINUP_SLOW then		return "SLOW SPINUP"
	elseif	state == turbineState.SPINDOWN then			return "SPINDOWN"
	elseif	state == turbineState.SPINDOWN_FAST then	return "FAST SPINDOWN"
	elseif	state == turbineState.STABLE then			return "STABLE"
	elseif	state == turbineState.SUSPENDED then		return "SUSPENDED"
	else												return "UNKNOWN"
	end
end


return turbineState;