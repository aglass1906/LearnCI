
import json
import os
import re

TAXONOMY_FILE = "LearnCI/Resources/Data/tag_taxonomy.json"

def load_rules_from_taxonomy():
    """Loads tag rules from the taxonomy JSON file."""
    try:
        with open(TAXONOMY_FILE, 'r') as f:
            taxonomy = json.load(f)
    except FileNotFoundError:
        print(f"Error: Taxonomy file not found at {TAXONOMY_FILE}")
        return {}

    rules = {}
    
    # Iterate through Domains (Grammar Topics, Basic Topics, etc.)
    for domain_name, domain_data in taxonomy.items():
        if "tags" not in domain_data:
            continue
            
        # Iterate through Tags within Domain
        for tag, tag_data in domain_data["tags"].items():
            if "words" in tag_data:
                # Add to flat rules dictionary
                if tag in rules:
                    # Merge if duplicate tag names exist across domains (unlikely but safe)
                    rules[tag].extend(tag_data["words"])
                else:
                    rules[tag] = tag_data["words"]
                    
    return rules

def enrich_file(filepath, tag_rules):
    try:
        with open(filepath, 'r') as f:
            data = json.load(f)
    except Exception as e:
        print(f"Skipping {filepath}: {e}")
        return 0

    if 'cards' not in data:
        return 0
        
    updated_count = 0
    # print(f"Processing {filepath}...")
    
    for card in data.get('cards', []):
        word_native = card.get('wordNative', '').lower()
        
        current_tags = set(card.get('tags', []))
        original_tags = current_tags.copy()
        
        # Apply Logic using loaded rules
        for tag, keywords in tag_rules.items():
            for keyword in keywords:
                # Optimized Matching Logic
                
                # 1. Special "to " verb heuristic
                if tag == "Verbs" and keyword == "to ":
                    if word_native.startswith("to ") or ", to " in word_native or "; to " in word_native:
                         current_tags.add(tag)
                         break
                
                # 2. Punctuation/Symbol specific keywords (like "(adj)") - Match anywhere simply
                if not keyword.isalnum() and len(keyword) > 1 and " " not in keyword: # e.g. "(adj)", "adj."
                    if keyword in word_native:
                         current_tags.add(tag)
                         break
                
                # 3. Standard Word Boundary search
                # Use regex with boundary only if keyword is alphanumeric
                if re.search(r'\b' + re.escape(keyword) + r'\b', word_native):
                     current_tags.add(tag)
                     break
                     
        # Specific override for known overlap: Colors
        if "Colors" in current_tags:
            current_tags.add("Adjectives")
            
        if current_tags != original_tags:
            card['tags'] = sorted(list(current_tags))
            updated_count += 1

    if updated_count > 0:
        with open(filepath, 'w') as f:
            json.dump(data, f, indent=4, ensure_ascii=False)
        print(f"  - Updated {updated_count} cards in {os.path.basename(filepath)}")
    
    return updated_count

def enrich_tags():
    print(f"Loading rules from {TAXONOMY_FILE}...")
    tag_rules = load_rules_from_taxonomy()
    
    if not tag_rules:
        print("No rules loaded. Exiting.")
        return

    print(f"Loaded {len(tag_rules)} categories.")
    
    root_dir = "LearnCI/Resources/Data"
    total_updated = 0
    
    for root, dirs, files in os.walk(root_dir):
        for file in files:
            if file.endswith(".json") and file != "tag_taxonomy.json" and file != "lang_taxonomy.json":
                path = os.path.join(root, file)
                total_updated += enrich_file(path, tag_rules)

    print(f"Done. Total cards enriched across all files: {total_updated}")


if __name__ == "__main__":
    enrich_tags()
