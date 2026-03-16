local M = {}

M.COMMENT_PREFIX = "> **[Comment]** "
M.COMMENT_SIGN = "󰆈"

function M.set_extmark(buf, ns, line, text)
	return vim.api.nvim_buf_set_extmark(buf, ns, line, 0, {
		virt_lines = {
			{ { "  " .. M.COMMENT_SIGN .. " " .. text, "DiagnosticInfo" } },
		},
		sign_text = M.COMMENT_SIGN,
		sign_hl_group = "DiagnosticInfo",
	})
end

function M.get_comment_at_line(buf, ns, line)
	local marks = vim.api.nvim_buf_get_extmarks(buf, ns, { line, 0 }, { line, -1 }, { details = true })
	if #marks > 0 then
		return marks[1]
	end
	return nil
end

local function extract_text(mark)
	local details = mark[4]
	if details.virt_lines and details.virt_lines[1] and details.virt_lines[1][1] then
		return details.virt_lines[1][1][1]:gsub("^%s*" .. M.COMMENT_SIGN .. "%s*", "")
	end
	return ""
end

function M.add_comment(buf, ns, line)
	line = line or vim.api.nvim_win_get_cursor(0)[1] - 1

	if M.get_comment_at_line(buf, ns, line) then
		M.edit_comment(buf, ns, line)
		return
	end

	vim.ui.input({ prompt = "Comment: " }, function(input)
		if not input or input == "" then
			return
		end
		M.set_extmark(buf, ns, line, input)
	end)
end

function M.edit_comment(buf, ns, line)
	line = line or vim.api.nvim_win_get_cursor(0)[1] - 1

	local mark = M.get_comment_at_line(buf, ns, line)
	if not mark then
		vim.notify("No comment on this line", vim.log.levels.INFO)
		return
	end

	local current_text = extract_text(mark)

	vim.ui.input({ prompt = "Comment: ", default = current_text }, function(input)
		if not input then
			return
		end
		vim.api.nvim_buf_del_extmark(buf, ns, mark[1])
		if input ~= "" then
			M.set_extmark(buf, ns, line, input)
		end
	end)
end

function M.delete_comment(buf, ns, line)
	line = line or vim.api.nvim_win_get_cursor(0)[1] - 1

	local mark = M.get_comment_at_line(buf, ns, line)
	if not mark then
		vim.notify("No comment on this line", vim.log.levels.INFO)
		return
	end

	vim.api.nvim_buf_del_extmark(buf, ns, mark[1])
end

function M.next_comment(buf, ns)
	local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1
	local marks = vim.api.nvim_buf_get_extmarks(buf, ns, { cursor_line + 1, 0 }, { -1, -1 }, {})
	if #marks > 0 then
		vim.api.nvim_win_set_cursor(0, { marks[1][2] + 1, 0 })
	else
		local wrap_marks = vim.api.nvim_buf_get_extmarks(buf, ns, { 0, 0 }, { cursor_line, -1 }, {})
		if #wrap_marks > 0 then
			vim.api.nvim_win_set_cursor(0, { wrap_marks[1][2] + 1, 0 })
		end
	end
end

function M.prev_comment(buf, ns)
	local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1
	if cursor_line > 0 then
		local marks = vim.api.nvim_buf_get_extmarks(buf, ns, { cursor_line - 1, -1 }, { 0, 0 }, {})
		if #marks > 0 then
			vim.api.nvim_win_set_cursor(0, { marks[1][2] + 1, 0 })
			return
		end
	end
	local wrap_marks = vim.api.nvim_buf_get_extmarks(buf, ns, { -1, -1 }, { cursor_line, 0 }, {})
	if #wrap_marks > 0 then
		vim.api.nvim_win_set_cursor(0, { wrap_marks[1][2] + 1, 0 })
	end
end

function M.deserialise(buf, ns)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local to_remove = {}

	for i, line in ipairs(lines) do
		local comment_text = line:match("^%s*" .. vim.pesc(M.COMMENT_PREFIX) .. "(.+)$")
		if comment_text and i > 1 then
			table.insert(to_remove, { line_idx = i - 1, anchor = i - 2, text = comment_text })
		end
	end

	for j = #to_remove, 1, -1 do
		local entry = to_remove[j]
		vim.api.nvim_buf_set_lines(buf, entry.line_idx, entry.line_idx + 1, false, {})
	end

	for _, entry in ipairs(to_remove) do
		local adjusted = entry.anchor
		for k = 1, #to_remove do
			if to_remove[k].line_idx <= entry.anchor then
				adjusted = adjusted - 1
			end
		end
		if adjusted >= 0 then
			M.set_extmark(buf, ns, adjusted, entry.text)
		end
	end

	return #to_remove
end

function M.serialise(buf, ns)
	local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
	if #marks == 0 then
		return 0
	end

	local insertions = {}
	for _, mark in ipairs(marks) do
		local text = extract_text(mark)
		if text ~= "" then
			table.insert(insertions, { after_line = mark[2], text = M.COMMENT_PREFIX .. text })
		end
	end

	table.sort(insertions, function(a, b)
		return a.after_line > b.after_line
	end)

	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

	for _, ins in ipairs(insertions) do
		vim.api.nvim_buf_set_lines(buf, ins.after_line + 1, ins.after_line + 1, false, { ins.text })
	end

	return #insertions
end

function M.setup_keymaps(buf, ns, extra_keymaps)
	local opts = { buffer = buf, nowait = true }
	vim.keymap.set("n", "c", function()
		M.add_comment(buf, ns)
	end, vim.tbl_extend("force", opts, { desc = "Add comment" }))
	vim.keymap.set("n", "C", function()
		M.edit_comment(buf, ns)
	end, vim.tbl_extend("force", opts, { desc = "Edit comment" }))
	vim.keymap.set("n", "dc", function()
		M.delete_comment(buf, ns)
	end, vim.tbl_extend("force", opts, { desc = "Delete comment" }))
	vim.keymap.set("n", "]c", function()
		M.next_comment(buf, ns)
	end, vim.tbl_extend("force", opts, { desc = "Next comment" }))
	vim.keymap.set("n", "[c", function()
		M.prev_comment(buf, ns)
	end, vim.tbl_extend("force", opts, { desc = "Previous comment" }))

	if extra_keymaps then
		for key, mapping in pairs(extra_keymaps) do
			vim.keymap.set("n", key, mapping.fn, vim.tbl_extend("force", opts, { desc = mapping.desc }))
		end
	end
end

return M
