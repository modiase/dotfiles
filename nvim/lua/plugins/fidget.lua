return {
	"j-hui/fidget.nvim",
	event = "VeryLazy",
	opts = {
		progress = {
			display = {
				render_limit = 5,
				done_ttl = 3,
				done_icon = "✓",
				progress_icon = { pattern = "dots" },
			},
		},
		notification = {
			window = {
				winblend = 0, -- Match nord theme (no transparency)
				border = "rounded",
			},
		},
	},
}
