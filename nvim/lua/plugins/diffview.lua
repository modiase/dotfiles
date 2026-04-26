---@diagnostic disable-next-line: undefined-global
local vim = vim

local vcs = require("utils.vcs")

local function get_git_options()
	local options = {
		{ label = "HEAD (uncommitted)", arg = "HEAD" },
		{ label = "HEAD~1 (previous)", arg = "HEAD~1" },
	}

	local merge_base = vim.fn.system("git merge-base HEAD main 2>/dev/null"):gsub("\n", "")
	if merge_base ~= "" then
		local short_sha = merge_base:sub(1, 7)
		table.insert(options, { label = "Merge base (main) - " .. short_sha, arg = merge_base })
	end

	table.insert(options, { label = "main", arg = "main" })
	table.insert(options, { label = "origin/main", arg = "origin/main" })

	return options
end

local function get_citc_options()
	return {
		{ label = ". (uncommitted)", arg = "." },
		{ label = ".^ (previous)", arg = ".^" },
		{ label = "p4base", arg = "p4base" },
		{ label = "p4head", arg = "p4head" },
	}
end

local function get_hg_options()
	return {
		{ label = ". (uncommitted)", arg = "" },
		{ label = ".^ (previous)", arg = ".^" },
	}
end

local loading_win = nil

local function close_loading()
	if loading_win and vim.api.nvim_win_is_valid(loading_win) then
		vim.api.nvim_win_close(loading_win, true)
	end
	loading_win = nil
end

local function pick_base_and_open()
	if next(require("diffview.lib").views) ~= nil then
		vim.cmd("DiffviewClose")
		return
	end

	local options
	if vcs.is_citc() then
		options = get_citc_options()
	elseif vcs.is_hg() then
		options = get_hg_options()
	else
		options = get_git_options()
	end

	local lines = {}
	for i, opt in ipairs(options) do
		table.insert(lines, string.format(" %d. %s", i, opt.label))
	end

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

	local width = 0
	for _, line in ipairs(lines) do
		width = math.max(width, #line)
	end
	width = width + 4

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		row = math.floor((vim.o.lines - #lines - 2) / 2),
		col = math.floor((vim.o.columns - width) / 2),
		width = width,
		height = #lines,
		style = "minimal",
		border = "rounded",
		title = " Select Diff Base ",
		title_pos = "center",
	})

	local function close()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end

	local function select_and_load(opt)
		loading_win = win
		vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { " Loading diff... " })
		vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
		vim.cmd("redraw")
		vim.cmd("DiffviewOpen " .. opt.arg)
	end

	for i, opt in ipairs(options) do
		vim.keymap.set("n", tostring(i), function()
			select_and_load(opt)
		end, { buffer = buf, nowait = true })
	end

	vim.keymap.set("n", "<CR>", function()
		select_and_load(options[1])
	end, { buffer = buf, nowait = true })
	vim.keymap.set("n", "q", close, { buffer = buf, nowait = true })
	vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true })
end

