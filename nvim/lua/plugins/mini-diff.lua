return {
	"echasnovski/mini.diff",
	event = "VeryLazy",
	config = function()
		require("mini.diff").setup({
			view = {
				style = "sign",
				signs = { add = " ", change = " ", delete = " " },
			},
			mappings = {
				apply = "",
				reset = "",
				textobject = "gh",
			},
		})

		vim.keymap.set("n", "<leader>do", function()
			MiniDiff.toggle_overlay(0)
		end, { desc = "Diff overlay" })
	end,
}
