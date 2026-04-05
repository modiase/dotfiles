vim.g.mapleader = " "

do
	local _original = vim.rpcnotify
	local _interceptors = {}
	---@class RpcNotify
	---@field notify fun(channel: integer, method: string, ...: any): any
	---@field add_interceptor fun(fn: fun(channel: integer, method: string, ...): boolean?)
	---@operator call(any): any
	vim.rpcnotify = setmetatable({
		notify = _original,
		add_interceptor = function(fn)
			table.insert(_interceptors, fn)
		end,
	}, {
		__call = function(_, channel, method, ...)
			for _, interceptor in ipairs(_interceptors) do
				if interceptor(channel, method, ...) == false then
					return
				end
			end
			return _original(channel, method, ...)
		end,
	})
end

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
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

require("lazy").setup(require("plugins"), {})

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