return {
	{
		"sindrets/diffview.nvim",
		cmd = { "DiffviewOpen", "DiffviewFileHistory" },
		config = function()
			local actions = require("diffview.actions")
			vim.opt.fillchars:append({ diff = " " })

			-- git-crypt: committed blobs are encrypted, so `git show <rev>:<path>`
			-- returns binary. Patch GitAdapter to use --textconv, which invokes the
			-- git-crypt diff textconv driver to decrypt blobs before diffing.
			local GitAdapter = require("diffview.vcs.adapters.git").GitAdapter

			local orig_get_show_args = GitAdapter.get_show_args
			function GitAdapter:get_show_args(path, rev)
				local args = orig_get_show_args(self, path, rev)
				for i, v in ipairs(args) do
					if v == "show" then
						table.insert(args, i + 1, "--textconv")
						break
					end
				end
				return args
			end

			local orig_is_binary = GitAdapter.is_binary
			function GitAdapter:is_binary(path, rev)
				-- --textconv decrypts git-crypt blobs, so skip binary check for
				-- files that have a textconv driver configured
				local attr = vim.fn.system("git check-attr diff -- " .. vim.fn.shellescape(path)):gsub("\n", "")
				if attr:match("diff: git%-crypt") then
					return false
				end
				return orig_is_binary(self, path, rev)
			end

			-- :DiffviewOpen HEAD pins left to the resolved SHA (track_head=false), so
			-- subsequent commits/resets don't move the diff base. update_files only
			-- re-resolves HEAD when left.track_head is true. Promote it for the literal
			-- "HEAD" arg so the picker's "HEAD (uncommitted)" option behaves dynamically.
			local orig_parse_revs = GitAdapter.parse_revs
			function GitAdapter:parse_revs(rev_arg, opt)
				local left, right = orig_parse_revs(self, rev_arg, opt)
				if rev_arg == "HEAD" and left then
					left.track_head = true
				end
				return left, right
			end

			local merge_keymaps = {
				["]x"] = actions.next_conflict,
				["[x"] = actions.prev_conflict,
				["gco"] = actions.conflict_choose("ours"),
				["gct"] = actions.conflict_choose("theirs"),
				["gcb"] = actions.conflict_choose("base"),
				["gca"] = actions.conflict_choose("all"),
				["q"] = "<cmd>DiffviewClose<CR>",
			}

			require("diffview").setup({
				enhanced_diff_hl = true,
				merge_tool = {
					layout = "diff3_mixed",
				},
				hooks = {
					view_opened = close_loading,
				},
				keymaps = {
					view = {
						["q"] = "<cmd>DiffviewClose<CR>",
						["gco"] = actions.conflict_choose("ours"),
						["gct"] = actions.conflict_choose("theirs"),
						["gcb"] = actions.conflict_choose("base"),
						["gca"] = actions.conflict_choose("all"),
					},
					diff3 = merge_keymaps,
					diff4 = merge_keymaps,
				},
			})

			local log = require("devlogs").new("diffview-refresh")
			log.info(
				"installed: parse_revs HEAD-track, is_binary git-crypt fix, FocusGained/ShellCmdPost/TermLeave → refresh, fs_event+fs_poll on .git"
			)

			-- :DiffviewRefresh emits via lib.get_current_view(), which only resolves the
			-- view in the *current* tabpage. So firing :DiffviewRefresh from FocusGained
			-- while the user is on a non-Diffview tab no-ops silently. Iterate lib.views
			-- and emit on each view's emitter directly instead.
			local function refresh_all_views(reason)
				local lib = package.loaded["diffview.lib"]
				if not lib or next(lib.views) == nil then
					log.debug(("autocmd %s → no views"):format(reason))
					return
				end
				for i, v in ipairs(lib.views) do
					local cur = v.tabpage == vim.api.nvim_get_current_tabpage()
					if not v.closing:check() then
						v.emitter:emit("refresh_files")
					end
					log.debug(
						("autocmd %s → emit refresh_files view#%d view.tabpage=%s is_cur=%s"):format(
							reason,
							i,
							tostring(v.tabpage),
							tostring(cur)
						)
					)
				end
			end

			local refresh_group = vim.api.nvim_create_augroup("user_diffview_refresh", { clear = true })
			vim.api.nvim_create_autocmd({ "FocusGained", "ShellCmdPost", "TermLeave" }, {
				group = refresh_group,
				callback = function(ev)
					refresh_all_views(ev.event)
				end,
			})

			-- Upstream only polls <git_dir>/index. Add fs_event (inotify/FSEvents) for
			-- low-latency notification on HEAD/MERGE_HEAD/refs, plus an fs_poll backstop
			-- to cover macOS coalescing, inotify overflow, and Linux's non-recursive
			-- fs_event. Watch directories rather than files: git replaces refs via atomic
			-- rename, which invalidates per-file watches but not directory watches.
			local DiffView = require("diffview.scene.views.diff.diff_view").DiffView

			local interesting = {
				HEAD = true,
				MERGE_HEAD = true,
				ORIG_HEAD = true,
				index = true,
				["packed-refs"] = true,
				FETCH_HEAD = true,
			}

			-- Accept top-level state files OR worktrees/<name>/<state-file>. When ctx.dir
			-- is the common gitdir but operations happen in a linked worktree, the relevant
			-- index/HEAD live under .git/worktrees/<name>/, and the recursive watch on .git/
			-- reports them with that subpath as the filename.
			local function is_interesting(filename)
				if not filename then
					return false
				end
				if interesting[filename] then
					return true
				end
				local base = filename:match("^worktrees/[^/]+/([^/]+)$")
				return base ~= nil and interesting[base] == true
			end

			local function trigger_update(view, source)
				local cur = view:is_cur_tabpage()
				log.debug(
					("%s → trigger_update is_cur_tabpage=%s view.tabpage=%s current=%s"):format(
						source,
						tostring(cur),
						tostring(view.tabpage),
						tostring(vim.api.nvim_get_current_tabpage())
					)
				)
				if cur then
					view:update_files()
				end
			end

			-- accept: nil to allow all filenames, or a function(filename) -> bool. The
			-- recursive watch on .git/ fires for every nested change including the
			-- objects/ flood, so a precise filter is essential to avoid spurious refreshes.
			local function start_event(view, path, accept, label)
				local w = vim.loop.new_fs_event()
				local ok, err = pcall(function()
					w:start(
						path,
						{ recursive = true },
						vim.schedule_wrap(function(cb_err, filename)
							if cb_err then
								log.warning(("fs_event %s ERR %s"):format(label, tostring(cb_err)))
								return
							end
							if accept and not accept(filename) then
								return
							end
							trigger_update(view, ("fs_event %s filename=%s"):format(label, tostring(filename)))
						end)
					)
				end)
				if ok then
					table.insert(view._extra_watchers, w)
					log.debug(("fs_event start OK %s %s"):format(label, path))
				else
					log.error(("fs_event start FAIL %s %s %s"):format(label, path, tostring(err)))
				end
			end

			local function start_poll(view, path, label)
				local w = vim.loop.new_fs_poll()
				local ok, err = pcall(function()
					w:start(
						path,
						1000,
						vim.schedule_wrap(function(cb_err)
							if cb_err then
								return
							end
							trigger_update(view, "fs_poll " .. label)
						end)
					)
				end)
				if ok then
					table.insert(view._extra_watchers, w)
					log.debug(("fs_poll start OK %s %s"):format(label, path))
				else
					log.error(("fs_poll start FAIL %s %s %s"):format(label, path, tostring(err)))
				end
			end

			local orig_post_open = DiffView.post_open
			function DiffView:post_open()
				orig_post_open(self)
				local is_git = self.adapter:instanceof(GitAdapter)
				log.debug(
					("post_open called is_git=%s ctx.dir=%s tabpage=%s"):format(
						tostring(is_git),
						tostring(self.adapter.ctx and self.adapter.ctx.dir),
						tostring(self.tabpage)
					)
				)
				if not is_git then
					return
				end
				self._extra_watchers = {}
				local d = self.adapter.ctx.dir

				start_event(self, d, is_interesting, "git_dir")
				start_event(self, d .. "/refs/heads", nil, "refs_heads")

				-- End-of-pipeline confirmation: if we see fs_event/fs_poll → trigger_update
				-- but no files_updated, update_files is short-circuiting (typically the
				-- self.tabpage ~= current_tabpage check, or an internal cancellation).
				self.emitter:on("files_updated", function()
					log.debug("files_updated event fired")
				end)

				start_poll(self, d .. "/HEAD", "HEAD")
				start_poll(self, d .. "/MERGE_HEAD", "MERGE_HEAD")

				-- Resolve the current branch's ref file once. If the user switches
				-- branches mid-view, the HEAD watcher fires a refresh; the now-stale
				-- ref-file poll is harmless until close.
				local hf = io.open(d .. "/HEAD", "r")
				if hf then
					local content = hf:read("*a") or ""
					hf:close()
					local ref = content:match("^ref:%s*(%S+)")
					if ref then
						start_poll(self, d .. "/" .. ref, "ref:" .. ref)
					else
						log.debug("post_open detached HEAD, no ref watcher")
					end
				end
			end

			local orig_close = DiffView.close
			function DiffView:close()
				log.debug(
					("close called, stopping %d extra watchers"):format(
						self._extra_watchers and #self._extra_watchers or 0
					)
				)
				for _, w in ipairs(self._extra_watchers or {}) do
					pcall(function()
						w:stop()
						w:close()
					end)
				end
				self._extra_watchers = nil
				orig_close(self)
			end
		end,
		keys = {
			{ "<leader>gd", pick_base_and_open, desc = "Diffview (pick base)" },
			{ "<leader>gh", "<cmd>DiffviewFileHistory<CR>", desc = "File History" },
			{ "<leader>gr", "<cmd>DiffviewRefresh<CR>", desc = "Refresh Diffview" },
		},
	},
}
