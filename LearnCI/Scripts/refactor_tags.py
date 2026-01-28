import json
import os

JSON_PATH = "/Users/alanglass/Documents/dev/_AI/Learn Comp Input/LearnCI/LearnCI/Resources/Data/spanish_others/refold_es1k.json"

# Semantic Categories Mapping
CATEGORIES = {
    "Verbs": {
        "heuristics": [lambda w, n: n.lower().startswith("to ")],
        "words": ["ser", "estar", "haber", "tener", "hacer", "poder", "decir", "ir", "ver", "dar", "saber", "querer", "llegar", "pasar", "deber", "poner", "parecer", "quedar", "creer", "hablar", "llevar", "dejarse", "seguir", "encontrar", "llamar", "venir", "pensar", "salir", "volver", "tomar", "conocer", "vivir", "sentir", "tratar", "mirar", "contar", "empezar", "esperar", "buscar", "existir", "entrar", "trabajar", "escribir", "perder", "producir", "ocurrir", "entender", "pedir", "recibir", "recordar", "terminar", "permitir", "aparecer", "conseguir", "comenzar", "servir", "sacar", "necesitar", "mantener", "resultar", "leer", "caer", "cambiar", "presentar", "crear", "abrir", "considerar", "oír", "acabar", "convertir", "ganar", "formar", "traer", "asistir", "morir", "viajar"]
    },
    "People": {
        "words": ["hombre", "mujer", "niño", "niña", "niños", "persona", "personas", "gente", "amigo", "amiga", "familia", "padre", "madre", "hijo", "hija", "hermano", "hermana", "tío", "tía", "abuelo", "abuela", "esposo", "esposa", "marido", "chico", "chica", "señor", "señora", "grupo", "humano", "médico", "doctor", "policía", "estudiante", "profesor", "maestro", "jefe", "rey", "reina", "presidente", "pueblo", "vecino", "víctima", "actor", "paciente"]
    },
    "Time": {
        "words": ["tiempo", "año", "día", "mes", "semana", "hora", "minuto", "segundo", "noche", "tarde", "mañana", "ayer", "hoy", "momento", "vez", "siempre", "nunca", "jamás", "ahora", "entonces", "luego", "antes", "después", "durante", "mientras", "temprano", "pronto", "época", "siglo", "fecha", "enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo", "fin", "principio"]
    },
    "Body": {
        "words": ["cuerpo", "mano", "pie", "cabeza", "ojo", "cara", "boca", "brazo", "pierna", "dedo", "espalda", "corazón", "sangre", "pelo", "cabello", "piel", "hueso", "cuello", "labio", "diente", "nariz", "oreja", "estómago", "pecho", "hombro", "dolor", "salud", "enfermedad", "fuerza", "mente", "alma", "sentimiento", "voz", "mirada"]
    },
    "Food": {
        "words": ["comida", "agua", "café", "té", "leche", "vino", "cerveza", "pan", "carne", "pollo", "pescado", "huevo", "queso", "fruta", "manzana", "naranja", "plátano", "verdura", "arroz", "azúcar", "sal", "aceite", "desayuno", "almuerzo", "cena", "restaurante", "hambre", "sed", "sabor", "cocina", "mesa", "copa", "vaso", "plato", "comer", "beber"]
    },
    "Nature": {
        "words": ["mundo", "tierra", "sol", "luna", "estrella", "cielo", "mar", "río", "lago", "agua", "fuego", "aire", "viento", "lluvia", "nieve", "luz", "oscuridad", "día", "noche", "montaña", "bosque", "campo", "playa", "piedra", "árbol", "flor", "planta", "animal", "perro", "gato", "caballo", "pájaro", "pez", "naturaleza", "vida", "muerte", "frío", "calor", "clima"]
    },
    "Places": {
        "words": ["lugar", "sitio", "parte", "zona", "país", "nación", "ciudad", "pueblo", "calle", "camino", "carretera", "casa", "hogar", "escuela", "colegio", "universidad", "oficina", "trabajo", "tienda", "mercado", "hospital", "edificio", "habitación", "cuarto", "sala", "cocina", "baño", "suelo", "pared", "puerta", "ventana", "parque", "jardín", "espacio", "centro", "norte", "sur", "este", "oeste"]
    },
    "Adjectives": {
         "words": ["bueno", "malo", "grande", "pequeño", "alto", "bajo", "largo", "corto", "nuevo", "viejo", "joven", "mayor", "bonito", "hermoso", "feo", "fuerte", "débil", "rico", "pobre", "feliz", "triste", "difícil", "fácil", "posible", "imposible", "importante", "necesario", "cierto", "verdadero", "falso", "libre", "ocupado", "lleno", "vacío", "caliente", "frío", "dulce", "rápido", "lento", "duro", "suave", "claro", "oscuro", "blanco", "negro", "rojo", "azul", "verde", "amarillo", "gris", "único", "raro", "extraño", "mismo", "otro", "todo", "ninguno", "poco", "mucho", "bastante", "demasiado", "mejor", "peor", "propio", "ajeno"]
    },
    "Grammar": {
        "words": ["el", "la", "los", "las", "un", "una", "unos", "unas", "y", "o", "pero", "porque", "si", "que", "como", "cuando", "donde", "quien", "cual", "cuyo", "para", "por", "en", "a", "de", "con", "sin", "desde", "hasta", "hacia", "sobre", "bajo", "entre", "contra", "yo", "tú", "él", "ella", "nosotros", "vosotros", "ellos", "mí", "ti", "sí", "me", "te", "le", "lo", "la", "nos", "os", "les", "se", "mi", "tu", "su", "nuestro", "vuestro", "este", "ese", "aquel", "esto", "eso", "aquello", "aquí", "allí", "allá", "acá", "ya", "todavía", "aún", "casi", "muy", "más", "menos", "tan", "así", "bien", "mal", "no", "sí", "quizás", "tal vez"]
    }
}

