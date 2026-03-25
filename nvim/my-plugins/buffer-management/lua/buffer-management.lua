local function get_windows_displaying_buffer(bufnr)
	local windows = {}
	local tabpage = vim.api.nvim_get_current_tabpage()
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
		if vim.api.nvim_win_get_buf(win) == bufnr then
			table.insert(windows, win)
		end
	end
	return windows
end

local M = {}

function M.swap(wincmd)
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

function M.close(config)
	config = config or {}
	local force = config.force or false

	local bufnr = vim.api.nvim_get_current_buf()
	local winnr = vim.api.nvim_get_current_win()
	local windows = get_windows_displaying_buffer(bufnr)

	if #windows == 1 then
		local success, _ = pcall(vim.api.nvim_buf_delete, bufnr, { force = force })
		if not success then
			print("Could not close window")
		end
	else
		vim.api.nvim_win_close(winnr, { force = force })
	end
end

function M.close_unopened()
	local buffers = vim.api.nvim_list_bufs()
	for _, bufnr in ipairs(buffers) do
		if #get_windows_displaying_buffer(bufnr) < 1 then
			pcall(vim.api.nvim_buf_delete, bufnr, { force = false })
		end
	end
end

function M.expand()
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

return M
