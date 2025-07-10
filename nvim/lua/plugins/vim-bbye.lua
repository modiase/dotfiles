---@diagnostic disable-next-line: undefined-global
local vim = vim
return {
	"moll/vim-bbye",
	event = "VeryLazy",
	config = function()
		vim.keymap.set("n", "<leader>b", ":Bdelete<CR>", { silent = true, noremap = true })
		vim.keymap.set("n", "<leader>B", ":Bdelete!<CR>", { silent = true, noremap = true })
	end,
}
