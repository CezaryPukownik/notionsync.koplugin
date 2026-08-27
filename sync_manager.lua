local logger = require("custom_logger")

local SyncManager = {}

-- 1. Helper: Clean Date (Human-readable: YYYY-MM-DD HH:MM:SS)
local function cleanDate(date_str)
    if not date_str then return nil end
    -- Replace 'T' with space for human readable format
    local iso = date_str:gsub("T", " "):gsub("%s+", " ")
    if not iso:find(" ") then
        -- If no space present (only date given), append " 00:00:00"
        iso = iso .. " 00:00:00"
    end
    -- Truncate to "YYYY-MM-DD HH:MM:SS"
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

--- Recover the page number from an existing block.
---
--- formatScholarBlock() writes a grey meta line containing "Page N", so the
--- number survives a round-trip through Notion. That is what lets a later sync
--- work out where a new highlight belongs among blocks it did not create.
--- Returns nil when the block predates that format or the page was unknown.
local function extractPageFromBlock(block)
    if not block or block.type ~= "quote" then return nil end
    if not block.quote or not block.quote.rich_text then return nil end
    for _, item in ipairs(block.quote.rich_text) do
        local content = item and item.text and item.text.content
        if content then
            local page = content:match("Page%s+(%d+)")
            if page then return tonumber(page) end
        end
    end
    return nil
end

--- Existing quote blocks, in the order Notion returns them (= page order).
local function collectQuoteBlocks(page_blocks)
    local quotes = {}
    for _, block in ipairs(page_blocks) do
        local hid = extractIdFromBlock(block)
        if hid then
            table.insert(quotes, {
                id = hid,
                block_id = block.id,
                page = extractPageFromBlock(block),
            })
        end
    end
    return quotes
end

--- The block a new highlight should sit after: the last existing quote whose
--- page is not beyond it. nil means it belongs before everything.
---
--- Blocks with no recoverable page are skipped rather than guessed at, so a
--- page written by an older version degrades to "append near the end" instead
--- of scattering new highlights around it.
local function findAnchor(existing, page)
    local anchor = nil
    for _, q in ipairs(existing) do
        if q.page and page and q.page <= page then
            anchor = q.block_id
        end
    end
    return anchor
end

