local result_buffer = require("db-cli-adapter.output.result_buffer")
local config_mod = require("db-cli-adapter.config")
local core = require("db-cli-adapter.core")

describe("result_buffer", function()
	local bufnr
	local previous_config
	local previous_core_run
	local previous_output_module

	before_each(function()
		previous_config = config_mod.current
		previous_core_run = core.run
		previous_output_module = package.loaded["db-cli-adapter.output"]
		package.loaded["db-cli-adapter.output"] = {
			split = nil,
			show = function() end,
		}
		config_mod.current = vim.tbl_deep_extend("force", config_mod.default, {})
		config_mod.current.output.editable.format = "tsv"
		bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(bufnr)
	end)

	after_each(function()
		if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end
		config_mod.current = previous_config
		core.run = previous_core_run
		package.loaded["db-cli-adapter.output"] = previous_output_module
	end)

	it("computes inserts updates and deletes from editable buffer", function()
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
			"id\tname\trole",
			"1\tAlice\teditor",
			"3\tCharlie\tviewer",
		})
		vim.b[bufnr].db_cli_result_state = {
			query = "select * from users",
			connection = "test",
			adapter_name = "psql",
			schema = "public",
			table = "users",
			columns = { "id", "name", "role" },
			pk_columns = { "id" },
			original_rows = {
				{ id = "1", name = "Alice", role = "admin" },
				{ id = "2", name = "Bob", role = "viewer" },
			},
			editable = true,
		}

		local changes, err = result_buffer.compute_changes(bufnr)
		assert.is_nil(err)
		assert.are.equal(1, #changes.inserts)
		assert.are.equal(1, #changes.updates)
		assert.are.equal(1, #changes.deletes)
	end)

	it("returns error when header is modified", function()
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
			"id\tusername\trole",
			"1\tAlice\tadmin",
		})
		vim.b[bufnr].db_cli_result_state = {
			query = "select * from users",
			connection = "test",
			adapter_name = "psql",
			schema = "public",
			table = "users",
			columns = { "id", "name", "role" },
			pk_columns = { "id" },
			original_rows = {
				{ id = "1", name = "Alice", role = "admin" },
			},
			editable = true,
		}

		local changes, err = result_buffer.compute_changes(bufnr)
		assert.is_nil(changes)
		assert.is_not_nil(err)
	end)

	it("invokes new_buffer_handler when opening a changes-preview buffer", function()
		local calls = {}
		config_mod.current.new_buffer_handler = function(cb_bufnr)
			table.insert(calls, cb_bufnr)
		end
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
			"id\tname\trole",
			"1\tAlice\teditor",
		})
		vim.b[bufnr].db_cli_result_state = {
			query = "select * from users",
			connection = "test",
			adapter_name = "psql",
			schema = "public",
			table = "users",
			columns = { "id", "name", "role" },
			pk_columns = { "id" },
			original_rows = {
				{ id = "1", name = "Alice", role = "admin" },
			},
			editable = true,
		}

		result_buffer.preview_changes(bufnr)
		local preview_bufnr = vim.api.nvim_get_current_buf()

		assert.are.same({ preview_bufnr }, calls)

		-- The preview buffer is `bufhidden = "wipe"`, so switching away wipes it automatically.
		if preview_bufnr ~= bufnr and vim.api.nvim_buf_is_valid(bufnr) then
			vim.api.nvim_set_current_buf(bufnr)
		end
	end)

	it("returns error for readonly result buffers", function()
		vim.b[bufnr].db_cli_result_state = {
			editable = false,
		}
		vim.b[bufnr].db_cli_result_readonly_reason = "readonly test reason"

		local changes, err = result_buffer.compute_changes(bufnr)
		assert.is_nil(changes)
		assert.are.equal("readonly test reason", err)
	end)

	it("opens editable results in a new buffer instead of mutating query buffer", function()
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "SELECT * FROM users;" })
		local original_bufnr = bufnr
		local result = {
			data = {
				column_names = { "id", "name" },
				rows = {
					{ "1", "Alice" },
				},
			},
		}
		local context = {
			query = "select * from users join teams on users.team_id = teams.id",
			connection_name = "test",
			adapter_name = "psql",
		}

		result_buffer.open_from_result(result, context)

		local new_bufnr = vim.api.nvim_get_current_buf()
		assert.are_not.equal(original_bufnr, new_bufnr)
		assert.are.same({ "SELECT * FROM users;" }, vim.api.nvim_buf_get_lines(original_bufnr, 0, -1, false))
		assert.are.same({ "id\tname", "1\tAlice" }, vim.api.nvim_buf_get_lines(new_bufnr, 0, -1, false))

		if vim.api.nvim_buf_is_valid(new_bufnr) then
			vim.api.nvim_set_current_buf(original_bufnr)
			vim.api.nvim_buf_delete(new_bufnr, { force = true })
		end
	end)

	it("invokes output.csv.after_query_callback with a nil file_path", function()
		local calls = {}
		config_mod.current.output.csv.after_query_callback = function(cb_bufnr, file_path)
			table.insert(calls, { bufnr = cb_bufnr, file_path = file_path })
		end
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "SELECT * FROM users;" })
		local result = {
			data = {
				column_names = { "id", "name" },
				rows = { { "1", "Alice" } },
			},
		}
		local context = {
			query = "select * from users join teams on users.team_id = teams.id",
			connection_name = "test",
			adapter_name = "psql",
		}

		result_buffer.open_from_result(result, context)
		local new_bufnr = vim.api.nvim_get_current_buf()

		assert.are.equal(1, #calls)
		assert.are.equal(new_bufnr, calls[1].bufnr)
		assert.is_nil(calls[1].file_path)

		if vim.api.nvim_buf_is_valid(new_bufnr) then
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_delete(new_bufnr, { force = true })
		end
	end)

	it("invokes new_buffer_handler for a newly opened editable result buffer", function()
		local calls = {}
		config_mod.current.new_buffer_handler = function(cb_bufnr)
			table.insert(calls, cb_bufnr)
		end
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "SELECT * FROM users;" })
		local result = {
			data = {
				column_names = { "id", "name" },
				rows = { { "1", "Alice" } },
			},
		}
		local context = {
			query = "select * from users join teams on users.team_id = teams.id",
			connection_name = "test",
			adapter_name = "psql",
		}

		result_buffer.open_from_result(result, context)
		local new_bufnr = vim.api.nvim_get_current_buf()

		assert.are.same({ new_bufnr }, calls)

		if vim.api.nvim_buf_is_valid(new_bufnr) then
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_delete(new_bufnr, { force = true })
		end
	end)

	it("does not invoke new_buffer_handler when reusing an existing target buffer", function()
		local calls = {}
		config_mod.current.new_buffer_handler = function(cb_bufnr)
			table.insert(calls, cb_bufnr)
		end
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "SELECT * FROM users;" })
		local result = {
			data = {
				column_names = { "id", "name" },
				rows = { { "1", "Alice" } },
			},
		}
		local context = {
			query = "select * from users join teams on users.team_id = teams.id",
			connection_name = "test",
			adapter_name = "psql",
		}

		result_buffer.open_from_result(result, context, { target_bufnr = bufnr })

		assert.are.same({}, calls)
	end)

	it("computes changes from CSV editable format when configured", function()
		config_mod.current.output.editable.format = "csv"
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
			"id,name,role",
			'1,"Alice, Sr.",editor',
		})
		vim.b[bufnr].db_cli_result_state = {
			query = "select * from users",
			connection = "test",
			adapter_name = "psql",
			schema = "public",
			table = "users",
			columns = { "id", "name", "role" },
			pk_columns = { "id" },
			original_rows = {
				{ id = "1", name = "Alice, Sr.", role = "admin" },
			},
			editable = true,
		}

		local changes, err = result_buffer.compute_changes(bufnr)
		assert.is_nil(err)
		assert.are.equal(0, #changes.inserts)
		assert.are.equal(1, #changes.updates)
		assert.are.equal(0, #changes.deletes)
	end)

	it("renders editable result buffer as CSV when configured", function()
		config_mod.current.output.editable.format = "csv"
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "SELECT * FROM users;" })
		local result = {
			data = {
				column_names = { "id", "name" },
				rows = {
					{ "1", "Alice, Sr." },
				},
			},
		}
		local context = {
			query = "select * from users join teams on users.team_id = teams.id",
			connection_name = "test",
			adapter_name = "psql",
		}

		result_buffer.open_from_result(result, context)
		local new_bufnr = vim.api.nvim_get_current_buf()
		assert.are.equal("db-cli-output.csv", vim.bo[new_bufnr].filetype)
		assert.are.same({ "id,name", '1,"Alice, Sr."' }, vim.api.nvim_buf_get_lines(new_bufnr, 0, -1, false))

		if vim.api.nvim_buf_is_valid(new_bufnr) then
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_delete(new_bufnr, { force = true })
		end
	end)

	it("keeps editable CSV buffers writable after opening", function()
		config_mod.current.output.editable.format = "csv"
		core.run = function(_, opts)
			opts.callback({
				data = {
					rows = {
						{ "id" },
					},
				},
			})
		end

		local result = {
			data = {
				column_names = { "id", "name" },
				rows = {
					{ "1", "Alice" },
				},
			},
		}
		local context = {
			query = "select id, name from users",
			connection_name = "test",
			adapter_name = "psql",
			adapter = {
				get_primary_keys_query = function()
					return "SELECT 'id' AS column_name"
				end,
			},
		}

		result_buffer.open_from_result(result, context)
		vim.wait(50)
		local new_bufnr = vim.api.nvim_get_current_buf()
		assert.are.equal("db-cli-output.csv", vim.bo[new_bufnr].filetype)
		assert.is_true(vim.bo[new_bufnr].modifiable)
		assert.is_false(vim.bo[new_bufnr].readonly)

		if vim.api.nvim_buf_is_valid(new_bufnr) then
			vim.api.nvim_set_current_buf(bufnr)
			vim.api.nvim_buf_delete(new_bufnr, { force = true })
		end
	end)
end)
