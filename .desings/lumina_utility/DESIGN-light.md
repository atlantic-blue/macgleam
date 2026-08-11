---
name: Clinical Precision
colors:
  surface: '#faf8ff'
  surface-dim: '#cfd9fb'
  surface-bright: '#faf8ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f2f3ff'
  surface-container: '#e9edff'
  surface-container-high: '#e1e7ff'
  surface-container-highest: '#d9e2ff'
  on-surface: '#101b34'
  on-surface-variant: '#3f484b'
  inverse-surface: '#25304a'
  inverse-on-surface: '#eef0ff'
  outline: '#6f797c'
  outline-variant: '#bec8cc'
  surface-tint: '#00687b'
  primary: '#005767'
  on-primary: '#ffffff'
  primary-container: '#0a7185'
  on-primary-container: '#bbefff'
  inverse-primary: '#82d2e8'
  secondary: '#535f77'
  on-secondary: '#ffffff'
  secondary-container: '#d3e0fd'
  on-secondary-container: '#57637b'
  tertiary: '#76430a'
  on-tertiary: '#ffffff'
  tertiary-container: '#935a22'
  on-tertiary-container: '#ffe2cc'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#adecff'
  primary-fixed-dim: '#82d2e8'
  on-primary-fixed: '#001f26'
  on-primary-fixed-variant: '#004e5d'
  secondary-fixed: '#d7e3ff'
  secondary-fixed-dim: '#bac7e3'
  on-secondary-fixed: '#0f1c31'
  on-secondary-fixed-variant: '#3b475e'
  tertiary-fixed: '#ffdcc1'
  tertiary-fixed-dim: '#ffb779'
  on-tertiary-fixed: '#2e1500'
  on-tertiary-fixed-variant: '#6c3a02'
  background: '#faf8ff'
  on-background: '#101b34'
  surface-variant: '#d9e2ff'
typography:
  display:
    fontFamily: Inter
    fontSize: 48px
    fontWeight: '700'
    lineHeight: 56px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Inter
    fontSize: 32px
    fontWeight: '600'
    lineHeight: 40px
    letterSpacing: -0.01em
  headline-lg-mobile:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
  title-md:
    fontFamily: Inter
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  label-sm:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.05em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
  gutter: 24px
  margin-mobile: 16px
  margin-desktop: 48px
---

## Brand & Style

The design system embodies a "Modern Corporate" aesthetic tailored for high-stakes professional environments like finance or healthcare. The brand personality is authoritative, dependable, and meticulously organized. It utilizes a refined color palette and structured layout to evoke a sense of calm efficiency.

The visual style leans into **Minimalism** with a touch of **Tactile** refinement. It avoids unnecessary decoration, focusing instead on clear information hierarchy, generous whitespace, and subtle depth cues that guide the user through complex workflows. The light mode is designed to feel "deliberate"—using high-contrast typography and specific surface tinting to ensure every element feels intentional and grounded.

## Colors

The palette is anchored by a deep Navy primary text (`#16213A`) and a professional Teal accent (`#0A7185`). The background uses a cool, desaturated blue-grey (`#F5F7FB`) to provide a soft canvas that makes the pure white card surfaces (`#FFFFFF`) pop with clarity.

- **Primary Accent**: Used for active states, primary buttons, and critical focus indicators.
- **Semantic Colors**: "Safe" (Green), "Review" (Amber), and "Dangerous" (Red) are calibrated for high legibility against white and light grey backgrounds, ensuring accessibility compliance while maintaining a professional tone.
- **Neutral Hierarchy**: Use Secondary text (`#4A566E`) for metadata, labels, and helper text to maintain a clear visual contrast from primary content.

## Typography

This design system utilizes **Inter** (as the closest high-quality alternative to SF Pro) to maintain a neutral, systematic, and highly legible typographic character. 

The scale is built on a tight hierarchy. Large headlines use tighter letter spacing and heavier weights to feel impactful. Body text is optimized for long-form reading with a standard 1.5x line height. Label styles use a medium weight and slight tracking increase to ensure clarity at small sizes. All type should render in Primary Text (`#16213A`) for maximum readability, switching to Secondary Text (`#4A566E`) only for tertiary information.

## Layout & Spacing

The layout is governed by a strict **8pt Grid System**. All dimensions, padding, and margins must be increments of 8px (or 4px for tight internal component spacing).

- **Grid Strategy**: Use a 12-column fluid grid for desktop with 24px gutters. On mobile, transition to a 4-column grid with 16px margins.
- **Vertical Rhythm**: Maintain consistent vertical spacing between sections using `lg` (24px) or `xl` (32px) units to prevent visual clutter.
- **Density**: The design favors a "comfortable" density. Components like list items should use `md` (16px) vertical padding to ensure touch targets are sufficient and information is digestible.

## Elevation & Depth

Depth is communicated through **Tonal Layers** and extremely soft **Ambient Shadows**.

1.  **Level 0 (Background)**: `#F5F7FB`. The lowest layer.
2.  **Level 1 (Cards/Surfaces)**: `#FFFFFF`. These elements "float" slightly above the background using a soft shadow: `0px 4px 12px rgba(22, 33, 58, 0.05)`.
3.  **Level 2 (Overlays/Modals)**: White surfaces with a more pronounced shadow: `0px 12px 32px rgba(22, 33, 58, 0.12)`.

Avoid heavy borders; use light, 1px strokes in a slightly darker grey (`#E1E5ED`) if additional separation is required between white-on-white elements.

## Shapes

The shape language differentiates between structural containers and interactive controls to provide a clear mental model for the user.

- **Structural Containers**: Cards, modals, and large panels use a **12px** corner radius. This softens the overall appearance of the professional interface without making it feel "bubbly."
- **Interactive Controls**: Buttons, input fields, and checkboxes use a sharper **6px** corner radius. This "tighter" look signals precision and utility.
- **Data Indicators**: Status chips or badges may use a fully rounded (pill) shape to distinguish them from interactive buttons.

## Components

- **Buttons**: Primary buttons use the Accent color (`#0A7185`) with white text. Secondary buttons use a light grey ghost style or a subtle border. Use 6px rounding.
- **Input Fields**: 1px border using Secondary text at 20% opacity. On focus, the border transitions to Primary Accent (`#0A7185`) with a 2px width or subtle outer glow.
- **Cards**: Pure white background, 12px rounding, and Level 1 shadow. Content within cards should follow the 16px (`md`) internal padding rule.
- **Chips/Badges**: Use semantic colors (Safe/Review/Dangerous) with a 10% opacity background of the same hue to create a "tinted" label that is easy on the eyes but clearly categorized.
- **Lists**: Interactive list items should have a subtle hover state using the Background color (`#F5F7FB`) to indicate row selection. Use 1px separators in `#E1E5ED`.