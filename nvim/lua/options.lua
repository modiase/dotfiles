---@diagnostic disable-next-line: undefined-global
local vim = vim

vim.opt.autoindent = true
vim.opt.listchars = { extends = ">", precedes = "<" }
vim.opt.mouse = "a"
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.tabstop = 4
vim.opt.updatetime = 300
vim.opt.wrap = false
vim.opt.termguicolors = true

vim.cmd("syntax on")
vim.cmd("colorscheme nord")

vim.api.nvim_set_hl(0, "Normal", { bg = "NONE" })
vim.api.nvim_set_hl(0, "NormalFloat", { bg = "NONE" })

vim.g.clipboard = {
	name = "OSC 52",
	copy = {
		["+"] = require("vim.ui.clipboard.osc52").copy("+"),
		["*"] = require("vim.ui.clipboard.osc52").copy("*"),
	},
	paste = {
		["+"] = require("vim.ui.clipboard.osc52").paste("+"),
		["*"] = require("vim.ui.clipboard.osc52").paste("*"),
	},
}

vim.api.nvim_set_hl(0, "DiffAdd", {
	bg = "#103510",
})

vim.api.nvim_set_hl(0, "DiffChange", {
	bg = "#4a4a00",
	fg = "NONE",
})

vim.api.nvim_set_hl(0, "DiffText", {
	bg = "#6b6b00",
	fg = "NONE",
})

vim.api.nvim_set_hl(0, "DiffDelete", {
	bg = "#401010",
})

vim.api.nvim_set_hl(0, "CocInlayHint", {
	fg = "#88c0d0", -- Nord light blue for inlay hints
	bg = "NONE", -- No background
})

vim.api.nvim_set_hl(0, "CocInlayHintParameter", {
	fg = "#88c0d0", -- Nord light blue for parameter hints
	bg = "NONE", -- No background
})

vim.api.nvim_set_hl(0, "CocInlayHintType", {
	fg = "#88c0d0", -- Nord light blue for type hints
	bg = "NONE", -- No background
})

-- Set filetype for OpenTofu files
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
	pattern = "*.tofu",
	command = "set filetype=terraform",
})

-- Export neovim socket to tmux environment for yazi integration
if vim.env.TMUX then
	vim.fn.system({ "tmux", "set-environment", "NVIM_" .. vim.env.TMUX_PANE, vim.v.servername })
end
