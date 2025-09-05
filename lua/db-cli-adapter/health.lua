local M = {}

function M.check()
	local plugin = require("db-cli-adapter")
	for _, adapter in pairs(plugin.config.adapters) do
		adapter:health_check()
	end
end

return M
