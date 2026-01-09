import os
import shutil
import json

# Define paths
PROJECT_ROOT = "/Users/alanglass/Documents/dev/_AI/LearnCI/LearnCI"
RESOURCES_DIR = os.path.join(PROJECT_ROOT, "Resources")
ASSETS_DIR = os.path.join(PROJECT_ROOT, "Assets.xcassets")

# Ensure Assets directory exists
if not os.path.exists(ASSETS_DIR):
    print(f"Error: Assets directory not found at {ASSETS_DIR}")
    exit(1)

def create_imageset(name, source_path):
    imageset_dir = os.path.join(ASSETS_DIR, f"{name}.imageset")
    
    # create dir
    if not os.path.exists(imageset_dir):
        os.makedirs(imageset_dir)
        
    # Copy file
    dest_filename = os.path.basename(source_path)
    shutil.copy(source_path, os.path.join(imageset_dir, dest_filename))
    
    # Create Contents.json
    contents = {
      "images" : [
        {
          "filename" : dest_filename,
          "idiom" : "universal",
          "scale" : "1x"
        },
        {
          "idiom" : "universal",
          "scale" : "2x"
        },
        {
          "idiom" : "universal",
          "scale" : "3x"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    
    with open(os.path.join(imageset_dir, "Contents.json"), 'w') as f:
        json.dump(contents, f, indent=2)
    print(f"Migrated {name} to Assets.xcassets")

# Check specifically for the PNGs we missed
for root, dirs, files in os.walk(RESOURCES_DIR):
    for file in files:
        if file.endswith(".png"):
            name = os.path.splitext(file)[0]
            # Avoid duplicating if already exists (optional, but overwriting is safer for updates)
            create_imageset(name, os.path.join(root, file))

print("Migration Complete.")
