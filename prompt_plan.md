# Saturday! Admin App - Implementation Prompt Plan

## Overview

This document contains a series of prompts designed for incremental, test-driven development of the Saturday! Admin App. Each prompt builds on the previous work, ensuring no orphaned code and maintaining a working application at every stage.

**Development Approach:**
- Test-Driven Development (TDD) where applicable
- Small, incremental changes
- Integration after each step
- Working app at every checkpoint
- Platform priority: Desktop first, then mobile, then web

**Technology Stack:**
- Flutter (cross-platform framework)
- Supabase (backend, auth, storage)
- Shopify GraphQL Admin API
- Riverpod (state management)

---

## Phase 0: Project Foundation (Prompts 1-3)

### Prompt 1: Project Setup and Dependencies

**Context:** Starting with a fresh Flutter project stub. Need to configure the project with all necessary dependencies, folder structure, and basic configuration.

**Prompt:**

```
I'm building a Flutter cross-platform admin app for production management. The project already exists at /Users/dlatham/workspace/saturday-app/saturday_app with a basic Flutter stub.

Please help me set up the project foundation:

1. Update pubspec.yaml with these dependencies:
   - supabase_flutter: ^2.0.0
   - flutter_riverpod: ^2.4.0
   - google_sign_in: ^6.1.0
   - graphql_flutter: ^5.1.0
   - qr_flutter: ^4.1.0
   - mobile_scanner: ^3.5.0
   - url_launcher: ^6.2.0
   - file_picker: ^6.1.0
   - google_fonts: ^6.1.0
   - flutter_svg: ^2.0.0
   - cached_network_image: ^3.3.0
   - intl: ^0.18.0
   - uuid: ^4.2.0
   - dio: ^5.4.0
   - logger: ^2.0.0
   - shared_preferences: ^2.2.0

   Dev dependencies:
   - flutter_lints: ^3.0.0
   - mockito: ^5.4.0
   - build_runner: ^2.4.0

2. Create this folder structure in lib/:
   - config/
   - models/
   - services/
   - repositories/
   - providers/
   - screens/
   - widgets/
   - utils/

3. Create a .env.example file with placeholders for:
   - SUPABASE_URL
   - SUPABASE_ANON_KEY
   - SHOPIFY_STORE_URL
   - SHOPIFY_ACCESS_TOKEN
   - GOOGLE_CLIENT_ID
   - APP_BASE_URL

4. Add .env to .gitignore

5. Update the analysis_options.yaml to use flutter_lints

6. Run flutter pub get to verify all dependencies resolve correctly

Please provide the complete updated pubspec.yaml and confirm the folder structure is created.
```

**Expected Outcome:**
- pubspec.yaml configured with all dependencies
- Folder structure created
- Environment file template ready
- Project ready for development

---

### Prompt 2: Brand Theme Configuration

**Context:** Now that the project structure is ready, configure the app's visual identity with brand colors, typography, and theme data.

**Prompt:**

```
Now let's configure the Saturday! brand theme. The brand assets are already in /assets/images/ (saturday-logo.svg and saturday-icon.svg).

Brand specifications:
- Colors:
  - Primary Dark: #3F3A34
  - Success/Green: #30AA47
  - Error/Orange: #F35345
  - Info/Blue: #6AC5F4
  - Secondary/Grey: #B2AAA3
  - Light: #E2DAD0
- Typography:
  - Headings: Bevan (Google Fonts serif)
  - Body: Default sans-serif

Create lib/config/theme.dart with:

1. Define a SaturdayColors class with static const Color properties for all brand colors
2. Define a SaturdayTheme class that returns ThemeData with:
   - ColorScheme using the brand colors
   - TextTheme using Bevan for headlines and default sans-serif for body
   - Consistent button styles, input decoration, etc.
3. Export both light and dark theme variations (for future use)

Also create lib/config/constants.dart with:
1. App name constant: "Saturday!"
2. Placeholder constants for environment variables (we'll load these later)
3. API timeout constants
4. Minimum supported versions

Write unit tests in test/config/theme_test.dart to verify:
- All brand colors are correctly defined
- Theme data is not null
- Text themes use correct font families

Integrate the theme into lib/main.dart by updating the MaterialApp to use the Saturday theme.
```

**Expected Outcome:**
- Theme configuration with brand colors and typography
- Constants file for app-wide values
- Unit tests verifying theme setup
- Theme integrated into main.dart

---

### Prompt 3: Environment Configuration and Logger Setup

**Context:** Set up environment variable loading and logging infrastructure for the app.

**Prompt:**

```
Let's set up environment configuration and logging infrastructure.

1. Add flutter_dotenv: ^5.1.0 to pubspec.yaml dependencies

2. Create lib/config/env_config.dart with:
   - A class that loads environment variables from .env file
   - Static getters for each environment variable (SUPABASE_URL, SUPABASE_ANON_KEY, etc.)
   - Validation that required variables are present
   - Throw descriptive errors if required env vars are missing

3. Create lib/utils/app_logger.dart with:
   - A wrapper around the logger package
   - Configure log levels (debug, info, warning, error)
   - Include timestamp and context in logs
   - Pretty printing for development
   - Method to log errors with stack traces

4. Update lib/main.dart to:
   - Load environment variables with dotenv on app start
   - Initialize the logger
   - Wrap app initialization in try-catch with proper error logging
   - Show a user-friendly error screen if initialization fails

5. Create a real .env file (not committed) with placeholder values for local development

6. Write tests in test/config/env_config_test.dart to verify:
   - Environment variables can be loaded
   - Missing required variables throw appropriate errors
   - Getters return correct values

Run the app to verify it launches successfully with environment configuration loaded.
```

**Expected Outcome:**
- Environment variable loading configured
- Logger infrastructure ready
- Error handling for missing configuration
- Tests for environment config
- App launches successfully

---

## Phase 1: Authentication Foundation (Prompts 4-8)

### Prompt 4: Supabase Service and Authentication Models

**Context:** Create the foundation for Supabase integration and define authentication-related data models.

**Prompt:**

```
Let's create the Supabase integration layer and authentication models.

1. Create lib/models/user.dart with:
   - User model class with properties: id (UUID), googleId, email, fullName, isAdmin, isActive, createdAt, lastLogin
   - fromJson and toJson methods for serialization
   - copyWith method for immutability
   - Override equality and hashCode

2. Create lib/models/permission.dart with:
   - Permission model with: id, name, description
   - Predefined static constants for the three initial permissions: MANAGE_PRODUCTS, MANAGE_FIRMWARE, MANAGE_PRODUCTION
   - fromJson and toJson methods

3. Create lib/services/supabase_service.dart with:
   - Singleton pattern for Supabase client
   - Initialize method that creates Supabase client with URL and anon key from env config
   - Getter for the client instance
   - Method to check connection status
   - Error handling with proper logging

4. Update lib/main.dart to initialize SupabaseService before running the app

5. Write unit tests in test/models/user_test.dart to verify:
   - User model serialization/deserialization
   - copyWith creates new instances correctly
   - Equality works as expected

6. Write unit tests in test/models/permission_test.dart for Permission model

7. Write integration tests in test/services/supabase_service_test.dart (using mocks) to verify:
   - Service initializes correctly
   - Singleton pattern works
   - Error handling for invalid credentials

Ensure all tests pass before proceeding.
```

**Expected Outcome:**
- User and Permission models defined
- Supabase service initialized
- Comprehensive model tests
- Service integration tests
- All tests passing

---

### Prompt 5: Google OAuth Authentication Service

**Context:** Implement Google Workspace authentication for employee users.

**Prompt:**

```
Now let's implement Google OAuth authentication for employees.

1. Create lib/services/auth_service.dart with:
   - Initialize Google Sign In with the client ID from env config
   - Configure to only allow @saturdayvinyl.com domain accounts
   - signInWithGoogle() method that:
     - Initiates Google OAuth flow
     - Gets Google credentials
     - Signs in to Supabase with Google provider
     - Returns the authenticated user or error
   - signOut() method
   - getCurrentUser() method that returns current Supabase user
   - Stream of auth state changes
   - Proper error handling and logging for each step

2. Create lib/repositories/user_repository.dart with:
   - Method to get or create user in Supabase database after Google auth
   - If user doesn't exist, create with default permissions (viewer)
   - If user exists, update lastLogin timestamp
   - Method to get user permissions from database
   - Method to check if user has specific permission
   - All database queries should be properly typed and use models

3. Create lib/providers/auth_provider.dart using Riverpod with:
   - authServiceProvider (singleton)
   - userRepositoryProvider (singleton)
   - authStateProvider (stream of auth state changes)
   - currentUserProvider (async, fetches current user data from database)
   - userPermissionsProvider (async, fetches user's permissions)

4. Write tests in test/services/auth_service_test.dart with mocks to verify:
   - Sign in flow works correctly
   - Domain validation (reject non-@saturdayvinyl.com accounts)
   - Sign out clears session
   - Error handling for auth failures

5. Write tests in test/repositories/user_repository_test.dart to verify:
   - User creation on first login
   - User update on subsequent logins
   - Permission checking logic

Don't integrate with UI yet - just ensure the services and providers are working with tests.
```

**Expected Outcome:**
- Google OAuth service implemented
- User repository for database operations
- Riverpod providers for auth state
- Comprehensive tests for auth flow
- Domain validation working

---

### Prompt 6: Login Screen UI

**Context:** Create the login screen with Google authentication integration.

**Prompt:**

