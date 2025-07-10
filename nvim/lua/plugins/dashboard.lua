return {
	"glepnir/dashboard-nvim",
	config = function()
		local db = require("dashboard")

		db.setup({
			theme = "hyper", --  theme is doom and hyper default is hyper
		})

		vim.api.nvim_set_keymap(
			"n",
			"<Leader>ss",
			"<cmd>SessionManager save_current_session<CR>",
			{ noremap = true, silent = true }
		)
		vim.api.nvim_set_keymap(
			"n",
			"<Leader>sp",
			"<cmd>SessionManager load_current_dir_session<CR>",
			{ noremap = true, silent = true }
		)
		vim.api.nvim_set_keymap(
			"n",
			"<Leader>sl",
			"<cmd>SessionManager load_session<CR>",
			{ noremap = true, silent = true }
		)
		vim.api.nvim_set_keymap(
			"n",
			"<Leader>sd",
			"<cmd>SessionManager delete_session<CR>",
			{ noremap = true, silent = true }
		)
		vim.api.nvim_set_keymap("n", "<Leader>fh", "<cmd>Telescope help_tags<CR>", { noremap = true, silent = true })
		vim.api.nvim_set_keymap("n", "<Leader>fh", "<cmd>Telescope help_tags<CR>", { noremap = true, silent = true })
		vim.api.nvim_set_keymap("n", "<Leader>ff", "<cmd>Telescope find_files<CR>", { noremap = true, silent = true })
		vim.api.nvim_set_keymap("n", "<Leader>fm", "<cmd>Telescope marks<CR>", { noremap = true, silent = true })
		vim.api.nvim_set_keymap("n", "<Leader>tc", "<cmd>Telescope colorscheme<CR>", { noremap = true, silent = true })
		vim.api.nvim_set_keymap("n", "<Leader>cn", "<cmd>DashboardNewFile<CR>", { noremap = true, silent = true })
	end,
}
