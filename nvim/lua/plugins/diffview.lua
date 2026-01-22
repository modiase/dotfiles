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
				watch_index = true,
				keymaps = {
					view = {
						["q"] = "<cmd>DiffviewClose<CR>",
						["gco"] = "<cmd>DiffviewChooseOurs<CR>",
						["gct"] = "<cmd>DiffviewChooseTheirs<CR>",
					},
				},
			})
		end,
		keys = {
			{
				"<leader>gd",
				function()
					if next(require("diffview.lib").views) == nil then
						local is_hg = vim.fn.system("hg root 2>/dev/null"):find("^/") ~= nil
						if is_hg then
							vim.cmd("DiffviewOpen")
						else
							vim.cmd("DiffviewOpen main")
						end
					else
						vim.cmd("DiffviewClose")
					end
				end,
				desc = "Toggle Diffview",
			},
			{ "<leader>gh", "<cmd>DiffviewFileHistory<CR>", desc = "Open File History" },
			{ "<leader>gr", "<cmd>DiffviewRefresh<CR>", desc = "Refresh Diffview" },
		},
	},
}