```
Let's build the login screen UI.

1. Create lib/widgets/common/app_button.dart with:
   - Reusable button widget using Saturday brand colors
   - Support for primary, secondary, and text button styles
   - Loading state (show spinner)
   - Disabled state
   - Customizable text and onPressed callback

2. Create lib/widgets/common/loading_indicator.dart with:
   - Centered circular progress indicator using brand colors
   - Optional message text below spinner

3. Create lib/screens/auth/login_screen.dart with:
   - Display Saturday! logo (from assets)
   - "Sign in with Google" button
   - Use ConsumerWidget to access auth providers
   - Show loading indicator during sign-in
   - Handle sign-in errors with user-friendly messages
   - Navigate to dashboard on successful auth
   - Proper responsive layout (works on mobile and desktop)

4. Create lib/screens/dashboard/dashboard_screen.dart (placeholder) with:
   - AppBar with "Dashboard" title
   - Display current user's email
   - Logout button
   - Placeholder text: "Dashboard coming soon"

5. Update lib/main.dart to:
   - Wrap app in ProviderScope (Riverpod)
   - Use authStateProvider to determine initial route
   - Show LoginScreen if not authenticated
   - Show DashboardScreen if authenticated
   - Show loading indicator while checking auth state

6. Create widget tests in test/screens/auth/login_screen_test.dart to verify:
   - Logo is displayed
   - Sign-in button is present
   - Loading state shows spinner
   - Error messages display correctly

Run the app manually to test the full authentication flow:
- Launch app → see login screen
- Click "Sign in with Google" → Google OAuth flow
- Successful auth → navigate to dashboard
- Logout → return to login screen
```

**Expected Outcome:**
- Reusable button and loading widgets
- Login screen with Google sign-in
- Dashboard placeholder
- Navigation based on auth state
- Widget tests for login screen
- Manual testing successful

---

### Prompt 7: User Profile and Session Management

**Context:** Add user profile display and session management features.

**Prompt:**

```
Let's add user profile display and improve session management.

1. Create lib/widgets/common/user_avatar.dart with:
   - Circular avatar showing user's initials or profile photo
   - Use Google profile photo if available, otherwise show initials
   - Brand color background
   - Size variants (small, medium, large)

2. Update lib/screens/dashboard/dashboard_screen.dart to:
   - Show user avatar in AppBar
   - Display full user name and email in a profile section
   - Show user's permissions (read-only for now)
   - Show "Admin" badge if user is admin
   - Improve logout button styling

3. Create lib/utils/extensions.dart with:
   - String extension to get initials (e.g., "John Doe" → "JD")
   - DateTime extension for friendly formatting ("Oct 8, 2025" or "2 hours ago")
   - Extension to check if user has specific permission

4. Update lib/services/auth_service.dart to:
   - Add session refresh logic (refresh token before 1-week expiry)
   - Add method to check session validity
   - Listen for session expiry and notify user

5. Add lib/providers/session_provider.dart with:
   - Provider that monitors session expiry
   - Shows warning when session will expire soon
   - Auto-refreshes token when needed

6. Write tests in test/utils/extensions_test.dart to verify:
   - Initials extraction works correctly
   - Date formatting is accurate
   - Permission checking helper works

7. Write widget tests for the updated dashboard screen

Run the app and verify:
- User profile displays correctly after login
- Permissions are shown
- Admin badge appears for admin users (test with seeded admin account)
- Session stays active
```

**Expected Outcome:**
- User avatar widget
- Enhanced dashboard with profile info
- Utility extensions for common operations
- Session management with auto-refresh
- Tests for extensions and widgets
- Working profile display

---

### Prompt 8: User Management Screen (Admin Only)

**Context:** Create the user management interface for admins to view users and assign permissions.

**Prompt:**

```
Let's build the user management screen for admins.

1. Create lib/models/user_permission.dart with:
   - UserPermission model representing the user-permission join table
   - Properties: userId, permissionId, grantedAt, grantedBy
   - fromJson/toJson methods

2. Update lib/repositories/user_repository.dart with:
   - Method to fetch all users (admin only)
   - Method to grant permission to user
   - Method to revoke permission from user
   - Method to fetch all available permissions
   - Proper error handling and permission checks

3. Create lib/providers/users_provider.dart with:
   - Provider for list of all users (filtered based on current user being admin)
   - Provider for available permissions
   - Methods to grant/revoke permissions

4. Create lib/screens/users/user_management_screen.dart with:
   - Only accessible to admin users (show error if non-admin tries to access)
   - List of all users with their email, role, and active status
   - Tap user to see detail view
   - Search/filter functionality (search by email or name)
   - Responsive design for desktop and mobile

5. Create lib/screens/users/user_detail_screen.dart with:
   - Display user details (name, email, role, created date, last login)
   - Show all available permissions with checkboxes
   - Checked = user has permission, unchecked = user doesn't
   - Only admin can toggle permissions
   - Confirmation dialog before granting/revoking permissions
   - Show who granted each permission and when

6. Create lib/widgets/navigation/sidebar_nav.dart (desktop) with:
   - Collapsible sidebar navigation
   - Menu items: Dashboard, Products, Production Units, Firmware, Users (admin only)
   - Highlight current route
   - Saturday! logo at top
   - User profile section at bottom

7. Update lib/screens/dashboard/dashboard_screen.dart to:
   - Use sidebar navigation on desktop
   - Keep current content as main dashboard view

8. Write widget tests for user management screens

9. Write integration tests to verify:
   - Only admins can access user management
   - Permissions can be granted/revoked
   - Changes persist to database

Test manually:
- Log in as admin → see Users menu item
- Open user management → see all users
- Open user detail → toggle permissions
- Verify permissions are saved
- Log in as non-admin → Users menu hidden
```

**Expected Outcome:**
- User management screen for admins
- Permission grant/revoke functionality
- Sidebar navigation for desktop
- Access control enforcement
- Tests for admin-only features
- Working user administration

---

## Phase 2: Product Management (Prompts 9-13)

### Prompt 9: Product and Variant Models

**Context:** Create data models for products, variants, and production steps from Shopify.

**Prompt:**

```
Let's create the product-related data models.

1. Create lib/models/product.dart with:
   - Product model with properties: id, shopifyProductId, shopifyProductHandle, name, productCode, description, isActive, createdAt, updatedAt, lastSyncedAt
   - fromJson/toJson methods
   - copyWith method
   - Equality and hashCode overrides

2. Create lib/models/product_variant.dart with:
   - ProductVariant model with: id, productId, shopifyVariantId, sku, name, option1Name, option1Value, option2Name, option2Value, option3Name, option3Value, price, isActive, createdAt, updatedAt
   - fromJson/toJson with proper null handling for options
   - Method to get formatted variant name (e.g., "Walnut / Black Liner")
   - copyWith, equality, hashCode

3. Create lib/models/production_step.dart with:
   - ProductionStep model with: id, productId, name, description, stepOrder, fileUrl, fileName, fileType, createdAt, updatedAt
   - fromJson/toJson methods
   - copyWith, equality, hashCode
   - Validation: stepOrder must be positive, name required

4. Create lib/models/device_type.dart with:
   - DeviceType model with: id, name, description, capabilities (List<String>), specUrl, isActive, createdAt, updatedAt
   - fromJson/toJson with array handling for capabilities
   - copyWith, equality, hashCode
   - Helper method to check if device has specific capability

5. Create lib/models/product_device_type.dart with:
   - Join model for product-device relationship
   - Properties: productId, deviceTypeId, quantity
   - fromJson/toJson methods

6. Write comprehensive unit tests for all models in test/models/ directory:
   - Serialization/deserialization
   - copyWith functionality
   - Validation logic
   - Helper methods (e.g., formatted variant name)
   - Equality comparisons

Ensure all tests pass. Don't integrate with UI yet - this is just the data layer.
```

**Expected Outcome:**
- Product, variant, and production step models
- Device type models
- Comprehensive model tests
- All validations working
- Clean data layer ready for integration

---

### Prompt 10: Shopify GraphQL Service

**Context:** Implement the Shopify GraphQL API client for syncing products and variants.

**Prompt:**

```
Let's build the Shopify integration service.

1. Create lib/services/shopify_service.dart with:
   - GraphQL client initialization using dio and graphql_flutter
   - Authenticate with Shopify access token from env config
   - Use Shopify Admin API version 2024-10 (or latest stable)
   - Method: fetchProducts() that:
     - Queries Shopify for all products with variants
     - Handles pagination (Shopify returns max 250 at a time)
     - Returns list of raw product data
     - Includes error handling and retry logic with exponential backoff
   - Method: fetchProduct(shopifyProductId) for single product fetch
   - Method: fetchOrders() for order sync (basic implementation, we'll expand later)
   - Rate limiting to respect Shopify API limits
   - Comprehensive logging for all API calls

2. Create the GraphQL queries in lib/services/shopify_queries.dart:
   - PRODUCTS_QUERY: fetch id, handle, title, description, variants (id, sku, title, price, selectedOptions)
   - PRODUCT_QUERY: fetch single product by ID
   - ORDERS_QUERY: fetch orders with customer info (we'll use this later)

3. Create lib/repositories/product_repository.dart with:
   - Method: syncProductsFromShopify() that:
     - Fetches products from Shopify service
     - Transforms Shopify data to Product and ProductVariant models
     - Upserts to Supabase (insert if new, update if existing)
     - Returns count of products synced
     - Updates lastSyncedAt timestamp
   - Method: getProducts() - fetch all products from Supabase
   - Method: getProduct(id) - fetch single product with variants
   - Method: getProductVariants(productId) - fetch variants for a product
   - All methods should use proper error handling and logging

4. Create lib/providers/product_provider.dart with Riverpod:
   - productsProvider - stream/future of all products
   - productProvider(id) - single product by ID
   - productVariantsProvider(productId) - variants for a product
   - syncProductsProvider - method provider for triggering sync

5. Write unit tests in test/services/shopify_service_test.dart with mocks:
   - Verify GraphQL queries are formatted correctly
   - Test pagination handling
   - Test error handling and retry logic
   - Test rate limiting

6. Write integration tests in test/repositories/product_repository_test.dart:
   - Test Shopify data transformation to models
   - Test upsert logic (insert new, update existing)
   - Verify sync updates timestamps

Don't build UI yet. Focus on getting the data sync working with tests.
```

**Expected Outcome:**
- Shopify GraphQL service implemented
- Product repository with sync logic
- Riverpod providers for products
- Comprehensive tests for Shopify integration
- Data sync working with test data

---

### Prompt 11: Product List and Detail Screens

**Context:** Build UI for viewing products synced from Shopify.

**Prompt:**

