import React, { useState } from 'react';
import { BulkOperation } from './types';

interface BulkOperationsPanelProps {
  selectedCount: number;
  filteredCount: number;
  onApply: (operation: BulkOperation) => void;
  onSelectAllFiltered: () => void;
  onClearSelection: () => void;
}

function BulkOperationsPanel({
  selectedCount,
  filteredCount,
  onApply,
  onSelectAllFiltered,
  onClearSelection
}: BulkOperationsPanelProps) {
  const [operationType, setOperationType] = useState<BulkOperation['type']>('add_fixed');
  const [field, setField] = useState<BulkOperation['field']>('flat_rate');
  const [value, setValue] = useState<string>('');
  const [scope, setScope] = useState<BulkOperation['scope']>('filtered');

  const handleApply = () => {
    const numValue = parseFloat(value);
    if (isNaN(numValue)) return;

    onApply({
      type: operationType,
      field,
      value: numValue,
      scope
    });

    // Clear value after applying
    setValue('');
  };

  const getPlaceholder = () => {
    switch (operationType) {
      case 'add_fixed':
        return 'e.g. 0.50';
      case 'add_percentage':
        return 'e.g. 10';
      case 'set_value':
        return 'e.g. 5.00';
    }
  };

  const getLabel = () => {
    switch (operationType) {
      case 'add_fixed':
        return 'Amount ($)';
      case 'add_percentage':
        return 'Percentage (%)';
      case 'set_value':
        return 'Value ($)';
    }
  };

  const getScopeCount = () => {
    switch (scope) {
      case 'selected':
        return selectedCount;
      case 'filtered':
        return filteredCount;
      case 'all':
        return filteredCount; // In this context, "all" means all currently filtered
    }
  };

  return (
    <div className="bg-white p-4 rounded-xl shadow-sm border border-gray-200">
      <div className="flex flex-wrap items-end gap-4">
        {/* Selection Controls */}
        <div className="flex items-center gap-2 border-r border-gray-200 pr-4">
          <span className="text-sm text-gray-600">
            {selectedCount} selected
          </span>
          <button
            onClick={onSelectAllFiltered}
            className="text-sm text-blue-600 hover:text-blue-800"
          >
            Select All ({filteredCount})
          </button>
          {selectedCount > 0 && (
            <button
              onClick={onClearSelection}
              className="text-sm text-gray-500 hover:text-gray-700"
            >
              Clear
            </button>
          )}
        </div>

        {/* Bulk Operation Controls */}
        <div className="flex items-center gap-2">
          <label htmlFor="operation-type" className="text-sm font-medium text-gray-700">
            Operation:
          </label>
          <select
            id="operation-type"
            value={operationType}
            onChange={(e) => setOperationType(e.target.value as BulkOperation['type'])}
            className="px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500"
          >
            <option value="add_fixed">Add Fixed Amount</option>
            <option value="add_percentage">Add Percentage</option>
            <option value="set_value">Set Value</option>
          </select>
        </div>

        <div className="flex items-center gap-2">
          <label htmlFor="field" className="text-sm font-medium text-gray-700">
            Field:
          </label>
          <select
            id="field"
            value={field}
            onChange={(e) => setField(e.target.value as BulkOperation['field'])}
            className="px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500"
          >
            <option value="flat_rate">Flat Rate</option>
            <option value="min_charge">Min Charge</option>
          </select>
        </div>

        <div className="flex items-center gap-2">
          <label htmlFor="value" className="text-sm font-medium text-gray-700">
            {getLabel()}:
          </label>
          <input
            id="value"
            type="number"
            step="0.01"
            value={value}
            onChange={(e) => setValue(e.target.value)}
            placeholder={getPlaceholder()}
            className="w-24 px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500"
          />
        </div>

        <div className="flex items-center gap-2">
          <label htmlFor="scope" className="text-sm font-medium text-gray-700">
            Apply to:
          </label>
          <select
            id="scope"
            value={scope}
            onChange={(e) => setScope(e.target.value as BulkOperation['scope'])}
            className="px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500"
          >
            <option value="filtered">Filtered ({filteredCount})</option>
            <option value="selected" disabled={selectedCount === 0}>
              Selected ({selectedCount})
            </option>
          </select>
        </div>

        <button
          onClick={handleApply}
          disabled={!value || getScopeCount() === 0}
          className={`px-4 py-2 text-sm font-medium text-white rounded-lg transition-colors ${
            !value || getScopeCount() === 0
              ? 'bg-gray-300 cursor-not-allowed'
              : 'bg-purple-600 hover:bg-purple-700'
          }`}
        >
          Apply to {getScopeCount()} rates
        </button>
      </div>
    </div>
  );
}

export default BulkOperationsPanel;
