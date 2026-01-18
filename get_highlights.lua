local md5 = require("ffi/sha2").md5

local GetHighlights = {}

-- Process the document and return a payload of book metadata and highlights
function GetHighlights.transform(doc, raw_annotations)
    if not doc then return nil, "No document" end
    if not raw_annotations or next(raw_annotations) == nil then return nil, "No annotations" end

    -- 1. Get Book Metadata
    local props = doc:getProps()
    local book_title = props.title or "Unknown Title"
    local book_author = props.authors or "Unknown Author"
    local file_path = doc.file or ""

    -- 2. Transform Data
    local clean_highlights = {}
    
    for _, item in pairs(raw_annotations) do
        -- Generate ID: md5(filepath + datetime)
        local created_at = item.datetime or ""
        local id_source = file_path .. created_at
        local unique_id = md5(id_source)

        -- Handle Updated At logic
        local updated_at = item.datetime_updated
        if not updated_at or updated_at == "" then
            updated_at = created_at
        end

        local entry = {
            id = unique_id,
            chapter = item.chapter or "",
            text = item.text or "",
            page = item.pageno or item.page,
            note = item.note,
            created_at = created_at,
            updated_at = updated_at
        }

        table.insert(clean_highlights, entry)
    end

    -- 3. Return Final Payload
    return {
        author = book_author,
        title = book_title,
        highlights = clean_highlights
    }
end

return GetHighlights