# NotionSync for KOReader

**NotionSync** is a powerful plugin for **KOReader** that automatically synchronizes your book highlights and notes directly to a **Notion database**. 

---

## ✨ Features

- 📚 **Rich Metadata Sync**  (New!)
  Automatically populates the following fields in your Notion database (if columns exist), they're:
  - **Authors** (Supports `Multi-select` tags or `Text`)
  - **ISBN** (Robust extraction from book files)
  - **Progress** (Real-time reading percentage, derived from book stats or metadata)
  - **Language** (e.g., "en", "es")
  - **Pages** (Total page count)
  - **Start Reading** (Date you started the book)

- 🔄 **Smart & Robust Sync**  
  - **Dynamic Schema Detection**: The plugin checks your Notion database types before syncing.
  - **Crash-Proof**: If a column is missing or has the wrong type (e.g., "Pages" is text instead of number), the plugin adapts its payload automatically to prevent errors.
  - **Live Progress**: Calculates reading progress live from the document, falling back to disk metadata if needed.

- 📝 **Rich Formatting**  
  Highlights are formatted as "Scholar blocks" (Quote style) including page number, chapter, date, and a hidden link to the highlight anchor.

- ⚡ **One-Click Sync**  
  Integrated directly into the KOReader **Tools** menu. Supports gesture triggers.

---

## 🛠️ Notion Setup

For the best experience, create a Notion Database with the following columns. **All metadata columns are optional**—if you don't add them, the plugin simply skips them.

| Property Name | Verified Types | Description |
|--------------|-------|-------------|
| **Name**     | Title | **Required**. Book title. |
| **Last Sync**| Text  | **Required**. Used to track updates. |
| **Authors**  | Multi-select *or* Text | Smart splitting of multiple authors (e.g. "Author A; Author B"). |
| **ISBN**     | Text  | The book's ISBN. |
| **Progress** | Number *or* Text | Reading percentage (0.0 to 1.0). Best formatted as `%` in Notion. |
| **Language** | Select *or* Text | Language code (e.g., `en`). |
| **Pages**    | Number *or* Text | Total pages in the book. |
| **Start Reading** | Date | Date the book was first opened/highlighted. |

> **Note**: Column names in Notion Database are **case-insensitive** (e.g., "progress", "Progress", "PROGRESS" all work).

---

## 🚀 Installation

### 1. Download
Download the latest `notionsync.koplugin.zip` from the **Releases** page (or clone this repo).

### 2. Install on Device
1. Connect your KOReader device via USB.
2. Navigate to `koreader/plugins/`.
3. Extract the `notionsync.koplugin` folder there.

### 3. Restart KOReader
Eject and restart your device.

---

## ⚙️ Configuration

1. **Get Notion Token**: Go to [Notion My Integrations](https://www.notion.so/my-integrations), create a new integration, and copy the Secret (`ntn_...`).
2. **Connect Database**: Open your Notion Database page -> **... (menu)** -> **Connect to** -> Select your integration.
3. **Configure on Device**:
   - Open any book in KOReader.
   - Go to **Tools (Gear/Wrench)** -> (Page 2) -> **More tools** -> **NotionSync Settings**.
   - **Set Notion Token**: Enter your key.
   - **Select Database**: Pick your database from the list.

---

## 📖 Usage

### Manual Sync
1. Open a book.
2. Go to **Book Menu** (second tab usually).
3. Tap **Sync to Notion**.
4. Watch the magic happen! 

### Gesture Sync
You can assign "Sync to Notion" to a corner tap in **Settings -> Taps and gestures -> Gesture manager**.

---

## ❓ Troubleshooting

- **"HTTP 400 Bad Request"**:
  - This usually means a mismatch between data sent and Notion's expectations.

- **Missing Progress/Metadata?**:
  - Ensure the column names in Notion match (e.g., "Authors", "ISBN").
  - Check `notion_debug.log` to see if the plugin found the values (search for `NotionSync Payload`).

---

## 📄 License & Credits
Licensed under **MIT**.
Based on the original work of [previous authors], significantly enhanced with metadata extraction and robust syncing capabilities.
