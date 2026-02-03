return {
	"3rd/image.nvim",
	event = "VeryLazy",
	build = false,
	opts = {
		max_width = 100,
		max_height = 12,
		max_height_window_percentage = math.huge,
		max_width_window_percentage = math.huge,
		window_overlap_clear_enabled = true,
		tmux_show_only_in_active_window = true,
	},
	config = function(_, opts)
		local image = require("image")
		image.setup(opts)

		local extensions = { "png", "jpg", "jpeg", "gif", "webp", "avif" }
		vim.api.nvim_create_autocmd("BufReadCmd", {
			pattern = vim.tbl_map(function(ext)
				return "*." .. ext
			end, extensions),
			callback = function(ev)
				vim.bo[ev.buf].buftype = "nofile"
				local img = image.from_file(ev.file)
				if img then
					img:render()
				end
			end,
		})
	end,
}
