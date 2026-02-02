return {
	"folke/noice.nvim",
	event = "VeryLazy",
	dependencies = {
		"MunifTanjim/nui.nvim",
		"rcarriga/nvim-notify",
	},
	opts = {
		lsp = {
			-- Disable for coc.nvim (it has its own handling)
			progress = { enabled = false },
			hover = { enabled = false },
			signature = { enabled = false },
			message = { enabled = false },
		},
		presets = {
			bottom_search = true,
			command_palette = true,
			long_message_to_split = true,
		},
		views = {
			cmdline_popup = {
				position = { row = "40%", col = "50%" },
				size = { width = 60, height = "auto" },
			},
		},
	},
}
