return {
	"mikavilpas/yazi.nvim",
	dependencies = {
		"nvim-lua/plenary.nvim",
	},
	event = "VeryLazy",
	keys = {
		{ "<leader>gf", "<cmd>Yazi<cr>", desc = "Open yazi at current file" },
		{ "<leader>gg", "<cmd>Yazi cwd<cr>", desc = "Open yazi in working directory" },
		{ "<c-up>", "<cmd>Yazi toggle<cr>", desc = "Resume last yazi session" },
	},
	opts = {
		open_for_directories = true,
	},
}
