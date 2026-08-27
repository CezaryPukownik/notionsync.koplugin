local Menus = {}

function Menus.register(plugin, menu_items)
    -- Create NotionSync submenu on first page of tools
    menu_items.notion_sync_menu = {
        text = "NotionSync",
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = "Sync Highlights to Notion",
                callback = function()
                    plugin:onSyncRequested()
                end
            },
            {
                text = "Sync All Highlights to Notion",
                callback = function()
                    plugin:onSyncAllBooksRequested()
                end
            },
            {
                text = "Auto-sync on book close",
                checked_func = function()
                    return G_reader_settings:isTrue("notionsync_auto_sync_on_close")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("notionsync_auto_sync_on_close")
                end,
                help_text = "Sync the book you just closed, automatically. Runs only when Wi-Fi is already on -- closing a book never switches the radio on by itself, and an offline close is skipped silently. Repeat closes of the same book are rate-limited to one sync every 5 minutes.",
            },
            {
                text = "Auto-sync on sleep",
                checked_func = function()
                    return G_reader_settings:isTrue("notionsync_auto_sync_on_suspend")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("notionsync_auto_sync_on_suspend")
                end,
                help_text = "Sync the open book when the device goes to sleep -- the sleep button, or auto-standby. Runs only when Wi-Fi is already on; sleeping never switches the radio on by itself. Shares the 5-minute rate limit with the close trigger, so locking right after closing a book does not sync twice.",
            },
            {
                text = "Settings",
                callback = function()
                    plugin:showConfigMenu()
                end
            }
        }
    }
end

return Menus