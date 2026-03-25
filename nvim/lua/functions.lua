---@diagnostic disable-next-line: undefined-global
local vim = vim

function FullPathCp()
	-- Get the full path of the current file
	local abs_path = vim.fn.expand("%:p")
	print(abs_path)
	vim.fn.setreg("+", abs_path, "c")
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
			vim.fn.setreg("+", relative_path, "c")
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

local LABELS = "asdfghjklASDFGHJKLqwertyuiopQWERTYUIOPzxcvbnmZXCVBNM1234567890"

local function pick_buffer()
	local bufs = vim.tbl_filter(function(b)
		return vim.bo[b].buflisted
	end, vim.api.nvim_list_bufs())

	if #bufs < 2 then
		vim.notify("No other buffers open", vim.log.levels.INFO)
		return
	end

	local cur = vim.api.nvim_get_current_buf()
	local count = math.min(#bufs, #LABELS)

	local lines = {}
	local max_width = 0
	for i = 1, count do
		local b = bufs[i]
		local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":t")
		if name == "" then
			name = "[No Name]"
		end
		local modified = vim.bo[b].modified and " +" or ""
		local label = LABELS:sub(i, i)
		local line = " " .. label .. "  " .. name .. modified .. " "
		table.insert(lines, { text = line, buf = b, label_col = 1, name_col = 4, mod_col = 4 + #name })
		if #line > max_width then
			max_width = #line
		end
	end

	local buf = vim.api.nvim_create_buf(false, true)
	local display = {}
	for _, l in ipairs(lines) do
		table.insert(display, l.text .. string.rep(" ", max_width - #l.text))
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, display)

	local ns = vim.api.nvim_create_namespace("pick_buffer")
	for i, l in ipairs(lines) do
		vim.api.nvim_buf_add_highlight(buf, ns, "FlashLabel", i - 1, l.label_col, l.label_col + 1)
		if l.buf == cur then
			vim.api.nvim_buf_add_highlight(
				buf,
				ns,
				"WarningMsg",
				i - 1,
				l.name_col,
				l.name_col + #display[i] - l.name_col
			)
		end
		if vim.bo[l.buf].modified then
			vim.api.nvim_buf_add_highlight(buf, ns, "DiffAdd", i - 1, l.mod_col, l.mod_col + 2)
		end
	end

	local win_height = count
	local win_width = max_width
	local editor_width = vim.o.columns
	local editor_height = vim.o.lines

	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		row = math.floor((editor_height - win_height) / 2),
		col = math.floor((editor_width - win_width) / 2),
		width = win_width,
		height = win_height,
		style = "minimal",
		border = "rounded",
		focusable = false,
		zindex = 250,
		title = " Go to Buffer ",
		title_pos = "center",
	})
	vim.api.nvim_win_set_option(win, "winhl", "FloatBorder:FlashLabel,NormalFloat:Normal")

	vim.cmd("redraw")
	local ok, char = pcall(vim.fn.getcharstr)

	if vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
	end
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_delete(buf, { force = true })
	end
	vim.cmd("redraw")

	if not ok then
		return
	end

	local idx = LABELS:find(char, 1, true)
	if idx and idx <= count then
		vim.api.nvim_set_current_buf(bufs[idx])
	end
end

vim.keymap.set("n", "gb", pick_buffer, { noremap = true, silent = true })

local PATH_PATTERN = [[\v[~.]?/?[a-zA-Z0-9_.@-]+(/[a-zA-Z0-9_.@-]+)+(:[0-9]+){,2}]]
local PATH_LABEL_HL = "PickPathLabel"
local colors = require("colors")
vim.api.nvim_set_hl(0, PATH_LABEL_HL, { fg = colors.base00, bg = colors.base0B, bold = true })

local function resolve_path(raw)
	local path, line, col = raw:match("^(.-)%:(%d+)%:(%d+)$")
	if not path then
		path, line = raw:match("^(.-)%:(%d+)$")
	end
	if not path then
		path = raw
	end

	local expanded = path:gsub("^~", vim.env.HOME)
	if vim.fn.filereadable(expanded) ~= 1 then
		return nil
	end
	return { path = expanded, line = tonumber(line), col = tonumber(col) }
end

local function pick_path()
	local top = vim.fn.line("w0")
	local bot = vim.fn.line("w$")
	local candidates = {}

	for lnum = top, bot do
		local text = vim.fn.getline(lnum)
		local start = 0
		while true do
			local match = vim.fn.matchstrpos(text, PATH_PATTERN, start)
			local str, s, e = match[1], match[2], match[3]
			if s == -1 then
				break
			end
			local resolved = resolve_path(str)
			if resolved then
				resolved.lnum = lnum
				resolved.col_start = s
				table.insert(candidates, resolved)
			end
			start = e
		end
	end

	if #candidates == 0 then
		vim.notify("No file paths found in viewport", vim.log.levels.INFO)
		return
	end

	local ns = vim.api.nvim_create_namespace("pick_path")
	local count = math.min(#candidates, #LABELS)

	for i = 1, count do
		local c = candidates[i]
		local label = LABELS:sub(i, i)
		vim.api.nvim_buf_set_extmark(0, ns, c.lnum - 1, c.col_start, {
			virt_text = { { label, PATH_LABEL_HL } },
			virt_text_pos = "overlay",
		})
	end

	vim.cmd("redraw")
	local ok, char = pcall(vim.fn.getcharstr)
	vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
	vim.cmd("redraw")

	if not ok then
		return
	end

	local idx = LABELS:find(char, 1, true)
	if not idx or idx > count then
		return
	end

	local target = candidates[idx]
	vim.cmd("edit " .. vim.fn.fnameescape(target.path))
	if target.line then
		vim.api.nvim_win_set_cursor(0, { target.line, (target.col or 1) - 1 })
	end
end

vim.keymap.set("n", "gp", pick_path, { noremap = true, silent = true })
