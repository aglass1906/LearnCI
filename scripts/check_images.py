import os
import json
import sys

def check_images():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    data_dir = os.path.join(base_dir, "LearnCI", "Resources", "Data")
    images_dir = os.path.join(base_dir, "LearnCI", "Resources", "Images")

    print(f"Checking decks in {data_dir}")
    print(f"Images directory: {images_dir}")

    summary = {}

    for root, dirs, files in os.walk(data_dir):
        for file in files:
            if file.endswith(".json") and "deck" in root: # heuristic to find deck files or check if content has 'cards'
                filepath = os.path.join(root, file)
                try:
                    with open(filepath, 'r') as f:
                        data = json.load(f)
                        
                    if "cards" not in data:
                        continue
                        
                    deck_name = data.get("title", file)
                    cards = data.get("cards", [])
                    total_cards = len(cards)
                    missing_images = []
                    
                    for card in cards:
                        media_file = card.get("mediaFile")
                        if not media_file:
                            missing_images.append(f"{card.get('id')} (No mediaFile specified)")
                            continue
                            
                        image_path = os.path.join(images_dir, media_file)
                        if not os.path.exists(image_path):
                            missing_images.append(f"{card.get('id')} (File missing: {media_file})")
                            
                    summary[deck_name] = {
                        "total": total_cards,
                        "missing": missing_images,
                        "file": file
                    }
                    
                except Exception as e:
                    print(f"Error processing {file}: {e}")

    print("\n" + "="*80)
    print(f"{'DECK NAME':<40} | {'TOTAL':<10} | {'MISSING':<10}")
    print("="*80)
    
    for deck, info in summary.items():
        missing_count = len(info["missing"])
        print(f"{deck:<40} | {info['total']:<10} | {missing_count:<10}")
        if missing_count > 0:
            # print(f"  Missing: {', '.join(info['missing'][:5])}..." if missing_count > 5 else f"  Missing: {', '.join(info['missing'])}")
            pass

    print("\n" + "="*80)
    print("DETAILED MISSING BY DECK")
    print("="*80)
    for deck, info in summary.items():
        if info["missing"]:
            print(f"\nDeck: {deck} ({info['file']})")
            for missing in info["missing"]:
                print(f"  - {missing}")

if __name__ == "__main__":
    check_images()
