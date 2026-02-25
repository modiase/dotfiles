local parsers = {
	"angular",
	"bash",
	"css",
	"fish",
	"go",
	"html",
	"json",
	"lua",
	"markdown",
	"markdown_inline",
	"nix",
	"python",
	"query",
	"scss",
	"svelte",
	"terraform",
	"typescript",
	"vim",
	"vimdoc",
	"yaml",
}

return {
	"nvim-treesitter/nvim-treesitter",
	build = function()
		require("nvim-treesitter").install(parsers)
	end,
	config = function()
		require("nvim-treesitter").install(parsers)
		vim.api.nvim_create_autocmd("FileType", {
			pattern = "*",
			callback = function()
				pcall(vim.treesitter.start)
			end,
		})
	end,
}
