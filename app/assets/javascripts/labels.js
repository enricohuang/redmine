/**
 * Redmine Labels
 * JavaScript for issue labels feature - tag input widget
 */

document.addEventListener('DOMContentLoaded', function() {

  // ========== Color picker live preview (label form) ==========
  var colorInput = document.getElementById('label-color-input');
  var nameInput = document.getElementById('label-name-input');
  var preview = document.getElementById('label-preview');

  if (colorInput && preview) {
    colorInput.addEventListener('input', function() {
      var color = colorInput.value;
      preview.style.backgroundColor = color;
      preview.style.color = textColor(color);
    });
  }

  if (nameInput && preview) {
    nameInput.addEventListener('input', function() {
      preview.textContent = nameInput.value || 'Preview';
    });
  }

  function textColor(hex) {
    var r = parseInt(hex.substr(1, 2), 16);
    var g = parseInt(hex.substr(3, 2), 16);
    var b = parseInt(hex.substr(5, 2), 16);
    var luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;
    return luminance > 0.5 ? '#000000' : '#FFFFFF';
  }

  // ========== Tag Input Widget ==========
  if (typeof jQuery === 'undefined' || !jQuery.ui || !jQuery.ui.autocomplete) return;

  $('.tag-input-container').each(function() {
    initTagInput($(this));
  });

  function initTagInput($container) {
    var allLabels     = $container.data('labels') || [];
    var assignedIds   = $container.data('assigned') || [];
    var createUrl     = $container.data('create-url') || '';
    var allowCreate   = ($container.data('allow-create') === true || $container.data('allow-create') === 'true');
    var placeholderText = $container.data('placeholder') || '';
    var createTextTpl = $container.data('create-text') || "Create '%{name}'";
    var noResultsText = $container.data('no-results-text') || 'No matching labels';

    var $badges       = $container.find('.tag-input-badges');
    var $input        = $container.find('.tag-input-field');
    var $hiddenFields = $container.find('.tag-input-hidden-fields');

    // Build lookup map
    var labelMap = {};
    allLabels.forEach(function(l) { labelMap[l.id] = l; });

    // Track selected IDs
    var selectedIds = assignedIds.slice();

    // ---------- Badge rendering ----------

    // Attach remove handlers to server-rendered badges
    $badges.find('.tag-remove').on('click', function(e) {
      e.preventDefault();
      e.stopPropagation();
      var $badge = $(this).closest('.badge-label-tag');
      var id = parseInt($badge.data('label-id'), 10);
      removeLabel(id);
    });

    function addBadge(label) {
      var $badge = $('<span class="badge label-badge badge-label-tag"></span>')
        .attr('data-label-id', label.id)
        .css({ 'background-color': label.color, 'color': label.textColor })
        .text(label.name);

      var $remove = $('<span class="tag-remove" title="Remove">&times;</span>');
      $remove.on('click', function(e) {
        e.preventDefault();
        e.stopPropagation();
        removeLabel(label.id);
      });
      $badge.append($remove);
      $badges.append($badge);
    }

    function removeBadge(id) {
      $badges.find('[data-label-id="' + id + '"]').remove();
    }

    // ---------- Hidden field management ----------

    function addHiddenField(id) {
      var $field = $('<input type="hidden" name="issue[label_ids][]" />')
        .val(id)
        .attr('data-label-id', id);
      $hiddenFields.append($field);
    }

    function removeHiddenField(id) {
      $hiddenFields.find('input[data-label-id="' + id + '"]').remove();
    }

    // ---------- Add / Remove logic ----------

    function addLabel(label) {
      if (selectedIds.indexOf(label.id) !== -1) return;
      selectedIds.push(label.id);
      addBadge(label);
      addHiddenField(label.id);
      $input.val('');
    }

    function removeLabel(id) {
      var idx = selectedIds.indexOf(id);
      if (idx !== -1) selectedIds.splice(idx, 1);
      removeBadge(id);
      removeHiddenField(id);
      $input.focus();
    }

    // ---------- jQuery UI Autocomplete ----------

    $input.autocomplete({
      minLength: 0,
      delay: 0,
      position: { collision: 'flipfit' },

      source: function(request, response) {
        var term = request.term.toLowerCase().trim();
        var results = [];

        allLabels.forEach(function(label) {
          if (selectedIds.indexOf(label.id) !== -1) return;
          if (term === '' || label.name.toLowerCase().indexOf(term) !== -1) {
            results.push({
              label: label.name,
              value: label.name,
              labelObj: label,
              type: 'existing'
            });
          }
        });

        // "Create" option if no exact match
        if (allowCreate && term.length > 0) {
          var exactMatch = results.some(function(r) {
            return r.labelObj.name.toLowerCase() === term;
          });
          if (!exactMatch) {
            results.push({
              label: createTextTpl.replace('%{name}', request.term.trim()),
              value: request.term.trim(),
              type: 'create'
            });
          }
        }

        if (results.length === 0) {
          results.push({
            label: noResultsText,
            value: '',
            type: 'none'
          });
        }

        response(results);
      },

      select: function(event, ui) {
        event.preventDefault();
        if (ui.item.type === 'none') return false;

        if (ui.item.type === 'existing') {
          addLabel(ui.item.labelObj);
        } else if (ui.item.type === 'create') {
          createLabelInline(ui.item.value);
        }
        return false;
      },

      focus: function(event, ui) {
        event.preventDefault();
        return false;
      }
    });

    // Custom item rendering
    $input.autocomplete('instance')._renderItem = function(ul, item) {
      var $li = $('<li>');
      if (item.type === 'existing') {
        var $badge = $('<span class="badge label-badge"></span>')
          .css({ 'background-color': item.labelObj.color, 'color': item.labelObj.textColor })
          .text(item.labelObj.name);
        $li.append($('<div>').append($badge));
      } else if (item.type === 'create') {
        $li.append($('<div>').append(
          $('<span class="tag-input-create-option"></span>').text(item.label)
        ));
      } else if (item.type === 'none') {
        $li.addClass('ui-state-disabled');
        $li.append($('<div>').text(item.label));
      }
      return $li.appendTo(ul);
    };

    // Add custom class to autocomplete menu
    $input.autocomplete('widget').addClass('tag-input-autocomplete');

    // Open dropdown on focus
    $input.on('focus', function() {
      $input.autocomplete('search', $input.val());
    });

    // Keyboard: Backspace removes last badge when input is empty
    $input.on('keydown', function(e) {
      if (e.keyCode === 8 /* BACKSPACE */ && $input.val() === '') {
        var lastId = selectedIds[selectedIds.length - 1];
        if (lastId !== undefined) {
          removeLabel(lastId);
        }
      }
    });

    // Click on container focuses input
    $container.on('click', function(e) {
      if (!$(e.target).closest('.tag-remove').length && !$(e.target).closest('.badge-label-tag').length) {
        $input.focus();
      }
    });

    // ---------- Inline creation via AJAX ----------

    function createLabelInline(name) {
      if (!allowCreate || !createUrl) return;

      var csrfToken = $('meta[name="csrf-token"]').attr('content');

      $input.prop('disabled', true).val('');

      $.ajax({
        url: createUrl,
        method: 'POST',
        dataType: 'json',
        data: { name: name },
        headers: { 'X-CSRF-Token': csrfToken },
        success: function(data) {
          var newLabel = {
            id: data.id,
            name: data.name,
            color: data.color,
            textColor: data.text_color
          };
          allLabels.push(newLabel);
          labelMap[newLabel.id] = newLabel;
          addLabel(newLabel);
          $input.prop('disabled', false).focus();
        },
        error: function(xhr) {
          var msg = 'Error creating label';
          try {
            var resp = JSON.parse(xhr.responseText);
            if (resp.errors) msg = resp.errors.join(', ');
          } catch(e) {}
          alert(msg);
          $input.prop('disabled', false).focus();
        }
      });
    }
  }
});
