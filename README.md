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

### Rails 8.1+ Compatibility

Fixed deprecated timezone configuration for Rails 8.1+ compatibility while maintaining backward compatibility with earlier Rails versions.

## Documentation

For detailed documentation, see the [Wiki](https://github.com/enricohuang/redmine/wiki):

- [Webhooks REST API Reference](https://github.com/enricohuang/redmine/wiki/Webhooks-REST-API) - Complete API documentation
- [Webhooks Use Cases](https://github.com/enricohuang/redmine/wiki/Webhooks-Use-Cases) - Integration examples and design rationale

## Fork Information

This repository is forked from the official Redmine project at commit `856a80eca` ("Add test for #43801.").

## Original Redmine

For more information about Redmine, visit:

- [Official Redmine Repository](https://github.com/redmine/redmine)
- [Redmine Official Website](https://www.redmine.org)
- [Redmine Documentation](https://www.redmine.org/guide)
