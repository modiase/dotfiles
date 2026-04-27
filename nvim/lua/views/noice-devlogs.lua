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

-- emsg is a broad bucket: noice tags every emsg with level="error", but most
-- are routine cmdline feedback (search misses, typos, write errors). Only
-- promote patterns we know to be real bugs; everything else falls to debug.
local emsg_real_bug_patterns = {
	"^Error in[: ]", -- nvim >=0.12 autocmd/function/script error chain
	"^Error detected while processing", -- nvim <0.12 wording
	"^Lua:", -- nvim >=0.12 Lua error via emsg
	"^Error executing [Ll]ua", -- nvim <0.12 wording
	"^E5%d%d%d", -- E5xxx series (Lua / treesitter / internal)
	"stack traceback:", -- embedded Lua stacktrace
}

local content_promotions = {
	{ pattern = "written$", fn = log.info },
}

---@class DevlogsView: NoiceView
---@field super NoiceView
---@diagnostic disable-next-line: undefined-field
local DevlogsView = View:extend("DevlogsView")

local function classify_emsg(content)
	for _, p in ipairs(emsg_real_bug_patterns) do
		if content:find(p) then
			return log.error
		end
	end
	return nil
end

function DevlogsView:show()
	for _, m in ipairs(self._messages) do
		local content = m:content()
		local fn
		if m.event == "notify" then
			fn = m.level and notify_level_map[m.level]
		elseif m.kind and m.kind ~= "" then
			fn = msg_show_kind_map[m.kind]
			if not fn and m.kind == "emsg" then
				fn = classify_emsg(content)
			end
		end
		if not fn then
			for _, p in ipairs(content_promotions) do
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