--- Push `blocks` in chunks of 100 (the API cap), all at the same position.
local function appendChunked(client, page_id, blocks, opts, yield_func)
    local chunk = 100
    for i = 1, #blocks, chunk do
        local sub = {}
        for k = i, math.min(i + chunk - 1, #blocks) do table.insert(sub, blocks[k]) end
        -- Only the first chunk carries the position; the rest follow the ones
        -- just inserted, which is what a plain append already does.
        local this_opts = (i == 1) and opts or nil
        local _, err = client:appendBlockChildren(page_id, sub, this_opts)
        if err then return err end
        if yield_func then yield_func() end
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

    -- Fetch Database Schema to see which properties exist (Optional handling)
    local db_schema, db_err = client:getDatabase(client.database_id)
    local valid_props = {}
    if db_schema and db_schema.properties then
        valid_props = db_schema.properties
        -- DEBUG LOGGING: Print available properties in DB
        local props_list = ""
        for k, _ in pairs(valid_props) do props_list = props_list .. "'" .. k .. "', " end
        logger.info("NotionSync DB Columns: " .. props_list)
    else
        logger.warn("NotionSync: Could not fetch DB schema: " .. tostring(db_err))
    end
    
    -- Helper: Case-insensitive lookup
    local function getRealPropName(target)
        for k, _ in pairs(valid_props) do
            if k:lower() == target:lower() then 
                logger.info("NotionSync: Found column '" .. k .. "' for target '" .. target .. "'")
                return k 
            end
        end
        logger.warn("NotionSync: Column '" .. target .. "' NOT found in DB.")
        return nil
    end

    -- Prepare Properties (Only if they exist in DB)
    local extra_props = {}
    
    -- LOG PAYLOAD
    logger.info("NotionSync Payload: Pages=" .. tostring(payload.pages) .. ", Lang=" .. tostring(payload.language) .. ", Start=" .. tostring(payload.start_date))

    -- Helper to format value based on Notion Type
    local function formatValue(key, val_type, value)
        if not value or value == "" then return nil end
        
        if val_type == "rich_text" or val_type == "title" then
            return { rich_text = {{ text = { content = tostring(value) } }} }
        elseif val_type == "number" then
            return { number = tonumber(value) }
        elseif val_type == "select" then
            return { select = { name = tostring(value) } }
        elseif val_type == "multi_select" then
            -- If value is a simple string, make it a single tag, or split if it looks like a list
            local tags = {}
            -- Try splitting by semicolon for authors/lists
            local val_str = tostring(value)
            if val_str:find(";") then
                for part in string.gmatch(val_str, "([^;]+)") do
                     local clean = part:match("^%s*(.-)%s*$")
                     if clean and clean ~= "" then table.insert(tags, { name = clean }) end
                end
            else
                table.insert(tags, { name = val_str })
            end
            return { multi_select = tags }
        elseif val_type == "date" then
            -- Expects ISO YYYY-MM-DD
            local d = tostring(value):sub(1,10)
            if d:match("^%d%d%d%d%-%d%d%-%d%d$") then
                return { date = { start = d } }
            end
            return nil -- Invalid date for date column
        elseif val_type == "url" then
             return { url = tostring(value) }
        end
        return nil -- Unsupported type
    end

    local key_author = getRealPropName("Authors") or getRealPropName("Author")
    if payload.author and key_author then
        extra_props[key_author] = formatValue(key_author, valid_props[key_author].type, payload.author)
    end
    
    local key_isbn = getRealPropName("ISBN")
    if payload.isbn and key_isbn then
        extra_props[key_isbn] = formatValue(key_isbn, valid_props[key_isbn].type, payload.isbn)
    end
    
    local key_progress = getRealPropName("Progress")
    if payload.progress and key_progress then
        extra_props[key_progress] = formatValue(key_progress, valid_props[key_progress].type, payload.progress)
    end
    
    local key_language = getRealPropName("Language")
    if payload.language and key_language then
        extra_props[key_language] = formatValue(key_language, valid_props[key_language].type, payload.language)
    end
    
    local key_pages = getRealPropName("Pages")
    if payload.pages and payload.pages > 0 and key_pages then
        extra_props[key_pages] = formatValue(key_pages, valid_props[key_pages].type, payload.pages)
    end
    
    local key_start = getRealPropName("Start Reading")
    if payload.start_date and key_start then
        extra_props[key_start] = formatValue(key_start, valid_props[key_start].type, payload.start_date)
    end

    -- DEBUG: Log the full JSON payload
    pcall(function() 
        local json = require("json")
        logger.info("NotionSync FULL JSON: " .. json.encode(extra_props))
    end)

    local page_id
    local last_sync_raw = nil
    if page then
        page_id = page.id
        if page.properties["Last Sync"] and page.properties["Last Sync"].rich_text and #page.properties["Last Sync"].rich_text > 0 then
            last_sync_raw = page.properties["Last Sync"].rich_text[1].plain_text
        end
        
        -- UPDATE PROPERTIES for existing page
        if next(extra_props) ~= nil then
            client:updatePageProperties(page_id, extra_props)
        end
    else
        local new_p, c_err = client:createPage(title, extra_props)
        if not new_p then return { success = false, msg = tostring(c_err) } end
        page_id = new_p.id
    end
    if yield_func then yield_func() end

    -- Scan Page Blocks (Flat Scan - Much Faster)
    logger.info("NotionSync: Scanning blocks...")
    local page_blocks, bl_err = client:getBlockChildren(page_id)
    if not page_blocks then return { success = false, msg = tostring(bl_err) } end

    local existing_quotes = collectQuoteBlocks(page_blocks)
    local existing_ids = {}
    for _, q in ipairs(existing_quotes) do existing_ids[q.id] = q.block_id end
    
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
            if h_iso > last_sync_clean then
                -- Re-generate the full block content (text + footer + anchor)
                local updated_struct = formatScholarBlock(h)
                local rich_text_content = updated_struct.quote.rich_text
                
                client:updateBlock(existing_block_id, rich_text_content)
                count_updated = count_updated + 1
            end
        else
            -- NEW Highlight
            table.insert(batch_append, {
                block = formatScholarBlock(h),
                page = tonumber(h.page),
            })
            count_new = count_new + 1
        end
    end

    -- Insert New, in place rather than at the end.
    --
    -- payload.highlights arrives sorted by page, so items sharing an anchor are
    -- contiguous: walk them in runs and send one request per run. A page that
    -- has never been synced has no anchors at all and takes a single append.
    if #batch_append > 0 then
        local i = 1
        while i <= #batch_append do
            local anchor = findAnchor(existing_quotes, batch_append[i].page)

            local run = { batch_append[i].block }
            local j = i + 1
            while j <= #batch_append and findAnchor(existing_quotes, batch_append[j].page) == anchor do
                table.insert(run, batch_append[j].block)
                j = j + 1
            end

            local opts = nil
            if anchor then
                opts = { after = anchor }
            elseif #existing_quotes > 0 then
                -- Sorts ahead of every existing quote.
                opts = { before = existing_quotes[1].block_id }
            end

            local append_err = appendChunked(client, page_id, run, opts, yield_func)
            if append_err then return { success = false, msg = tostring(append_err) } end

            i = j
        end
    end

    -- Update Cursor
    if max_updated_at > last_sync_clean then
        client:updateLastSync(page_id, max_updated_at)
    end

    return { success = true, new = count_new, updated = count_updated }
end

--- Rewrite a book's page so its quotes sit in reading order.
---
--- Needed because the Notion API cannot move a block once it exists: a page
--- whose quotes were appended out of order can only be repaired by deleting
--- them and creating them again. Non-quote blocks are left untouched.
---
--- Refuses to run if the page holds a quote this device doesn't know about --
--- a highlight deleted locally but still in Notion, or one made on another
--- device that hasn't synced here yet. Deleting those would be silent data
--- loss, so the caller is told to sync first instead.
function SyncManager.rebuild(client, payload, yield_func)
    local title = payload.title
    logger.info("NotionSync: rebuild page order for " .. tostring(title))

    local page, err = client:findPage(title)
    if not page then
        return { success = false, msg = err and tostring(err) or "Page not found in Notion" }
    end
    local page_id = page.id

    local page_blocks, bl_err = client:getBlockChildren(page_id)
    if not page_blocks then return { success = false, msg = tostring(bl_err) } end
    if yield_func then yield_func() end

    local existing_quotes = collectQuoteBlocks(page_blocks)
    if #existing_quotes == 0 then
        return { success = false, msg = "No highlights on the Notion page yet -- run a sync first." }
    end

    local known = {}
    for _, h in ipairs(payload.highlights) do known[h.id] = true end

    local unknown = 0
    for _, q in ipairs(existing_quotes) do
        if not known[q.id] then unknown = unknown + 1 end
    end
    if unknown > 0 then
        return {
            success = false,
            msg = string.format(
                "%d highlight(s) on the Notion page are not in this book locally. "
                .. "Rebuilding would delete them. Sync first, or remove them in Notion.",
                unknown),
        }
    end

    local deleted = 0
    for _, q in ipairs(existing_quotes) do
        local _, del_err = client:deleteBlock(q.block_id)
        if del_err then
            return {
                success = false,
                msg = string.format("Deleted %d of %d blocks, then failed: %s. "
                    .. "Run the rebuild again to finish.", deleted, #existing_quotes, tostring(del_err)),
            }
        end
        deleted = deleted + 1
        if yield_func then yield_func() end
    end

    local blocks = {}
    for _, h in ipairs(payload.highlights) do
        table.insert(blocks, formatScholarBlock(h))
    end

    local append_err = appendChunked(client, page_id, blocks, nil, yield_func)
    if append_err then
        return {
            success = false,
            msg = "Blocks were removed but re-adding them failed: " .. tostring(append_err)
                .. ". Run a sync to restore them.",
        }
    end

    logger.info(string.format("NotionSync: rebuild done removed=%d added=%d", deleted, #blocks))
    return { success = true, removed = deleted, added = #blocks }
end

return SyncManager
