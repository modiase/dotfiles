return {
	"vim-airline/vim-airline",
	dependencies = {
		"vim-airline/vim-airline-themes",
	},
	event = "VeryLazy",
	config = function()
		vim.g.airline_theme = "luna"
	end,
}
