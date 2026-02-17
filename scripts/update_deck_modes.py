import os
import json

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(PROJECT_ROOT, 'LearnCI/Resources/Data')

REQUIRED_MODES = [
    "flashcards",
    "memoryMatch",
    "multipleChoice",
    "audioCloze",
    "linker"
]

def update_decks():
    print(f"Scanning {DATA_DIR} for decks...")
    
    updated_count = 0
    
    for root, dirs, files in os.walk(DATA_DIR):
        for file in files:
            if file.endswith('.json'):
                file_path = os.path.join(root, file)
                try:
                    with open(file_path, 'r') as f:
                        data = json.load(f)
                    
                    # Check if it's a valid deck
                    if 'cards' not in data:
                        continue
                        
                    current_modes = data.get('supportedModes', [])
                    missing_modes = [mode for mode in REQUIRED_MODES if mode not in current_modes]
                    
                    if missing_modes:
                        print(f"Updating {file}. Missing: {missing_modes}")
                        
                        # Add missing modes
                        if 'supportedModes' not in data:
                            data['supportedModes'] = []
                        
                        for mode in missing_modes:
                            data['supportedModes'].append(mode)
                            
                        # Save file
                        with open(file_path, 'w') as f:
                            json.dump(data, f, indent=4, ensure_ascii=False)
                            
                        updated_count += 1
                    else:
                        print(f"Skipping {file} (Already up to date)")
                        
                except Exception as e:
                    print(f"Error processing {file}: {e}")
                    
    print("-" * 30)
    print(f"Update Complete. Updated {updated_count} files.")
    print("-" * 30)

if __name__ == "__main__":
    update_decks()
