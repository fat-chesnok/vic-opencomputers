local computer = require('computer')
local term = require('term')
local shell = require('shell')
local fs = require('filesystem')
local unicode = require('unicode')
local text = require('text')
local keyboard = require('keyboard')
local env = os.getenv()
local gpu = term.gpu()
vic = {
    BG_COLOR=0x1E1E1E,
    LINE_COLOR=0x4B4B4B,
    THEME=nil,
    keymap={},
    keyfuncs={},
    commands={}
}

local MODE = 'NORMAL'
local lines_on_screen = {first=1, last=1}
local buffer = {}
local args, options = shell.parse(...)
local filename, file_path

local new = false
if #args == 0 then
    filename = '[No Name]' 
    file_path = env.PWD
    new = true
else
    filename = shell.resolve(args[1])
    file_path = fs.path(filename)
    if not fs.exists(filename) then
	new = true
    end
end


-- Load Config
local config
if not fs.exists('/etc/vic/init.vic') then
    config = [[
vic.BG_COLOR = 0x1E1E1E
vic.LINE_COLOR = 0x4B4B4B
vic.THEME = nil
]]
    fs.makeDirectory('/etc/vic')
    local cfg_file = io.open('/etc/vic/init.vic', 'w')
    if cfg_file then
	cfg_file:write(config)
	cfg_file:close()
    end
else
    config = loadfile('/etc/vic/init.vic')
    pcall(config)
end

-- Funcs
local function getArea()
    local x, y, w, h = term.getGlobalArea()
    return x + unicode.wlen(tostring(lines_amount)) + 1, y, w, h - 2
end

local function draw_status_line(cur_col, cur_row, debug_info)
    local x, y, w, h = term.getGlobalArea()
    gpu.setBackground(vic.LINE_COLOR)
    gpu.fill(1, h - 1, w, 1, " ")
    local cursor_pos = string.format(' %d:%d ', cur_row, cur_col) 
    local line = " "..MODE.."  "..fs.name(filename)..' '..tostring(debug_info)
    line = line..text.padLeft(cursor_pos, w - line:len())
    gpu.set(1, h - 1, line)
end

local function draw_line_numbers(start)
    local x, y, w, h = term.getGlobalArea()
    start = start or y
    h = h - 2
    gpu.setBackground(vic.BG_COLOR)
    for number = start, h do 
	if number <= #buffer then
	    gpu.set(1, number, tostring(number))
	else 
	    gpu.set(1, number, '~')
	end
    end
end

local function draw_file_lines(start, finish)
    gpu.setBackground(vic.BG_COLOR)
    local x, y, w, h = getArea()
    start = start or y
    finish = finish or h
    lines_on_screen.first = start
    for number = start, finish do 
	if y + number - 1 > h then
	    lines_on_screen.last = number - 1
	    break
	end
	local line = buffer[number]
	if number > #buffer then
	    lines_on_screen.last = #buffer
	    break
	end
	gpu.set(x, y + number - 1, line)
    end
end

local function insert(str)
    return
end

local function scroll(direction, pixels)
    local x, y, w, h = term.getGlobalArea()
    local lines_first, lines_last = lines_on_screen.first, lines_on_screen.last
    if direction == 'up' then
	draw_file_lines(lines_first - pixels, lines_last - pixels)
	draw_line_numbers(lines_first - pixels)
    elseif direction == 'down' then
	draw_file_lines(lines_first + pixels, lines_last + pixels)
	draw_line_numbers(lines_first + pixels)
    elseif direction == 'right' then
    elseif direction == 'left' then
    end
end

local function getCursor()
    local x, _, _, _ = getArea()
    local col, row = term.getCursor()
    return col - x + 1, row
end

