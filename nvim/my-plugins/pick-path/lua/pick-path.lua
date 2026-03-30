local log = require("devlogs").new("pick-path")
local LABELS = "asdfghjklASDFGHJKLqwertyuiopQWERTYUIOPzxcvbnmZXCVBNM1234567890"
local PATH_PATTERN = [[\v[~.]?/?[a-zA-Z0-9_.@-]+(/[a-zA-Z0-9_.@-]+)+(:[0-9]+){,2}(:\{[^}]+\})?]]
local LABEL_HL = "PickPathLabel"

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
	if vim.fn.filereadable(expanded) ~= 1 then
		log.debug("rejected (not readable): " .. raw)
		return nil
	end
	log.debug("resolved: " .. raw .. " -> " .. expanded)
	return { path = expanded, line = tonumber(line), col = tonumber(col), search = search }
end

local M = {}

function M.pick()
	local top = vim.fn.line("w0")
	local bot = vim.fn.line("w$")
	log.debug("viewport scan: lines " .. top .. "-" .. bot)
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
				local detail = "candidate: path=" .. resolved.path .. " line=" .. lnum .. " col=" .. s
				if resolved.search then
					detail = detail .. " search=" .. resolved.search
				end
				log.debug(detail)
				table.insert(candidates, resolved)
			end
			start = e
		end
	end

	log.debug("total candidates: " .. #candidates)

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
			virt_text = { { label, LABEL_HL } },
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
	log.debug("selected: label=" .. char .. " path=" .. target.path)
	vim.cmd("edit " .. vim.fn.fnameescape(target.path))
	if target.search then
		vim.fn.search(target.search, "cw")
	elseif target.line then
		vim.api.nvim_win_set_cursor(0, { target.line, (target.col or 1) - 1 })
	end
end

return M