```
Let's create the product viewing screens.

1. Create lib/widgets/common/empty_state.dart with:
   - Reusable widget for empty states
   - Icon, message, and optional action button
   - Use brand styling

2. Create lib/widgets/common/error_state.dart with:
   - Widget for error display
   - Error icon, message, and retry button
   - Use brand error color

3. Create lib/widgets/products/product_card.dart with:
   - Card displaying product name, product code, variant count
   - Tap to navigate to detail view
   - Show sync status icon if recently synced
   - Responsive for mobile and desktop

4. Create lib/screens/products/product_list_screen.dart with:
   - AppBar with title "Products" and sync button
   - Use ConsumerWidget to watch productsProvider
   - Show loading state while fetching
   - Show empty state if no products
   - Show error state if sync fails
   - List/Grid of product cards (grid on desktop, list on mobile)
   - Pull-to-refresh on mobile
   - Manual "Sync from Shopify" button
   - Show last sync timestamp
   - Search bar to filter products by name or code

5. Create lib/screens/products/product_detail_screen.dart with:
   - Display product details: name, code, description, Shopify ID
   - List of all variants with their options and prices
   - Section for production steps (read-only for now, shows "No steps configured" if empty)
   - Section for device types (empty for now)
   - Link to Shopify admin (open in browser)
   - "Edit" button (only for users with manage_products permission) - disabled for now, we'll implement later

6. Update lib/widgets/navigation/sidebar_nav.dart to:
   - Add Products menu item
   - Navigate to ProductListScreen when clicked

7. Create lib/config/routes.dart with:
   - Named routes for all screens
   - Route guards for permission-based access

8. Write widget tests for product screens:
   - Test loading, empty, and error states
   - Test product card rendering
   - Test navigation to detail view
   - Test sync button functionality

9. Write integration tests for the full flow:
   - Navigate to products → trigger sync → see products → tap product → see details

Test manually with real Shopify data:
- Set up test Shopify store with 2-3 products
- Launch app → navigate to Products
- Click "Sync from Shopify"
- Verify products appear
- Tap product → see details and variants
```

**Expected Outcome:**
- Product list and detail screens
- Shopify sync UI
- Empty and error states
- Search and filter functionality
- Navigation integrated
- Widget and integration tests
- Manual testing with real Shopify data successful

---

### Prompt 12: Production Step Configuration (Part 1 - UI)

**Context:** Allow admins to configure production steps for each product.

**Prompt:**

```
Let's build the UI for configuring production steps.

1. Create lib/repositories/production_step_repository.dart with:
   - Method: getStepsForProduct(productId) - fetch all steps for a product, ordered by stepOrder
   - Method: createStep(ProductionStep) - insert new step
   - Method: updateStep(ProductionStep) - update existing step
   - Method: deleteStep(stepId) - delete step
   - Method: reorderSteps(productId, List<stepId>) - update stepOrder for multiple steps
   - All methods require user to have manage_products permission (check in repository)

2. Create lib/providers/production_step_provider.dart with:
   - productionStepsProvider(productId) - stream/future of steps for a product
   - Methods for CRUD operations on steps

3. Create lib/screens/products/production_steps_config_screen.dart with:
   - Accessible from product detail screen
   - Only users with manage_products permission can access
   - Display all production steps in order
   - Drag-and-drop to reorder steps (use reorderable_list)
   - "Add Step" button
   - Each step shows: order number, name, description preview, file name (if attached)
   - Edit and delete buttons for each step
   - Confirmation dialog before deleting

4. Create lib/screens/products/production_step_form_screen.dart with:
   - Form for creating/editing a production step
   - Fields: name (required), description (multiline text), file upload (optional)
   - File picker for selecting local file
   - Show file name and size after selection
   - Validation: name required, stepOrder auto-assigned
   - Save and cancel buttons
   - Show loading state while saving

5. Update lib/screens/products/product_detail_screen.dart to:
   - Show list of production steps (read-only)
   - "Configure Steps" button (only visible if user has manage_products permission)
   - Navigate to ProductionStepsConfigScreen

6. Create lib/widgets/products/production_step_item.dart with:
   - Widget to display a single production step
   - Show step number, name, description snippet
   - Show file icon if step has file attached
   - Edit/delete actions (if editable)
   - Drag handle for reordering

7. Write widget tests for production step screens

8. Write integration tests:
   - Create product step → verify saved to database
   - Update step → verify changes persist
   - Delete step → verify removed from database
   - Reorder steps → verify new order saved

Don't implement file upload to Supabase storage yet - just UI for file selection. We'll wire up storage in the next step.
```

**Expected Outcome:**
- Production step configuration UI
- CRUD operations for steps
- Reordering functionality
- Permission-based access control
- Tests for step management
- File selection UI (upload pending)

---

### Prompt 13: File Upload to Supabase Storage

**Context:** Implement file upload functionality for production step files.

**Prompt:**

```
Let's implement file upload to Supabase storage.

1. Create lib/services/storage_service.dart with:
   - Initialize with Supabase storage client
   - Method: uploadProductionFile(File, productId, stepId) that:
     - Generates unique file name (stepId-timestamp-originalname)
     - Uploads to 'production-files' bucket in Supabase
     - Returns public URL of uploaded file
     - Handles upload errors with retry logic
   - Method: deleteProductionFile(fileUrl) - deletes file from storage
   - Method: downloadFile(fileUrl, localPath) - downloads file to local storage
   - Track upload progress (for future progress bar)
   - Validate file size (max 50MB for production files)

2. Update lib/repositories/production_step_repository.dart to:
   - Use StorageService when creating/updating steps with files
   - Upload file first, then save step with file URL
   - If step update fails, clean up uploaded file (rollback)
   - When deleting step, also delete associated file from storage

3. Update lib/screens/products/production_step_form_screen.dart to:
   - Integrate file upload on save
   - Show upload progress indicator
   - Handle upload errors gracefully
   - Allow removing/replacing file before save
   - Show preview of file name and size

4. Create lib/widgets/common/file_upload_widget.dart with:
   - Reusable file upload component
   - Drag-and-drop area (desktop) or file picker button (mobile)
   - Show selected file details
   - Remove file button
   - Upload progress bar
   - Error display

5. Set up Supabase storage bucket:
   - Create 'production-files' bucket in Supabase dashboard
   - Set bucket to private (authenticated users only)
   - Configure storage policies for read/write access

6. Write tests in test/services/storage_service_test.dart:
   - Test file upload with mock file
   - Test error handling for upload failures
   - Test file deletion
   - Test file size validation

7. Write integration tests for the full flow:
   - Select file → upload → save step → verify file URL in database
   - Edit step → change file → verify old file deleted, new file uploaded
   - Delete step → verify file deleted from storage

Test manually:
- Create production step with gcode file
- Verify file uploaded to Supabase storage
- Edit step and change file
- Verify old file removed, new file uploaded
- Delete step
- Verify file removed from storage
```

**Expected Outcome:**
- Supabase storage service
- File upload integrated with step creation
- Progress indicators and error handling
- Storage bucket configured
- File lifecycle management (upload, replace, delete)
- Tests for storage operations
- Manual testing successful

---

## Phase 3: Production Unit Tracking (Prompts 14-19)

### Prompt 14: Production Unit Models and QR Code Generation

**Context:** Create models for production units and implement QR code generation with logo embedding.

**Prompt:**

```
Let's build the production unit models and QR code generation.

1. Create lib/models/production_unit.dart with:
   - ProductionUnit model with properties: id, uuid, unitId, productId, variantId, orderId (nullable), currentOwnerId (nullable), qrCodeUrl, productionStartedAt, productionCompletedAt, isCompleted, createdAt, createdBy
   - fromJson/toJson methods
   - copyWith, equality, hashCode
   - Method: getFormattedUnitId() that returns the full unit ID
   - Method: isInProgress() - returns true if started but not completed
   - Validation: unitId format must match "SV-{PRODUCT_CODE}-{NUMBER}"

2. Create lib/models/unit_step_completion.dart with:
   - UnitStepCompletion model: id, unitId, stepId, completedAt, completedBy, notes
   - fromJson/toJson methods
   - copyWith, equality, hashCode

3. Create lib/services/qr_service.dart with:
   - Method: generateQRCode(uuid, {size, embedLogo}) that:
     - Creates QR code with URL: "{APP_BASE_URL}/unit/{uuid}"
     - Embeds Saturday icon logo in center of QR code
     - Uses high error correction level (to accommodate logo)
     - Returns QR code as image data (Uint8List)
   - Method: generateQRCodeUrl(qrImageData) that:
     - Uploads QR code image to Supabase storage 'qr-codes' bucket (public)
     - Returns public URL
   - Method: parseQRCode(scannedText) that:
     - Extracts UUID from scanned URL
     - Validates URL format
     - Returns UUID or throws error if invalid

4. Update lib/services/storage_service.dart to:
   - Add method: uploadQRCode(imageData, uuid) - uploads to 'qr-codes' bucket
   - QR codes bucket should be public (readable by anyone)

5. Create lib/utils/id_generator.dart with:
   - Method: generateUnitId(productCode, sequenceNumber) that:
     - Formats as "SV-{PRODUCT_CODE}-{SEQUENCE}" with zero-padding (e.g., "SV-PROD1-00001")
   - Method: getNextSequenceNumber(productCode) that:
     - Queries database for highest sequence number for product code
     - Returns next number in sequence

6. Set up Supabase storage bucket:
   - Create 'qr-codes' bucket (public read access)
   - Configure storage policies

7. Write unit tests in test/models/production_unit_test.dart

8. Write tests in test/services/qr_service_test.dart:
   - Test QR code generation with logo
   - Test URL parsing from scanned code
   - Test invalid QR code handling

9. Write tests in test/utils/id_generator_test.dart:
   - Test unit ID formatting
   - Test sequence number generation

Ensure all tests pass. Don't build UI yet - this is foundation work.
```

**Expected Outcome:**
- Production unit models defined
- QR code generation with logo embedding
- Unit ID generation logic
- URL parsing for scanned codes
- Storage bucket for QR codes
- Comprehensive tests
- All tests passing

---

### Prompt 15: Production Unit Repository and Providers

**Context:** Build the data access layer for production units.

**Prompt:**

