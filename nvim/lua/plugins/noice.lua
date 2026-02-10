return {
	"folke/noice.nvim",
	event = "VeryLazy",
	dependencies = {
		"MunifTanjim/nui.nvim",
		"rcarriga/nvim-notify",
	},
	opts = {
		lsp = {
			progress = { enabled = true },
			hover = { enabled = false },
			signature = { enabled = false },
			message = { enabled = false },
		},
		views = {
			popup = { enter = true },
			mini = {
				position = {
					row = -2,
					col = "50%",
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
