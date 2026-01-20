import React, { useMemo } from 'react';
import {
  useReactTable,
  getCoreRowModel,
  getSortedRowModel,
  flexRender,
  createColumnHelper,
  SortingState,
} from '@tanstack/react-table';
import { RateState } from './types';
import EditableCell from './EditableCell';

interface RateEditorTableProps {
  rates: RateState[];
  selectedIds: Set<number>;
  onToggleSelection: (id: number) => void;
  onUpdateRate: (id: number, field: 'flat_rate' | 'min_charge', value: number) => void;
}

const columnHelper = createColumnHelper<RateState>();

function RateEditorTable({ rates, selectedIds, onToggleSelection, onUpdateRate }: RateEditorTableProps) {
  const [sorting, setSorting] = React.useState<SortingState>([
    { id: 'shipping_option_name', desc: false }
  ]);

  const columns = useMemo(() => [
    columnHelper.display({
      id: 'select',
      header: ({ table }) => (
        <input
          type="checkbox"
          checked={rates.length > 0 && rates.every(r => selectedIds.has(r.id))}
          onChange={() => {
            if (rates.every(r => selectedIds.has(r.id))) {
              // Deselect all
              rates.forEach(r => {
                if (selectedIds.has(r.id)) onToggleSelection(r.id);
              });
            } else {
              // Select all
              rates.forEach(r => {
                if (!selectedIds.has(r.id)) onToggleSelection(r.id);
              });
            }
          }}
          className="h-4 w-4 rounded border-gray-300 text-blue-600 focus:ring-blue-500"
        />
      ),
      cell: ({ row }) => (
        <input
          type="checkbox"
          checked={selectedIds.has(row.original.id)}
          onChange={() => onToggleSelection(row.original.id)}
          className="h-4 w-4 rounded border-gray-300 text-blue-600 focus:ring-blue-500"
        />
      ),
      size: 40,
    }),
    columnHelper.accessor('shipping_option_name', {
      header: 'Shipping Option',
      cell: info => (
        <span className="font-medium text-gray-900">{info.getValue()}</span>
      ),
      sortingFn: 'alphanumeric',
    }),
    columnHelper.accessor('country', {
      header: 'Country',
      cell: info => (
        <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-800">
          {info.getValue()}
        </span>
      ),
      sortingFn: 'alphanumeric',
    }),
    columnHelper.accessor('region', {
      header: 'Region',
      cell: info => info.getValue() || '-',
      sortingFn: 'alphanumeric',
    }),
    columnHelper.accessor('min_range_lbs', {
      header: 'Min (lbs)',
      cell: info => info.getValue().toFixed(2),
      sortingFn: 'basic',
    }),
    columnHelper.accessor('max_range_lbs', {
      header: 'Max (lbs)',
      cell: info => {
        const val = info.getValue();
        return val >= 9999 ? '∞' : val.toFixed(2);
      },
      sortingFn: 'basic',
    }),
    columnHelper.accessor('flat_rate', {
      header: 'Flat Rate',
      cell: ({ row }) => (
        <EditableCell
          value={row.original.flat_rate}
          originalValue={row.original.originalFlatRate}
          error={row.original.errors.flat_rate}
          onChange={(value) => onUpdateRate(row.original.id, 'flat_rate', value)}
        />
      ),
      sortingFn: 'basic',
    }),
    columnHelper.accessor('min_charge', {
      header: 'Min Charge',
      cell: ({ row }) => (
        <EditableCell
          value={row.original.min_charge}
          originalValue={row.original.originalMinCharge}
          error={row.original.errors.min_charge}
          onChange={(value) => onUpdateRate(row.original.id, 'min_charge', value)}
        />
      ),
      sortingFn: 'basic',
    }),
  ], [selectedIds, onToggleSelection, onUpdateRate, rates]);

  const table = useReactTable({
    data: rates,
    columns,
    state: {
      sorting,
    },
    onSortingChange: setSorting,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
  });

  if (rates.length === 0) {
    return (
      <div className="bg-white p-8 rounded-xl shadow-sm border border-gray-200 text-center text-gray-500">
        No rates found. Try adjusting your filters.
      </div>
    );
  }

  return (
    <div className="bg-white rounded-xl shadow-sm border border-gray-200 overflow-hidden">
      <div className="overflow-x-auto">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            {table.getHeaderGroups().map(headerGroup => (
              <tr key={headerGroup.id}>
                {headerGroup.headers.map(header => (
                  <th
                    key={header.id}
                    onClick={header.column.getCanSort() ? header.column.getToggleSortingHandler() : undefined}
                    className={`px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider ${
                      header.column.getCanSort() ? 'cursor-pointer hover:bg-gray-100' : ''
                    }`}
                    style={{ width: header.getSize() !== 150 ? header.getSize() : undefined }}
                  >
                    <div className="flex items-center gap-1">
                      {flexRender(header.column.columnDef.header, header.getContext())}
                      {header.column.getIsSorted() && (
                        <span className="text-blue-600">
                          {header.column.getIsSorted() === 'asc' ? '↑' : '↓'}
                        </span>
                      )}
                    </div>
                  </th>
                ))}
              </tr>
            ))}
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {table.getRowModel().rows.map(row => (
              <tr
                key={row.id}
                className={`hover:bg-gray-50 ${
                  row.original.isDirty ? 'bg-yellow-50' : ''
                } ${
                  selectedIds.has(row.original.id) ? 'bg-blue-50' : ''
                }`}
              >
                {row.getVisibleCells().map(cell => (
                  <td key={cell.id} className="px-4 py-2 whitespace-nowrap text-sm text-gray-600">
                    {flexRender(cell.column.columnDef.cell, cell.getContext())}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

export default RateEditorTable;
