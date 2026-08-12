local utils = {}

--- Returns whether the given command is available in the system PATH.
--- @param cmd string
--- @return boolean
function utils.is_executable(cmd)
	return vim.fn.executable(cmd) == 1
end

function utils.check_executable(cmd)
	if utils.is_executable(cmd) then
		vim.health.ok(string.format("'%s' is installed", cmd))
	else
		vim.health.warn(string.format("'%s' is not available", cmd))
	end
end
return utils
