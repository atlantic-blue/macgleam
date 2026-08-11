---
name: Lumina Utility
colors:
  surface: '#091423'
  surface-dim: '#091423'
  surface-bright: '#303a4b'
  surface-container-lowest: '#050e1e'
  surface-container-low: '#121c2c'
  surface-container: '#162030'
  surface-container-high: '#202a3b'
  surface-container-highest: '#2b3546'
  on-surface: '#d9e3f9'
  on-surface-variant: '#bcc9ca'
  inverse-surface: '#d9e3f9'
  inverse-on-surface: '#273141'
  outline: '#869394'
  outline-variant: '#3d494a'
  surface-tint: '#65d7df'
  primary: '#a9f9ff'
  on-primary: '#00373a'
  primary-container: '#6fe0e8'
  on-primary-container: '#006268'
  inverse-primary: '#00696f'
  secondary: '#c0c5e0'
  on-secondary: '#2a3045'
  secondary-container: '#454b61'
  on-secondary-container: '#b5bbd5'
  tertiary: '#e8eafc'
  on-tertiary: '#2c303d'
  tertiary-container: '#cbcee0'
  on-tertiary-container: '#545866'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#84f4fc'
  primary-fixed-dim: '#65d7df'
  on-primary-fixed: '#002022'
  on-primary-fixed-variant: '#004f53'
  secondary-fixed: '#dce1fd'
  secondary-fixed-dim: '#c0c5e0'
  on-secondary-fixed: '#151b2f'
  on-secondary-fixed-variant: '#40465c'
  tertiary-fixed: '#dfe2f3'
  tertiary-fixed-dim: '#c3c6d7'
  on-tertiary-fixed: '#171b28'
  on-tertiary-fixed-variant: '#434654'
  background: '#091423'
  on-background: '#d9e3f9'
  surface-variant: '#2b3546'
typography:
  display-hub:
    fontFamily: Inter
    fontSize: 56px
    fontWeight: '700'
    lineHeight: 64px
    letterSpacing: -0.02em
  title-main:
    fontFamily: Inter
    fontSize: 22px
    fontWeight: '600'
    lineHeight: 28px
    letterSpacing: -0.01em
  body-standard:
    fontFamily: Inter
    fontSize: 13px
    fontWeight: '400'
    lineHeight: 18px
  caption-tiny:
    fontFamily: Inter
    fontSize: 11px
    fontWeight: '500'
    lineHeight: 14px
  code-path:
    fontFamily: JetBrains Mono
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  unit: 8px
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
  container-margin: 24px
  gutter: 16px
---

## Brand & Style

The design system is engineered for a high-performance macOS utility environment. The brand personality is authoritative yet ethereal, blending the precision of a system tool with the immersive quality of a high-end creative suite. 

The aesthetic is **Modern-Tactile**, heavily influenced by the macOS Sequoia and Sonoma design language. It utilizes deep canvas layers, high-density information layouts, and luminous accents to guide the user's eye. The core visual hook is a central hexagonal focal point—a "Command Orb"—that serves as the primary interaction hub, radiating status and progress via dynamic gradients.

**Key visual principles:**
- **Materiality:** Every surface feels like physical glass or anodized metal.
- **Precision:** Fine-line borders and 1px "inner glows" to define edges against dark backgrounds.
- **Atmospheric:** Use of deep blue background washes to prevent "crushed blacks" and maintain legibility.

## Colors

The palette is optimized for a pro-tier dark mode experience. 

- **Canvas:** The primary background (`#0A0E1A`) provides a deep, non-distracting foundation.
- **Surfaces:** Elevated containers (`#141A2E`) use a slightly higher luminosity to create clear containment for data and controls.
- **Accents:** The Cyan primary (`#6FE0E8`) is used sparingly for active states, focus rings, and primary progress indicators to ensure high contrast and a "tech-forward" feel.
- **Semantic:** Standardized colors for health checks: Green (Safe), Amber (Review), and Red (Dangerous). These should always be accompanied by icons or text to ensure accessibility.

## Typography

Since SF Pro is a system restricted font, **Inter** is utilized as the primary typeface for its near-identical metrics and high legibility on high-DPI displays. **JetBrains Mono** is assigned to technical strings (file paths, terminal outputs) to differentiate data from UI labels.

- **Display Hub:** Used exclusively for large numeric readouts or hero states within the central orb.
- **Title Main:** Used for view headers and primary card titles.
- **Body Standard:** The workhorse for all descriptions and list items. 
- **Caption Tiny:** Used for metadata, labels, and secondary supporting text.
- **Code Path:** Used for any system-level file referencing to ensure character distinction (e.g., distinguishing '0' from 'O').

## Layout & Spacing

This design system follows a strict **8px grid** to align with macOS standard spacing rhythms. 

**The Hexagonal Hub:**
The application layout centers around a geometric hub. The layout is not a traditional top-down list but a radial-inspired composition:
1. **Central Orb:** Located in the upper middle, containing the "Display Hub" figure.
2. **Hexagonal Satellites:** Six primary categories or action cards arranged in a hexagonal pattern around the orb.
3. **Sidebar:** A standard 200px-240px translucent sidebar for high-level navigation.

Margins are generous (24px) to create the "minimalist" breathing room characteristic of native utilities.

## Elevation & Depth

Visual hierarchy is established through **Tonal Layering** and **Luminous Outlines** rather than heavy shadows.

- **Level 0 (Base):** The `#0A0E1A` canvas.
- **Level 1 (Card):** `#141A2E` surface with a 1px solid border of `rgba(255, 255, 255, 0.05)`.
- **Level 2 (Interactive):** Elements like buttons or active tabs utilize a subtle inner glow (top-down white gradient at 10% opacity) to simulate a physical edge.
- **The Orb Glow:** The central hub uses a heavy background blur (30px) and a radial gradient of the Primary Accent color (`#6FE0E8`) at 20% opacity to create a sense of energy.
- **Shadows:** Only used on floating menus or popovers. Use sharp, small-radius shadows: `0 4px 12px rgba(0,0,0,0.5)`.

## Shapes

The design system employs a tiered corner radius system to create a "nested" aesthetic.

- **Cards/Containers:** Use **12px** radius. This provides a friendly, modern look that matches the standard macOS window corners.
- **Controls/Buttons/Inputs:** Use **6px** radius. The sharper corners for controls convey precision and "tool-like" utility.
- **The Hub:** The central element should be a perfect circle or a soft-hexagon (60-degree rounded corners) to differentiate it from the standard rectangular UI.

## Components

### Buttons
- **Primary:** Filled with `#6FE0E8`, text in `#0A0E1A`. 6px radius.
- **Secondary:** Transparent with 1px border of `#A8B2C7` at 30% opacity.
- **Hover States:** Increase brightness by 10%; avoid changing the hue.

### Cards
- **Construction:** Background `#141A2E`, 12px radius, 1px border of `rgba(255, 255, 255, 0.06)`.
- **Interaction:** On hover, the border color shifts to the Primary Accent (`#6FE0E8`) at 40% opacity.

### Progress Indicators (Hexagonal)
- Progress is visualized as a stroke running around the perimeter of the hexagonal cards. 
- The stroke width is 2px, using the Primary Accent.

### Input Fields
- Subtle dark wells (`rgba(0,0,0,0.2)`) with 6px radius. 
- Focus state: 2px outer glow of `#6FE0E8` at 50% opacity.

### Lists
- Use horizontal separators only if the list is dense. Otherwise, use 8px of vertical spacing between items.
- File paths in lists should use the `code-path` typography and be truncated in the middle (e.g., `/Users/.../config.json`).