return {
	name = "copy-path",
	dir = vim.fn.stdpath("config") .. "/my-plugins/copy-path",
	keys = {
		{
			"cp",
			function()
				require("copy-path").absolute()
			end,
			desc = "Copy absolute file path",
		},
		{
			"gcp",
			function()
				require("copy-path").git_relative()
			end,
			desc = "Copy git-relative file path",
		},
	},
}
