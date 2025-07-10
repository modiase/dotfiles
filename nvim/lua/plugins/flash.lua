---@diagnostic disable-next-line: undefined-global
local vim = vim
return {
	"folke/flash.nvim",
	event = "VeryLazy",
	config = function()
		require("flash").setup({
			modes = {
				char = {
					jump_labels = true,
				},
			},
		})
		vim.keymap.set("n", "s", function()
			require("flash").jump()
		end, { noremap = true })
		vim.keymap.set("n", "S", function()
			require("flash").treesitter()
		end, { noremap = true })
	end,
}
