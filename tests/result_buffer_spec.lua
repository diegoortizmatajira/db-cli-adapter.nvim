local result_buffer = require("db-cli-adapter.result_buffer")

describe("result_buffer", function()
	local bufnr

	before_each(function()
		bufnr = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(bufnr)
	end)

	after_each(function()
		if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
			vim.api.nvim_buf_delete(bufnr, { force = true })
		end
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

	it("returns error for readonly result buffers", function()
		vim.b[bufnr].db_cli_result_state = {
			editable = false,
		}
		vim.b[bufnr].db_cli_result_readonly_reason = "readonly test reason"

		local changes, err = result_buffer.compute_changes(bufnr)
		assert.is_nil(changes)
		assert.are.equal("readonly test reason", err)
	end)
end)
