return {
	"vim-airline/vim-airline",
	dependencies = {
		"vim-airline/vim-airline-themes",
	},
	event = "VeryLazy",
	init = function()
		vim.g.airline_theme = "deus"
		vim.g["airline#extensions#tabline#enabled"] = 1
		vim.g["airline#extensions#tabline#formatter"] = "unique_tail"
	end,
}
