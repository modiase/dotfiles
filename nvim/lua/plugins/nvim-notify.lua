return {
	"rcarriga/nvim-notify",
	event = "VeryLazy",
	opts = {
		stages = "fade",
		timeout = 3000,
		max_height = function()
			return math.floor(vim.o.lines * 0.75)
		end,
		max_width = function()
			return math.floor(vim.o.columns * 0.75)
		end,
		background_colour = "#1c1c1c",
	},
	config = function(_, opts)
		local notify = require("notify")
		notify.setup(opts)
		vim.notify = notify

		vim.api.nvim_set_hl(0, "NotifyERRORBorder", { fg = "#d08080" })
		vim.api.nvim_set_hl(0, "NotifyWARNBorder", { fg = "#d8d0b8" })
		vim.api.nvim_set_hl(0, "NotifyINFOBorder", { fg = "#a8d8ea" })
		vim.api.nvim_set_hl(0, "NotifyDEBUGBorder", { fg = "#c9a8c9" })
		vim.api.nvim_set_hl(0, "NotifyTRACEBorder", { fg = "#a8c99a" })
		vim.api.nvim_set_hl(0, "NotifyERRORIcon", { fg = "#d08080" })
		vim.api.nvim_set_hl(0, "NotifyWARNIcon", { fg = "#d8d0b8" })
		vim.api.nvim_set_hl(0, "NotifyINFOIcon", { fg = "#a8d8ea" })
		vim.api.nvim_set_hl(0, "NotifyDEBUGIcon", { fg = "#c9a8c9" })
		vim.api.nvim_set_hl(0, "NotifyTRACEIcon", { fg = "#a8c99a" })
		vim.api.nvim_set_hl(0, "NotifyERRORTitle", { fg = "#d08080" })
		vim.api.nvim_set_hl(0, "NotifyWARNTitle", { fg = "#d8d0b8" })
		vim.api.nvim_set_hl(0, "NotifyINFOTitle", { fg = "#a8d8ea" })
		vim.api.nvim_set_hl(0, "NotifyDEBUGTitle", { fg = "#c9a8c9" })
		vim.api.nvim_set_hl(0, "NotifyTRACETitle", { fg = "#a8c99a" })
	end,
}
