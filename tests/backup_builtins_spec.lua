describe("backup/restore command builders", function()
	describe("psql", function()
		local adapter = require("db-cli-adapter.builtins.psql")

		it("marks backup/restore support and dump command", function()
			assert.is_true(adapter.supports_backup_restore)
			assert.are.equal("pg_dump", adapter.dump_command)
		end)

		it("builds backup args/env from connection params", function()
			local args, env = adapter:get_backup_args({
				username = "admin",
				password = "secret",
				host = "db.example.com",
				port = 5433,
				dbname = "testdb",
			})
			assert.is_true(vim.tbl_contains(args, "--username=admin"))
			assert.is_true(vim.tbl_contains(args, "--host=db.example.com"))
			assert.is_true(vim.tbl_contains(args, "--port=5433"))
			assert.is_true(vim.tbl_contains(args, "--dbname=testdb"))
			assert.are.equal("secret", env.PGPASSWORD)
			assert.is_false(vim.tbl_contains(args, "--csv"))
		end)

		it("builds restore args identical in shape to backup args", function()
			local params = { username = "admin", host = "localhost", dbname = "testdb" }
			local backup_args = adapter:get_backup_args(params)
			local restore_args = adapter:get_restore_args(params)
			assert.are.same(backup_args, restore_args)
		end)
	end)

	describe("mysql", function()
		local adapter = require("db-cli-adapter.builtins.mysql")

		it("marks backup/restore support and dump command", function()
			assert.is_true(adapter.supports_backup_restore)
			assert.are.equal("mysqldump", adapter.dump_command)
		end)

		it("builds backup args without query-only flags", function()
			local args = adapter:get_backup_args({ username = "root", host = "localhost", dbname = "app" })
			assert.is_true(vim.tbl_contains(args, "--user=root"))
			assert.is_true(vim.tbl_contains(args, "--host=localhost"))
			assert.is_true(vim.tbl_contains(args, "--database=app"))
			assert.is_false(vim.tbl_contains(args, "--table"))
		end)
	end)

	describe("mariadb", function()
		local adapter = require("db-cli-adapter.builtins.mariadb")

		it("marks backup/restore support and dump command", function()
			assert.is_true(adapter.supports_backup_restore)
			assert.are.equal("mariadb-dump", adapter.dump_command)
		end)

		it("builds restore args from connection params", function()
			local args = adapter:get_restore_args({ username = "root", dbname = "app" })
			assert.is_true(vim.tbl_contains(args, "--user=root"))
			assert.is_true(vim.tbl_contains(args, "--database=app"))
		end)
	end)

	describe("sqlite", function()
		local adapter = require("db-cli-adapter.builtins.sqlite")

		it("marks backup/restore support with no separate dump command", function()
			assert.is_true(adapter.supports_backup_restore)
			assert.is_nil(adapter.dump_command)
		end)

		it("builds backup args using .dump", function()
			local args = adapter:get_backup_args({ filename = "test.db" })
			assert.are.same({ "test.db", ".dump" }, args)
		end)

		it("builds restore args reading from stdin", function()
			local args = adapter:get_restore_args({ filename = "test.db" })
			assert.are.same({ "test.db" }, args)
		end)
	end)

	describe("usql", function()
		local adapter = require("db-cli-adapter.builtins.usql")

		it("does not support backup/restore in v1", function()
			assert.is_false(adapter.supports_backup_restore)
		end)
	end)
end)
