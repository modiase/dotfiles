---@diagnostic disable-next-line: undefined-global
local vim = vim
return {
	{
		"sindrets/diffview.nvim",
		dependencies = { "nvim-lua/plenary.nvim" },
		cmd = { "DiffviewOpen", "DiffviewFileHistory" },
		config = function()
			require("diffview").setup({
				enhanced_diff_hl = true, -- See ':h diffview-config-enhanced_diff_hl'
				keymaps = {
					view = {
						-- Keybinds in diff view
						["q"] = "<cmd>DiffviewClose<CR>",
						["gco"] = "<cmd>DiffviewChooseOurs<CR>", -- Choose our changes
						["gct"] = "<cmd>DiffviewChooseTheirs<CR>", -- Choose their changes
					},
				},
			})
		end,
		keys = {
			{ "<leader>gd", "<cmd>DiffviewOpen main<CR>", desc = "Open Diffview" },
			{ "<leader>gh", "<cmd>DiffviewFileHistory<CR>", desc = "Open File History" },
			{ "<leader>gc", "<cmd>DiffviewClose<CR>", desc = "Close Diffview" },
		},
	},
}
