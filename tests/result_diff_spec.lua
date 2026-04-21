local result_diff = require("db-cli-adapter.output.result_diff")

describe("result_diff", function()
	it("detects inserts, updates and deletes", function()
		local original_rows = {
			{ id = "1", name = "Alice", role = "admin" },
			{ id = "2", name = "Bob", role = "viewer" },
		}
		local current_rows = {
			{ id = "1", name = "Alice", role = "editor" },
			{ id = "3", name = "Charlie", role = "viewer" },
		}

		local changes, err = result_diff.diff(original_rows, current_rows, { "id", "name", "role" }, { "id" })
		assert.is_nil(err)
		assert.are.equal(1, #changes.inserts)
		assert.are.equal(1, #changes.updates)
		assert.are.equal(1, #changes.deletes)
		assert.are.equal("3", changes.inserts[1].pk.id)
		assert.are.equal("1", changes.updates[1].pk.id)
		assert.are.equal("editor", changes.updates[1].changed_columns.role.new)
		assert.are.equal("2", changes.deletes[1].pk.id)
	end)

	it("supports composite primary keys", function()
		local original_rows = {
			{ account_id = "1", region = "us", quota = "100" },
		}
		local current_rows = {
			{ account_id = "1", region = "us", quota = "101" },
		}

		local changes, err =
			result_diff.diff(original_rows, current_rows, { "account_id", "region", "quota" }, { "account_id", "region" })
		assert.is_nil(err)
		assert.are.equal(1, #changes.updates)
		assert.are.equal("101", changes.updates[1].changed_columns.quota.new)
	end)

	it("returns error when PK value is missing", function()
		local original_rows = {}
		local current_rows = {
			{ id = "", name = "Alice" },
		}
		local _, err = result_diff.diff(original_rows, current_rows, { "id", "name" }, { "id" })
		assert.is_not_nil(err)
	end)

	it("returns error when duplicate PK is detected", function()
		local original_rows = {}
		local current_rows = {
			{ id = "1", name = "Alice" },
			{ id = "1", name = "Alice copy" },
		}
		local _, err = result_diff.diff(original_rows, current_rows, { "id", "name" }, { "id" })
		assert.is_not_nil(err)
	end)

	it("ignores pk-only changes in update set", function()
		local original_rows = {
			{ id = "1", name = "Alice" },
		}
		local current_rows = {
			{ id = "1", name = "Alice" },
		}
		local changes, err = result_diff.diff(original_rows, current_rows, { "id", "name" }, { "id" })
		assert.is_nil(err)
		assert.are.equal(0, #changes.updates)
	end)
end)
