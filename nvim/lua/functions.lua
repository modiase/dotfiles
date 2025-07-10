---@diagnostic disable-next-line: undefined-global
local vim = vim

function FullPathCp()
	-- Get the full path of the current file
	local abs_path = vim.fn.expand("%:p")
	print(abs_path)
	vim.fn.setreg("+", abs_path, c)
end

vim.api.nvim_set_keymap("n", "cp", ":lua FullPathCp()<CR>", { noremap = true })

function GitAwareCp()
	-- Get the full path of the current file
	local file_path = vim.fn.expand("%:p")

	-- Separate the path into directory and trailing file component
	local dir_path = vim.fn.fnamemodify(file_path, ":h")

	-- Iterate up through directory structure
	while dir_path ~= "/" and dir_path ~= "." do
		-- Check for .git directory or file
		if vim.fn.isdirectory(dir_path .. "/.git") == 1 then
			-- Found .git, compute relative path
			local relative_path = vim.fn.fnamemodify(file_path, ":.")
			print(relative_path)
			vim.fn.setreg("+", relative_path, c)
			return
		else
			-- Move up one directory level
			dir_path = vim.fn.fnamemodify(dir_path, ":h")
		end
	end

	print("No git directory found in hierarchy")
end

vim.api.nvim_set_keymap("n", "gcp", ":lua GitAwareCp()<CR>", { noremap = true })

function SwapWithBuffer(wincmd)
	-- Get the current buffer and window ID
	local start_win = vim.api.nvim_get_current_win()
	local start_buf = vim.api.nvim_win_get_buf(start_win)
	local start_cursor = vim.api.nvim_win_get_cursor(start_win)

	vim.cmd(wincmd)
	local target_win = vim.api.nvim_get_current_win()

	if target_win == start_win then
		print("Could not move to next window")
		return
	end
	local target_buf = vim.api.nvim_win_get_buf(target_win)
	local target_cursor = vim.api.nvim_win_get_cursor(target_win)

	vim.api.nvim_win_set_buf(start_win, target_buf)
	vim.api.nvim_win_set_buf(target_win, start_buf)

	vim.api.nvim_win_set_cursor(target_win, start_cursor)
	vim.api.nvim_win_set_cursor(start_win, target_cursor)
end

-- To use this command directly in Neovim, map it to a desired keybinding:
vim.api.nvim_set_keymap("n", "<C-w><C-h>", ":lua SwapWithBuffer('wincmd h')<CR>", { noremap = true, silent = true })

vim.api.nvim_set_keymap("n", "<C-w><C-l>", ":lua SwapWithBuffer('wincmd l')<CR>", { noremap = true, silent = true })

function GetWindowsDisplayingBuffer(bufnr)
	local windows_displaying_buffer = {}
	local tabpage = vim.api.nvim_get_current_tabpage()
	local windows = vim.api.nvim_tabpage_list_wins(tabpage)
	for _, win in ipairs(windows) do
		if vim.api.nvim_win_get_buf(win) == bufnr then
			table.insert(windows_displaying_buffer, win)
		end
	end
	return windows_displaying_buffer
end

function CloseBufferWindow(config)
	config = config or {}
	local force = config.force or false

	local bufnr = vim.api.nvim_get_current_buf()
	local winnr = vim.api.nvim_get_current_win()
	local windows = GetWindowsDisplayingBuffer(bufnr)

	if #windows == 1 then
		local success, _ = pcall(vim.api.nvim_buf_delete, bufnr, { force = force })
		if not success then
			print("Could not close window")
		end
	else
		vim.api.nvim_win_close(winnr, { force = force })
	end
end

function CloseUnopenedBuffers()
	local buffers = vim.api.nvim_list_bufs()
	for _, bufnr in ipairs(buffers) do
		local buffer_open_in_window_count = #GetWindowsDisplayingBuffer(bufnr)
		if buffer_open_in_window_count < 1 then
			pcall(vim.api.nvim_buf_delete, bufnr, { force = false })
		end
	end
end

function ExpandCurrentBuffer()
	local current_win = vim.api.nvim_get_current_win()
	local current_win_width = vim.api.nvim_win_get_width(current_win)

	vim.cmd("wincmd h")
	local left_win = vim.api.nvim_get_current_win()
	local left_win_width = vim.api.nvim_win_get_width(current_win)

	if left_win ~= current_win then
		vim.api.nvim_win_set_width(left_win, left_win_width - math.floor(0.5 * (140 - current_win_width)))
		vim.api.nvim_set_current_win(current_win)
	end
	vim.api.nvim_win_set_width(current_win, 140)
end

vim.api.nvim_set_keymap("n", "<leader>x", ":lua CloseBufferWindow()<CR>", { noremap = true, silent = true })

vim.api.nvim_set_keymap(
	"n",
	"<leader>X",
	":lua CloseBufferWindow({ force = true })<CR>",
	{ noremap = true, silent = true }
)

vim.api.nvim_set_keymap("n", "<leader>A", ":lua CloseUnopenedBuffers()<CR>", { noremap = true, silent = true })

vim.api.nvim_set_keymap("n", "<C-w><leader>", ":lua ExpandCurrentBuffer()<CR>", { noremap = true, silent = true })

local function syn_stack()
	local line = vim.fn.line(".")
	local col = vim.fn.col(".")

	for _, id1 in ipairs(vim.fn.synstack(line, col)) do
		local id2 = vim.fn.synIDtrans(id1)
		local name1 = vim.fn.synIDattr(id1, "name")
		local name2 = vim.fn.synIDattr(id2, "name")
		print(name1 .. " -> " .. name2)
	end
end

vim.keymap.set("n", "gm", syn_stack, { silent = true })
