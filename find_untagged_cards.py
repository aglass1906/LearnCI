
import json
import os

ROOT_DIR = "LearnCI/Resources/Data"

def find_untagged():
    untagged_count = 0
    files_with_untagged = {}

    for root, dirs, files in os.walk(ROOT_DIR):
        for file in files:
            if file.endswith(".json"):
                path = os.path.join(root, file)
                try:
                    with open(path, 'r') as f:
                        data = json.load(f)
                        
                    if 'cards' not in data:
                        continue
                        
                    for card in data['cards']:
                        tags = card.get('tags', [])
                        if not tags:
                            untagged_count += 1
                            if file not in files_with_untagged:
                                files_with_untagged[file] = []
                            files_with_untagged[file].append(card.get('wordTarget', 'Unknown'))
                            
                except Exception as e:
                    print(f"Error reading {file}: {e}")

    if untagged_count == 0:
        print("All cards have at least one tag!")
    else:
        print(f"Found {untagged_count} cards without tags.")
        print("\nBreakdown by file:")
        for file, examples in files_with_untagged.items():
            count = len(examples)
            example_str = ", ".join(examples[:5])
            if count > 5:
                example_str += ", ..."
            print(f"- {file}: {count} cards (e.g. {example_str})")

if __name__ == "__main__":
    find_untagged()
