return {
	"lewis6991/gitsigns.nvim",
	event = "VeryLazy",
	config = function()
		local c = require("colors")

		require("gitsigns").setup({
			signs = {
				add = { text = "│" },
				change = { text = "│" },
				delete = { text = "▁" },
				topdelete = { text = "▔" },
				changedelete = { text = "│" },
				untracked = { text = "┆" },
			},
			on_attach = function(bufnr)
				local gs = package.loaded.gitsigns

				local function map(mode, l, r, opts)
					opts = opts or {}
					opts.buffer = bufnr
					vim.keymap.set(mode, l, r, opts)
				end

				map("n", "]c", function()
					if vim.wo.diff then
						vim.cmd.normal({ "]c", bang = true })
					else
						gs.nav_hunk("next")
					end
				end, { desc = "Next hunk" })

				map("n", "[c", function()
					if vim.wo.diff then
						vim.cmd.normal({ "[c", bang = true })
					else
						gs.nav_hunk("prev")
					end
				end, { desc = "Previous hunk" })

				map("n", "<leader>hs", gs.stage_hunk, { desc = "Stage hunk" })
				map("n", "<leader>hr", gs.reset_hunk, { desc = "Reset hunk" })
				map("v", "<leader>hs", function()
					gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
				end, { desc = "Stage hunk" })
				map("v", "<leader>hr", function()
					gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
				end, { desc = "Reset hunk" })
				map("n", "<leader>hu", gs.undo_stage_hunk, { desc = "Undo stage hunk" })
				map("n", "<leader>hp", gs.preview_hunk, { desc = "Preview hunk" })
				map("n", "<leader>hb", function()
					gs.blame_line({ full = true })
				end, { desc = "Blame line" })
			end,
		})

		vim.api.nvim_set_hl(0, "GitSignsAdd", { fg = c.base09 })
		vim.api.nvim_set_hl(0, "GitSignsChange", { fg = c.base0D })
		vim.api.nvim_set_hl(0, "GitSignsDelete", { fg = c.base08 })
		vim.api.nvim_set_hl(0, "GitSignsTopdelete", { fg = c.base08 })
		vim.api.nvim_set_hl(0, "GitSignsChangedelete", { fg = c.base0D })
		vim.api.nvim_set_hl(0, "GitSignsUntracked", { fg = c.base03 })
	end,
}
