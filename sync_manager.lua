local logger = require("logger")

local SyncManager = {}

-- 1. Helper: Clean Date (Strict comparison)
local function cleanDate(date_str)
    if not date_str then return nil end
    local iso = date_str:gsub(" ", "T")
    if not iso:find("T") then iso = iso .. "T00:00:00" end
    return iso:sub(1, 19)
end

-- Format Block with Inline Anchor
local function formatScholarBlock(h)
    local content = {}
    
    -- Main Text
    table.insert(content, { text = { content = h.text } })
    
    -- Metadata Line (Soft break \n)
    local meta = "\n"
    
    -- Add Chapter if it exists
    if h.chapter and h.chapter ~= "" then
        meta = meta .. h.chapter .. " • "
    end
    
    meta = meta .. string.format("Page %s • %s", h.page or "?", cleanDate(h.updated_at))
    
    if h.note and h.note ~= "" then 
        -- Bold the "Note:" label for visibility
        meta = meta .. " • Note: " .. h.note 
    end
    
    table.insert(content, { 
        text = { content = meta },
        annotations = { color = "gray", italic = true }
    })

    -- The ID Anchor (Hidden)
    table.insert(content, { text = { content = "  " } })
    table.insert(content, {
        text = { 
            content = "⚓", 
            link = { url = "https://ref.koreader/" .. h.id } 
        },
        annotations = { color = "gray" }
    })

    return {
        object = "block",
        type = "quote",
        quote = {
            rich_text = content
        }
    }
end

-- Extract ID from block
local function extractIdFromBlock(block)
    if not block or block.type ~= "quote" then return nil end
    if not block.quote or not block.quote.rich_text then return nil end
    
    local rt = block.quote.rich_text
    
    for i = #rt, 1, -1 do
        local item = rt[i]
        if item and item.type == "text" and item.text then
            local link = item.text.link
            if link and type(link) == "table" and link.url then
                local url = link.url
                local id = url:match("koreader/(.+)")
                if id then return id end
            end
        end
    end
    return nil
end

function SyncManager.sync(client, payload, notify_func, yield_func)
    local title = payload.title
    logger.info("NotionSync: " .. title)
    if yield_func then yield_func() end

    -- Find/Create Page
    local page, err = client:findPage(title)
    if not page and err then return { success = false, msg = tostring(err) } end

    local page_id
    local last_sync_raw = nil
    if page then
        page_id = page.id
        if page.properties["Last Sync"] and page.properties["Last Sync"].rich_text and #page.properties["Last Sync"].rich_text > 0 then
            last_sync_raw = page.properties["Last Sync"].rich_text[1].plain_text
        end
    else
        local new_p, c_err = client:createPage(title)
        if not new_p then return { success = false, msg = tostring(c_err) } end
        page_id = new_p.id
    end
    if yield_func then yield_func() end

    -- Scan Page Blocks (Flat Scan - Much Faster)
    logger.info("NotionSync: Scanning blocks...")
    local page_blocks, bl_err = client:getBlockChildren(page_id)
    if not page_blocks then return { success = false, msg = tostring(bl_err) } end

    local existing_ids = {} 
    for _, block in ipairs(page_blocks) do
        local hid = extractIdFromBlock(block)
        if hid then existing_ids[hid] = block.id end
    end
    
    if yield_func then yield_func() end

    -- Process Highlights
    local last_sync_clean = cleanDate(last_sync_raw) or "1970-01-01T00:00:00"
    local max_updated_at = last_sync_clean
    local count_new = 0
    local count_updated = 0
    local batch_append = {}

    for _, h in ipairs(payload.highlights) do
        local h_iso = cleanDate(h.updated_at)
        
        -- Track the latest updated highlight to update the cursor
        if h_iso > max_updated_at then 
            max_updated_at = h_iso 
        end

        local existing_block_id = existing_ids[h.id]

        if existing_block_id then
            -- UPDATE Existing
            logger.info("NotionSync: Last sync: " .. last_sync_clean)
            logger.info("NotionSync: Last sync: " .. h_iso)
            if h_iso > last_sync_clean then
                -- Re-generate the full block content (text + footer + anchor)
                local updated_struct = formatScholarBlock(h)
                local rich_text_content = updated_struct.quote.rich_text
                
                client:updateBlock(existing_block_id, rich_text_content)
                count_updated = count_updated + 1
            end
        else
            -- NEW Highlight
            table.insert(batch_append, formatScholarBlock(h))
            count_new = count_new + 1
        end
    end

    -- Append New
    if #batch_append > 0 then
        local chunk = 100
        for i=1, #batch_append, chunk do
            local sub = {}
            for k=i, math.min(i+chunk-1, #batch_append) do table.insert(sub, batch_append[k]) end
            
            local _, append_err = client:appendBlockChildren(page_id, sub)
            if append_err then return { success = false, msg = tostring(append_err) } end
            
            if yield_func then yield_func() end
        end
    end

    -- Update Cursor
    if max_updated_at > last_sync_clean then
        client:updateLastSync(page_id, max_updated_at)
    end

    return { success = true, new = count_new, updated = count_updated }
end

return SyncManager