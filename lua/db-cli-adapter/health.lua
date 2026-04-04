local M = {}

function M.check()
	vim.health.start("db-cli-adapter")

	-- Check plugin dependencies
	local has_nui, _ = pcall(require, "nui.split")
	if has_nui then
		vim.health.ok("nui.nvim installed")
	else
		vim.health.error("nui.nvim not found", { "Install MunifTanjim/nui.nvim" })
	end

	local has_overseer, _ = pcall(require, "overseer")
	if has_overseer then
		vim.health.ok("overseer.nvim installed")
	else
		vim.health.warn("overseer.nvim not found (needed for terminal output mode)", { "Install stevearc/overseer.nvim" })
	end

	-- Check adapter CLI tools
	local config = require("db-cli-adapter.config")
	for _, adapter in pairs(config.current.adapters) do
		adapter:health_check()
	end
end

return M
