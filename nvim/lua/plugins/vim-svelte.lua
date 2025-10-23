---@diagnostic disable-next-line: undefined-global
local vim = vim
return {
	"leafOfTree/vim-svelte-plugin",
	ft = "svelte",
	config = function()
		vim.g.vim_svelte_plugin_use_typescript = 1
	end,
}
