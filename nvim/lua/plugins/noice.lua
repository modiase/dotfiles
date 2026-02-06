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
			popup = { enter = true },
		},
		routes = {
			{ filter = { min_height = 10 }, view = "popup" },
			-- nvim-mcp's setup_autocmd.lua broadcasts an unhandled "NVIM_MCP" notification
			-- which causes coc.nvim to error. The notification is debug noise with no handler.
			{ filter = { find = "NVIM_MCP" }, opts = { skip = true } },
		},
		presets = {
			bottom_search = true,
			command_palette = true,
		},
	},
}
