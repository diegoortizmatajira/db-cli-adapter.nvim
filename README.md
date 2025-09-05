# db-cli-adapter.nvim

`db-cli-adapter.nvim` is a Neovim plugin designed to provide seamless
integration with various database CLI tools. It enhances developer productivity
by offering an easy-to-use interface for database operations directly within
Neovim.

It follows KISS principle, so instead of requiring a custom-built backend cli tool,
you can use the default tooling for each database provider.

## Features

- Support for multiple databases (e.g., MySQL, PostgreSQL, SQLite, MariaDB).
- Lightweight and easy to configure.
- Compatible with Neovim's Lua ecosystem.

## Prerequisites

- Neovim 0.5 or higher.
- Ensure the appropriate database CLI tools (e.g., `mysql`, `psql`, `sqlite3`)
  are installed and available in your system's PATH.

## Installation

### Using [Packer](https://github.com/wbthomason/packer.nvim)

Add the following to your `init.lua` or `init.vim`:

```lua
use {
    'diegoortizmatajira/db-cli-adapter.nvim',
    config = function()
        require('db-cli-adapter').setup({})
    end
}
```

Run the `:PackerSync` command to install the plugin.

### Using [Lazy.nvim](https://github.com/folke/lazy.nvim)

Add the following to your `lazy` setup:

```lua
{
    'diegoortizmatajira/db-cli-adapter.nvim',
    opts={}
}
```

## Configuration

## Usage

## Contributing

Contributions are welcome! Please feel free to open issues or submit pull
requests.

## License

This plugin is licensed under the MIT License. See the LICENSE file for more
details.

---

Enjoy seamless database operations directly within Neovim!
