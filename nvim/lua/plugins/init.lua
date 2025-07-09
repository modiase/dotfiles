local plugins = {}

local function scan_dir(directory)
  local pfile = io.popen('ls -1 "' .. directory .. '"')
  if not pfile then return {} end
  
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
  local ok, plugin_spec = pcall(require, "plugins." .. plugin_name)
  if ok and plugin_spec then
    table.insert(plugins, plugin_spec)
  end
end

return plugins