```
Let's create the repository and providers for production units.

1. Create lib/repositories/production_unit_repository.dart with:
   - Method: createProductionUnit(productId, variantId, orderId?, userId) that:
     - Gets product code from product
     - Generates next sequence number
     - Creates unit ID (e.g., "SV-PROD1-00001")
     - Generates UUID
     - Generates QR code with logo
     - Uploads QR code to storage
     - Inserts unit record to database with QR URL
     - Returns created ProductionUnit
     - All in a transaction (rollback if any step fails)
   - Method: getUnitsInProduction() - returns all units where isCompleted = false
   - Method: getUnitByUuid(uuid) - fetch unit for QR code lookup
   - Method: getUnitById(id) - fetch unit by primary key
   - Method: getUnitSteps(unitId) - fetch all production steps for unit's product
   - Method: getUnitStepCompletions(unitId) - fetch all completed steps for unit
   - Method: completeStep(unitId, stepId, userId, notes?) that:
     - Creates step completion record
     - Checks if all steps complete, if so mark unit as completed
     - Returns updated unit
   - Method: markUnitComplete(unitId) - manually mark unit as complete
   - All methods require manage_production permission (except read operations)

2. Create lib/providers/production_unit_provider.dart with Riverpod:
   - unitsInProductionProvider - stream of units in production
   - unitProvider(uuid) - single unit by UUID
   - unitStepsProvider(unitId) - production steps for unit
   - unitCompletionsProvider(unitId) - completed steps for unit
   - Method providers for creating units and completing steps

3. Create lib/models/order.dart and lib/models/customer.dart (minimal for now):
   - Order: id, shopifyOrderId, shopifyOrderNumber, customerId, orderDate, status
   - Customer: id, shopifyCustomerId, email, firstName, lastName
   - fromJson/toJson methods
   - We'll expand these later when we implement order sync

4. Write unit tests in test/repositories/production_unit_repository_test.dart:
   - Test unit creation flow (ID generation, QR generation, database insert)
   - Test transaction rollback if QR upload fails
   - Test fetching units in production
   - Test step completion logic
   - Test auto-complete when all steps done

5. Write integration tests for the full production unit lifecycle:
   - Create unit → complete steps one by one → verify unit marked complete

Ensure all repository logic works correctly with tests before moving to UI.
```

**Expected Outcome:**
- Production unit repository with full CRUD
- Transaction handling for unit creation
- Step completion logic
- Riverpod providers for production data
- Order and customer models (basic)
- Comprehensive repository tests
- Integration tests passing

---

### Prompt 16: Create Production Unit Flow

**Context:** Build the UI for creating new production units with QR generation.

**Prompt:**

```
Let's build the UI for creating production units.

1. Create lib/repositories/order_repository.dart with:
   - Method: getUnassignedOrders() - fetch orders from Shopify that don't have production units yet
   - Method: getOrderById(id) - fetch single order
   - We'll implement full Shopify order sync later; for now, return mock data or empty list

2. Create lib/screens/production/create_unit_screen.dart with multi-step wizard:
   - Step 1: Select Product
     - List all active products
     - Search/filter by name
     - Continue button
   - Step 2: Select Variant
     - Show variants for selected product
     - Display variant options (wood species, liner color, etc.)
     - Back and Continue buttons
   - Step 3: Associate Order (optional)
     - Show "Recommended Orders" that match selected product/variant
     - Display order number, customer name, order date
     - "Select This Order" button for each
     - "Build for Inventory (No Order)" button
     - Back and Create buttons
   - Step 4: Confirmation
     - Show created unit ID
     - Display generated QR code
     - Show product/variant details
     - Customer info if order selected
     - "Print Label" button (we'll implement printing next)
     - "View Unit" button → navigate to unit detail
     - "Create Another" button → restart wizard

3. Create lib/widgets/production/product_selector.dart:
   - Grid of product cards for selection
   - Highlight selected product
   - Use brand colors for selection state

4. Create lib/widgets/production/variant_selector.dart:
   - List of variant options with radio buttons
   - Display variant attributes clearly
   - Show price (optional info)

5. Create lib/widgets/production/order_selector.dart:
   - List of recommended orders
   - Each order card shows: order number, customer, date
   - Highlight if order matches exact variant
   - "No Order" option prominently displayed

6. Create lib/widgets/production/qr_code_display.dart:
   - Display QR code image from URL
   - Show unit ID below QR code
   - Optional: download QR code button

7. Update lib/widgets/navigation/sidebar_nav.dart:
   - Add "Production Units" menu item
   - Navigate to production list screen (we'll create next)

8. Update lib/screens/dashboard/dashboard_screen.dart:
   - Add "+ New Production Unit" button
   - Navigate to CreateUnitScreen

9. Write widget tests for create unit wizard:
   - Test each step renders correctly
   - Test navigation between steps
   - Test form validation
   - Test unit creation on final step

10. Write integration test for full flow:
    - Select product → select variant → skip order → see confirmation with QR code

Test manually:
- Launch app → click "New Production Unit"
- Go through wizard
- Verify unit created in database
- Verify QR code generated and displayed
- Verify unit ID format correct
```

**Expected Outcome:**
- Multi-step unit creation wizard
- Product and variant selection
- Order association (optional)
- QR code generation and display
- Widget tests for wizard
- Integration test for full flow
- Manual testing successful

---

### Prompt 17: Production Unit List and Detail Screens

**Context:** Build screens to view units in production and individual unit details.

**Prompt:**

```
Let's create the production unit list and detail views.

1. Create lib/widgets/production/unit_card.dart with:
   - Display unit ID prominently
   - Show product name and variant
   - Current step or "Not started" if no steps completed
   - Associated order/customer info if available
   - Production start date
   - Tap to navigate to detail view
   - Use brand colors for different states (in progress, completed)

2. Create lib/screens/production/production_list_screen.dart with:
   - Title "Units in Production"
   - List/grid of all units where isCompleted = false
   - Show loading state
   - Empty state: "No units in production. Create one to get started."
   - Pull to refresh
   - Search by unit ID
   - Floating action button: "Create Unit"
   - For desktop: show in table format with columns (Unit ID, Product, Current Step, Order, Started)

3. Create lib/widgets/production/step_list_item.dart with:
   - Display step number, name, description
   - Completion status: completed (green checkmark) or pending (gray circle)
   - If completed: show who completed and when
   - If completed: show notes (if any)
   - If has file: show file icon and file name
   - "Mark Complete" button if pending (only for users with manage_production permission)
   - Use brand colors for states

4. Create lib/screens/production/unit_detail_screen.dart with:
   - Display QR code at top
   - Unit ID as title
   - Product and variant details
   - Order and customer info (if applicable)
   - Production dates (started, completed if finished)
   - List of all production steps using StepListItem widget
   - Steps displayed in configured order
   - Show completion progress (X of Y steps complete)
   - "Print Label" button
   - "Scan Next QR" button to quickly scan another unit
   - Link to view product details

5. Create lib/widgets/production/unit_progress_bar.dart:
   - Visual progress bar showing X/Y steps complete
   - Use brand success color for completed portion
   - Show percentage

6. Create lib/config/routes.dart updates:
   - Add named routes for production screens
   - Handle navigation with parameters (unitId, uuid, etc.)

7. Write widget tests for production screens:
   - Test unit card rendering
   - Test list view with multiple units
   - Test empty state
   - Test detail view displays all info
   - Test step list rendering

8. Write integration tests:
   - Navigate to production list → tap unit → see details
   - Verify step completion status displayed correctly

Test manually:
- Create a few production units
- View production list
- Tap unit → see detail view
- Verify all information displays correctly
- Verify steps show in correct order
```

**Expected Outcome:**
- Production list screen
- Unit detail screen with full info
- Step list display
- Progress indicators
- Navigation between screens
- Widget and integration tests
- Manual testing successful

---

### Prompt 18: QR Code Scanning (Desktop and Mobile)

**Context:** Implement QR code scanning for both USB scanners (desktop) and camera (mobile).

**Prompt:**

```
Let's implement QR code scanning for production floor use.

1. Create lib/services/qr_scanner_service.dart with:
   - Abstract interface for QR scanning
   - Method: scanQRCode() - returns scanned UUID
   - Desktop implementation: listen for keyboard input from USB scanner
   - Mobile implementation: use camera with mobile_scanner package
   - Parse scanned text to extract UUID
   - Validate UUID format
   - Error handling for invalid codes

2. Create lib/widgets/production/qr_scanner_desktop.dart with:
   - Input field that captures USB scanner keyboard input
   - Auto-focused to receive scanner data
   - Show "Ready to scan" state
   - Show "Scanning..." while processing
   - Navigate to unit detail on successful scan
   - Show error message for invalid code
   - Reset after scan for next code

3. Create lib/widgets/production/qr_scanner_mobile.dart with:
   - Full-screen camera view
   - QR code detection overlay (highlight detected code)
   - "Position QR code in the center to scan" instructions
   - Navigate to unit detail on successful scan
   - Close button to exit scanner
   - Torch/flash toggle for low light
   - Error message for invalid codes

4. Create lib/screens/production/qr_scan_screen.dart with:
   - Platform detection (desktop vs mobile)
   - Use appropriate scanner widget based on platform
   - Handle scan result and navigate to unit detail
   - "Enter Unit ID Manually" fallback option

5. Update lib/screens/production/unit_detail_screen.dart to:
   - Add "Scan Next QR" button
   - Opens QR scanner
   - Quick workflow for production floor: view unit → complete step → scan next unit

6. Update lib/widgets/navigation/sidebar_nav.dart (desktop):
   - Always show QR scanner input field in header or sidebar
   - Workers can scan from any screen

7. Create lib/widgets/navigation/bottom_nav.dart (mobile):
   - Bottom navigation bar for mobile
   - Tabs: Dashboard, Scan QR, Units, More
   - Large scan button in center

8. Update lib/main.dart to:
   - Use bottom navigation on mobile
   - Use sidebar navigation on desktop
   - Platform detection with Platform.isAndroid, Platform.isIOS, etc.

9. Write tests for QR scanning:
   - Test UUID extraction from URL
   - Test invalid code handling
   - Widget tests for scanner UI

10. Write integration tests:
    - Simulate QR scan → verify navigation to unit detail
    - Test manual ID entry fallback

Test manually:
- Desktop: Use USB scanner to scan generated QR codes
- Mobile: Use camera to scan QR codes
- Verify navigation to correct unit
- Test error handling with invalid codes
```

