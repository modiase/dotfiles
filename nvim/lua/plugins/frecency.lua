return {
	"nvim-telescope/telescope-frecency.nvim",
	dependencies = { "nvim-telescope/telescope.nvim" },
	event = "VeryLazy",
	config = function()
		require("telescope").setup({
			extensions = {
				frecency = {
					default_workspace = "CWD",
					show_filter_column = false,
					matcher = "fuzzy",
				},
			},
		})
		require("telescope").load_extension("frecency")
	end,
}
