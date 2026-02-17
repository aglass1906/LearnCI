import json
import os

# Paths
RESOURCES_DIR = os.path.join(os.path.dirname(__file__), "../LearnCI/Resources/Data")
TAG_TAXONOMY_PATH = os.path.join(RESOURCES_DIR, "tag_taxonomy.json")

def verify_tag_taxonomy():
    print(f"Verifying {TAG_TAXONOMY_PATH}...")
    if not os.path.exists(TAG_TAXONOMY_PATH):
        print("Error: tag_taxonomy.json not found.")
        return False

    with open(TAG_TAXONOMY_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            print(f"Error decoding JSON: {e}")
            return False

    # Check for "Functional Language" domain
    if "Functional Language" not in data:
        print("Error: 'Functional Language' domain missing in tag_taxonomy.json")
        return False
    
    functional_domain = data["Functional Language"]
    print(f"Found 'Functional Language': {functional_domain.get('description', 'No description')}")
    
    expected_tags = ["Contrast Connectors", "Cause & Effect", "Time Connectors", "Strategic Verbs"]
    found_tags = functional_domain.get("tags", {}).keys()
    
    missing_tags = [tag for tag in expected_tags if tag not in found_tags]
    
    if missing_tags:
        print(f"Error: Missing expected tags: {missing_tags}")
        return False
        
    print("Success: All expected Functional Language tags found.")
    return True

def verify_decks():
    print("\nVerifying decks for Functional Language tags...")
    deck_dir = os.path.join(RESOURCES_DIR, "spanish_card_deck")
    
    functional_tags_count = 0
    
    for filename in os.listdir(deck_dir):
        if filename.endswith(".json"):
            path = os.path.join(deck_dir, filename)
            with open(path, 'r') as f:
                try:
                    deck = json.load(f)
                except:
                    continue
            
            cards = deck.get("cards", [])
            for card in cards:
                tags = card.get("tags", [])
                for tag in tags:
                    if tag in ["Contrast Connectors", "Cause & Effect", "Time Connectors", "Strategic Verbs"]:
                        print(f"Found '{tag}' on card: {card.get('wordTarget')} ({filename})")
                        functional_tags_count += 1
                        
    if functional_tags_count == 0:
        print("Warning: No cards found with Functional Language tags.")
    else:
        print(f"Success: Found {functional_tags_count} cards with Functional Language tags.")

if __name__ == "__main__":
    if verify_tag_taxonomy():
        verify_decks()