**Expected Outcome:**
- QR scanning for desktop (USB scanner)
- QR scanning for mobile (camera)
- Platform-specific UI
- Navigation based on scanned code
- Manual entry fallback
- Tests for scanning functionality
- Manual testing with real QR codes

---

### Prompt 19: Production Step Completion

**Context:** Implement the workflow for marking production steps as complete.

**Prompt:**

```
Let's build the step completion workflow.

1. Create lib/screens/production/complete_step_screen.dart with:
   - Displayed as modal/dialog
   - Show step name and unit ID
   - Optional notes field (multiline text input)
   - Cancel and Complete buttons
   - Show loading state while saving
   - Auto-dismiss on success
   - Show error message if save fails

2. Update lib/widgets/production/step_list_item.dart to:
   - "Mark Complete" button opens CompleteStepScreen modal
   - Only show button for pending steps
   - Only show button if user has manage_production permission
   - Disable if step already completed

3. Update lib/repositories/production_unit_repository.dart to:
   - Ensure completeStep() creates completion record
   - Record timestamp, user, and optional notes
   - Check if all steps complete after each completion
   - If all steps complete, mark unit as completed and set productionCompletedAt
   - Return updated unit with completion status

4. Create lib/widgets/production/completion_confirmation.dart:
   - Success message when step completed
   - If unit fully complete: "🎉 All steps complete! Unit ready for shipment."
   - Option to print label
   - Option to scan next unit

5. Update lib/screens/production/unit_detail_screen.dart to:
   - Refresh unit data after step completion
   - Show completion confirmation
   - Update progress bar
   - Highlight newly completed step

6. Create lib/providers/recent_completions_provider.dart:
   - Track recently completed steps for current user
   - Used for showing quick stats on dashboard

7. Update lib/screens/dashboard/dashboard_screen.dart to:
   - Show units in production count
   - Show units completed today count
   - Show current user's recent completions
   - Quick actions: Create Unit, Scan QR

8. Write widget tests for step completion:
   - Test completion modal renders
   - Test form validation (notes optional)
   - Test success and error states

9. Write integration tests for completion flow:
   - Open unit detail → mark step complete → verify completion recorded
   - Complete all steps → verify unit marked complete
   - Verify completion shows in dashboard stats

10. Test manually the full production workflow:
    - Create production unit
    - Scan QR code (or navigate to unit)
    - Complete each production step
    - Add notes to some completions
    - Verify final step marks unit complete
    - Verify completed units removed from "in production" list
    - Check dashboard stats updated

This is a critical workflow - test thoroughly!
```

**Expected Outcome:**
- Step completion modal
- Notes capture
- Auto-complete unit when all steps done
- Dashboard stats for completions
- Widget and integration tests
- Full production workflow tested end-to-end
- Manual testing successful

---

## Phase 4: Thermal Label Printing (Prompts 20-21)

### Prompt 20: Label Layout and Print Service

**Context:** Implement thermal label printing for QR codes.

**Prompt:**

```
Let's implement thermal label printing for 1" x 1" labels.

1. Create lib/services/printer_service.dart with:
   - Method: printQRLabel(ProductionUnit) that:
     - Generates print layout for 1" x 1" label
     - Includes: QR code (with logo), unit ID, product name + variant, customer name and order date (if applicable)
     - Uses brand fonts and styling
     - Sends to default thermal printer
   - Method: listAvailablePrinters() - returns connected printers
   - Method: selectPrinter(printerId) - sets default printer
   - Platform-specific: desktop only (not available on mobile)
   - Use Flutter printing package

2. Create lib/widgets/production/print_preview_dialog.dart with:
   - Preview of how label will look
   - 1" x 1" size visualization
   - All label elements visible
   - "Print" and "Cancel" buttons
   - Printer selection dropdown
   - Error handling if no printers available

3. Update lib/screens/production/unit_detail_screen.dart to:
   - "Print Label" button only visible on desktop
   - Opens print preview dialog
   - Show success message after printing
   - Allow reprinting if needed

4. Update lib/screens/production/create_unit_screen.dart (confirmation step) to:
   - Auto-show print preview after unit creation
   - Option to skip printing
   - Continue without printing should still work

5. Create lib/widgets/production/label_layout.dart with:
   - Custom painter or layout widget for label design
   - QR code at top (centered)
   - Unit ID below QR code (bold, large font)
   - Product + variant name (smaller font)
   - Customer name and order date on bottom (if applicable)
   - All text sized to fit in 1" x 1" space
   - High contrast for thermal printing

6. Write service tests in test/services/printer_service_test.dart:
   - Test label generation with all fields
   - Test label generation without order (inventory build)
   - Mock printer communication
   - Test error handling for printer not available

7. Write widget tests for print preview dialog

Integration testing will be manual due to hardware dependency.

Manual testing checklist:
- Connect USB thermal printer to macOS
- Configure printer in system settings
- Create production unit
- Click "Print Label"
- Verify preview looks correct
- Print label
- Verify printed label quality:
  - QR code scannable
  - Text readable
  - All information present
  - Fits on 1" x 1" label
- Test with order (shows customer name)
- Test without order (no customer name)
```

**Expected Outcome:**
- Thermal printer service
- Label layout design (1" x 1")
- Print preview dialog
- Integration with unit creation flow
- Service tests
- Manual testing with real printer successful

---

### Prompt 21: Print Settings and Configuration

**Context:** Add printer configuration options for different workstations.

**Prompt:**

```
Let's add printer configuration and settings.

1. Create lib/models/printer_settings.dart with:
   - PrinterSettings model: defaultPrinterId, labelSize, autoPrint (bool)
   - fromJson/toJson for persistence
   - Validation for printer ID and label size

2. Update lib/services/printer_service.dart to:
   - Load printer settings from local storage
   - Save printer settings when changed
   - Use default printer from settings
   - Auto-print option (skip preview if enabled)

3. Create lib/screens/settings/settings_screen.dart with:
   - Printer configuration section (desktop only)
   - Dropdown to select default printer
   - Checkbox for "Auto-print labels after unit creation"
   - Label size configuration (default 1" x 1", but allow customization)
   - Test print button
   - Save settings button

4. Update lib/widgets/navigation/sidebar_nav.dart to:
   - Add "Settings" menu item at bottom (near user profile)
   - Navigate to settings screen

5. Update lib/screens/production/create_unit_screen.dart to:
   - Check auto-print setting
   - If enabled, print automatically after unit creation (skip preview)
   - If disabled, show print preview dialog

6. Create lib/repositories/settings_repository.dart with:
   - Save/load printer settings from shared_preferences
   - Save/load user preferences (theme, language, etc. for future)

7. Create lib/providers/settings_provider.dart:
   - printerSettingsProvider - current printer settings
   - Methods to update settings

8. Write tests for settings:
   - Test settings persistence
   - Test auto-print logic
   - Widget tests for settings screen

Manual testing:
- Open settings
- Select default printer
- Enable auto-print
- Create unit → verify label prints automatically
- Disable auto-print
- Create unit → verify preview shown
- Test print button in settings
```

**Expected Outcome:**
- Printer settings configuration
- Auto-print option
- Settings persistence
- Settings screen UI
- Tests for settings
- Manual testing successful

---

## Phase 5: Firmware Management (Prompts 22-25)

### Prompt 22: Device Type Management

**Context:** Build UI for managing device types (embedded hardware catalog).

**Prompt:**

```
Let's create the device type management interface.

1. Create lib/repositories/device_type_repository.dart with:
   - Method: getDeviceTypes() - fetch all device types
   - Method: getDeviceType(id) - fetch single device type
   - Method: createDeviceType(DeviceType) - insert new device type
   - Method: updateDeviceType(DeviceType) - update device type
   - Method: deleteDeviceType(id) - soft delete (mark inactive)
   - Permission required: manage_firmware

2. Create lib/providers/device_type_provider.dart:
   - deviceTypesProvider - list of all active device types
   - deviceTypeProvider(id) - single device type
   - Methods for CRUD operations

3. Create lib/screens/firmware/device_type_list_screen.dart with:
   - List of all device types
   - Show: name, capabilities (as badges), active status
   - Search by name
   - "Add Device Type" button (only if user has manage_firmware permission)
   - Tap device type to see details/edit

4. Create lib/screens/firmware/device_type_form_screen.dart with:
   - Form for create/edit device type
   - Fields:
     - Name (required)
     - Description (multiline)
     - Spec URL (link to datasheets)
     - Capabilities (multi-select: BLE, WiFi, Thread, RFID, etc.)
   - Add custom capability option
   - Active/inactive toggle
   - Save and cancel buttons
   - Validation

5. Create lib/widgets/firmware/capability_badge.dart:
   - Small badge displaying capability name
   - Different colors for different types (BLE=blue, WiFi=green, etc.)
   - Used in device type lists

6. Create lib/widgets/firmware/capability_selector.dart:
   - Multi-select widget for capabilities
   - Checkboxes for predefined capabilities
   - Text field to add custom capability
   - Display selected capabilities as badges

7. Update lib/widgets/navigation/sidebar_nav.dart:
   - Add "Firmware" menu item
   - Navigate to device type list (for now, will add firmware list later)

8. Write widget tests for device type screens

9. Write integration tests:
   - Create device type → verify saved
   - Edit device type → verify updated
   - Delete device type → verify marked inactive

Manual testing:
- Navigate to Firmware → Device Types
- Create new device type with capabilities
- Edit device type
- Verify changes persist
```

**Expected Outcome:**
- Device type management UI
- CRUD operations for device types
- Capability selection
- Permission-based access
- Tests for device types
- Manual testing successful

---

### Prompt 23: Firmware Version Management (Part 1 - Upload)

**Context:** Build firmware library with upload functionality.

**Prompt:**

