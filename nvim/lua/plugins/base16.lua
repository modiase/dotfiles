return {
	"RRethy/base16-nvim",
	lazy = false,
	priority = 1000,
	config = function()
		require("base16-colorscheme").setup({
			base00 = "#1c1c1c",
			base01 = "#2a2a2a",
			base02 = "#3a3a3a",
			base03 = "#707070",
			base04 = "#909090",
			base05 = "#e0e0e0",
			base06 = "#f0f0f0",
			base07 = "#ffffff",
			base08 = "#d08080",
			base09 = "#a8c99a",
			base0A = "#f4b6c2",
			base0B = "#d8d0b8",
			base0C = "#a8d8ea",
			base0D = "#8fa8c9",
			base0E = "#c9a8c9",
			base0F = "#d08080",
		})
	end,
}
