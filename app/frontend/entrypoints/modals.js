let shippingMethodCountriesChoices, editShippingMethodCountriesChoices;

document.addEventListener('DOMContentLoaded', function() {
  setupModals();
  initializeShippingMethodChoices();
});

document.addEventListener('turbo:load', function() {
  setupModals();
  initializeShippingMethodChoices();
});

document.addEventListener('turbo:render', function() {
  setupModals();
  initializeShippingMethodChoices();
});

document.addEventListener('turbo:before-cache', cleanupShippingMethodChoices);
document.addEventListener('turbo:before-render', cleanupShippingMethodChoices);

function initializeShippingMethodChoices() {
  cleanupShippingMethodChoices();
  
  const shippingMethodCountriesEl = document.getElementById('shippingMethodCountries');
  if (shippingMethodCountriesEl && !shippingMethodCountriesEl.hasAttribute('data-choices-initialized')) {
    shippingMethodCountriesChoices = new Choices('#shippingMethodCountries', {
      searchEnabled: true,
      placeholder: true,
      placeholderValue: 'Select countries...',
      searchPlaceholderValue: 'Search countries...',
      noResultsText: 'No countries found',
      noChoicesText: 'No countries available',
      itemSelectText: 'Press to select',
      shouldSort: false,
      removeItemButton: true
    });
    shippingMethodCountriesEl.setAttribute('data-choices-initialized', 'true');
  }

  const editCountriesEl = document.getElementById('editCountries');
  if (editCountriesEl && !editCountriesEl.hasAttribute('data-choices-initialized')) {
    editShippingMethodCountriesChoices = new Choices('#editCountries', {
      searchEnabled: true,
      placeholder: true,
      placeholderValue: 'Select countries...',
      searchPlaceholderValue: 'Search countries...',
      noResultsText: 'No countries found',
      noChoicesText: 'No countries available',
      itemSelectText: 'Press to select',
      shouldSort: false,
      removeItemButton: true
    });
    editCountriesEl.setAttribute('data-choices-initialized', 'true');
  }

  loadShippingMethodCountriesData();
}

function cleanupShippingMethodChoices() {
  if (shippingMethodCountriesChoices) {
    try {
      shippingMethodCountriesChoices.destroy();
    } catch (e) {
      console.log('Error destroying shippingMethodCountriesChoices:', e);
    }
    shippingMethodCountriesChoices = null;
  }

  if (editShippingMethodCountriesChoices) {
    try {
      editShippingMethodCountriesChoices.destroy();
    } catch (e) {
      console.log('Error destroying editShippingMethodCountriesChoices:', e);
    }
    editShippingMethodCountriesChoices = null;
  }

  const elements = ['shippingMethodCountries', 'editCountries'];
  elements.forEach(id => {
    const el = document.getElementById(id);
    if (el) {
      el.removeAttribute('data-choices-initialized');
    }
  });
}

async function loadShippingMethodCountriesData() {
  try {
    const response = await fetch('https://restcountries.com/v3.1/all?fields=name,cca2');
    const countries = await response.json();
    
    const countryOptions = countries.map(country => ({
      value: country.cca2,
      label: `${country.name.common} (${country.cca2})`
    }));

    countryOptions.sort((a, b) => a.label.localeCompare(b.label));

    if (shippingMethodCountriesChoices) {
      shippingMethodCountriesChoices.setChoices(countryOptions, 'value', 'label', true);
    }
    if (editShippingMethodCountriesChoices) {
      editShippingMethodCountriesChoices.setChoices(countryOptions, 'value', 'label', true);
    }

  } catch (error) {
    console.error('Error loading countries:', error);
    loadFallbackShippingMethodCountries();
  }
}

