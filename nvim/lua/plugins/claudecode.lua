return {
	"coder/claudecode.nvim",
	cond = not vim.g.pager_mode,
	event = "VeryLazy",
	dependencies = { "folke/snacks.nvim" },
	opts = {},
	keys = {
		{ "<leader>C", "<cmd>ClaudeCode<cr>", desc = "Toggle Claude Code" },
		{ "<leader>Cs", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Send selection to Claude" },
		{ "<leader>Ca", "<cmd>ClaudeCodeAdd<cr>", desc = "Add file to Claude context" },
	},
}
