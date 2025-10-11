# Manual Testing Checklist - Prompt 20: Thermal Label Printing

## Overview
This document provides a comprehensive manual testing checklist for the thermal label printing functionality implemented in Prompt 20.

## Prerequisites
- Desktop platform (macOS, Windows, or Linux)
- At least one thermal printer installed and configured on the system
- Test production units created in the database
- Test products and variants configured

## Test Cases

### 1. Printer Service Tests

#### 1.1 Printer Detection
- [ ] Launch the application on a desktop platform
- [ ] Verify that available printers are detected
- [ ] Confirm printer list includes all system-configured printers

#### 1.2 Printer Selection
- [ ] Open the print preview dialog
- [ ] Verify that the printer dropdown is populated
- [ ] Select different printers from the dropdown
- [ ] Confirm selection persists across dialog reopens

### 2. Print Preview Dialog Tests

#### 2.1 Dialog Display
- [ ] Navigate to a production unit detail screen
- [ ] Click the "Print Label" button in the app bar
- [ ] Verify print preview dialog opens
- [ ] Confirm dialog title is "Print Label"

#### 2.2 Label Preview
- [ ] Verify label preview shows at 3x scale
- [ ] Confirm QR code is displayed correctly
- [ ] Verify unit ID is shown in bold, larger font
- [ ] Check product name and variant are displayed
- [ ] If order is associated, verify customer name is shown
- [ ] If order is associated, verify order number is shown
- [ ] Confirm all text is readable and properly formatted

#### 2.3 Label Content - With Customer Info
- [ ] Create a unit associated with a Shopify order
- [ ] Open print preview for that unit
- [ ] Verify customer name appears on the label
- [ ] Verify order number appears on the label
- [ ] Confirm layout accommodates all information

#### 2.4 Label Content - Without Customer Info
- [ ] Create a unit for inventory build (no order)
- [ ] Open print preview for that unit
- [ ] Verify label displays correctly without customer info
- [ ] Confirm QR code, unit ID, product, and variant are shown

#### 2.5 Long Product/Variant Names
- [ ] Create a unit with a very long product name (>50 characters)
- [ ] Open print preview
- [ ] Verify text is truncated or wrapped appropriately
- [ ] Confirm label remains readable

#### 2.6 Special Characters
- [ ] Create a unit with special characters in product name (&, <, >, ", ')
- [ ] Open print preview
- [ ] Verify special characters display correctly
- [ ] Confirm no encoding issues

### 3. Printing Tests

#### 3.1 Basic Printing
- [ ] Open print preview dialog
- [ ] Select a thermal printer
- [ ] Click "Print" button
- [ ] Verify "Printing..." state is shown
- [ ] Confirm label prints successfully
- [ ] Check success message appears
- [ ] Verify dialog closes after printing

#### 3.2 Print Quality
- [ ] Print a label
- [ ] Verify QR code is scannable
- [ ] Confirm all text is clear and readable
- [ ] Check that label size is correct (1" x 1")
- [ ] Verify alignment is correct

#### 3.3 Printer Errors
- [ ] Disconnect the selected printer
- [ ] Try to print a label
- [ ] Verify error message is displayed
- [ ] Confirm dialog remains open after error
- [ ] Reconnect printer and retry
- [ ] Verify printing succeeds after reconnection

#### 3.4 No Printers Available
- [ ] Disconnect all printers
- [ ] Open print preview dialog
- [ ] Verify appropriate message is shown
- [ ] Confirm "Print" button is disabled

### 4. Unit Detail Screen Integration

#### 4.1 Print Button Visibility
- [ ] Open unit detail screen on desktop
- [ ] Verify print button appears in app bar
- [ ] Open unit detail screen on mobile (if available)
- [ ] Confirm print button is hidden on mobile

#### 4.2 Print Button Functionality
- [ ] Click print button from unit detail screen
- [ ] Verify print preview dialog opens
- [ ] Confirm all unit data is correctly populated

#### 4.3 Print from Completion Confirmation
- [ ] Complete a production step
- [ ] In the completion confirmation dialog, click "Print Label"
- [ ] Verify print preview opens
- [ ] Confirm correct unit data is shown

### 5. Create Unit Screen Integration

#### 5.1 Print Button After Creation
- [ ] Create a new production unit
- [ ] Complete the wizard to confirmation step
- [ ] Verify "Print Label" button appears (desktop only)
- [ ] Verify button is positioned correctly with other action buttons

#### 5.2 Print Newly Created Unit
- [ ] Click "Print Label" button after unit creation
- [ ] Verify print preview opens with correct data
- [ ] Confirm QR code URL is accessible
- [ ] Print the label successfully

#### 5.3 Mobile Behavior
- [ ] Create a unit on mobile device (if applicable)
- [ ] Verify "Print Label" button is not shown
- [ ] Confirm other action buttons (Done, Create Another) work normally

### 6. QR Code Handling

#### 6.1 QR Code Download
- [ ] Create a unit and wait for QR code to upload
- [ ] Open print preview
- [ ] Verify QR code image is downloaded successfully
- [ ] Confirm label generates without errors

#### 6.2 QR Code Fallback
- [ ] Simulate network error (or invalid QR code URL)
- [ ] Open print preview
- [ ] Verify system falls back to generating QR code locally
- [ ] Confirm label still prints correctly

### 7. Edge Cases

#### 7.1 Missing Product/Variant Data
- [ ] Try to print with missing product data (manually test error handling)
- [ ] Verify appropriate error message is shown
- [ ] Confirm user can dismiss error and retry

#### 7.2 Concurrent Printing
- [ ] Open multiple print preview dialogs
- [ ] Print labels from different units simultaneously
- [ ] Verify all prints complete successfully
- [ ] Confirm no race conditions occur

#### 7.3 Dialog Cancellation
- [ ] Open print preview dialog
- [ ] Click "Cancel" without printing
- [ ] Verify dialog closes cleanly
- [ ] Confirm no side effects

### 8. Platform-Specific Tests

#### 8.1 macOS
- [ ] Test on macOS
- [ ] Verify printer detection works
- [ ] Confirm printing to various printer types (USB, network)
- [ ] Check print quality matches expectations

#### 8.2 Windows
- [ ] Test on Windows
- [ ] Verify printer detection works
- [ ] Confirm printing to various printer types
- [ ] Check print quality matches expectations

#### 8.3 Linux
- [ ] Test on Linux
- [ ] Verify printer detection works
- [ ] Confirm CUPS integration works correctly
- [ ] Check print quality matches expectations

## Defect Reporting

If any issues are found during testing, please document:
1. Test case number that failed
2. Steps to reproduce
3. Expected result
4. Actual result
5. Platform and OS version
6. Printer model
7. Screenshots or photos of printed labels (if relevant)

## Sign-Off

- [ ] All test cases passed
- [ ] All defects resolved or documented
- [ ] Feature approved for release

**Tested By:** ________________
**Date:** ________________
**Signature:** ________________
