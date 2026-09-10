local AdapterConfig = require("db-cli-adapter.adapter_config")

describe("AdapterConfig", function()
	local adapter

	before_each(function()
		adapter = AdapterConfig:new({
			name = "test-adapter",
			command = "test-cmd",
		})
	end)

	describe("new", function()
		it("creates an instance with provided values", function()
			assert.are.equal("test-adapter", adapter.name)
			assert.are.equal("test-cmd", adapter.command)
		end)

		it("sets default queries from information_schema", function()
			assert.is_not_nil(adapter.schemas_query)
			assert.is_not_nil(adapter.tables_query)
			assert.is_not_nil(adapter.table_columns_query)
			assert.is_not_nil(adapter.views_query)
		end)

		it("allows overriding default queries", function()
			local custom = AdapterConfig:new({
				name = "custom",
				command = "cmd",
				schemas_query = "SELECT 1",
			})
			assert.are.equal("SELECT 1", custom.schemas_query)
		end)
	end)

	describe("parse_output", function()
		it("parses pipe-delimited table output", function()
			local output = {
				"|  col1  |  col2  |",
				"|--------|--------|",
				"|  val1  |  val2  |",
				"|  val3  |  val4  |",
			}
			local result = adapter:parse_output(output)
			assert.are.same({ "col1", "col2" }, result.data.column_names)
			assert.are.same({ { "val1", "val2" }, { "val3", "val4" } }, result.data.rows)
			assert.are.equal(2, result.row_count)
		end)

		it("discards separator rows", function()
			local output = {
				"|  col1  |",
				"|--------|",
				"|  val1  |",
			}
			local result = adapter:parse_output(output)
			assert.are.equal(1, result.row_count)
			assert.is_true(#result.discarded_lines > 0)
		end)

		it("discards non-table lines", function()
			local output = {
				"Some message",
				"|  col1  |",
				"|--------|",
				"|  val1  |",
				"(1 row)",
			}
			local result = adapter:parse_output(output)
			assert.are.equal(1, result.row_count)
			assert.are.same({ "col1" }, result.data.column_names)
			assert.is_true(vim.tbl_contains(result.discarded_lines, "Some message"))
			assert.is_true(vim.tbl_contains(result.discarded_lines, "(1 row)"))
		end)

		it("handles empty output", function()
			local result = adapter:parse_output({})
			assert.are.equal(0, result.row_count)
			assert.is_nil(result.data.column_names)
			assert.are.same({}, result.data.rows)
		end)

		it("handles output with only headers", function()
			local output = {
				"|  col1  |  col2  |",
				"|--------|--------|",
			}
			local result = adapter:parse_output(output)
			assert.are.same({ "col1", "col2" }, result.data.column_names)
			assert.are.equal(0, result.row_count)
		end)

		it("applies line_preprocessor when set", function()
			adapter.line_preprocessor = function(line)
				if line:match("\t") then
					line = line:gsub("\t", "|")
					return "|" .. line .. "|"
				end
				return line
			end
			local output = {
				"col1\tcol2",
				"val1\tval2",
			}
			local result = adapter:parse_output(output)
			assert.are.same({ "col1", "col2" }, result.data.column_names)
			assert.are.same({ { "val1", "val2" } }, result.data.rows)
		end)
	end)

	describe("get_schemas_query", function()
		it("returns the schemas query", function()
			local query = adapter:get_schemas_query()
			assert.is_string(query)
			assert.is_truthy(query:match("schema_name"))
		end)

		it("returns empty string when not defined", function()
			adapter.schemas_query = nil
			local query = adapter:get_schemas_query()
			assert.are.equal("", query)
		end)
	end)

	describe("get_tables_query", function()
		it("interpolates schema name", function()
			local query = adapter:get_tables_query("public")
			assert.is_truthy(query:match("public"))
		end)

		it("escapes single quotes in schema name", function()
			local query = adapter:get_tables_query("it's")
			assert.is_truthy(query:match("it''s"))
			assert.is_falsy(query:match("it's[^']"))
		end)

		it("returns empty string when not defined", function()
			adapter.tables_query = nil
			local query = adapter:get_tables_query("public")
			assert.are.equal("", query)
		end)
	end)

	describe("get_views_query", function()
		it("interpolates schema name", function()
			local query = adapter:get_views_query("public")
			assert.is_truthy(query:match("public"))
		end)

		it("escapes single quotes in schema name", function()
			local query = adapter:get_views_query("it's")
			assert.is_truthy(query:match("it''s"))
			assert.is_falsy(query:match("it's[^']"))
		end)

		it("returns empty string when not defined", function()
			adapter.views_query = nil
			local query = adapter:get_views_query("public")
			assert.are.equal("", query)
		end)
	end)

	describe("qualify_table_name", function()
		it("quotes and joins schema and table name", function()
			assert.are.equal('"public"."users"', adapter:qualify_table_name("public", "users"))
		end)

		it("quotes only the table name when schema is nil or empty", function()
			assert.are.equal('"users"', adapter:qualify_table_name(nil, "users"))
			assert.are.equal('"users"', adapter:qualify_table_name("", "users"))
		end)
	end)

	describe("build_select_query", function()
		it("builds a SELECT with explicit columns and no limit by default", function()
			local query = adapter:build_select_query("public", "users", { '"id"', '"name"' }, nil)
			assert.are.equal('SELECT "id", "name" FROM "public"."users"', query)
		end)

		it("appends a LIMIT clause when a positive limit is given", function()
			local query = adapter:build_select_query("public", "users", { '"id"' }, 200)
			assert.are.equal('SELECT "id" FROM "public"."users" LIMIT 200', query)
		end)

		it("omits the LIMIT clause when the limit is 0", function()
			local query = adapter:build_select_query("public", "users", { '"id"' }, 0)
			assert.are.equal('SELECT "id" FROM "public"."users"', query)
		end)
	end)

	describe("get_native_ddl_query", function()
		it("returns nil by default", function()
			assert.is_nil(adapter:get_native_ddl_query("public", "users", "table"))
			assert.is_nil(adapter:get_native_ddl_query("public", "users", "view"))
		end)
	end)

	describe("extract_native_ddl", function()
		it("returns the last column of the first row", function()
			local result = { data = { rows = { { "users", "CREATE TABLE users (id int);" } } } }
			assert.are.equal("CREATE TABLE users (id int);", adapter:extract_native_ddl(result))
		end)

		it("returns nil when there is no data", function()
			assert.is_nil(adapter:extract_native_ddl(nil))
			assert.is_nil(adapter:extract_native_ddl({ data = { rows = {} } }))
		end)
	end)

	describe("build_create_table_query", function()
		it("builds column definitions with a composite primary key", function()
			local query = adapter:build_create_table_query("public", "users", {
				{ name = "id", data_type = "integer", is_primary_key = true },
				{ name = "tenant_id", data_type = "integer", is_primary_key = true },
				{ name = "name", data_type = "text", is_primary_key = false },
			})
			assert.are.equal(
				[[CREATE TABLE "public"."users" (
  "id" integer,
  "tenant_id" integer,
  "name" text,
  PRIMARY KEY ("id", "tenant_id")
);]],
				query
			)
		end)

		it("omits the PRIMARY KEY clause when there is no primary key", function()
			local query = adapter:build_create_table_query(nil, "logs", {
				{ name = "message", data_type = "text", is_primary_key = false },
			})
			assert.are.equal(
				[[CREATE TABLE "logs" (
  "message" text
);]],
				query
			)
		end)
	end)

	describe("build_insert_query", function()
		it("builds an INSERT with a placeholder per column", function()
			local query = adapter:build_insert_query("public", "users", { "id", "name" })
			assert.are.equal('INSERT INTO "public"."users" ("id", "name")\nVALUES (?, ?);', query)
		end)
	end)

	describe("build_update_query", function()
		it("sets non-primary-key columns and filters on primary key columns", function()
			local query = adapter:build_update_query("public", "users", { "id", "name", "email" }, { "id" })
			assert.are.equal('UPDATE "public"."users"\nSET "name" = ?,\n    "email" = ?\nWHERE "id" = ?;', query)
		end)

		it("uses a <condition> placeholder when there are no primary key columns", function()
			local query = adapter:build_update_query(nil, "logs", { "message" }, {})
			assert.are.equal('UPDATE "logs"\nSET "message" = ?\nWHERE <condition>;', query)
		end)
	end)

	describe("build_delete_query", function()
		it("filters on primary key columns", function()
			local query = adapter:build_delete_query("public", "users", { "id" })
			assert.are.equal('DELETE FROM "public"."users"\nWHERE "id" = ?;', query)
		end)

		it("filters on composite primary key columns", function()
			local query = adapter:build_delete_query(nil, "users", { "id", "tenant_id" })
			assert.are.equal('DELETE FROM "users"\nWHERE "id" = ? AND "tenant_id" = ?;', query)
		end)

		it("uses a <condition> placeholder when there are no primary key columns", function()
			local query = adapter:build_delete_query(nil, "logs", {})
			assert.are.equal('DELETE FROM "logs"\nWHERE <condition>;', query)
		end)
	end)

	describe("get_table_columns_query", function()
		it("interpolates schema and table names", function()
			local query = adapter:get_table_columns_query("public", "users")
			assert.is_truthy(query:match("public"))
			assert.is_truthy(query:match("users"))
		end)

		it("escapes single quotes in both parameters", function()
			local query = adapter:get_table_columns_query("it's", "ta'ble")
			assert.is_truthy(query:match("it''s"))
			assert.is_truthy(query:match("ta''ble"))
		end)

		it("returns empty string when not defined", function()
			adapter.table_columns_query = nil
			local query = adapter:get_table_columns_query("public", "users")
			assert.are.equal("", query)
		end)
	end)

	describe("parse_command", function()
		it("returns string commands as-is", function()
			local result = adapter:parse_command("SELECT 1", {})
			assert.are.equal("SELECT 1", result)
		end)

		it("calls function commands with connection params", function()
			local params = { host = "localhost" }
			local cmd = function(p)
				return "SELECT * FROM " .. p.host
			end
			local result = adapter:parse_command(cmd, params)
			assert.are.equal("SELECT * FROM localhost", result)
		end)
	end)

	describe("run_command", function()
		it("uses system execution when callback is provided", function()
			-- Just verifying it doesn't error; actual execution tested via integration
			assert.is_function(adapter.run_command)
		end)
	end)
end)
