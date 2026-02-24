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
				path_display = { "filename_first" },
				dynamic_preview_title = true,
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

		local fidget_handle = nil
		local last_spinner_time = 0

		local function stop_spinner()
			if fidget_handle then
				fidget_handle:finish()
				fidget_handle = nil
			end
		end

		local function call_with_spinner(picker_fn, opts)
			opts = opts or {}

			local ok, fidget = pcall(require, "fidget.progress.handle")
			if not ok then
				picker_fn(opts)
				return
			end

			local function start_spinner()
				if fidget_handle then
					return
				end

				local now = vim.uv.now()
				if now - last_spinner_time < 1000 then
					return
				end
				last_spinner_time = now

				fidget_handle = fidget.create({
					message = "Searching...",
					lsp_client = { name = "telescope" },
				})
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

			local original_attach = opts.attach_mappings
			opts.attach_mappings = function(prompt_bufnr, map)
				local picker = require("telescope.actions.state").get_current_picker(prompt_bufnr)

				vim.api.nvim_create_autocmd("BufWinLeave", {
					buffer = prompt_bufnr,
					once = true,
					callback = stop_spinner,
				})

				local original_completor = picker.get_result_completor
				picker.get_result_completor = function(self, ...)
					local completor = original_completor(self, ...)
					return function()
						stop_spinner()
						completor()
					end
				end

				if original_attach then
					return original_attach(prompt_bufnr, map)
				end
				return true
			end

			picker_fn(opts)
		end

		vim.keymap.set("n", "<leader>fg", function()
			if is_citc() then
				call_with_spinner(require("telescope").extensions.codesearch.find_query)
			else
				call_with_spinner(require("telescope").extensions.live_grep_args.live_grep_args)
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
				call_with_spinner(function(opts)
					require("telescope.builtin").find_files(vim.tbl_extend("force", { hidden = true }, opts or {}))
				end)
			end
		end, { desc = "Find files" })

		vim.api.nvim_set_keymap("n", "<leader>fm", "<cmd>Telescope marks<CR>", { noremap = true })
		vim.api.nvim_set_keymap("n", "<leader>fk", "<cmd>Telescope keymaps<CR>", { noremap = true })
		vim.api.nvim_set_keymap("n", "<leader>tc", "<cmd>Telescope colorscheme<CR>", { noremap = true })

		pcall(require("telescope").load_extension, "noice")
		vim.api.nvim_set_keymap("n", "<leader>fn", "<cmd>Telescope noice<CR>", { noremap = true })
	end,
}
