#!/usr/bin/env python3
"""
Generate app icon variations with baseballs at the ends of lines.
Creates multiple versions with different baseball placements.
"""

from PIL import Image, ImageDraw
import math
import os

def create_baseball(draw, x, y, radius, rotation=0):
    """Draw a small baseball at position (x, y) with given radius."""
    # Main circle (white fill with red stitching)
    draw.ellipse([x - radius, y - radius, x + radius, y + radius], fill=(255, 255, 255), outline=(180, 30, 30), width=1)
    
    # Baseball stitching (two curved lines)
    stitch_color = (200, 50, 50)
    
    # Left curve
    for angle in range(-60, 61, 15):
        rad = math.radians(angle + rotation)
        sx = x + (radius * 0.6) * math.cos(rad)
        sy = y + (radius * 0.8) * math.sin(rad)
        draw.ellipse([sx-1, sy-1, sx+1, sy+1], fill=stitch_color)
    
    # Right curve  
    for angle in range(-60, 61, 15):
        rad = math.radians(angle + rotation + 180)
        sx = x + (radius * 0.6) * math.cos(rad)
        sy = y + (radius * 0.8) * math.sin(rad)
        draw.ellipse([sx-1, sy-1, sx+1, sy+1], fill=stitch_color)

def create_icon_version_1(output_path):
    """Version 1: Simple lines with baseballs at ends - horizontal layout."""
    size = 1024
    img = Image.new('RGB', (size, size), color=(25, 35, 55))  # Dark blue background
    draw = ImageDraw.Draw(img)
    
    # Draw 3 horizontal lines with baseballs at ends
    line_y_positions = [300, 512, 724]
    line_x_start = 200
    line_x_end = 824
    
    for y in line_y_positions:
        # Draw line
        draw.line([(line_x_start, y), (line_x_end, y)], fill=(220, 220, 230), width=12)
        # Baseball at left end
        create_baseball(draw, line_x_start, y, 24)
        # Baseball at right end
        create_baseball(draw, line_x_end, y, 24)
    
    img.save(output_path, 'PNG')
    print(f"Created: {output_path}")

def create_icon_version_2(output_path):
    """Version 2: Cross/plus shape with baseballs at ends."""
    size = 1024
    img = Image.new('RGB', (size, size), color=(25, 35, 55))
    draw = ImageDraw.Draw(img)
    
    center = size // 2
    arm_length = 300
    
    # Horizontal line with baseballs
    draw.line([(center - arm_length, center), (center + arm_length, center)], 
              fill=(220, 220, 230), width=12)
    create_baseball(draw, center - arm_length, center, 28)
    create_baseball(draw, center + arm_length, center, 28)
    
    # Vertical line with baseballs
    draw.line([(center, center - arm_length), (center, center + arm_length)], 
              fill=(220, 220, 230), width=12)
    create_baseball(draw, center, center - arm_length, 28)
    create_baseball(draw, center, center + arm_length, 28)
    
    img.save(output_path, 'PNG')
    print(f"Created: {output_path}")

def create_icon_version_3(output_path):
    """Version 3: Diamond/baseball field shape with baseballs at corners."""
    size = 1024
    img = Image.new('RGB', (size, size), color=(25, 35, 55))
    draw = ImageDraw.Draw(img)
    
    center = size // 2
    diamond_size = 280
    
    # Diamond points (top, right, bottom, left)
    points = [
        (center, center - diamond_size),      # top
        (center + diamond_size, center),       # right
        (center, center + diamond_size),       # bottom
        (center - diamond_size, center),       # left
    ]
    
    # Draw diamond lines
    for i in range(4):
        start = points[i]
        end = points[(i + 1) % 4]
        draw.line([start, end], fill=(220, 220, 230), width=12)
    
    # Draw baseballs at each corner
    for point in points:
        create_baseball(draw, point[0], point[1], 30)
    
    img.save(output_path, 'PNG')
    print(f"Created: {output_path}")

def create_icon_version_4(output_path):
    """Version 4: Circular arrangement with baseballs."""
    size = 1024
    img = Image.new('RGB', (size, size), color=(25, 35, 55))
    draw = ImageDraw.Draw(img)
    
    center = size // 2
    radius = 250
    
    # Draw circle
    draw.ellipse([center - radius, center - radius, center + radius, center + radius], 
                 outline=(220, 220, 230), width=12)
    
    # Draw baseballs at 4 points on circle
    angles = [0, 90, 180, 270]
    for angle in angles:
        rad = math.radians(angle)
        x = center + radius * math.cos(rad)
        y = center + radius * math.sin(rad)
        create_baseball(draw, int(x), int(y), 28)
    
    img.save(output_path, 'PNG')
    print(f"Created: {output_path}")

def create_icon_version_5(output_path):
    """Version 5: Chevron/arrows with baseballs."""
    size = 1024
    img = Image.new('RGB', (size, size), color=(25, 35, 55))
    draw = ImageDraw.Draw(img)
    
    center_y = size // 2
    
    # Three chevron lines
    for i, offset in enumerate([-150, 0, 150]):
        y = center_y + offset
        
        # Left point
        left_x = 250
        mid_x = 512
        right_x = 774
        
        # Draw > shape
        draw.line([(mid_x, y - 60), (right_x, y)], fill=(220, 220, 230), width=10)
        draw.line([(right_x, y), (mid_x, y + 60)], fill=(220, 220, 230), width=10)
        
        # Baseball at the arrow point
        create_baseball(draw, right_x, y, 26)
    
    img.save(output_path, 'PNG')
    print(f"Created: {output_path}")

def main():
    output_dir = "/Users/jackwallner/baseball/icon_variations"
    os.makedirs(output_dir, exist_ok=True)
    
    print("Generating icon variations with baseballs at line ends...")
    print()
    
    create_icon_version_1(os.path.join(output_dir, "icon_v1_horizontal_lines.png"))
    create_icon_version_2(os.path.join(output_dir, "icon_v2_cross.png"))
    create_icon_version_3(os.path.join(output_dir, "icon_v3_diamond.png"))
    create_icon_version_4(os.path.join(output_dir, "icon_v4_circle.png"))
    create_icon_version_5(os.path.join(output_dir, "icon_v5_chevrons.png"))
    
    print()
    print(f"All icons saved to: {output_dir}")
    print("\nVersions created:")
    print("  v1: Three horizontal lines with baseballs at ends")
    print("  v2: Cross/plus shape with baseballs at 4 ends")
    print("  v3: Diamond/baseball field shape with baseballs at corners")
    print("  v4: Circle with baseballs at 4 cardinal points")
    print("  v5: Chevron arrows with baseballs at arrow tips")

if __name__ == "__main__":
    main()
