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
		background_colour = "#2e3440",
	},
	config = function(_, opts)
		local notify = require("notify")
		notify.setup(opts)
		vim.notify = notify

		-- Nord-themed highlight overrides
		vim.api.nvim_set_hl(0, "NotifyERRORBorder", { fg = "#bf616a" })
		vim.api.nvim_set_hl(0, "NotifyWARNBorder", { fg = "#ebcb8b" })
		vim.api.nvim_set_hl(0, "NotifyINFOBorder", { fg = "#88c0d0" })
		vim.api.nvim_set_hl(0, "NotifyDEBUGBorder", { fg = "#b48ead" })
		vim.api.nvim_set_hl(0, "NotifyTRACEBorder", { fg = "#a3be8c" })
		vim.api.nvim_set_hl(0, "NotifyERRORIcon", { fg = "#bf616a" })
		vim.api.nvim_set_hl(0, "NotifyWARNIcon", { fg = "#ebcb8b" })
		vim.api.nvim_set_hl(0, "NotifyINFOIcon", { fg = "#88c0d0" })
		vim.api.nvim_set_hl(0, "NotifyDEBUGIcon", { fg = "#b48ead" })
		vim.api.nvim_set_hl(0, "NotifyTRACEIcon", { fg = "#a3be8c" })
		vim.api.nvim_set_hl(0, "NotifyERRORTitle", { fg = "#bf616a" })
		vim.api.nvim_set_hl(0, "NotifyWARNTitle", { fg = "#ebcb8b" })
		vim.api.nvim_set_hl(0, "NotifyINFOTitle", { fg = "#88c0d0" })
		vim.api.nvim_set_hl(0, "NotifyDEBUGTitle", { fg = "#b48ead" })
		vim.api.nvim_set_hl(0, "NotifyTRACETitle", { fg = "#a3be8c" })
	end,
}
