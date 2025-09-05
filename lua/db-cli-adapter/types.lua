--- @class DbCliAdapter.base_params
--- @field timeout number Timeout in seconds for the connection

--- @class DbCliAdapter.OutputData
--- @field column_names string[] List of column names in the output
--- @field rows string[][] List of rows, where each row is a list of column values

--- @class DbCliAdapter.Output
--- @field data DbCliAdapter.OutputData|nil The structured output data
--- @field row_count number The number of rows returned/affected
--- @field message string A message describing the result of the operation

--- @class  DbCliAdapter.Config defines the configuration structure for DbCliAdapter
--- @field adapters table<string, DbCliAdapter.AdapterConfig> List of adapter configurations
--- @field sources table<string, string|fun():string> A mapping of source names to their configurations
--- @field source_icons table<string, string> Icons for different connection sources
--- @field adapter_icons table<string, string> Icons for different connection sources
