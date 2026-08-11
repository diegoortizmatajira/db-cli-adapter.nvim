local backup = require("db-cli-adapter.backup")
local utils = require("db-cli-adapter.utils")

describe("backup.list_providers", function()
	it("returns empty for adapters without backup/restore support", function()
		assert.are.same({}, backup.list_providers({ supports_backup_restore = false }))
	end)

	it("returns empty for a nil adapter", function()
		assert.are.same({}, backup.list_providers(nil))
	end)

	it("reports local availability separately for backup and restore tools", function()
		local adapter = {
			supports_backup_restore = true,
			command = "sh", -- present on any Unix test runner
			dump_command = "definitely-not-a-real-binary-xyz",
		}
		local providers = backup.list_providers(adapter)
		local local_provider = providers[1]
		assert.are.equal("local", local_provider.kind)
		assert.is_false(local_provider.backup_available)
		assert.is_true(local_provider.restore_available)
	end)

	it("falls back to `command` for the dump tool when dump_command is unset", function()
		local adapter = { supports_backup_restore = true, command = "sh" }
		local providers = backup.list_providers(adapter)
		assert.is_true(providers[1].backup_available)
		assert.is_true(providers[1].restore_available)
	end)

	it("reports container availability based on the `docker` executable", function()
		local adapter = { supports_backup_restore = true, command = "sh" }
		local providers = backup.list_providers(adapter)
		local container_provider = providers[2]
		assert.are.equal("container", container_provider.kind)
		assert.are.equal(utils.is_executable("docker"), container_provider.backup_available)
		assert.are.equal(utils.is_executable("docker"), container_provider.restore_available)
	end)
end)

describe("backup.default_backup_path", function()
	local config = require("db-cli-adapter.config")

	before_each(function()
		config.update({ backup = { directory = "/tmp/db-cli-adapter-test-backups" } })
	end)

	after_each(function()
		config.current = nil
	end)

	it("builds a sanitized, timestamped .sql path under the configured directory", function()
		local path = backup.default_backup_path("🌐 my postgres!")
		assert.is_truthy(path:match("^/tmp/db%-cli%-adapter%-test%-backups/"))
		assert.is_truthy(path:match("%.sql$"))
		assert.is_falsy(path:match("[^%w%-_./]"))
	end)
end)
