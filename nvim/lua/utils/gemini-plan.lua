local M = {}
local log = require("devlogs").new("gemini-plan")
local comments = require("utils.plan-comments")

local ns = vim.api.nvim_create_namespace("gemini_plan_comments")

local function find_win_by_fifo(fifo_path)
	for _, t in ipairs(vim.api.nvim_list_tabpages()) do
		local win = vim.api.nvim_tabpage_get_win(t)
		if vim.w[win].plan_fifo == fifo_path then
			return win, t
		end
	end
	return nil, nil
end

local function buf_has_other_plan_wins(buf, exclude_win)
	for _, w in ipairs(vim.api.nvim_list_wins()) do
		if w ~= exclude_win and vim.api.nvim_win_get_buf(w) == buf and vim.w[w].plan_fifo then
			return true
		end
	end
	return false
end

local function close_plan_tab(buf, win)
	if buf_has_other_plan_wins(buf, win) then
		if #vim.api.nvim_list_tabpages() > 1 then
			vim.cmd("tabclose")
		end
	elseif vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_delete(buf, { force = true })
	end
end

function M.close_by_fifo(fifo_path)
	local win, tab = find_win_by_fifo(fifo_path)
	if not win then
		log.debug("close_by_fifo: no win for fifo=" .. tostring(fifo_path))
		return
	end

	local buf = vim.api.nvim_win_get_buf(win)
	log.debug("close_by_fifo: buf=" .. buf .. " tab=" .. tostring(tab))

	comments.serialise_comments(buf, ns)

	vim.api.nvim_set_current_tabpage(tab)
	close_plan_tab(buf, win)
end

function M.close()
	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_win_get_buf(win)
	if not vim.b[buf].plan_provider then
		log.debug("close: not a plan buffer")
		return
	end
	log.info("close: buf=" .. buf)

	comments.serialise_comments(buf, ns)
	close_plan_tab(buf, win)
end

function M.accept_auto()
	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_win_get_buf(win)
	log.info("accept_auto")
	comments.serialise_comments(buf, ns)
	comments.write_fifo(vim.w[win].plan_fifo, "accept_auto")
	vim.notify("Plan accepted", vim.log.levels.INFO)
end

function M.accept_manual()
	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_win_get_buf(win)
	log.info("accept_manual")
	comments.serialise_comments(buf, ns)
	comments.write_fifo(vim.w[win].plan_fifo, "accept_manual")
	vim.notify("Plan accepted", vim.log.levels.INFO)
end

function M.reject()
	local buf = vim.api.nvim_get_current_buf()
	local fifo = vim.w[vim.api.nvim_get_current_win()].plan_fifo
	local has_comments = #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) > 0

	local function do_reject(reason)
		M.close()
		comments.write_fifo(fifo, "reject:" .. reason)
	end

	if has_comments then
		vim.ui.input({ prompt = "Additional comment (optional): " }, function(input)
			if not input then
				return
			end
			local reason = "Please address all comments in the plan"
			if input ~= "" then
				reason = reason .. "\n\n" .. input
			end
			do_reject(reason)
		end)
		return
	end

	vim.ui.input({ prompt = "Rejection reason: " }, function(input)
		if not input then
			return
		end
		do_reject(input)
	end)
end

function M.open(file_path, fifo_path)
	if not file_path or not fifo_path then
		return
	end
	log.info("open file=" .. file_path .. " fifo=" .. fifo_path)

	local _, existing_tab = find_win_by_fifo(fifo_path)
	if existing_tab then
		vim.api.nvim_set_current_tabpage(existing_tab)
		return
	end

	vim.cmd("tabnew " .. vim.fn.fnameescape(file_path))
	M.setup_buffer(fifo_path)
end

function M.setup_buffer(fifo_path)
	local win = vim.api.nvim_get_current_win()
	vim.w[win].plan_fifo = fifo_path

	local buf = vim.api.nvim_get_current_buf()
	if vim.b[buf].gemini_plan_setup then
		log.info("setup_buffer: reused buf=" .. buf .. " new win fifo=" .. tostring(fifo_path))
		return
	end
	vim.b[buf].gemini_plan_setup = true
	vim.b[buf].plan_provider = "gemini"
	log.info("setup_buffer buf=" .. buf .. " fifo=" .. tostring(fifo_path))

	local ok, count = pcall(comments.deserialise, buf, ns)
	if ok then
		log.debug("setup_buffer: deserialised " .. count .. " comments")
	else
		log.error("setup_buffer: deserialise failed: " .. tostring(count))
	end

	vim.bo[buf].modifiable = false
	vim.bo[buf].readonly = true
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

	comments.setup_keymaps(buf, ns)

	for _, key in ipairs({ "i", "I", "A", "o", "O", "s", "S", "r", "R" }) do
		vim.keymap.set("n", key, "<Nop>", { buffer = buf })
	end
end

return M
