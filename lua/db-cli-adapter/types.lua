--- @class DbCliAdapter.base_params
--- @field timeout number Timeout in seconds for the connection

--- @class DbCliAdapter.OutputData
--- @field column_names string[] List of column names in the output
--- @field rows string[][] List of rows, where each row is a list of column values

--- @class DbCliAdapter.Output
--- @field data DbCliAdapter.OutputData|nil The structured output data
--- @field row_count number The number of rows returned/affected
--- @field message string A message describing the result of the operation
--- @field discarded_lines string[] Lines that were discarded during parsing (if any)

--- @class DbCliAdapter.SidebarKeybindingsConfig
--- @field toggle_expand string[] Keybindings to toggle expand/collapse a node
--- @field expand string[] Keybindings to expand a node
--- @field collapse string[] Keybindings to collapse a node
--- @field quit string[] Keybindings to quit the sidebar
--- @field refresh string[] Keybindings to refresh the sidebar
--- @field refresh_all string[] Keybindings to refresh the sidebar

--- @class DbCliAdapter.SidebarConfig
--- @field keybindings DbCliAdapter.SidebarKeybindingsConfig Keybindings for sidebar actions

--- @class DbCliAdapter.TreeIcons
--- @field chevron_open string Icon for an expanded tree node
--- @field chevron_closed string Icon for a collapsed tree node
--- @field connected_database string Icon for a connected database
--- @field folder string Icon for a folder
--- @field database string Icon for a database
--- @field schema string Icon for a schema
--- @field table string Icon for a table
--- @field column string Icon for a column
--- @field key string Icon for a key

--- @class DbCliAdapter.TreeHighlight
--- @field chevron string Chevron icon highlight group
--- @field default_icon string Default icon highlight group
--- @field connected_database string Highlight group for a connected database
--- @field folder string Highlight group for a folder
--- @field database string Highlight group for a database
--- @field schema string Highlight group for a schema
--- @field table string Highlight group for a table
--- @field column string Highlight group for a column
--- @field key string Highlight group for a key

--- @class  DbCliAdapter.IconConfig defines the configuration structure for DbCliAdapter
--- @field source table<string, string> Icons for different connection sources
--- @field adapter table<string, string> Icons for different connection sources
--- @field tree DbCliAdapter.TreeIcons Icons for different tree elements

--- @class  DbCliAdapter.HighlighConfig defines the configuration structure for DbCliAdapter
--- @field tree DbCliAdapter.TreeHighlight Highlight groups for different tree elements

--- @class DbCliAdapter.ExecutionOptions defines parameters for executing a command
--- @field cmd string The command to execute
--- @field args string[] A list of arguments to pass to the command
--- @field env? table<string, string> Optional environment variables to set for the command
--- @field callback? fun(output: DbCliAdapter.Output) Optional callback function to handle the output

--- @class DbCliAdapter.RunOptions defines parameters for running a query
--- @field connection? string The name of the connection to use. If not provided, the buffer-local connection will be used.
--- @field timeout? number Timeout in seconds for the query execution
--- @field callback? fun(output: DbCliAdapter.Output) Optional callback function to handle the
--- @field csv_file? string If provided, the query output will be saved to this CSV file

--- @class DbCliAdapter.CsvOutputConfig defines parameters for CSV output configuration
--- @field after_query_callback? fun(bufnr: number, file_path: string) Optional callback function to handle the

--- @class DbCliAdapter.OutputConfig defines parameters for output configuration
--- @field csv DbCliAdapter.CsvOutputConfig Configuration for CSV output

--- @class  DbCliAdapter.Config defines the configuration structure for DbCliAdapter
--- @field adapters table<string, DbCliAdapter.AdapterConfig> List of adapter configurations
--- @field sources table<string, string|fun():string> A mapping of source names to their configurations
--- @field sidebar DbCliAdapter.SidebarConfig Configuration for the sidebar
--- @field output DbCliAdapter.OutputConfig Configuration for output handling
--- @field icons DbCliAdapter.IconConfig Configuration for icons used in the UI
--- @field highlight DbCliAdapter.HighlighConfig Configuration for highlight groups used in the UI
