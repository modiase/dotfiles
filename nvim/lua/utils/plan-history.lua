local M = {}

local MAX_ENTRIES = 100
local MAX_AGE_DAYS = 90

local history_path = vim.fn.stdpath("data") .. "/plan-history.json"

local function plans_dir()
	local config = os.getenv("CLAUDE_CONFIG_DIR") or (os.getenv("HOME") .. "/.claude")
	return vim.fn.resolve(config) .. "/plans"
end

local function load()
	local f = io.open(history_path, "r")
	if not f then
		return {}
	end
	local raw = f:read("*a")
	f:close()

	local ok, entries = pcall(vim.json.decode, raw)
	if not ok or type(entries) ~= "table" then
		return {}
	end

	local cutoff = os.time() - (MAX_AGE_DAYS * 86400)
	local pruned = {}
	for _, e in ipairs(entries) do
		if e.last_opened and e.last_opened >= cutoff then
			pruned[#pruned + 1] = e
		end
	end

	if #pruned > MAX_ENTRIES then
		local trimmed = {}
		for i = 1, MAX_ENTRIES do
			trimmed[i] = pruned[i]
		end
		pruned = trimmed
	end

	return pruned
end

local function save(entries)
	table.sort(entries, function(a, b)
		return a.last_opened > b.last_opened
	end)

	local f = io.open(history_path, "w")
	if not f then
		return
	end
	f:write(vim.json.encode(entries))
	f:close()
end

local function extract_title(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	for line in f:lines() do
		local title = line:match("^#%s+(.+)")
		if title then
			f:close()
			return title
		end
	end
	f:close()
	return nil
end

function M.record(filepath)
	filepath = vim.fn.resolve(filepath)
	local entries = load()
	local now = os.time()
	local title = extract_title(filepath) or vim.fn.fnamemodify(filepath, ":t:r")

	for _, e in ipairs(entries) do
		if e.path == filepath then
			e.last_opened = now
			e.title = title
			save(entries)
			return
		end
	end

	entries[#entries + 1] = {
		path = filepath,
		title = title,
		first_opened = now,
		last_opened = now,
	}
	save(entries)
end

local function relative_time(epoch)
	local diff = os.time() - epoch
	if diff < 60 then
		return "now"
	end
	if diff < 3600 then
		return math.floor(diff / 60) .. "m ago"
	end
	if diff < 86400 then
		return math.floor(diff / 3600) .. "h ago"
	end
	return math.floor(diff / 86400) .. "d ago"
end

function M.picker()
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local entry_display = require("telescope.pickers.entry_display")

	local entries = load()
	if #entries == 0 then
		vim.notify("No plan history", vim.log.levels.INFO)
		return
	end

	local displayer = entry_display.create({
		separator = "  ",
		items = {
			{ remaining = true },
			{ width = 8 },
			{ remaining = true },
		},
	})

	pickers
		.new({}, {
			prompt_title = "Plan History",
			finder = finders.new_table({
				results = entries,
				entry_maker = function(entry)
					local filename = vim.fn.fnamemodify(entry.path, ":t:r")
					return {
						value = entry,
						display = function()
							return displayer({
								entry.title,
								relative_time(entry.last_opened),
								filename,
							})
						end,
						ordinal = entry.title .. " " .. filename,
						filename = entry.path,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			previewer = conf.file_previewer({}),
			attach_mappings = function(prompt_bufnr)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local selection = action_state.get_selected_entry()
					if selection then
						vim.cmd("tabnew " .. vim.fn.fnameescape(selection.value.path))
					end
				end)
				return true
			end,
		})
		:find()
end

function M.setup()
	vim.api.nvim_create_autocmd("BufRead", {
		pattern = plans_dir() .. "/*.md",
		callback = function(ev)
			M.record(ev.match)
		end,
	})
end

return M
