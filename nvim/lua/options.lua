---@diagnostic disable-next-line: undefined-global
local vim = vim
local colors = require("colors")

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
vim.opt.fillchars = { eob = " " }

vim.cmd("syntax on")

vim.api.nvim_set_hl(0, "Normal", { bg = colors.background })
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

vim.api.nvim_set_hl(0, "CocInlayHint", { fg = colors.base0C, bg = "NONE" })
vim.api.nvim_set_hl(0, "CocInlayHintParameter", { fg = colors.base0C, bg = "NONE" })
vim.api.nvim_set_hl(0, "CocInlayHintType", { fg = colors.base0C, bg = "NONE" })

-- Set filetype for OpenTofu files
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
	pattern = "*.tofu",
	command = "set filetype=terraform",
})

vim.api.nvim_create_autocmd({ "TermOpen", "BufEnter" }, {
	pattern = "term://*",
	callback = function()
		if vim.bo.buftype == "terminal" then
			vim.cmd("startinsert")
		end
	end,
})

if vim.env.TMUX and vim.g.pager_mode ~= 1 then
	local env_var = "NVIM_" .. vim.env.TMUX_PANE
	vim.fn.system({ "tmux", "set-environment", env_var, vim.v.servername })
	vim.api.nvim_create_autocmd("VimLeave", {
		callback = function()
			vim.fn.system({ "tmux", "set-environment", "-u", env_var })
		end,
	})
end
