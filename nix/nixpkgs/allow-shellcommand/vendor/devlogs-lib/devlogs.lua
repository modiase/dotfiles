local M = {}

local window = ""
local pane = vim.env.TMUX_PANE
if pane then
	local out = vim.fn.system({ "tmux", "display-message", "-t", pane, "-p", "#{window_index}" })
	if vim.v.shell_error == 0 then
		window = vim.trim(out)
	end
end

local function log(level, component, instance, msg)
	local tag = component .. "{" .. instance .. "}"
	if window ~= "" then
		tag = tag .. "(@" .. window .. ")"
	end
	local formatted = ("[devlogs] %s %s: %s"):format(level:upper(), tag, msg)
	-- all levels use user.info; macOS unified logging drops user.debug from history
	vim.fn.system({ "logger", "-t", "devlogs", "-p", "user.info", formatted })
end

function M.new(component)
	component = component or vim.env.DEVLOGS_COMPONENT or "unknown"
	local instance = vim.env.DEVLOGS_INSTANCE or "-"
	local logger = {}
	for _, level in ipairs({ "debug", "info", "warning", "error" }) do
		logger[level] = function(msg)
			log(level, component, instance, msg)
		end
	end
	return logger
end

return M
