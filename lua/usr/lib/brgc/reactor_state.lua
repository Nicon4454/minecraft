local reactorState = {
	ERROR = -2,
	OFFLINE = -1,
	CALIBRATING = 1,
	ONLINE = 2
};

function reactorState.toString(state)
	if		state == reactorState.ERROR then		return "ERROR"
	elseif	state == reactorState.OFFLINE then		return "OFFLINE"
	elseif	state == reactorState.CALIBRATING then	return "CALIBRATING"
	elseif	state == reactorState.ONLINE then		return "ONLINE"
	else											return "UNKNOWN"
	end
end

return reactorState;