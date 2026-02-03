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

		local function call_with_spinner(picker_fn, opts)
			opts = opts or {}

			local ok, fidget = pcall(require, "fidget.progress.handle")
			if not ok then
				picker_fn(opts)
				return
			end

			local fidget_handle = nil
			local poll_timer = nil

			local function stop_spinner()
				if poll_timer then
					poll_timer:stop()
					poll_timer = nil
				end
				if fidget_handle then
					fidget_handle:finish()
					fidget_handle = nil
				end
			end

			local function poll_for_results()
				local bufnr = vim.api.nvim_get_current_buf()
				if vim.bo[bufnr].filetype ~= "TelescopePrompt" then
					stop_spinner()
					return
				end

				local picker = require("telescope.actions.state").get_current_picker(bufnr)
				if picker and picker.manager and picker.manager:num_results() > 0 then
					stop_spinner()
				end
			end

			local function start_spinner()
				if fidget_handle then
					return
				end

				fidget_handle = fidget.create({
					title = "Codesearch",
					message = "Searching...",
					lsp_client = { name = "codesearch" },
				})

				poll_timer = vim.uv.new_timer()
				poll_timer:start(200, 100, vim.schedule_wrap(poll_for_results))
			end

			local original_input_filter = opts.on_input_filter_cb
			opts.on_input_filter_cb = function(prompt)
				if #prompt > 0 then
					start_spinner()
				end

				if original_input_filter then
					return original_input_filter(prompt)
				end
				return { prompt = prompt }
			end

			picker_fn(opts)
		end

		vim.keymap.set("n", "<leader>fg", function()
			if is_citc() then
				call_with_spinner(require("telescope").extensions.codesearch.find_query)
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
				call_with_spinner(require("telescope").extensions.codesearch.find_files)
			else
				require("telescope.builtin").find_files({ hidden = true })
			end
		end, { desc = "Find files" })

		vim.api.nvim_set_keymap("n", "<leader>fm", "<cmd>Telescope marks<CR>", { noremap = true })
		vim.api.nvim_set_keymap("n", "<leader>tc", "<cmd>Telescope colorscheme<CR>", { noremap = true })

		pcall(require("telescope").load_extension, "noice")
		vim.api.nvim_set_keymap("n", "<leader>fn", "<cmd>Telescope noice<CR>", { noremap = true })
	end,
}
