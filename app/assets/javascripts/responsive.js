/**
 * Redmine - project management software
 * Copyright (C) 2006-  Jean-Philippe Lang
 * This code is released under the GNU General Public License.
 */

// Bootstrap offcanvas integration for mobile menu
// Copies sidebar and main menu content into the offcanvas panel

$(document).ready(function() {
  var flyoutMenu = document.getElementById('flyoutMenu');
  if (!flyoutMenu) return;

  flyoutMenu.addEventListener('show.bs.offcanvas', function() {
    // Copy main menu into offcanvas project menu slot
    var mainMenu = document.querySelector('#main-menu > ul');
    var projectSlot = flyoutMenu.querySelector('.js-project-menu');
    if (mainMenu && projectSlot) {
      var clone = mainMenu.cloneNode(true);
      clone.classList.add('nav', 'flex-column');
      // Style links for offcanvas
      clone.querySelectorAll('a').forEach(function(a) {
        a.classList.add('nav-link');
      });
      projectSlot.innerHTML = '';
      projectSlot.appendChild(clone);
    }

    // Copy sidebar content into offcanvas sidebar slot
    var sidebarWrapper = document.getElementById('sidebar-wrapper');
    var sidebarSlot = flyoutMenu.querySelector('.offcanvas-sidebar');
    if (sidebarWrapper && sidebarSlot) {
      sidebarSlot.innerHTML = sidebarWrapper.innerHTML;
    }
  });

  flyoutMenu.addEventListener('hidden.bs.offcanvas', function() {
    // Clear cloned content to avoid stale data
    var projectSlot = flyoutMenu.querySelector('.js-project-menu');
    if (projectSlot) projectSlot.innerHTML = '';

    var sidebarSlot = flyoutMenu.querySelector('.offcanvas-sidebar');
    if (sidebarSlot) sidebarSlot.innerHTML = '';
  });
});
