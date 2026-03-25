return {
	name = "pick-buffer",
	dir = vim.fn.stdpath("config") .. "/my-plugins/pick-buffer",
	keys = {
		{
			"gb",
			function()
				require("pick-buffer").pick()
			end,
			desc = "Pick buffer",
		},
	},
}
