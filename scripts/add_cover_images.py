import json
import os

data_dir = "/Users/alanglass/_dev_local/Learn Comp Input/LearnCI/LearnCI/Resources/Data/spanish_card_deck/"

for filename in os.listdir(data_dir):
    if filename.endswith(".json"):
        filepath = os.path.join(data_dir, filename)
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                data = json.load(f)
            
            if "coverImage" not in data:
                deck_id = data.get("id", filename.replace(".json", ""))
                data["coverImage"] = f"{deck_id}_cover.png"
                
                with open(filepath, 'w', encoding='utf-8') as f:
                    json.dump(data, f, indent=4, ensure_ascii=False)
                print(f"Updated {filename} with coverImage: {data['coverImage']}")
            else:
                print(f"Skipping {filename}, coverImage already exists.")
        except Exception as e:
            print(f"Error processing {filename}: {e}")
