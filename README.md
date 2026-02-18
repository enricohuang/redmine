# Redmine Fork

This is a fork of [Redmine](https://github.com/redmine/redmine) with additional features and improvements.

Redmine is a flexible project management web application written using the Ruby on Rails framework.

## Additional Features

### Webhooks REST API

Full CRUD REST API for managing webhooks programmatically, enabling CI/CD integration and automation workflows.

- Create, read, update, and delete webhooks via API
- JSON and XML response formats
- HMAC-SHA256 signature verification for secure payload delivery
- Support for multiple event types (issues, wiki pages, time entries, news, versions)

### Journals REST API

Dedicated API endpoints for managing issue comments/journals directly.

- List journals for an issue with pagination
- Get single journal details
- Create comments directly via API (no need to update issue)
- Update comments with proper response data
- Private notes support

### Wiki REST API

Enhanced Wiki API with new endpoints for advanced wiki management.

- Page history listing with pagination
- Page rename with redirect support
- Page protection toggle
- Protected status in API responses
- Index pagination for large wikis

### Labels (Issue Tags)

Built-in label/tag system for issues with colored badges.

- Project-scoped colored labels with automatic contrast text
- Modern tag-input widget with autocomplete and inline label creation
- Labels column and filter in issue lists
- Bulk edit support for multiple issues
- CSV export support
- REST API for label management

### Mermaid Diagrams

Built-in support for rendering Mermaid.js diagrams in Markdown content.

- Write diagrams in fenced code blocks with `mermaid` language tag
- Automatic rendering in issues, wiki pages, and comments
- Supports all Mermaid.js v11 diagram types:
  - Flowcharts
  - Sequence diagrams
  - Class diagrams
  - State diagrams
  - Entity relationship diagrams
  - Pie charts
  - Gantt charts
  - Git graphs
  - And more...
- Lazy loading - only downloads Mermaid.js when diagrams are present
- No additional plugins required

### Attachment Fulltext Indexing API

REST API for external indexers to extract and store fulltext content from attachments (PDFs, Word docs, etc.), enabling search within file contents.

- **Dedicated API** - Separate API key for indexer access (`attachment_indexer_api_key`)
- **List pending attachments** - `GET /attachments/fulltext.json?status=pending`
- **Get fulltext status** - `GET /attachments/:id/fulltext.json`
- **Update fulltext content** - `PATCH /attachments/:id/fulltext.json`
- **Batch updates** - `POST /attachments/fulltext/batch.json`
- **Search integration** - Fulltext content searchable via standard Redmine search
- **Elasticsearch support** - Fulltext content included in ES documents

Supported file types for indexing:
- PDF, Word (.doc, .docx), Excel (.xls, .xlsx), PowerPoint (.ppt, .pptx)
- OpenDocument formats (.odt, .ods, .odp)
- Text files (.txt, .md, .csv, .xml, .json, .html, .rtf)

To enable:
1. Go to Administration > Settings > API
2. Enable "Attachment fulltext indexer API"
3. Set "Attachment fulltext indexer API key"
4. Use the key in `X-Redmine-Indexer-Key` header

### Modern Search UI

Redesigned search results with a modern card-based layout for improved visual hierarchy and usability.

- **Card-based results** - Each result displayed as a clean card with hover effects
- **Type badges** - Color-coded badges for content types:
  - Issues: Blue (Bug: Red, Feature: Green, Support: Orange)
  - Wiki pages: Orange
  - News: Purple
  - Documents: Teal
  - Changesets: Gray
  - Projects: Amber
- **Status pills** - For issues: New (green), In Progress (blue), Resolved (purple), Closed (gray)
- **Relative timestamps** - "about 2 hours ago", "1 day ago" with full date on hover
- **Attachment indicators** - Icon with count for results with attachments
- **Sidebar filters** - Filter by type, search options, attachment settings in collapsible panels
- **Keyboard navigation** - Press `j`/`k` to navigate results, `Enter` to open, `/` to focus search
- **Responsive design** - Adapts to mobile screens with collapsible sidebar

### Elasticsearch Search (Optional)

Full-text search powered by Elasticsearch for faster, more powerful search capabilities.

- **Advanced Search page** - Dedicated search page with more options when ES is enabled:
  - Search in all fields, titles only, or content only
  - Filter by content types, date range, and projects
  - Sort by relevance, date, or last updated
  - Faceted results showing counts by type and project
  - Relevance scores displayed for each result
- **All searchable content** - Issues, wiki pages, news, messages, changesets, documents, projects
- **Permission-aware** - Respects all Redmine permissions (private issues, project membership, etc.)
- **Highlighted results** - Search terms highlighted in yellow
- **Fallback support** - Falls back to database search if Elasticsearch unavailable
- **Easy setup** - Configure connection in `config/elasticsearch.yml`

To enable:
1. Install Elasticsearch 8.x
2. Run `bundle exec rake redmine:elasticsearch:create_index`
3. Run `bundle exec rake redmine:elasticsearch:reindex_all`

### Rails 8.1+ Compatibility

Fixed deprecated timezone configuration for Rails 8.1+ compatibility while maintaining backward compatibility with earlier Rails versions.

## Documentation

For detailed documentation, see the [Wiki](https://github.com/enricohuang/redmine/wiki):

- [Labels Feature Overview](https://github.com/enricohuang/redmine/wiki/Labels) - Labels documentation and usage guide
- [Labels REST API Reference](https://github.com/enricohuang/redmine/wiki/Labels-REST-API) - Label management API
- [Mermaid Diagrams](https://github.com/enricohuang/redmine/wiki/Mermaid-Diagrams) - Diagram syntax and examples
- [Webhooks REST API Reference](https://github.com/enricohuang/redmine/wiki/Webhooks-REST-API) - Complete API documentation
- [Webhooks Use Cases](https://github.com/enricohuang/redmine/wiki/Webhooks-Use-Cases) - Integration examples and design rationale
- [Journals REST API Reference](https://github.com/enricohuang/redmine/wiki/Journals-REST-API) - Comment management API
- [Wiki REST API Reference](https://github.com/enricohuang/redmine/wiki/Wiki-REST-API) - Wiki page management API
- [Elasticsearch Search](https://github.com/enricohuang/redmine/wiki/Elasticsearch-Search) - Setup, configuration, and limitations
- [Search User Guide](https://github.com/enricohuang/redmine/wiki/User-Guide-Search) - Search features and keyboard shortcuts
- [Attachment Fulltext Indexing API](https://github.com/enricohuang/redmine/wiki/Attachment-Fulltext-Indexing-API) - External indexer integration

## Fork Information

This repository is forked from the official Redmine project at commit `856a80eca` ("Add test for #43801.").

## Original Redmine

For more information about Redmine, visit:

- [Official Redmine Repository](https://github.com/redmine/redmine)
- [Redmine Official Website](https://www.redmine.org)
- [Redmine Documentation](https://www.redmine.org/guide)