function loadFallbackShippingMethodCountries() {
  const commonCountries = [
    { value: 'US', label: 'United States (US)' },
    { value: 'CA', label: 'Canada (CA)' },
    { value: 'MX', label: 'Mexico (MX)' },
    { value: 'GB', label: 'United Kingdom (GB)' },
    { value: 'AU', label: 'Australia (AU)' },
    { value: 'DE', label: 'Germany (DE)' },
    { value: 'FR', label: 'France (FR)' },
    { value: 'IT', label: 'Italy (IT)' },
    { value: 'ES', label: 'Spain (ES)' },
    { value: 'BR', label: 'Brazil (BR)' },
    { value: 'AR', label: 'Argentina (AR)' },
    { value: 'CL', label: 'Chile (CL)' },
    { value: 'CO', label: 'Colombia (CO)' },
    { value: 'PE', label: 'Peru (PE)' },
    { value: 'JP', label: 'Japan (JP)' },
    { value: 'CN', label: 'China (CN)' },
    { value: 'IN', label: 'India (IN)' },
    { value: 'KR', label: 'South Korea (KR)' },
    { value: 'SG', label: 'Singapore (SG)' },
    { value: 'NL', label: 'Netherlands (NL)' }
  ];

  if (shippingMethodCountriesChoices) {
    shippingMethodCountriesChoices.setChoices(commonCountries, 'value', 'label', true);
  }
  if (editShippingMethodCountriesChoices) {
    editShippingMethodCountriesChoices.setChoices(commonCountries, 'value', 'label', true);
  }
}

function setupModals() {
  document.addEventListener('click', function(e) {
    if (e.target && (e.target.id === 'addMethodBtn' || e.target.id === 'addMethodBtnEmpty')) {
      openAddMethodModal();
    }

    if (e.target && e.target.classList.contains('edit-method-btn')) {
      handleEditMethodClick(e.target);
    }

    if (e.target && e.target.classList.contains('disable-method-btn')) {
      handleDisableMethodClick(e.target);
    }
  });

  document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') {
      closeAllModals();
    }
  });
}

function openAddMethodModal() {
  const modal = document.getElementById('addMethodModal');
  if (modal) {
    modal.classList.remove('hidden');

    resetAddMethodForm();

    const addMethodForm = document.getElementById('addMethodForm');
    if (addMethodForm && !addMethodForm.hasAttribute('data-handler-added')) {
      addMethodForm.setAttribute('data-handler-added', 'true');
      addMethodForm.addEventListener('submit', function(e) {
        e.preventDefault();

        const formData = new FormData(this);

        const csrfToken = document.querySelector('meta[name="csrf-token"]').getAttribute('content');

        const submitBtn = this.querySelector('input[type="submit"]');
        const originalValue = submitBtn.value;
        submitBtn.value = 'Creating...';
        submitBtn.disabled = true;

        fetch('/shipping_options', {
          method: 'POST',
          body: formData,
          headers: {
            'X-CSRF-Token': csrfToken,
            'X-Requested-With': 'XMLHttpRequest'
          }
        })
        .then(response => {
          return response.json();
        })
        .then(data => {
          if (data.success) {
            closeAddMethodModal();
            window.location.reload();
          } else {
            showFormErrors(data.errors);
          }
        })
        .catch(error => {
          showFormErrors(['An unexpected error occurred. Please try again.']);
        })
        .finally(() => {
          submitBtn.value = originalValue;
          submitBtn.disabled = false;
        });
      });
    }
  }
}

function resetAddMethodForm() {
  const addMethodForm = document.getElementById('addMethodForm');
  if (addMethodForm) {
    const nameField = addMethodForm.querySelector('input[name="shipping_option[name]"]');
    const deliveryTimeField = addMethodForm.querySelector('input[name="shipping_option[delivery_time]"]');
    const startingRateField = addMethodForm.querySelector('input[name="shipping_option[starting_rate]"]');
    const statusField = addMethodForm.querySelector('select[name="shipping_option[status]"]');

    try {
      if (shippingMethodCountriesChoices) {
        shippingMethodCountriesChoices.setChoiceByValue([]);
      }
    } catch (e) {
      console.log('Error resetting shipping method countries choices:', e);
    }

    const existingErrors = document.getElementById('addMethodErrors');
    if (existingErrors) {
      existingErrors.remove();
    }
  }
}