def get_tags(word_target, word_native):
    found_tags = []
    target = word_target.lower().strip()
    native = word_native.lower().strip()
    
    for category, rules in CATEGORIES.items():
        # Check dictionary match
        if target in rules.get("words", []):
            found_tags.append(category)
            continue
            
        # Check heuristics
        heuristics = rules.get("heuristics", [])
        for heuristic in heuristics:
            if heuristic(target, native):
                found_tags.append(category)
                break
                
    return found_tags

def process_file():
    if not os.path.exists(JSON_PATH):
        print(f"File not found: {JSON_PATH}")
        return

    try:
        with open(JSON_PATH, 'r', encoding='utf-8') as f:
            data = json.load(f)
            
        print(f"Loaded {len(data['cards'])} cards.")
        
        modified_count = 0
        tag_counts = {}
        
        for card in data['cards']:
            original_tags = card.get('tags', [])
            # Filter out Rank tags
            new_tags = [t for t in original_tags if not t.startswith("Rank")]
            
            # Determine new semantic tags
            semantic_tags = get_tags(card.get('wordTarget', ''), card.get('wordNative', ''))
            
            # Add unique new tags
            for tag in semantic_tags:
                if tag not in new_tags:
                    new_tags.append(tag)
                    tag_counts[tag] = tag_counts.get(tag, 0) + 1
            
            # Check if tags actually changed
            if set(original_tags) != set(new_tags):
                card['tags'] = new_tags
                modified_count += 1
                
        with open(JSON_PATH, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=4, ensure_ascii=False)
            
        print(f"Successfully modified {modified_count} cards.")
        print("New Tag Distribution:")
        for tag, count in sorted(tag_counts.items(), key=lambda item: item[1], reverse=True):
            print(f"  {tag}: {count}")
            
    except Exception as e:
        print(f"Error processing file: {e}")

if __name__ == "__main__":
    process_file()
