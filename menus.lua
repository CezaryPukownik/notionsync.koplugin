local Menus = {}

function Menus.register(plugin, menu_items)
    -- 1. The Quick Action (Top Level)
    menu_items.notion_quick_sync = {
        text = "Sync to Notion",
        callback = function()
            plugin:onSyncRequested()
        end
    }

    -- 2. The Configuration Menu (Inside "More tools" or similar)
    menu_items.notion_config = {
        text = "NotionSync Settings",
        sorting_hint = "more_tools",
        callback = function()
            plugin:showConfigMenu()
        end
    }
end

return Menus