import "controllers"

// Bootstrap 5.3 JavaScript initialization
import * as bootstrap from "bootstrap"

// Make Bootstrap available globally for compatibility
window.bootstrap = bootstrap

// Initialize Bootstrap components on Turbo navigation
document.addEventListener("turbo:load", () => {
  // Initialize all tooltips
  const tooltipTriggerList = document.querySelectorAll('[data-bs-toggle="tooltip"]')
  tooltipTriggerList.forEach(el => new bootstrap.Tooltip(el))

  // Initialize all popovers
  const popoverTriggerList = document.querySelectorAll('[data-bs-toggle="popover"]')
  popoverTriggerList.forEach(el => new bootstrap.Popover(el))
})

// Also initialize on regular page load
document.addEventListener("DOMContentLoaded", () => {
  // Initialize all tooltips
  const tooltipTriggerList = document.querySelectorAll('[data-bs-toggle="tooltip"]')
  tooltipTriggerList.forEach(el => new bootstrap.Tooltip(el))

  // Initialize all popovers
  const popoverTriggerList = document.querySelectorAll('[data-bs-toggle="popover"]')
  popoverTriggerList.forEach(el => new bootstrap.Popover(el))
})
