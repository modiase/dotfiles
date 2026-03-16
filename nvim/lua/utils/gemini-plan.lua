local M = {}
local log = require("devlogs").new("gemini-plan")

function M.setup_buffer()
	local buf = vim.api.nvim_get_current_buf()
	log.info("setup_buffer buf=" .. buf)

	vim.bo[buf].modifiable = false
	vim.bo[buf].readonly = true
	vim.bo[buf].bufhidden = "delete"

	local opts = { buffer = buf, nowait = true }
	vim.keymap.set("n", "q", "<cmd>bd!<CR>", vim.tbl_extend("force", opts, { desc = "Close plan (accept)" }))

	for _, key in ipairs({ "i", "I", "A", "o", "O", "s", "S", "c", "C", "r", "R" }) do
		vim.keymap.set("n", key, "<Nop>", { buffer = buf })
	end
end

return M
