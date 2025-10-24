# CSV Import Guide for Rate Tables

## Overview

The CSV import feature allows you to bulk import shipping rates instead of entering them one-by-one. This is particularly useful when you need to configure rates for multiple regions, shipping methods, or weight ranges.

## Accessing the Import Feature

1. Navigate to **Rate Tables** in the application
2. Click the **"Import CSV"** button (green button)
3. Upload your CSV file
4. Review results and any errors

## CSV File Format

### Required Columns

Your CSV file **must** include these columns (order doesn't matter):

| Column | Type | Description | Example |
|--------|------|-------------|---------|
| `shipping_method` | String | Name of existing shipping method | Express Shipping |
| `country` | String (2 chars) | ISO 2-letter country code | US, CA, MX |
| `region` | String | State/province **code** (not full name) | CA, NY, ON, BC |
| `min_range_lbs` | Decimal | Minimum weight in pounds | 0, 5.5, 10 |
| `max_range_lbs` | Decimal | Maximum weight in pounds | 5, 10.5, 25 |
| `flat_rate` | Decimal | Shipping cost in dollars | 9.99, 15.50 |
| `min_charge` | Decimal | Minimum charge in dollars | 5.00, 10.00 |

### Important Notes

- **Region codes, not names**: Use `CA` (not California), `NY` (not New York), `ON` (not Ontario)
- **Country codes**: Must be exactly 2 characters (US, CA, MX, GB, etc.)
- **First rate must start at 0**: For each unique shipping_method + country + region combination, the first rate must have `min_range_lbs = 0`
- **No overlapping ranges**: Weight ranges cannot overlap for the same location and shipping method
- **Shipping method must exist**: The shipping method name must match an existing method in your account

## Example CSV File

```csv
shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
Express Shipping,US,CA,0,5,9.99,5.00
Express Shipping,US,CA,5,10,14.99,10.00
Express Shipping,US,CA,10,25,24.99,15.00
Express Shipping,US,NY,0,5,12.99,8.00
Express Shipping,US,NY,5,10,17.99,12.00
Standard Shipping,US,CA,0,10,5.99,3.00
Standard Shipping,US,CA,10,25,9.99,5.00
Standard Shipping,CA,ON,0,10,15.99,10.00
Standard Shipping,CA,BC,0,10,18.99,12.00
```

## Common Region Codes

### United States (US)
- CA - California
- NY - New York
- TX - Texas
- FL - Florida
- IL - Illinois
- etc. (use 2-letter state abbreviations)

### Canada (CA)
- ON - Ontario
- BC - British Columbia
- QC - Quebec
- AB - Alberta
- MB - Manitoba
- etc. (use 2-letter province abbreviations)

### Other Countries
Check the specific country's standard region/state codes.

## Validation Rules

The import process validates each row and will report errors for:

1. **Missing shipping method**: Shipping method doesn't exist
2. **Invalid country code**: Not exactly 2 characters
3. **Missing region**: Region field is blank
4. **Invalid weight ranges**: 
   - min_range_lbs is negative
   - max_range_lbs is less than or equal to min_range_lbs
   - First rate for a location doesn't start at 0
   - Ranges overlap with existing rates
5. **Invalid pricing**: 
   - flat_rate or min_charge is negative

## Import Results

After uploading your CSV:

- **Success**: All rates imported successfully
- **Partial Success**: Some rates imported, some had errors (errors shown with row numbers)
- **Failure**: No rates imported (errors shown)

## Tips

1. **Download the sample CSV** from the import page to see the correct format
2. **Test with a small file first** (2-3 rows) to verify your format
3. **Check your shipping method names** - they must match exactly (case-sensitive)
4. **Use codes, not full names** for regions
5. **Organize by location** - group all rates for the same location together
6. **Sequential weight ranges** - ensure ranges don't overlap and start at 0

## Troubleshooting

### "Shipping method not found"
- Verify the shipping method name matches exactly (including spaces and capitalization)
- Create the shipping method first if it doesn't exist

### "Country is the wrong length"
- Use 2-letter codes only (US, not USA or United States)

### "Min_range_lbs must be 0 for the first rate"
- Each new location (country + region + shipping method combo) must start with min_range_lbs = 0

### "Weight range overlaps"
- Check for existing rates in the database
- Ensure no overlapping ranges in your CSV file
- Each rate must have distinct, non-overlapping weight ranges

## Example Use Cases

### Setting up tiered pricing for multiple states
```csv
shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
Express Shipping,US,CA,0,5,9.99,5.00
Express Shipping,US,CA,5,15,14.99,10.00
Express Shipping,US,CA,15,50,24.99,15.00
Express Shipping,US,NY,0,5,9.99,5.00
Express Shipping,US,NY,5,15,14.99,10.00
Express Shipping,US,NY,15,50,24.99,15.00
```

### Multiple shipping methods for same region
```csv
shipping_method,country,region,min_range_lbs,max_range_lbs,flat_rate,min_charge
Express Shipping,US,CA,0,10,15.99,10.00
Standard Shipping,US,CA,0,10,8.99,5.00
Economy Shipping,US,CA,0,10,4.99,3.00
```

