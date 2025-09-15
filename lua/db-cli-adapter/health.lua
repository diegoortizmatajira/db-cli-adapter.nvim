local M = {}

function M.check()
	local config = require("db-cli-adapter.config")
	for _, adapter in pairs(config.current.adapters) do
		adapter:health_check()
	end
end

return M
