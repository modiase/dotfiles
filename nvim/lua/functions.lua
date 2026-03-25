---@diagnostic disable-next-line: undefined-global
local vim = vim

local function syn_stack()
	local line = vim.fn.line(".")
	local col = vim.fn.col(".")

	for _, id1 in ipairs(vim.fn.synstack(line, col)) do
		local id2 = vim.fn.synIDtrans(id1)
		local name1 = vim.fn.synIDattr(id1, "name")
		local name2 = vim.fn.synIDattr(id2, "name")
		print(name1 .. " -> " .. name2)
	end
end

vim.keymap.set("n", "gm", syn_stack, { silent = true })
