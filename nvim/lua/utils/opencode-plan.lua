local M = {}
local log = require("devlogs").new("opencode-plan")
local comments = require("utils.plan-comments")

local ns = vim.api.nvim_create_namespace("opencode_plan_comments")
local watcher = nil
local PLANS_DIR = ".opencode/plans"
local DEBOUNCE_MS = 200

local function get_plans_dir()
	return vim.fn.getcwd() .. "/" .. PLANS_DIR
end

local function is_plan_file(path)
	return path and path:match("%.md$") and path:find(PLANS_DIR, 1, true) ~= nil
end

function M.serialise_and_close()
	local buf = vim.api.nvim_get_current_buf()
	local count = comments.serialise(buf, ns)
	if count > 0 then
		log.info("serialise_and_close: wrote " .. count .. " comments")
	end

	vim.cmd("silent write")

	vim.g.opencode_plan_bufnr = nil
	vim.g.opencode_plan_tabnr = nil

	if #vim.api.nvim_list_tabpages() > 1 then
		vim.cmd("tabclose")
	else
		vim.api.nvim_buf_delete(buf, { force = true })
	end
end

function M.find_plan_tab()
	local buf = vim.g.opencode_plan_bufnr
	local tab = vim.g.opencode_plan_tabnr
	if tab and vim.api.nvim_tabpage_is_valid(tab) and buf and vim.api.nvim_buf_is_valid(buf) then
		return tab, buf
	end

	for _, t in ipairs(vim.api.nvim_list_tabpages()) do
		local win = vim.api.nvim_tabpage_get_win(t)
		local b = vim.api.nvim_win_get_buf(win)
		local name = vim.api.nvim_buf_get_name(b)
		if is_plan_file(name) then
			return t, b
		end
	end
	return nil, nil
end

function M.setup_buffer()
	local buf = vim.api.nvim_get_current_buf()
	log.info("setup_buffer buf=" .. buf)

	comments.deserialise(buf, ns)

	vim.g.opencode_plan_bufnr = buf
	vim.g.opencode_plan_tabnr = vim.api.nvim_get_current_tabpage()

	comments.setup_keymaps(buf, ns, {
		["<leader>q"] = {
			fn = function()
				M.serialise_and_close()
			end,
			desc = "Save comments and close",
		},
	})
end

local debounce_timer = nil

function M.on_plan_change(path)
	if debounce_timer then
		debounce_timer:stop()
		debounce_timer:close()
	end

	debounce_timer = vim.uv.new_timer()
	debounce_timer:start(
		DEBOUNCE_MS,
		0,
		vim.schedule_wrap(function()
			debounce_timer:close()
			debounce_timer = nil

			if not is_plan_file(path) then
				return
			end

			log.info("on_plan_change path=" .. path)

			local existing_tab, existing_buf = M.find_plan_tab()
			if existing_tab then
				vim.api.nvim_set_current_tabpage(existing_tab)
				local current_name = vim.api.nvim_buf_get_name(existing_buf)
				if current_name ~= path then
					vim.cmd("edit " .. vim.fn.fnameescape(path))
					M.setup_buffer()
				else
					vim.cmd("checktime")
				end
			else
				vim.cmd("tabnew " .. vim.fn.fnameescape(path))
				M.setup_buffer()
			end
		end)
	)
end

function M.setup()
	local plans_dir = get_plans_dir()
	if watcher then
		log.debug("setup: already watching")
		return
	end

	if vim.fn.isdirectory(vim.fn.getcwd() .. "/.opencode") == 0 then
		log.debug("setup: no .opencode directory, skipping")
		return
	end

	vim.fn.mkdir(plans_dir, "p")

	local handle = vim.uv.new_fs_event()
	if not handle then
		log.warning("setup: failed to create fs_event")
		return
	end

	local ok, err = handle:start(plans_dir, { recursive = true }, function(err_msg, filename, events)
		if err_msg then
			log.warning("fs_event error: " .. err_msg)
			return
		end
		if not filename or not events.change then
			return
		end

		local full_path = plans_dir .. "/" .. filename
		vim.schedule(function()
			M.on_plan_change(full_path)
		end)
	end)

	if not ok then
		log.warning("setup: fs_event start failed: " .. tostring(err))
		handle:close()
		return
	end

	watcher = handle
	log.info("setup: watching " .. plans_dir)

	vim.api.nvim_create_autocmd("BufRead", {
		pattern = plans_dir .. "/*.md",
		callback = function()
			M.setup_buffer()
		end,
	})
end

function M.stop()
	if watcher then
		watcher:stop()
		watcher:close()
		watcher = nil
		log.info("stop: watcher closed")
	end
	if debounce_timer then
		debounce_timer:stop()
		debounce_timer:close()
		debounce_timer = nil
	end
end

return M
