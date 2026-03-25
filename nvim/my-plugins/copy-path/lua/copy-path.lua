local M = {}

function M.absolute()
	local abs_path = vim.fn.expand("%:p")
	print(abs_path)
	vim.fn.setreg("+", abs_path, "c")
end

function M.git_relative()
	local file_path = vim.fn.expand("%:p")
	local dir_path = vim.fn.fnamemodify(file_path, ":h")

	while dir_path ~= "/" and dir_path ~= "." do
		if vim.fn.isdirectory(dir_path .. "/.git") == 1 then
			local relative_path = vim.fn.fnamemodify(file_path, ":.")
			print(relative_path)
			vim.fn.setreg("+", relative_path, "c")
			return
		end
		dir_path = vim.fn.fnamemodify(dir_path, ":h")
	end

	print("No git directory found in hierarchy")
end

return M
