local core = require("db-cli-adapter.core")
local config = require("db-cli-adapter.config")
local utils = require("db-cli-adapter.utils")

local M = {}

--- Resolves a connection name to its stored parameters and adapter.
--- @param connection_name string
--- @return DbCliAdapter.base_params|nil connection, DbCliAdapter.AdapterConfig|nil adapter
local function resolve(connection_name)
	local connections = core.get_available_connections(true)
	local connection = connections[connection_name]
	if not connection then
		vim.notify("Connection not found: " .. connection_name, vim.log.levels.ERROR)
		return nil, nil
	end
	local adapter = config.current.adapters[connection.adapter]
	if not adapter then
		vim.notify("Adapter not found: " .. tostring(connection.adapter), vim.log.levels.ERROR)
		return nil, nil
	end
	return connection, adapter
end

--- Runs `on_ready(connection_name)` for the connection to operate on, resolving it from
--- `connection_name`, the buffer-local connection, or an interactive prompt, in that order.
--- @param connection_name string|nil
--- @param on_ready fun(connection_name: string)
local function with_connection_name(connection_name, on_ready)
	if connection_name then
		on_ready(connection_name)
	elseif vim.b.db_cli_adapter_connection then
		on_ready(vim.b.db_cli_adapter_connection)
	else
		core.select_connection(function()
			on_ready(vim.b.db_cli_adapter_connection)
		end)
	end
end

--- Returns the backup/restore providers available for an adapter, based on which
--- backup/restore tools are actually installed on the system.
--- @param adapter DbCliAdapter.AdapterConfig|nil
--- @return table[] providers List of { kind, label, backup_available, restore_available }
function M.list_providers(adapter)
	if not adapter or not adapter.supports_backup_restore then
		return {}
	end
	local dump_tool = adapter.dump_command or adapter.command
	return {
		{
			kind = "local",
			label = "Local",
			backup_available = utils.is_executable(dump_tool),
			restore_available = utils.is_executable(adapter.command),
		},
		{
			kind = "container",
			label = "Container (docker exec)",
			backup_available = utils.is_executable("docker"),
			restore_available = utils.is_executable("docker"),
		},
	}
end

--- Notifies a formatted summary of the available backup/restore providers for a connection.
--- @param connection_name string|nil
function M.list_providers_command(connection_name)
	with_connection_name(connection_name, function(name)
		local _, adapter = resolve(name)
		if not adapter then
			return
		end
		if not adapter.supports_backup_restore then
			vim.notify(string.format("Adapter '%s' does not support backup/restore", adapter.name), vim.log.levels.WARN)
			return
		end
		local lines = { string.format("Backup/restore providers for '%s' (%s):", name, adapter.name) }
		for _, provider in ipairs(M.list_providers(adapter)) do
			table.insert(
				lines,
				string.format(
					"  %s: backup %s, restore %s",
					provider.label,
					provider.backup_available and "available" or "unavailable",
					provider.restore_available and "available" or "unavailable"
				)
			)
		end
		vim.notify(table.concat(lines, "\n"))
	end)
end

--- Sanitizes a connection display name for safe use in a filename.
--- @param name string
--- @return string
local function sanitize_filename(name)
	return (name:gsub("[^%w%-_]", "_"))
end

--- Computes a default, timestamped backup file path for a connection under the
--- configured backup directory, creating the directory if needed.
--- @param connection_name string
--- @return string path
function M.default_backup_path(connection_name)
	local dir = config.current.backup.directory
	vim.fn.mkdir(dir, "p")
	local filename = string.format("%s_%s.sql", sanitize_filename(connection_name), os.date("%Y%m%d_%H%M%S"))
	return dir .. "/" .. filename
end

--- Default container picker: prompts via `vim.ui.input`.
--- @param _ DbCliAdapter.ContainerPickerContext
--- @param callback fun(container: string|nil)
local function default_container_picker(_, callback)
	vim.ui.input({ prompt = "Container name/id: " }, function(container)
		callback(container and container ~= "" and container or nil)
	end)
end

--- Prompts to select from the given providers, and to supply a container name/id when
--- a container-based provider is chosen. Container selection goes through
--- `config.current.backup.container_picker` when set (e.g. to integrate with Telescope
--- or another picker), falling back to `vim.ui.input` otherwise.
--- @param providers table[]
--- @param context DbCliAdapter.ContainerPickerContext
--- @param on_ready fun(provider: table, container: string|nil)
local function with_provider(providers, context, on_ready)
	local function proceed(provider)
		if provider.kind == "container" then
			local picker = (config.current.backup and config.current.backup.container_picker) or default_container_picker
			picker(context, function(container)
				if not container or container == "" then
					vim.notify("Cancelled: no container provided", vim.log.levels.WARN)
					return
				end
				on_ready(provider, container)
			end)
		else
			on_ready(provider, nil)
		end
	end
	if #providers == 1 then
		proceed(providers[1])
		return
	end
	vim.ui.select(providers, {
		prompt = "Select a provider:",
		format_item = function(p)
			return p.label
		end,
	}, function(choice)
		if choice then
			proceed(choice)
		else
			vim.notify("No provider selected", vim.log.levels.WARN)
		end
	end)
