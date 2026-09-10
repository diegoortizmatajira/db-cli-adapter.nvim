local config = require("db-cli-adapter.config")
local core = require("db-cli-adapter.core")

describe("core", function()
	describe("trigger_new_buffer", function()
		local previous_config

		before_each(function()
			previous_config = config.current
			config.current = vim.tbl_deep_extend("force", config.default, {})
		end)

		after_each(function()
			config.current = previous_config
		end)

		it("invokes the configured new_buffer_handler with the buffer number", function()
			local calls = {}
			config.current.new_buffer_handler = function(bufnr)
				table.insert(calls, bufnr)
			end

			core.trigger_new_buffer(42)

			assert.are.same({ 42 }, calls)
		end)

		it("does nothing when no new_buffer_handler is configured", function()
			config.current.new_buffer_handler = nil
			assert.has_no.errors(function()
				core.trigger_new_buffer(42)
			end)
		end)

		it("does nothing when there is no current configuration", function()
			config.current = nil
			assert.has_no.errors(function()
				core.trigger_new_buffer(42)
			end)
		end)
	end)
end)
