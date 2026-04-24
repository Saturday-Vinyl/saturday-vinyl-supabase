# Product Image Slot Editor — Admin App Feature Prompt

## Overview

Build a WYSIWYG editor that allows admins to define **album cover compositing slots** for product images. This data drives the consumer app's product image rendering, which perspective-transforms album art into product photos (e.g., showing a vinyl record's cover art inside a Saturday Crate).

## Data Model

### Table: `product_image_slots`

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `product_id` | UUID (FK → products) | Which product this slot belongs to |
| `angle` | TEXT | View angle: `front`, `angle`, `top`, etc. |
| `capacity` | TEXT | Crate fill level: `full`, `half`, `empty`. Use `full` for non-crate products. |
| `slot_data` | JSONB | Transform + clip polygon (see below) |

**Unique constraint:** `(product_id, angle, capacity)`

### `slot_data` JSON Structure

```json
{
  "transform": [
    {"x": 380, "y": 300},
    {"x": 920, "y": 310},
    {"x": 910, "y": 850},
    {"x": 370, "y": 840}
  ],
  "clip": [
    {"x": 370, "y": 320},
    {"x": 925, "y": 325},
    {"x": 920, "y": 850},
    {"x": 370, "y": 845}
  ]
}
```

All coordinates are in **source image pixel space** (e.g., within a 1310×1310 product image).

### Related Table: `product_image_assets`

| Column | Type | Description |
|--------|------|-------------|
| `variant_id` | UUID (FK → product_variants) | Which variant this frame image is for |
| `angle` | TEXT | View angle (matches `product_image_slots.angle`) |
| `frame_path` | TEXT | Supabase Storage path to the product frame image |
| `image_width` | INT | Source image width in pixels |
| `image_height` | INT | Source image height in pixels |

The frame images are **variant-specific** (different wood finishes, colors) while slots are **product-level** (same slot geometry across all variants).

## What the Editor Needs to Do

### Screen 1: Product/Angle/Capacity Selection

1. Select a product from the `products` table
2. Select an angle (`front`, `angle`, `top`)
3. Select a capacity (`full`, `half`, `empty`) — only show for crate-type products
4. Load the product frame image for any variant of that product (used as the background for editing)
5. Load existing `slot_data` if a row already exists for this product/angle/capacity

### Screen 2: WYSIWYG Slot Editor

Display the product frame image at full resolution with two interactive overlay modes:

#### Mode 1: Transform Editor (4 corners)

- Show 4 draggable corner handles overlaid on the product image
- Corners define where the album cover's TL, TR, BR, BL will map to
- The corners form a quadrilateral (not necessarily rectangular) to allow perspective skew
- **Live preview:** Show a sample album cover image perspective-transformed into the quad as the user drags corners
- Corner order: top-left → top-right → bottom-right → bottom-left (clockwise)

**Visual guidance:**
- Draw lines connecting the 4 corners to show the quad outline
- Show the sample album texture-mapped into the quad in real-time
- Display coordinate values next to each handle

#### Mode 2: Clip Editor (N-point polygon)

- Show N draggable points overlaid on the product image
- Points define the visible area — album art outside this polygon is hidden by the product frame
- Allow adding/removing points (minimum 3)
- **Live preview:** Show the clipped album to verify occlusion looks correct

**Visual guidance:**
- Draw the polygon outline with a semi-transparent fill
- Show which parts of the album will be hidden (dim/striped overlay outside polygon)

#### Combined Preview

- A "Preview" toggle that renders the final composite exactly as the consumer app would see it:
  1. Album perspective-transformed into the transform quad
  2. Clipped to the clip polygon
  3. Frame drawn on top with clip area cleared

### Save Action

- Upsert the `product_image_slots` row with the edited `slot_data`
- Validate: transform must have exactly 4 points, clip must have ≥ 3 points

## How the Consumer App Uses This Data

The consumer app's `ProductCompositePainter` (Flutter `CustomPainter`) renders in this order:

1. **Clip:** Set `canvas.clipPath()` using the clip polygon
2. **Transform:** Compute a perspective `Matrix4` that maps the album's rectangle to the 4 transform corners
3. **Draw album:** `canvas.drawImage()` with the perspective transform applied — the album appears skewed to match the product's angle
4. **Draw frame:** Draw the product frame image on top, using `BlendMode.clear` to punch out the clip area so the album shows through underneath

### Perspective Transform Math

The 4 transform corners define a projective mapping from the album's source rectangle to a destination quadrilateral. This is computed by solving for a 3×3 projective matrix:

```
[a b c]   [x]   [x']
[d e f] × [y] = [y']
[g h 1]   [1]   [w']
```

Where `screen_x = x'/w'`, `screen_y = y'/w'`. The matrix is embedded into a 4×4 `Matrix4` for Flutter's canvas transform.

## Capacity Variants

For crates, the album's position changes based on how full the crate is:

- **Full:** Album is pushed to the front, appearing larger and less recessed
- **Half:** Album sits in the middle, moderately recessed
- **Empty:** Album is at the back, appears smaller with more perspective distortion, crate walls occlude more

Each capacity gets its own `slot_data` row. The admin should be able to:
1. Create the `full` slot first
2. Duplicate it to `half` and `empty`
3. Adjust corners inward/smaller for more recessed positions

## Sample Album for Preview

Use any square image as the sample album cover for preview purposes. A 600×600 album cover with recognizable features (text, distinct corners) makes it easier to verify perspective correctness.

## Storage Paths

Product frame images are stored in Supabase Storage at:
```
product-images/{shopify_product_handle}/{sku}/{angle}.png
```

The editor only needs to display these images, not manage them. Frame image upload is handled separately.