function closeAddMethodModal() {
  const modal = document.getElementById('addMethodModal');
  if (modal) {
    modal.classList.add('hidden');

    const addMethodForm = document.getElementById('addMethodForm');
    if (addMethodForm) {
      addMethodForm.removeAttribute('data-handler-added');
    }
  }
}

function openEditMethodModal() {
  const modal = document.getElementById('editMethodModal');
  if (modal) {
    modal.classList.remove('hidden');
  }
}

function closeEditMethodModal() {
  const modal = document.getElementById('editMethodModal');
  if (modal) {
    modal.classList.add('hidden');
    try {
      if (editShippingMethodCountriesChoices) {
        editShippingMethodCountriesChoices.setChoiceByValue([]);
      }
    } catch (e) {
      console.log('Error resetting edit shipping method countries choices:', e);
    }
  }
}

function handleEditMethodClick(button) {
  const id = button.getAttribute('data-shipping-option-id');
  const name = button.getAttribute('data-shipping-option-name');
  const deliveryTime = button.getAttribute('data-shipping-option-delivery-time');
  const startingRate = button.getAttribute('data-shipping-option-starting-rate');
  const countries = button.getAttribute('data-shipping-option-countries');
  const status = button.getAttribute('data-shipping-option-status');

  const editShippingOptionId = document.getElementById('editShippingOptionId');
  const editName = document.getElementById('editName');
  const editDeliveryTime = document.getElementById('editDeliveryTime');
  const editStartingRate = document.getElementById('editStartingRate');
  const editCountries = document.getElementById('editCountries');
  const editStatus = document.getElementById('editStatus');
  const editMethodForm = document.getElementById('editMethodForm');

  if (editShippingOptionId) editShippingOptionId.value = id;
  if (editName) editName.value = name;
  if (editDeliveryTime) editDeliveryTime.value = deliveryTime;
  if (editStartingRate) editStartingRate.value = startingRate;
  if (editStatus) editStatus.value = status;

  if (countries && editShippingMethodCountriesChoices) {
    const countryArray = countries.split(',').map(c => c.trim()).filter(c => c);
    editShippingMethodCountriesChoices.setChoiceByValue(countryArray);
  }

  if (editMethodForm) {
    editMethodForm.action = `/shipping_options/${id}`;
    editMethodForm.method = 'POST';
  }

  openEditMethodModal();
}

function handleDisableMethodClick(button) {
  const id = button.getAttribute('data-shipping-option-id');
  const name = button.getAttribute('data-shipping-option-name');

  if (confirm(`Are you sure you want to disable "${name}"? This action cannot be undone.`)) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]').getAttribute('content');

    const formData = new FormData();
    formData.append('_method', 'PATCH');
    
    fetch(`/shipping_options/${id}/disable`, {
      method: 'POST',
      body: formData,
      headers: {
        'X-CSRF-Token': csrfToken
      }
    })
    .then(response => {
      if (response.ok) {
        window.location.reload();
      } else {
        throw new Error(`Failed to disable shipping method: ${response.status} ${response.statusText}`);
      }
    })
    .catch(error => {
      console.error('Error details:', error);
      alert('Failed to disable shipping method. Please check the console for details and try again.');
    });
  }
}

