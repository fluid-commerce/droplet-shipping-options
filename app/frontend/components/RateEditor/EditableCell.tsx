import React, { useState, useEffect, useRef } from 'react';

interface EditableCellProps {
  value: number;
  originalValue: number;
  error?: string;
  onChange: (value: number) => void;
}

function EditableCell({ value, originalValue, error, onChange }: EditableCellProps) {
  const [isEditing, setIsEditing] = useState(false);
  const [inputValue, setInputValue] = useState(value.toFixed(2));
  const inputRef = useRef<HTMLInputElement>(null);

  const isDirty = value !== originalValue;

  useEffect(() => {
    if (isEditing && inputRef.current) {
      inputRef.current.focus();
      inputRef.current.select();
    }
  }, [isEditing]);

  useEffect(() => {
    if (!isEditing) {
      setInputValue(value.toFixed(2));
    }
  }, [value, isEditing]);

  const handleBlur = () => {
    setIsEditing(false);
    const numValue = parseFloat(inputValue);
    if (!isNaN(numValue) && numValue !== value) {
      onChange(Math.round(numValue * 100) / 100);
    } else {
      setInputValue(value.toFixed(2));
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      handleBlur();
    } else if (e.key === 'Escape') {
      setInputValue(value.toFixed(2));
      setIsEditing(false);
    }
  };

  if (isEditing) {
    return (
      <input
        ref={inputRef}
        type="number"
        step="0.01"
        min="0"
        value={inputValue}
        onChange={(e) => setInputValue(e.target.value)}
        onBlur={handleBlur}
        onKeyDown={handleKeyDown}
        className={`w-20 px-2 py-1 text-right border rounded text-sm ${
          error ? 'border-red-500 bg-red-50' : 'border-blue-500 bg-white'
        }`}
      />
    );
  }

  return (
    <div
      onClick={() => setIsEditing(true)}
      className={`px-2 py-1 text-right cursor-pointer rounded text-sm transition-colors ${
        isDirty ? 'bg-yellow-100 font-medium' : 'hover:bg-gray-100'
      } ${error ? 'text-red-600' : ''}`}
      title={error || (isDirty ? `Original: $${originalValue.toFixed(2)}` : 'Click to edit')}
    >
      ${value.toFixed(2)}
      {error && <span className="text-red-500 ml-1">!</span>}
    </div>
  );
}

export default EditableCell;
