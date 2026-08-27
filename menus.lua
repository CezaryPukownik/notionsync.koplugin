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
                text = "Rebuild page order",
                callback = function()
                    plugin:onRebuildPageOrder()
                end,
                help_text = "Deletes and recreates this book's quote blocks so they sit in reading order. Only needed for pages built before ordered inserts -- the Notion API cannot move an existing block. Text is restored from this device; Notion comments on those blocks are not.",
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
                text = "Settings",
                callback = function()
                    plugin:showConfigMenu()
                end
            }
        }
    }
end

return Menus