```
Let's create the firmware library and upload interface.

1. Create lib/repositories/firmware_repository.dart with:
   - Method: getFirmwareVersions(deviceTypeId?) - fetch all firmware, optionally filter by device type
   - Method: getFirmwareVersion(id) - fetch single firmware version
   - Method: createFirmwareVersion(FirmwareVersion, File) - upload firmware binary and create record
   - Method: updateFirmwareVersion(FirmwareVersion) - update metadata (not binary)
   - Method: deleteFirmwareVersion(id) - delete firmware and binary
   - Method: markAsProductionReady(id) - toggle production ready status
   - Permission required: manage_firmware

2. Update lib/services/storage_service.dart to:
   - Method: uploadFirmwareBinary(File, deviceTypeId, version) that:
     - Generates filename: {deviceTypeId}-{version}-{timestamp}.bin
     - Uploads to 'firmware-binaries' bucket
     - Returns public URL
     - Validates file is binary format
     - Track file size for display
   - Method: deleteFirmwareBinary(fileUrl)

3. Create lib/providers/firmware_provider.dart:
   - firmwareVersionsProvider(deviceTypeId?) - list of firmware versions
   - firmwareVersionProvider(id) - single firmware version
   - productionFirmwareProvider(deviceTypeId) - latest production-ready firmware for device type
   - Methods for CRUD operations

4. Create lib/screens/firmware/firmware_list_screen.dart with:
   - Tabs: "Device Types" and "Firmware Versions"
   - Firmware Versions tab shows all firmware
   - Group by device type or show flat list with device type labels
   - Display: version, device type, production ready badge, upload date, file size
   - Filter: by device type, production ready status
   - Sort: by version (semantic versioning), date
   - "Upload Firmware" button (only if user has manage_firmware permission)
   - Tap firmware to see details

5. Create lib/screens/firmware/firmware_upload_screen.dart with:
   - Form for uploading firmware
   - Fields:
     - Device type (dropdown, required)
     - Version (text, must be semantic versioning format X.Y.Z)
     - Release notes (multiline text)
     - Binary file (file picker, required)
     - Production ready checkbox (default unchecked)
   - Show file name and size after selection
   - Upload progress bar
   - Validation: version format, device type selected, file selected
   - Save button uploads file then creates record
   - Transaction: rollback if either fails

6. Create lib/utils/validators.dart with:
   - Semantic version validator (format: X.Y.Z where X, Y, Z are numbers)
   - Email validator (for future use)
   - URL validator

7. Write tests for firmware repository and service

8. Write widget tests for firmware screens

9. Write integration tests:
   - Upload firmware → verify file in storage and record in database
   - Delete firmware → verify file and record removed

Manual testing:
- Navigate to Firmware → Firmware Versions
- Click "Upload Firmware"
- Select device type, enter version, add release notes, select binary file
- Upload
- Verify firmware appears in list
- Verify binary file in Supabase storage
```

**Expected Outcome:**
- Firmware upload functionality
- Binary file storage
- Firmware list screen
- Semantic versioning validation
- Tests for firmware management
- Manual testing successful

---

### Prompt 24: Firmware Version Management (Part 2 - Details and Updates)

**Context:** Add firmware detail view and version update functionality.

**Prompt:**

```
Let's build firmware detail view and update capabilities.

1. Create lib/screens/firmware/firmware_detail_screen.dart with:
   - Display firmware version details:
     - Version number (large, prominent)
     - Device type name (link to device type details)
     - Release notes (formatted, multiline)
     - Upload date and uploader name
     - Binary file name and size
     - Production ready status (badge)
   - Download binary button
   - Mark as production ready / Mark as testing (toggle)
   - Edit button (opens edit screen)
   - Delete button (with confirmation)
   - Show units using this firmware (count and list)

2. Create lib/screens/firmware/firmware_edit_screen.dart with:
   - Edit version metadata (version number, release notes, production ready)
   - Cannot change device type or binary file (must upload new version for that)
   - Validation
   - Save changes

3. Update lib/repositories/firmware_repository.dart to:
   - Method: getUnitsWithFirmware(firmwareId) - find all units that have this firmware installed
   - Used to show impact before deleting firmware

4. Create lib/widgets/firmware/firmware_card.dart:
   - Card widget displaying firmware summary
   - Version, device type, production ready badge
   - Upload date
   - Tap to view details

5. Create confirmation dialog for deleting firmware:
   - Show warning if units are using this firmware
   - "Are you sure? X units are currently using this firmware."
   - Require typing firmware version to confirm deletion

6. Write widget tests for firmware detail and edit screens

7. Write integration tests:
   - Edit firmware → verify changes saved
   - Toggle production ready → verify updated
   - Delete firmware → verify removed

Manual testing:
- View firmware details
- Edit release notes
- Toggle production ready status
- Download binary file
- Try to delete firmware (with and without units using it)
```

**Expected Outcome:**
- Firmware detail screen
- Edit firmware metadata
- Production ready toggle
- Delete with safeguards
- Tests for firmware CRUD
- Manual testing successful

---

### Prompt 25: Firmware Provisioning During Production

**Context:** Integrate firmware flashing into production workflow.

**Prompt:**

```
Let's add firmware provisioning to the production workflow.

1. Update lib/repositories/production_unit_repository.dart to:
   - Method: getFirmwareForUnit(unitId) that:
     - Gets device types used in unit's product
     - Gets production-ready firmware for each device type
     - Returns map of deviceTypeId → latest production firmware
   - Method: recordFirmwareInstallation(unitId, deviceTypeId, firmwareVersionId, userId) that:
     - Creates record in unit_firmware_history table
     - Marks firmware provisioning step as complete (if it's a production step)

2. Create lib/models/unit_firmware_history.dart with:
   - UnitFirmwareHistory model: id, unitId, deviceTypeId, firmwareVersionId, installedAt, installedBy, installationMethod
   - fromJson/toJson methods

3. Create lib/screens/production/firmware_flash_screen.dart with:
   - Shown when worker clicks production step for firmware provisioning
   - Display unit information
   - List device types for this unit
   - For each device type:
     - Show recommended firmware version (latest production-ready)
     - Dropdown to select different version if needed
     - "Download & Launch Flashing Tool" button
     - Checkbox: "Firmware flashed successfully"
   - Notes field (optional)
   - "Confirm Installation" button (only enabled if all checkboxes checked)
   - Close/cancel button

4. Update lib/services/file_launcher_service.dart (create if doesn't exist) to:
   - Method: launchFile(fileUrl, fileName) that:
     - Downloads file to temp directory
     - Attempts to open with system default application
     - Platform-specific: desktop only
     - Returns success/failure
   - Method: launchFirmwareFlashTool(binaryPath, deviceType) that:
     - For ESP32: launch terminal with esptool command
     - For other devices: open binary in default app
     - Provide instructions to user on what to do next

5. Update lib/widgets/production/step_list_item.dart to:
   - If step is firmware provisioning, show special firmware icon
   - Open FirmwareFlashScreen instead of CompleteStepScreen

6. Create lib/widgets/firmware/firmware_selector.dart:
   - Dropdown to select firmware version for a device type
   - Show version, production ready badge, upload date
   - Highlight recommended version

7. Write tests for firmware provisioning flow

8. Write integration test:
   - Create unit → navigate to firmware step → select firmware → confirm installation → verify recorded

Manual testing (desktop only):
- Create production unit with product that has device type
- Navigate to firmware provisioning step
- Download firmware binary
- Attempt to launch flashing tool
- Mark as installed
- Verify firmware installation recorded in unit history
```

**Expected Outcome:**
- Firmware selection during production
- Binary download and launch external tools
- Firmware installation tracking
- Integration with production workflow
- Tests for provisioning
- Manual testing successful

---

## Phase 6: File Launching and Production Workflows (Prompts 26-28)

### Prompt 26: File Launching for Production Steps

**Context:** Implement file launching to open production files (gcode, laser designs) in external applications.

**Prompt:**

```
Let's implement file launching for production step files.

1. Complete lib/services/file_launcher_service.dart with:
   - Method: openProductionFile(fileUrl, fileName, fileType) that:
     - Downloads file from Supabase storage to temp directory
     - Determines appropriate application based on file type
     - Launches file in external application
     - Platform-specific (desktop only)
     - Returns success/failure with error message if failed
   - Method: openInDefaultApp(filePath) - open file with system default app
   - Method: openInSpecificApp(filePath, appPath) - open file in specific application
   - Method: getDefaultAppForFileType(fileType) - returns app path if configured
   - Error handling: app not installed, file type not supported, etc.

2. Create lib/models/app_association.dart with:
   - AppAssociation model: fileType, appPath, appName
   - Used to store user preferences for which app opens which file type
   - fromJson/toJson for persistence

3. Update lib/repositories/settings_repository.dart to:
   - Save/load app associations (e.g., .gcode files open in gSender)
   - Method: setAppAssociation(fileType, appPath)
   - Method: getAppAssociation(fileType)

4. Update lib/screens/settings/settings_screen.dart to:
   - Add "File Associations" section (desktop only)
   - List common file types: .gcode, .nc, .svg, .ai, etc.
   - For each: show associated app and "Change" button
   - File picker to select application executable
   - "Use System Default" option

5. Update lib/widgets/production/step_list_item.dart to:
   - If step has file attached, show "Open File" button
   - Desktop: clicking opens file in configured/default app
   - Mobile: clicking downloads file to device
   - Show success message when file opened
   - Show error message if opening fails with suggestion (e.g., "gSender not found. Install gSender or configure in Settings.")

6. Create lib/widgets/production/file_action_button.dart:
   - Reusable button for file actions
   - Desktop: "Open in {AppName}" or "Open File"
   - Mobile: "Download File"
   - Show loading state while downloading
   - Show success/error feedback

7. Write tests in test/services/file_launcher_service_test.dart:
   - Test file download
   - Test app launching (mocked)
   - Test error handling for missing apps

8. Write widget tests for file action button

Manual testing (desktop):
- Configure gSender path in settings (file association for .gcode)
- Create production step with gcode file
- Open unit detail
- Click "Open File" on CNC step
- Verify gSender launches with file
- Test with laser file (SVG)
- Test with no app configured (should use system default)
- Test error case: app path invalid
```

**Expected Outcome:**
- File launching service
- App association configuration
- Settings UI for file types
- Production step integration
- Desktop-specific functionality
- Tests for file launching
- Manual testing successful

---

### Prompt 27: Shopify Order Sync

**Context:** Implement Shopify order synchronization to show recommended units to build.

**Prompt:**

