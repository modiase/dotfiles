return {
	"nvim-telescope/telescope.nvim",
	dependencies = {
		"nvim-telescope/telescope-live-grep-args.nvim",
		"nvim-telescope/telescope-project.nvim",
	},
	event = "VeryLazy",
	config = function()
		require("telescope").setup({
			defaults = {
				mappings = {
					n = {
						["<c-d>"] = require("telescope.actions").delete_buffer,
					},
					i = {
						["<C-h>"] = "which_key",
						["<c-d>"] = require("telescope.actions").delete_buffer,
					},
				},
			},
		})
		vim.api.nvim_set_keymap(
			"n",
			"<leader>fg",
			":lua require('telescope').extensions.live_grep_args.live_grep_args()<CR>",
			{ noremap = true }
		)
		vim.api.nvim_set_keymap("n", "<leader>fb", "<cmd>Telescope buffers<cr>", { noremap = true })
		vim.api.nvim_set_keymap("n", "<leader>ft", "<cmd>Telescope help_tags<cr>", { noremap = true })
		vim.api.nvim_set_keymap(
			"n",
			"<leader>fw",
			":lua require('telescope-live-grep-args.shortcuts').grep_word_under_cursor({ postfix = \"\"})<CR>",
			{ noremap = true }
		)
		vim.keymap.set(
			"n",
			"<leader>ff",
			"<cmd>lua require('telescope.builtin').find_files({ hidden = true })<CR>",
			{ desc = "Find files" }
		)
		vim.api.nvim_set_keymap("n", "<leader>fm", "<cmd>Telescope marks<CR>", { noremap = true })
		vim.api.nvim_set_keymap("n", "<leader>tc", "<cmd>Telescope colorscheme<CR>", { noremap = true })
	end,
}
