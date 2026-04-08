local View = require("noice.view")
local log = require("devlogs").new("nvim-notify")

local notify_level_map = {
	error = log.error,
	warn = log.warning,
}

local msg_show_kind_map = {
	lua_error = log.error,
	rpc_error = log.error,
}

local promotions = {
	{ pattern = "written$", fn = log.info },
}

---@class DevlogsView: NoiceView
---@field super NoiceView
---@diagnostic disable-next-line: undefined-field
local DevlogsView = View:extend("DevlogsView")

function DevlogsView:show()
	for _, m in ipairs(self._messages) do
		local content = m:content()
		local fn = m.level and notify_level_map[m.level]
		if not fn and m.kind and m.kind ~= "" then
			fn = msg_show_kind_map[m.kind]
		end
		if not fn then
			for _, p in ipairs(promotions) do
				if content:find(p.pattern) then
					fn = p.fn
					break
				end
			end
		end
		(fn or log.debug)(content)
	end
	self:clear()
end

function DevlogsView:hide() end

return DevlogsView
