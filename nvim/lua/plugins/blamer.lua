function GitBlameCp()
	vim.api.nvim_exec("GitBlameCopySHA", true)
	print(vim.fn.getreg("+"))
end

return {
	"f-person/git-blame.nvim",
	event = "VeryLazy",
	config = function()
		vim.api.nvim_set_keymap("n", "gcs", ":lua GitBlameCp()<CR>", { noremap = true })
	end,
}
