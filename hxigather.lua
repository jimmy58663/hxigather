--[[
Copyright © 2024, jimmy58663
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of HXIGather nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL jimmy58663 BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--]] _addon.name = 'hxigather';
_addon.author = 'jimmy58663';
_addon.version = '0.0.3';
-- _addon.desc      = 'HorizonXI chocobo digging tracker addon.';
-- _addon.link      = 'https://github.com/jimmy58663/HXIGather';
_addon.commands = {'hxigather'};

require('tables');
require('strings');
local logger = require('logger');
local config = require('config');
local data = require('itemdata');
local texts = require('texts');
local res = require('resources');
local packets = require('packets');

local logs = T {log_base_name = 'dugitems', char_name = nil};

-- Default Settings
local default_settings = T {
    visible = T {true},
    moon_display = T {true},
    display_timeout = T {600},
    item_index = data.ItemIndex,
    enable_logging = T {true},

    digging = T {
        gysahl_cost = T {62},
        gysahl_subtract = T {true},
        skillup_display = T {true}
    },
    reset_on_load = T {false},

    -- Text object display settings
    display = {
        padding = 1,
        pos = {x = 100, y = 100},
        text = {
            font = 'Arial',
            size = 14
            -- red = ,
            -- green = ,
            -- blue = ,
            -- alpha = ,
            -- stroke = {
            -- width = ,
            -- red = ,
            -- green = ,
            -- blue = ,
            -- alpha = ,
            -- },
        },
        flags = {italic = false, bold = false, right = false, bottom = false},
        bg = {
            -- red = ,
            -- green = ,
            -- blue = ,
            alpha = 200,
            visible = true
        }
    }
};

-- HXIGather Variables
local hxigather = T {
    settings = config.load(default_settings),
    is_attempt = false,
    last_attempt = os.time(),
    pricing = T {},
    gil_per_hour = 0,

    digging = T {
        dig_timing = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
        dig_index = 1,
        dig_per_minute = 0,
        dig_skillup = 0.0
    },

    first_attempt = 0,
    rewards = T {},
    -- Save dig items/tries across sessions for fatigue tracking
    dig_items = 0,
    dig_tries = 0
};

-- Display setup
local hxigather_display = texts.new('', hxigather.settings.display);
hxigather_display:draggable(true);

----------------------------------------------------------------------------------------------------
-- Helper functions
----------------------------------------------------------------------------------------------------
local function split(inputstr, sep)
    if sep == nil then sep = '%s'; end
    local t = {};
    for str in string.gmatch(inputstr, '([^' .. sep .. ']+)') do
        table.insert(t, str);
    end
    return t;
end

----------------------------------------------------------------------------------------------------
-- Format numbers with commas
-- https://stackoverflow.com/questions/10989788/format-integer-in-lua
----------------------------------------------------------------------------------------------------
local function format_int(number)
    if (string.len(number) < 4) then return number end
    if (number ~= nil and number ~= '' and type(number) == 'number') then
        local i, j, minus, int, fraction =
            tostring(number):find('([-]?)(%d+)([.]?%d*)');

        -- we sometimes get a nil int from the above tostring, just return number in those cases
        if (int == nil) then return number end

        -- reverse the int-string and append a comma to all blocks of 3 digits
        int = int:reverse():gsub("(%d%d%d)", "%1,");

        -- reverse the int-string back remove an optional comma and put the
        -- optional minus and fractional part back
        return minus .. int:reverse():gsub("^,", "") .. fraction;
    else
        return 'NaN';
    end
end

local function WriteLog(item)
    local datetime = os.date('*t');
    local log_file_name = ('%s_%s_%.4u.%.2u.%.2u.log'):format(logs.char_name,
                                                              logs.log_base_name,
                                                              datetime.year,
                                                              datetime.month,
                                                              datetime.day);
    local full_directory = ('%slogs/'):format(windower.addon_path);

    -- Set up log dirs if they do not exist
    if not windower.dir_exists(full_directory) then
        windower.create_dir(full_directory)
    end

    local file = io.open(('%s/%s'):format(full_directory, log_file_name), 'a');
    if (file ~= nil) then
        local filedata = ('%s, %s\n'):format(os.date('[%H:%M:%S]'), item);
        file:write(filedata);
        file:close();
    end
