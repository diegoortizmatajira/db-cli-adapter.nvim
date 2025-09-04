local utils = {}
function utils.check_executable(cmd)
	if vim.fn.executable(cmd) then
		vim.health.ok(string.format("'%s' is installed", cmd))
	else
		vim.health.warn(string.format("'%s' is not available", cmd))
	end
end
return utils
