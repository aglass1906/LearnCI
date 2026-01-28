
import json
import os

SOURCE_FILE = 'enrich_tags.py'
OUTPUT_FILE = 'LearnCI/Resources/Data/tag_taxonomy.json'

DOMAIN_DESCRIPTIONS = {
    "Grammar Topics": "Core grammatical concepts and structural words necessary for sentence construction.",
    "Basic Topics": "Fundamental vocabulary categories covering everyday objects, people, and nature.",
    "Time & Calendar": "Expressions related to time, dates, frequency, and scheduling.",
    "Spatial & Direction": "Words used to describe location, relative position, movement, and orientation.",
    "Activity": "Actions, daily routines, sports, and common activities.",
    "New Categories": "Advanced categories including professions, abstract concepts, and specific objects."
}

TAG_DESCRIPTIONS = {
    "Verbs": "Action words and states of being.",
    "Adjectives": "Descriptive words modifying nouns.",
    "Adverbs": "Words modifying verbs to describe how, when, or where.",
    "Prepositions": "Words linking nouns to other parts of the sentence, often indicating relationship.",
    "Conjunctions": "Connecting words that link clauses or sentences.",
    "Pronouns": "Words that substitute for nouns.",
    "Food": "Ingredients, meals, drinks, and dining vocabulary.",
    "Family": "Family members and kinship terms.",
    "People": "General terms for people, roles, and relationships.",
    "Body": "Parts of the body and health-related terms.",
    "Nature": "Natural world, weather, animals, and environment.",
    "Places": "Buildings, city components, and locations.",
    "Clothing": "Apparel, accessories, and wearable items.",
    "Colors": "Names of colors and visual attributes.",
    "Numbers": "Cardinal and ordinal numbers.",
    "Animals": "Creatures and living beings.",
    "Time": "General time references and units of time.",
    "Days": "Specific days of the week.",
    "Months": "Months of the year.",
    "Time of Day": "Specific periods like morning, evening, or night.",
    "Position": "Relative locations (above, below, etc.).",
    "Directions": "Navigation and directional terms.",
    "Daily Routine": "Habitual actions performed throughout the day.",
    "Sports": "Games, athletics, and recreational activities.",
    "Concepts": "Abstract ideas, emotions, and intellectual terms.",
    "Objects": "Physical inanimate items and tools.",
    "Jobs": "Professions, occupations, and roles.",
    "Materials": "Substances like wood, metal, gold, etc."
}

def export_taxonomy():
    print(f"Reading {SOURCE_FILE}...")
    with open(SOURCE_FILE, 'r') as f:
        lines = f.readlines()

    taxonomy = {}
    current_domain = "General" 
    
    in_tag_rules = False
    
    for line in lines:
        line = line.strip()
        
        if line.startswith("TAG_RULES = {"):
            in_tag_rules = True
            continue
        
        if line.startswith("}") and in_tag_rules:
            in_tag_rules = False
            continue
            
        if not in_tag_rules:
            continue
            
        # Parse Domain from Comment
        if line.startswith("#"):
            comment = line.lstrip("# ").strip()
            if comment and not comment.startswith("Conf"): # Avoid Configuration comment
                current_domain = comment
            if current_domain not in taxonomy:
                taxonomy[current_domain] = {
                    "description": DOMAIN_DESCRIPTIONS.get(current_domain, "Category group."),
                    "tags": {}
                }
            continue
            
        # Parse Tag Entry
        if line.startswith('"'):
            try:
                parts = line.split(':', 1)
                tag_name = parts[0].strip().strip('"')
                
                value_part = parts[1].strip()
                end_idx = value_part.rfind(']')
                if end_idx != -1:
                    list_str = value_part[:end_idx+1]
                    keywords = eval(list_str)
                    
                    if current_domain not in taxonomy:
                        taxonomy[current_domain] = {
                            "description": DOMAIN_DESCRIPTIONS.get(current_domain, "Category group."),
                            "tags": {}
                        }
                        
                    taxonomy[current_domain]["tags"][tag_name] = {
                        "description": TAG_DESCRIPTIONS.get(tag_name, f"Words related to {tag_name}."),
                        "words": keywords
                    }
            except Exception as e:
                pass

    os.makedirs(os.path.dirname(OUTPUT_FILE), exist_ok=True)
    
    with open(OUTPUT_FILE, 'w') as f:
        json.dump(taxonomy, f, indent=4)
        
    print(f"Successfully exported rich taxonomy to {OUTPUT_FILE}")

if __name__ == "__main__":
    export_taxonomy()
