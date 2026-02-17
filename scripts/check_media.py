import os
import json
import sys

def check_media():
    # Determine base directory (repo root)
    # Assumes this script is in <repo>/scripts/
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    
    data_dir = os.path.join(repo_root, "LearnCI", "Resources", "Data")
    images_dir = os.path.join(repo_root, "LearnCI", "Resources", "Images")
    audio_dir = os.path.join(repo_root, "LearnCI", "Resources", "Audio")
    
    print(f"Repo Root: {repo_root}")
    print(f"Data Dir: {data_dir}")
    print(f"Images Dir: {images_dir}")
    print(f"Audio Dir: {audio_dir}")
    
    # Get all existing audio files (recurse if needed, but structure seems flat or language-prefixed?)
    # analyze_audio_status.py used os.listdir(audio_dir), implying flat.
    # Let's verify if audio_dir has subdirs.
    existing_audio = set()
    for root, _, files in os.walk(audio_dir):
        for f in files:
            existing_audio.add(f)
            
    # Get all existing image files
    existing_images = set()
    for root, _, files in os.walk(images_dir):
        for f in files:
            existing_images.add(f)

    summary_rows = []

    for root, dirs, files in os.walk(data_dir):
        for file in files:
            if file.endswith(".json"):
                # Check if it looks like a deck (has 'cards' or 'id'/'title')
                filepath = os.path.join(root, file)
                try:
                    with open(filepath, 'r') as f:
                        data = json.load(f)
                        
                    if "cards" not in data:
                        continue
                        
                    deck_name = data.get("title", file)
                    cards = data.get("cards", [])
                    total_cards = len(cards)
                    
                    if total_cards == 0:
                        continue

                    # Metrics
                    missing_img_count = 0
                    missing_audio_count = 0
                    total_audio_refs = 0
                    
                    # Specific lists for debug if needed
                    # missing_img_files = []
                    # missing_audio_files = []

                    for card in cards:
                        # --- Image Check ---
                        media_file = card.get("mediaFile")
                        if not media_file:
                            missing_img_count += 1
                        else:
                            if media_file not in existing_images:
                                missing_img_count += 1
                                # missing_img_files.append(media_file)

                        # --- Audio Check ---
                        # Check word audio
                        audio_word = card.get("audioWordFile")
                        if audio_word:
                            total_audio_refs += 1
                            if audio_word not in existing_audio:
                                missing_audio_count += 1
                        
                        # Check sentence audio
                        audio_sentence = card.get("audioSentenceFile")
                        if audio_sentence:
                            total_audio_refs += 1
                            if audio_sentence not in existing_audio:
                                missing_audio_count += 1

                    # Determine statuses
                    # Images
                    present_imgs = total_cards - missing_img_count
                    if missing_img_count == total_cards:
                        img_label = "🔴 None"
                    elif missing_img_count > 0:
                        img_label = "🟡 Partial"
                    else:
                        img_label = "🟢 Nominal"
                    
                    img_status = f"{img_label} ({present_imgs}/{total_cards})"

                    # Audio
                    present_audio = total_audio_refs - missing_audio_count
                    if total_audio_refs == 0:
                        audio_status = "⚪️ N/A (0/0)"
                    else:
                        if missing_audio_count == 0:
                            audio_label = "🟢 Nominal"
                        elif missing_audio_count == total_audio_refs:
                            audio_label = "🔴 Missing All"
                        else:
                            audio_label = "🟡 Partial"
                        
                        audio_status = f"{audio_label} ({present_audio}/{total_audio_refs})"

                    summary_rows.append({
                        "name": deck_name,
                        "file": file,
                        "cards": total_cards,
                        "img_stat": img_status,
                        "audio_stat": audio_status
                    })
                    
                except Exception as e:
                    print(f"Error reading {file}: {e}")

    # Print Table
    print("\n" + "="*100)
    print(f"{'DECK NAME':<35} | {'FILE':<30} | {'IMG STATUS':<20} | {'AUDIO STATUS':<20}")
    print("="*100)
    
    for row in summary_rows:
        print(f"{row['name']:<35} | {row['file']:<30} | {row['img_stat']:<20} | {row['audio_stat']:<20}")
    print("="*100 + "\n")

if __name__ == "__main__":
    check_media()
