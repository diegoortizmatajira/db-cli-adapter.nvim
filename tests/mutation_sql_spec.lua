local mutation_sql = require("db-cli-adapter.mutation_sql")

describe("mutation_sql", function()
	it("generates insert, update and delete statements", function()
		local changes = {
			inserts = {
				{ row = { id = "3", name = "Charlie", role = "viewer" } },
			},
			updates = {
				{
					pk = { id = "1" },
					changed_columns = {
						role = { old = "admin", new = "editor" },
					},
				},
			},
			deletes = {
				{ pk = { id = "2" } },
			},
		}
		local table_meta = {
			schema = "public",
			table = "users",
			columns = { "id", "name", "role" },
			pk_columns = { "id" },
		}

		local statements = mutation_sql.generate(changes, table_meta, nil)
		assert.are.equal(3, #statements)
		assert.is_truthy(statements[1]:match('INSERT INTO "public"%.\"users\"'))
		assert.is_truthy(statements[2]:match('UPDATE "public"%.\"users\" SET "role" = \'editor\' WHERE "id" = \'1\';'))
		assert.is_truthy(statements[3]:match('DELETE FROM "public"%.\"users\" WHERE "id" = \'2\';'))
	end)

	it("uses adapter-specific quoting and literal formatting", function()
		local changes = {
			inserts = {
				{ row = { id = "1", name = "alice" } },
			},
			updates = {},
			deletes = {},
		}
		local table_meta = {
			table = "users",
			columns = { "id", "name" },
			pk_columns = { "id" },
		}
		local adapter = {
			quote_identifier = function(identifier)
				return "`" .. identifier .. "`"
			end,
			format_literal = function(value)
				return "x'" .. tostring(value) .. "'"
			end,
		}

		local statements = mutation_sql.generate(changes, table_meta, adapter)
		assert.are.equal("INSERT INTO `users` (`id`, `name`) VALUES (x'1', x'alice');", statements[1])
	end)

	it("does not generate update statement when only PK columns are listed as changed", function()
		local changes = {
			inserts = {},
			updates = {
				{
					pk = { id = "1" },
					changed_columns = {
						id = { old = "1", new = "1" },
					},
				},
			},
			deletes = {},
		}
		local table_meta = {
			table = "users",
			columns = { "id", "name" },
			pk_columns = { "id" },
		}
		local statements = mutation_sql.generate(changes, table_meta, nil)
		assert.are.equal(0, #statements)
	end)
end)
