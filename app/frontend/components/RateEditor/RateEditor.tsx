import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { Rate, RateState, ShippingOption, Filters, BulkOperation, ApiResponse, BulkUpdateResponse } from './types';
import FilterPanel from './FilterPanel';
import RateEditorTable from './RateEditorTable';
import BulkOperationsPanel from './BulkOperationsPanel';

interface RateEditorProps {
  apiBasePath: string;
  bulkUpdatePath: string;
  dri: string;
  backUrl: string;
}

function validateRate(rate: RateState): Record<string, string> {
  const errors: Record<string, string> = {};

  if (rate.flat_rate < 0) {
    errors.flat_rate = 'Must be >= 0';
  }

  if (rate.min_charge < 0) {
    errors.min_charge = 'Must be >= 0';
  }

  return errors;
}

function RateEditor({ apiBasePath, bulkUpdatePath, dri, backUrl }: RateEditorProps) {
  const [rates, setRates] = useState<RateState[]>([]);
  const [shippingOptions, setShippingOptions] = useState<ShippingOption[]>([]);
  const [countries, setCountries] = useState<string[]>([]);
  const [filters, setFilters] = useState<Filters>({});
  const [selectedIds, setSelectedIds] = useState<Set<number>>(new Set());
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);

  // Fetch rates from API
  const fetchRates = useCallback(async () => {
    setIsLoading(true);
    setError(null);

    try {
      const url = new URL(`${apiBasePath}`, window.location.origin);
      url.searchParams.set('dri', dri);

      const response = await fetch(url.toString());

      if (!response.ok) {
        throw new Error('Failed to fetch rates');
      }

      const data: ApiResponse = await response.json();

      // Transform rates to RateState with tracking fields
      const rateStates: RateState[] = data.rates.map(rate => ({
        ...rate,
        originalFlatRate: rate.flat_rate,
        originalMinCharge: rate.min_charge,
        isDirty: false,
        errors: {}
      }));

      setRates(rateStates);
      setShippingOptions(data.shipping_options);
      setCountries(data.countries);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'An error occurred');
    } finally {
      setIsLoading(false);
    }
  }, [apiBasePath, dri]);

  useEffect(() => {
    fetchRates();
  }, [fetchRates]);

  // Filtered rates
  const filteredRates = useMemo(() => {
    return rates.filter(rate => {
      if (filters.shippingOptionId && rate.shipping_option_id !== filters.shippingOptionId) {
        return false;
      }
      if (filters.country && rate.country !== filters.country) {
        return false;
      }
      return true;
    });
  }, [rates, filters]);

  // Dirty rates
  const dirtyRates = useMemo(() => rates.filter(r => r.isDirty), [rates]);

  // Update a single rate
  const updateRate = useCallback((id: number, field: 'flat_rate' | 'min_charge', value: number) => {
    setRates(prev => prev.map(rate => {
      if (rate.id !== id) return rate;

      const updated = { ...rate, [field]: value };
      updated.isDirty = updated.flat_rate !== rate.originalFlatRate ||
                        updated.min_charge !== rate.originalMinCharge;
      updated.errors = validateRate(updated);

      return updated;
    }));
  }, []);

  // Apply bulk operation
  const applyBulkOperation = useCallback((operation: BulkOperation) => {
    setRates(prev => prev.map(rate => {
      // Check scope
      if (operation.scope === 'selected' && !selectedIds.has(rate.id)) return rate;
      if (operation.scope === 'filtered') {
        if (filters.shippingOptionId && rate.shipping_option_id !== filters.shippingOptionId) return rate;
        if (filters.country && rate.country !== filters.country) return rate;
      }

      const updated = { ...rate };
      const field = operation.field;

      switch (operation.type) {
        case 'add_fixed':
          updated[field] = Math.round((rate[field] + operation.value) * 100) / 100;
          break;
        case 'add_percentage':
          updated[field] = Math.round(rate[field] * (1 + operation.value / 100) * 100) / 100;
          break;
        case 'set_value':
          updated[field] = operation.value;
          break;
      }

      // Ensure non-negative
      if (updated[field] < 0) updated[field] = 0;

      updated.isDirty = updated.flat_rate !== rate.originalFlatRate ||
                        updated.min_charge !== rate.originalMinCharge;
      updated.errors = validateRate(updated);

      return updated;
    }));
  }, [selectedIds, filters]);

  // Toggle row selection
  const toggleSelection = useCallback((id: number) => {
    setSelectedIds(prev => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
  }, []);

  // Select all filtered
  const selectAllFiltered = useCallback(() => {
    const filteredIds = new Set(filteredRates.map(r => r.id));
    setSelectedIds(filteredIds);
  }, [filteredRates]);

  // Clear selection
  const clearSelection = useCallback(() => {
    setSelectedIds(new Set());
  }, []);

  // Save changes
  const saveChanges = useCallback(async () => {
    if (dirtyRates.length === 0) return;

    // Check for validation errors
    const hasErrors = dirtyRates.some(r => Object.keys(r.errors).length > 0);
    if (hasErrors) {
      setError('Please fix validation errors before saving');
      return;
    }

    setIsSaving(true);
    setError(null);
    setSuccessMessage(null);

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');

      const response = await fetch(`${bulkUpdatePath}?dri=${encodeURIComponent(dri)}`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken || ''
        },
        body: JSON.stringify({
          rates: dirtyRates.map(r => ({
            id: r.id,
            flat_rate: r.flat_rate,
            min_charge: r.min_charge
          }))
        })
      });

      const data: BulkUpdateResponse = await response.json();

      if (data.success) {
        setSuccessMessage(`Successfully updated ${data.updated_count} rates`);

        // Reset dirty state
        setRates(prev => prev.map(rate => ({
          ...rate,
          originalFlatRate: rate.flat_rate,
          originalMinCharge: rate.min_charge,
          isDirty: false
        })));

        // Clear success message after 3 seconds
        setTimeout(() => setSuccessMessage(null), 3000);
      } else {
        const errorMessages = data.errors?.map(e => `Rate ${e.id}: ${e.errors.join(', ')}`).join('; ');
        setError(`Failed to save: ${errorMessages}`);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save changes');
    } finally {
      setIsSaving(false);
    }
  }, [bulkUpdatePath, dri, dirtyRates]);

  // Revert all changes
  const revertChanges = useCallback(() => {
    setRates(prev => prev.map(rate => ({
      ...rate,
      flat_rate: rate.originalFlatRate,
      min_charge: rate.originalMinCharge,
      isDirty: false,
      errors: {}
    })));
  }, []);

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-12">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
        <span className="ml-3 text-gray-600">Loading rates...</span>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Error/Success Messages */}
      {error && (
        <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded-xl">
          {error}
        </div>
      )}
      {successMessage && (
        <div className="bg-green-50 border border-green-200 text-green-700 px-4 py-3 rounded-xl">
          {successMessage}
        </div>
      )}

      {/* Filter Panel */}
      <FilterPanel
        shippingOptions={shippingOptions}
        countries={countries}
        filters={filters}
        onFilterChange={setFilters}
      />

      {/* Bulk Operations Panel */}
      <BulkOperationsPanel
        selectedCount={selectedIds.size}
        filteredCount={filteredRates.length}
        onApply={applyBulkOperation}
        onSelectAllFiltered={selectAllFiltered}
        onClearSelection={clearSelection}
      />

      {/* Action Bar */}
      <div className="flex items-center justify-between bg-white p-4 rounded-xl shadow-sm border border-gray-200">
        <div className="text-sm text-gray-600">
          Showing {filteredRates.length} of {rates.length} rates
          {dirtyRates.length > 0 && (
            <span className="ml-2 text-orange-600 font-medium">
              ({dirtyRates.length} unsaved changes)
            </span>
          )}
        </div>
        <div className="flex gap-2">
          {dirtyRates.length > 0 && (
            <button
              onClick={revertChanges}
              className="px-4 py-2 text-sm font-medium text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-lg transition-colors"
            >
              Revert All
            </button>
          )}
          <button
            onClick={saveChanges}
            disabled={dirtyRates.length === 0 || isSaving}
            className={`px-4 py-2 text-sm font-medium text-white rounded-lg transition-colors ${
              dirtyRates.length === 0
                ? 'bg-gray-300 cursor-not-allowed'
                : 'bg-blue-600 hover:bg-blue-700'
            }`}
          >
            {isSaving ? 'Saving...' : `Save ${dirtyRates.length} Changes`}
          </button>
        </div>
      </div>

      {/* Table */}
      <RateEditorTable
        rates={filteredRates}
        selectedIds={selectedIds}
        onToggleSelection={toggleSelection}
        onUpdateRate={updateRate}
      />
    </div>
  );
}

export default RateEditor;
