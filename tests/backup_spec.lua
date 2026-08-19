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

	it("prefers the connection's own backup_directory over the global one", function()
		local path =
			backup.default_backup_path("my postgres", { backup_directory = "/tmp/db-cli-adapter-test-backups/mine" })
		assert.is_truthy(path:match("^/tmp/db%-cli%-adapter%-test%-backups/mine/"))
	end)
end)

describe("container_picker extensibility", function()
	local core = require("db-cli-adapter.core")
	local config = require("db-cli-adapter.config")
	local utils = require("db-cli-adapter.utils")

	local fake_adapter, captured_run_opts, orig_ui_input, orig_ui_select, orig_filereadable, orig_is_executable

	--- Builds a vim.ui.input stub keyed by exact prompt string (or a function(opts) -> answer).
	local function stub_ui_input(responses)
		vim.ui.input = function(opts, cb)
			local answer = responses[opts.prompt]
			if type(answer) == "function" then
				answer = answer(opts)
			end
			cb(answer)
		end
	end

	before_each(function()
		captured_run_opts = nil
		fake_adapter = {
			name = "fake",
			command = "sh",
			supports_backup_restore = true,
			get_backup_args = function(_, _params)
				return { "--fake" }, {}
			end,
			get_restore_args = function(_, _params)
				return { "--fake" }, {}
			end,
			run_redirected = function(_, opts)
				captured_run_opts = opts
				opts.callback(true)
			end,
		}
		core._cached_connections = { test_conn = { adapter = "fake" } }
		config.update({
			adapters = { fake = fake_adapter },
			backup = { directory = "/tmp/db-cli-adapter-test-backups" },
		})
		-- Only "docker" reports as installed, forcing the container provider to be
		-- the sole available one so provider selection is deterministic.
		orig_is_executable = utils.is_executable
		utils.is_executable = function(cmd)
			return cmd == "docker"
		end
		orig_ui_input = vim.ui.input
		orig_ui_select = vim.ui.select
		-- Default to declining the "save preferred directory?" prompt so tests that
		-- don't care about it don't need to stub vim.ui.select themselves.
		vim.ui.select = function(_, _opts, cb)
			cb("No")
		end
		orig_filereadable = vim.fn.filereadable
	end)

	after_each(function()
		core._cached_connections = nil
		config.current = nil
		utils.is_executable = orig_is_executable
		vim.ui.input = orig_ui_input
		vim.ui.select = orig_ui_select
		vim.fn.filereadable = orig_filereadable
	end)

	it("backup falls back to vim.ui.input for the container prompt when unconfigured", function()
		stub_ui_input({
			["Container name/id: "] = "my-container",
			["Backup output path: "] = function(opts)
				return opts.default
			end,
		})

		backup.backup({ connection = "test_conn" })

		assert.is_not_nil(captured_run_opts)
		assert.are.equal("docker", captured_run_opts.cmd)
		assert.are.same({ "exec", "-i", "my-container", "sh", "--fake" }, captured_run_opts.args)
	end)

	it("backup uses the configured container_picker, passing full context", function()
		local captured_context
		config.current.backup.container_picker = function(context, callback)
			captured_context = context
			callback("picked-container")
		end
		stub_ui_input({
			["Backup output path: "] = function(opts)
				return opts.default
			end,
		})

		backup.backup({ connection = "test_conn" })

		assert.is_not_nil(captured_context)
		assert.are.equal("test_conn", captured_context.connection_name)
		assert.are.equal("backup", captured_context.direction)
		assert.are.equal(fake_adapter, captured_context.adapter)
		assert.is_not_nil(captured_run_opts)
		assert.are.same({ "exec", "-i", "picked-container", "sh", "--fake" }, captured_run_opts.args)
	end)

	it("restore passes direction = 'restore' to the configured container_picker", function()
		local captured_context
		config.current.backup.container_picker = function(context, callback)
			captured_context = context
			callback("picked-container")
		end
		vim.fn.filereadable = function()
			return 1
		end
		stub_ui_input({
			["Restore input path: "] = "/tmp/db-cli-adapter-test-backups/in.sql",
		})
		vim.ui.select = function(_, _opts, cb)
			cb("Yes")
		end

		backup.restore({ connection = "test_conn" })

		assert.is_not_nil(captured_context)
		assert.are.equal("restore", captured_context.direction)
		assert.is_not_nil(captured_run_opts)
		assert.are.equal("docker", captured_run_opts.cmd)
		assert.are.same({ "exec", "-i", "picked-container", "sh", "--fake" }, captured_run_opts.args)
		assert.are.equal("<", captured_run_opts.redirect.mode)
	end)
end)

describe("preferred backup directory persistence", function()
	local core = require("db-cli-adapter.core")
	local config = require("db-cli-adapter.config")
	local utils = require("db-cli-adapter.utils")

	local fake_adapter, orig_ui_input, orig_ui_select, orig_is_executable, source_path

	before_each(function()
		-- Force a single local provider so provider selection is deterministic
		-- regardless of whether `docker` happens to be installed on the test host.
		orig_is_executable = utils.is_executable
		utils.is_executable = function(cmd)
			return cmd == "sh"
		end
		source_path = os.tmpname()
		vim.fn.writefile({ vim.fn.json_encode({ test_conn = { adapter = "fake" } }) }, source_path)
		fake_adapter = {
			name = "fake",
			command = "sh",
			supports_backup_restore = true,
			get_icon = function()
				return "X"
			end,
			get_backup_args = function(_, _params)
				return {}, {}
			end,
			run_redirected = function(_, opts)
				opts.callback(true)
			end,
		}
		config.current = vim.tbl_deep_extend("force", config.default, {
			adapters = { fake = fake_adapter },
			sources = { global = source_path },
			backup = { directory = "/tmp/db-cli-adapter-test-backups" },
		})
		config.current.sources.workspace = nil
		core._cached_connections = nil
		core._connection_locations = nil
		orig_ui_input = vim.ui.input
		orig_ui_select = vim.ui.select
	end)

	after_each(function()
		core._cached_connections = nil
		core._connection_locations = nil
		config.current = nil
		vim.ui.input = orig_ui_input
		vim.ui.select = orig_ui_select
		utils.is_executable = orig_is_executable
		os.remove(source_path)
	end)

	local function connection_display_name()
		local names = vim.tbl_keys(core.get_available_connections())
		return names[1]
	end

	it("offers to save the chosen directory and persists it to the connection's source file", function()
		local name = connection_display_name()
		local select_prompt
		vim.ui.input = function(opts, cb)
			cb(opts.default)
		end
		vim.ui.select = function(_, opts, cb)
			select_prompt = opts.prompt
			cb("Yes")
		end

		backup.backup({ connection = name })

		assert.is_truthy(select_prompt and select_prompt:match("^Save "))
		local saved = vim.fn.json_decode(table.concat(vim.fn.readfile(source_path), "\n"))
		assert.are.equal("/tmp/db-cli-adapter-test-backups", saved.test_conn.backup_directory)
	end)

	it("does not offer to save when the path already matches the saved backup_directory", function()
		vim.fn.writefile({
			vim.fn.json_encode({
				test_conn = { adapter = "fake", backup_directory = "/tmp/db-cli-adapter-test-backups" },
			}),
		}, source_path)
		local name = connection_display_name()
		local select_called = false
		vim.ui.input = function(opts, cb)
			cb(opts.default)
		end
		vim.ui.select = function(_, _opts, cb)
			select_called = true
			cb("No")
		end

		backup.backup({ connection = name })

		assert.is_false(select_called)
	end)
end)