local function setCursor(col, row)
    local target_row = buffer[row] 
    local target_col = string.sub(target_row or '', col, col)
    local current_col, current_row = getCursor()
    local x, y, w, h = getArea()
    if row ~= current_row and target_row then -- Up and Down
	if row < current_row and row < lines_on_screen.first then
	    scroll('up', math.abs(row - current_row))
	    row = current_row
	elseif row > current_row and row > lines_on_screen.last then
	    scroll('down', math.abs(row - current_row))
	    row = current_row
	end

	if target_col ~= '' then -- set cursor on end or not
	    term.setCursor(x + col - 1, row)
	else 
	    term.setCursor(x + #target_row, row)
	end
    end

    if col ~= current_col and target_row then -- Left and Right
	if target_col ~= '' then
	    term.setCursor(x + col - 1, row)
	end
    end
end

-- Keybinds Handler
local sequence_buffer = ''
local amount = ''
vic.keymap = {

    down = {'n', 'j'},
    up = {'n', 'k'},
    left = {'n', 'h'},
    right = {'n', 'l'},

    insert_mode = {'n', 'i'},
    append_mode = {'n', 'a'},
    normal_mode = {'i', '<C-c>'},
    v_line_mode = {'n', 'V'},
    visual_mode = {'n', 'v'},
    command_mode = {'n', ':'},
    clear_buffers = {'n', '<C-c>'} 
}

vic.commands = {
    {'q', callback = function(...)
	os.exit()
    end},
}

vic.keyfuncs = {
    down = function()
	local col, row = getCursor()
	setCursor(col, row + 1)
    end,
    up = function()
	local col, row = getCursor()
	setCursor(col, row - 1)
    end,
    left = function()
	local col, row = getCursor()
	setCursor(col - 1, row)
    end,
    right = function()
	local col, row = getCursor()
	setCursor(col + 1, row)
    end,
    command_mode = function()
	local cursor_r, cursor_c = getCursor()
	local x, y, w, h = term.getGlobalArea()
	gpu.setBackground(vic.BG_COLOR)
	gpu.set(x, h, ':')
	term.setCursor(x + 1, h)
	local options = {}
	local command = term.read(nil, false, nil, nil)
	for option in string.gmatch(command, '%a+') do 
	    table.insert(options)
	end
	for i, command in pairs(vic.commands) do 
	    
	end 
    end,
    normal_mode = function()
    end,
    clear_buffers = function()
	sequence_buffer = ''
    end
}

local function specialsHandle(mode, on_ctrl, on_alt, on_shift, code)
    local pattern = ''
    if on_ctrl then pattern = '<C-%s>' end
    if on_alt then pattern = '<A-%s>' end
    if on_shift then pattern = '<S-%s>' end
    if pattern == '' then 
	return false
    end
    for command, map in pairs(vic.keymap) do 
	if map[1] == mode and string.format(pattern, keyboard.keys[code]) == map[2] then
	    vic.keyfuncs[command]()
	    return true
	end
    end
    return false
end

local function keymapHandle(mode, char)
    local char_code = char
    local char = unicode.char(char)
    local is_number = tonumber(char)
    local com_amount = 1
    if type(is_number) == 'number' then
	if char == '0' and amount == '' then
	    return
	end
	amount = amount .. char
	return
    end
    if char_code ~= 0 then
	sequence_buffer = sequence_buffer .. char
    end
    for command, map in pairs(vic.keymap) do 
	if sequence_buffer == map[2] and mode == map[1] then
	    if amount ~= '' then
		com_amount = tonumber(amount)
	    end
	    for i = 1, com_amount do 
		vic.keyfuncs[command]()
	    end
	    amount = ''
	    sequence_buffer = '' 
	end
    end
end

local function keyHandle(char, code)
    local on_ctrl = keyboard.isControlDown()
    local on_alt = keyboard.isAltDown()
    local on_shift = keyboard.isShiftDown()
    local unicode_char = unicode.char(char) 

    if MODE == 'INSERT' then
        if not specialsHandle('i', on_ctrl, on_alt, on_shift, code) then
	    insert(unicode_char)
	end
    end

    if MODE == 'NORMAL' then
	if not specialsHandle('n', on_ctrl, on_alt, on_shift, code) then
	    keymapHandle('n', char)
	end
    end

end

-- Main
local running = true

if not new then -- Buffer filling
    local file = io.open(filename)
    local lines_amount = 0
    for line in file:lines() do 
	table.insert(buffer, line)
	lines_amount = lines_amount + 1
    end
    if #buffer == 0 then
	table.insert(buffer, '')
    end
    file:close()
end

do -- UI drawing
    local _, _, w, h = term.getGlobalArea()
    local x, y, _, _ = getArea()
    term.clear() 
    gpu.setBackground(vic.BG_COLOR)
    gpu.fill(1, 1, w, h, " ")
    term.setCursorBlink(false)
    term.setCursor(x, y)
    draw_status_line(getCursor())
    draw_line_numbers()
    draw_file_lines()
end

while running do 
    local event, address, arg1, arg2, arg3 = term.pull()
    if event == 'key_down' then
	keyHandle(arg1, arg2)
	local cr, cc = getCursor()
	draw_status_line(cr, cc, sequence_buffer)
    end
end
