export interface Rate {
  id: number;
  shipping_option_id: number;
  shipping_option_name: string;
  country: string;
  region: string | null;
  min_range_lbs: number;
  max_range_lbs: number;
  flat_rate: number;
  min_charge: number;
}

export interface RateState extends Rate {
  originalFlatRate: number;
  originalMinCharge: number;
  isDirty: boolean;
  errors: Record<string, string>;
}

export interface ShippingOption {
  id: number;
  name: string;
}

export interface Filters {
  shippingOptionId?: number;
  country?: string;
}

export interface BulkOperation {
  type: 'add_fixed' | 'add_percentage' | 'set_value';
  field: 'flat_rate' | 'min_charge';
  value: number;
  scope: 'all' | 'selected' | 'filtered';
}

export interface ApiResponse {
  rates: Rate[];
  shipping_options: ShippingOption[];
  countries: string[];
}

export interface BulkUpdateResponse {
  success: boolean;
  updated_count?: number;
  errors?: Array<{ id: number; errors: string[] }>;
}
