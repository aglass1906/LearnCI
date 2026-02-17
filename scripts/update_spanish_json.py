import json
import os

def update_spanish_json():
    filepath = '/Users/alanglass/_dev_local/Learn Comp Input/LearnCI/LearnCI/Resources/Data/spanish_card_deck/spanish_intermediate.json'
    images_dir = '/Users/alanglass/_dev_local/Learn Comp Input/LearnCI/LearnCI/Resources/Images'
    
    with open(filepath, 'r') as f:
        data = json.load(f)
    
    updated_count = 0
    for card in data['cards']:
        current_media = card.get('mediaFile', '')
        if current_media and current_media.endswith('.jpg'):
            png_name = current_media.replace('.jpg', '.png')
            png_path = os.path.join(images_dir, png_name)
            
            if os.path.exists(png_path):
                card['mediaFile'] = png_name
                updated_count += 1
                print(f"Updated {card['wordTarget']} -> {png_name}")
    
    if updated_count > 0:
        with open(filepath, 'w') as f:
            json.dump(data, f, indent=4, ensure_ascii=False)
        print(f"Total cards updated: {updated_count}")
    else:
        print("No updates needed.")

if __name__ == "__main__":
    update_spanish_json()
