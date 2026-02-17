import json
import os
import time
import requests
from openai import OpenAI
from dotenv import load_dotenv

# Load environment variables
load_dotenv()
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")

if not OPENAI_API_KEY:
    print("Error: OPENAI_API_KEY not found.")
    exit(1)

client = OpenAI(api_key=OPENAI_API_KEY)

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(PROJECT_ROOT, 'LearnCI/Resources/Data')
IMAGES_DIR = os.path.join(PROJECT_ROOT, 'LearnCI/Resources/Images')
JSON_PATH = os.path.join(DATA_DIR, 'spanish_card_deck/spanish_intermediate.json')

def generate_image(prompt, output_path):
    print(f"Generating: {prompt}")
    try:
        response = client.images.generate(
            model="dall-e-3",
            prompt=prompt,
            size="1024x1024",
            quality="standard",
            n=1,
        )
        
        image_url = response.data[0].url
        img_data = requests.get(image_url).content
        with open(output_path, 'wb') as handler:
            handler.write(img_data)
        print(f"Saved to {output_path}")
        return True
    except Exception as e:
        print(f"Error generating image: {e}")
        return False

def main():
    with open(JSON_PATH, 'r') as f:
        data = json.load(f)

    cards = data.get('cards', [])
    total = len(cards)
    
    print(f"Found {total} cards in Spanish Intermediate deck.")
    
    for i, card in enumerate(cards):
        word_target = card.get('wordTarget')
        sentence_target = card.get('sentenceTarget')
        sentence_native = card.get('sentenceNative')
        
        # Determine filename - check current mediaFile or construct one
        current_media = card.get('mediaFile', '')
        if current_media:
            # Change extension to .png if it is .jpg
            base_name = os.path.splitext(current_media)[0]
            filename = f"{base_name}.png"
        else:
            # Fallback
            filename = f"es_int_{word_target.lower().replace(' ', '_')}.png"
            
        output_path = os.path.join(IMAGES_DIR, filename)
        
        if os.path.exists(output_path):
            print(f"[{i+1}/{total}] Skipping {word_target} (Image exists: {filename})")
            continue
            
        print(f"[{i+1}/{total}] Processing {word_target}...")
        
        # Construct Prompt
        prompt = f"Photorealistic culturally relevant image of '{word_target}' in a real world context. The image should visually represent the concept: '{sentence_native}'. Clear lighting, no text on image."
        
        success = generate_image(prompt, output_path)
        
        if success:
            # Update JSON reference to ensure it points to the .png
            if current_media != filename:
                card['mediaFile'] = filename
                # Save progress incrementally to JSON to avoid data loss
                with open(JSON_PATH, 'w') as f:
                    json.dump(data, f, indent=4, ensure_ascii=False)
            
            print("Sleeping for 20 seconds...")
            time.sleep(20)
        else:
            print("Skipping sleep due to error.")

if __name__ == "__main__":
    main()
