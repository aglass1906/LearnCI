import json
import os
import argparse
import time
import requests
from openai import OpenAI
from dotenv import load_dotenv

# Load environment variables
load_dotenv()
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")

if not OPENAI_API_KEY:
    print("Error: OPENAI_API_KEY not found.")
    # In a real scenario, we might want to exit, but for now allow dry-run
    # exit(1) 

client = OpenAI(api_key=OPENAI_API_KEY) if OPENAI_API_KEY else None

def generate_image(client, prompt, output_path, dry_run=False):
    if dry_run:
        print(f"[Dry Run] Prompt: {prompt}")
        print(f"[Dry Run] Would save to: {output_path}")
        return True

    if not client:
        print("Error: OpenAI client not initialized (missing API key).")
        return False

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

def get_prompt_for_card(card):
    word_target = card.get('wordTarget', '')
    word_native = card.get('wordNative', '')
    sentence_native = card.get('sentenceNative', '')
    tags = card.get('tags', [])
    
    # Functional Language Logic
    if "Contrast Connectors" in tags:
        return f"A split composition image showing a clear contrast. Left side: A scene representing the first part of the concept. Right side: A scene representing the opposing idea or contrast. Highlighting the concept of '{word_target}' ({word_native}). Clear, different lighting on each side."
    elif "Cause & Effect" in tags:
        return f"A visual sequence or cause-and-effect scene. Panel 1: An event or action. Panel 2: The direct result or consequence. Highlighting the concept of '{word_target}' ({word_native})."
    elif "Strategic Verbs" in tags:
        return f"A dynamic scene showing a character facing a challenge or problem but persisting with the action of '{word_target}' ({word_native}). Cinematic lighting, tension, focus on the effort or strategy. Context: '{sentence_native}'."
    elif "Time Connectors" in tags:
        return f"A visual representation of time or sequence. Showing the relationship between two events described by '{word_target}' ({word_native}). Context: '{sentence_native}'."
        
    # Standard Logic
    return f"Photorealistic culturally relevant image of '{word_target}' in a real world context. The image should visually represent the concept: '{sentence_native}'. Clear lighting, no text on image."

def main():
    parser = argparse.ArgumentParser(description="Generate images for LearnCI decks.")
    parser.add_argument("--deck", required=True, help="Path to the deck JSON file.")
    parser.add_argument("--force", action="store_true", help="Overwrite existing images.")
    parser.add_argument("--dry-run", action="store_true", help="Print prompts without generating.")
    args = parser.parse_args()

    json_path = args.deck
    if not os.path.exists(json_path):
        print(f"Error: Deck file not found at {json_path}")
        exit(1)
        
    # Determine absolute path directory
    deck_dir = os.path.dirname(os.path.abspath(json_path))
    
    # Heuristic for Images folder: 
    # If in Resources/Data/spanish_card_deck, images should be in Resources/Images/spanish_card_deck
    
    images_dir = deck_dir.replace("Resources/Data", "Resources/Images").replace("Data", "Images")
    
    # If replacement didn't work (same path), assume sibling 'images' or just create 'images'
    if images_dir == deck_dir:
        images_dir = os.path.join(deck_dir, "images")

    if not os.path.exists(images_dir):
        print(f"Creating images directory: {images_dir}")
        os.makedirs(images_dir, exist_ok=True)

    with open(json_path, 'r') as f:
        data = json.load(f)

    cards = data.get('cards', [])
    total = len(cards)
    print(f"Found {total} cards in {os.path.basename(json_path)}")
    print(f"Images will be saved to: {images_dir}")
    
    updated_count = 0
    deck_id_prefix = data.get('id', 'card').split('_')[0]
    
    for i, card in enumerate(cards):
        word_target = card.get('wordTarget', 'unknown')
        
        # Determine filename
        current_media = card.get('mediaFile', '')
        
        if current_media:
            base_name = os.path.splitext(current_media)[0]
            filename = f"{base_name}.png"
        else:
            # Fallback filename generation
            card_id = card.get('id', 'unknown')
            safe_word = word_target.lower().replace(' ', '_').replace('/', '_')
            filename = f"{deck_id_prefix}_{safe_word}.png"
            
        output_path = os.path.join(images_dir, filename)
        
        # Check if file exists
        exists = os.path.exists(output_path)
        
        if exists and not args.force:
            # print(f"[{i+1}/{total}] Skipping {word_target} (Image exists)")
            continue
            
        print(f"[{i+1}/{total}] Processing {word_target}...")
        
        prompt = get_prompt_for_card(card)
        
        success = generate_image(client, prompt, output_path, dry_run=args.dry_run)
        
        if success:
            updated_count += 1
            if not args.dry_run:
                # Update JSON reference
                if current_media != filename:
                    card['mediaFile'] = filename
                    # Save incremental progress
                    with open(json_path, 'w') as f:
                        json.dump(data, f, indent=4, ensure_ascii=False)
                
                print("Sleeping for 20 seconds...")
                time.sleep(20)
            else:
                 pass # Dry run, no sleep
                 
    print(f"Done. Processed {updated_count} images.")

if __name__ == "__main__":
    main()
