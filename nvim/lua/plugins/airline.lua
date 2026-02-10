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
		vim.api.nvim_create_autocmd("VimEnter", {
			callback = function()
				local palette = vim.g["airline#themes#base16#palette"]
				if palette then
					palette.tabline = {
						airline_tab = { colors.base04, colors.base01, 245, 235, "" },
						airline_tabsel = { colors.foreground, colors.base02, 254, 237, "bold" },
						airline_tabfill = { colors.base03, colors.base00, 243, 234, "" },
					}
					vim.g["airline#themes#base16#palette"] = palette
					vim.cmd("AirlineRefresh")
				end
			end,
		})
	end,
}
