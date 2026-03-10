local M = {}

local plans_dir = os.getenv("HOME") .. "/.gemini/plans"

local function is_plan_file(path)
	return path and path:match("^" .. vim.pesc(plans_dir) .. "/.*%.md$")
end

function M.find_existing_plan_tab()
	for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
		local win = vim.api.nvim_tabpage_get_win(tab)
		local buf = vim.api.nvim_win_get_buf(win)
		local name = vim.api.nvim_buf_get_name(buf)
		if is_plan_file(name) then
			return tab, buf
		end
	end
	return nil, nil
end

local function get_gemini_pane()
	local output = vim.fn.system("tmux show-environment GEMINI_PANE 2>/dev/null")
	if vim.v.shell_error ~= 0 then
		return nil
	end
	return output:match("GEMINI_PANE=(%%%d+)")
end

local function tmux_send(text)
	local pane = get_gemini_pane()
	if not pane then
		vim.notify("Gemini pane not found", vim.log.levels.WARN)
		return false
	end
	vim.fn.system({ "tmux", "send-keys", "-t", pane, "-l", text })
	return vim.v.shell_error == 0
end

function M.close()
	local tab, buf = M.find_existing_plan_tab()

	if tab and #vim.api.nvim_list_tabpages() > 1 then
		vim.api.nvim_set_current_tabpage(tab)
		vim.cmd("tabclose")
	elseif buf and vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_delete(buf, { force = true })
	end
end

local function close_and_send(text)
	M.close()
	tmux_send(text)
end

function M.open_latest()
	local output = vim.fn.system("ls -t " .. vim.fn.shellescape(plans_dir) .. "/*.md 2>/dev/null")
	if vim.v.shell_error ~= 0 or output == "" then
		vim.notify("No Gemini plans found", vim.log.levels.INFO)
		return
	end

	local latest = output:match("[^\n]+")
	if not latest then
		return
	end

	local existing_tab, existing_buf = M.find_existing_plan_tab()
	if existing_tab then
		vim.api.nvim_set_current_tabpage(existing_tab)
		if not existing_buf or vim.api.nvim_buf_get_name(existing_buf) ~= latest then
			vim.cmd("edit " .. vim.fn.fnameescape(latest))
			M.setup_buffer()
		end
	else
		vim.cmd("tabnew " .. vim.fn.fnameescape(latest))
		M.setup_buffer()
	end
end

function M.setup_buffer()
	local buf = vim.api.nvim_get_current_buf()

	vim.bo[buf].modifiable = false
	vim.bo[buf].readonly = true

	local bopts = { buffer = buf, nowait = true }
	vim.keymap.set("n", "a", function()
		close_and_send("1")
	end, vim.tbl_extend("force", bopts, { desc = "Auto-approve" }))
	vim.keymap.set("n", "y", function()
		close_and_send("2")
	end, vim.tbl_extend("force", bopts, { desc = "Manual approve" }))
	vim.keymap.set("n", "n", function()
		close_and_send("3")
	end, vim.tbl_extend("force", bopts, { desc = "Reject" }))
	vim.keymap.set("n", "q", M.close, vim.tbl_extend("force", bopts, { desc = "Close plan" }))

	for _, key in ipairs({ "i", "I", "A", "o", "O", "s", "S", "c", "C", "r", "R" }) do
		vim.keymap.set("n", key, "<Nop>", { buffer = buf })
	end
end

return M
