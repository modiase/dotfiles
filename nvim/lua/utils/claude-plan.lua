local M = {}

local current_plans_dir = nil

local function get_plans_dir(config_dir)
	config_dir = config_dir or os.getenv("CLAUDE_CONFIG_DIR") or (os.getenv("HOME") .. "/.claude")
	return vim.fn.resolve(config_dir) .. "/plans"
end

local function is_plan_file(path, plans_dir)
	plans_dir = plans_dir or current_plans_dir or get_plans_dir()
	return path and path:match("^" .. vim.pesc(plans_dir) .. "/.*%.md$")
end

function M.find_existing_plan_tab()
	local plans_dir = current_plans_dir or get_plans_dir()
	for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
		local win = vim.api.nvim_tabpage_get_win(tab)
		local buf = vim.api.nvim_win_get_buf(win)
		local name = vim.api.nvim_buf_get_name(buf)
		if is_plan_file(name, plans_dir) then
			return tab, buf
		end
	end
	return nil, nil
end

function M.find_claude_terminal_win()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "terminal" then
			local name = vim.api.nvim_buf_get_name(buf)
			if name:match("claude") then
				for _, win in ipairs(vim.api.nvim_list_wins()) do
					if vim.api.nvim_win_get_buf(win) == buf then
						return win, vim.b[buf].terminal_job_id
					end
				end
			end
		end
	end
	return nil, nil
end

function M.open(file_path, config_dir)
	if not file_path then
		return
	end

	current_plans_dir = get_plans_dir(config_dir)
	file_path = vim.fn.resolve(file_path)
	if not is_plan_file(file_path, current_plans_dir) then
		return
	end

	local existing_tab = M.find_existing_plan_tab()
	if existing_tab then
		vim.api.nvim_set_current_tabpage(existing_tab)
		vim.cmd("edit " .. vim.fn.fnameescape(file_path))
	else
		vim.cmd("tabnew " .. vim.fn.fnameescape(file_path))
	end

	M.setup_buffer()
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

function M.send_keys(keys)
	local _, chan = M.find_claude_terminal_win()
	if chan then
		vim.api.nvim_chan_send(chan, keys)
		return true
	end
	vim.notify("Claude terminal not found", vim.log.levels.WARN)
	return false
end

local function find_claude_terminal_buf()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "terminal" then
			local name = vim.api.nvim_buf_get_name(buf)
			if name:match("claude") then
				return buf
			end
		end
	end
	return nil
end

local function terminal_contains(buf, pattern)
	local line_count = vim.api.nvim_buf_line_count(buf)
	local start_line = math.max(0, line_count - 10)
	local lines = vim.api.nvim_buf_get_lines(buf, start_line, -1, false)
	for _, line in ipairs(lines) do
		if line:find(pattern, 1, true) then
			return true
		end
	end
	return false
end

local POLL_INTERVAL_MS = 100
local POLL_TIMEOUT_MS = 10000
local DIALOG_PATTERN = "Would you like to proceed?"

local function poll_and_send(key, callback)
	local elapsed = 0
	local timer = vim.uv.new_timer()

	timer:start(
		0,
		POLL_INTERVAL_MS,
		vim.schedule_wrap(function()
			elapsed = elapsed + POLL_INTERVAL_MS
			local buf = find_claude_terminal_buf()

			if buf and terminal_contains(buf, DIALOG_PATTERN) then
				timer:stop()
				timer:close()
				M.send_keys(key)
				if callback then
					callback()
				end
				return
			end

			if elapsed >= POLL_TIMEOUT_MS then
				timer:stop()
				timer:close()
				vim.notify("Timed out waiting for plan dialog", vim.log.levels.WARN)
			end
		end)
	)
end

function M.accept_auto()
	M.close()
	poll_and_send("1")
end

function M.accept_manual()
	M.close()
	poll_and_send("2")
end

function M.reject()
	vim.ui.input({ prompt = "Rejection reason: " }, function(input)
		if not input then
			return
		end
		M.close()
		poll_and_send("3", function()
			vim.defer_fn(function()
				local win = M.find_claude_terminal_win()
				if win then
					vim.api.nvim_set_current_win(win)
					vim.cmd("startinsert")
					vim.api.nvim_feedkeys(input, "t", false)
				end
			end, 100)
		end)
	end)
end

function M.setup_buffer()
	local buf = vim.api.nvim_get_current_buf()

	vim.bo[buf].modifiable = false
	vim.bo[buf].readonly = true

	local opts = { buffer = buf, nowait = true }
	vim.keymap.set("n", "a", M.accept_auto, vim.tbl_extend("force", opts, { desc = "Accept plan (auto)" }))
	vim.keymap.set("n", "y", M.accept_auto, vim.tbl_extend("force", opts, { desc = "Accept plan (auto)" }))
	vim.keymap.set("n", "m", M.accept_manual, vim.tbl_extend("force", opts, { desc = "Accept plan (manual)" }))
	vim.keymap.set("n", "q", M.close, vim.tbl_extend("force", opts, { desc = "Close plan" }))
	vim.keymap.set("n", "n", M.reject, vim.tbl_extend("force", opts, { desc = "Reject plan" }))

	for _, key in ipairs({ "i", "I", "A", "o", "O", "s", "S", "c", "C", "r", "R" }) do
		vim.keymap.set("n", key, "<Nop>", { buffer = buf })
	end
end

return M
