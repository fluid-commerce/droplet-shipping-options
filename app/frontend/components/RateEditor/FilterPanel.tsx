import React from 'react';
import { ShippingOption, Filters } from './types';

interface FilterPanelProps {
  shippingOptions: ShippingOption[];
  countries: string[];
  filters: Filters;
  onFilterChange: (filters: Filters) => void;
}

function FilterPanel({ shippingOptions, countries, filters, onFilterChange }: FilterPanelProps) {
  return (
    <div className="bg-white p-4 rounded-xl shadow-sm border border-gray-200">
      <div className="flex flex-wrap items-center gap-4">
        <div className="flex items-center gap-2">
          <label htmlFor="shipping-option-filter" className="text-sm font-medium text-gray-700">
            Shipping Option:
          </label>
          <select
            id="shipping-option-filter"
            value={filters.shippingOptionId || ''}
            onChange={(e) => onFilterChange({
              ...filters,
              shippingOptionId: e.target.value ? parseInt(e.target.value, 10) : undefined
            })}
            className="px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
          >
            <option value="">All Shipping Options</option>
            {shippingOptions.map(opt => (
              <option key={opt.id} value={opt.id}>{opt.name}</option>
            ))}
          </select>
        </div>

        <div className="flex items-center gap-2">
          <label htmlFor="country-filter" className="text-sm font-medium text-gray-700">
            Country:
          </label>
          <select
            id="country-filter"
            value={filters.country || ''}
            onChange={(e) => onFilterChange({
              ...filters,
              country: e.target.value || undefined
            })}
            className="px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
          >
            <option value="">All Countries</option>
            {countries.map(country => (
              <option key={country} value={country}>{country}</option>
            ))}
          </select>
        </div>

        {(filters.shippingOptionId || filters.country) && (
          <button
            onClick={() => onFilterChange({})}
            className="px-3 py-2 text-sm text-gray-600 hover:text-gray-800 hover:bg-gray-100 rounded-lg transition-colors"
          >
            Clear Filters
          </button>
        )}
      </div>
    </div>
  );
}

export default FilterPanel;