function showFormErrors(errors) {
  const existingErrors = document.getElementById('addMethodErrors');
  if (existingErrors) {
    existingErrors.remove();
  }
  
  const errorHtml = `
    <div id="addMethodErrors" class="bg-red-50 border border-red-200 rounded-xl p-4 mb-4">
      <div class="flex">
        <div class="flex-shrink-0">
          <i class="fa-solid fa-exclamation-triangle text-red-400"></i>
        </div>
        <div class="ml-3">
          <h3 class="text-sm font-medium text-red-800">
            ${errors.length} error${errors.length > 1 ? 's' : ''} prohibited this shipping method from being saved:
          </h3>
          <div class="mt-2 text-sm text-red-700">
            <ul class="list-disc list-inside space-y-1">
              ${errors.map(error => `<li>${error}</li>`).join('')}
            </ul>
          </div>
        </div>
      </div>
    </div>
  `;
  
  const form = document.getElementById('addMethodForm');
  if (form) {
    form.insertAdjacentHTML('afterbegin', errorHtml);
  }
}

function closeAllModals() {
  closeAddMethodModal();
  closeEditMethodModal();
  closeAddRateModal();
}

document.addEventListener('DOMContentLoaded', function() {
  const closeModal = document.getElementById('closeModal');
  const cancelBtn = document.getElementById('cancelBtn');
  if (closeModal) closeModal.addEventListener('click', closeAddMethodModal);
  if (cancelBtn) cancelBtn.addEventListener('click', closeAddMethodModal);

  const closeEditModal = document.getElementById('closeEditModal');
  const cancelEditBtn = document.getElementById('cancelEditBtn');
  if (closeEditModal) closeEditModal.addEventListener('click', closeEditMethodModal);
  if (cancelEditBtn) cancelEditBtn.addEventListener('click', closeEditMethodModal);

  const closeRateModal = document.getElementById('closeRateModal');
  const cancelRateBtn = document.getElementById('cancelRateBtn');
  if (closeRateModal) closeRateModal.addEventListener('click', closeAddRateModal);
  if (cancelRateBtn) cancelRateBtn.addEventListener('click', closeAddRateModal);

  document.addEventListener('click', function(e) {
    const addMethodModal = document.getElementById('addMethodModal');
    if (addMethodModal && e.target === addMethodModal) {
      closeAddMethodModal();
    }

    const editMethodModal = document.getElementById('editMethodModal');
    if (editMethodModal && e.target === editMethodModal) {
      closeEditMethodModal();
    }

    const addRateModal = document.getElementById('addRateModal');
    if (addRateModal && e.target === addRateModal) {
      closeAddRateModal();
    }
  });

  const editMethodForm = document.getElementById('editMethodForm');
  if (editMethodForm) {
    editMethodForm.addEventListener('submit', function(e) {
      e.preventDefault();
      
      const formData = new FormData(this);
      const id = document.getElementById('editShippingOptionId').value;
      
      const csrfToken = document.querySelector('meta[name="csrf-token"]').getAttribute('content');
      
      fetch(`/shipping_options/${id}`, {
        method: 'POST',
        body: formData,
        headers: {
          'X-CSRF-Token': csrfToken
        }
      })
      .then(response => {
        if (response.ok) {
          Turbo.visit(window.location.href, { action: 'replace' });
        } else {
          throw new Error(`Update failed: ${response.status} ${response.statusText}`);
        }
      })
      .catch(error => {
        console.error('Error details:', error);
        alert('Failed to update shipping method. Please check the console for details and try again.');
      });
    });
  }

  const addRateForm = document.getElementById('addRateForm');
  if (addRateForm) {
    addRateForm.addEventListener('submit', function(e) {
      e.preventDefault();
      
      const formData = new FormData(this);
      
      const csrfToken = document.querySelector('meta[name="csrf-token"]').getAttribute('content');
      
      fetch('/rates', {
        method: 'POST',
        body: formData,
        headers: {
          'X-CSRF-Token': csrfToken
        }
      })
      .then(response => {
        if (response.ok) {
          Turbo.visit(window.location.href, { action: 'replace' });
        } else {
          throw new Error(`Creation failed: ${response.status} ${response.statusText}`);
        }
      })
      .catch(error => {
        console.error('Error details:', error);
        alert('Failed to create rate table. Please check the console for details and try again.');
      });
    });
  }
});

