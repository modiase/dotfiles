return {
	"NickvanDyke/opencode.nvim",
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
