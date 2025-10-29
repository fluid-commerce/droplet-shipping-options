# frozen_string_literal: true

# Pagy initializer file (9.4.0)
# Customize only what you really need and notice that the arrays/hashes are frozen.

# Default page size
Pagy::DEFAULT[:limit] = 20

# Better user experience handled automatically
require "pagy/extras/overflow"
Pagy::DEFAULT[:overflow] = :last_page

# Enable i18n
require "pagy/extras/i18n"
