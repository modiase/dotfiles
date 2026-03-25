local colors = require("colors")

return {
	name = "pick-path",
	dir = vim.fn.stdpath("config") .. "/my-plugins/pick-path",
	keys = {
		{
			"gp",
			function()
				require("pick-path").pick()
			end,
			desc = "Pick path in viewport",
		},
	},
	config = function()
		vim.api.nvim_set_hl(0, "PickPathLabel", { fg = colors.base00, bg = colors.base0B, bold = true })
	end,
}
