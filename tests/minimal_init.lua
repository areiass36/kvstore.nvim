local root = vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(debug.getinfo(1, "S").source:sub(2))))

vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:prepend(vim.fs.joinpath(root, ".tests", "plenary.nvim"))
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"

vim.cmd("runtime plugin/plenary.vim")
