// Modals functionality for Shipping Options
document.addEventListener('DOMContentLoaded', function() {
  setupModals();
});

// Global event delegation for all modals
function setupModals() {
  // Global click handler for all modal buttons
  document.addEventListener('click', function(e) {
    // Handle Add Method buttons
    if (e.target && (e.target.id === 'addMethodBtn' || e.target.id === 'addMethodBtnEmpty')) {
      openAddMethodModal();
    }
    
    // Handle Add Rate buttons
    if (e.target && (e.target.id === 'addRateBtn' || e.target.id === 'addRateBtnEmpty')) {
      openAddRateModal();
    }
    
    // Handle Edit buttons
    if (e.target && e.target.classList.contains('edit-method-btn')) {
      handleEditMethodClick(e.target);
    }
    
    // Handle Disable buttons
    if (e.target && e.target.classList.contains('disable-method-btn')) {
      handleDisableMethodClick(e.target);
    }
  });
  
  // Global escape key handler
  document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') {
      closeAllModals();
    }
  });
}

// Add Method Modal functions
function openAddMethodModal() {
  const modal = document.getElementById('addMethodModal');
  if (modal) {
    modal.classList.remove('hidden');
  }
}

function closeAddMethodModal() {
  const modal = document.getElementById('addMethodModal');
  if (modal) {
    modal.classList.add('hidden');
  }
}

// Edit Method Modal functions
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
  }
}

// Add Rate Modal functions
function openAddRateModal() {
  const modal = document.getElementById('addRateModal');
  if (modal) {
    modal.classList.remove('hidden');
  }
}

function closeAddRateModal() {
  const modal = document.getElementById('addRateModal');
  if (modal) {
    modal.classList.add('hidden');
    const form = document.getElementById('addRateForm');
    if (form) form.reset();
  }
}

// Handle Edit Method Click
function handleEditMethodClick(button) {
  const id = button.getAttribute('data-shipping-option-id');
  const name = button.getAttribute('data-shipping-option-name');
  const deliveryTime = button.getAttribute('data-shipping-option-delivery-time');
  const startingRate = button.getAttribute('data-shipping-option-starting-rate');
  const countries = button.getAttribute('data-shipping-option-countries');
  const status = button.getAttribute('data-shipping-option-status');

  // Populate the edit form
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
  if (editCountries) editCountries.value = countries;
  if (editStatus) editStatus.value = status;

  // Update form action
  if (editMethodForm) {
    editMethodForm.action = `/shipping_options/${id}`;
    editMethodForm.method = 'POST';
  }

  openEditMethodModal();
}

// Handle Disable Method Click
function handleDisableMethodClick(button) {
  const id = button.getAttribute('data-shipping-option-id');
  const name = button.getAttribute('data-shipping-option-name');

  if (confirm(`Are you sure you want to disable "${name}"? This action cannot be undone.`)) {
    // Get CSRF token
    const csrfToken = document.querySelector('meta[name="csrf-token"]').getAttribute('content');
    
    // Create form data with _method field for PATCH
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

// Close all modals
function closeAllModals() {
  closeAddMethodModal();
  closeEditMethodModal();
  closeAddRateModal();
}

// Setup modal close buttons and form submissions
document.addEventListener('DOMContentLoaded', function() {
  // Add Method Modal close buttons
  const closeModal = document.getElementById('closeModal');
  const cancelBtn = document.getElementById('cancelBtn');
  if (closeModal) closeModal.addEventListener('click', closeAddMethodModal);
  if (cancelBtn) cancelBtn.addEventListener('click', closeAddMethodModal);

  // Edit Method Modal close buttons
  const closeEditModal = document.getElementById('closeEditModal');
  const cancelEditBtn = document.getElementById('cancelEditBtn');
  if (closeEditModal) closeEditModal.addEventListener('click', closeEditMethodModal);
  if (cancelEditBtn) cancelEditBtn.addEventListener('click', closeEditMethodModal);

  // Add Rate Modal close buttons
  const closeRateModal = document.getElementById('closeRateModal');
  const cancelRateBtn = document.getElementById('cancelRateBtn');
  if (closeRateModal) closeRateModal.addEventListener('click', closeAddRateModal);
  if (cancelRateBtn) cancelRateBtn.addEventListener('click', closeAddRateModal);

  // Close modals when clicking outside
  document.addEventListener('click', function(e) {
    // Add Method Modal
    const addMethodModal = document.getElementById('addMethodModal');
    if (addMethodModal && e.target === addMethodModal) {
      closeAddMethodModal();
    }

    // Edit Method Modal
    const editMethodModal = document.getElementById('editMethodModal');
    if (editMethodModal && e.target === editMethodModal) {
      closeEditMethodModal();
    }

    // Add Rate Modal
    const addRateModal = document.getElementById('addRateModal');
    if (addRateModal && e.target === addRateModal) {
      closeAddRateModal();
    }
  });

  // Handle edit form submission
  const editMethodForm = document.getElementById('editMethodForm');
  if (editMethodForm) {
    editMethodForm.addEventListener('submit', function(e) {
      e.preventDefault();
      
      const formData = new FormData(this);
      const id = document.getElementById('editShippingOptionId').value;
      
      // Get CSRF token
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
          window.location.reload();
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

  // Handle rate form submission
  const addRateForm = document.getElementById('addRateForm');
  if (addRateForm) {
    addRateForm.addEventListener('submit', function(e) {
      e.preventDefault();
      
      const formData = new FormData(this);
      
      // Get CSRF token
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
          window.location.reload();
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

