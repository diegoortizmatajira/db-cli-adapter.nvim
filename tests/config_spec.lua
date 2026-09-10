local config = require("db-cli-adapter.config")

describe("config", function()
	describe("default", function()
		it("has all required adapter entries", function()
			assert.is_not_nil(config.default.adapters.psql)
			assert.is_not_nil(config.default.adapters.sqlite)
			assert.is_not_nil(config.default.adapters.mysql)
			assert.is_not_nil(config.default.adapters.mariadb)
			assert.is_not_nil(config.default.adapters.usql)
		end)

		it("has source configurations", function()
			assert.is_string(config.default.sources.global)
			assert.is_function(config.default.sources.workspace)
		end)

		it("has sidebar keybindings", function()
			local kb = config.default.sidebar.keybindings
			assert.is_table(kb.toggle_expand)
			assert.is_table(kb.expand)
			assert.is_table(kb.collapse)
			assert.is_table(kb.quit)
			assert.is_table(kb.refresh)
			assert.is_table(kb.refresh_all)
			assert.is_table(kb.execute_query)
			assert.is_table(kb.open_query)
			assert.is_table(kb.generate_ddl)
			assert.is_table(kb.generate_insert)
			assert.is_table(kb.generate_update)
			assert.is_table(kb.generate_delete)
		end)

		it("has a default sidebar query row limit", function()
			assert.is_number(config.default.sidebar.query_row_limit)
			assert.is_true(config.default.sidebar.query_row_limit > 0)
		end)

		it("has icon configurations", function()
			assert.is_table(config.default.icons.tree)
			assert.is_table(config.default.icons.source)
			assert.is_table(config.default.icons.adapter)
		end)

		it("has correct default adapter icon key", function()
			assert.is_not_nil(config.default.icons.adapter["default"])
		end)

		it("has highlight configurations", function()
			assert.is_table(config.default.highlight.tree)
		end)

		it("has editable output format configuration", function()
			assert.is_table(config.default.output.editable)
			assert.are.equal("csv", config.default.output.editable.format)
		end)

		it("has no new_buffer_handler configured by default", function()
			assert.is_nil(config.default.new_buffer_handler)
		end)
	end)

	describe("update", function()
		after_each(function()
			config.current = nil
		end)

		it("sets current config", function()
			config.update({ test = true })
			assert.is_true(config.current.test)
		end)

		it("ignores nil input", function()
			config.update(nil)
			assert.is_nil(config.current)
		end)
	end)

	describe("attach_lsp_for_filetype_handler", function()
		local previous_get_clients, previous_buf_attach_client
		local bufnr

		before_each(function()
			previous_get_clients = vim.lsp.get_clients
			previous_buf_attach_client = vim.lsp.buf_attach_client
			bufnr = vim.api.nvim_create_buf(false, true)
		end)

		after_each(function()
			vim.lsp.get_clients = previous_get_clients
			vim.lsp.buf_attach_client = previous_buf_attach_client
			if vim.api.nvim_buf_is_valid(bufnr) then
				vim.api.nvim_buf_delete(bufnr, { force = true })
			end
		end)

		it("attaches only clients whose filetypes include the buffer's filetype", function()
			vim.bo[bufnr].filetype = "sql"
			vim.lsp.get_clients = function()
				return {
					{ id = 1, config = { filetypes = { "sql" } } },
					{ id = 2, config = { filetypes = { "python" } } },
				}
			end
			local attached = {}
			vim.lsp.buf_attach_client = function(cb_bufnr, client_id)
				table.insert(attached, { bufnr = cb_bufnr, client_id = client_id })
			end

			config.attach_lsp_for_filetype_handler(bufnr)

			assert.are.same({ { bufnr = bufnr, client_id = 1 } }, attached)
		end)

		it("does nothing when the buffer has no filetype", function()
			vim.lsp.get_clients = function()
				error("get_clients should not be called")
			end
			config.attach_lsp_for_filetype_handler(bufnr)
		end)

		it("does nothing for an invalid buffer", function()
			vim.lsp.get_clients = function()
				error("get_clients should not be called")
			end
			config.attach_lsp_for_filetype_handler(999999)
		end)
	end)

	describe("workspace source", function()
		it("returns a path under stdpath data", function()
			local workspace_path = config.default.sources.workspace()
			local data_path = vim.fn.stdpath("data")
			assert.is_truthy(workspace_path:match("^" .. vim.pesc(data_path)))
			assert.is_truthy(workspace_path:match("workspace%-connections%.json$"))
		end)

		it("includes the folder name in the path", function()
			local workspace_path = config.default.sources.workspace()
			local folder_name = vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
			assert.is_truthy(workspace_path:match(vim.pesc(folder_name)))
		end)
	end)
end)
