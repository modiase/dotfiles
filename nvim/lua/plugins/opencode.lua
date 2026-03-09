return {
	"NickvanDyke/opencode.nvim",
	cond = not vim.g.pager_mode,
	event = "VeryLazy",
	dependencies = { "folke/snacks.nvim" },
	config = function()
		vim.o.autoread = true
	end,
	keys = {
		{
			"<leader>Oa",
			function()
				require("opencode").ask("@this: ", { submit = true })
			end,
			mode = { "n", "x" },
			desc = "Ask opencode",
		},
		{
			"<leader>Os",
			function()
				require("opencode").select()
			end,
			mode = { "n", "x" },
			desc = "Select opencode prompt",
		},
		{
			"<leader>Ot",
			function()
				require("opencode").toggle()
			end,
			desc = "Toggle opencode terminal",
		},
	},
}
