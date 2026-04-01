local View = require("noice.view")
local log = require("devlogs").new("nvim-notify")

local notify_level_map = {
	error = log.error,
	warn = log.warning,
	info = log.info,
	debug = log.debug,
	trace = log.debug,
}

local msg_show_kind_map = {
	emsg = log.error,
	echoerr = log.error,
	lua_error = log.error,
	rpc_error = log.error,
	wmsg = log.warning,
}

---@class DevlogsView: NoiceView
---@field super NoiceView
---@diagnostic disable-next-line: undefined-field
local DevlogsView = View:extend("DevlogsView")

function DevlogsView:show()
	for _, m in ipairs(self._messages) do
		local fn = notify_level_map[m.level] or msg_show_kind_map[m.kind] or log.info
		fn(m:content())
	end
	self:clear()
end

function DevlogsView:hide() end

return DevlogsView
