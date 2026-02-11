return {
	"vim-airline/vim-airline",
	dependencies = {
		"vim-airline/vim-airline-themes",
	},
	event = "VeryLazy",
	init = function()
		vim.g.airline_theme = "base16"
		vim.g["airline#extensions#tabline#enabled"] = 1
		vim.g["airline#extensions#tabline#formatter"] = "unique_tail"
	end,
	config = function()
		local colors = require("colors")
		vim.api.nvim_set_hl(0, "airline_tab", { fg = colors.base04, bg = colors.base01 })
	end,
}
