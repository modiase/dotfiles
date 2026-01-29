return {
	"glepnir/dashboard-nvim",
	config = function()
		local db = require("dashboard")

		db.setup({
			theme = "hyper",
		})
	end,
}
