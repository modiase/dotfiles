---@diagnostic disable-next-line: undefined-global
local vim = vim

local colors = require("colors")

local function blend(fg_hex, bg_hex, alpha)
	local function parse(hex)
		hex = hex:gsub("#", "")
		return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
	end
	local fr, fg, fb = parse(fg_hex)
	local br, bg_, bb = parse(bg_hex)
	return string.format(
		"#%02x%02x%02x",
		math.floor(fr * alpha + br * (1 - alpha)),
		math.floor(fg * alpha + bg_ * (1 - alpha)),
		math.floor(fb * alpha + bb * (1 - alpha))
	)
end

local bg = colors.base00
vim.api.nvim_set_hl(0, "ConflictOurs", { bg = blend(colors.base0B, bg, 0.20) })
vim.api.nvim_set_hl(0, "ConflictTheirs", { bg = blend(colors.base0D, bg, 0.20) })
vim.api.nvim_set_hl(0, "ConflictAncestor", { bg = blend(colors.base0E, bg, 0.20) })
vim.api.nvim_set_hl(0, "ConflictMarker", { bg = colors.base01, fg = colors.base03, bold = true })

local ns = vim.api.nvim_create_namespace("conflict_markers")

local function highlight_conflicts(buf)
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local region = nil
	for i, line in ipairs(lines) do
		if line:match("^<<<<<<<") then
			region = "ours"
			vim.api.nvim_buf_add_highlight(buf, ns, "ConflictMarker", i - 1, 0, -1)
		elseif line:match("^|||||||") and region then
			region = "ancestor"
			vim.api.nvim_buf_add_highlight(buf, ns, "ConflictMarker", i - 1, 0, -1)
		elseif line:match("^=======") and region then
			region = "theirs"
			vim.api.nvim_buf_add_highlight(buf, ns, "ConflictMarker", i - 1, 0, -1)
		elseif line:match("^>>>>>>>") and region then
			vim.api.nvim_buf_add_highlight(buf, ns, "ConflictMarker", i - 1, 0, -1)
			region = nil
		elseif region == "ours" then
			vim.api.nvim_buf_add_highlight(buf, ns, "ConflictOurs", i - 1, 0, -1)
		elseif region == "theirs" then
			vim.api.nvim_buf_add_highlight(buf, ns, "ConflictTheirs", i - 1, 0, -1)
		elseif region == "ancestor" then
			vim.api.nvim_buf_add_highlight(buf, ns, "ConflictAncestor", i - 1, 0, -1)
		end
	end
end

vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "BufEnter" }, {
	group = vim.api.nvim_create_augroup("ConflictMarkerHighlight", { clear = true }),
	callback = function(ev)
		highlight_conflicts(ev.buf)
	end,
})

local function find_conflict_at_cursor()
	local buf = vim.api.nvim_get_current_buf()
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local cursor_row = vim.api.nvim_win_get_cursor(0)[1]

	local start_row, mid_row, sep_row, end_row, ancestor_row
	for i, line in ipairs(lines) do
		if line:match("^<<<<<<<") then
			start_row = i
			mid_row, sep_row, end_row, ancestor_row = nil, nil, nil, nil
		elseif line:match("^|||||||") and start_row then
			ancestor_row = i
		elseif line:match("^=======") and start_row then
			sep_row = i
		elseif line:match("^>>>>>>>") and start_row then
			end_row = i
			if cursor_row >= start_row and cursor_row <= end_row then
				mid_row = ancestor_row
				return { start_row = start_row, mid_row = mid_row, sep_row = sep_row, end_row = end_row }
			end
			start_row, mid_row, sep_row, end_row, ancestor_row = nil, nil, nil, nil, nil
		end
	end
end

local function choose_conflict(choice)
	return function()
		local c = find_conflict_at_cursor()
		if not c then
			vim.notify("No conflict marker under cursor", vim.log.levels.WARN)
			return
		end

		local buf = vim.api.nvim_get_current_buf()
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		local keep = {}

		if choice == "ours" then
			for i = c.start_row + 1, (c.mid_row or c.sep_row) - 1 do
				table.insert(keep, lines[i])
			end
		elseif choice == "theirs" then
			for i = c.sep_row + 1, c.end_row - 1 do
				table.insert(keep, lines[i])
			end
		elseif choice == "base" then
			if c.mid_row then
				for i = c.mid_row + 1, c.sep_row - 1 do
					table.insert(keep, lines[i])
				end
			end
		elseif choice == "all" then
			for i = c.start_row + 1, (c.mid_row or c.sep_row) - 1 do
				table.insert(keep, lines[i])
			end
			for i = c.sep_row + 1, c.end_row - 1 do
				table.insert(keep, lines[i])
			end
		end

		vim.api.nvim_buf_set_lines(buf, c.start_row - 1, c.end_row, false, keep)
		highlight_conflicts(buf)
	end
end

local function jump_conflict(direction)
	return function()
		local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
		local targets = {}
		for i, line in ipairs(lines) do
			if line:match("^<<<<<<<") then
				table.insert(targets, i)
			end
		end
		if #targets == 0 then
			return
		end

		if direction == "next" then
			for _, row in ipairs(targets) do
				if row > cursor_row then
					vim.api.nvim_win_set_cursor(0, { row, 0 })
					return
				end
			end
			vim.api.nvim_win_set_cursor(0, { targets[1], 0 })
		else
			for i = #targets, 1, -1 do
				if targets[i] < cursor_row then
					vim.api.nvim_win_set_cursor(0, { targets[i], 0 })
					return
				end
			end
			vim.api.nvim_win_set_cursor(0, { targets[#targets], 0 })
		end
	end
end

vim.keymap.set("n", "gco", choose_conflict("ours"), { desc = "Conflict: choose ours" })
vim.keymap.set("n", "gct", choose_conflict("theirs"), { desc = "Conflict: choose theirs" })
vim.keymap.set("n", "gcb", choose_conflict("base"), { desc = "Conflict: choose base" })
vim.keymap.set("n", "gca", choose_conflict("all"), { desc = "Conflict: choose all" })
vim.keymap.set("n", "]x", jump_conflict("next"), { desc = "Next conflict" })
vim.keymap.set("n", "[x", jump_conflict("prev"), { desc = "Previous conflict" })
