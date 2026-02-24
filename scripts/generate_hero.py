import os
from PIL import Image, ImageDraw, ImageFont

# Dimensions for hero image (e.g., 1200x800)
width = 1200
height = 800

# Create a new image with a nice gradient
img = Image.new('RGB', (width, height))
draw = ImageDraw.Draw(img)

# Draw a vertical gradient from modern blue to orange/yellowish
for y in range(height):
    r = int(24 + (255 - 24) * (y / height) * 0.8)
    g = int(144 + (165 - 144) * (y / height))
    b = int(255 - (255 - 0) * (y / height) * 0.5)
    
    # Just a nice smooth modern gradient (Teal/Blue to Soft Orange)
    r = int(y / height * 255)
    g = int(y / height * 150 + 50)
    b = int(150 + (1 - y/height)*105)
    draw.line([(0, y), (width, y)], fill=(r, g, b))

# Try to draw some abstract "comprehensible input" shapes
# A book shape
draw.rectangle([width/2 - 150, height/2 + 50, width/2 + 150, height/2 + 150], fill=(255, 255, 255, 100), outline=(255, 255, 255), width=5)
draw.line([(width/2, height/2 + 50), (width/2, height/2 + 150)], fill=(255, 255, 255), width=5)

# A lightbulb abstract circle
draw.ellipse([width/2 - 50, height/2 - 150, width/2 + 50, height/2 - 50], fill=(255, 220, 100))

# Make sure the target directory exists
target_dir = "/Users/alanglass/_dev_local/Learn Comp Input/LearnCI/LearnCI/Assets.xcassets/ci_hero.imageset"
os.makedirs(target_dir, exist_ok=True)

# Save the image
img.save(f"{target_dir}/ci_hero.png")

# Write the Contents.json
import json
contents = {
  "images" : [
    {
      "filename" : "ci_hero.png",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
with open(f"{target_dir}/Contents.json", "w") as f:
    json.dump(contents, f, indent=2)

print(f"Created hero image successfully in {target_dir}")
