return {
	"MeanderingProgrammer/render-markdown.nvim",
	ft = { "markdown" },
	dependencies = {
		"nvim-treesitter/nvim-treesitter",
		"nvim-tree/nvim-web-devicons",
	},
	opts = {
		restart_highlighter = true,
		anti_conceal = { enabled = false },
	},
	config = function(_, opts)
		for i = 1, 6 do
			vim.api.nvim_set_hl(0, "RenderMarkdownH" .. i .. "Bg", { bg = "#2a2a2a" })
		end
		require("render-markdown").setup(opts)
	end,
}
