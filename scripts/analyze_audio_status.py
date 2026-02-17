import os
import json

def analyze_audio_status():
    project_root = '/Users/alanglass/_dev_local/Learn Comp Input/LearnCI'
    data_dir = os.path.join(project_root, 'LearnCI/Resources/Data')
    audio_dir = os.path.join(project_root, 'LearnCI/Resources/Audio')
    
    # Get set of existing audio files
    existing_audio = set(os.listdir(audio_dir))
    
    missing_word_audio = []
    missing_sentence_audio = []
    total_referenced = 0
    
    # Walk through data directory
    for root, dirs, files in os.walk(data_dir):
        for file in files:
            if file.endswith('.json'):
                file_path = os.path.join(root, file)
                try:
                    with open(file_path, 'r') as f:
                        data = json.load(f)
                        
                    # Check if it's a card deck (has 'cards' array)
                    if 'cards' in data:
                        cards = data['cards']
                        print(f"Analyzing {file}: {len(cards)} cards")
                        
                        for card in cards:
                            # Check word audio
                            if 'audioWordFile' in card:
                                total_referenced += 1
                                if card['audioWordFile'] not in existing_audio:
                                    missing_word_audio.append(f"{file} -> {card['audioWordFile']}")
                            
                            # Check sentence audio
                            if 'audioSentenceFile' in card:
                                total_referenced += 1
                                if card['audioSentenceFile'] not in existing_audio:
                                    missing_sentence_audio.append(f"{file} -> {card['audioSentenceFile']}")
                                    
                except Exception as e:
                    print(f"Error reading {file}: {e}")

    print("-" * 30)
    print(f"Total Audio References Checked: {total_referenced}")
    print(f"Existing Audio Files: {len(existing_audio)}")
    print(f"Missing Word Audio Files: {len(missing_word_audio)}")
    print(f"Missing Sentence Audio Files: {len(missing_sentence_audio)}")
    print(f"Total Missing: {len(missing_word_audio) + len(missing_sentence_audio)}")
    print("-" * 30)
    
    if len(missing_word_audio) > 0:
        print("\nSample Missing Word Audio:")
        for item in missing_word_audio[:5]:
            print(f"  - {item}")
            
    if len(missing_sentence_audio) > 0:
        print("\nSample Missing Sentence Audio:")
        for item in missing_sentence_audio[:5]:
            print(f"  - {item}")

if __name__ == "__main__":
    analyze_audio_status()
