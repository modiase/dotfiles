local M = {}

local current_plans_dir = nil
local claude_pane_id = nil

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

local function tmux_send(text)
	if not claude_pane_id then
		vim.notify("Claude pane ID not set", vim.log.levels.WARN)
		return false
	end
	vim.fn.system({ "tmux", "send-keys", "-t", claude_pane_id, "-l", text })
	return vim.v.shell_error == 0
end

local function tmux_send_key(key)
	if not claude_pane_id then
		return false
	end
	vim.fn.system({ "tmux", "send-keys", "-t", claude_pane_id, key })
	return vim.v.shell_error == 0
end

local function tmux_pane_contains(pattern)
	if not claude_pane_id then
		return false
	end
	local output = vim.fn.system({ "tmux", "capture-pane", "-t", claude_pane_id, "-p" })
	return output:find(pattern, 1, true) ~= nil
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

	local existing_tab, existing_buf = M.find_existing_plan_tab()
	if existing_tab then
		vim.api.nvim_set_current_tabpage(existing_tab)
		if not existing_buf or vim.api.nvim_buf_get_name(existing_buf) ~= file_path then
			vim.cmd("edit " .. vim.fn.fnameescape(file_path))
			M.setup_buffer()
		end
	else
		vim.cmd("tabnew " .. vim.fn.fnameescape(file_path))
		M.setup_buffer()
	end
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

local POLL_INTERVAL_MS = 100
local POLL_TIMEOUT_MS = 10000
local DIALOG_PATTERN = "manually approve edits"

local function poll_and_send(key, callback)
	local elapsed = 0
	local timer = vim.uv.new_timer()

	timer:start(
		0,
		POLL_INTERVAL_MS,
		vim.schedule_wrap(function()
			elapsed = elapsed + POLL_INTERVAL_MS

			if tmux_pane_contains(DIALOG_PATTERN) then
				timer:stop()
				timer:close()
				tmux_send(key)
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

function M.accept_clear()
	M.close()
	poll_and_send("1")
end

function M.accept_auto()
	M.close()
	poll_and_send("2")
end

function M.accept_manual()
	M.close()
	poll_and_send("3")
end

function M.reject()
	vim.ui.input({ prompt = "Rejection reason: " }, function(input)
		if not input then
			return
		end
		M.close()
		poll_and_send("4", function()
			tmux_send_key("Enter")
			vim.defer_fn(function()
				tmux_send(input)
				tmux_send_key("Enter")
			end, 200)
		end)
	end)
end

function M.setup_buffer(config_dir, pane_id)
	if config_dir then
		current_plans_dir = get_plans_dir(config_dir)
	end
	if pane_id then
		claude_pane_id = pane_id
	end
	local buf = vim.api.nvim_get_current_buf()

	vim.bo[buf].modifiable = false
	vim.bo[buf].readonly = true

	local opts = { buffer = buf, nowait = true }
	vim.keymap.set("n", "a", M.accept_clear, vim.tbl_extend("force", opts, { desc = "Accept + clear context" }))
	vim.keymap.set("n", "y", M.accept_auto, vim.tbl_extend("force", opts, { desc = "Accept (auto-approve)" }))
	vim.keymap.set("n", "m", M.accept_manual, vim.tbl_extend("force", opts, { desc = "Accept (manual approve)" }))
	vim.keymap.set("n", "q", M.close, vim.tbl_extend("force", opts, { desc = "Close plan" }))
	vim.keymap.set("n", "n", M.reject, vim.tbl_extend("force", opts, { desc = "Reject plan" }))

	for _, key in ipairs({ "i", "I", "A", "o", "O", "s", "S", "c", "C", "r", "R" }) do
		vim.keymap.set("n", key, "<Nop>", { buffer = buf })
	end
end

return M
