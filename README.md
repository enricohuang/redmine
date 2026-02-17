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

## Fork Information

This repository is forked from the official Redmine project at commit `856a80eca` ("Add test for #43801.").

## Original Redmine

For more information about Redmine, visit:

- [Official Redmine Repository](https://github.com/redmine/redmine)
- [Redmine Official Website](https://www.redmine.org)
- [Redmine Documentation](https://www.redmine.org/guide)
