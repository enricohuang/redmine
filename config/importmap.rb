# frozen_string_literal: true

# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "turndown" # @7.2.0
pin_all_from "app/javascript/controllers", under: "controllers"
pin "tablesort", to: "tablesort.min.js"
pin "tablesort.number", to: "tablesort.number.min.js"

# Bootstrap 5.3 JavaScript modules
pin "@popperjs/core", to: "https://cdn.jsdelivr.net/npm/@popperjs/core@2.11.8/dist/esm/popper.min.js"
pin "bootstrap", to: "https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.esm.min.js"
