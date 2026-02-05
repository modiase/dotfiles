return {
	"folke/persistence.nvim",
	cond = not vim.g.pager_mode,
	event = "BufReadPre",
	opts = {},
	init = function()
		vim.api.nvim_create_autocmd("VimEnter", {
			group = vim.api.nvim_create_augroup("persistence_restore", { clear = true }),
			nested = true,
			callback = function()
				if vim.fn.argc() == 0 then
					require("persistence").load()
				end
			end,
		})
	end,
	keys = {
		{
			"<leader>qs",
			function()
				require("persistence").load()
			end,
			desc = "Restore session",
		},
		{
			"<leader>qS",
			function()
				require("persistence").select()
			end,
			desc = "Select session",
		},
		{
			"<leader>ql",
			function()
				require("persistence").load({ last = true })
			end,
			desc = "Restore last session",
		},
	},
}
