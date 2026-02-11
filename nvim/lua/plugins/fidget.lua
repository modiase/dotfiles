return {
	"j-hui/fidget.nvim",
	event = "VeryLazy",
	config = function()
		local function centered_padding()
			local width = 40
			return math.max(1, math.floor((vim.o.columns - width) / 2))
		end

		local function setup_fidget()
			require("fidget").setup({
				progress = {
					display = {
						render_limit = 5,
						progress_icon = { "moon" },
					},
				},
				notification = {
					window = {
						winblend = 100,
						border = "none",
						align = "bottom",
						x_padding = centered_padding(),
						y_padding = 1,
					},
				},
			})
		end

		setup_fidget()

		vim.api.nvim_create_autocmd("VimResized", {
			callback = setup_fidget,
		})
	end,
}
