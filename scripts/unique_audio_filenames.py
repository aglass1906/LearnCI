
import os
import json
import re

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(PROJECT_ROOT, 'LearnCI/Resources/Data')

def clean_filename(s):
    """Sanitize string for filename use."""
    # Remove accents/special chars by replacing non-alphanumeric with underscore
    s = s.lower()
    s = re.sub(r'[^a-z0-9]', '_', s)
    # Remove redundant underscores
    s = re.sub(r'_+', '_', s)
    return s.strip('_')

def process_decks():
    print(f"Scanning {DATA_DIR} for decks...")
    
    updated_files = 0
    total_cards = 0

    for root, dirs, files in os.walk(DATA_DIR):
        for file in files:
            if file.endswith('.json') and file not in ['tag_taxonomy.json', 'language_taxonomy.json', 'domain_taxonomy.json', 'layouts.json', 'quotes.json', 'curated_resources.json', 'tag_semantics.json', 'tag_taxonomy2.json']:
                file_path = os.path.join(root, file)
                try:
                    with open(file_path, 'r', encoding='utf-8') as f:
                        data = json.load(f)
                    
                    if 'cards' not in data:
                        continue
                        
                    lang = data.get('language', 'xx')
                    deck_modified = False
                    
                    print(f"Processing {file} ({lang})...")
                    
                    for card in data['cards']:
                        card_id = card.get('id', 'no_id')
                        word = clean_filename(card.get('wordTarget', 'unknown'))
                        
                        # Apply new naming convention
                        if 'audioWordFile' in card:
                            old_name = card['audioWordFile']
                            new_name = f"{lang}_{word}_{card_id}_word.mp3"
                            if old_name != new_name:
                                card['audioWordFile'] = new_name
                                deck_modified = True
                        
                        if 'audioSentenceFile' in card:
                            old_name = card['audioSentenceFile']
                            new_name = f"{lang}_{word}_{card_id}_sentence.mp3"
                            if old_name != new_name:
                                card['audioSentenceFile'] = new_name
                                deck_modified = True
                                
                        total_cards += 1

                    if deck_modified:
                        with open(file_path, 'w', encoding='utf-8') as f:
                            json.dump(data, f, indent=4, ensure_ascii=False)
                        updated_files += 1
                        print(f"  - Updated {file}")
                        
                except Exception as e:
                    print(f"Error processing {file}: {e}")

    print("-" * 30)
    print(f"Done. Updated {updated_files} files.")
    print(f"Processed {total_cards} cards.")
    print("-" * 30)

if __name__ == "__main__":
    process_decks()
