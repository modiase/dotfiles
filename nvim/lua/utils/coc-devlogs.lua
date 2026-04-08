local log = require("devlogs").new("coc")

local M = {}

function M.setup()
	local group = vim.api.nvim_create_augroup("coc_devlogs", {})

	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "CocNvimInit",
		callback = function()
			log.info("coc initialised")
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "CocStatusChange",
		callback = function()
			local status = vim.g.coc_status or ""
			if status == "" then
				return
			end
			log.debug(status)
		end,
	})
end

return M
