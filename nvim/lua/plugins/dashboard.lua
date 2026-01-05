return {
	"glepnir/dashboard-nvim",
	config = function()
		local db = require("dashboard")

		db.setup({
			theme = "hyper", --  theme is doom and hyper default is hyper
		})

		vim.api.nvim_set_keymap("n", "<Leader>cn", "<cmd>DashboardNewFile<CR>", { noremap = true, silent = true })
	end,
}
