local View = require("noice.view")
local log = require("devlogs").new("nvim-notify")

local level_map = {
	error = log.error,
	warn = log.warning,
	info = log.info,
	debug = log.debug,
	trace = log.debug,
}

---@class DevlogsView: NoiceView
---@field super NoiceView
---@diagnostic disable-next-line: undefined-field
local DevlogsView = View:extend("DevlogsView")

function DevlogsView:show()
	for _, m in ipairs(self._messages) do
		local fn = level_map[m.level] or log.info
		fn(m:content())
	end
	self:clear()
end

function DevlogsView:hide() end

return DevlogsView
