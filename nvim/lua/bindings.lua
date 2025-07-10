---@diagnostic disable-next-line: undefined-global
local vim = vim

vim.g.mapleader = " "

-- Window swap functionality
local marked_window = nil

local function mark_window_swap()
	marked_window = vim.fn.winnr()
end

local function do_window_swap()
	local cur_num = vim.fn.winnr()
	local cur_buf = vim.fn.bufnr("%")

	vim.cmd(marked_window .. "wincmd w")
	local marked_buf = vim.fn.bufnr("%")

	vim.cmd("hide buf " .. cur_buf)
	vim.cmd(cur_num .. "wincmd w")
	vim.cmd("hide buf " .. marked_buf)
end

-- Key mappings
local opts = { silent = true }

-- Managing buffers
vim.keymap.set("n", "<leader>C", ":bufdo bd<CR>:Dashboard<CR>", opts)
vim.keymap.set({ "n", "v" }, "<leader>y", '"+y', opts)
vim.keymap.set({ "n", "v" }, "<leader>d", '"+d', opts)

-- Managing files
vim.keymap.set("n", "<leader><leader>", ":noh<CR>", opts)

-- Centerpad
vim.keymap.set("n", "<leader>z", function()
	local width = vim.api.nvim_win_get_width(0)
	local pad = math.floor(width / (1 + math.sqrt(5)))
	require("centerpad").toggle({ leftpad = pad, rightpad = pad })
end, opts)

-- Window swap mappings
vim.keymap.set("n", "<leader>mw", mark_window_swap, opts)
vim.keymap.set("n", "<leader>pw", do_window_swap, opts)

-- Insert literal tab
vim.keymap.set("i", "<S-Tab>", "<C-V><Tab>", opts)

-- Window management
vim.keymap.set({ "n", "v" }, "<leader>k", ":close<CR>", opts)
vim.keymap.set({ "n", "v" }, "<leader>K", ":close!<CR>", opts)
vim.keymap.set({ "n", "v" }, "<leader>ww", ":vs<CR>", opts)
vim.keymap.set({ "n", "v" }, "<leader>ws", ":sp<CR>", opts)

-- Configuration
vim.keymap.set({ "n", "v" }, "<leader>r", function()
	vim.cmd("source " .. vim.env.MYVIMRC)
	print("Configuration reloaded")
end, opts)

vim.keymap.set({ "n", "v" }, "<leader>Q", ":qa!<CR>", opts)
