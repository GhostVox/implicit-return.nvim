-- implicit_return.lua
-- Highlights implicit return expressions in Rust
-- Place in ~/.config/nvim/lua/custom/implicit_return.lua
if not pcall(require, "nvim-treesitter") then
	vim.notify("implicit-return.nvim requires nvim-treesitter", vim.log.levels.WARN)
	return
end
local M = {}

local ns = vim.api.nvim_create_namespace("implicit_return")

-- Forward declaration
local get_implicit_returns

-- Get the last named child of a block that isn't semicolon-terminated
local function last_expr(block)
	local count = block:named_child_count()
	if count == 0 then
		return nil
	end
	local last = block:named_child(count - 1)
	if not last then
		return nil
	end
	if last:type() == "expression_statement" then
		local lc = last:child(last:child_count() - 1)
		if lc and lc:type() == ";" then
			return nil
		end
	end
	return last
end

get_implicit_returns = function(node, results)
	local t = node:type()

	-- match expression: recurse into each match arm's body
	if t == "match_expression" then
		for i = 0, node:named_child_count() - 1 do
			local child = node:named_child(i)
			if child:type() == "match_block" then
				for j = 0, child:named_child_count() - 1 do
					local arm = child:named_child(j)
					if arm:type() == "match_arm" then
						-- last named child of match_arm is the body
						local body = arm:named_child(arm:named_child_count() - 1)
						if body then
							get_implicit_returns(body, results)
						end
					end
				end
			end
		end
		return
	end

	-- if expression: recurse into consequence and alternative blocks
	if t == "if_expression" then
		for i = 0, node:named_child_count() - 1 do
			local child = node:named_child(i)
			if child:type() == "block" or child:type() == "else_clause" or child:type() == "if_expression" then
				get_implicit_returns(child, results)
			end
		end
		return
	end

	-- else clause: recurse into its block or if_expression
	if t == "else_clause" then
		for i = 0, node:named_child_count() - 1 do
			local child = node:named_child(i)
			get_implicit_returns(child, results)
		end
		return
	end

	-- block: get its last expression and recurse if needed
	if t == "block" then
		local expr = last_expr(node)
		if expr then
			get_implicit_returns(expr, results)
		end
		return
	end

	-- unwrap expression_statement and recurse
	if t == "expression_statement" then
		local child = node:named_child(0)
		if child then
			get_implicit_returns(child, results)
		end
		return
	end

	-- anything else is a leaf implicit return — highlight it
	table.insert(results, node)
end

local function find_function_blocks(node, results)
	local t = node:type()

	if t == "function_item" or t == "closure_expression" then
		for i = 0, node:child_count() - 1 do
			local child = node:child(i)
			if child:type() == "block" then
				local expr = last_expr(child)
				if expr then
					get_implicit_returns(expr, results)
				end
				break
			end
		end
	end

	for i = 0, node:child_count() - 1 do
		find_function_blocks(node:child(i), results)
	end
end

local function apply_highlights(bufnr)
	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "rust")
	if not ok or not parser then
		return
	end

	local tree = parser:parse()[1]
	if not tree then
		return
	end

	local root = tree:root()
	local results = {}
	find_function_blocks(root, results)

	for _, node in ipairs(results) do
		local sr, sc, er, ec = node:range()
		vim.api.nvim_buf_set_extmark(bufnr, ns, sr, sc, {
			end_row = er,
			end_col = ec,
			hl_group = "ImplicitReturn",
		})
	end
end

local function setup_hl()
	-- Try to read sp or fg from @keyword.return
	local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = "@keyword.return", link = false })
	local color = (ok and hl and (hl.sp or hl.fg)) or "#F77FBE" -- fallback to pink

	vim.api.nvim_set_hl(0, "ImplicitReturn", {
		sp = color,
		underline = true,
	})
end
function M.setup(opts)
	opts = opts or {}
	setup_hl()

	if opts.hl then
		vim.api.nvim_set_hl(0, "ImplicitReturn", opts.hl)
	end

	local group = vim.api.nvim_create_augroup("ImplicitReturn", { clear = true })

	vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "TextChanged", "TextChangedI" }, {
		group = group,
		pattern = "*.rs",
		callback = function(ev)
			apply_highlights(ev.buf)
		end,
	})

	vim.api.nvim_create_autocmd("ColorScheme", {
		group = group,
		callback = setup_hl,
	})

	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(bufnr) then
			local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
			if ft == "rust" then
				apply_highlights(bufnr)
			end
		end
	end
end

return M
