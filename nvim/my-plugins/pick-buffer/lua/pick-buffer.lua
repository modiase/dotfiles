local LABELS = "asdfghjklASDFGHJKLqwertyuiopQWERTYUIOPzxcvbnmZXCVBNM1234567890"

local M = {}

function M.pick()
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

return M