```
Let's implement Shopify order sync for build-to-order workflow.

1. Update lib/services/shopify_service.dart to:
   - Method: fetchOrders(status?, limit?) that:
     - Queries Shopify for orders
     - Filter by status (unfulfilled, fulfilled, etc.)
     - Returns order data with customer info and line items
     - Handles pagination
   - Method: fetchOrder(shopifyOrderId) for single order

2. Update lib/services/shopify_queries.dart to:
   - ORDERS_QUERY: fetch id, orderNumber, createdAt, customer (email, firstName, lastName), lineItems (product, variant, quantity), fulfillmentStatus

3. Update lib/repositories/order_repository.dart to:
   - Method: syncOrdersFromShopify() that:
     - Fetches unfulfilled orders from Shopify
     - Transforms to Order and Customer models
     - Upserts to Supabase
     - Returns count synced
   - Method: getUnfulfilledOrders() - orders without associated production units
   - Method: getOrdersForProductVariant(productId, variantId) - recommended orders for specific variant

4. Create lib/models/order_line_item.dart with:
   - OrderLineItem model: id, orderId, productId, variantId, quantity, price
   - fromJson/toJson

5. Update lib/models/order.dart to:
   - Add lineItems property (List<OrderLineItem>)
   - Add customer property (Customer)
   - Method to check if order needs production unit

6. Create lib/providers/order_provider.dart:
   - ordersProvider - list of unfulfilled orders
   - orderProvider(id) - single order
   - recommendedOrdersProvider(productId, variantId) - filtered orders
   - syncOrdersProvider - trigger sync

7. Update lib/screens/production/create_unit_screen.dart (Step 3: Associate Order):
   - Show orders synced from Shopify
   - Filter to show only orders matching selected product/variant
   - Display order details: order number, customer name, order date, quantity
   - Link to Shopify admin for order details
   - "Sync Orders" refresh button

8. Update lib/repositories/production_unit_repository.dart to:
   - When creating unit with order, link unit to order in database
   - Update order record with associated unit ID

9. Create lib/widgets/production/order_card.dart:
   - Display order summary
   - Order number, customer, date
   - Product/variant line items
   - "Build Unit for This Order" button

10. Write tests for order sync:
    - Test Shopify order fetch
    - Test order transformation
    - Test recommended orders filtering

11. Write integration test:
    - Sync orders → create unit for order → verify linkage

Manual testing with real Shopify store:
- Create test order in Shopify
- Sync orders in app
- Verify order appears in recommended list
- Create production unit for order
- Verify order details show on unit
```

**Expected Outcome:**
- Shopify order sync working
- Order filtering for recommendations
- Order card display
- Unit-to-order linkage
- Tests for order sync
- Manual testing with Shopify successful

---

### Prompt 28: Product-Device-Firmware Integration

**Context:** Connect device types to products and ensure firmware workflow is complete.

**Prompt:**

```
Let's complete the product-device-firmware integration.

1. Update lib/repositories/product_repository.dart to:
   - Method: getDeviceTypesForProduct(productId) - fetch associated device types
   - Method: addDeviceTypeToProduct(productId, deviceTypeId, quantity)
   - Method: removeDeviceTypeFromProduct(productId, deviceTypeId)
   - Method: updateDeviceTypeQuantity(productId, deviceTypeId, quantity)

2. Update lib/providers/product_provider.dart to:
   - productDeviceTypesProvider(productId) - device types for product

3. Update lib/screens/products/product_detail_screen.dart to:
   - Add "Device Types" section
   - List device types used in this product with quantity
   - "Configure Devices" button (only for users with manage_products permission)

4. Create lib/screens/products/product_device_config_screen.dart with:
   - List of all available device types (checkboxes)
   - For each selected device type, quantity input
   - Save button
   - Remove device type option

5. Update lib/screens/products/production_steps_config_screen.dart to:
   - When adding firmware provisioning step, show which device types will be flashed
   - Validate that product has device types configured before allowing firmware step

6. Update lib/screens/production/firmware_flash_screen.dart to:
   - Load device types from product configuration
   - Show quantity needed (e.g., "ESP32 Audio Controller (Qty: 2)")
   - Allow recording firmware for each device separately if quantity > 1

7. Create lib/widgets/firmware/device_type_chip.dart:
   - Small chip displaying device type name
   - Used in product details and firmware screens

8. Write tests for product-device association

9. Write integration test for full firmware workflow:
   - Configure product with device type → create unit → flash firmware → verify recorded

Manual testing:
- Configure product with device types
- Add firmware provisioning step to production workflow
- Create unit for that product
- Go through firmware flashing
- Verify device types appear correctly
- Verify firmware installation recorded
```

**Expected Outcome:**
- Product-device type association
- Device configuration UI
- Firmware workflow validation
- Complete end-to-end firmware tracking
- Tests for associations
- Manual testing successful

---

## Phase 7: Polish and Production Readiness (Prompts 29-33)

### Prompt 29: Responsive Design and Mobile Optimization

**Context:** Optimize UI for mobile devices and ensure responsive design works across platforms.

**Prompt:**

```
Let's optimize the app for mobile and ensure responsive design.

1. Create lib/utils/responsive.dart with:
   - Helper functions: isMobile(context), isTablet(context), isDesktop(context)
   - Responsive breakpoints: mobile < 600px, tablet 600-1200px, desktop > 1200px
   - ResponsiveBuilder widget that shows different layouts based on screen size

2. Update all screens to use responsive design:
   - lib/screens/dashboard/dashboard_screen.dart:
     - Desktop: sidebar navigation, multi-column layout
     - Mobile: bottom navigation, single column
   - lib/screens/products/product_list_screen.dart:
     - Desktop: grid view with 3-4 columns
     - Mobile: list view
   - lib/screens/production/production_list_screen.dart:
     - Desktop: table view with all columns
     - Mobile: card list view with essential info
   - lib/screens/production/unit_detail_screen.dart:
     - Desktop: QR code on left, steps on right (two columns)
     - Mobile: QR code top, steps below (single column)

3. Update lib/widgets/navigation/bottom_nav.dart to:
   - Mobile-optimized bottom navigation
   - Large touch targets (min 44x44 points)
   - Icons with labels
   - Active state highlighting

4. Update lib/widgets/navigation/sidebar_nav.dart to:
   - Responsive: hide on mobile, show on desktop
   - Collapsible on tablet

5. Create lib/widgets/common/responsive_grid.dart:
   - Grid that adjusts column count based on screen size
   - Used for product lists, firmware lists, etc.

6. Update form screens for mobile:
   - Larger text inputs
   - Proper keyboard types (email, number, etc.)
   - Bottom sheet modals instead of dialogs on mobile
   - Floating action buttons for primary actions

7. Test on different screen sizes:
   - Desktop: 1920x1080, 1366x768
   - Tablet: iPad (1024x768)
   - Mobile: iPhone (390x844), Android (360x800)

8. Write responsive widget tests:
   - Test layouts at different breakpoints
   - Verify touch targets are appropriately sized
   - Test navigation works on all platforms

Manual testing:
- Test app on macOS desktop
- Test on iOS device
- Test on Android device
- Verify all screens are usable on each platform
- Check that production workflows work on mobile (scan, complete steps)
```

**Expected Outcome:**
- Responsive design across all screens
- Mobile-optimized UI
- Proper touch targets
- Platform-specific navigation
- Tests for responsive layouts
- Manual testing on all platforms successful

---

### Prompt 30: Error Handling and User Feedback

**Context:** Improve error handling throughout the app and provide better user feedback.

**Prompt:**

```
Let's improve error handling and user feedback across the app.

1. Create lib/utils/error_handler.dart with:
   - Global error handler for unexpected errors
   - User-friendly error messages for common errors
   - Method: handleError(error, context) that:
     - Logs error with stack trace
     - Shows user-friendly message to user
     - Determines if error is recoverable
   - Error categories: NetworkError, AuthError, PermissionError, ValidationError, UnknownError

2. Create lib/widgets/common/error_dialog.dart with:
   - Consistent error dialog design
   - Error icon, message, and action buttons
   - Optional retry button
   - Optional "Contact Support" button (opens email)

3. Create lib/widgets/common/success_snackbar.dart and lib/widgets/common/error_snackbar.dart:
   - Consistent snackbar design for success and error messages
   - Brand colors
   - Auto-dismiss after 3-5 seconds
   - Action button option

4. Update all repositories to:
   - Wrap database operations in try-catch
   - Throw specific error types (not generic Exception)
   - Log errors before rethrowing
   - Provide context in error messages

5. Update all services to:
   - Handle network errors gracefully
   - Implement retry logic for transient failures
   - Timeout handling
   - Show user-friendly messages

6. Update all screens to:
   - Show loading states during async operations
   - Show error states when operations fail
   - Provide retry options
   - Clear error states after successful retry

7. Create lib/models/app_error.dart with:
   - AppError class with: code, message, userMessage, stackTrace, isRecoverable
   - Factory constructors for common error types

8. Add error boundaries to main widget tree:
   - Catch errors at app level
   - Show error screen with restart option
   - Log error for debugging

9. Write tests for error handling:
   - Test error dialog display
   - Test retry logic
   - Test error logging

Manual testing checklist:
- Test network disconnection during Shopify sync
- Test permission errors (non-admin accessing admin features)
- Test invalid QR code scan
- Test file upload failure
- Test form validation errors
- Verify all errors show user-friendly messages
- Verify retry works where applicable
```

**Expected Outcome:**
- Comprehensive error handling
- User-friendly error messages
- Retry logic for recoverable errors
- Consistent error UI
- Error logging
- Tests for error handling
- Manual testing of error scenarios

---

### Prompt 31: Performance Optimization

**Context:** Optimize app performance for production use.

**Prompt:**

