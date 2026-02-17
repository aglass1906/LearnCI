import json
import os
import re

def clean_filename(text):
    # Remove accents and special chars, replace spaces with underscores, lowercase
    text = text.lower()
    replacements = {
        'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
        'à': 'a', 'â': 'a',
        'î': 'i', 'ï': 'i',
        'ô': 'o', 'ö': 'o',
        'ù': 'u', 'û': 'u', 'ü': 'u',
        'ç': 'c',
        "'": "_"
    }
    for k, v in replacements.items():
        text = text.replace(k, v)
    text = re.sub(r'[^a-z0-9_]', '_', text)
    text = re.sub(r'_+', '_', text) # Collapse multiple underscores
    text = text.strip('_')
    return text

def update_french_json():
    filepath = '/Users/alanglass/_dev_local/Learn Comp Input/LearnCI/LearnCI/Resources/Data/french_card_deck/french_super_beginner.json'
    
    with open(filepath, 'r') as f:
        data = json.load(f)
    
    updated_count = 0
    for card in data['cards']:
        if True: # Force update to fix extension
            word = clean_filename(card['wordTarget'])
            native = clean_filename(card['wordNative'])
            filename = f"fr_sb_{word}_{native}.png"
            card['mediaFile'] = filename
            updated_count += 1
            print(f"Updated {card['wordTarget']} -> {filename}")
    
    with open(filepath, 'w') as f:
        json.dump(data, f, indent=4, ensure_ascii=False)
        
    print(f"Total cards updated: {updated_count}")

if __name__ == "__main__":
    update_french_json()
