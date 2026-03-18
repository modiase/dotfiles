return {
	"folke/noice.nvim",
	event = "VeryLazy",
	dependencies = {
		"MunifTanjim/nui.nvim",
		"rcarriga/nvim-notify",
	},
	opts = {
		lsp = {
			progress = { enabled = false },
			hover = { enabled = false },
			signature = { enabled = false },
			message = { enabled = false },
		},
		views = {
			popup = {
				enter = true,
				size = { max_width = 120 },
				win_options = {
					wrap = true,
					linebreak = true,
				},
			},
			cmdline_input = {
				size = { width = 120 },
				win_options = {
					wrap = true,
					linebreak = true,
				},
			},
		},
		routes = {
			{ filter = { min_height = 10 }, view = "popup" },
		},
		presets = {
			bottom_search = true,
			command_palette = true,
		},
	},
}
