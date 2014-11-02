-- vkmusic.lua -- VLC extension --
--[[
INSTALLATION:
Put the file in the VLC subdir /lua/extensions, by default:
* Windows (all users): %ProgramFiles%\VideoLAN\VLC\lua\extensions\
* Windows (current user): %APPDATA%\VLC\lua\extensions\
* Linux (all users): /usr/share/vlc/lua/extensions/
* Linux (current user): ~/.local/share/vlc/lua/extensions/
* Mac OS X (all users): /Applications/VLC.app/Contents/MacOS/share/lua/extensions/
(create directories if they don't exist)
* Create symlink on Linux: 
*  ln -s /usr/lib/vlc/lua/intf/modules/common.luac <install_path>/modules/common.luac
Restart the VLC.
Then you simply use the extension by going to the "View" menu and selecting it.
--]]

require "common"

-- needed modules
local json = nil

-- VK API version
local apiVersion = "5.25"
-- App ID
--! Don't remove or change !--
local appId = 4605667

local auth_url = "https://oauth.vk.com/authorize?client_id="..appId..
                 "&scope=audio&redirect_uri=https://oauth.vk.com/blank.html&display=page&v="..apiVersion..
                 "&response_type=token"

local dlg = nil        -- dialog
local input_table = {} -- input widgets by id
local config = {}      -- global configuration
local list = {}        -- list of searched records
local page_size = {10, 50, 100, 200, 300}

function descriptor()
	return {
		title = "VK Music";
		version = "1.0";
		author = "Romastyi";
		url = "https://github.com/Romastyi/VLC-VK-Music";
		shortdesc = "vk.com music player";
		description = "<div style=\"background-color:lightgreen;\">"
		            .."<b>VK Music</b> is VLC extension (extension script \"vkmusic.lua\") that plays music from vk.com.</div>";
	    scope = "network";
		capabilities = { "menu" }
	}
end

function activate()
    vlc.msg.dbg("[VK Music] Welcome")
    
    if not check_config() then
        vlc.msg.dbg("[VK Music] Configuration loading failed!")
        return false
    end
    
	show_main()
end

function deactivate()
    save_interface()
    
    vlc.msg.dbg("[VK Music] Goodbye!")
    
    if dlg then
        dlg:hide()
    end
end

function close()
	vlc.deactivate()
end

function menu()
    return { "Research", "Config", "Help" }
end

-- initialization of json
function json_init()
    if json ~= nil then return false end

    vlc.msg.dbg("[VK Music] JSON parser lazy initialization")
    json = require ("dkjson")
    
    -- Use vlc.stream to grab a remote json file, place it in a string,
    -- decode it and return the decoded data.
    json["parse_url"] = function(url)
        local stream = vlc.stream(url)
        
        if stream == nil then
            setError("Request to "..url.." is failed.")
            return {}
        end
        
        local string = ""
        local line   = ""

        repeat
            line = stream:readline()
            string = string..line
        until line ~= nil

        return json.decode(string)
    end
end

-- Interface of main dialog
function interface_main()
    dlg:add_label("<b>Search:</b>"   , 1,1,1,1)
    dlg:add_label("<b>Count:</b>"    , 1,2,1,1)
    dlg:add_label("<b>Offset:</b>"   , 3,2,1,1)
    dlg:add_label("<b>Search by:</b>", 9,3,1,1);
    dlg:add_label("<b>Play:</b>"     , 9,7,1,1);
    dlg:add_label("<b>Download:</b>" , 9,10,1,1);
    input_table["search"]  = dlg:add_text_input(config.options.search, 2,1,5,1)
    input_table["where"]   = dlg:add_dropdown(7,1,2,1)
    input_table["count"]   = dlg:add_dropdown(2,2,1,1)
    input_table["offset"]  = dlg:add_text_input(config.options.offset, 4,2,1,1)
    input_table["mainlist"]= dlg:add_list(1,3,8,17)
    input_table["message"] = nil
    input_table["message"] = dlg:add_label("", 1,20,9,1)
    input_table["total"]   = dlg:add_label("", 7,2,1,1)
    dlg:add_button("Search"  , searchAll   , 9,1,1,1)
    dlg:add_button("Clear"   , clearSearch , 9,2,1,1)
    dlg:add_button("Artist"  , searchArtist, 9,4,1,1)
    dlg:add_button("Title"   , searchTitle , 9,5,1,1)
    dlg:add_button("Artist+Title",searchOne, 9,6,1,1)
    dlg:add_button("Selected" , addSelected , 9,8,1,1)
    dlg:add_button("All Found", addAllFound , 9,9,1,1)
    dlg:add_button("Selected" , downloadSelected, 9,11,1,1)
    dlg:add_button("All Found", downloadAllFound, 9,12,1,1)
    dlg:add_button("< Prev", movePrev  , 5,2,1,1)
    dlg:add_button("Next >", moveNext  , 6,2,1,1)
    dlg:add_button("Help"  , show_help , 7,21,1,1)
    dlg:add_button("Config", show_conf , 8,21,1,1)
    dlg:add_button("Close" , deactivate, 9,21,1,1)
    -- fill dropdowns
    input_table["where"]:add_value("Search everywhere", 1)
    input_table["where"]:add_value("Search in user\'s audio", 2)
    for i,v in ipairs(page_size) do
        input_table["count"]:add_value(v, i)
    end
    input_table["count"]:set_text(config.options.count)
end

-- Interface of config dialog
function interface_conf()
	dlg:add_label("<b>Auth request:</b>"   , 1,1,1,1)
	dlg:add_label("<a href=\""..auth_url.."\">Click Here...</a>", 2,1,1,1)
	dlg:add_label("<b>Access token:</b>"   , 1,2,1,1)
	dlg:add_label("<b>User ID:</b>"        , 1,3,1,1)
    if config.options.folder then
        if config.os == "win" then
            dlg:add_label("<a href='file:///"..config.options.folder.."'>Download folder:</a>", 1,4,1,1)
        else
            dlg:add_label("<a href='"..config.options.folder.."'>Download folder:</a>", 1,4,1,1)
        end
    else
        dlg:add_label("<b>Download folder:</b>", 1,4,1,1)
    end
	input_table["token"]  = dlg:add_text_input(config.options.token , 2,2,7,1)
	input_table["userId"] = dlg:add_text_input(config.options.userId, 2,3,7,1)
	input_table["folder"] = dlg:add_text_input(config.options.folder, 2,4,7,1)
	-- something strange with position of checkbox?
	input_table["dir_for_artist"] = dlg:add_check_box("Create new folder for each artist", 1,3,6,2)
	input_table["dir_for_artist"]:set_checked(config.options.dir_for_artist)
    input_table["message"] = nil
    input_table["message"] = dlg:add_label("", 1,7,4,1)
	dlg:add_button("Cancel", show_main   , 7,7,1,1)
	dlg:add_button("Save"  , apply_config, 8,7,1,1)
end

-- Interface of help dialog 
function interface_help()
    dlg:add_html("", 1,1,3,1)
    dlg:add_button("OK", show_main, 2,2,1,1)
end

-- show dialog by id
function trigger_menu(dlg_id)
    if dlg_id == 1 then
        close_dlg()
        dlg = vlc.dialog("Music Search")
        interface_main()
    elseif dlg_id == 2 then
        close_dlg()
        dlg = vlc.dialog("Configuration")
        interface_conf()
    elseif dlg_id == 3 then
        close_dlg()
        dlg = vlc.dialog("Help")
        interface_help()
    end
    collectgarbage()
end

function show_main()
    trigger_menu(1)
end

function show_conf()
    trigger_menu(2)
end

function show_help()
    trigger_menu(3)
end

-- Close current dialog
function close_dlg()
    save_interface()
    
    vlc.msg.dbg("[VK Music] Closing dialog")
    
    if dlg ~= nil then
        dlg:hide()
    end
    
    dlg = nil
    input_table = nil
    input_table = {}
    collectgarbage()
end

function setMessage(msg)
    if input_table["message"] then
        input_table["message"]:set_text(msg)
        dlg:update()
    end
end

function setError(msg)
    setMessage(error_tag(msg))
end

function success_tag(str)
    return "<span style='color:#181'><b>Success:</b></span> "..str..""
end

function error_tag(str)
    return "<span style='color:#B23'><b>Error:</b></span> "..str..""
end

-- Save interface config
function save_interface()
    vlc.msg.dbg("[VK Music] Saving interface")
    
    if input_table["search"] then
        config.options.search = input_table["search"]:get_text()
    end
    
    if input_table["count"] then
        config.options.count  = input_table["count"]:get_text()
    end
    
    if input_table["offset"] then
        config.options.offset  = input_table["offset"]:get_text()
    end
    
    save_config()
end

-- Change offset
function pageSize()
    if input_table["count"] then
        return input_table["count"]:get_text()
    end
    return 100
end

function getOffset()
    if input_table["offset"] then
        local o = tonumber(input_table["offset"]:get_text())
        
        if o == nil then
            setError("Offset must be a number!")
            input_table["offset"]:set_text(0)
            o = 0
        elseif o < 0 then
            setError("Offset must be greater than 0")
            input_table["offset"]:set_text(0)
            o = 0
        elseif o > 1000 then
            setError("Offset must be less than 1000")
            input_table["offset"]:set_text(1000)
            o = 1000
        end
        
        dlg:update()
        
        return o
    end        
    
    return -1
end

function movePrev()
    local o = getOffset()
    if o ~= -1 then
        local v = o - pageSize()
        if v < 0 then
            input_table["offset"]:set_text(0)
        else
            input_table["offset"]:set_text(v)
        end
        dlg:update()
        -- If search was started
        if next(list) ~= nil then
            searchAll()
            return falses
        end
    end
end

function moveNext()
    local o = getOffset()
    if o ~= -1 then
        local v = o + pageSize()
        if v > 1000 then
            input_table["offset"]:set_text(1000)
        else
            input_table["offset"]:set_text(v)
        end
        dlg:update()
        -- If search was started
        if next(list) ~= nil then
            searchAll()
            return false
        end
    end
end

-- Clear search controls
function clearSearch()
    input_table["search"]:set_text("")
    input_table["offset"]:set_text(0)
    input_table["mainlist"]:clear()
    list = nil
    collectgarbage()
    list = {}
    dlg:update()
end

-- Search all
function searchAll()
    local str = input_table["search"]:get_text()
    -- check if search string is a link like:
    if str:match("^http[s]?://vk%.com/.+") then
        local url = str:gsub("^http[s]?://vk%.com/", "")
        -- http://vk.com/search?c[q]=xxx&c[section]=audio
        -- http://vk.com/search?c[performer]=1&c[q]=xxx&c[section]=audio
        if url:match("^search%?.*c%[q%]=.+&c%[section%]=audio") then
            str = unescape(string.gsub(url:gsub("search%?.*c%[q%]=", ""), "&c%[section%]=audio", ""))
        -- http://vk.com/audiosXXX?q=yyy
        -- http://vk.com/audiosXXX?performer=1&q=yyy
        elseif url:match("^audios.+%?.*[&]?q=.+") then 
            str = unescape(url:gsub("^audios.+%?.*[&]?q=", ""))
        else
            setError("Unrecognized URL")
            return false
        end
    end
    
    search(str);
end

-- Selected record
function getSelectedRecord()
    local count = 0
    
    for i, _ in pairs(input_table["mainlist"]:get_selection()) do
        if count == 0 then
            return list.items[i]
        end
        count = 1
        break
    end
    
    if count == 0 then
        setError("Any record is not selected")
        return false
    else
        setError("More than one record is selected")
        return false
    end
end

-- Search by artist
function searchArtist()
    local selected = getSelectedRecord()
    
    if selected then
        search(selected.artist)
    end
end

-- Search by title
function searchTitle()
    local selected = getSelectedRecord()
    
    if selected then
        search(selected.title)
    end
end

-- 
function searchOne()
    local selected = getSelectedRecord()
    
    if selected then
        search(selected.artist.." "..selected.title)
    end
end

-- Search request
function search( str )
    input_table["search"]:set_text(str)
--    dlg:update()
 
    save_interface()
   
    local auto_complete = true
    if str:match("^!.+") then 
        auto_complete = false
        str = str:gsub("^!", "")
    end
    
    local msg = "Searching"
    if str ~= "" then
        msg = msg.."\""..str.."\""
    end
    msg = msg.."... "
    setMessage(msg)
    
    local where = input_table["where"]:get_value()
    local mainlist = input_table["mainlist"]
    local count = pageSize()
    local offset = getOffset()
    if offset == -1 then return false end

    list = nil
    mainlist:clear()
    collectgarbage()
    list = {}
    
    if where == 2 then
        if not str or trim(str) == "" then 
            list = get_music(config.options.token, config.options.userId, nil, nil, offset, count)
        else
            list = search_music(config.options.token, str, offset, count, true, auto_complete)
        end
    else
        if not str or trim(str) == "" then 
            setError("Search string is empty. Nothing to find!")
            return false 
        end
        list = search_music(config.options.token, str, offset, count, false, auto_complete)
    end
    
    local total = 0
    
    for i, item in ipairs(list.items) do
        mainlist:add_value(
            item.artist.." - "..item.title..
            " ["..string.format("%02d", math.floor(item.duration / 60))..":"
                ..string.format("%02d", item.duration % 60).."]", i)
        total = total + 1
    end
    
    if input_table["total"] then 
        input_table["total"]:set_text("<b>Total:</b> "..total) 
    end
    
    setMessage(success_tag(msg.."Finished!"))
end

-- Add record to playlist
function newRecord( item )
    local new_record = {}
    -- http://cs521502.vk.me/u17423406/audios/d135a1860461.mp3?extra=xxx
    -- removing ?extra=xxx
    local url = string.match(item.url, "^http[s]?://.+%?extra=")
    if url then
        new_record.path = url:gsub("?extra=", "")
    else
        new_record.path = item.url
    end
    new_record.name = item.artist.." - "..item.title
    new_record.artist = item.artist
    new_record.title = item.title
    new_record.duration = item.duration
    
    return new_record
end

-- Add selected records to playlist
function addSelected()
    local records = {}
    local count = 0
    
    for i, _ in pairs(input_table["mainlist"]:get_selection()) do
        table.insert(records, newRecord(list.items[i]))
        count = count + 1
    end

    if count == 0 then
        setError("Where is nothing to add")
    else
        vlc.playlist.enqueue(records)
        setMessage(success_tag(count.." records were added"))
    end
end

-- Add all founded records
function addAllFound()
    local records = {}
    local count = 0
    
    for _, item in pairs(list.items) do
        table.insert(records, newRecord(item))
        count = count + 1
    end

    if count == 0 then
        setError("Where is nothing to add")
    else
        vlc.playlist.enqueue(records)
        setMessage(success_tag(count.." records were added"))
    end
end

-- Parse music list
function parse_music_list( source )
    if is_error(source) then
        -- error
        setError(source.error.error_msg)
        return false
    elseif is_response(source) then
        -- success
        local res = {}
        res.count = 0
        res.items = {}
        if source.response then
            -- the total amount of elements
            if source.response[1] then res.count = source.response[1] end
            -- list of elements
            for _, item in pairs(source.response) do
                if type(item) == "table" and item.url then 
                    -- properties of record
                    local i = {}
                    i.duration = item.duration
                    i.artist   = item.artist
                    i.title    = item.title
                    i.url      = item.url
                    table.insert(res.items, i)
                end
            end
        end
        return res
    else
        -- unknown result
        setError("Unknown result!")
        return false
    end
end

function is_response(obj)
    return type(obj) == "table" and obj.response ~= nil
end

function is_error(obj)
    return type(obj) ~= "table" or obj.error ~= nil
end

-- Get music by owner
-- Help: http://vk.com/dev/audio.get
-- URL: https://api.vk.com/method/audio.get?owner_id=xxx&album_id=yyy&audio_ids=aa,bb,cc&need_user=0&offset=0&count=0&access_token=yyy
function get_music( token, owner_id, album_id, audio_ids, offset, count )
    local url = "https://api.vk.com/method/audio.get?"
    -- request params
    if owner_id then url = url.."owner_id="..owner_id.."&" end
    if album_id then url = url.."album_id="..album_id.."&" end
    if audio_ids then
        url = url.."audio_ids="
        if type(audio_ids) == "table" then
            for _, item in pairs(audio_ids) do
                url = url..item..","
            end
        else
            url = url..audio_ids
        end
        url = url.."&"
    end
    if offset then url = url.."offset="..offset.."&" end
    if count then url = url.."count="..count.."&" end
    -- access token
    url = url.."access_token="..token
    local r = json.parse_url(url)
    return parse_music_list(r)
end

-- Search music by string request
-- Help: http://vk.com/dev/audio.search
-- URL: https://api.vk.com/method/audio.search?q=xxx&auto_complete=0&lyrics=0&performer_only=0&sort=0&search_own=0&offset=0&count=3&access_token=yyy
function search_music( token, str, offset, count, search_own, auto_complete )
    local url = "https://api.vk.com/method/audio.search?"
    -- request params
    if str then url = url.."q="..str.."&" end
    if offset then url = url.."offset="..offset.."&" end
    if count then url = url.."count="..count.."&" end
    if search_own then url = url.."search_own=1&" end
    if auto_complete then url = url.."auto_complete=1&" end
    -- access token
    url = url.."access_token="..token
    local r = json.parse_url(url)
    return parse_music_list(r)
end

-- Download records
function downloadRecord(item)
    if item == nil or item.url == "" then
        setError("Where is nothing to download")
        return false
    end

    local folder = config.options.folder
    local filename = item.title..".mp3"
    if item.artist ~= "" then
        if config.options.dir_for_artist then
            folder = folder..slash..item.artist
        else
            filename = item.artist.." - "..filename
        end
    end
    local target = folder..slash..filename

    vlc.msg.dbg("[VK Music] Downloading ulr to file \""..target.."\"...")
    setMessage("Downloading to file \""..filename.."\"...")
    -- if file already exists
    if file_exists(target) then
        setMessage(success_tag("File \""..filename.."\" already exists"))
        return true
    end
    -- Determine if the path to the audio file is accessible for writing
    if not is_dir(folder) then
        mkdir_p(folder)
    end
    if not file_touch(target) then
        setError("Could not create file \""..target.."\"")
        return false
    end
    -- Downlaod data into file
    local stream = vlc.stream(item.url)
    local data = ""
    local file = io.open(target, "wb")
    while data do
        file:write(data)
        data = stream:read(65536)
    end
    file:flush()
    file:close()
    stream = nil
    collectgarbage()

    setMessage(success_tag("Downloading to file \""..filename.."\"... Finished"))
    vlc.msg.dbg("[VK Music] Downloading ulr to file \""..target.."\"... Finished")
    return true
end

-- Download selected records
function downloadSelected()
    local count = 0
    
    for i, _ in pairs(input_table["mainlist"]:get_selection()) do
        if downloadRecord(list.items[i]) then
            count = count + 1
        end
    end
    
    if count == 0 then
        setError("Where is nothing to download")
    else
        local dir = config.options.folder
        if config.os == "win" then
            dir = "<a href='file:///"..dir.."'>"..dir.."</a>"
        else
            dir = "<a href='"..dir.."'>"..dir.."</a>"
        end
        setMessage(success_tag(count.." records were downloaded in \""..dir.."\""))
    end
end

-- Download all found records
function downloadAllFound()
    local count = 0
    
    for _, item in pairs(list.items) do
        if downloadRecord(item) then
            count = count + 1
        end
    end
    
    if count == 0 then
        setError("Where is nothing to download")
    else
        local dir = config.options.folder
        if config.os == "win" then
            dir = "<a href='file:///"..dir.."'>"..dir.."</a>"
        else
            dir = "<a href='"..dir.."'>"..dir.."</a>"
        end
        setMessage(success_tag(count.." records were downloaded in \""..dir.."\""))
    end
end

-- Configurations
function check_config()
    json_init()

    if is_windows_path(vlc.config.datadir()) then
        config.os = "win"
        slash = "\\"
    else
        config.os = "*nix"
        slash = "/"
    end
    
    config.file = vlc.config.configdir()..slash.."vkmusic.conf"
    config.options = {}
    
    if not file_exists(config.file) and not file_touch(config.file) then
        vlc.msg.dbg("[VK Music] Permission denied for \""..config.file.."\"")
        return false
    else
        if not load_config() then
            vlc.msg.dbg("[VK Music] Could not load config from \""..config.file.."\"")
            return false
        end
    end
    
    return true
end

function load_config()
    config.options = {}
    local f = io.open(config.file, "rb")
    if not f then return false end
    local content = f:read("*all")
    f:flush()
    f:close()
    f = nil
    if content ~= "" then
        local obj, _, err = json.decode(content)
        if err then return false end
        config.options = obj
    end
    if not config.options.search then config.options.search = "" end
    if not config.options.count  then config.options.count = 100 end
    if not config.options.offset then config.options.offset =  0 end
    if not config.options.folder then config.options.folder = vlc.config.userdatadir() end
    if config.options.dir_for_artist == nil then
        config.options.dir_for_artist = true
    end
    collectgarbage()
    return true
end

function save_config()
    if file_touch(config.file) then
        local f = io.open(config.file, "wb")
        local resp = json.encode(config.options)
        f:write(resp)
        f:flush()
        f:close()
        f = nil
    else
        return false
    end
    collectgarbage()
    return true
end

function apply_config()
    local new_token = input_table["token"]:get_text()
    local new_userId = input_table["userId"]:get_text()
    local new_folder = input_table["folder"]:get_text()
    config.options.dir_for_artist = input_table["dir_for_artist"]:get_checked()
    
    -- check new token
    if new_token ~= config.options.token then
        if not search_music(new_token, nil, nil, 1) then
            setError("Invalid access token")
            return false
        end
        config.options.token = new_token
    end
    
    -- check new userId
    if new_userId ~= config.options.userId then
        if not get_music(new_token, new_userId, nil, nil, nil, 1) then
            setError("Invalid user ID")
            return false
        end
        config.options.userId = new_userId
    end
    
    -- check download folder
    if new_folder ~= config.options.folder then
        if not is_dir(new_folder) then
            if file_exists(new_folder) then
                setError("Invalid path (file path specified)")
                return false
            end
            mkdir_p(new_folder)
        end
        config.options.folder = new_folder
    end
    
    if not save_config() then
        setError("Could not save config file")
        return false
    end
    
    show_main()
end

function is_windows_path(path)
    return string.match(path, "^(%a:.+)$")
end

function file_touch(name) -- test write ability
    if not name or trim(name) == "" then 
        return false 
    end
    local f = io.open(name, "w")
    if f ~= nil then 
        io.close(f) 
        return true 
    else 
        return false 
    end
end

function file_exists(name) -- test readability
    if not name or trim(name) == "" then 
        return false 
    end
    local f = io.open(name, "r")
    if f ~= nil then 
        io.close(f) 
        return true 
    else 
        return false 
    end
end

function is_dir(path)
    if not path or trim(path) == "" then 
        return false 
    end
    -- Remove slash at the end or it won't work on Windows
    path = string.gsub(path, "^(.-)[\\/]?$", "%1")
    local f, _, code = io.open(path, "rb")
    if f then
        _, _, code = f:read("*a")
        f:close()
        if code == 21 then
            return true
        end
    elseif code == 13 then
        -- permission denied
        return true 
    end
    return false
end

function mkdir_p(path)
    if not path or trim(path) == "" then 
        return false 
    end
    if config.os == "win" then
        os.execute('mkdir "' .. path..'"')
    elseif config.os == "*nix" then
        os.execute("mkdir -p '" .. path.."'")
    end
end

function trim(str)
    if not str then return "" end
    return string.gsub(str, "^[\r\n%s]*(.-)[\r\n%s]*$", "%1")
end

function unescape(s)
    s = string.gsub(s, "+", " ")
    s = string.gsub(s, "%%(%x%x)", function (h)
        return string.char(tonumber(h, 16))
    end)
    return s
end

