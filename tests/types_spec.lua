local ConnectionChangedData = require("db-cli-adapter.types")

describe("ConnectionChangedData", function()
	describe("new", function()
		it("creates an instance with provided values", function()
			local data = ConnectionChangedData:new({
				name = "test",
				adapter = "postgres",
				host = "localhost",
				port = 5432,
				user = "admin",
				password = "secret",
				database = "mydb",
			})
			assert.are.equal("test", data.name)
			assert.are.equal("postgres", data.adapter)
			assert.are.equal("localhost", data.host)
			assert.are.equal(5432, data.port)
			assert.are.equal("admin", data.user)
			assert.are.equal("secret", data.password)
			assert.are.equal("mydb", data.database)
		end)

		it("creates an empty instance when no args provided", function()
			local data = ConnectionChangedData:new()
			assert.is_table(data)
		end)
	end)

	describe("as_sqlls_connection", function()
		it("returns self", function()
			local data = ConnectionChangedData:new({
				name = "test",
				adapter = "postgres",
				host = "localhost",
			})
			assert.are.equal(data, data:as_sqlls_connection())
		end)
	end)

	describe("as_sqls_connection", function()
		it("maps postgres adapter to postgresql driver", function()
			local data = ConnectionChangedData:new({
				name = "test",
				adapter = "postgres",
				host = "localhost",
				port = 5432,
				user = "admin",
				password = "secret",
				database = "mydb",
			})
			local sqls = data:as_sqls_connection()
			assert.are.equal("postgresql", sqls.driver)
			assert.are.equal("localhost", sqls.host)
			assert.are.equal(5432, sqls.port)
			assert.are.equal("admin", sqls.user)
			assert.are.equal("secret", sqls.passwd)
			assert.are.equal("mydb", sqls.dbName)
			assert.is_nil(sqls.dataSourceName)
		end)

		it("keeps unknown adapter names as-is", function()
			local data = ConnectionChangedData:new({
				name = "test",
				adapter = "mysql",
			})
			local sqls = data:as_sqls_connection()
			assert.are.equal("mysql", sqls.driver)
		end)

		it("uses default values for postgres when fields are missing", function()
			local data = ConnectionChangedData:new({
				name = "test",
				adapter = "postgres",
			})
			local sqls = data:as_sqls_connection()
			assert.are.equal("localhost", sqls.host)
			assert.are.equal(5432, sqls.port)
			assert.are.equal("user", sqls.user)
			assert.are.equal("password", sqls.passwd)
			assert.are.equal("database", sqls.dbName)
			assert.are.equal("tcp", sqls.proto)
		end)

		it("uses default values for mysql when fields are missing", function()
			local data = ConnectionChangedData:new({
				name = "test",
				adapter = "mysql",
			})
			local sqls = data:as_sqls_connection()
			assert.are.equal("localhost", sqls.host)
			assert.are.equal(3306, sqls.port)
			assert.are.equal("tcp", sqls.proto)
		end)

		it("generates dataSourceName for file-based connections", function()
			local data = ConnectionChangedData:new({
				name = "test",
				adapter = "sqlite3",
				filename = "/tmp/test.db",
			})
			local sqls = data:as_sqls_connection()
			assert.are.equal("file:/tmp/test.db", sqls.dataSourceName)
		end)
	end)
end)
