local plugins = {}

local ok, enabled_plugins = pcall(require, "enabled-plugins")
if not ok then
	enabled_plugins = {}
end

local pager_plugins = {
	["base16"] = true,
	["treesitter"] = true,
	["airline"] = true,
	["nvim-web-devicons"] = true,
	["neoscroll"] = true,
	["tmux"] = true,
	["render-markdown"] = true,
	["noice"] = true,
	["nvim-notify"] = true,
}

local function scan_dir(directory)
	local pfile = io.popen('ls -1 "' .. directory .. '"')
	if not pfile then
		return {}
	end

	local files = {}
	for filename in pfile:lines() do
		if filename:match("%.lua$") and filename ~= "init.lua" then
			local name = filename:gsub("%.lua$", "")
			table.insert(files, name)
		end
	end
	pfile:close()
	return files
end

local plugin_dir = vim.fn.stdpath("config") .. "/lua/plugins"
local plugin_files = scan_dir(plugin_dir)

for _, plugin_name in ipairs(plugin_files) do
	if enabled_plugins[plugin_name] and (not vim.g.pager_mode or pager_plugins[plugin_name]) then
		local ok_req, plugin_spec = pcall(require, "plugins." .. plugin_name)
		if ok_req and plugin_spec then
			table.insert(plugins, plugin_spec)
		end
	end
end

return plugins
