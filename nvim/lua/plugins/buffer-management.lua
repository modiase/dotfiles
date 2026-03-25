return {
	name = "buffer-management",
	dir = vim.fn.stdpath("config") .. "/my-plugins/buffer-management",
	keys = {
		{
			"<C-w><C-h>",
			function()
				require("buffer-management").swap("wincmd h")
			end,
			desc = "Swap buffer left",
		},
		{
			"<C-w><C-l>",
			function()
				require("buffer-management").swap("wincmd l")
			end,
			desc = "Swap buffer right",
		},
		{
			"<leader>x",
			function()
				require("buffer-management").close()
			end,
			desc = "Close buffer/window",
		},
		{
			"<leader>X",
			function()
				require("buffer-management").close({ force = true })
			end,
			desc = "Force close buffer/window",
		},
		{
			"<leader>A",
			function()
				require("buffer-management").close_unopened()
			end,
			desc = "Close unopened buffers",
		},
		{
			"<C-w><leader>",
			function()
				require("buffer-management").expand()
			end,
			desc = "Expand current buffer to 140 columns",
		},
	},
}
