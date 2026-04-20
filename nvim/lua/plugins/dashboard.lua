return {
	"folke/snacks.nvim",
	opts = {
		dashboard = {
			enabled = true,
			preset = {
				header = "│ ╲ ││\n││╲╲││\n││ ╲ │",
			},
			sections = {
				{ section = "header" },
				{ section = "keys", gap = 1 },
				{ section = "startup" },
			},
		},
	},
	init = function()
		vim.api.nvim_set_hl(0, "SnacksDashboardHeader", { fg = require("colors").foreground })
		vim.api.nvim_create_autocmd("BufDelete", {
			group = vim.api.nvim_create_augroup("dashboard_on_empty", { clear = true }),
			callback = function()
				vim.schedule(function()
					local bufs = vim.tbl_filter(function(b)
						return vim.api.nvim_buf_is_valid(b)
							and vim.bo[b].buflisted
							and vim.bo[b].filetype ~= "snacks_dashboard"
					end, vim.api.nvim_list_bufs())

					if
						#bufs == 0
						or (#bufs == 1 and vim.api.nvim_buf_get_name(bufs[1]) == "" and not vim.bo[bufs[1]].modified)
					then
						require("snacks").dashboard.open()
					end
				end)
			end,
		})
	end,
}
