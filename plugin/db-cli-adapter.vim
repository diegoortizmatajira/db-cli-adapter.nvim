" Title:        db-cli-adapter.nvim
" Description:  A Neovim plugin to interact with a database CLI.
" Last Change:  2025-10-01
" Maintainer:   http://github.com/diegoortizmatajira

" Prevents the plugin from being loaded multiple times. If the loaded
" variable exists, do nothing more. Otherwise, assign the loaded
" variable and continue running this instance of the plugin.
if exists("g:loaded_db_cli_adapter")
    finish
endif
let g:loaded_db_cli_adapter = 1

" Exposes the plugin's functions for use as commands in Neovim.
command! -range -nargs=0 DbCliRunAtCursor lua require("db-cli-adapter").run_at_cursor()
command! -nargs=0 DbCliRunBuffer lua require("db-cli-adapter").run_buffer()
command! -nargs=0 DbCliSelectConnection lua require("db-cli-adapter").select_connection()
command! -nargs=1 DbCliEditConnection lua require("db-cli-adapter").edit_connections_source(<q-args>)
command! -nargs=0 DbCliSidebarToggle lua require("db-cli-adapter.sidebar").toggle()
