---@diagnostic disable-next-line: undefined-global
local vim = vim

local function is_citc()
	return vim.fn.getcwd():match("^/google/src/cloud/") ~= nil
end

local function is_hg()
	return vim.fn.system("hg root 2>/dev/null"):find("^/") ~= nil
end

local function get_git_options()
	local options = {
		{ label = "HEAD (uncommitted)", arg = "HEAD" },
		{ label = "HEAD~1 (previous)", arg = "HEAD~1" },
	}

	local merge_base = vim.fn.system("git merge-base HEAD main 2>/dev/null"):gsub("\n", "")
	if merge_base ~= "" then
		local short_sha = merge_base:sub(1, 7)
		table.insert(options, { label = "Merge base (main) - " .. short_sha, arg = merge_base })
	end

	table.insert(options, { label = "main", arg = "main" })
	table.insert(options, { label = "origin/main", arg = "origin/main" })

	return options
end

local function get_citc_options()
	return {
		{ label = ". (uncommitted)", arg = "." },
		{ label = ".^ (previous)", arg = ".^" },
		{ label = "p4base", arg = "p4base" },
		{ label = "p4head", arg = "p4head" },
	}
end

local function get_hg_options()
	return {
		{ label = ". (uncommitted)", arg = "" },
		{ label = ".^ (previous)", arg = ".^" },
	}
end

local loading_win = nil

local function close_loading()
	if loading_win and vim.api.nvim_win_is_valid(loading_win) then
		vim.api.nvim_win_close(loading_win, true)
	end
	loading_win = nil
end

local function pick_base_and_open()
	if next(require("diffview.lib").views) ~= nil then
		vim.cmd("DiffviewClose")
		return
	end

	local options
	if is_citc() then
		options = get_citc_options()
	elseif is_hg() then
		options = get_hg_options()
	else
		options = get_git_options()
	end

	local lines = {}
	for i, opt in ipairs(options) do
		table.insert(lines, string.format(" %d. %s", i, opt.label))
	end

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

	local width = 0
	for _, line in ipairs(lines) do
		width = math.max(width, #line)
	end
	width = width + 4

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		row = math.floor((vim.o.lines - #lines - 2) / 2),
		col = math.floor((vim.o.columns - width) / 2),
		width = width,
		height = #lines,
		style = "minimal",
		border = "rounded",
		title = " Select Diff Base ",
		title_pos = "center",
	})

	local function close()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end

	local function select_and_load(opt)
		loading_win = win
		vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { " Loading diff... " })
		vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
		vim.cmd("redraw")
		vim.cmd("DiffviewOpen " .. opt.arg)
	end

	for i, opt in ipairs(options) do
		vim.keymap.set("n", tostring(i), function()
			select_and_load(opt)
		end, { buffer = buf, nowait = true })
	end

	vim.keymap.set("n", "<CR>", function()
		select_and_load(options[1])
	end, { buffer = buf, nowait = true })
	vim.keymap.set("n", "q", close, { buffer = buf, nowait = true })
	vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true })
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
					view_opened = close_loading,
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
			{ "<leader>gd", pick_base_and_open, desc = "Diffview (pick base)" },
			{ "<leader>gh", "<cmd>DiffviewFileHistory<CR>", desc = "File History" },
			{ "<leader>gr", "<cmd>DiffviewRefresh<CR>", desc = "Refresh Diffview" },
		},
	},
}
