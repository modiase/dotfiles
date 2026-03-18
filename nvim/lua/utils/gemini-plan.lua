local M = {}
local log = require("devlogs").new("gemini-plan")
local comments = require("utils.plan-comments")

local ns = vim.api.nvim_create_namespace("gemini_plan_comments")
local gemini_pane_id = nil

local POLL_INTERVAL_MS = 100
local POLL_TIMEOUT_MS = 10000
local DIALOG_PATTERN = "Do you want to"

local function tmux_send(text)
	if not gemini_pane_id then
		log.warning("tmux_send: pane ID not set")
		vim.notify("Gemini pane ID not set", vim.log.levels.WARN)
		return false
	end
	vim.fn.system({ "tmux", "send-keys", "-t", gemini_pane_id, "-l", text })
	local ok = vim.v.shell_error == 0
	log.debug("tmux_send pane=" .. gemini_pane_id .. " ok=" .. tostring(ok))
	return ok
end

local function tmux_send_key(key)
	if not gemini_pane_id then
		return false
	end
	vim.fn.system({ "tmux", "send-keys", "-t", gemini_pane_id, key })
	return vim.v.shell_error == 0
end

local function tmux_pane_contains(pattern)
	if not gemini_pane_id then
		return false
	end
	local output = vim.fn.system({ "tmux", "capture-pane", "-t", gemini_pane_id, "-p" })
	return output:find(pattern, 1, true) ~= nil
end

local function poll_and_send(key, callback)
	local elapsed = 0
	local timer = vim.uv.new_timer()
	log.debug("poll_and_send: waiting for dialog, key=" .. key)

	timer:start(
		0,
		POLL_INTERVAL_MS,
		vim.schedule_wrap(function()
			elapsed = elapsed + POLL_INTERVAL_MS

			if tmux_pane_contains(DIALOG_PATTERN) then
				timer:stop()
				timer:close()
				log.debug("poll_and_send: dialog found after " .. elapsed .. "ms key=" .. key)
				tmux_send(key)
				if callback then
					callback()
				end
				return
			end

			if elapsed >= POLL_TIMEOUT_MS then
				timer:stop()
				timer:close()
				log.warning("poll_and_send: timed out after " .. elapsed .. "ms")
				vim.notify("Timed out waiting for plan dialog", vim.log.levels.WARN)
			end
		end)
	)
end

local function is_plan_file(path)
	local match = path and path:match("/.gemini/.+/plans/.*%.md$") ~= nil
	log.debug("is_plan_file path=" .. tostring(path) .. " match=" .. tostring(match))
	return match
end

function M.find_existing_plan_tab()
	local buf = vim.g.gemini_plan_bufnr
	local tab = vim.g.gemini_plan_tabnr
	if tab and vim.api.nvim_tabpage_is_valid(tab) and buf and vim.api.nvim_buf_is_valid(buf) then
		log.debug("find_existing_plan_tab: cached tab=" .. tab .. " buf=" .. buf)
		return tab, buf
	end

	for _, t in ipairs(vim.api.nvim_list_tabpages()) do
		local win = vim.api.nvim_tabpage_get_win(t)
		local b = vim.api.nvim_win_get_buf(win)
		local name = vim.api.nvim_buf_get_name(b)
		if is_plan_file(name) then
			log.debug("find_existing_plan_tab: found by scan tab=" .. tostring(t) .. " buf=" .. b)
			return t, b
		end
	end
	log.debug("find_existing_plan_tab: none found")
	return nil, nil
end