end

----------------------------------------------------------------------------------------------------
-- Core functions
----------------------------------------------------------------------------------------------------
--[[
* Prints the addon help information.
*
* @param {boolean} isError - Flag if this function was invoked due to an error.
--]]
local function print_help(isError)
    -- Print the help header..
    if (isError) then
        windower.add_to_chat(38,
                             ('[%s] Invalid command syntax for command: //%s'):format(
                                 _addon.name, _addon.name));
    else
        windower.add_to_chat(121,
                             ('[%s] Available commands:'):format(_addon.name));
    end

    local cmds = T {
        {'//hxigather save', 'Saves the current settings to disk.'},
        {'//hxigather reload', 'Reloads the current settings from disk.'},
        {'//hxigather clear', 'Clears the HXIGather rewards and session stats.'},
        {'//hxigather show', 'Shows the HXIGather display.'},
        {'//hxigather hide', 'Hides the HXIGather display.'},
        {
            '//hxigather update pricing',
            'Updates the HXIGather item pricing info.'
        }
    };

    -- Print the command list..
    for k, v in pairs(cmds) do
        windower.add_to_chat(121, ('[%s] Usage: %s - %s'):format(_addon.name,
                                                                 v[1], v[2]));
    end
end

local function update_pricing()
    local itemname;
    local itemvalue;
    for k, v in pairs(hxigather.settings.item_index) do
        for k2, v2 in pairs(split(v, ':')) do
            if (k2 == 1) then itemname = v2; end
            if (k2 == 2) then itemvalue = v2; end
        end

        hxigather.pricing[itemname] = itemvalue;
    end
end

-- Needed to move session data out of settings because of how Windower saves the settings
local function save_session_data()
    local filepath = ('%sdata/session_data'):format(windower.addon_path)
    local file = io.open(filepath, "w");
    if (file ~= nil) then
        file:write('session\n');
        file:write(('%s\n'):format(hxigather.dig_tries));
        file:write(('%s\n'):format(hxigather.dig_items));
        file:write(('%s\n'):format(hxigather.digging.dig_skillup));
        for k, v in pairs(hxigather.rewards) do
            file:write(('%s:%d\n'):format(k, v));
        end
        file:close();
    end
end

local function load_session_data()
    local filepath = ('%sdata/session_data'):format(windower.addon_path);
    if (windower.file_exists(filepath)) then
        local file = io.open(filepath, 'r');
        if (file ~= nil) then
            local trash = file:read();
            hxigather.dig_tries = file:read();
            hxigather.dig_items = file:read();
            hxigather.digging.dig_skillup = file:read();
            local line = file:read();
            while (line ~= nil) do
                local splitTable = split(line, ':');
                hxigather.rewards[splitTable[1]] = splitTable[2];
                line = file:read();
            end
            file:close();
        end
    end
end

local function clear()
    hxigather.is_attempt = 0;
    hxigather.last_attempt = os.time();
    hxigather.first_attempt = 0;
    hxigather.rewards = {};
    hxigather.dig_items = 0;
    hxigather.dig_tries = 0;
    hxigather.digging.dig_skillup = 0.0;
    save_session_data();
end

----------------------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------------------
--[[
* event: load
* desc : Event called when the addon is being loaded.
--]]
windower.register_event('load', function()
    update_pricing();
    load_session_data();
    if (hxigather.settings.reset_on_load[1]) then
        notice('Reset rewards and session stats on reload.');
        clear();
    end

    local name = windower.ffxi.get_player().name
    if (name ~= nil and name:len() > 0) then logs.char_name = name; end
end);

--[[
* event: unload
* desc : Event called when the addon is being unloaded.
--]]
windower.register_event('unload', function()
    -- Save the current settings..
    hxigather.settings:save();
    save_session_data();
end);

--[[
* event: logout
* desc : Event called when the character logs out.
--]]
windower.register_event('logout', function()
    -- Save the current settings..
    hxigather.settings:save();
    save_session_data();
end);

