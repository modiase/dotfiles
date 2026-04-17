local log = require("devlogs").new("pick-path")
local LABELS = "asdfghjklASDFGHJKLqwertyuiopQWERTYUIOPzxcvbnmZXCVBNM1234567890"
local PATH_CHARS = "[%w_.@~/:-]+"
local LABEL_HL = "PickPathLabel"

local DEFAULT_OPTS = {
	precompute_deadline_ms = 100,
	interactive_deadline_ms = 5000,
	debounce_ms = 50,
}

local opts = vim.deepcopy(DEFAULT_OPTS)
local buf_cache = {}
local debounce_timer = vim.uv.new_timer()
local label_ns = vim.api.nvim_create_namespace("pick_path")

local function is_path_candidate(str)
	if str:find("/", 1, true) then
		return true
	end
	if str:match("%.[%a][%a]+$") then
		return true
	end
	return false
end

local function find_repo_root(from)
	for _, vcs in ipairs({ ".git", ".hg" }) do
		local found = vim.fn.finddir(vcs, from .. ";")
		if found ~= "" then
			return vim.fn.fnamemodify(found, ":h")
		end
	end
	return nil
end

local function try_resolve(path)
	local stat = vim.uv.fs_stat(path)
	if stat and stat.type == "file" then
		return path
	end

	local buf_dir = vim.fn.expand("%:p:h")
	if buf_dir ~= "" then
		local buf_relative = buf_dir .. "/" .. path
		stat = vim.uv.fs_stat(buf_relative)
		if stat and stat.type == "file" then
			return buf_relative
		end

		local repo_root = find_repo_root(buf_dir)
		if repo_root then
			local repo_relative = repo_root .. "/" .. path
			stat = vim.uv.fs_stat(repo_relative)
			if stat and stat.type == "file" then
				return repo_relative
			end
		end
	end
	return nil
end

local function resolve_path(raw)
	local search
	local before, term = raw:match("^(.-):%{(.+)%}$")
	if before then
		raw = before
		search = term
	end

	local path, line, col = raw:match("^(.-)%:(%d+)%:(%d+)$")
	if not path then
		path, line = raw:match("^(.-)%:(%d+)$")
	end
	if not path then
		path = raw
	end

	local expanded = path:gsub("^~", vim.env.HOME)
	local resolved = try_resolve(expanded)
	if not resolved then
		log.debug("rejected (not readable): " .. raw)
		return nil
	end
	log.debug("resolved: " .. raw .. " -> " .. resolved)
	return { path = resolved, line = tonumber(line), col = tonumber(col), search = search }
end

local function get_cache(bufnr)
	local tick = vim.api.nvim_buf_get_changedtick(bufnr)
	local cwd = vim.uv.cwd()
	local c = buf_cache[bufnr]
	if c and c.tick == tick and c.cwd == cwd then
		return c
	end
	c = { tick = tick, cwd = cwd, resolved = {} }
	buf_cache[bufnr] = c
	return c
end

local function scan_viewport(deadline_ms)
	local bufnr = vim.api.nvim_get_current_buf()
	local c = get_cache(bufnr)
	local top = vim.fn.line("w0")
	local bot = vim.fn.line("w$")
	local deadline = vim.uv.hrtime() + deadline_ms * 1e6
	local candidates = {}
	local timed_out = false

	for lnum = top, bot do
		local text = vim.fn.getline(lnum)
		for pos, str in text:gmatch("()(" .. PATH_CHARS .. ")") do
			if is_path_candidate(str) then
				if c.resolved[str] == nil then
					if timed_out or vim.uv.hrtime() > deadline then
						timed_out = true
					else
						c.resolved[str] = resolve_path(str) or false
					end
				end
				local result = c.resolved[str]
				if result then
					table.insert(candidates, {
						path = result.path,
						line = result.line,
						col = result.col,
						search = result.search,
						lnum = lnum,
						col_start = pos - 1,
					})
				end
			end
		end
	end

	log.debug("scan: " .. #candidates .. " candidates, timed_out=" .. tostring(timed_out))
	return candidates
end

local function open_target(target)
	log.debug("opening: " .. target.path)
	vim.cmd("edit " .. vim.fn.fnameescape(target.path))
	if target.search then
		vim.fn.search(target.search, "cw")
	elseif target.line then
		vim.api.nvim_win_set_cursor(0, { target.line, (target.col or 1) - 1 })
	end
end

local M = {}

function M.pick()
	local candidates = scan_viewport(opts.interactive_deadline_ms)

	if #candidates == 0 then
		vim.notify("No file paths found in viewport", vim.log.levels.INFO)
		return
	end

	local count = math.min(#candidates, #LABELS)

	for i = 1, count do
		local c = candidates[i]
		local label = LABELS:sub(i, i)
		vim.api.nvim_buf_set_extmark(0, label_ns, c.lnum - 1, c.col_start, {
			virt_text = { { label, LABEL_HL } },
			virt_text_pos = "overlay",
		})
	end

	vim.cmd("redraw")
	local ok, char = pcall(vim.fn.getcharstr)
	vim.api.nvim_buf_clear_namespace(0, label_ns, 0, -1)
	vim.cmd("redraw")

	if not ok then
		return
	end

	local idx = LABELS:find(char, 1, true)
	if not idx or idx > count then
		return
	end

	local target = candidates[idx]
	log.debug("selected: label=" .. char .. " path=" .. target.path)
	open_target(target)
end

function M.setup(user_opts)
	if user_opts then
		opts = vim.tbl_extend("force", opts, user_opts)
	end

	local group = vim.api.nvim_create_augroup("pick_path", { clear = true })
	vim.api.nvim_create_autocmd({ "WinScrolled", "BufEnter" }, {
		group = group,
		callback = function()
			debounce_timer:stop()
			debounce_timer:start(
				opts.debounce_ms,
				0,
				vim.schedule_wrap(function()
					scan_viewport(opts.precompute_deadline_ms)
				end)
			)
		end,
	})
	vim.api.nvim_create_autocmd("BufDelete", {
		group = group,
		callback = function(ev)
			buf_cache[ev.buf] = nil
		end,
	})
end

return M