function M.serialise_comments()
	local _, buf = M.find_existing_plan_tab()
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		log.debug("serialise_comments: no valid buf, skipping")
		return
	end

	local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
	if #marks == 0 then
		log.debug("serialise_comments: no extmarks, skipping")
		return
	end

	log.debug("serialise_comments: found " .. #marks .. " extmarks")
	vim.bo[buf].modifiable = true
	vim.bo[buf].readonly = false
	local count = comments.serialise(buf, ns)
	vim.cmd("silent write")
	vim.bo[buf].modifiable = false
	vim.bo[buf].readonly = true
	log.info("serialise_comments: wrote " .. count .. " comments")
end

function M.close()
	log.info("close: starting")
	M.serialise_comments()

	local tab, buf = M.find_existing_plan_tab()
	log.debug("close: tab=" .. tostring(tab) .. " buf=" .. tostring(buf))

	vim.g.gemini_plan_bufnr = nil
	vim.g.gemini_plan_tabnr = nil

	if tab and #vim.api.nvim_list_tabpages() > 1 then
		log.debug("close: closing tab=" .. tostring(tab))
		vim.api.nvim_set_current_tabpage(tab)
		vim.cmd("tabclose")
	else
		log.debug(
			"close: skipping tabclose (tab=" .. tostring(tab) .. " tabcount=" .. #vim.api.nvim_list_tabpages() .. ")"
		)
	end

	if buf and vim.api.nvim_buf_is_valid(buf) then
		log.debug("close: deleting buf=" .. buf)
		vim.api.nvim_buf_delete(buf, { force = true })
	end
end

function M.accept_auto()
	log.info("accept_auto")
	M.close()
	poll_and_send("1")
end

function M.accept_manual()
	log.info("accept_manual")
	M.close()
	poll_and_send("2")
end

function M.reject()
	log.info("reject")
	local buf = vim.g.gemini_plan_bufnr
	local has_comments = buf and #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) > 0

	local function do_reject(reason)
		M.close()
		poll_and_send("3", function()
			tmux_send_key("Enter")
			vim.defer_fn(function()
				tmux_send(reason)
				tmux_send_key("Enter")
			end, 200)
		end)
	end

	if has_comments then
		do_reject("Please address all comments in the plan")
		return
	end

	vim.ui.input({ prompt = "Rejection reason: " }, function(input)
		if not input then
			return
		end
		do_reject(input)
	end)
end

function M.setup_buffer(pane_id)
	log.info("setup_buffer called pane=" .. tostring(pane_id))
	if pane_id then
		gemini_pane_id = pane_id
	end

	local buf = vim.api.nvim_get_current_buf()
	local bufname = vim.api.nvim_buf_get_name(buf)
	log.debug(
		"setup_buffer: buf="
			.. buf
			.. " name="
			.. bufname
			.. " ft="
			.. vim.bo[buf].filetype
			.. " loaded="
			.. tostring(vim.api.nvim_buf_is_loaded(buf))
	)

	if vim.b[buf].gemini_plan_setup then
		log.debug("setup_buffer: already setup buf=" .. buf .. ", skipping")
		return
	end
	vim.b[buf].gemini_plan_setup = true

	local ok, count = pcall(comments.deserialise, buf, ns)
	if ok then
		log.debug("setup_buffer: deserialised " .. count .. " comments")
	else
		log.error("setup_buffer: deserialise failed: " .. tostring(count))
	end

	vim.bo[buf].modifiable = false
	vim.bo[buf].readonly = true
	vim.bo[buf].bufhidden = "delete"

	local opts = { buffer = buf, nowait = true }
	vim.keymap.set("n", "<leader>y", M.accept_auto, vim.tbl_extend("force", opts, { desc = "Accept (auto-approve)" }))
	vim.keymap.set(
		"n",
		"<leader>m",
		M.accept_manual,
		vim.tbl_extend("force", opts, { desc = "Accept (manual approve)" })
	)
	vim.keymap.set("n", "<leader>q", M.close, vim.tbl_extend("force", opts, { desc = "Close plan" }))
	vim.keymap.set("n", "<leader>n", M.reject, vim.tbl_extend("force", opts, { desc = "Reject plan" }))
	vim.keymap.set("n", "q", M.close, vim.tbl_extend("force", opts, { desc = "Close plan" }))
	log.debug("setup_buffer: mapped plan action keys (y/m/q/n)")

	comments.setup_keymaps(buf, ns)
	log.debug("setup_buffer: mapped comment keys (c/C/dc/]c/[c)")

	local disabled = { "i", "I", "A", "o", "O", "s", "S", "r", "R" }
	for _, key in ipairs(disabled) do
		vim.keymap.set("n", key, "<Nop>", { buffer = buf })
	end
	log.debug("setup_buffer: disabled insert keys")

	vim.g.gemini_plan_bufnr = buf
	vim.g.gemini_plan_tabnr = vim.api.nvim_get_current_tabpage()
	log.info("setup_buffer: complete buf=" .. buf .. " tab=" .. vim.api.nvim_get_current_tabpage())
end

return M