--[[
* event: command
* desc : Event called when the addon is processing a command.
--]]
windower.register_event('addon command', function(command, ...)
    -- Parse the command arguments..
    command = command and command:lower() or '';
    local args = (...) and (...):lower() or '';

    -- Handle: //hxigather save - Saves the current settings.
    if (command:match('save')) then
        update_pricing();
        hxigather.settings:save();
        save_session_data();
        notice('Settings saved.');
        return;
    end

    -- Handle: //hxigather reload - Reloads the current settings from disk.
    if (command:match('reload')) then
        config.reload(hxigather.settings);
        update_pricing();
        notice('Settings reloaded.');
        return;
    end

    -- Handle: //hxigather clear - Clears the current rewards and session stats.
    if (command:match('clear')) then
        clear();
        notice('Cleared rewards and session stats.');
        return;
    end

    -- Handle: //hxigather show - Shows the hxigather display.
    if (command:match('show')) then
        -- reset last dig on show command to reset timeout counter
        hxigather.last_attempt = os.time();
        hxigather.settings.visible[1] = true;
        return;
    end

    -- Handle: //hxigather hide - Hides the hxigather display.
    if (command:match('hide')) then
        hxigather.settings.visible[1] = false;
        return;
    end

    -- Handle: //hxigather update pricing - Updates the current pricing info for items.
    if (command:match('update')) then
        if (args:match('pricing')) then
            update_pricing();
            notice('Pricing updated.');
        end
        return;
    end

    -- Unhandled: Print help information..
    print_help(true);
end);