end

--- Wraps command args/env to run through `docker exec -i <container> <cmd> ...` when
--- the chosen provider is container-based.
--- @param provider table
--- @param container string|nil
--- @param cmd string
--- @param args string[]
--- @return string cmd, string[] args
local function apply_provider(provider, container, cmd, args)
	if provider.kind == "container" then
		return "docker", vim.list_extend({ "exec", "-i", container, cmd }, args)
	end
	return cmd, args
end

--- Backs up a database connection to a SQL file using an available backup provider.
--- @param opts? { connection?: string }
function M.backup(opts)
	opts = opts or {}
	with_connection_name(opts.connection, function(name)
		local connection, adapter = resolve(name)
		if not adapter then
			return
		end
		if not adapter.supports_backup_restore then
			vim.notify(string.format("Adapter '%s' does not support backup", adapter.name), vim.log.levels.ERROR)
			return
		end
		local providers = vim.tbl_filter(function(p)
			return p.backup_available
		end, M.list_providers(adapter))
		if #providers == 0 then
			vim.notify(
				string.format(
					"No backup provider available for '%s'. Install '%s' locally, or install 'docker' for container backups.",
					adapter.name,
					adapter.dump_command or adapter.command
				),
				vim.log.levels.ERROR
			)
			return
		end
		local context = { connection_name = name, connection = connection, adapter = adapter, direction = "backup" }
		with_provider(providers, context, function(provider, container)
			local args, env, err = adapter:get_backup_args(connection)
			if not args then
				vim.notify(err, vim.log.levels.ERROR)
				return
			end
			local cmd, wrapped_args = apply_provider(provider, container, adapter.dump_command or adapter.command, args)
			vim.ui.input({ prompt = "Backup output path: ", default = M.default_backup_path(name) }, function(path)
				if not path or path == "" then
					vim.notify("Backup cancelled: no path provided", vim.log.levels.WARN)
					return
				end
				vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
				adapter:run_redirected({
					cmd = cmd,
					args = wrapped_args,
					env = env,
					redirect = { mode = ">", path = path },
					callback = function(ok)
						if ok then
							vim.notify("Backup written to " .. path)
						else
							vim.notify("Backup failed, see previous error", vim.log.levels.ERROR)
						end
					end,
				})
			end)
		end)
	end)
end

--- Restores a database connection from a SQL file using an available restore provider.
--- Prompts for explicit confirmation before running, since this may overwrite data.
--- @param opts? { connection?: string }
function M.restore(opts)
	opts = opts or {}
	with_connection_name(opts.connection, function(name)
		local connection, adapter = resolve(name)
		if not adapter then
			return
		end
		if not adapter.supports_backup_restore then
			vim.notify(string.format("Adapter '%s' does not support restore", adapter.name), vim.log.levels.ERROR)
			return
		end
		local providers = vim.tbl_filter(function(p)
			return p.restore_available
		end, M.list_providers(adapter))
		if #providers == 0 then
			vim.notify(
				string.format(
					"No restore provider available for '%s'. Install '%s' locally, or install 'docker' for container restores.",
					adapter.name,
					adapter.command
				),
				vim.log.levels.ERROR
			)
			return
		end
		local context = { connection_name = name, connection = connection, adapter = adapter, direction = "restore" }
		with_provider(providers, context, function(provider, container)
			vim.ui.input({ prompt = "Restore input path: " }, function(path)
				if not path or path == "" then
					vim.notify("Restore cancelled: no path provided", vim.log.levels.WARN)
					return
				end
				if vim.fn.filereadable(path) ~= 1 then
					vim.notify("File not readable: " .. path, vim.log.levels.ERROR)
					return
				end
				vim.ui.select({ "Yes", "No" }, {
					prompt = string.format("Restore into '%s' from %s? This may overwrite existing data.", name, path),
				}, function(choice)
					if choice ~= "Yes" then
						vim.notify("Restore cancelled", vim.log.levels.WARN)
						return
					end
					local args, env, err = adapter:get_restore_args(connection)
					if not args then
						vim.notify(err, vim.log.levels.ERROR)
						return
					end
					local cmd, wrapped_args = apply_provider(provider, container, adapter.command, args)
					adapter:run_redirected({
						cmd = cmd,
						args = wrapped_args,
						env = env,
						redirect = { mode = "<", path = path },
						callback = function(ok)
							if ok then
								vim.notify("Restore completed from " .. path)
							else
								vim.notify("Restore failed, see previous error", vim.log.levels.ERROR)
							end
						end,
					})
				end)
			end)
		end)
	end)
end

return M
