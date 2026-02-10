local function is_citc()
	return vim.fn.getcwd():match("^/google/src/cloud/") ~= nil
end

return {
	"nvim-telescope/telescope.nvim",
	dependencies = {
		"nvim-telescope/telescope-live-grep-args.nvim",
		"nvim-telescope/telescope-project.nvim",
		{ "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
	},
	event = "VeryLazy",
	config = function()
		require("telescope").setup({
			defaults = {
				file_ignore_patterns = {
					"^%.git/",
					"node_modules/",
					"__pycache__/",
					"%.pyc$",
					"%.venv/",
					"venv/",
					"%.DS_Store",
					"target/",
					"dist/",
					"build/",
					"vendor/",
					"%.cache/",
					"%.next/",
					"%.angular/",
					"%.terraform/",
					"%.pytest_cache/",
					"%.mypy_cache/",
					"coverage/",
					"%.class$",
					"%.gradle/",
					"%.idea/",
					"out/",
					"builddir/",
					"subprojects/",
					"%.o$",
					"%.a$",
					"%.so$",
					"%.cargo/",
				},
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
			extensions = {
				fzf = {
					fuzzy = true,
					override_generic_sorter = true,
					override_file_sorter = true,
					case_mode = "smart_case",
				},
			},
		})
		require("telescope").load_extension("fzf")

		vim.keymap.set("n", "<leader>fg", function()
			if is_citc() then
				require("telescope").extensions.codesearch.find_query()
			else
				require("telescope").extensions.live_grep_args.live_grep_args()
			end
		end, { desc = "Live grep" })

		vim.api.nvim_set_keymap("n", "<leader>fb", "<cmd>Telescope buffers<cr>", { noremap = true })
		vim.api.nvim_set_keymap("n", "<leader>ft", "<cmd>Telescope help_tags<cr>", { noremap = true })
		vim.api.nvim_set_keymap(
			"n",
			"<leader>fw",
			":lua require('telescope-live-grep-args.shortcuts').grep_word_under_cursor({ postfix = \"\"})<CR>",
			{ noremap = true }
		)

		vim.keymap.set("n", "<leader>ff", function()
			if is_citc() then
				require("telescope").extensions.codesearch.find_files()
			else
				require("telescope.builtin").find_files({ hidden = true })
			end
		end, { desc = "Find files" })

		vim.api.nvim_set_keymap("n", "<leader>fm", "<cmd>Telescope marks<CR>", { noremap = true })
		vim.api.nvim_set_keymap("n", "<leader>fk", "<cmd>Telescope keymaps<CR>", { noremap = true })
		vim.api.nvim_set_keymap("n", "<leader>tc", "<cmd>Telescope colorscheme<CR>", { noremap = true })

		pcall(require("telescope").load_extension, "noice")
		vim.api.nvim_set_keymap("n", "<leader>fn", "<cmd>Telescope noice<CR>", { noremap = true })
	end,
}
