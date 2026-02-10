return {
	"rcarriga/nvim-notify",
	event = "VeryLazy",
	config = function()
		local colors = require("colors")
		local notify = require("notify")
		notify.setup({
			stages = "fade",
			timeout = 3000,
			max_height = function()
				return math.floor(vim.o.lines * 0.75)
			end,
			max_width = function()
				return math.floor(vim.o.columns * 0.75)
			end,
			background_colour = colors.background,
		})
		vim.notify = notify

		vim.api.nvim_set_hl(0, "NotifyERRORBorder", { fg = colors.base08 })
		vim.api.nvim_set_hl(0, "NotifyWARNBorder", { fg = colors.base0B })
		vim.api.nvim_set_hl(0, "NotifyINFOBorder", { fg = colors.base0C })
		vim.api.nvim_set_hl(0, "NotifyDEBUGBorder", { fg = colors.base0E })
		vim.api.nvim_set_hl(0, "NotifyTRACEBorder", { fg = colors.base09 })
		vim.api.nvim_set_hl(0, "NotifyERRORIcon", { fg = colors.base08 })
		vim.api.nvim_set_hl(0, "NotifyWARNIcon", { fg = colors.base0B })
		vim.api.nvim_set_hl(0, "NotifyINFOIcon", { fg = colors.base0C })
		vim.api.nvim_set_hl(0, "NotifyDEBUGIcon", { fg = colors.base0E })
		vim.api.nvim_set_hl(0, "NotifyTRACEIcon", { fg = colors.base09 })
		vim.api.nvim_set_hl(0, "NotifyERRORTitle", { fg = colors.base08 })
		vim.api.nvim_set_hl(0, "NotifyWARNTitle", { fg = colors.base0B })
		vim.api.nvim_set_hl(0, "NotifyINFOTitle", { fg = colors.base0C })
		vim.api.nvim_set_hl(0, "NotifyDEBUGTitle", { fg = colors.base0E })
		vim.api.nvim_set_hl(0, "NotifyTRACETitle", { fg = colors.base09 })
	end,
}
