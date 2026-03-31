return {
	"folke/noice.nvim",
	event = "VeryLazy",
	dependencies = {
		"MunifTanjim/nui.nvim",
		"rcarriga/nvim-notify",
	},
	config = function(_, opts)
		package.preload["noice.view.backend.devlogs"] = function()
			return require("views.noice-devlogs")
		end
		require("noice").setup(opts)
	end,
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
			{ view = "devlogs", filter = { event = "notify" }, opts = { stop = false } },
			{ filter = { min_height = 10 }, view = "popup" },
		},
		presets = {
			bottom_search = true,
			command_palette = true,
		},
	},
}
