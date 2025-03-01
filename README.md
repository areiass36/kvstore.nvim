# kvstore.nvim

A simple key-value store plugin for Neovim, allowing you to easily persist and retrieve data in a JSON file.

## Features

Load and Save: Automatically loads the data from a JSON file on startup and saves changes.
Get, Set, Delete: Simple API to interact with stored data.
Persistence: Automatically persists data to a JSON file at a defined path.
## Installation

Using Lazy.nvim
```
require('lazy').setup({
  'your-username/kvstore.nvim'
})
```
Using packer.nvim
use 'your-username/kvstore.nvim'
Manually
If you prefer to install manually, clone this repository into your ~/.config/nvim/lua/plugins/ directory:

git clone https://github.com/your-username/kvstore.nvim ~/.config/nvim/lua/plugins/kvstore
Usage

Setting Up
Once installed, you need to set up the plugin. Add the following to your init.lua or another configuration file:

local kvstore = require('kvstore')
kvstore.setup()  -- Loads the store and sets up the file path
Available Functions
kvstore.get(key)

Returns the value associated with the key. If the key doesn't exist, it will return nil.

local value = kvstore.get("my_key")
kvstore.set(key, value)

Sets the key to the given value and saves the data to the JSON file.

kvstore.set("my_key", "my_value")
kvstore.has(key)

Checks if a key exists in the store.

if kvstore.has("my_key") then
    print("Key exists!")
end
kvstore.delete(key)

Deletes the specified key from the store and saves the changes.

kvstore.delete("my_key")
kvstore.get_or_set(key, callback)

Returns the value of key if it exists. If it does not, calls the provided callback function and saves the result to the store.

local value = kvstore.get_or_set("my_key", function()
    return "default_value"
end)
File Location
The store data is saved in a JSON file located at:

vim.fn.stdpath('data') .. '/kvstore.json'
This location can be changed by modifying the store_path in the plugin.

Example

local kvstore = require('kvstore')
kvstore.setup()

-- Set a key-value pair
kvstore.set("name", "Alice")

-- Get the value
local name = kvstore.get("name")
print(name)  -- Output: Alice

-- Check if a key exists
if kvstore.has("name") then
    print("The key 'name' exists.")
end

-- Delete a key
kvstore.delete("name")

-- Use get_or_set to provide a default value if the key doesn't exist
local default_value = kvstore.get_or_set("age", function()
    return 25
end)
print(default_value)  -- Output: 25
Contributing

Fork the repository.
Create a new branch for your changes.
Make your changes.
Commit and push your changes.
Create a pull request.
Feel free to open issues for suggestions, questions, or bugs.

License

This plugin is licensed under the MIT License. See the LICENSE file for more information.

This README provides a clear guide on how to install and use your kvstore.nvim plugin, as well as contributing instructions and basic examples. Let me know if you need more modifications!
