---@diagnostic disable-next-line: undefined-global
local vim = vim

local fidget_handle = nil

local function start_spinner()
	local ok, fidget = pcall(require, "fidget.progress.handle")
	if not ok then
		return
	end
	fidget_handle = fidget.create({
		message = "Loading diff...",
		lsp_client = { name = "diffview" },
	})
	vim.cmd("redraw")
end

local function stop_spinner()
	if fidget_handle then
		fidget_handle:finish()
		fidget_handle = nil
	end
end

return {
	{
		"sindrets/diffview.nvim",
		dependencies = { "nvim-lua/plenary.nvim" },
		cmd = { "DiffviewOpen", "DiffviewFileHistory" },
		config = function()
			vim.opt.fillchars:append({ diff = " " })
			require("diffview").setup({
				enhanced_diff_hl = true,
				hooks = {
					view_opened = stop_spinner,
					view_closed = stop_spinner,
				},
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
						start_spinner()
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
			{
				"<leader>gh",
				function()
					start_spinner()
					vim.cmd("DiffviewFileHistory")
				end,
				desc = "Open File History",
			},
			{ "<leader>gr", "<cmd>DiffviewRefresh<CR>", desc = "Refresh Diffview" },
		},
	},
}
