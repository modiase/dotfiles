return {
	"coder/claudecode.nvim",
	cond = not vim.g.pager_mode,
	event = "VeryLazy",
	dependencies = { "folke/snacks.nvim" },
	opts = {
		diff_opts = {
			auto_close_on_accept = true,
			vertical_split = true,
			open_in_current_tab = false,
		},
	},
	config = function(_, opts)
		require("claudecode").setup(opts)
		vim.opt.fillchars:append({ diff = " " })
	end,
	keys = {
		{ "<leader>C", "<cmd>ClaudeCode --continue<cr>", desc = "Continue Claude Code" },
		{ "<leader>Cn", "<cmd>ClaudeCode<cr>", desc = "New Claude Code session" },
		{ "<leader>Cs", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Send selection to Claude" },
		{ "<leader>Ca", "<cmd>ClaudeCodeAdd<cr>", desc = "Add file to Claude context" },
	},
}