--[[
* event: outgoing chunk
* desc : Event called when the addon is processing outgoing chunks
]]
windower.register_event('outgoing chunk',
                        function(id, original, modified, injected, blocked)
    if (id == 0x01A) then -- digging
        local p = packets.parse('outgoing', modified);
        if p.Category == 17 then -- digging
            hxigather.is_attempt = true;
            local dig_diff = os.time() - hxigather.last_attempt;
            hxigather.last_attempt = os.time();
            hxigather.settings.visible[1] = true
            if (hxigather.first_attempt == 0) then
                hxigather.first_attempt = os.time();
            end
            if (dig_diff > 1) then
                hxigather.digging.dig_timing[hxigather.digging.dig_index] =
                    dig_diff;
                local timing_total = 0;
                for i = 1, #hxigather.digging.dig_timing do
                    timing_total = timing_total +
                                       hxigather.digging.dig_timing[i];
                end

                hxigather.digging.dig_per_minute = 60 /
                                                       (timing_total /
                                                           #hxigather.digging
                                                               .dig_timing);

                if (hxigather.digging.dig_index > #hxigather.digging.dig_timing) then
                    hxigather.digging.dig_index = 1;
                else
                    hxigather.digging.dig_index =
                        hxigather.digging.dig_index + 1;
                end
            end
        end
    end
end);

----------------------------------------------------------------------------------------------------
-- Parse Digging Items + Main Logic
----------------------------------------------------------------------------------------------------
windower.register_event('incoming text',
                        function(original, modified, original_mode,
                                 modified_mode, blocked)
    if (original_mode == 142 or original_mode == 9 or original_mode == 121) then
        local dig_diff = os.time() - hxigather.last_attempt
        local message = string.lower(original);
        message = string.strip_colors(message);

        local item = string.match(message, "obtained: (.*).");
        local unable = string.match(message, "you dig and you dig.*");
        local toss = string.match(message,
                                  ".*you regretfully throw the (.*) away.");
        local skill_up =
            string.match(message, "skill increases by (.*) raising");

        -- only set is_attempt if we dug within last 60 seconds
        if ((item or unable or toss) and dig_diff < 60) then
            hxigather.is_attempt = true;
        else
            hxigather.is_attempt = false;
        end

        if (skill_up) then
            hxigather.digging.dig_skillup =
                hxigather.digging.dig_skillup + skill_up;
        end

        if hxigather.is_attempt then
            hxigather.dig_tries = hxigather.dig_tries + 1;
            if (item) then
                hxigather.dig_items = hxigather.dig_items + 1;
                if (item ~= nil) then
                    if (hxigather.rewards[item] == nil) then
                        hxigather.rewards[item] = 1;
                    elseif (hxigather.rewards[item] ~= nil) then
                        hxigather.rewards[item] = hxigather.rewards[item] + 1;
                    end

                    -- Log the item
                    if (hxigather.settings.enable_logging[1]) then
                        WriteLog(item);
                    end
                end
            end
        end
    end
end);

windower.register_event('prerender', function()
    local info = windower.ffxi.get_info();
    local last_attempt = os.time() - hxigather.last_attempt;

    if (last_attempt > hxigather.settings.display_timeout[1]) then
        hxigather.settings.visible[1] = false;
    end

    -- Hide the display if not visible
    if (not hxigather.settings.visible[1]) then
        hxigather_display:hide();
        return;
    end

    local elapsed_time = os.time() - math.floor(hxigather.first_attempt);
    local total_worth = 0;
    local accuracy = 0;
    local moon_percent = info.moon;
    local moon_phase = res.moon_phases[info.moon_phase].name;

    if (hxigather.dig_tries ~= 0) then
        accuracy = (hxigather.dig_items / hxigather.dig_tries) * 100;
    end

    local output_text = '--------HXIGather--------';
    output_text = output_text .. '\nAttempted Digs: ' .. hxigather.dig_tries ..
                      ' (' ..
                      string.format('%.2f', hxigather.digging.dig_per_minute) ..
                      ' dpm)';
    output_text = output_text .. '\nGreens Cost: ' ..
                      format_int(
                          hxigather.dig_tries *
                              hxigather.settings.digging.gysahl_cost[1]);
    output_text = output_text .. '\nItems Dug: ' .. hxigather.dig_items;
    output_text = output_text .. '\nDig Accuracy: ' ..
                      string.format('%.2f', accuracy) .. '%';
    output_text = output_text .. '\nWeather: ' .. res.weather[info.weather].name;
    if (hxigather.settings.moon_display[1]) then
        if (moon_phase == 'Waxing Crescent') then
            output_text = output_text .. '\nMoon: ' .. moon_phase .. ' (' ..
                              tostring(moon_percent):text_color(0, 255, 0) ..
                              '%)'; -- Green elemental or time
        else
            if (moon_percent >= 35 and moon_percent <= 65) then
                output_text = output_text .. '\nMoon: ' .. moon_phase .. ' (' ..
                                  tostring(moon_percent):text_color(255, 0, 0) ..
                                  '%)'; -- Red bad accuracy time
            else
                output_text = output_text .. '\nMoon: ' .. moon_phase .. ' (' ..
                                  tostring(moon_percent):text_color(255, 255, 0) ..
                                  '%)'; -- Yellow decent accuracy time
            end
        end
    end

    if (hxigather.settings.digging.skillup_display[1]) then
        -- Only show skillup line if one was seen during session
        if (hxigather.digging.dig_skillup ~= 0.0) then
            output_text = output_text .. '\nSkillups: ' ..
                              hxigather.digging.dig_skillup;
        end
    end

    output_text = output_text .. '\n--------------------------';

    for k, v in pairs(hxigather.rewards) do
        local itemTotal = 0;
        if (hxigather.pricing[k] ~= nil) then
            itemTotal = hxigather.pricing[k] * v;
            total_worth = total_worth + itemTotal;
        end

        output_text =
            output_text .. '\n' .. k .. ': x' .. format_int(v) .. ' (' ..
                format_int(itemTotal) .. 'g)';
    end

    output_text = output_text .. '\n--------------------------';

    if (hxigather.settings.digging.gysahl_subtract[1]) then
        total_worth = total_worth -
                          (hxigather.dig_tries *
                              hxigather.settings.digging.gysahl_cost[1]);
        -- only update gil_per_hour every 3 seconds
        if ((os.time() % 3) == 0) then
            hxigather.gil_per_hour = math.floor(
                                         (total_worth / elapsed_time) * 3600);
        end
        output_text = output_text .. '\nTotal Profit: ' ..
                          format_int(total_worth) .. 'g (' ..
                          format_int(hxigather.gil_per_hour) .. ' gph)';
    else
        -- only update gil_per_hour every 3 seconds
        if ((os.time() % 3) == 0) then
            hxigather.gil_per_hour = math.floor(
                                         (total_worth / elapsed_time) * 3600);
        end
        output_text = output_text .. '\nTotal Revenue: ' ..
                          format_int(total_worth) .. 'g (' ..
                          format_int(hxigather.gil_per_hour) .. ' gph)';
    end

    hxigather_display:text(output_text);

    if (not hxigather_display:visible()) then hxigather_display:show(); end
end);