```
Let's optimize app performance.

1. Implement pagination for large lists:
   - Update lib/repositories/product_repository.dart:
     - Add pagination to getProducts(limit, offset)
   - Update lib/repositories/production_unit_repository.dart:
     - Add pagination to getUnitsInProduction(limit, offset)
   - Update lib/repositories/firmware_repository.dart:
     - Add pagination to getFirmwareVersions(limit, offset)

2. Create lib/widgets/common/paginated_list.dart:
   - Generic widget for paginated lists
   - Infinite scroll or "Load More" button
   - Loading indicator at bottom while fetching
   - Cache fetched pages

3. Optimize image loading:
   - Use cached_network_image for all remote images
   - Implement image compression for QR code generation
   - Lazy load images in lists
   - Placeholder images while loading

4. Optimize Supabase queries:
   - Add indexes to frequently queried fields (already in schema)
   - Use select() to fetch only needed fields
   - Implement query result caching with expiry
   - Use Supabase real-time subscriptions only where necessary

5. Create lib/utils/cache_manager.dart:
   - In-memory cache for frequently accessed data
   - Cache with TTL (time to live)
   - Methods: get, set, invalidate, clear
   - Cache keys: products, device types, firmware versions

6. Update providers to use caching:
   - Cache products for 5 minutes
   - Cache device types for 10 minutes
   - Cache firmware versions for 5 minutes
   - Invalidate cache on mutations

7. Optimize QR code generation:
   - Generate QR codes in isolate (background thread) to avoid UI blocking
   - Cache generated QR codes in memory

8. Add performance monitoring:
   - Log slow operations (> 2 seconds)
   - Track API response times
   - Monitor memory usage

9. Lazy load heavy widgets:
   - Use lazy_load_scrollview package
   - Defer rendering of off-screen widgets

10. Write performance tests:
    - Benchmark QR code generation
    - Test list scrolling performance with 100+ items
    - Test cache hit/miss rates

Manual testing:
- Create 50+ production units
- Scroll production list smoothly
- Monitor memory usage
- Test with slow network (throttle to 3G)
- Verify app remains responsive
```

**Expected Outcome:**
- Pagination for large lists
- Image loading optimization
- Query optimization and caching
- Background processing for heavy tasks
- Performance monitoring
- Smooth scrolling and responsive UI
- Performance tests

---

### Prompt 32: Database Migrations and Seed Data

**Context:** Set up database migration system and create seed data for development/testing.

**Prompt:**

```
Let's set up database migrations and seed data.

1. Create database/migrations/ directory with SQL migration files:
   - 001_initial_schema.sql - full schema from spec.md
   - 002_add_indexes.sql - performance indexes
   - Add migration version tracking table

2. Create lib/services/migration_service.dart with:
   - Method: checkAndRunMigrations() that:
     - Checks current database version
     - Runs pending migrations in order
     - Updates version tracking
     - Logs migration results
   - Run automatically on app startup

3. Create database/seeds/ directory with seed data:
   - dev_users.sql - seed admin user and test users
   - dev_products.sql - sample products with variants
   - dev_device_types.sql - sample device types (ESP32, etc.)
   - dev_firmware.sql - sample firmware versions
   - Production seeds should be minimal (just essential data)

4. Create lib/services/seed_service.dart with:
   - Method: seedDatabase(environment) that:
     - Loads appropriate seed files based on environment (dev, staging, prod)
     - Inserts seed data
     - Only runs if database is empty
   - Method: resetDatabase() - clears all data and reseeds (dev only)

5. Create database setup script:
   - database/setup.sh (bash script)
   - Creates Supabase buckets (production-files, firmware-binaries, qr-codes)
   - Sets bucket policies
   - Runs migrations
   - Seeds database
   - Can be run on fresh Supabase project

6. Update lib/main.dart to:
   - Check and run migrations on startup
   - Seed database if empty (dev environment only)

7. Create database/README.md with:
   - Instructions for setting up new Supabase project
   - How to run migrations manually
   - How to seed database
   - How to reset development database

8. Document environment setup:
   - Create .env.development.example
   - Create .env.production.example
   - Instructions in README for copying and filling out

Manual setup and testing:
- Create fresh Supabase project
- Run setup script
- Verify tables created
- Verify seed data loaded
- Launch app and verify it connects
- Test with seeded admin user
```

**Expected Outcome:**
- Database migration system
- Seed data for development
- Setup scripts for new environments
- Documentation for database setup
- Environment configuration templates
- Successful fresh setup test

---

### Prompt 33: Testing, Documentation, and Deployment Prep

**Context:** Final testing, documentation, and preparation for deployment.

**Prompt:**

```
Let's complete testing, documentation, and prepare for deployment.

1. Write comprehensive integration tests in test/integration/:
   - test/integration/auth_flow_test.dart - full auth flow
   - test/integration/production_flow_test.dart - create unit → complete steps → mark done
   - test/integration/firmware_flow_test.dart - upload firmware → assign to unit
   - test/integration/shopify_sync_test.dart - sync products and orders
   - Use mocked Supabase and Shopify for deterministic tests

2. Create test utilities in test/helpers/:
   - test_data_factory.dart - factory methods for creating test models
   - mock_services.dart - mock implementations of services
   - test_setup.dart - setup and teardown for tests

3. Update README.md with:
   - Project overview and description
   - Technology stack
   - Prerequisites (Flutter, Supabase account, etc.)
   - Installation instructions
   - Environment setup
   - Running the app (desktop, iOS, Android)
   - Running tests
   - Project structure overview
   - Contributing guidelines

4. Create docs/ directory with:
   - docs/SETUP.md - detailed setup instructions
   - docs/DEVELOPMENT.md - development guidelines, code style, Git workflow
   - docs/ARCHITECTURE.md - architecture overview, data flow diagrams
   - docs/API.md - Supabase and Shopify API integration details
   - docs/DEPLOYMENT.md - deployment instructions for each platform
   - docs/TROUBLESHOOTING.md - common issues and solutions

5. Create user documentation:
   - docs/USER_GUIDE.md - how to use the app (for production workers)
   - docs/ADMIN_GUIDE.md - admin features (user management, product config)
   - Include screenshots (can be added later after UI finalized)

6. Add code documentation:
   - Ensure all public APIs have doc comments
   - Add example usage to complex services
   - Document environment variables
   - Document database schema

7. Set up CI/CD (basic):
   - Create .github/workflows/test.yml - run tests on push
   - Create .github/workflows/build.yml - build app on tag
   - Run linting and formatting checks

8. Create deployment checklist:
   - Pre-deployment: run all tests, check linting, update version
   - Deployment: build apps, upload to distribution
   - Post-deployment: verify on all platforms, smoke test critical flows

9. Security audit:
   - Check for hardcoded secrets
   - Verify .env not committed
   - Check API key permissions
   - Verify row-level security policies in Supabase
   - Test permission enforcement

10. Performance audit:
    - Test with 100+ products, 100+ units
    - Profile app performance
    - Check bundle size
    - Optimize if needed

11. Final manual testing:
    - Full production workflow: create unit → scan → complete all steps → print label
    - Admin workflows: user management, product config, firmware upload
    - Shopify integration: sync products, sync orders, link to Shopify admin
    - Error scenarios: network failure, invalid inputs, permission denied
    - Multi-platform: test on macOS, iOS, Android

12. Version and tag:
    - Update version to 1.0.0 in pubspec.yaml
    - Create git tag v1.0.0
    - Update CHANGELOG.md with release notes

This is the final checkpoint before MVP release!
```

**Expected Outcome:**
- Comprehensive test coverage
- Complete documentation (developer and user)
- CI/CD pipeline
- Security audit complete
- Performance optimized
- Deployment checklist
- Version 1.0.0 ready for release
- All platforms tested and working

---

## Appendix: Prompt Usage Guide

### How to Use These Prompts

1. **Sequential Execution**: Execute prompts in order. Each builds on previous work.

2. **Verification**: After each prompt, verify:
   - All tests pass
   - App still runs
   - No regressions introduced

3. **Iteration**: If a prompt produces incomplete results:
   - Review the output
   - Identify gaps
   - Request refinements before moving to next prompt

4. **Platform Testing**: Test regularly on target platforms:
   - After Phase 1: Test on desktop
   - After Phase 3: Test on mobile
   - After Phase 7: Test on all platforms

5. **Git Workflow**: After each prompt (or logical group):
   - Commit changes with descriptive message
   - Reference prompt number in commit
   - Tag major milestones (end of each phase)

### Customization Notes

- **Shopify Store**: Replace mock Shopify data with real store in Prompt 11
- **Device Types**: Customize device capabilities in Prompt 22 based on actual hardware
- **Printer Models**: Specify actual thermal printer models in Prompt 20
- **Admin User**: Set first admin email before deployment (Prompt 32)

### Testing Strategy

- **Unit Tests**: Run after every prompt
- **Widget Tests**: Run after UI prompts
- **Integration Tests**: Run at end of each phase
- **Manual Testing**: Critical after Prompts 6, 16, 20, 25, 33

### Estimated Timeline

Based on a solo developer new to Flutter/Supabase:

- **Phase 0 (Prompts 1-3)**: 1-2 days
- **Phase 1 (Prompts 4-8)**: 1-2 weeks
- **Phase 2 (Prompts 9-13)**: 1-2 weeks
- **Phase 3 (Prompts 14-19)**: 2-3 weeks
- **Phase 4 (Prompts 20-21)**: 3-5 days
- **Phase 5 (Prompts 22-25)**: 1-2 weeks
- **Phase 6 (Prompts 26-28)**: 1 week
- **Phase 7 (Prompts 29-33)**: 1-2 weeks

**Total: 8-12 weeks**

### Key Decision Points

Prompts where architectural decisions may need adjustment:

- **Prompt 2**: Theme customization
- **Prompt 5**: Auth domain restrictions
- **Prompt 10**: Shopify API version
- **Prompt 14**: QR code URL format
- **Prompt 20**: Label size and layout
- **Prompt 26**: File type associations

### Success Criteria

Before considering MVP complete:

- [ ] All 33 prompts executed
- [ ] All tests passing (unit, widget, integration)
- [ ] Manual testing complete on macOS, iOS, Android
- [ ] Documentation complete
- [ ] Security audit passed
- [ ] Performance acceptable (no major lag)
- [ ] Deployment to TestFlight/internal tracks successful
- [ ] First admin user can log in and use all features
- [ ] Production floor workflow tested end-to-end

---

**Document Version**: 1.0
**Last Updated**: October 8, 2025
**Total Prompts**: 33
**Estimated Completion**: 8-12 weeks
