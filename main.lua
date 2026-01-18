local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local logger = require("logger")
local json = require("json")
local NetworkMgr = require("ui/network/manager")
local Dispatcher = require("dispatcher")

local Menus = require("menus")
local GetHighlights = require("get_highlights")
local NotionClient = require("notion_client")
local SyncManager = require("sync_manager")

local NotionSync = WidgetContainer:new{
    name = "NotionSync",
    config = {
        notion_token = "",
        database_id = ""
    },
    client = nil,
    config_file = "plugins/notionsync.koplugin/config.json"
}

function NotionSync:init()
    self.ui.menu:registerToMainMenu(self)
    self:loadConfig()

    Dispatcher:registerAction("notionsync_action", {
        category = "none",
        event = "NotionSyncTrigger",
        title = "Sync to Notion",
        general = true,
    })
end

function NotionSync:addToMainMenu(menu_items)
    Menus.register(self, menu_items)
end

function NotionSync:onNotionSyncTrigger()
    self:onSyncRequested()
end

-- =========================================================
-- CONFIGURATION LOGIC
-- =========================================================

function NotionSync:loadConfig()
    local file = io.open(self.config_file, "r")
    if file then
        local content = file:read("*a")
        file:close()
        local loaded = json.decode(content)
        if loaded then
            self.config = loaded
            if self.config.notion_token and self.config.notion_token ~= "" then
                self.client = NotionClient:new(self.config)
            end
        end
    end
end

function NotionSync:saveConfig()
    local file = io.open(self.config_file, "w")
    if file then
        file:write(json.encode(self.config))
        file:close()
        self.client = NotionClient:new(self.config)
    else
        self:notify("Error saving config.json")
    end
end

function NotionSync:showConfigMenu()
    local db_info = "Not Configured"
    if self.config.database_id and self.config.database_id ~= "" then
        db_info = "Configured (" .. self.config.database_id:sub(1, 4) .. "...)"
    end

    local token_info = "Not Set"
    if self.config.notion_token and self.config.notion_token ~= "" then
        token_info = "Set (Ends in ..." .. self.config.notion_token:sub(-4) .. ")"
    end

    local settings_menu -- Forward declaration
    
    settings_menu = Menu:new{
        title = "NotionSync Settings",
        item_table = {
            {
                text = "Set Notion Token",
                sub_text = token_info,
                callback = function() 
                    self:promptForToken(settings_menu) 
                end
            },
            {
                text = "Select Database",
                sub_text = db_info,
                callback = function() 
                    self:promptForDatabase(settings_menu) 
                end
            }
        }
    }
    UIManager:show(settings_menu)
end

function NotionSync:promptForToken(parent_menu)
    local input_dialog
    input_dialog = InputDialog:new{
        title = "Enter Notion Integration Token",
        input = self.config.notion_token,
        buttons = {
            {
                {
                    text = "Cancel",
                    id = "close",
                    callback = function()
                        UIManager:close(input_dialog)
                    end
                },
                {
                    text = "Save",
                    callback = function()
                        local token = input_dialog:getInputValue()
                        if token and token ~= "" then
                            self.config.notion_token = token
                            self:saveConfig()
                            self:notify("Token Saved")
                            if parent_menu then UIManager:close(parent_menu) end
                            self:showConfigMenu()
                        end
                        UIManager:close(input_dialog)
                    end
                }
            }
        }
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function NotionSync:promptForDatabase(parent_menu)
    if not NetworkMgr:isOnline() then self:notify("Enable Wi-Fi first") return end
    if not self.client then self:notify("Set Token first!") return end

    -- 1. Show Persistent Loading Popup
    local loading_popup = InfoMessage:new{
        text = "Fetching Databases...",
        timeout = nil, -- Persistent
    }
    UIManager:show(loading_popup)

    -- 2. Create Coroutine
    local co = coroutine.create(function()
        -- IMPORTANT: Yield immediately to allow the popup to draw on screen
        coroutine.yield()

        -- Now perform the blocking network request
        local res, err = self.client:listDatabases()
        
        -- Close the loading popup immediately after data returns
        if loading_popup then UIManager:close(loading_popup) end

        if not res or not res.results then
            self:notify("Error: " .. tostring(err))
            return
        end

        local db_list = {}
        local db_menu -- Forward declaration

        for _, item in ipairs(res.results) do
            local title = "Untitled"
            if item.title and item.title[1] then
                title = item.title[1].plain_text
            end
            
            table.insert(db_list, {
                text = title,
                callback = function()
                    self.config.database_id = item.id
                    self:saveConfig()
                    
                    if db_menu then UIManager:close(db_menu) end
                    self:notify("Selected: " .. title)
                    
                    if parent_menu then UIManager:close(parent_menu) end
                    self:showConfigMenu()
                end
            })
        end

        if #db_list == 0 then
            self:notify("No databases found accessible by this token.")
        else
            -- Show the Menu (Yielding first ensures cleanup of previous popup)
            coroutine.yield()
            local show_menu = function()
                db_menu = Menu:new{
                    title = "Select Target Database",
                    item_table = db_list
                }
                UIManager:show(db_menu)
            end
            UIManager:nextTick(show_menu)
        end
    end)

    -- 3. Pump the coroutine
    local function pump()
        if coroutine.status(co) == "suspended" then
            local status, res = coroutine.resume(co)
            if not status then
                if loading_popup then UIManager:close(loading_popup) end
                logger.err("NotionSync DB List Crash: " .. tostring(res))
                self:notify("Crash: " .. tostring(res))
            else
                UIManager:nextTick(pump)
            end
        end
    end
    UIManager:nextTick(pump)
end

-- =========================================================
-- SYNC LOGIC
-- =========================================================

function NotionSync:notify(msg)
    UIManager:nextTick(function()
        UIManager:show(InfoMessage:new{
            text = msg,
            timeout = 3
        })
    end)
end

-- Sync current book to notion
function NotionSync:onSyncRequested()

    -- Enable Wi-Fi if not online
    if not NetworkMgr:isOnline() then
        NetworkMgr:enableWifi()
        return
    end

    -- Check if plugin is configured
    if not self.client or not self.config.database_id or self.config.database_id == "" then
        self:notify("Plugin not configured. Check settings.")
        self:showConfigMenu()
        return
    end

    local doc = self.ui.document
    local annotations = self.ui.annotation and self.ui.annotation.annotations
    local payload, err = GetHighlights.transform(doc, annotations)
    
    if not payload then self:notify(err or "Error extracting highlights") return end

    local loading_popup = InfoMessage:new{
        text = "Syncing highlights to Notion...",
        timeout = nil,
    }
    UIManager:show(loading_popup)

    local yield_func = function() coroutine.yield() end

    local co = coroutine.create(function()
        local result = SyncManager.sync(self.client, payload, nil, yield_func)
        if loading_popup then UIManager:close(loading_popup) end
        
        if result.success then
            coroutine.yield() 
            self:notify(string.format("Success! New: %d, Updated: %d", result.new, result.updated))
        else
            self:notify("Failed: " .. result.msg)
        end
    end)

    local function pump()
        if coroutine.status(co) == "suspended" then
            local status, res = coroutine.resume(co)
            if not status then
                if loading_popup then UIManager:close(loading_popup) end
                logger.err("NotionSync Crash: " .. tostring(res))
                self:notify("Crash: " .. tostring(res))
            else
                UIManager:nextTick(pump)
            end
        end
    end
    UIManager:nextTick(pump)
end

return NotionSync