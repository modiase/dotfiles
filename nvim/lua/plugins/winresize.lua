---@diagnostic disable-next-line: undefined-global
local vim = vim
return {
	"simeji/winresizer",
	event = "VeryLazy",
	config = function()
		vim.keymap.set("n", "<C-n>", ":WinResizerStartResize<CR>")
	end,
}
