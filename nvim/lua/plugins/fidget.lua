return {
	"j-hui/fidget.nvim",
	event = "VeryLazy",
	opts = function()
		local notification_width = 30
		local x_padding = math.floor((vim.o.columns - notification_width) / 2)
		return {
			progress = {
				display = {
					render_limit = 5,
					progress_icon = { "bouncing_bar" },
				},
			},
			notification = {
				window = {
					winblend = 0,
					border = "rounded",
					zindex = 100,
					align = "bottom",
					x_padding = x_padding,
				},
			},
		}
	end,
}
