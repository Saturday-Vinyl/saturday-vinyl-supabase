# Manual Testing Checklist - Prompt 21: Print Settings and Configuration

## Overview
This document provides manual testing instructions for the printer settings and configuration functionality implemented in Prompt 21.

## Test Cases

### 1. Settings Screen Access
- [ ] Navigate to Settings from sidebar menu
- [ ] Verify Settings screen opens
- [ ] Confirm Settings is highlighted in navigation

### 2. Printer Configuration Section
- [ ] Verify "Printer Configuration" section appears (desktop only)
- [ ] Confirm section is hidden on mobile platforms
- [ ] Check that all configuration options are visible

### 3. Default Printer Selection
- [ ] Open Settings screen
- [ ] Verify printer dropdown is populated with available printers
- [ ] Select a default printer from dropdown
- [ ] Save settings
- [ ] Refresh/reload app
- [ ] Verify selected printer is still selected

### 4. Auto-Print Checkbox
- [ ] Locate "Auto-print labels after unit creation" checkbox
- [ ] Check the auto-print checkbox
- [ ] Verify checkbox state changes
- [ ] Save settings
- [ ] Reload app
- [ ] Verify auto-print remains enabled

### 5. Label Size Configuration
- [ ] View label size fields (width and height)
- [ ] Verify default values are 1.0" x 1.0"
- [ ] Change width to 2.0"
- [ ] Change height to 1.5"
- [ ] Save settings
- [ ] Verify success message appears

### 6. Label Size Validation
- [ ] Try to set width to 0.3" (too small)
- [ ] Click Save
- [ ] Verify error message appears
- [ ] Try to set width to 5.0" (too large)
- [ ] Click Save
- [ ] Verify error message appears
- [ ] Set valid values (between 0.5" and 4.0")
- [ ] Verify save succeeds

### 7. Test Print Function
- [ ] Configure default printer
- [ ] Click "Test Print" button
- [ ] Verify button shows "Printing..." state
- [ ] Confirm test label prints with:
  - Unit ID: SV-TEST-00001
  - Product: Test Product
  - Variant: Test Variant
  - Customer: Test Customer
  - Order: TEST-123
- [ ] Verify success message appears

### 8. Settings Persistence
- [ ] Configure all settings (printer, auto-print, label size)
- [ ] Save settings
- [ ] Close app
- [ ] Reopen app
- [ ] Navigate to Settings
- [ ] Verify all settings are persisted correctly

### 9. Auto-Print Functionality - Enabled
- [ ] Enable auto-print in Settings
- [ ] Select a default printer
- [ ] Save settings
- [ ] Navigate to Create Production Unit
- [ ] Complete wizard and create a unit
- [ ] Verify label prints automatically
- [ ] Confirm "Label printed automatically" message appears
- [ ] Verify print preview dialog does NOT appear

### 10. Auto-Print Functionality - Disabled
- [ ] Disable auto-print in Settings
- [ ] Save settings
- [ ] Navigate to Create Production Unit
- [ ] Complete wizard and create a unit
- [ ] Verify label does NOT print automatically
- [ ] Confirm "Print Label" button is available
- [ ] Click "Print Label" button manually
- [ ] Verify print preview dialog appears

### 11. Auto-Print with No Default Printer
- [ ] Enable auto-print in Settings
- [ ] Do NOT select a default printer
- [ ] Save settings
- [ ] Create a production unit
- [ ] Verify system attempts to print with system default
- [ ] OR verify appropriate error message if no printer available

### 12. Auto-Print Error Handling
- [ ] Enable auto-print
- [ ] Select a printer
- [ ] Disconnect/turn off the selected printer
- [ ] Create a production unit
- [ ] Verify error message appears
- [ ] Confirm message says "Auto-print failed. Please print manually."
- [ ] Verify "Print Label" button is still available for manual printing

### 13. Settings Screen UI/UX
- [ ] Verify all labels are clear and readable
- [ ] Check spacing and padding are consistent
- [ ] Confirm Save button is prominently displayed
- [ ] Verify loading states work correctly
- [ ] Check error states are shown appropriately

### 14. PrinterService Integration
- [ ] Verify PrinterService loads settings on initialization
- [ ] Confirm default printer is selected automatically
- [ ] Check label size from settings is used in generation
- [ ] Verify settings are cached properly

### 15. Mobile Platform Behavior
- [ ] Open app on mobile (if applicable)
- [ ] Navigate to Settings
- [ ] Verify printer configuration section is hidden
- [ ] Confirm other settings (future: theme, language) would be visible

### 16. Settings Provider State Management
- [ ] Change settings in one part of the app
- [ ] Navigate to another screen
- [ ] Return to Settings
- [ ] Verify state is maintained
- [ ] Modify settings again
- [ ] Verify updates propagate correctly

### 17. Edge Cases

#### No Printers Available
- [ ] Disconnect all printers
- [ ] Open Settings
- [ ] Verify appropriate message is shown
- [ ] Confirm dropdown is empty or shows "No printers available"

#### Invalid Settings
- [ ] Manually corrupt settings in shared_preferences (if possible)
- [ ] Open Settings
- [ ] Verify app falls back to default settings
- [ ] Confirm no crash occurs

#### Rapid Setting Changes
- [ ] Quickly toggle auto-print on/off multiple times
- [ ] Save settings
- [ ] Verify final state is correct
- [ ] Check for any race conditions

### 18. Integration with Existing Features
- [ ] Print from unit detail screen
- [ ] Verify respects default printer setting
- [ ] Print from unit creation
- [ ] Verify respects auto-print setting
- [ ] Manually trigger print
- [ ] Confirm uses configured label size

## Performance Tests
- [ ] Settings load time < 500ms
- [ ] Printer list loads < 1 second
- [ ] Settings save time < 500ms
- [ ] Test print time < 3 seconds

## Regression Tests
- [ ] Manual print from unit detail screen still works
- [ ] Manual print from create unit screen still works
- [ ] Print preview dialog still functions correctly
- [ ] QR code generation not affected
- [ ] Production unit creation not affected

## Sign-Off

- [ ] All test cases passed
- [ ] All defects documented
- [ ] Settings functionality approved for release

**Tested By:** ________________
**Date:** ________________
**Signature:** ________________

## Notes
- Auto-print only works on desktop platforms (macOS, Windows, Linux)
- Test print functionality requires an actual printer connection
- Settings are stored in shared_preferences (local to device)
