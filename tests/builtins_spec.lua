describe("builtin adapters", function()
	describe("psql", function()
		local adapter = require("db-cli-adapter.builtins.psql")

		it("has correct name and command", function()
			assert.are.equal("PostgreSQL (psql)", adapter.name)
			assert.are.equal("psql", adapter.command)
		end)

		it("generates connection URL data", function()
			local data = adapter:get_url_connection({
				host = "db.example.com",
				port = 5433,
				username = "admin",
				password = "secret",
				dbname = "testdb",
			})
			assert.are.equal("postgres", data.adapter)
			assert.are.equal("db.example.com", data.host)
			assert.are.equal(5433, data.port)
			assert.are.equal("admin", data.user)
			assert.are.equal("secret", data.password)
			assert.are.equal("testdb", data.database)
		end)

		it("uses defaults for missing connection params", function()
			local data = adapter:get_url_connection({})
			assert.are.equal("localhost", data.host)
			assert.are.equal(5432, data.port)
		end)
	end)

	describe("mysql", function()
		local adapter = require("db-cli-adapter.builtins.mysql")

		it("has correct name and command", function()
			assert.are.equal("Mysql (mysql)", adapter.name)
			assert.are.equal("mysql", adapter.command)
		end)

		it("generates connection URL data", function()
			local data = adapter:get_url_connection({
				host = "db.example.com",
				port = 3307,
				username = "root",
				password = "pass",
				dbname = "mydb",
			})
			assert.are.equal("mysql", data.adapter)
			assert.are.equal("db.example.com", data.host)
			assert.are.equal(3307, data.port)
		end)

		it("has a line_preprocessor that converts tabs to pipes", function()
			assert.is_function(adapter.line_preprocessor)
			local result = adapter.line_preprocessor("col1\tcol2")
			assert.are.equal("|col1|col2|", result)
		end)

		it("line_preprocessor passes non-tab lines through", function()
			local result = adapter.line_preprocessor("no tabs here")
			assert.are.equal("no tabs here", result)
		end)
	end)

	describe("mariadb", function()
		local adapter = require("db-cli-adapter.builtins.mariadb")

		it("has correct name and command", function()
			assert.are.equal("MariaDb (mariadb)", adapter.name)
			assert.are.equal("mariadb", adapter.command)
		end)

		it("has a line_preprocessor", function()
			assert.is_function(adapter.line_preprocessor)
		end)
	end)

	describe("sqlite", function()
		local adapter = require("db-cli-adapter.builtins.sqlite")

		it("has correct name and command", function()
			assert.are.equal("Sqlite (sqlite3)", adapter.name)
			assert.are.equal("sqlite3", adapter.command)
		end)

		it("has a hardcoded public schema query", function()
			local query = adapter:get_schemas_query()
			assert.is_truthy(query:match("public"))
		end)

		it("queries sqlite_master for tables", function()
			local query = adapter:get_tables_query("public")
			assert.is_truthy(query:match("sqlite_master"))
		end)

		it("uses pragma_table_info for columns", function()
			local query = adapter:get_table_columns_query("public", "users")
			assert.is_truthy(query:match("pragma_table_info"))
			assert.is_truthy(query:match("users"))
		end)

		it("generates connection URL data with filename", function()
			local data = adapter:get_url_connection({
				filename = "/tmp/test.db",
			})
			assert.are.equal("sqlite3", data.adapter)
			assert.are.equal("/tmp/test.db", data.filename)
		end)
	end)

	describe("usql", function()
		local adapter = require("db-cli-adapter.builtins.usql")

		it("has correct name and command", function()
			assert.are.equal("Universal Sql (usql)", adapter.name)
			assert.are.equal("usql", adapter.command)
		end)

		it("returns function queries for lazy evaluation", function()
			assert.is_function(adapter:get_schemas_query())
			assert.is_function(adapter:get_tables_query("public"))
			assert.is_function(adapter:get_table_columns_query("public", "users"))
		end)

		it("resolves postgres schema query from connection URL", function()
			local query_fn = adapter:get_schemas_query()
			local query = query_fn({ url = "postgres://user:pass@localhost/db" })
			assert.is_truthy(query:match("schema_name"))
		end)

		it("resolves sqlite schema query from connection URL", function()
			local query_fn = adapter:get_schemas_query()
			local query = query_fn({ url = "sqlite3:///tmp/test.db" })
			assert.is_truthy(query:match("public"))
		end)

		it("decomposes URL for connection data", function()
			local data = adapter:get_url_connection({
				url = "postgres://admin:secret@db.example.com:5433/testdb",
			})
			assert.are.equal("postgres", data.adapter)
			assert.are.equal("db.example.com", data.host)
			assert.are.equal(5433, data.port)
			assert.are.equal("admin", data.user)
			assert.are.equal("secret", data.password)
			assert.are.equal("testdb", data.database)
		end)

		it("handles URL without port", function()
			local data = adapter:get_url_connection({
				url = "postgres://admin:secret@db.example.com/testdb",
			})
			assert.are.equal("db.example.com", data.host)
			assert.is_nil(data.port)
			assert.are.equal("testdb", data.database)
		end)

		it("maps icon for known database schemes", function()
			local config_mod = require("db-cli-adapter.config")
			config_mod.update(config_mod.default)

			local icon = adapter:get_icon({ url = "postgres://localhost/db", adapter = "usql" })
			assert.is_string(icon)

			config_mod.current = nil
		end)
	end)
end)
