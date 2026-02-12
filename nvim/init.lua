vim.g.mapleader = " "

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable",
		lazypath,
	})
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup("plugins", {})

local function _pcall(f_name)
	local ok, _ = pcall(require, f_name)
	if not ok then
		vim.notify("Failed to load " .. f_name, vim.log.levels.ERROR)
	end
end

_pcall("bindings")
_pcall("filetypes")
_pcall("functions")
_pcall("options")
