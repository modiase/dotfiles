return {
	"aserowy/tmux.nvim",
	event = "VeryLazy",
	opts = {
		navigation = {
			enable_default_keybindings = false,
		},
	},
	config = function(_, opts)
		local tmux = require("tmux")
		tmux.setup(opts)

		local function nav_wrap(nav_fn)
			return function()
				local mode = vim.api.nvim_get_mode().mode
				if mode == "t" then
					vim.cmd("stopinsert")
				end
				nav_fn()
			end
		end

		local map_opts = { noremap = true, silent = true }
		vim.keymap.set({ "n", "t" }, "<C-h>", nav_wrap(tmux.move_left), map_opts)
		vim.keymap.set({ "n", "t" }, "<C-j>", nav_wrap(tmux.move_bottom), map_opts)
		vim.keymap.set({ "n", "t" }, "<C-k>", nav_wrap(tmux.move_top), map_opts)
		vim.keymap.set({ "n", "t" }, "<C-l>", nav_wrap(tmux.move_right), map_opts)
	end,
}
