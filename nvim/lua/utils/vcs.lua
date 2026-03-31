local M = {}

function M.is_citc()
	return vim.fn.getcwd():match("^/google/src/cloud/") ~= nil
end

function M.is_hg()
	return vim.fn.system("hg root 2>/dev/null"):find("^/") ~= nil
end

return M
